import 'package:drift/drift.dart';

import '../../../sources/models.dart';
import '../app_db.dart';

/// Resume positions for movies and episodes.
class ProgressDao extends DatabaseAccessor<AppDatabase> {
  ProgressDao(super.attachedDatabase);

  /// Less than this left counts as finished.
  static const finishedRemaining = Duration(minutes: 2);

  /// More than this fraction watched counts as finished.
  static const finishedFraction = 0.95;

  /// The "finished" rule: over 95 % watched or under 2 minutes left.
  /// Unknown durations (<= 0) never finish.
  static bool isFinished(int positionMs, int durationMs) =>
      durationMs > 0 &&
      (positionMs >= durationMs * finishedFraction ||
          durationMs - positionMs < finishedRemaining.inMilliseconds);

  Expression<bool> _match(
    $WatchProgressTable p,
    int sourceId,
    PlayableKind kind,
    String key,
  ) =>
      p.sourceId.equals(sourceId) &
      p.kind.equalsValue(kind) &
      p.key.equals(key);

  /// Saves the position of a movie or episode (live is ignored).
  ///
  /// Without [seriesKey], an episode takes it from the catalog (or keeps the
  /// one saved before), so series grouping still works.
  Future<void> saveProgress(
    int sourceId,
    PlayableKind kind,
    String key,
    int positionMs,
    int durationMs, {
    String? seriesKey,
  }) async {
    if (kind == PlayableKind.live) return;
    final position = positionMs < 0 ? 0 : positionMs;
    final series =
        seriesKey ??
        (kind == PlayableKind.episode
            ? await _seriesKeyOfEpisode(sourceId, key)
            : null);
    final row = WatchProgressCompanion.insert(
      sourceId: sourceId,
      kind: kind,
      key: key,
      seriesKey: Value(series),
      positionMs: position,
      durationMs: durationMs,
      updatedAt: toEpochSec(db.clock.now()),
      finished: Value(isFinished(position, durationMs)),
    );
    await into(db.watchProgress).insert(
      row,
      onConflict: DoUpdate(
        (_) => series == null
            ? row.copyWith(seriesKey: const Value.absent())
            : row,
      ),
    );
  }

  Future<String?> _seriesKeyOfEpisode(int sourceId, String key) {
    final e = db.episodes;
    return (selectOnly(e)
          ..addColumns([e.seriesKey])
          ..where(e.sourceId.equals(sourceId) & e.key.equals(key)))
        .map((r) => r.read(e.seriesKey))
        .getSingleOrNull();
  }

  Future<ProgressRow?> progressFor(
    int sourceId,
    PlayableKind kind,
    String key,
  ) async => (await (select(
    db.watchProgress,
  )..where((p) => _match(p, sourceId, kind, key))).getSingleOrNull())?.toRow();

  Stream<ProgressRow?> watchProgressFor(
    int sourceId,
    PlayableKind kind,
    String key,
  ) => (select(db.watchProgress)..where((p) => _match(p, sourceId, kind, key)))
      .watchSingleOrNull()
      .map((r) => r?.toRow());

  /// Episode progress of one series, by episode key (for progress bars).
  Future<Map<String, ProgressRow>> progressForSeries(
    int sourceId,
    String seriesKey,
  ) async {
    final rows =
        await (select(db.watchProgress)..where(
              (p) =>
                  p.sourceId.equals(sourceId) &
                  p.kind.equalsValue(PlayableKind.episode) &
                  p.seriesKey.equals(seriesKey),
            ))
            .get();
    return {for (final r in rows) r.key: r.toRow()};
  }

  /// Most recently watched episode of a series (finished or not).
  Future<ProgressRow?> lastWatchedEpisode(
    int sourceId,
    String seriesKey,
  ) async =>
      (await (select(db.watchProgress)
                ..where(
                  (p) =>
                      p.sourceId.equals(sourceId) &
                      p.kind.equalsValue(PlayableKind.episode) &
                      p.seriesKey.equals(seriesKey),
                )
                ..orderBy([
                  (p) => OrderingTerm.desc(p.updatedAt),
                  (p) => OrderingTerm.desc(p.rowId),
                ])
                ..limit(1))
              .getSingleOrNull())
          ?.toRow();

  Future<void> clearProgress(int sourceId, PlayableKind kind, String key) =>
      (delete(
        db.watchProgress,
      )..where((p) => _match(p, sourceId, kind, key))).go();

  /// Unfinished movies and episodes, newest first, with names and artwork.
  ///
  /// A series appears once, with its most recently watched episode, and only
  /// while that episode is unfinished. Items whose movie or series vanished
  /// from the catalog are left out.
  Future<List<ContinueWatchingItem>> continueWatching(
    int sourceId, {
    int limit = 20,
  }) => _continueWatching(sourceId, limit).get();

  Stream<List<ContinueWatchingItem>> watchContinueWatching(
    int sourceId, {
    int limit = 20,
  }) => _continueWatching(sourceId, limit).watch();

  Selectable<ContinueWatchingItem> _continueWatching(int sourceId, int limit) =>
      customSelect(
        // Latest entry per series (by the saved or the catalog series key),
        // then only unfinished ones whose movie or series still exists.
        'WITH cw AS (SELECT wp.*, wp.rowid AS rid, '
        'e.title AS ep_title, e.season AS ep_season, e.number AS ep_number, '
        'e.still AS ep_still, '
        "CASE WHEN wp.kind = 'episode' "
        'THEN COALESCE(wp.series_key, e.series_key) END AS skey '
        'FROM watch_progress wp '
        "LEFT JOIN episodes e ON wp.kind = 'episode' "
        'AND e.source_id = wp.source_id AND e."key" = wp."key" '
        'WHERE wp.source_id = ?1), '
        'ranked AS (SELECT cw.*, ROW_NUMBER() OVER ('
        "PARTITION BY CASE WHEN cw.kind = 'episode' "
        "THEN 'e:' || cw.skey ELSE 'm:' || cw.\"key\" END "
        'ORDER BY cw.updated_at DESC, cw.rid DESC) AS rn FROM cw) '
        'SELECT r.*, m.name AS movie_name, m.poster AS movie_poster, '
        's.name AS series_name, s.poster AS series_poster '
        'FROM ranked r '
        "LEFT JOIN movies m ON r.kind = 'movie' "
        'AND m.source_id = r.source_id AND m."key" = r."key" '
        "LEFT JOIN series s ON r.kind = 'episode' "
        'AND s.source_id = r.source_id AND s."key" = r.skey '
        'WHERE r.rn = 1 AND r.finished = 0 AND r.position_ms > 0 '
        'AND (m."key" IS NOT NULL OR s."key" IS NOT NULL) '
        'ORDER BY r.updated_at DESC, r.rid DESC LIMIT ?2',
        variables: [Variable.withInt(sourceId), Variable.withInt(limit)],
        readsFrom: {db.watchProgress, db.movies, db.episodes, db.series},
      ).map((r) {
        final progress = db.watchProgress.map(r.data).toRow();
        final isMovie = progress.kind == PlayableKind.movie;
        return ContinueWatchingItem(
          progress: progress,
          title: isMovie
              ? r.read<String?>('movie_name')
              : r.read<String?>('ep_title'),
          poster: isMovie
              ? r.read<String?>('movie_poster')
              : r.read<String?>('ep_still') ?? r.read<String?>('series_poster'),
          seriesName: r.read<String?>('series_name'),
          season: r.read<int?>('ep_season'),
          episodeNumber: r.read<int?>('ep_number'),
        );
      });
}
