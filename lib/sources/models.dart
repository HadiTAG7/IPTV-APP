// Domain models shared by source adapters, sync, storage and UI.
//
// Pure Dart: no Flutter, no dart:io, no database types. Adapters produce these
// values; the sync service maps them into database rows.

/// How a saved source gets its catalog.
enum SourceKind { m3uUrl, m3uFile, xtream }

/// Top level content families.
enum ContentKind { live, movie, series }

/// Kind of item handed to the player.
enum PlayableKind { live, movie, episode }

/// Live output container for Xtream panels.
enum LiveFormat { ts, m3u8 }

/// Everything needed to talk to one saved source.
///
/// [url] means: the playlist URL for [SourceKind.m3uUrl], the local file path
/// (app-private copy) for [SourceKind.m3uFile], or the base URL
/// (`scheme://host:port`) for [SourceKind.xtream].
class SourceConfig {
  const SourceConfig({
    required this.kind,
    required this.url,
    this.id,
    this.name = '',
    this.username,
    this.password,
    this.userAgent,
    this.referer,
    this.liveFormat = LiveFormat.ts,
    this.epgOffsetMin = 0,
  });

  final int? id;
  final String name;
  final SourceKind kind;
  final String url;
  final String? username;
  final String? password;
  final String? userAgent;
  final String? referer;
  final LiveFormat liveFormat;
  final int epgOffsetMin;

  SourceConfig copyWith({
    int? id,
    String? name,
    String? url,
    String? username,
    String? password,
    String? userAgent,
    String? referer,
    LiveFormat? liveFormat,
    int? epgOffsetMin,
  }) => SourceConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind,
    url: url ?? this.url,
    username: username ?? this.username,
    password: password ?? this.password,
    userAgent: userAgent ?? this.userAgent,
    referer: referer ?? this.referer,
    liveFormat: liveFormat ?? this.liveFormat,
    epgOffsetMin: epgOffsetMin ?? this.epgOffsetMin,
  );
}

/// Account state reported by [SourceAdapter.verify].
enum AccountStatus { active, expired, banned, disabled, unknown }

class AccountInfo {
  const AccountInfo({
    this.status = AccountStatus.active,
    this.expiresAt,
    this.maxConnections,
    this.activeConnections,
    this.allowedFormats = const [],
    this.isTrial = false,
    this.serverTimezone,
  });

  final AccountStatus status;

  /// Null means it never expires (or unknown).
  final DateTime? expiresAt;
  final int? maxConnections;
  final int? activeConnections;
  final List<String> allowedFormats;
  final bool isTrial;
  final String? serverTimezone;
}

class CategoryData {
  const CategoryData({
    required this.kind,
    required this.key,
    required this.name,
    this.sortIndex = 0,
  });

  final ContentKind kind;
  final String key;
  final String name;
  final int sortIndex;
}

class ChannelData {
  const ChannelData({
    required this.key,
    required this.name,
    this.num,
    this.logo,
    this.tvgId,
    this.tvgName,
    this.url,
    this.headers = const {},
    this.isRadio = false,
    this.categoryKeys = const [],
    this.catchupMode,
    this.catchupDays = 0,
    this.catchupSource,
    this.tvgShiftMin = 0,
  });

  /// Stable key: Xtream `stream_id`, or for M3U the URL without query.
  final String key;
  final String name;
  final int? num;
  final String? logo;
  final String? tvgId;
  final String? tvgName;

  /// Direct stream URL (M3U only). Xtream builds URLs at play time.
  final String? url;
  final Map<String, String> headers;
  final bool isRadio;
  final List<String> categoryKeys;
  final String? catchupMode;
  final int catchupDays;
  final String? catchupSource;
  final int tvgShiftMin;
}

class MovieData {
  const MovieData({
    required this.key,
    required this.name,
    this.poster,
    this.year,
    this.rating,
    this.ext,
    this.url,
    this.headers = const {},
    this.categoryKeys = const [],
    this.addedAt,
  });

  final String key;
  final String name;
  final String? poster;
  final int? year;
  final double? rating;

  /// Container extension, e.g. `mkv` (Xtream `container_extension`).
  final String? ext;
  final String? url;
  final Map<String, String> headers;
  final List<String> categoryKeys;
  final DateTime? addedAt;
}

class SeriesData {
  const SeriesData({
    required this.key,
    required this.name,
    this.poster,
    this.year,
    this.rating,
    this.plot,
    this.categoryKeys = const [],
  });

  final String key;
  final String name;
  final String? poster;
  final int? year;
  final double? rating;
  final String? plot;
  final List<String> categoryKeys;
}

class EpisodeData {
  const EpisodeData({
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
}

class SeasonInfo {
  const SeasonInfo({required this.number, this.name, this.cover});

  final int number;
  final String? name;
  final String? cover;
}

class MovieDetail {
  const MovieDetail({
    required this.key,
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.durationSec,
    this.backdrop,
    this.rating,
    this.releaseDate,
    this.ext,
  });

  final String key;
  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final int? durationSec;
  final String? backdrop;
  final double? rating;
  final String? releaseDate;
  final String? ext;
}

class SeriesDetail {
  const SeriesDetail({
    required this.key,
    this.plot,
    this.cast,
    this.genre,
    this.backdrop,
    this.seasons = const [],
    this.episodes = const [],
  });

  final String key;
  final String? plot;
  final String? cast;
  final String? genre;
  final String? backdrop;
  final List<SeasonInfo> seasons;
  final List<EpisodeData> episodes;
}

/// What the UI asks to play. Adapters turn it into a [StreamRequest].
class PlayableRef {
  const PlayableRef({
    required this.kind,
    required this.key,
    this.url,
    this.ext,
    this.headers = const {},
    this.title,
  });

  final PlayableKind kind;
  final String key;

  /// Stored direct URL (M3U), if any.
  final String? url;
  final String? ext;
  final Map<String, String> headers;
  final String? title;
}

/// A fully resolved request for a player engine.
class StreamRequest {
  const StreamRequest({
    required this.url,
    required this.kind,
    this.headers = const {},
    this.isHls = false,
    this.startAt,
    this.title,
  });

  final String url;
  final PlayableKind kind;
  final Map<String, String> headers;

  /// True when the URL is known to be HLS (`.m3u8`).
  final bool isHls;
  final Duration? startAt;
  final String? title;

  bool get isLive => kind == PlayableKind.live;

  StreamRequest copyWith({String? url, bool? isHls, Duration? startAt}) =>
      StreamRequest(
        url: url ?? this.url,
        kind: kind,
        headers: headers,
        isHls: isHls ?? this.isHls,
        startAt: startAt ?? this.startAt,
        title: title,
      );
}

/// Where an XMLTV guide comes from.
enum EpgOrigin { xtream, m3uHeader, manual }

class EpgSourceSpec {
  const EpgSourceSpec({required this.url, required this.origin});

  final String url;
  final EpgOrigin origin;
}

/// One batch emitted while fetching a catalog.
sealed class SyncBatch {
  const SyncBatch();
}

class CategoriesBatch extends SyncBatch {
  const CategoriesBatch(this.items);
  final List<CategoryData> items;
}

class ChannelsBatch extends SyncBatch {
  const ChannelsBatch(this.items);
  final List<ChannelData> items;
}

class MoviesBatch extends SyncBatch {
  const MoviesBatch(this.items);
  final List<MovieData> items;
}

class SeriesBatch extends SyncBatch {
  const SeriesBatch(this.items);
  final List<SeriesData> items;
}

class EpisodesBatch extends SyncBatch {
  const EpisodesBatch(this.items);
  final List<EpisodeData> items;
}

/// Guide URLs discovered while parsing (e.g. M3U `url-tvg`).
class EpgHintBatch extends SyncBatch {
  const EpgHintBatch(this.urls);
  final List<String> urls;
}

/// Marks the end of one content family so the UI can use it early.
class PhaseDoneBatch extends SyncBatch {
  const PhaseDoneBatch(this.kind);
  final ContentKind kind;
}

/// Which families a sync should fetch.
class SyncScope {
  const SyncScope({this.live = true, this.movies = true, this.series = true});

  static const all = SyncScope();
  final bool live;
  final bool movies;
  final bool series;
}

/// Typed failures from adapters. Messages never contain credentials.
sealed class SourceFailure implements Exception {
  const SourceFailure(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class NetworkFailure extends SourceFailure {
  const NetworkFailure(super.message, {this.statusCode});
  final int? statusCode;
}

class TimeoutFailure extends SourceFailure {
  const TimeoutFailure(super.message);
}

class AuthFailure extends SourceFailure {
  const AuthFailure(super.message, {this.status = AccountStatus.unknown});
  final AccountStatus status;
}

class ParseFailure extends SourceFailure {
  const ParseFailure(super.message);
}

class CancelledFailure extends SourceFailure {
  const CancelledFailure() : super('cancelled');
}

/// What an adapter can do.
class SourceCapabilities {
  const SourceCapabilities({
    this.live = true,
    this.movies = false,
    this.series = false,
    this.shortEpg = false,
    this.catchup = false,
  });

  final bool live;
  final bool movies;
  final bool series;
  final bool shortEpg;
  final bool catchup;
}
