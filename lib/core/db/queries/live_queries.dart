// Extra reads for the Live, Favorites and Search screens.
//
// They live in their own file (an extension on [AppDatabase]) so the DAOs
// stay untouched by feature work.
import 'package:drift/drift.dart';

import '../../../sources/models.dart';
import '../app_db.dart';
import '../daos/query_utils.dart';

/// Committed-generation filter for a catalog table aliased `t`.
const _committed =
    't.first_gen <= (SELECT generation FROM sources WHERE id = ?1)';

extension LiveQueries on AppDatabase {
  /// Index of [key] in `CatalogDao.allChannelsPage` order (number with
  /// unnumbered channels last, then normalised name, then key), or null when
  /// it is not a committed channel of [sourceId].
  Future<int?> allChannelsIndexOf(int sourceId, String key) async {
    final row = await customSelect(
      'SELECT (SELECT COUNT(*) FROM channels c WHERE c.source_id = ?1 '
      'AND c.first_gen <= (SELECT generation FROM sources WHERE id = ?1) '
      'AND (CASE '
      'WHEN t.num IS NULL THEN c.num IS NOT NULL '
      'OR (c.name_norm, c."key") < (t.name_norm, t."key") '
      'ELSE c.num < t.num OR (c.num = t.num '
      'AND (c.name_norm, c."key") < (t.name_norm, t."key")) END)) AS idx '
      'FROM channels t WHERE t.source_id = ?1 AND t."key" = ?2 '
      'AND $_committed',
      variables: [Variable.withInt(sourceId), Variable.withString(key)],
      readsFrom: {channels, sources},
    ).getSingleOrNull();
    return row?.read<int>('idx');
  }

  /// Keys of the committed channels numbered [number], in the order of
  /// `CatalogDao.channelByNumber` (normalised name, then key).
  Future<List<String>> liveKeysWithNumber(
    int sourceId,
    int number, {
    int limit = 20,
  }) async {
    final rows = await customSelect(
      'SELECT t."key" AS k FROM channels t WHERE t.source_id = ?1 '
      'AND t.num = ?2 AND $_committed ORDER BY t.name_norm, t."key" LIMIT ?3',
      variables: [
        Variable.withInt(sourceId),
        Variable.withInt(number),
        Variable.withInt(limit),
      ],
      readsFrom: {channels, sources},
    ).get();
    return [for (final r in rows) r.read<String>('k')];
  }

  /// Saved progress of [keys] (movies or episodes), by key, in one query per
  /// 900 keys.
  Future<Map<String, ProgressRow>> progressForKeys(
    int sourceId,
    PlayableKind kind,
    List<String> keys,
  ) async {
    final result = <String, ProgressRow>{};
    for (final chunk in chunked(keys.toSet().toList())) {
      final rows =
          await (select(watchProgress)..where(
                (p) =>
                    p.sourceId.equals(sourceId) &
                    p.kind.equalsValue(kind) &
                    p.key.isIn(chunk),
              ))
              .get();
      for (final r in rows) {
        result[r.key] = r.toRow();
      }
    }
    return result;
  }
}
