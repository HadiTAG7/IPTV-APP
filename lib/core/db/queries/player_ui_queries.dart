// Reads used by the fullscreen player (zapping lists). Additive: lives
// outside the DAO files so slices do not edit the same code.
//
// Zapping walks a category or the whole source without loading it: the
// player reads windows of entries by position, the position of one channel
// and the first channel with a number, each as its own small query.
import 'package:drift/drift.dart';

import '../../../sources/models.dart';
import '../app_db.dart';
import '../daos/query_utils.dart';

/// One channel of a zapping list: its key and number (null when the
/// playlist has none). Records compare by value, so two entries for the
/// same channel are equal.
typedef ZapEntry = ({String key, int? num});

/// Size of a zapping list and how many of its channels have a number.
typedef ZapListCount = ({int total, int numbered});

const _committedGen = '(SELECT generation FROM sources WHERE id = ?1)';

extension PlayerUiQueries on AppDatabase {
  // -------------------------------------------------------------------
  // A live category, in list order (`category_items.position`).

  /// Channels in a live category, and how many of them are numbered.
  Future<ZapListCount> zapCountInCategory(
    int sourceId,
    String categoryKey,
  ) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS t, COUNT(c.num) AS n FROM category_items ci '
      'LEFT JOIN channels c ON c.source_id = ci.source_id '
      'AND c."key" = ci.item_key '
      'WHERE ci.source_id = ?1 AND ci.generation = $_committedGen '
      'AND ci.kind = ?2 AND ci.category_key = ?3',
      variables: [
        Variable.withInt(sourceId),
        Variable.withString(ContentKind.live.name),
        Variable.withString(categoryKey),
      ],
      readsFrom: {categoryItems, channels, sources},
    ).getSingle();
    return (total: row.read<int>('t'), numbered: row.read<int>('n'));
  }

  /// [limit] entries of a live category from list index [offset].
  Future<List<ZapEntry>> zapRangeInCategory(
    int sourceId,
    String categoryKey,
    int offset,
    int limit,
  ) async {
    if (limit <= 0) return const [];
    final rows = await customSelect(
      'SELECT ci.item_key AS k, c.num AS n FROM category_items ci '
      'LEFT JOIN channels c ON c.source_id = ci.source_id '
      'AND c."key" = ci.item_key '
      'WHERE ci.source_id = ?1 AND ci.generation = $_committedGen '
      'AND ci.kind = ?2 AND ci.category_key = ?3 '
      'ORDER BY ci.position LIMIT ?4 OFFSET ?5',
      variables: [
        Variable.withInt(sourceId),
        Variable.withString(ContentKind.live.name),
        Variable.withString(categoryKey),
        Variable.withInt(limit),
        Variable.withInt(offset < 0 ? 0 : offset),
      ],
      readsFrom: {categoryItems, channels, sources},
    ).get();
    return [for (final r in rows) _entry(r)];
  }

  /// List index of [key] in a live category, or null when it is not in it.
  Future<int?> zapIndexInCategory(
    int sourceId,
    String categoryKey,
    String key,
  ) async {
    final row = await customSelect(
      'SELECT MIN(position) AS p FROM category_items WHERE source_id = ?1 '
      'AND generation = $_committedGen AND kind = ?2 AND category_key = ?3 '
      'AND item_key = ?4',
      variables: [
        Variable.withInt(sourceId),
        Variable.withString(ContentKind.live.name),
        Variable.withString(categoryKey),
        Variable.withString(key),
      ],
      readsFrom: {categoryItems, sources},
    ).getSingle();
    final position = row.read<int?>('p');
    if (position == null) return null;
    return _categoryIndexOf(sourceId, categoryKey, position);
  }

  /// The first channel (in list order) numbered [number] in a live
  /// category, with its list index.
  Future<(ZapEntry, int)?> zapNumberInCategory(
    int sourceId,
    String categoryKey,
    int number,
  ) async {
    final row = await customSelect(
      'SELECT ci.position AS p, ci.item_key AS k, c.num AS n '
      'FROM category_items ci JOIN channels c ON c.source_id = ci.source_id '
      'AND c."key" = ci.item_key '
      'WHERE ci.source_id = ?1 AND ci.generation = $_committedGen '
      'AND ci.kind = ?2 AND ci.category_key = ?3 AND c.num = ?4 '
      'ORDER BY ci.position LIMIT 1',
      variables: [
        Variable.withInt(sourceId),
        Variable.withString(ContentKind.live.name),
        Variable.withString(categoryKey),
        Variable.withInt(number),
      ],
      readsFrom: {categoryItems, channels, sources},
    ).getSingleOrNull();
    if (row == null) return null;
    final index = await _categoryIndexOf(
      sourceId,
      categoryKey,
      row.read<int>('p'),
    );
    return (_entry(row), index);
  }

  Future<int> _categoryIndexOf(
    int sourceId,
    String categoryKey,
    int position,
  ) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS i FROM category_items WHERE source_id = ?1 '
      'AND generation = $_committedGen AND kind = ?2 AND category_key = ?3 '
      'AND position < ?4',
      variables: [
        Variable.withInt(sourceId),
        Variable.withString(ContentKind.live.name),
        Variable.withString(categoryKey),
        Variable.withInt(position),
      ],
      readsFrom: {categoryItems, sources},
    ).getSingle();
    return row.read<int>('i');
  }

  // -------------------------------------------------------------------
  // Every committed channel of a source, in the "All channels" order:
  // numbered channels by number, then unnumbered ones; ties by name, key.
  // Each half is read on its own so the `channels_num` index serves the
  // order (NULLS LAST would need a sort of the whole table).

  /// Committed channels of a source, and how many of them are numbered.
  Future<ZapListCount> zapCountAll(int sourceId) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS t, COUNT(num) AS n FROM channels '
      'WHERE source_id = ?1 AND first_gen <= $_committedGen',
      variables: [Variable.withInt(sourceId)],
      readsFrom: {channels, sources},
    ).getSingle();
    return (total: row.read<int>('t'), numbered: row.read<int>('n'));
  }

  /// [limit] entries of all channels from list index [offset]; [numbered]
  /// is [ZapListCount.numbered] of [zapCountAll].
  Future<List<ZapEntry>> zapRangeAll(
    int sourceId,
    int offset,
    int limit, {
    required int numbered,
  }) async {
    if (limit <= 0) return const [];
    final from = offset < 0 ? 0 : offset;
    final result = <ZapEntry>[];
    if (from < numbered) {
      result.addAll(await _allPage(sourceId, true, from, limit));
    }
    final left = limit - result.length;
    if (left > 0) {
      final unnumberedFrom = from + result.length - numbered;
      result.addAll(
        await _allPage(
          sourceId,
          false,
          unnumberedFrom < 0 ? 0 : unnumberedFrom,
          left,
        ),
      );
    }
    return result;
  }

  Future<List<ZapEntry>> _allPage(
    int sourceId,
    bool numbered,
    int offset,
    int limit,
  ) async {
    final rows = await customSelect(
      'SELECT "key" AS k, num AS n FROM channels WHERE source_id = ?1 '
      'AND num IS ${numbered ? 'NOT NULL' : 'NULL'} '
      'AND first_gen <= $_committedGen '
      'ORDER BY ${numbered ? 'num, ' : ''}name_norm, "key" '
      'LIMIT ?2 OFFSET ?3',
      variables: [
        Variable.withInt(sourceId),
        Variable.withInt(limit),
        Variable.withInt(offset),
      ],
      readsFrom: {channels, sources},
    ).get();
    return [for (final r in rows) _entry(r)];
  }

  /// List index of [key] among all channels, or null when it is not a
  /// committed channel.
  Future<int?> zapIndexAll(int sourceId, String key) async {
    final row = await customSelect(
      'SELECT "key" AS k, num AS n, name_norm AS nn FROM channels '
      'WHERE source_id = ?1 AND "key" = ?2 AND first_gen <= $_committedGen',
      variables: [Variable.withInt(sourceId), Variable.withString(key)],
      readsFrom: {channels, sources},
    ).getSingleOrNull();
    if (row == null) return null;
    return _allIndexOf(sourceId, row);
  }

  /// The first channel numbered [number] (by name, then key) with its index
  /// among all channels.
  Future<(ZapEntry, int)?> zapNumberAll(int sourceId, int number) async {
    final row = await customSelect(
      'SELECT "key" AS k, num AS n, name_norm AS nn FROM channels '
      'WHERE source_id = ?1 AND num = ?2 AND first_gen <= $_committedGen '
      'ORDER BY name_norm, "key" LIMIT 1',
      variables: [Variable.withInt(sourceId), Variable.withInt(number)],
      readsFrom: {channels, sources},
    ).getSingleOrNull();
    if (row == null) return null;
    return (_entry(row), await _allIndexOf(sourceId, row));
  }

  /// Channels sorting before [row] (which has `k`, `n` and `nn`).
  Future<int> _allIndexOf(int sourceId, QueryRow row) async {
    final num = row.read<int?>('n');
    final tie = '(name_norm < ?3 OR (name_norm = ?3 AND "key" < ?4))';
    final count = await customSelect(
      'SELECT COUNT(*) AS i FROM channels WHERE source_id = ?1 '
      'AND first_gen <= $_committedGen AND '
      '${num == null ? '(num IS NOT NULL OR $tie)' : '(num < ?2 OR (num = ?2 AND $tie))'}',
      variables: [
        Variable.withInt(sourceId),
        Variable.withInt(num ?? 0),
        Variable.withString(row.read<String>('nn')),
        Variable.withString(row.read<String>('k')),
      ],
      readsFrom: {channels, sources},
    ).getSingle();
    return count.read<int>('i');
  }

  // -------------------------------------------------------------------
  // An explicit list (favourites, recent), held by the caller anyway.

  /// Entries for [keys] in the same order; keys missing from the catalog are
  /// skipped.
  Future<List<ZapEntry>> zapEntriesForKeys(
    int sourceId,
    List<String> keys,
  ) async {
    final found = <String, int?>{};
    for (final chunk in chunked(keys.toSet().toList())) {
      final rows = await customSelect(
        'SELECT "key" AS k, num AS n FROM channels WHERE source_id = ?1 '
        'AND "key" IN (${sqlParams(chunk.length, 2)})',
        variables: [
          Variable.withInt(sourceId),
          for (final k in chunk) Variable.withString(k),
        ],
        readsFrom: {channels},
      ).get();
      for (final r in rows) {
        found[r.read<String>('k')] = r.read<int?>('n');
      }
    }
    final seen = <String>{};
    return [
      for (final k in keys)
        if (found.containsKey(k) && seen.add(k)) (key: k, num: found[k]),
    ];
  }
}

ZapEntry _entry(QueryRow r) =>
    (key: r.read<String>('k'), num: r.read<int?>('n'));
