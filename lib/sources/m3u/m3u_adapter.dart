import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/net/http.dart';
import '../../core/net/redact.dart';
import '../models.dart';
import '../source_adapter.dart';
import 'byte_source.dart';
import 'm3u_classify.dart';
import 'm3u_episode_store.dart';
import 'm3u_headers.dart';
import 'm3u_parser.dart';

/// Maximum items per emitted batch.
const kM3uBatchSize = 2000;

/// Bytes read by [M3uAdapter.verify] to sniff the playlist format.
const kM3uSniffBytes = 64 * 1024;

const _notM3u = ParseFailure('not an M3U playlist');
const _noEntries = ParseFailure('playlist has no entries');

/// [SourceAdapter] for M3U playlists from a URL or a local file.
///
/// One streaming pass classifies entries into live channels, movies and
/// series episodes. Memory stays bounded: only the pending batches, the seen
/// key sets and (for [seriesDetail]) a compact [M3uEpisodeStore] are kept.
///
/// A body without `#EXTM3U`/`#EXTINF` (an HTML or JSON error page, an empty
/// response) or without any entry fails with [ParseFailure] before any item
/// batch or [PhaseDoneBatch], so a bad download never replaces the catalog.
class M3uAdapter implements SourceAdapter {
  M3uAdapter(this.config, {required Dio dio, ByteSource? byteSource}) {
    _bytes =
        byteSource ??
        (config.kind == SourceKind.m3uFile
            ? FileByteSource(config.url)
            : HttpByteSource(
                dio,
                config.url,
                headers: {
                  'User-Agent': _hasText(config.userAgent)
                      ? config.userAgent!
                      : kDefaultUserAgent,
                  if (_hasText(config.referer)) 'Referer': config.referer!,
                },
                cancelToken: _cancelToken,
                secrets: _secrets,
              ));
  }

  final SourceConfig config;
  final _cancelToken = CancelToken();
  late final ByteSource _bytes;

  List<String> _epgUrls = const [];

  /// Episodes from the last completed series fetch, for [seriesDetail].
  M3uEpisodeStore? _episodes;

  List<String> get _secrets => [
    if (_hasText(config.username)) config.username!,
    if (_hasText(config.password)) config.password!,
  ];

  @override
  SourceCapabilities get caps =>
      const SourceCapabilities(live: true, movies: true, series: true);

  @override
  Future<AccountInfo> verify() async {
    final head = BytesBuilder(copy: false);
    try {
      await for (final chunk in _bytes.open()) {
        head.add(chunk);
        if (head.length >= kM3uSniffBytes) break;
      }
    } catch (e) {
      throw _failure(e);
    }
    final bytes = head.takeBytes();
    final sniff = bytes.length > kM3uSniffBytes
        ? Uint8List.sublistView(bytes, 0, kM3uSniffBytes)
        : bytes;
    if (!looksLikeM3u(const Utf8Decoder(allowMalformed: true).convert(sniff))) {
      throw const ParseFailure('not an M3U playlist');
    }
    return const AccountInfo(status: AccountStatus.active);
  }

  /// Streams the playlist. A fetch that includes series first releases the
  /// previous episode copy (so two never coexist) and installs the new one
  /// only when the fetch completes; until then [seriesDetail] has nothing.
  @override
  Stream<SyncBatch> fetchCatalog([SyncScope scope = SyncScope.all]) async* {
    final store = scope.series ? M3uEpisodeStore() : null;
    if (store != null) _episodes = null;
    final builder = _CatalogBuilder(scope, store);
    final parser = M3uParser();
    final epg = <String>[];
    var entries = 0;
    try {
      await for (final records in parseM3uChunks(
        _bytes.open(),
        parser: parser,
      )) {
        for (final record in records) {
          switch (record) {
            case M3uHeader(:final epgUrls):
              final fresh = [
                for (final url in epgUrls)
                  if (!epg.contains(url)) url,
              ];
              if (fresh.isNotEmpty) {
                epg.addAll(fresh);
                _epgUrls = List.unmodifiable(epg);
                yield EpgHintBatch(fresh);
              }
            case M3uEntry():
              entries++;
              final batches = builder.add(record);
              // Never emit lines of a non-playlist body as items.
              if (batches.isNotEmpty && !parser.sawMarker) throw _notM3u;
              for (final batch in batches) {
                yield batch;
              }
          }
        }
      }
    } catch (e) {
      throw _failure(e);
    }
    if (!parser.sawMarker) throw _notM3u;
    if (entries == 0) throw _noEntries;
    final tail = builder.finish();
    _epgUrls = List.unmodifiable(epg);
    if (store != null) _episodes = store;
    for (final batch in tail) {
      yield batch;
    }
  }

  @override
  Future<SeriesDetail> seriesDetail(String seriesKey) async {
    final episodes = _episodes?.episodesOf(seriesKey);
    if (episodes == null) throw const ParseFailure('unknown series');
    final sorted = episodes
      ..sort((a, b) {
        final bySeason = a.season.compareTo(b.season);
        return bySeason != 0 ? bySeason : a.number.compareTo(b.number);
      });
    final seasons = <int>{for (final e in sorted) e.season};
    return SeriesDetail(
      key: seriesKey,
      seasons: [for (final s in seasons) SeasonInfo(number: s)],
      episodes: sorted,
    );
  }

  @override
  Future<MovieDetail?> movieDetail(String movieKey) async => null;

  @override
  StreamRequest resolve(PlayableRef ref, {Duration? startAt}) {
    final raw = ref.url;
    if (raw == null || raw.trim().isEmpty) {
      throw const ParseFailure('no stream URL for this item');
    }
    final split = splitPipeHeaders(raw.trim());
    final headers = <String, String>{'User-Agent': kDefaultUserAgent};
    if (_hasText(config.userAgent)) headers['User-Agent'] = config.userAgent!;
    if (_hasText(config.referer)) headers['Referer'] = config.referer!;
    mergeHeaders(headers, split.headers);
    mergeHeaders(headers, ref.headers);
    return StreamRequest(
      url: split.url,
      kind: ref.kind,
      headers: headers,
      isHls: looksLikeHls(split.url),
      startAt: startAt,
      title: ref.title,
    );
  }

  @override
  List<EpgSourceSpec> epgSpecs() => [
    for (final url in _epgUrls)
      EpgSourceSpec(url: url, origin: EpgOrigin.m3uHeader),
  ];

  /// Cancels in-flight reads and releases the episode copy. The adapter is
  /// not reusable afterwards.
  @override
  void close() {
    if (!_cancelToken.isCancelled) _cancelToken.cancel();
    _bytes.cancel();
    _episodes = null;
  }

  SourceFailure _failure(Object e) {
    if (e is SourceFailure) return e;
    if (e is DioException) return mapDioError(e, secrets: _secrets);
    return ParseFailure(redact('$e', secrets: _secrets));
  }
}

bool _hasText(String? s) => s != null && s.trim().isNotEmpty;

/// Whole seconds for a positive, finite `#EXTINF` duration, else null.
int? _durationSec(double? d) {
  if (d == null || !d.isFinite || d <= 0 || d > 0x7FFFFFFF) return null;
  return d.round();
}

/// Per-kind bookkeeping: pending categories, category names seen and the
/// stable keys handed out so far.
class _Lane {
  _Lane(this.kind);

  final ContentKind kind;
  final pendingCategories = <CategoryData>[];
  final _categoryNames = <String>{};
  final _keys = <String>{};
  final _collisions = <String, int>{};

  void addCategories(List<String> groups) {
    for (final g in groups) {
      if (_categoryNames.add(g)) {
        pendingCategories.add(
          CategoryData(
            kind: kind,
            key: g,
            name: g,
            sortIndex: _categoryNames.length - 1,
          ),
        );
      }
    }
  }

  /// Returns [base], or `base#n` when it was already used in this pass.
  String uniqueKey(String base) {
    if (_keys.add(base)) return base;
    var n = (_collisions[base] ?? 1) + 1;
    while (!_keys.add('$base#$n')) {
      n++;
    }
    _collisions[base] = n;
    return '$base#$n';
  }

  List<SyncBatch> takeCategories() {
    if (pendingCategories.isEmpty) return const [];
    final batch = CategoriesBatch(List.of(pendingCategories));
    pendingCategories.clear();
    return [batch];
  }
}

/// Turns parsed entries into bounded [SyncBatch]es.
class _CatalogBuilder {
  _CatalogBuilder(this.scope, this.episodeStore);

  final SyncScope scope;

  /// Receives every episode for [M3uAdapter.seriesDetail].
  final M3uEpisodeStore? episodeStore;
  final _live = _Lane(ContentKind.live);
  final _movie = _Lane(ContentKind.movie);
  final _series = _Lane(ContentKind.series);
  final _seenSeries = <String>{};

  var _channels = <ChannelData>[];
  var _movies = <MovieData>[];
  var _seriesItems = <SeriesData>[];
  var _episodes = <EpisodeData>[];

  List<SyncBatch> add(M3uEntry e) {
    switch (classifyM3uUrl(e.url, isRadio: e.isRadio)) {
      case M3uItemKind.live:
        return scope.live ? _addChannel(e) : const [];
      case M3uItemKind.movie:
        return scope.movies ? _addMovie(e) : const [];
      case M3uItemKind.episode:
        final match =
            matchEpisode(e.name) ??
            (e.tvgName != null ? matchEpisode(e.tvgName!) : null);
        if (match == null) return scope.movies ? _addMovie(e) : const [];
        return scope.series ? _addEpisode(e, match) : const [];
    }
  }

  String _baseKey(M3uEntry e) =>
      baseStableKey(e.url, tvgId: e.tvgId, name: e.name);

  List<SyncBatch> _addChannel(M3uEntry e) {
    _live.addCategories(e.groups);
    _channels.add(
      ChannelData(
        key: _live.uniqueKey(_baseKey(e)),
        name: e.name,
        num: e.chno,
        logo: e.logo,
        tvgId: e.tvgId,
        tvgName: e.tvgName,
        url: e.url,
        headers: e.headers,
        isRadio: e.isRadio,
        categoryKeys: e.groups,
        catchupMode: e.catchup,
        catchupDays: e.catchupDays,
        catchupSource: e.catchupSource,
        tvgShiftMin: e.tvgShiftMin,
      ),
    );
    if (_channels.length >= kM3uBatchSize ||
        _live.pendingCategories.length >= kM3uBatchSize) {
      return _flushLive();
    }
    return const [];
  }

  List<SyncBatch> _addMovie(M3uEntry e) {
    _movie.addCategories(e.groups);
    _movies.add(
      MovieData(
        key: _movie.uniqueKey(_baseKey(e)),
        name: e.name,
        poster: e.logo,
        year: extractYear(e.name),
        ext: urlExtension(e.url),
        url: e.url,
        headers: e.headers,
        categoryKeys: e.groups,
      ),
    );
    if (_movies.length >= kM3uBatchSize ||
        _movie.pendingCategories.length >= kM3uBatchSize) {
      return _flushMovies();
    }
    return const [];
  }

  List<SyncBatch> _addEpisode(M3uEntry e, EpisodeMatch match) {
    final seriesKey = seriesKeyFor(match.series);
    if (_seenSeries.add(seriesKey)) {
      _series.addCategories(e.groups);
      _seriesItems.add(
        SeriesData(
          key: seriesKey,
          name: match.series,
          poster: e.logo,
          year: extractYear(match.series),
          categoryKeys: e.groups,
        ),
      );
    }
    final episode = EpisodeData(
      seriesKey: seriesKey,
      key: _series.uniqueKey(_baseKey(e)),
      season: match.season,
      number: match.episode,
      title: e.name,
      ext: urlExtension(e.url),
      url: e.url,
      headers: e.headers,
      durationSec: _durationSec(e.duration),
      still: e.logo,
    );
    _episodes.add(episode);
    episodeStore?.add(episode);
    if (_episodes.length >= kM3uBatchSize ||
        _seriesItems.length >= kM3uBatchSize ||
        _series.pendingCategories.length >= kM3uBatchSize) {
      return _flushSeries();
    }
    return const [];
  }

  List<SyncBatch> _flushLive() {
    final out = _live.takeCategories();
    if (_channels.isEmpty) return out;
    final batch = ChannelsBatch(_channels);
    _channels = [];
    return [...out, batch];
  }

  List<SyncBatch> _flushMovies() {
    final out = _movie.takeCategories();
    if (_movies.isEmpty) return out;
    final batch = MoviesBatch(_movies);
    _movies = [];
    return [...out, batch];
  }

  List<SyncBatch> _flushSeries() {
    final out = [..._series.takeCategories()];
    if (_seriesItems.isNotEmpty) {
      out.add(SeriesBatch(_seriesItems));
      _seriesItems = [];
    }
    if (_episodes.isNotEmpty) {
      out.add(EpisodesBatch(_episodes));
      _episodes = [];
    }
    return out;
  }

  /// Remaining batches followed by one [PhaseDoneBatch] per fetched family.
  List<SyncBatch> finish() => [
    ..._flushLive(),
    ..._flushMovies(),
    ..._flushSeries(),
    if (scope.live) const PhaseDoneBatch(ContentKind.live),
    if (scope.movies) const PhaseDoneBatch(ContentKind.movie),
    if (scope.series) const PhaseDoneBatch(ContentKind.series),
  ];
}
