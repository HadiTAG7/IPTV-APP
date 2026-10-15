// Series detail providers and the remembered season (no code generation).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../core/db/queries/vod_queries.dart';
import '../../sources/models.dart';
import '../vod_common/vod_providers.dart';

/// The catalog row of a series, or null when it is no longer in the source.
final seriesRowProvider = FutureProvider.autoDispose
    .family<SeriesRow?, VodItemRef>(
      (ref, r) => ref.watch(catalogDaoProvider).seriesByKey(r.sourceId, r.key),
    );

/// Lazily fetched header and seasons (Xtream `get_series_info`); the fetched
/// episodes are stored first, so [seriesEpisodesProvider] updates. Never
/// fails, see [DetailResult]. The value keeps the fetched episodes until
/// the page closes (they are not cached as JSON).
final seriesDetailProvider = FutureProvider.autoDispose
    .family<DetailResult<SeriesDetail>, VodItemRef>(
      (ref, r) =>
          ref.watch(vodDetailServiceProvider).seriesDetail(r.sourceId, r.key),
    );

/// Stored episodes of a series by season and number (from the playlist
/// import for M3U, from the lazy fetch for Xtream).
final seriesEpisodesProvider = StreamProvider.autoDispose
    .family<List<EpisodeRow>, VodItemRef>(
      (ref, r) => ref
          .watch(catalogDaoProvider)
          .watchEpisodesForSeries(r.sourceId, r.key),
    );

/// Episode progress of a series by episode key.
final seriesProgressProvider = StreamProvider.autoDispose
    .family<Map<String, ProgressRow>, VodItemRef>(
      (ref, r) => ref
          .watch(progressDaoProvider)
          .watchProgressForSeries(r.sourceId, r.key),
    );

/// Settings key of the last selected season per series.
const kLastSeasonsKey = 'vod.lastSeasons';

/// Series whose season choice is remembered (the oldest are dropped).
const kMaxRememberedSeasons = 300;

String _seasonKey(int sourceId, String seriesKey) => '$sourceId|$seriesKey';

/// The season last selected in series [seriesKey], if remembered.
Future<int?> loadLastSeason(
  SettingsDao settings,
  int sourceId,
  String seriesKey,
) async {
  final all = await settings.getJson(kLastSeasonsKey);
  if (all is! Map) return null;
  final value = all[_seasonKey(sourceId, seriesKey)];
  return value is int ? value : null;
}

/// Remembers [season] as the selected season of series [seriesKey].
Future<void> saveLastSeason(
  SettingsDao settings,
  int sourceId,
  String seriesKey,
  int season,
) async {
  final stored = await settings.getJson(kLastSeasonsKey);
  final key = _seasonKey(sourceId, seriesKey);
  // Insertion order is recency: re-adding moves the series to the end.
  final all = <String, Object?>{
    if (stored is Map)
      for (final e in stored.entries)
        if (e.key is String && e.key != key) e.key as String: e.value,
    key: season,
  };
  while (all.length > kMaxRememberedSeasons) {
    all.remove(all.keys.first);
  }
  await settings.setJson(kLastSeasonsKey, all);
}
