import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';

import '../../core/db/app_db.dart';
import '../../core/log/ring_log.dart';
import '../../core/net/redact.dart';
import '../../sources/models.dart';
import '../../sources/source_adapter.dart';

/// Builds a ready adapter for a saved source (the caller closes it).
typedef VodAdapterLoader = Future<SourceAdapter> Function(int sourceId);

/// Lazily fetched details and whether fetching them failed.
@immutable
class DetailResult<T> {
  const DetailResult(this.value, {this.failed = false});

  /// The details (fresh, cached or stale), or null when there are none.
  final T? value;

  /// True when the details could not be fetched and nothing was cached.
  final bool failed;
}

/// Lazy movie and series details with the 24 h detail cache.
///
/// * Movies: Xtream `get_vod_info`, cached in `detail_cache`. A fresh cache
///   entry answers without any network call; an empty answer is cached too,
///   so a title without details is not asked for again within the TTL.
/// * Series: Xtream `get_series_info`. Its episodes are stored in the
///   `episodes` table (`CatalogDao.saveFetchedEpisodes`) and the header and
///   season list in the cache (without the episodes, which live in the
///   table). A fresh cache entry is used only while the series still has
///   stored episodes; its value then has no episodes. A fetch without
///   episodes keeps the ones stored before.
/// * M3U sources: nothing to fetch. Movie details stay null and series
///   episodes come from the playlist import.
///
/// Never throws: a failed fetch falls back to a stale cache entry, else
/// reports [DetailResult.failed]. Errors are logged with URLs redacted.
class VodDetailService {
  VodDetailService({required this.db, required this.adapters, RingLog? log})
    : _log = log ?? RingLog.instance;

  final AppDatabase db;
  final VodAdapterLoader adapters;
  final RingLog _log;

  Future<bool> _fetchable(int sourceId) async =>
      (await db.sourcesDao.byId(sourceId))?.kind == SourceKind.xtream;

  /// Details of movie [key] of source [sourceId].
  Future<DetailResult<MovieDetail>> movieDetail(
    int sourceId,
    String key,
  ) async {
    final cache = db.detailCacheDao;
    try {
      final fresh = await cache.movieDetail(sourceId, key);
      if (fresh != null) return DetailResult(fresh);
      if (!await _fetchable(sourceId)) return const DetailResult(null);
    } on Object catch (e) {
      _log.warn('Movie details unreadable: ${redact('$e')}');
      return const DetailResult(null, failed: true);
    }
    SourceAdapter? adapter;
    try {
      adapter = await adapters(sourceId);
      final detail = await adapter.movieDetail(key) ?? MovieDetail(key: key);
      await cache.putMovieDetail(sourceId, detail);
      return DetailResult(detail);
    } on Object catch (e) {
      _log.warn('Movie details failed: ${redact('$e')}');
      final stale = await _orNull(
        () => cache.movieDetail(sourceId, key, allowStale: true),
      );
      return DetailResult(stale, failed: stale == null);
    } finally {
      adapter?.close();
    }
  }

  /// Details of series [key] of source [sourceId]; its episodes are in the
  /// `episodes` table when this completes.
  Future<DetailResult<SeriesDetail>> seriesDetail(
    int sourceId,
    String key,
  ) async {
    final cache = db.detailCacheDao;
    try {
      if (!await _fetchable(sourceId)) return const DetailResult(null);
      final fresh = await cache.seriesDetail(sourceId, key);
      if (fresh != null && await _hasEpisodes(sourceId, key)) {
        return DetailResult(fresh);
      }
    } on Object catch (e) {
      _log.warn('Series details unreadable: ${redact('$e')}');
      return const DetailResult(null, failed: true);
    }
    SourceAdapter? adapter;
    try {
      adapter = await adapters(sourceId);
      final detail = await adapter.seriesDetail(key);
      // An empty answer never wipes episodes fetched before (panels
      // sometimes answer with an empty list while overloaded).
      if (detail.episodes.isNotEmpty || !await _hasEpisodes(sourceId, key)) {
        await db.catalogDao.saveFetchedEpisodes(sourceId, key, detail.episodes);
      }
      final header = SeriesDetail(
        key: key,
        plot: detail.plot,
        cast: detail.cast,
        genre: detail.genre,
        backdrop: detail.backdrop,
        seasons: detail.seasons,
      );
      await cache.putSeriesDetail(sourceId, header);
      // The caller gets the fetched episodes too (the page shows them
      // before the episodes query has re-run).
      return DetailResult(detail);
    } on Object catch (e) {
      _log.warn('Series details failed: ${redact('$e')}');
      final stale = await _orNull(
        () => cache.seriesDetail(sourceId, key, allowStale: true),
      );
      return DetailResult(stale, failed: true);
    } finally {
      adapter?.close();
    }
  }

  Future<bool> _hasEpisodes(int sourceId, String seriesKey) async {
    final row = await db
        .customSelect(
          'SELECT 1 AS x FROM episodes WHERE source_id = ?1 '
          'AND series_key = ?2 LIMIT 1',
          variables: [
            Variable.withInt(sourceId),
            Variable.withString(seriesKey),
          ],
          readsFrom: {db.episodes},
        )
        .getSingleOrNull();
    return row != null;
  }

  static Future<T?> _orNull<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } on Object {
      return null;
    }
  }
}
