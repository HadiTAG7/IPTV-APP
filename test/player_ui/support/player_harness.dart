// Pumps the fullscreen player on an in-memory database with fake engines.
// All data is synthetic (127.0.0.1 URLs, made-up names).
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
import 'package:iptv_player/epg/epg_models.dart';
import 'package:iptv_player/features/diagnostics/providers.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/player/player_providers.dart';
import 'package:iptv_player/player/ui/play_request.dart';
import 'package:iptv_player/player/ui/player_route.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/theme/app_theme.dart';
import 'package:iptv_player/tv/dpad_shortcuts.dart';
import 'package:iptv_player/tv/key_repeat.dart';
import 'package:iptv_player/widgets/logo_image.dart';

import '../../support/fake_engine.dart';

const tvCaps = DeviceCaps(uiModeTv: true, leanback: true, touch: false);
const phoneCaps = DeviceCaps();
const en = Locale('en');
const ar = Locale('ar');

/// Everything a player test needs: database, fake engines and recorders.
class PlayerRig {
  PlayerRig({DateTime? now})
    : clock = FakeClock(now ?? DateTime.utc(2026, 3, 1, 20, 30)) {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory(), clock: clock);
  }

  final FakeClock clock;
  late final AppDatabase db;
  final engines = FakeEngineFactory();
  final log = RingLog();
  final wakelock = <bool>[];
  final played = <(int, String)>[];

  /// Platform calls (SystemChrome, Clipboard...).
  final platformCalls = <MethodCall>[];

  /// Text put on the clipboard.
  String? clipboard;

  /// Every engine shows a first frame when opened (playing at once).
  void autoPlay({Duration? duration}) {
    engines.onCreate = (e) => e.onOpen = (e, _) {
      if (duration != null) e.setState(duration: duration);
      e.emitFirstFrame();
    };
  }

  FakeEngine get engine => engines.last;

  /// All stream URLs opened so far, in order.
  List<String> get openedUrls => [
    for (final e in engines.created)
      for (final r in e.opened) r.url,
  ];

  List<MethodCall> callsOf(String method) =>
      platformCalls.where((c) => c.method == method).toList();
}

/// An M3U source with [count] live channels `ch1..chN` in category `news`.
Future<int> seedLive(
  PlayerRig rig, {
  int count = 5,
  bool numbered = true,
}) async {
  final db = rig.db;
  final id = await db.sourcesDao.create(
    const SourceConfig(
      kind: SourceKind.m3uUrl,
      url: 'http://127.0.0.1:9/list.m3u',
      name: 'Home',
    ),
  );
  final gen = await db.catalogDao.beginGeneration(id);
  await db.catalogDao.upsertCategories(id, gen, const [
    CategoryData(kind: ContentKind.live, key: 'news', name: 'News'),
  ]);
  await db.catalogDao.upsertChannels(id, gen, [
    for (var i = 1; i <= count; i++)
      ChannelData(
        key: 'ch$i',
        name: 'Channel $i',
        num: numbered ? 100 + i : null,
        url: 'http://127.0.0.1:9/live/ch$i.ts',
        categoryKeys: const ['news'],
      ),
  ]);
  await db.catalogDao.commitGeneration(id, gen);
  return id;
}

/// Adds a guide with one current and one next programme for `ch1`.
Future<void> seedGuide(PlayerRig rig, int sourceId) async {
  final db = rig.db;
  final epg = await db.epgDao.addEpgSource(
    sourceId,
    'http://127.0.0.1:9/guide.xml',
    EpgOrigin.manual,
  );
  final now = rig.clock.now();
  await db.epgDao.insertProgrammes(epg, [
    EpgProgramme(
      channelId: 'one',
      start: now.subtract(const Duration(minutes: 30)),
      stop: now.add(const Duration(minutes: 30)),
      title: 'Evening News',
    ),
    EpgProgramme(
      channelId: 'one',
      start: now.add(const Duration(minutes: 30)),
      stop: now.add(const Duration(minutes: 90)),
      title: 'Late Show',
    ),
  ]);
  await db.epgDao.setManualLink(sourceId, 'ch1', epg, 'one');
}

/// An M3U source with one movie and a series of three episodes.
Future<int> seedVod(PlayerRig rig) async {
  final db = rig.db;
  final id = await db.sourcesDao.create(
    const SourceConfig(
      kind: SourceKind.m3uUrl,
      url: 'http://127.0.0.1:9/vod.m3u',
      name: 'Films',
    ),
  );
  final gen = await db.catalogDao.beginGeneration(id);
  await db.catalogDao.upsertCategories(id, gen, const [
    CategoryData(kind: ContentKind.movie, key: 'films', name: 'Films'),
    CategoryData(kind: ContentKind.series, key: 'shows', name: 'Shows'),
  ]);
  await db.catalogDao.upsertMovies(id, gen, const [
    MovieData(
      key: 'm1',
      name: 'Test Movie',
      ext: 'mp4',
      url: 'http://127.0.0.1:9/movie/m1.mp4',
      categoryKeys: ['films'],
    ),
  ]);
  await db.catalogDao.upsertSeries(id, gen, const [
    SeriesData(key: 's1', name: 'Test Show', categoryKeys: ['shows']),
  ]);
  await db.catalogDao.upsertEpisodes(id, gen, [
    for (var i = 1; i <= 3; i++)
      EpisodeData(
        seriesKey: 's1',
        key: 'e$i',
        season: 1,
        number: i,
        title: 'Episode title $i',
        ext: 'mp4',
        url: 'http://127.0.0.1:9/series/e$i.mp4',
      ),
  ]);
  await db.catalogDao.commitGeneration(id, gen);
  return id;
}

/// An Xtream source (password in the secret store) with live channel 501.
Future<int> seedXtream(PlayerRig rig) async {
  final db = rig.db;
  final id = await db.sourcesDao.create(
    const SourceConfig(
      kind: SourceKind.xtream,
      url: 'http://127.0.0.1:9',
      name: 'Panel',
      username: 'viewer7',
      password: 'Secret-Pass-9',
    ),
  );
  await db.sourcesDao.updateAccount(
    id,
    const AccountInfo(maxConnections: 1, allowedFormats: ['ts', 'm3u8']),
  );
  final gen = await db.catalogDao.beginGeneration(id);
  await db.catalogDao.upsertCategories(id, gen, const [
    CategoryData(kind: ContentKind.live, key: '1', name: 'News'),
  ]);
  await db.catalogDao.upsertChannels(id, gen, const [
    ChannelData(key: '501', name: 'Panel News', num: 1, categoryKeys: ['1']),
    ChannelData(key: '502', name: 'Panel Sport', num: 2, categoryKeys: ['1']),
  ]);
  await db.catalogDao.commitGeneration(id, gen);
  return id;
}

PlayRequest liveRequest(int sourceId, {String key = 'ch1', String? category}) =>
    PlayRequest(
      sourceId: sourceId,
      item: PlayableRef(
        kind: PlayableKind.live,
        key: key,
        url: 'http://127.0.0.1:9/live/$key.ts',
        title: 'Channel ${key.substring(2)}',
      ),
      categoryKey: category ?? 'news',
    );

/// A live request for a channel of [seedXtream] (no stored URL: the
/// adapter builds it).
PlayRequest xtreamRequest(int sourceId, String key) => PlayRequest(
  sourceId: sourceId,
  item: PlayableRef(kind: PlayableKind.live, key: key),
  categoryKey: '1',
);

PlayRequest movieRequest(int sourceId, {Duration? startAt}) => PlayRequest(
  sourceId: sourceId,
  item: const PlayableRef(
    kind: PlayableKind.movie,
    key: 'm1',
    url: 'http://127.0.0.1:9/movie/m1.mp4',
    ext: 'mp4',
    title: 'Test Movie',
  ),
  startAt: startAt,
);

PlayRequest episodeRequest(int sourceId, {String key = 'e1'}) => PlayRequest(
  sourceId: sourceId,
  item: PlayableRef(
    kind: PlayableKind.episode,
    key: key,
    url: 'http://127.0.0.1:9/series/$key.mp4',
    ext: 'mp4',
    title: 'Episode title ${key.substring(1)}',
  ),
  seriesKey: 's1',
);

/// Key of the launcher page that opens the player.
const launcherKey = ValueKey('launcher');

/// Pumps the app frame with a launcher page; [open] pushes the player.
Future<void> pumpPlayerApp(
  WidgetTester tester,
  PlayerRig rig, {
  bool tv = true,
  Locale locale = en,
  AppSettings settings = const AppSettings(),
  TargetPlatform platform = TargetPlatform.android,
  List<Override> overrides = const [],
}) async {
  final size = tv ? const Size(960, 540) : const Size(390, 800);
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  addTearDown(() => applyFocusHighlightStrategy(tv: false));
  KeyRepeatThrottle.instance = KeyRepeatThrottle(clock: rig.clock);
  FailedImageCache.clear();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      rig.platformCalls.add(call);
      if (call.method == 'Clipboard.setData') {
        rig.clipboard = (call.arguments as Map)['text'] as String?;
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(rig.db),
        deviceCapsProvider.overrideWithValue(tv ? tvCaps : phoneCaps),
        initialSettingsProvider.overrideWithValue(settings),
        ringLogProvider.overrideWithValue(rig.log),
        clockProvider.overrideWithValue(rig.clock),
        targetPlatformProvider.overrideWithValue(platform),
        engineFactoryBuilderProvider.overrideWithValue((_) => rig.engines.call),
        playerWakelockProvider.overrideWithValue(rig.wakelock.add),
        onChannelPlayedProvider.overrideWithValue(
          (sourceId, key) async => rig.played.add((sourceId, key)),
        ),
        appVersionProvider.overrideWith((ref) async => '0.1.0+1'),
        ...overrides,
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          navigatorKey: ref.watch(navigatorKeyProvider),
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(tv: tv),
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          shortcuts: appShortcuts,
          builder: (context, child) =>
              AppFrame(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(
            key: launcherKey,
            body: Center(child: Text('launcher')),
          ),
        ),
      ),
    ),
  );
  await settle(tester);
}

/// Pushes the player for [request]; returns when the route is shown. The
/// result completes when the player closes.
Future<Future<void>> openPlayerFor(
  WidgetTester tester,
  PlayRequest request,
) async {
  final closed = openPlayer(tester.element(find.byKey(launcherKey)), request);
  await settle(tester);
  return Future.value(closed);
}

/// Lets drift futures complete and frames settle (fake time moves 250 ms).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets real async work (drift on a background thread) finish.
Future<void> flushDb(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

/// Presses [key] and lets frames settle.
Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await settle(tester);
}

/// Unmounts everything (disposing the controller) and closes the database.
Future<void> disposeRig(WidgetTester tester, PlayerRig rig) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  await rig.db.close();
}

/// Whether the primary focus is inside the widget with [key].
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

/// The primary focus node's debug label.
String? get focusLabel => FocusManager.instance.primaryFocus?.debugLabel;

/// Aspect of the fake engine view on screen, from its key.
AspectMode? shownAspect(WidgetTester tester) {
  for (final mode in AspectMode.values) {
    for (final kind in EngineKind.values) {
      if (find
          .byKey(ValueKey('fake-${kind.name}-${mode.name}'))
          .evaluate()
          .isNotEmpty) {
        return mode;
      }
    }
  }
  return null;
}

/// Runs [body] for both locales.
void forLocales(void Function(Locale locale) body) {
  for (final l in const [en, ar]) {
    body(l);
  }
}

/// Unawaited helper for futures the test does not wait on.
void ignore(Future<void> f) => unawaited(f);
