// Reads used by the fullscreen player (zapping lists). Additive: lives
// outside the DAO files so slices do not edit the same code.
import 'package:drift/drift.dart';

import '../../../sources/models.dart';
import '../app_db.dart';
import '../daos/query_utils.dart';

/// One channel of a zapping list: its key and number (null when the
/// playlist has none). Records compare by value, so two entries for the
/// same channel are equal.
typedef ZapEntry = ({String key, int? num});

extension PlayerUiQueries on AppDatabase {
  /// Channels of a live category in list order (keys and numbers only, so
  /// even a 50k-channel category stays small in memory).
  Future<List<ZapEntry>> zapEntriesInCategory(
    int sourceId,
    String categoryKey,
  ) async {
    final rows = await customSelect(
      'SELECT ci.item_key AS k, c.num AS n FROM category_items ci '
      'JOIN channels c ON c.source_id = ci.source_id '
      'AND c."key" = ci.item_key '
      'WHERE ci.source_id = ?1 '
      'AND ci.generation = (SELECT generation FROM sources WHERE id = ?1) '
      'AND ci.kind = ?2 AND ci.category_key = ?3 ORDER BY ci.position',
      variables: [
        Variable.withInt(sourceId),
        Variable.withString(ContentKind.live.name),
        Variable.withString(categoryKey),
      ],
      readsFrom: {categoryItems, channels, sources},
    ).get();
    return [for (final r in rows) _entry(r)];
  }

  /// Every committed channel of a source, in the "All channels" order
  /// (number, unnumbered last, then name).
  Future<List<ZapEntry>> zapEntriesAll(int sourceId) async {
    final rows = await customSelect(
      'SELECT "key" AS k, num AS n FROM channels WHERE source_id = ?1 '
      'AND first_gen <= (SELECT generation FROM sources WHERE id = ?1) '
      'ORDER BY num ASC NULLS LAST, name_norm, "key"',
      variables: [Variable.withInt(sourceId)],
      readsFrom: {channels, sources},
    ).get();
    return [for (final r in rows) _entry(r)];
  }

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
