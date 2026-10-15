// Shared seeding and pumping helpers for the Live, Favorites and Search
// widget tests. All names and URLs are synthetic.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/app.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/epg/epg_models.dart';
import 'package:iptv_player/epg/epg_providers.dart';
import 'package:iptv_player/features/live/live_actions.dart';
import 'package:iptv_player/player/ui/play_request.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/tv/dpad_shortcuts.dart';
import 'package:iptv_player/tv/key_repeat.dart';
import 'package:iptv_player/widgets/logo_image.dart';

import '../../../app/app_harness.dart';
import '../../../support/fake_epg_service.dart';

export '../../../app/app_harness.dart';

/// Logical TV size (1920x1080 at device pixel ratio 2).
const tvSize = Size(960, 540);

/// Logical phone size (portrait).
const phoneSize = Size(390, 800);

/// The guide's "now" in these tests.
final testNow = DateTime.utc(2026, 10, 15, 18, 10);

ChannelData testChannel(
  int n, {
  String? name,
  List<String> categories = const ['news'],
  bool numbered = true,
}) => ChannelData(
  key: 'k$n',
  name: name ?? 'Channel $n',
  num: numbered ? n : null,
  url: 'http://127.0.0.1:9/live/$n.ts',
  categoryKeys: categories,
);

/// Writes and commits one catalog generation.
Future<void> seedCatalog(
  AppDatabase db,
  int sourceId, {
  List<CategoryData> categories = const [],
  List<ChannelData> channels = const [],
  List<MovieData> movies = const [],
  List<SeriesData> series = const [],
}) async {
  final dao = db.catalogDao;
  final gen = await dao.beginGeneration(sourceId);
  await dao.upsertCategories(sourceId, gen, categories);
  for (var i = 0; i < channels.length; i += 2000) {
    final end = i + 2000 > channels.length ? channels.length : i + 2000;
    await dao.upsertChannels(sourceId, gen, channels.sublist(i, end));
  }
  await dao.upsertMovies(sourceId, gen, movies);
  await dao.upsertSeries(sourceId, gen, series);
  await dao.commitGeneration(sourceId, gen);
}

CategoryData liveCategory(String key, String name, int sortIndex) =>
    CategoryData(
      kind: ContentKind.live,
      key: key,
      name: name,
      sortIndex: sortIndex,
    );

/// A source with three live categories of ten numbered channels each:
/// News (1-10), Sports (11-20) and Kids (21-30).
Future<int> seedThreeCategories(AppDatabase db) async {
  final id = await addTestSource(db, lastSyncAt: DateTime.now());
  await seedCatalog(
    db,
    id,
    categories: [
      liveCategory('news', 'News', 0),
      liveCategory('sports', 'Sports', 1),
      liveCategory('kids', 'Kids', 2),
    ],
    channels: [
      for (var n = 1; n <= 30; n++)
        testChannel(
          n,
          categories: [
            n <= 10
                ? 'news'
                : n <= 20
                ? 'sports'
                : 'kids',
          ],
        ),
    ],
  );
  return id;
}

/// Links channel `k<n>` to a guide channel `g<n>` and stores [programmes].
Future<void> seedGuide(
  AppDatabase db,
  int sourceId,
  Map<int, List<EpgProgramme>> programmes,
) async {
  final guide = await db.epgDao.addEpgSource(
    sourceId,
    'http://127.0.0.1:9/guide.xml',
    EpgOrigin.manual,
  );
  await db.epgDao.replaceChannelMap(sourceId, {
    for (final n in programmes.keys)
      'k$n': (epgSourceId: guide, xmltvId: 'g$n', kind: EpgMatchKind.tvgId),
  });
  await db.epgDao.insertProgrammes(guide, [
    for (final list in programmes.values) ...list,
  ]);
}

EpgProgramme programme(
  int channel,
  DateTime start,
  Duration length,
  String title, {
  String? desc,
}) => EpgProgramme(
  channelId: 'g$channel',
  start: start,
  stop: start.add(length),
  title: title,
  desc: desc,
);

/// Pumps the real app (shell included) on a TV or a phone with [db] in
/// [locale]; [overrides] are added to the harness's.
Future<void> pumpLiveApp(
  WidgetTester tester,
  AppDatabase db, {
  bool tv = true,
  Locale locale = const Locale('en'),
  Clock? clock,
  List<Override> overrides = const [],
}) async {
  final size = tv ? tvSize : phoneSize;
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  addTearDown(() => applyFocusHighlightStrategy(tv: false));
  KeyRepeatThrottle.instance = KeyRepeatThrottle();
  FailedImageCache.clear();
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceCapsProvider.overrideWithValue(tv ? tvCaps : phoneCaps),
        initialSettingsProvider.overrideWithValue(
          AppSettings(
            locale: locale.languageCode == 'ar'
                ? AppLocaleSetting.ar
                : AppLocaleSetting.en,
          ),
        ),
        ringLogProvider.overrideWithValue(RingLog()),
        autoSyncOnStartProvider.overrideWithValue(false),
        // No guide downloads: the schedule in IptvApp is always alive.
        epgServiceProvider.overrideWithValue(FakeEpgService()),
        clockProvider.overrideWithValue(clock ?? FakeClock(testNow)),
        ...overrides,
      ],
      child: const IptvApp(),
    ),
  );
  await settle(tester);
}

/// The arrow toward the end side (into the page) for [rtl].
LogicalKeyboardKey toEnd(bool rtl) =>
    rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight;

/// The arrow toward the start side (toward the rail) for [rtl].
LogicalKeyboardKey toStart(bool rtl) =>
    rtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft;

/// Texts shown by the focused widget.
List<String> focusedTexts() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return const [];
  final texts = <String>[];
  void visit(Element e) {
    final w = e.widget;
    if (w is Text && w.data != null) texts.add(w.data!);
    e.visitChildren(visit);
  }

  (ctx as Element).visitChildren(visit);
  return texts;
}

/// Whether the focused widget shows a [Text] reading exactly [text].
bool focusedShows(String text) => focusedTexts().contains(text);

/// Expects the focused widget to show [text].
void expectFocusOn(String text) =>
    expect(focusedTexts(), contains(text), reason: 'focus should be on $text');

/// Lets timers of [d] fire, then settles frames.
Future<void> wait(WidgetTester tester, Duration d) async {
  await tester.pump(d);
  await settle(tester);
}

/// Records play requests and shows a stand-in player route (Back closes it).
class FakePlayer {
  final requests = <PlayRequest>[];

  Future<void> launch(BuildContext context, PlayRequest request) {
    requests.add(request);
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/fake-player'),
        builder: (_) =>
            Scaffold(body: Center(child: Text('PLAYING ${request.item.key}'))),
      ),
    );
  }

  Override get override => playerLauncherProvider.overrideWithValue(launch);
}
