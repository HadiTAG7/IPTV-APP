import '../../core/db/app_db.dart';
import '../../core/db/queries/live_queries.dart';
import '../../player/ui/play_request.dart';
import '../../sources/models.dart';
import 'live_models.dart';

/// Where a channel list reads its rows: random access by position, so lists
/// page from the database instead of loading every channel.
abstract class ChannelListSource {
  ChannelListSource(this.db, this.sourceId);

  final AppDatabase db;
  final int sourceId;

  /// The list this source reads.
  LiveList get list;

  /// Number of positions. Call before [page]; keyed sources load their keys
  /// here.
  Future<int> count();

  /// Entries at positions `[offset, offset + limit)`.
  Future<List<LiveEntry>> page(int offset, int limit);

  /// Position of the channel [key], or null when the list lacks it.
  Future<int?> indexOfKey(String key);

  /// Position of the first channel numbered [number], or null.
  Future<int?> indexOfNumber(int number) async {
    int? best;
    for (final key in await db.liveKeysWithNumber(sourceId, number)) {
      final i = await indexOfKey(key);
      if (i != null && (best == null || i < best)) best = i;
    }
    return best;
  }

  /// What the player gets for [channel], including the zapping list.
  Future<PlayRequest> requestFor(ChannelRow channel);
}

/// The source for [list] of [sourceId].
ChannelListSource channelSourceFor(
  AppDatabase db,
  int sourceId,
  LiveList list,
) => switch (list.kind) {
  LiveListKind.category => CategoryChannelsSource(
    db,
    sourceId,
    list.categoryKey!,
  ),
  LiveListKind.all => AllChannelsSource(db, sourceId),
  LiveListKind.favorites => FavoriteChannelsSource(db, sourceId),
  LiveListKind.channelList => ListChannelsSource(db, sourceId, list.listId!),
  LiveListKind.recent => RecentChannelsSource(db, sourceId),
};

/// A provider category, paged by position from `category_items`. Zapping
/// walks the category.
class CategoryChannelsSource extends ChannelListSource {
  CategoryChannelsSource(super.db, super.sourceId, this.categoryKey);

  final String categoryKey;

  @override
  LiveList get list => LiveList.category(categoryKey);

  @override
  Future<int> count() =>
      db.catalogDao.itemCount(sourceId, ContentKind.live, categoryKey);

  @override
  Future<List<LiveEntry>> page(int offset, int limit) async => [
    for (final row in await db.catalogDao.channelsPage(
      sourceId,
      categoryKey,
      offset,
      limit,
    ))
      LiveEntry(row.key, row),
  ];

  @override
  Future<int?> indexOfKey(String key) => db.catalogDao.positionInCategory(
    sourceId,
    ContentKind.live,
    categoryKey,
    key,
  );

  @override
  Future<PlayRequest> requestFor(ChannelRow channel) async => PlayRequest(
    sourceId: sourceId,
    item: channel.toPlayable(),
    categoryKey: categoryKey,
  );
}

/// Every channel of the source by number, then name. Zapping walks all
/// channels (no category key).
class AllChannelsSource extends ChannelListSource {
  AllChannelsSource(super.db, super.sourceId);

  @override
  LiveList get list => const LiveList.all();

  @override
  Future<int> count() => db.catalogDao.totalCount(sourceId, ContentKind.live);

  @override
  Future<List<LiveEntry>> page(int offset, int limit) async => [
    for (final row in await db.catalogDao.allChannelsPage(
      sourceId,
      offset,
      limit,
    ))
      LiveEntry(row.key, row),
  ];

  @override
  Future<int?> indexOfKey(String key) => db.allChannelsIndexOf(sourceId, key);

  @override
  Future<PlayRequest> requestFor(ChannelRow channel) async =>
      PlayRequest(sourceId: sourceId, item: channel.toPlayable());
}

/// Favourite channels in favourite order. Channels gone from the catalog
/// stay listed as unavailable. Zapping walks the available favourites.
class FavoriteChannelsSource extends ChannelListSource {
  FavoriteChannelsSource(super.db, super.sourceId);

  List<String> _keys = const [];

  @override
  LiveList get list => const LiveList.favorites();

  @override
  Future<int> count() async {
    _keys = await db.favoritesDao.favoriteKeys(sourceId, ContentKind.live);
    return _keys.length;
  }

  @override
  Future<List<LiveEntry>> page(int offset, int limit) async => [
    for (final f in await db.favoritesDao.favoriteChannelsPage(
      sourceId,
      offset: offset,
      limit: limit,
    ))
      LiveEntry(f.key, f.item),
  ];

  @override
  Future<int?> indexOfKey(String key) async {
    final i = _keys.indexOf(key);
    return i < 0 ? null : i;
  }

  @override
  Future<PlayRequest> requestFor(ChannelRow channel) async {
    final available = await db.catalogDao.channelsByKeys(sourceId, _keys);
    return PlayRequest(
      sourceId: sourceId,
      item: channel.toPlayable(),
      zapKeys: [for (final c in available) c.key],
    );
  }
}

/// One of the user's channel lists, in list order. Channels gone from the
/// catalog stay listed as unavailable. Zapping walks the available channels
/// of the list.
class ListChannelsSource extends ChannelListSource {
  ListChannelsSource(super.db, super.sourceId, this.listId);

  final int listId;
  List<String> _keys = const [];

  /// The list's channel keys as of the last [count].
  List<String> get keys => _keys;

  @override
  LiveList get list => LiveList.channelList(listId);

  @override
  Future<int> count() async {
    _keys = await db.channelListsDao.channelKeys(listId);
    return _keys.length;
  }

  @override
  Future<List<LiveEntry>> page(int offset, int limit) async => [
    for (final item in await db.channelListsDao.channelsPage(
      listId,
      offset: offset,
      limit: limit,
    ))
      LiveEntry(item.key, item.item),
  ];

  @override
  Future<int?> indexOfKey(String key) async {
    final i = _keys.indexOf(key);
    return i < 0 ? null : i;
  }

  @override
  Future<PlayRequest> requestFor(ChannelRow channel) async {
    final available = await db.catalogDao.channelsByKeys(sourceId, _keys);
    return PlayRequest(
      sourceId: sourceId,
      item: channel.toPlayable(),
      zapKeys: [for (final c in available) c.key],
    );
  }
}

/// Recently played channels, newest first (at most `RecentDao.maxEntries`,
/// so they are read in one go). Zapping walks the recent list.
class RecentChannelsSource extends ChannelListSource {
  RecentChannelsSource(super.db, super.sourceId);

  List<ChannelRow> _rows = const [];

  @override
  LiveList get list => const LiveList.recent();

  @override
  Future<int> count() async {
    _rows = await db.recentDao.recentChannels(sourceId);
    return _rows.length;
  }

  @override
  Future<List<LiveEntry>> page(int offset, int limit) async {
    if (offset >= _rows.length || limit <= 0) return const [];
    final end = offset + limit > _rows.length ? _rows.length : offset + limit;
    return [for (final r in _rows.sublist(offset, end)) LiveEntry(r.key, r)];
  }

  @override
  Future<int?> indexOfKey(String key) async {
    final i = _rows.indexWhere((r) => r.key == key);
    return i < 0 ? null : i;
  }

  @override
  Future<PlayRequest> requestFor(ChannelRow channel) async => PlayRequest(
    sourceId: sourceId,
    item: channel.toPlayable(),
    zapKeys: [for (final r in _rows) r.key],
  );
}

/// A fixed, already loaded list of channels (search results). Zapping walks
/// the list.
class FixedChannelsSource extends ChannelListSource {
  FixedChannelsSource(super.db, super.sourceId, this.rows);

  final List<ChannelRow> rows;

  @override
  LiveList get list => const LiveList.all();

  @override
  Future<int> count() async => rows.length;

  @override
  Future<List<LiveEntry>> page(int offset, int limit) async {
    if (offset >= rows.length || limit <= 0) return const [];
    final end = offset + limit > rows.length ? rows.length : offset + limit;
    return [for (final r in rows.sublist(offset, end)) LiveEntry(r.key, r)];
  }

  @override
  Future<int?> indexOfKey(String key) async {
    final i = rows.indexWhere((r) => r.key == key);
    return i < 0 ? null : i;
  }

  @override
  Future<PlayRequest> requestFor(ChannelRow channel) async => PlayRequest(
    sourceId: sourceId,
    item: channel.toPlayable(),
    zapKeys: [for (final r in rows) r.key],
  );
}
