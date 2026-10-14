// Drift schema v1. Times are epoch seconds UTC; enums are stored by name.
//
// Catalog tables (categories, category_items, channels, movies, series,
// episodes) carry `generation` and `firstGen` for the generation swap done by
// `CatalogDao`. User data (favorites, watch_progress, channel_prefs,
// recent_channels, channel_epg_map) is keyed by stable item keys, never by
// row ids, and is never touched by a sync.
import 'package:drift/drift.dart';

import '../../player/engine/player_engine.dart';
import '../../sources/models.dart';

/// How a channel was linked to a guide channel. A manual link always wins.
enum EpgMatchKind { tvgId, tvgName, name, manual }

/// Saved playlists and Xtream accounts. Passwords live in [Secrets].
@DataClassName('SourceRecord')
class Sources extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get kind => textEnum<SourceKind>()();

  /// Playlist URL, app-private file path or Xtream base URL, with any
  /// credentials masked (the full URL is then in [Secrets]).
  TextColumn get url => text()();
  TextColumn get username => text().nullable()();
  TextColumn get userAgent => text().nullable()();
  TextColumn get referer => text().nullable()();
  TextColumn get liveFormat =>
      textEnum<LiveFormat>().withDefault(const Constant('ts'))();
  IntColumn get epgOffsetMin => integer().withDefault(const Constant(0))();
  TextColumn get engineLive => textEnum<EngineKind>().nullable()();
  TextColumn get engineVod => textEnum<EngineKind>().nullable()();
  TextColumn get accountStatus =>
      textEnum<AccountStatus>().withDefault(const Constant('unknown'))();
  IntColumn get expiresAt => integer().nullable()();
  IntColumn get maxConnections => integer().nullable()();
  TextColumn get allowedFormatsJson => text().nullable()();

  /// Last committed catalog generation (0 = never synced).
  IntColumn get generation => integer().withDefault(const Constant(0))();

  /// Generation a sync is writing, or null. Only this one accepts writes.
  IntColumn get openGeneration => integer().nullable()();

  /// Highest generation ever handed out; numbers are never reused, so a
  /// stale or aborted writer can never match a later sync.
  IntColumn get lastGeneration => integer().withDefault(const Constant(0))();
  IntColumn get lastSyncAt => integer().nullable()();
  IntColumn get lastEpgAt => integer().nullable()();
  IntColumn get sortIndex => integer().withDefault(const Constant(0))();
}

/// Credentials per source, read and written only through `SecretStore`.
@DataClassName('SecretRecord')
class Secrets extends Table {
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {sourceId, name};

  @override
  bool get withoutRowId => true;
}

@DataClassName('CategoryRecord')
class Categories extends Table {
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => textEnum<ContentKind>()();
  TextColumn get key => text()();
  TextColumn get name => text()();
  TextColumn get nameNorm => text()();
  IntColumn get sortIndex => integer().withDefault(const Constant(0))();

  /// Items in the committed generation; refreshed on commit.
  IntColumn get itemCount => integer().withDefault(const Constant(0))();

  /// User choice; kept across syncs while the category exists.
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();
  IntColumn get generation => integer()();

  /// Generation in which the row first appeared (abort removes only these).
  IntColumn get firstGen => integer()();

  @override
  Set<Column> get primaryKey => {sourceId, kind, key};
}

/// Membership of items in categories, with dense positions for range paging.
///
/// `generation` is part of the key so a sync can write the next generation's
/// positions next to the committed ones; the swap then drops the old rows.
@DataClassName('CategoryItemRecord')
@TableIndex(name: 'category_items_item', columns: {#sourceId, #kind, #itemKey})
class CategoryItems extends Table {
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  IntColumn get generation => integer()();
  TextColumn get kind => textEnum<ContentKind>()();
  TextColumn get categoryKey => text()();
  IntColumn get position => integer()();
  TextColumn get itemKey => text()();

  @override
  Set<Column> get primaryKey => {
    sourceId,
    generation,
    kind,
    categoryKey,
    position,
  };

  @override
  bool get withoutRowId => true;
}

@DataClassName('ChannelRecord')
@TableIndex(name: 'channels_num', columns: {#sourceId, #num, #nameNorm, #key})
@TableIndex(name: 'channels_tvg_id', columns: {#tvgId})
class Channels extends Table {
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get key => text()();
  IntColumn get num => integer().nullable()();
  TextColumn get name => text()();
  TextColumn get nameNorm => text()();
  TextColumn get logo => text().nullable()();
  TextColumn get tvgId => text().nullable()();
  TextColumn get tvgName => text().nullable()();

  /// M3U only; Xtream URLs are built at play time.
  TextColumn get url => text().nullable()();
  TextColumn get headersJson => text().nullable()();
  BoolColumn get isRadio => boolean().withDefault(const Constant(false))();
  TextColumn get catchupMode => text().nullable()();
  IntColumn get catchupDays => integer().withDefault(const Constant(0))();
  TextColumn get catchupSource => text().nullable()();
  IntColumn get tvgShiftMin => integer().withDefault(const Constant(0))();
  IntColumn get generation => integer()();
  IntColumn get firstGen => integer()();

  @override
  Set<Column> get primaryKey => {sourceId, key};
}

@DataClassName('MovieRecord')
@TableIndex(name: 'movies_name', columns: {#sourceId, #nameNorm, #key})
class Movies extends Table {
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get key => text()();
  TextColumn get name => text()();
  TextColumn get nameNorm => text()();
  TextColumn get poster => text().nullable()();
  IntColumn get year => integer().nullable()();
  RealColumn get rating => real().nullable()();
  TextColumn get ext => text().nullable()();
  TextColumn get url => text().nullable()();
  TextColumn get headersJson => text().nullable()();
  IntColumn get addedAt => integer().nullable()();
  IntColumn get generation => integer()();
  IntColumn get firstGen => integer()();

  @override
  Set<Column> get primaryKey => {sourceId, key};
}

@DataClassName('SeriesRecord')
@TableIndex(name: 'series_name', columns: {#sourceId, #nameNorm, #key})
class Series extends Table {
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get key => text()();
  TextColumn get name => text()();
  TextColumn get nameNorm => text()();
  TextColumn get poster => text().nullable()();
  IntColumn get year => integer().nullable()();
  RealColumn get rating => real().nullable()();
  TextColumn get plot => text().nullable()();
  IntColumn get generation => integer()();
  IntColumn get firstGen => integer()();

  @override
  Set<Column> get primaryKey => {sourceId, key};
}

/// M3U fills episodes during sync (with a generation). Xtream episodes are
/// fetched lazily per series and have a null generation: the swap keeps them
/// until their series disappears.
@DataClassName('EpisodeRecord')
@TableIndex(
  name: 'episodes_series',
  columns: {#sourceId, #seriesKey, #season, #number},
)
class Episodes extends Table {
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get seriesKey => text()();
  TextColumn get key => text()();
  IntColumn get season => integer()();
  IntColumn get number => integer()();
  TextColumn get title => text().nullable()();
  TextColumn get ext => text().nullable()();
  TextColumn get url => text().nullable()();
  TextColumn get headersJson => text().nullable()();
  IntColumn get durationSec => integer().nullable()();
  TextColumn get plot => text().nullable()();
  TextColumn get still => text().nullable()();
  IntColumn get generation => integer().nullable()();
  IntColumn get firstGen => integer().nullable()();

  @override
  Set<Column> get primaryKey => {sourceId, key};
}

/// Lazily fetched details (`get_vod_info`, `get_series_info`), 24 h TTL.
@DataClassName('DetailCacheRecord')
class DetailCache extends Table {
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => textEnum<ContentKind>()();
  TextColumn get key => text()();
  TextColumn get json => text()();
  IntColumn get fetchedAt => integer()();

  @override
  Set<Column> get primaryKey => {sourceId, kind, key};

  @override
  bool get withoutRowId => true;
}

@DataClassName('EpgSourceRecord')
@TableIndex(name: 'epg_sources_url', columns: {#sourceId, #url}, unique: true)
class EpgSources extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();

  /// Guide URL with credentials masked (the full URL is then in [Secrets]).
  TextColumn get url => text()();
  TextColumn get origin => textEnum<EpgOrigin>()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get etag => text().nullable()();
  TextColumn get lastModified => text().nullable()();
  IntColumn get lastFetchAt => integer().nullable()();
  TextColumn get status => text().nullable()();
  IntColumn get programmeCount => integer().withDefault(const Constant(0))();
}

@DataClassName('EpgChannelRecord')
class EpgChannels extends Table {
  IntColumn get epgSourceId =>
      integer().references(EpgSources, #id, onDelete: KeyAction.cascade)();
  TextColumn get xmltvId => text()();

  /// First display name as published, for pickers.
  TextColumn get displayName => text().nullable()();

  /// `normalizeForEpg` of every display name, newline separated.
  TextColumn get displayNamesNorm => text()();
  TextColumn get icon => text().nullable()();

  @override
  Set<Column> get primaryKey => {epgSourceId, xmltvId};

  @override
  bool get withoutRowId => true;
}

/// Guide entries. The key also drops SD/HD duplicates sharing an id.
///
/// Times are as published (plus the source's user offset). A playlist
/// channel's `tvg-shift` is applied when reading, so a "+1" channel can share
/// a guide id with its original.
@DataClassName('ProgrammeRecord')
class Programmes extends Table {
  IntColumn get epgSourceId =>
      integer().references(EpgSources, #id, onDelete: KeyAction.cascade)();
  TextColumn get xmltvId => text()();
  IntColumn get startUtc => integer()();
  IntColumn get stopUtc => integer()();
  TextColumn get title => text()();
  TextColumn get subTitle => text().nullable()();
  TextColumn get desc => text().named('description').nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get icon => text().nullable()();

  @override
  Set<Column> get primaryKey => {epgSourceId, xmltvId, startUtc};

  @override
  bool get withoutRowId => true;
}

@DataClassName('ChannelEpgMapRecord')
@TableIndex(name: 'channel_epg_map_guide', columns: {#epgSourceId, #xmltvId})
class ChannelEpgMap extends Table {
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get channelKey => text()();
  IntColumn get epgSourceId =>
      integer().references(EpgSources, #id, onDelete: KeyAction.cascade)();
  TextColumn get xmltvId => text()();
  TextColumn get matchKind => textEnum<EpgMatchKind>()();

  @override
  Set<Column> get primaryKey => {sourceId, channelKey};

  @override
  bool get withoutRowId => true;
}

@DataClassName('ChannelPrefRecord')
class ChannelPrefs extends Table {
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get channelKey => text()();
  TextColumn get engine => textEnum<EngineKind>().nullable()();
  TextColumn get aspect => textEnum<AspectMode>().nullable()();
  TextColumn get audioLang => text().nullable()();

  @override
  Set<Column> get primaryKey => {sourceId, channelKey};

  @override
  bool get withoutRowId => true;
}

@DataClassName('FavoriteRecord')
class Favorites extends Table {
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => textEnum<ContentKind>()();
  TextColumn get key => text()();
  IntColumn get addedAt => integer()();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {sourceId, kind, key};
}

@DataClassName('WatchProgressRecord')
@TableIndex(name: 'watch_progress_updated', columns: {#sourceId, #updatedAt})
class WatchProgress extends Table {
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();

  /// [PlayableKind.movie] or [PlayableKind.episode].
  TextColumn get kind => textEnum<PlayableKind>()();
  TextColumn get key => text()();
  TextColumn get seriesKey => text().nullable()();
  IntColumn get positionMs => integer()();
  IntColumn get durationMs => integer()();
  IntColumn get updatedAt => integer()();
  BoolColumn get finished => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {sourceId, kind, key};
}

@DataClassName('RecentChannelRecord')
@TableIndex(name: 'recent_channels_time', columns: {#sourceId, #lastWatchedAt})
class RecentChannels extends Table {
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get key => text()();
  IntColumn get lastWatchedAt => integer()();

  @override
  Set<Column> get primaryKey => {sourceId, key};
}

/// App settings as JSON values.
@DataClassName('SettingRecord')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get json => text()();

  @override
  Set<Column> get primaryKey => {key};

  @override
  bool get withoutRowId => true;
}
