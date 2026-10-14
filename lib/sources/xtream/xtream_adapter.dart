import 'package:dio/dio.dart';

import '../../core/net/http.dart';
import '../../core/time/clock.dart';
import '../../epg/epg_models.dart';
import '../models.dart';
import '../source_adapter.dart';
import 'coerce.dart';
import 'xtream_client.dart';
import 'xtream_urls.dart';

typedef _Fetch = Stream<Map<String, Object?>> Function({
  String? categoryId,
  Duration? idleTimeout,
});

/// [SourceAdapter] for Xtream Codes panels.
///
/// Catalog lists are streamed and emitted in batches of at most [batchSize].
/// When a full list stalls for [fullListTimeout], or in [lowMemory] mode, the
/// list is fetched per `category_id` instead, skipping items already emitted
/// (items without a category are then unreachable). Records the mappers cannot
/// read are skipped. Stream URLs are built at play time.
class XtreamAdapter implements SourceAdapter {
  XtreamAdapter(
    this.config, {
    required Dio dio,
    this.lowMemory = false,
    this.fullListTimeout = const Duration(seconds: 60),
    this.allowedFormats = const [],
    Clock clock = const SystemClock(),
  }) : client = XtreamClient(
         XtreamUrls(config.url, config.username ?? '', config.password ?? ''),
         dio,
         clock: clock,
       );

  static const batchSize = 2000;

  final SourceConfig config;
  final XtreamClient client;
  final bool lowMemory;
  final Duration fullListTimeout;

  /// `allowed_output_formats` from the last [verify] (lower case). Seed it
  /// from storage when the adapter is built only for playback.
  List<String> allowedFormats;

  XtreamUrls get urls => client.urls;

  @override
  SourceCapabilities get caps => const SourceCapabilities(
    live: true,
    movies: true,
    series: true,
    shortEpg: true,
  );

  @override
  Future<AccountInfo> verify() async {
    final info = await client.authenticate();
    allowedFormats = info.allowedFormats;
    return info;
  }

  @override
  Stream<SyncBatch> fetchCatalog([SyncScope scope = SyncScope.all]) async* {
    if (scope.live) {
      final cats = _categories(
        ContentKind.live,
        await client.getLiveCategories(),
      );
      if (cats.isNotEmpty) yield CategoriesBatch(cats);
      yield* _items(
        client.getLiveStreams,
        cats,
        XtreamMappers.channel,
        (c) => c.key,
        ChannelsBatch.new,
      );
      yield const PhaseDoneBatch(ContentKind.live);
    }
    if (scope.movies) {
      final cats = _categories(
        ContentKind.movie,
        await client.getVodCategories(),
      );
      if (cats.isNotEmpty) yield CategoriesBatch(cats);
      yield* _items(
        client.getVodStreams,
        cats,
        XtreamMappers.movie,
        (m) => m.key,
        MoviesBatch.new,
      );
      yield const PhaseDoneBatch(ContentKind.movie);
    }
    if (scope.series) {
      final cats = _categories(
        ContentKind.series,
        await client.getSeriesCategories(),
      );
      if (cats.isNotEmpty) yield CategoriesBatch(cats);
      yield* _items(
        client.getSeries,
        cats,
        XtreamMappers.series,
        (s) => s.key,
        SeriesBatch.new,
      );
      yield const PhaseDoneBatch(ContentKind.series);
    }
  }

  @override
  Future<SeriesDetail> seriesDetail(String seriesKey) async {
    final json = await client.getSeriesInfo(seriesKey);
    return guardParse(
      'get_series_info',
      () => XtreamMappers.seriesDetail(seriesKey, json),
    );
  }

  @override
  Future<MovieDetail?> movieDetail(String movieKey) async {
    final json = await client.getVodInfo(movieKey);
    return guardParse(
      'get_vod_info',
      () => XtreamMappers.movieDetail(movieKey, json),
    );
  }

  /// Short EPG for one live stream (fallback when XMLTV has no data).
  Future<List<EpgProgramme>> shortEpg(String streamKey, {int limit = 2}) =>
      client.getShortEpg(streamKey, limit: limit);

  /// Live container to request: [PlayableRef.ext] when it is `ts`/`m3u8`
  /// (the "try other format" toggle), else the source's [LiveFormat], unless
  /// the panel's allowed formats exclude it.
  String liveExt([String? override]) {
    final o = override?.toLowerCase();
    if (o == 'ts' || o == 'm3u8') return o!;
    final preferred = config.liveFormat.name;
    if (allowedFormats.isEmpty || allowedFormats.contains(preferred)) {
      return preferred;
    }
    for (final f in const ['ts', 'm3u8']) {
      if (allowedFormats.contains(f)) return f;
    }
    return preferred;
  }

  @override
  StreamRequest resolve(PlayableRef ref, {Duration? startAt}) {
    final String ext;
    final String url;
    switch (ref.kind) {
      case PlayableKind.live:
        ext = liveExt(ref.ext);
        url = urls.live(ref.key, ext);
      case PlayableKind.movie:
        ext = _ext(ref.ext);
        url = urls.movie(ref.key, ext);
      case PlayableKind.episode:
        ext = _ext(ref.ext);
        url = urls.episode(ref.key, ext);
    }
    final ua = config.userAgent;
    final referer = config.referer;
    return StreamRequest(
      url: url,
      kind: ref.kind,
      headers: {
        'User-Agent': (ua == null || ua.isEmpty) ? kDefaultUserAgent : ua,
        if (referer != null && referer.isNotEmpty) 'Referer': referer,
        ...ref.headers,
      },
      isHls: ext == 'm3u8',
      startAt: startAt,
      title: ref.title,
    );
  }

  @override
  List<EpgSourceSpec> epgSpecs() => [
    EpgSourceSpec(url: urls.xmltv(), origin: EpgOrigin.xtream),
  ];

  @override
  void close() => client.close();

  static String _ext(String? ext) {
    final e = ext?.trim().toLowerCase();
    if (e == null || e.isEmpty) return 'mp4';
    return e.startsWith('.') ? e.substring(1) : e;
  }

  static List<CategoryData> _categories(
    ContentKind kind,
    List<Map<String, Object?>> raw,
  ) {
    final seen = <String>{};
    final out = <CategoryData>[];
    for (final j in raw) {
      final key = asStr(j['category_id']);
      if (key == null || !seen.add(key)) continue;
      out.add(
        CategoryData(
          kind: kind,
          key: key,
          name: asStr(j['category_name']) ?? key,
          sortIndex: out.length,
        ),
      );
    }
    return out;
  }

  Stream<SyncBatch> _items<T>(
    _Fetch fetch,
    List<CategoryData> categories,
    T? Function(Map<String, Object?> json, {String? categoryId}) map,
    String Function(T item) keyOf,
    SyncBatch Function(List<T> items) wrap,
  ) async* {
    // One malformed record is skipped rather than failing the whole sync.
    T? mapOrSkip(Map<String, Object?> json, [String? categoryId]) {
      try {
        return map(json, categoryId: categoryId);
      } catch (_) {
        return null;
      }
    }

    final seen = <String>{};
    var batch = <T>[];
    // Without categories there is nothing to fall back to: use the full list
    // and let a timeout fail the sync rather than return an empty catalog.
    final canSplit = categories.isNotEmpty;
    var perCategory = lowMemory && canSplit;
    if (!perCategory) {
      try {
        final full = fetch(idleTimeout: canSplit ? fullListTimeout : null);
        await for (final json in full) {
          final item = mapOrSkip(json);
          if (item == null || !seen.add(keyOf(item))) continue;
          batch.add(item);
          if (batch.length >= batchSize) {
            yield wrap(batch);
            batch = <T>[];
          }
        }
      } on TimeoutFailure {
        if (!canSplit) rethrow;
        perCategory = true;
      }
    }
    if (perCategory) {
      for (final cat in categories) {
        await for (final json in fetch(categoryId: cat.key)) {
          final item = mapOrSkip(json, cat.key);
          if (item == null || !seen.add(keyOf(item))) continue;
          batch.add(item);
          if (batch.length >= batchSize) {
            yield wrap(batch);
            batch = <T>[];
          }
        }
      }
    }
    if (batch.isNotEmpty) yield wrap(batch);
  }
}

/// Pure JSON → domain mapping for Xtream responses. `direct_source` and
/// `now_playing` are never read.
abstract final class XtreamMappers {
  static final _yearInName = RegExp(r'[(\[]\s*((?:19|20)\d\d)\s*[)\]]');
  static final _year = RegExp(r'(?<!\d)((?:19|20)\d\d)(?!\d)');

  /// `get_live_streams` item; null without a `stream_id`. [categoryId] is used
  /// when the item names no category.
  static ChannelData? channel(Map<String, Object?> j, {String? categoryId}) {
    final key = asStr(j['stream_id']);
    if (key == null) return null;
    final archive = asBool(j['tv_archive']);
    final type = asStr(j['stream_type']);
    return ChannelData(
      key: key,
      name: asStr(j['name']) ?? key,
      num: asInt(j['num']),
      logo: asStr(j['stream_icon']),
      tvgId: asStr(j['epg_channel_id']),
      isRadio: type == 'radio_streams' || type == 'radio',
      categoryKeys: _categoryKeys(j, categoryId),
      catchupMode: archive ? 'xc' : null,
      catchupDays: archive ? (asInt(j['tv_archive_duration']) ?? 0) : 0,
    );
  }

  /// `get_vod_streams` item; null without a `stream_id`.
  static MovieData? movie(Map<String, Object?> j, {String? categoryId}) {
    final key = asStr(j['stream_id']);
    if (key == null) return null;
    final name = asStr(j['name']) ?? asStr(j['title']) ?? key;
    return MovieData(
      key: key,
      name: name,
      poster: asStr(j['stream_icon']) ?? asStr(j['cover']),
      year: _yearOf(j['year']) ?? _yearFromName(name),
      rating: rating(j),
      ext: asStr(j['container_extension'])?.toLowerCase(),
      addedAt: asEpoch(j['added']),
      categoryKeys: _categoryKeys(j, categoryId),
    );
  }

  /// `get_series` item; null without a `series_id`.
  static SeriesData? series(Map<String, Object?> j, {String? categoryId}) {
    final key = asStr(j['series_id']);
    if (key == null) return null;
    final name = asStr(j['name']) ?? asStr(j['title']) ?? key;
    return SeriesData(
      key: key,
      name: name,
      poster: asStr(j['cover']) ?? asStr(j['stream_icon']),
      year:
          _yearOf(j['year']) ??
          _yearOf(j['releaseDate']) ??
          _yearOf(j['release_date']) ??
          _yearFromName(name),
      rating: rating(j),
      plot: asStr(j['plot']),
      categoryKeys: _categoryKeys(j, categoryId),
    );
  }

  /// `get_series_info` → seasons and episodes.
  ///
  /// `episodes` may be a map keyed by season or a flat list; an episode's own
  /// `season` field wins. Seasons come from `seasons[]` plus any season that
  /// has episodes; listed seasons without episodes are dropped when episodes
  /// exist.
  static SeriesDetail seriesDetail(String key, Map<String, Object?> j) {
    final info = asMap(j['info']);
    final raw = <(int, int?, Map<String, Object?>)>[];
    void addEpisode(Object? e, int? seasonHint) {
      final m = asMap(e);
      if (m.isEmpty) return;
      final season = asInt(m['season']) ?? seasonHint ?? 1;
      raw.add((season, asInt(m['episode_num']), m));
    }

    void addAll(Object? value, int? seasonHint) {
      if (value is Map && value.containsKey('id')) {
        addEpisode(value, seasonHint);
        return;
      }
      for (final e in asList(value)) {
        if (e is List) {
          for (final inner in e) {
            addEpisode(inner, seasonHint);
          }
        } else {
          addEpisode(e, seasonHint);
        }
      }
    }

    final episodesJson = j['episodes'];
    if (episodesJson is Map) {
      for (final entry in asMap(episodesJson).entries) {
        addAll(entry.value, asInt(entry.key));
      }
    } else {
      addAll(episodesJson, null);
    }

    final counters = <int, int>{};
    final seenKeys = <String>{};
    final episodes = <EpisodeData>[];
    for (final (season, number, m) in raw) {
      final position = (counters[season] ?? 0) + 1;
      counters[season] = position;
      final id = asStr(m['id']);
      if (id == null || !seenKeys.add(id)) continue;
      final epInfo = asMap(m['info']);
      episodes.add(
        EpisodeData(
          seriesKey: key,
          key: id,
          season: season,
          number: number ?? position,
          title: asStr(m['title']),
          ext: asStr(m['container_extension'])?.toLowerCase(),
          durationSec:
              asInt(epInfo['duration_secs']) ??
              parseDuration(epInfo['duration']),
          plot: asStr(epInfo['plot']),
          still: asStr(epInfo['movie_image']) ?? asStr(epInfo['cover_big']),
        ),
      );
    }
    episodes.sort((a, b) {
      final bySeason = a.season.compareTo(b.season);
      return bySeason != 0 ? bySeason : a.number.compareTo(b.number);
    });

    final seasons = <int, SeasonInfo>{};
    for (final s in asList(j['seasons'])) {
      final m = asMap(s);
      final n = asInt(m['season_number']) ?? asInt(m['season']);
      if (n == null) continue;
      seasons.putIfAbsent(
        n,
        () => SeasonInfo(
          number: n,
          name: asStr(m['name']),
          cover: asStr(m['cover_big']) ?? asStr(m['cover']),
        ),
      );
    }
    final withEpisodes = {for (final e in episodes) e.season};
    for (final n in withEpisodes) {
      seasons.putIfAbsent(n, () => SeasonInfo(number: n));
    }
    final seasonList =
        seasons.values
            .where((s) => episodes.isEmpty || withEpisodes.contains(s.number))
            .toList()
          ..sort((a, b) => a.number.compareTo(b.number));

    return SeriesDetail(
      key: key,
      plot: asStr(info['plot']),
      cast: asStr(info['cast']),
      genre: asStr(info['genre']),
      backdrop: firstStr(info['backdrop_path']),
      seasons: seasonList,
      episodes: episodes,
    );
  }

  /// `get_vod_info` → details; null when both `info` and `movie_data` are
  /// empty.
  static MovieDetail? movieDetail(String key, Map<String, Object?> j) {
    final info = asMap(j['info']);
    final data = asMap(j['movie_data']);
    if (info.isEmpty && data.isEmpty) return null;
    return MovieDetail(
      key: key,
      plot: asStr(info['plot']) ?? asStr(info['description']),
      cast: asStr(info['cast']) ?? asStr(info['actors']),
      director: asStr(info['director']),
      genre: asStr(info['genre']),
      durationSec:
          asInt(info['duration_secs']) ?? parseDuration(info['duration']),
      backdrop: firstStr(info['backdrop_path']),
      rating: rating(info),
      releaseDate: asStr(info['releasedate']) ?? asStr(info['release_date']),
      ext: asStr(data['container_extension'])?.toLowerCase(),
    );
  }

  /// 0–10 rating from `rating`, else `rating_5based * 2`; null when unrated.
  static double? rating(Map<String, Object?> j) {
    var r = asDouble(j['rating']);
    if (r == null || r <= 0) {
      final five = asDouble(j['rating_5based']);
      r = five == null ? null : five * 2;
    }
    if (r == null || r <= 0) return null;
    return r > 10 ? 10 : r;
  }

  /// Seconds from `HH:MM:SS` or `MM:SS`.
  static int? parseDuration(Object? v) {
    final s = asStr(v);
    if (s == null) return null;
    final parts = s.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    var total = 0;
    for (final p in parts) {
      final n = int.tryParse(p.trim());
      if (n == null || n < 0) return null;
      total = total * 60 + n;
    }
    return total > 0 ? total : null;
  }

  /// A string, or the first non-empty string of a list.
  static String? firstStr(Object? v) =>
      v is String ? asStr(v) : asStrList(v).firstOrNull;

  static int? _yearOf(Object? v) {
    final s = asStr(v);
    if (s == null) return null;
    final m = _year.firstMatch(s);
    return m == null ? null : int.parse(m[1]!);
  }

  static int? _yearFromName(String name) {
    final m = _yearInName.firstMatch(name);
    return m == null ? null : int.parse(m[1]!);
  }

  static List<String> _categoryKeys(Map<String, Object?> j, String? fallback) {
    final ids = asStrList(j['category_ids']);
    if (ids.isNotEmpty) return ids.toSet().toList();
    final id = asStr(j['category_id']) ?? fallback;
    return id == null ? const [] : [id];
  }
}
