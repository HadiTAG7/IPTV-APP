// Extra read queries for the movie and series screens. Extensions keep the
// DAO files untouched.
import 'package:drift/drift.dart';

import '../../../sources/models.dart';
import '../app_db.dart';

extension VodProgressQueries on ProgressDao {
  /// Episode progress of one series by episode key; emits after every
  /// change. Includes entries saved without a series key whose episode
  /// belongs to the series.
  Stream<Map<String, ProgressRow>> watchProgressForSeries(
    int sourceId,
    String seriesKey,
  ) {
    final db = attachedDatabase;
    return customSelect(
      'SELECT * FROM watch_progress WHERE source_id = ?1 AND kind = ?3 '
      'AND (series_key = ?2 OR "key" IN (SELECT "key" FROM episodes '
      'WHERE source_id = ?1 AND series_key = ?2))',
      variables: [
        Variable.withInt(sourceId),
        Variable.withString(seriesKey),
        Variable.withString(PlayableKind.episode.name),
      ],
      readsFrom: {db.watchProgress, db.episodes},
    ).watch().map(
      (rows) => {
        for (final r in rows)
          r.read<String>('key'): db.watchProgress.map(r.data).toRow(),
      },
    );
  }
}

extension VodCatalogQueries on CatalogDao {
  /// Episodes of a series ordered by season, then number; emits after every
  /// change (a lazy fetch or a sync).
  Stream<List<EpisodeRow>> watchEpisodesForSeries(
    int sourceId,
    String seriesKey,
  ) {
    final e = attachedDatabase.episodes;
    return (select(e)
          ..where(
            (t) => t.sourceId.equals(sourceId) & t.seriesKey.equals(seriesKey),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.season),
            (t) => OrderingTerm.asc(t.number),
            (t) => OrderingTerm.asc(t.key),
          ]))
        .watch()
        .map((rows) => [for (final r in rows) r.toRow()]);
  }
}
