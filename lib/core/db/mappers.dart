// Row views handed to the UI and conversions between domain models
// (`sources/models.dart`, `epg/epg_models.dart`) and drift rows.
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../epg/epg_models.dart';
import '../../player/engine/player_engine.dart';
import '../../sources/models.dart';
import '../text/normalize.dart';
import 'app_db.dart';

/// Epoch seconds (UTC) for storage.
int toEpochSec(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

/// UTC [DateTime] from stored epoch seconds.
DateTime fromEpochSec(int s) =>
    DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);

DateTime? _fromEpochSecOrNull(int? s) => s == null ? null : fromEpochSec(s);

String? encodeHeaders(Map<String, String> headers) =>
    headers.isEmpty ? null : jsonEncode(headers);

Map<String, String> decodeHeaders(String? json) {
  if (json == null || json.isEmpty) return const {};
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return const {};
    return {
      for (final e in decoded.entries)
        if (e.value != null) '${e.key}': '${e.value}',
    };
  } on FormatException {
    return const {};
  }
}

List<String> _decodeStringList(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return [for (final v in decoded) '$v'];
  } on FormatException {
    return const [];
  }
}

/// A saved source as shown in source management.
class SourceRow {
  const SourceRow({
    required this.id,
    required this.name,
    required this.kind,
    required this.url,
    this.username,
    this.userAgent,
    this.referer,
    this.liveFormat = LiveFormat.ts,
    this.epgOffsetMin = 0,
    this.engineLive,
    this.engineVod,
    this.accountStatus = AccountStatus.unknown,
    this.expiresAt,
    this.maxConnections,
    this.allowedFormats = const [],
    this.generation = 0,
    this.lastSyncAt,
    this.lastEpgAt,
    this.sortIndex = 0,
  });

  final int id;
  final String name;
  final SourceKind kind;

  /// Credentials masked; `SourcesDao.configFor` has the full URL.
  final String url;
  final String? username;
  final String? userAgent;
  final String? referer;
  final LiveFormat liveFormat;
  final int epgOffsetMin;
  final EngineKind? engineLive;
  final EngineKind? engineVod;
  final AccountStatus accountStatus;
  final DateTime? expiresAt;
  final int? maxConnections;
  final List<String> allowedFormats;

  /// Committed catalog generation; 0 means never synced.
  final int generation;
  final DateTime? lastSyncAt;
  final DateTime? lastEpgAt;
  final int sortIndex;

  bool get hasCatalog => generation > 0;

  /// Adapter configuration; the password and the unmasked [url] come from
  /// the secret store.
  SourceConfig toConfig({String? password, String? url}) => SourceConfig(
    id: id,
    name: name,
    kind: kind,
    url: url ?? this.url,
    username: username,
    password: password,
    userAgent: userAgent,
    referer: referer,
    liveFormat: liveFormat,
    epgOffsetMin: epgOffsetMin,
  );
}

class CategoryRow {
  const CategoryRow({
    required this.kind,
    required this.key,
    required this.name,
    this.sortIndex = 0,
    this.itemCount = 0,
    this.hidden = false,
  });

  final ContentKind kind;
  final String key;
  final String name;
  final int sortIndex;
  final int itemCount;
  final bool hidden;
}

class ChannelRow {
  const ChannelRow({
    required this.key,
    required this.name,
    this.num,
    this.logo,
    this.tvgId,
    this.tvgName,
    this.url,
    this.headers = const {},
    this.isRadio = false,
    this.catchupMode,
    this.catchupDays = 0,
    this.catchupSource,
    this.tvgShiftMin = 0,
  });

  final String key;
  final String name;
  final int? num;
  final String? logo;
  final String? tvgId;
  final String? tvgName;
  final String? url;
  final Map<String, String> headers;
  final bool isRadio;
  final String? catchupMode;
  final int catchupDays;
  final String? catchupSource;
  final int tvgShiftMin;

  PlayableRef toPlayable() => PlayableRef(
    kind: PlayableKind.live,
    key: key,
    url: url,
    headers: headers,
    title: name,
  );
}

class MovieRow {
  const MovieRow({
    required this.key,
    required this.name,
    this.poster,
    this.year,
    this.rating,
    this.ext,
    this.url,
    this.headers = const {},
    this.addedAt,
  });

  final String key;
  final String name;
  final String? poster;
  final int? year;
  final double? rating;
  final String? ext;
  final String? url;
  final Map<String, String> headers;
  final DateTime? addedAt;

  PlayableRef toPlayable() => PlayableRef(
    kind: PlayableKind.movie,
    key: key,
    url: url,
    ext: ext,
    headers: headers,
    title: name,
  );
}

class SeriesRow {
  const SeriesRow({
    required this.key,
    required this.name,
    this.poster,
    this.year,
    this.rating,
    this.plot,
  });

  final String key;
  final String name;
  final String? poster;
  final int? year;
  final double? rating;
  final String? plot;
}

class EpisodeRow {
  const EpisodeRow({
    required this.seriesKey,
    required this.key,
    required this.season,
    required this.number,
    this.title,
    this.ext,
    this.url,
    this.headers = const {},
    this.durationSec,
    this.plot,
    this.still,
  });

  final String seriesKey;
  final String key;
  final int season;
  final int number;
  final String? title;
  final String? ext;
  final String? url;
  final Map<String, String> headers;
  final int? durationSec;
  final String? plot;
  final String? still;

  PlayableRef toPlayable() => PlayableRef(
    kind: PlayableKind.episode,
    key: key,
    url: url,
    ext: ext,
    headers: headers,
    title: title,
  );
}

/// Search hits grouped by kind, each list capped by `limitPerKind`.
class SearchResults {
  const SearchResults({
    this.channels = const [],
    this.movies = const [],
    this.series = const [],
  });

  static const empty = SearchResults();

  final List<ChannelRow> channels;
  final List<MovieRow> movies;
  final List<SeriesRow> series;

  bool get isEmpty => channels.isEmpty && movies.isEmpty && series.isEmpty;
}

/// A favourite and its catalog item; [item] is null when the item vanished
/// from the source ("unavailable").
class FavoriteItem<T> {
  const FavoriteItem({
    required this.kind,
    required this.key,
    required this.addedAt,
    this.item,
  });

  final ContentKind kind;
  final String key;
  final DateTime addedAt;
  final T? item;

  bool get available => item != null;
}

class ProgressRow {
  const ProgressRow({
    required this.kind,
    required this.key,
    required this.position,
    required this.duration,
    required this.updatedAt,
    this.seriesKey,
    this.finished = false,
  });

  final PlayableKind kind;
  final String key;
  final String? seriesKey;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;
  final bool finished;

  /// 0..1, or 0 when the duration is unknown.
  double get fraction => duration.inMilliseconds <= 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
}

/// One entry of the "Continue watching" row.
class ContinueWatchingItem {
  const ContinueWatchingItem({
    required this.progress,
    this.title,
    this.poster,
    this.seriesName,
    this.season,
    this.episodeNumber,
  });

  final ProgressRow progress;

  /// Movie name or episode title.
  final String? title;

  /// Movie poster, episode still or series poster.
  final String? poster;
  final String? seriesName;
  final int? season;
  final int? episodeNumber;

  PlayableKind get kind => progress.kind;
  String get key => progress.key;
}

/// Per-channel player choices.
class ChannelPrefsData {
  const ChannelPrefsData({this.engine, this.aspect, this.audioLang});

  static const empty = ChannelPrefsData();

  final EngineKind? engine;
  final AspectMode? aspect;
  final String? audioLang;

  bool get isEmpty => engine == null && aspect == null && audioLang == null;
}

class EpgSourceRow {
  const EpgSourceRow({
    required this.id,
    required this.sourceId,
    required this.url,
    required this.origin,
    this.enabled = true,
    this.priority = 0,
    this.etag,
    this.lastModified,
    this.lastFetchAt,
    this.status,
    this.programmeCount = 0,
  });

  final int id;
  final int sourceId;

  /// Credentials masked; `EpgDao.epgSourceUrl` has the full URL.
  final String url;
  final EpgOrigin origin;
  final bool enabled;
  final int priority;
  final String? etag;
  final String? lastModified;
  final DateTime? lastFetchAt;
  final String? status;
  final int programmeCount;
}

/// A guide channel as stored for matching and manual assignment.
class EpgChannelRow {
  const EpgChannelRow({
    required this.epgSourceId,
    required this.xmltvId,
    this.displayName,
    this.displayNamesNorm = const [],
    this.icon,
  });

  final int epgSourceId;
  final String xmltvId;
  final String? displayName;

  /// `normalizeForEpg` of each display name.
  final List<String> displayNamesNorm;
  final String? icon;
}

/// Identity fields of a channel used by the EPG matcher.
typedef ChannelIdentity = ({
  String key,
  String name,
  String? tvgId,
  String? tvgName,
});

/// Where a channel's guide comes from.
typedef EpgLink = ({int epgSourceId, String xmltvId, EpgMatchKind kind});

/// Current and next programme of one channel.
typedef NowNext = ({EpgProgramme? now, EpgProgramme? next});

// ---------------------------------------------------------------------------
// Record -> view.

extension SourceRecordView on SourceRecord {
  SourceRow toRow() => SourceRow(
    id: id,
    name: name,
    kind: kind,
    url: url,
    username: username,
    userAgent: userAgent,
    referer: referer,
    liveFormat: liveFormat,
    epgOffsetMin: epgOffsetMin,
    engineLive: engineLive,
    engineVod: engineVod,
    accountStatus: accountStatus,
    expiresAt: _fromEpochSecOrNull(expiresAt),
    maxConnections: maxConnections,
    allowedFormats: _decodeStringList(allowedFormatsJson),
    generation: generation,
    lastSyncAt: _fromEpochSecOrNull(lastSyncAt),
    lastEpgAt: _fromEpochSecOrNull(lastEpgAt),
    sortIndex: sortIndex,
  );
}

extension CategoryRecordView on CategoryRecord {
  CategoryRow toRow() => CategoryRow(
    kind: kind,
    key: key,
    name: name,
    sortIndex: sortIndex,
    itemCount: itemCount,
    hidden: hidden,
  );
}

extension ChannelRecordView on ChannelRecord {
  ChannelRow toRow() => ChannelRow(
    key: key,
    name: name,
    num: this.num,
    logo: logo,
    tvgId: tvgId,
    tvgName: tvgName,
    url: url,
    headers: decodeHeaders(headersJson),
    isRadio: isRadio,
    catchupMode: catchupMode,
    catchupDays: catchupDays,
    catchupSource: catchupSource,
    tvgShiftMin: tvgShiftMin,
  );
}

extension MovieRecordView on MovieRecord {
  MovieRow toRow() => MovieRow(
    key: key,
    name: name,
    poster: poster,
    year: year,
    rating: rating,
    ext: ext,
    url: url,
    headers: decodeHeaders(headersJson),
    addedAt: _fromEpochSecOrNull(addedAt),
  );
}

extension SeriesRecordView on SeriesRecord {
  SeriesRow toRow() => SeriesRow(
    key: key,
    name: name,
    poster: poster,
    year: year,
    rating: rating,
    plot: plot,
  );
}

extension EpisodeRecordView on EpisodeRecord {
  EpisodeRow toRow() => EpisodeRow(
    seriesKey: seriesKey,
    key: key,
    season: season,
    number: number,
    title: title,
    ext: ext,
    url: url,
    headers: decodeHeaders(headersJson),
    durationSec: durationSec,
    plot: plot,
    still: still,
  );
}

extension WatchProgressRecordView on WatchProgressRecord {
  ProgressRow toRow() => ProgressRow(
    kind: kind,
    key: key,
    seriesKey: seriesKey,
    position: Duration(milliseconds: positionMs),
    duration: Duration(milliseconds: durationMs),
    updatedAt: fromEpochSec(updatedAt),
    finished: finished,
  );
}

extension EpgSourceRecordView on EpgSourceRecord {
  EpgSourceRow toRow() => EpgSourceRow(
    id: id,
    sourceId: sourceId,
    url: url,
    origin: origin,
    enabled: enabled,
    priority: priority,
    etag: etag,
    lastModified: lastModified,
    lastFetchAt: _fromEpochSecOrNull(lastFetchAt),
    status: status,
    programmeCount: programmeCount,
  );
}

extension EpgChannelRecordView on EpgChannelRecord {
  EpgChannelRow toRow() => EpgChannelRow(
    epgSourceId: epgSourceId,
    xmltvId: xmltvId,
    displayName: displayName,
    displayNamesNorm: displayNamesNorm.isEmpty
        ? const []
        : displayNamesNorm.split('\n'),
    icon: icon,
  );
}

extension ProgrammeRecordView on ProgrammeRecord {
  EpgProgramme toProgramme() => EpgProgramme(
    channelId: xmltvId,
    start: fromEpochSec(startUtc),
    stop: fromEpochSec(stopUtc),
    // Stored guides may hold literal `\r\n` escapes.
    title: unescapeGuideText(title),
    subTitle: subTitle == null ? null : unescapeGuideText(subTitle!),
    desc: desc == null ? null : unescapeGuideText(desc!),
    category: category,
    icon: icon,
  );
}

// ---------------------------------------------------------------------------
// Model -> companion (catalog writes).

ChannelsCompanion channelCompanion(int sourceId, int gen, ChannelData c) =>
    ChannelsCompanion.insert(
      sourceId: sourceId,
      key: c.key,
      num: Value(c.num),
      name: c.name,
      nameNorm: normalizeForSearch(c.name),
      logo: Value(c.logo),
      tvgId: Value(c.tvgId),
      tvgName: Value(c.tvgName),
      url: Value(c.url),
      headersJson: Value(encodeHeaders(c.headers)),
      isRadio: Value(c.isRadio),
      catchupMode: Value(c.catchupMode),
      catchupDays: Value(c.catchupDays),
      catchupSource: Value(c.catchupSource),
      tvgShiftMin: Value(c.tvgShiftMin),
      generation: gen,
      firstGen: gen,
    );

MoviesCompanion movieCompanion(int sourceId, int gen, MovieData m) =>
    MoviesCompanion.insert(
      sourceId: sourceId,
      key: m.key,
      name: m.name,
      nameNorm: normalizeForSearch(m.name),
      poster: Value(m.poster),
      year: Value(m.year),
      rating: Value(m.rating),
      ext: Value(m.ext),
      url: Value(m.url),
      headersJson: Value(encodeHeaders(m.headers)),
      addedAt: Value(m.addedAt == null ? null : toEpochSec(m.addedAt!)),
      generation: gen,
      firstGen: gen,
    );

SeriesCompanion seriesCompanion(int sourceId, int gen, SeriesData s) =>
    SeriesCompanion.insert(
      sourceId: sourceId,
      key: s.key,
      name: s.name,
      nameNorm: normalizeForSearch(s.name),
      poster: Value(s.poster),
      year: Value(s.year),
      rating: Value(s.rating),
      plot: Value(s.plot),
      generation: gen,
      firstGen: gen,
    );

/// [gen] is null for lazily fetched episodes (kept across syncs).
EpisodesCompanion episodeCompanion(int sourceId, int? gen, EpisodeData e) =>
    EpisodesCompanion.insert(
      sourceId: sourceId,
      seriesKey: e.seriesKey,
      key: e.key,
      season: e.season,
      number: e.number,
      title: Value(e.title),
      ext: Value(e.ext),
      url: Value(e.url),
      headersJson: Value(encodeHeaders(e.headers)),
      durationSec: Value(e.durationSec),
      plot: Value(e.plot),
      still: Value(e.still),
      generation: Value(gen),
      firstGen: Value(gen),
    );

CategoriesCompanion categoryCompanion(int sourceId, int gen, CategoryData c) =>
    CategoriesCompanion.insert(
      sourceId: sourceId,
      kind: c.kind,
      key: c.key,
      name: c.name,
      nameNorm: normalizeForSearch(c.name),
      sortIndex: Value(c.sortIndex),
      generation: gen,
      firstGen: gen,
    );

ProgrammesCompanion programmeCompanion(int epgSourceId, EpgProgramme p) =>
    ProgrammesCompanion.insert(
      epgSourceId: epgSourceId,
      xmltvId: p.channelId,
      startUtc: toEpochSec(p.start),
      stopUtc: toEpochSec(p.stop),
      title: p.title,
      subTitle: Value(p.subTitle),
      desc: Value(p.desc),
      category: Value(p.category),
      icon: Value(p.icon),
    );

EpgChannelsCompanion epgChannelCompanion(int epgSourceId, EpgChannel c) {
  final norms = <String>{for (final n in c.displayNames) normalizeForEpg(n)}
    ..remove('');
  return EpgChannelsCompanion.insert(
    epgSourceId: epgSourceId,
    xmltvId: c.id,
    displayName: Value(c.displayNames.isEmpty ? null : c.displayNames.first),
    displayNamesNorm: norms.join('\n'),
    icon: Value(c.icon),
  );
}

// ---------------------------------------------------------------------------
// Detail cache JSON.

Map<String, Object?> movieDetailToJson(MovieDetail d) => {
  'key': d.key,
  'plot': d.plot,
  'cast': d.cast,
  'director': d.director,
  'genre': d.genre,
  'durationSec': d.durationSec,
  'backdrop': d.backdrop,
  'rating': d.rating,
  'releaseDate': d.releaseDate,
  'ext': d.ext,
};

MovieDetail movieDetailFromJson(Map<String, Object?> j) => MovieDetail(
  key: '${j['key']}',
  plot: j['plot'] as String?,
  cast: j['cast'] as String?,
  director: j['director'] as String?,
  genre: j['genre'] as String?,
  durationSec: (j['durationSec'] as num?)?.toInt(),
  backdrop: j['backdrop'] as String?,
  rating: (j['rating'] as num?)?.toDouble(),
  releaseDate: j['releaseDate'] as String?,
  ext: j['ext'] as String?,
);

Map<String, Object?> episodeToJson(EpisodeData e) => {
  'seriesKey': e.seriesKey,
  'key': e.key,
  'season': e.season,
  'number': e.number,
  'title': e.title,
  'ext': e.ext,
  'url': e.url,
  if (e.headers.isNotEmpty) 'headers': e.headers,
  'durationSec': e.durationSec,
  'plot': e.plot,
  'still': e.still,
};

EpisodeData episodeFromJson(Map<String, Object?> j) => EpisodeData(
  seriesKey: '${j['seriesKey']}',
  key: '${j['key']}',
  season: (j['season'] as num?)?.toInt() ?? 0,
  number: (j['number'] as num?)?.toInt() ?? 0,
  title: j['title'] as String?,
  ext: j['ext'] as String?,
  url: j['url'] as String?,
  headers: switch (j['headers']) {
    final Map<String, Object?> h => {
      for (final e in h.entries) e.key: '${e.value}',
    },
    _ => const {},
  },
  durationSec: (j['durationSec'] as num?)?.toInt(),
  plot: j['plot'] as String?,
  still: j['still'] as String?,
);

Map<String, Object?> seriesDetailToJson(SeriesDetail d) => {
  'key': d.key,
  'plot': d.plot,
  'cast': d.cast,
  'genre': d.genre,
  'backdrop': d.backdrop,
  'seasons': [
    for (final s in d.seasons)
      {'number': s.number, 'name': s.name, 'cover': s.cover},
  ],
  'episodes': [for (final e in d.episodes) episodeToJson(e)],
};

SeriesDetail seriesDetailFromJson(Map<String, Object?> j) => SeriesDetail(
  key: '${j['key']}',
  plot: j['plot'] as String?,
  cast: j['cast'] as String?,
  genre: j['genre'] as String?,
  backdrop: j['backdrop'] as String?,
  seasons: [
    for (final s in (j['seasons'] as List<Object?>? ?? const []))
      if (s is Map<String, Object?>)
        SeasonInfo(
          number: (s['number'] as num?)?.toInt() ?? 0,
          name: s['name'] as String?,
          cover: s['cover'] as String?,
        ),
  ],
  episodes: [
    for (final e in (j['episodes'] as List<Object?>? ?? const []))
      if (e is Map<String, Object?>) episodeFromJson(e),
  ],
);
