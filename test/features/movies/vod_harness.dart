// Shared helpers for the movie and series screen tests. All data is
// synthetic; nothing touches the network.
import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/app.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/core/platform/device_caps.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/epg/epg_providers.dart';
import 'package:iptv_player/features/vod_common/vod_providers.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/player/ui/play_request.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/sources/source_adapter.dart';
import 'package:iptv_player/tv/dpad_shortcuts.dart';
import 'package:iptv_player/tv/key_repeat.dart';
import 'package:iptv_player/widgets/logo_image.dart';

import '../../support/fake_epg_service.dart';

const tvCaps = DeviceCaps(uiModeTv: true, leanback: true, touch: false);
const phoneCaps = DeviceCaps();

final testEpoch = DateTime.utc(2026, 1, 10, 12);

final enL10n = lookupAppLocalizations(const Locale('en'));
final arL10n = lookupAppLocalizations(const Locale('ar'));

/// In-memory database with a controllable clock (progress order, cache age).
AppDatabase openVodDb(FakeClock clock) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory(), clock: clock);
}

Future<int> addM3uSource(AppDatabase db) => db.sourcesDao.create(
  const SourceConfig(
    kind: SourceKind.m3uUrl,
    url: 'http://127.0.0.1:9/list.m3u',
    name: 'Playlist',
  ),
);

Future<int> addXtreamSource(AppDatabase db) => db.sourcesDao.create(
  const SourceConfig(
    kind: SourceKind.xtream,
    url: 'http://127.0.0.1:9',
    name: 'Panel',
    username: 'tester',
    password: 'secret-pass',
  ),
);

/// Writes one committed catalog generation.
Future<void> seedCatalog(
  AppDatabase db,
  int sourceId, {
  List<CategoryData> categories = const [],
  List<MovieData> movies = const [],
  List<SeriesData> series = const [],
  List<EpisodeData> episodes = const [],
}) async {
  final dao = db.catalogDao;
  final gen = await dao.beginGeneration(sourceId);
  await dao.upsertCategories(sourceId, gen, categories);
  for (var i = 0; i < movies.length; i += 2000) {
    await dao.upsertMovies(
      sourceId,
      gen,
      movies.sublist(i, (i + 2000).clamp(0, movies.length)),
    );
  }
  await dao.upsertSeries(sourceId, gen, series);
  await dao.upsertEpisodes(sourceId, gen, episodes);
  await dao.commitGeneration(sourceId, gen);
}

/// `count` movies named "Movie 000"... in [category].
List<MovieData> movies(
  int count, {
  String category = 'action',
  String prefix = 'm',
  String name = 'Movie',
}) => [
  for (var i = 0; i < count; i++)
    MovieData(
      key: '$prefix${i.toString().padLeft(3, '0')}',
      name: '$name ${i.toString().padLeft(3, '0')}',
      ext: 'mkv',
      year: 2020,
      categoryKeys: [category],
    ),
];

/// Records the pages the browser grids read, and can fail some of them.
class SpyCatalogDao extends CatalogDao {
  SpyCatalogDao(super.attachedDatabase);

  /// Offsets read by category (null: All).
  final movieReads = <(String?, int)>[];

  /// Throws for these offsets while set.
  bool Function(int offset)? failMovies;

  void _record(String? category, int offset) {
    movieReads.add((category, offset));
    if (failMovies?.call(offset) ?? false) {
      throw StateError('disk I/O error');
    }
  }

  /// Offsets read in [category] (null: All).
  List<int> movieOffsets(String? category) => [
    for (final (c, o) in movieReads)
      if (c == category) o,
  ];

  @override
  Future<List<MovieRow>> moviesPage(
    int sourceId,
    String categoryKey,
    int offset,
    int limit,
  ) async {
    _record(categoryKey, offset);
    return super.moviesPage(sourceId, categoryKey, offset, limit);
  }

  @override
  Future<List<MovieRow>> allMoviesPage(
    int sourceId,
    int offset,
    int limit,
  ) async {
    _record(null, offset);
    return super.allMoviesPage(sourceId, offset, limit);
  }
}

/// Records what the screens ask the player to play.
class PlayRecorder {
  final requests = <PlayRequest>[];

  PlayRequest get last => requests.last;

  Future<void> call(BuildContext context, PlayRequest request) async =>
      requests.add(request);
}

/// A scriptable adapter for lazy details; counts calls.
class FakeVodAdapter implements SourceAdapter {
  FakeVodAdapter({this.onMovie, this.onSeries});

  Future<MovieDetail?> Function(String key)? onMovie;
  Future<SeriesDetail> Function(String key)? onSeries;
  final movieCalls = <String>[];
  final seriesCalls = <String>[];
  int closed = 0;

  @override
  SourceCapabilities get caps =>
      const SourceCapabilities(movies: true, series: true);

  @override
  Future<AccountInfo> verify() async => const AccountInfo();

  @override
  Stream<SyncBatch> fetchCatalog([SyncScope scope = SyncScope.all]) =>
      const Stream.empty();

  @override
  Future<MovieDetail?> movieDetail(String movieKey) {
    movieCalls.add(movieKey);
    final handler = onMovie;
    return handler == null ? Future.value() : handler(movieKey);
  }

  @override
  Future<SeriesDetail> seriesDetail(String seriesKey) {
    seriesCalls.add(seriesKey);
    final handler = onSeries;
    return handler == null
        ? Future.error(const ParseFailure('no details'))
        : handler(seriesKey);
  }

  @override
  StreamRequest resolve(PlayableRef ref, {Duration? startAt}) =>
      StreamRequest(url: 'http://127.0.0.1:9/${ref.key}', kind: ref.kind);

  @override
  List<EpgSourceSpec> epgSpecs() => const [];

  @override
  void close() => closed++;
}

/// Pumps the real app (shells, routes) on [db] with the VOD seams faked.
///
/// [desktop] runs it as a Windows window (large layout, mouse).
Future<void> pumpVodApp(
  WidgetTester tester, {
  required AppDatabase db,
  bool tv = true,
  bool desktop = false,
  bool rtl = false,
  Size? phoneSize,
  PlayRecorder? player,
  FakeVodAdapter? adapter,
  List<Override> overrides = const [],
}) async {
  final isTv = tv && !desktop;
  final size = isTv
      ? const Size(960, 540)
      : desktop
      ? const Size(1280, 800)
      : (phoneSize ?? const Size(390, 800));
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  addTearDown(() => applyFocusHighlightStrategy(tv: false));
  final caps = isTv ? tvCaps : phoneCaps;
  KeyRepeatThrottle.instance = KeyRepeatThrottle();
  FailedImageCache.clear();
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceCapsProvider.overrideWithValue(caps),
        initialSettingsProvider.overrideWithValue(
          AppSettings(locale: rtl ? AppLocaleSetting.ar : AppLocaleSetting.en),
        ),
        ringLogProvider.overrideWithValue(RingLog()),
        autoSyncOnStartProvider.overrideWithValue(false),
        // No guide downloads: the schedule in IptvApp is always alive.
        epgServiceProvider.overrideWithValue(FakeEpgService()),
        vodPlayerLauncherProvider.overrideWithValue(
          (player ?? PlayRecorder()).call,
        ),
        vodAdapterLoaderProvider.overrideWithValue((sourceId) async {
          final a = adapter;
          if (a == null) throw StateError('no adapter expected');
          return a;
        }),
        if (desktop)
          targetPlatformProvider.overrideWithValue(TargetPlatform.windows),
        ...overrides,
      ],
      child: const IptvApp(),
    ),
  );
  await settle(tester);
}

/// Lets drift streams deliver, debounce timers fire and frames settle.
Future<void> settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Unmounts the app and closes [db].
Future<void> disposeVodApp(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  await db.close();
}

/// Presses [key] and lets frames settle.
Future<void> press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  int frames = 8,
}) async {
  await tester.sendKeyEvent(key);
  await settle(tester, frames: frames);
}

/// Presses [key] [times] times.
Future<void> pressN(
  WidgetTester tester,
  LogicalKeyboardKey key,
  int times,
) async {
  for (var i = 0; i < times; i++) {
    await press(tester, key);
  }
}

/// Whether the primary focus is the widget with [key] or inside it.
bool focusedIn(Key key) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  if (ctx.widget.key == key) return true;
  var found = false;
  ctx.visitAncestorElements((e) {
    if (e.widget.key == key) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// A description of the focused widget for failure messages.
String describeFocus() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return 'no focus';
  final keys = <String>[];
  ctx.visitAncestorElements((e) {
    final k = e.widget.key;
    if (k is ValueKey) keys.add('${k.value}');
    return keys.length < 3;
  });
  return '${FocusManager.instance.primaryFocus} in $keys';
}

/// Arrow toward the content (end side) and toward the rail (start side).
LogicalKeyboardKey toEnd(bool rtl) =>
    rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight;
LogicalKeyboardKey toStart(bool rtl) =>
    rtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft;

/// Moves rail focus from Live down to [index] (Live 0, Guide 1, Movies 2,
/// Series 3) and enters the page.
Future<void> openTabFromRail(
  WidgetTester tester,
  int index, {
  required bool rtl,
}) async {
  await pressN(tester, LogicalKeyboardKey.arrowDown, index);
  await press(tester, toEnd(rtl));
}
