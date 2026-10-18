import 'package:drift/drift.dart';

import '../app_db.dart';

/// Why a channel list name was refused.
enum ChannelListNameError {
  /// Nothing but white space.
  empty,

  /// Another list of the source has it (ignoring case).
  taken,
}

/// Thrown by [ChannelListsDao.createList] and [ChannelListsDao.renameList]
/// for a name they refuse.
class ChannelListNameException implements Exception {
  const ChannelListNameException(this.error);

  final ChannelListNameError error;

  @override
  String toString() => 'ChannelListNameException(${error.name})';
}

/// A channel list with the number of channels in it (unavailable ones
/// included, as the Favorites count does).
class ChannelListRow {
  const ChannelListRow({
    required this.id,
    required this.sourceId,
    required this.name,
    required this.position,
    required this.count,
  });

  final int id;
  final int sourceId;
  final String name;
  final int position;
  final int count;
}

/// One channel of a list: its stable key and its catalog row, or a null
/// [item] when the channel left the catalog.
class ChannelListItem {
  const ChannelListItem({required this.key, required this.addedAt, this.item});

  final String key;
  final DateTime addedAt;
  final ChannelRow? item;

  bool get available => item != null;
}

/// The user's own live channel lists per source, next to the favourites.
///
/// Lists are ordered by `position`; their channels too, densely from 0, and
/// keyed by stable channel keys so they survive every catalog refresh.
/// Names are trimmed and unique per source, ignoring case.
class ChannelListsDao extends DatabaseAccessor<AppDatabase> {
  ChannelListsDao(super.attachedDatabase);

  static const _listsQuery =
      'SELECT l.id AS id, l.source_id AS source_id, l.name AS name, '
      'l.position AS position, COUNT(i."key") AS n '
      'FROM channel_lists l LEFT JOIN channel_list_items i ON i.list_id = l.id '
      'WHERE l.source_id = ?1 GROUP BY l.id ORDER BY l.position, l.id';

  Selectable<ChannelListRow> _lists(int sourceId) =>
      customSelect(
        _listsQuery,
        variables: [Variable.withInt(sourceId)],
        readsFrom: {db.channelLists, db.channelListItems},
      ).map(
        (r) => ChannelListRow(
          id: r.read<int>('id'),
          sourceId: r.read<int>('source_id'),
          name: r.read<String>('name'),
          position: r.read<int>('position'),
          count: r.read<int>('n'),
        ),
      );

  /// The lists of a source in list order.
  Future<List<ChannelListRow>> lists(int sourceId) => _lists(sourceId).get();

  /// The lists of a source in list order; emits after every change to them
  /// or their channels.
  Stream<List<ChannelListRow>> watchLists(int sourceId) =>
      _lists(sourceId).watch();

  /// The list [listId], or null when it does not exist.
  Future<ChannelListRecord?> listById(int listId) => (select(
    db.channelLists,
  )..where((l) => l.id.equals(listId))).getSingleOrNull();

  /// [name] trimmed, or a [ChannelListNameException] when it is empty or
  /// another list of [sourceId] (not [exceptId]) has it.
  Future<String> _checkName(int sourceId, String name, {int? exceptId}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ChannelListNameException(ChannelListNameError.empty);
    }
    final folded = trimmed.toLowerCase();
    final others = await (select(
      db.channelLists,
    )..where((l) => l.sourceId.equals(sourceId))).get();
    if (others.any((l) => l.id != exceptId && l.name.toLowerCase() == folded)) {
      throw const ChannelListNameException(ChannelListNameError.taken);
    }
    return trimmed;
  }

  /// Creates a list at the end of the source's lists, holding [channels] in
  /// that order, and returns its id. Throws [ChannelListNameException] (and
  /// creates nothing) for an empty or taken name.
  Future<int> createList(
    int sourceId,
    String name, {
    List<String> channels = const [],
  }) => transaction(() async {
    final trimmed = await _checkName(sourceId, name);
    final max = db.channelLists.position.max();
    final last =
        await (selectOnly(db.channelLists)
              ..addColumns([max])
              ..where(db.channelLists.sourceId.equals(sourceId)))
            .map((r) => r.read(max))
            .getSingle();
    final id = await into(db.channelLists).insert(
      ChannelListsCompanion.insert(
        sourceId: sourceId,
        name: trimmed,
        position: (last ?? -1) + 1,
        createdAt: toEpochSec(db.clock.now()),
      ),
    );
    for (final key in channels) {
      await setChannel(id, key, true);
    }
    return id;
  });

  /// Renames a list. Throws [ChannelListNameException] for an empty name or
  /// one another list of its source has; a missing list is ignored.
  Future<void> renameList(int listId, String name) => transaction(() async {
    final list = await listById(listId);
    if (list == null) return;
    final trimmed = await _checkName(list.sourceId, name, exceptId: listId);
    await (update(db.channelLists)..where((l) => l.id.equals(listId))).write(
      ChannelListsCompanion(name: Value(trimmed)),
    );
  });

  /// Deletes a list and its channels (the channels themselves stay in the
  /// catalog).
  Future<void> deleteList(int listId) =>
      (delete(db.channelLists)..where((l) => l.id.equals(listId))).go();

  /// Rewrites the positions of a source's lists from the order of [ids];
  /// lists of other sources are left alone.
  Future<void> reorderLists(int sourceId, List<int> ids) => batch((b) {
    for (final (i, id) in ids.indexed) {
      b.update(
        db.channelLists,
        ChannelListsCompanion(position: Value(i)),
        where: (l) => l.id.equals(id) & l.sourceId.equals(sourceId),
      );
    }
  });

  Expression<bool> _item($ChannelListItemsTable i, int listId, String key) =>
      i.listId.equals(listId) & i.key.equals(key);

  /// Whether the channel [key] is in the list.
  Future<bool> contains(int listId, String key) async =>
      await (select(
        db.channelListItems,
      )..where((i) => _item(i, listId, key))).getSingleOrNull() !=
      null;

  /// Adds the channel [key] at the end of the list, or removes it (closing
  /// the gap). Adding twice keeps the original position; adding to a missing
  /// list does nothing.
  Future<void> setChannel(int listId, String key, bool member) => transaction(
    () async {
      if (!member) {
        final row = await (select(
          db.channelListItems,
        )..where((i) => _item(i, listId, key))).getSingleOrNull();
        if (row == null) return;
        await (delete(
          db.channelListItems,
        )..where((i) => _item(i, listId, key))).go();
        await customUpdate(
          'UPDATE channel_list_items SET position = position - 1 '
          'WHERE list_id = ?1 AND position > ?2',
          variables: [Variable.withInt(listId), Variable.withInt(row.position)],
          updates: {db.channelListItems},
        );
        return;
      }
      if (await listById(listId) == null) return;
      final max = db.channelListItems.position.max();
      final last =
          await (selectOnly(db.channelListItems)
                ..addColumns([max])
                ..where(db.channelListItems.listId.equals(listId)))
              .map((r) => r.read(max))
              .getSingle();
      await into(db.channelListItems).insert(
        ChannelListItemsCompanion.insert(
          listId: listId,
          key: key,
          position: (last ?? -1) + 1,
          addedAt: toEpochSec(db.clock.now()),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    },
  );

  /// Flips whether the channel [key] is in the list and returns the new
  /// state.
  Future<bool> toggleChannel(int listId, String key) => transaction(() async {
    final now = !await contains(listId, key);
    await setChannel(listId, key, now);
    return now;
  });

  /// Moves the channel [key] [by] places (negative: toward the top), within
  /// the list's bounds. Returns whether it moved.
  Future<bool> moveChannel(int listId, String key, int by) =>
      transaction(() async {
        final keys = await channelKeys(listId);
        final from = keys.indexOf(key);
        if (from < 0) return false;
        final to = (from + by).clamp(0, keys.length - 1);
        if (to == from) return false;
        keys
          ..removeAt(from)
          ..insert(to, key);
        await reorderChannels(listId, keys);
        return true;
      });

  /// Rewrites the list's positions from the order of [keys] (every key of
  /// the list, as [channelKeys] gives them).
  Future<void> reorderChannels(int listId, List<String> keys) => batch((b) {
    for (final (i, key) in keys.indexed) {
      b.update(
        db.channelListItems,
        ChannelListItemsCompanion(position: Value(i)),
        where: (item) => _item(item, listId, key),
      );
    }
  });

  SimpleSelectStatement<$ChannelListItemsTable, ChannelListItemRecord> _ordered(
    int listId,
  ) => select(db.channelListItems)
    ..where((i) => i.listId.equals(listId))
    ..orderBy([
      (i) => OrderingTerm.asc(i.position),
      (i) => OrderingTerm.asc(i.key),
    ]);

  /// Channel keys of the list in list order (also usable as a zapping
  /// list).
  Future<List<String>> channelKeys(int listId) async => [
    for (final r in await _ordered(listId).get()) r.key,
  ];

  /// Channel keys of the list in list order; emits after every change.
  Stream<List<String>> watchChannelKeys(int listId) =>
      _ordered(listId).watch().map((rows) => [for (final r in rows) r.key]);

  Selectable<int> _membership(int sourceId, String key) => customSelect(
    'SELECT l.id AS id FROM channel_lists l JOIN channel_list_items i '
    'ON i.list_id = l.id WHERE l.source_id = ?1 AND i."key" = ?2',
    variables: [Variable.withInt(sourceId), Variable.withString(key)],
    readsFrom: {db.channelLists, db.channelListItems},
  ).map((r) => r.read<int>('id'));

  /// Ids of the source's lists holding the channel [key].
  Future<Set<int>> listsWithChannel(int sourceId, String key) async =>
      (await _membership(sourceId, key).get()).toSet();

  /// Ids of the source's lists holding the channel [key]; emits after every
  /// change.
  Stream<Set<int>> watchListsWithChannel(int sourceId, String key) =>
      _membership(sourceId, key).watch().map((ids) => ids.toSet());

  /// Channels of the list at positions `[offset, offset + limit)`, joined
  /// to the catalog of the list's source.
  Future<List<ChannelListItem>> channelsPage(
    int listId, {
    int offset = 0,
    int limit = 200,
  }) async {
    if (limit <= 0) return const [];
    final rows = await customSelect(
      'SELECT i."key" AS item_key, i.added_at AS item_added_at, c.* '
      'FROM channel_list_items i JOIN channel_lists l ON l.id = i.list_id '
      'LEFT JOIN channels c ON c.source_id = l.source_id AND c."key" = i."key" '
      'WHERE i.list_id = ?1 ORDER BY i.position, i."key" LIMIT ?2 OFFSET ?3',
      variables: [
        Variable.withInt(listId),
        Variable.withInt(limit),
        Variable.withInt(offset < 0 ? 0 : offset),
      ],
      readsFrom: {db.channelListItems, db.channelLists, db.channels},
    ).get();
    return [
      for (final r in rows)
        ChannelListItem(
          key: r.read<String>('item_key'),
          addedAt: fromEpochSec(r.read<int>('item_added_at')),
          item: r.data['source_id'] == null
              ? null
              : db.channels.map(r.data).toRow(),
        ),
    ];
  }
}
