// Synthetic guide data and an app pump for the guide tests.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/app.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/core/platform/device_caps.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/epg/epg_models.dart';
import 'package:iptv_player/epg/epg_providers.dart';
import 'package:iptv_player/epg/epg_service.dart';
import 'package:iptv_player/features/guide/guide_model.dart';
import 'package:iptv_player/features/guide/providers.dart';
import 'package:iptv_player/player/ui/play_request.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/tv/dpad_shortcuts.dart';
import 'package:iptv_player/tv/key_repeat.dart';
import 'package:iptv_player/widgets/logo_image.dart';

import '../../../app/app_harness.dart' show settle, tvCaps;
import 'fake_epg_service.dart';

export '../../../app/app_harness.dart'
    show disposeApp, focusedIn, phoneCaps, press, settle, tvCaps;
export 'fake_epg_service.dart';

/// "Now" in the guide tests: 18:47 local time, mid-programme.
final guideNow = DateTime(2026, 10, 15, 18, 47).toUtc();

/// Start of the visible window at [guideNow] (18:30 local).
DateTime get guideViewStart => floorToSlot(guideNow);

AppDatabase openGuideDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory(), clock: FakeClock(guideNow));
}

/// Title of programme [k] of channel [i] (k = 0 is on air at [guideNow]).
String progTitle(int i, int k) => 'Show $i.$k';

/// Hourly programmes of channel [i]: k = -3..12 cover
/// `[18:00 + k h, 19:00 + k h)` local, so k = 0 is on air at 18:47.
/// Channels whose number is even have 30-minute programmes instead
/// (k = 0 is `[18:30, 19:00)`).
List<EpgProgramme> programmesFor(int i) {
  final hourly = i.isOdd;
  final base = guideViewStart.subtract(
    hourly ? const Duration(minutes: 30) : Duration.zero,
  );
  final step = hourly ? const Duration(hours: 1) : const Duration(minutes: 30);
  return [
    for (var k = -3; k <= 12; k++)
      EpgProgramme(
        channelId: 'x.c$i',
        start: base.add(step * k),
        stop: base.add(step * (k + 1)),
        title: progTitle(i, k),
        desc: 'About ${progTitle(i, k)}',
      ),
  ];
}

typedef SeededGuide = ({int sourceId, int epgSourceId});

/// Channel `c<i>`: number 100 + i, News up to 10, else Sports.
ChannelData channelData(int i) => ChannelData(
  key: 'c$i',
  name: 'Channel $i',
  num: 100 + i,
  tvgId: 'x.c$i',
  url: 'http://127.0.0.1:9/live/c$i.ts',
  categoryKeys: [i <= 10 ? 'news' : 'sports'],
);

/// Commits a new catalog generation of [sourceId] holding [channels]
/// (what a sync does).
Future<void> resyncChannels(
  AppDatabase db,
  int sourceId,
  List<ChannelData> channels,
) async {
  final catalog = db.catalogDao;
  final gen = await catalog.beginGeneration(sourceId);
  await catalog.upsertCategories(sourceId, gen, const [
    CategoryData(kind: ContentKind.live, key: 'news', name: 'News'),
    CategoryData(kind: ContentKind.live, key: 'sports', name: 'Sports'),
  ]);
  await catalog.upsertChannels(sourceId, gen, channels);
  await catalog.commitGeneration(sourceId, gen);
}

/// One source with [channels] channels (`c1`..`cN`, numbers 101.., names
/// `Channel N`): `c1`..`c10` in News, the rest in Sports. Channels up to
/// [withGuide] have programmes ([programmesFor]); the others have none.
/// Without [guide], no guide source exists at all.
Future<SeededGuide> seedGuide(
  AppDatabase db, {
  int channels = 30,
  int withGuide = 25,
  bool guide = true,
  List<String> favorites = const [],
}) async {
  final sourceId = await db.sourcesDao.create(
    const SourceConfig(
      kind: SourceKind.m3uUrl,
      url: 'http://127.0.0.1:9/guide.m3u',
      name: 'Home',
    ),
  );
  await db.sourcesDao.markSynced(sourceId, guideNow);
  final catalog = db.catalogDao;
  final gen = await catalog.beginGeneration(sourceId);
  await catalog.upsertCategories(sourceId, gen, const [
    CategoryData(kind: ContentKind.live, key: 'news', name: 'News'),
    CategoryData(
      kind: ContentKind.live,
      key: 'sports',
      name: 'Sports',
      sortIndex: 1,
    ),
  ]);
  await catalog.upsertChannels(sourceId, gen, [
    for (var i = 1; i <= channels; i++) channelData(i),
  ]);
  await catalog.commitGeneration(sourceId, gen);
  for (final key in favorites) {
    await db.favoritesDao.setFavorite(sourceId, ContentKind.live, key, true);
  }
  if (!guide) return (sourceId: sourceId, epgSourceId: -1);

  final epgSourceId = await db.epgDao.addEpgSource(
    sourceId,
    'http://127.0.0.1:9/guide.xml',
    EpgOrigin.manual,
  );
  await db.epgDao.insertProgrammes(epgSourceId, [
    for (var i = 1; i <= withGuide; i++) ...programmesFor(i),
  ]);
  await db.epgDao.replaceChannelMap(sourceId, {
    for (var i = 1; i <= withGuide; i++)
      'c$i': (
        epgSourceId: epgSourceId,
        xmltvId: 'x.c$i',
        kind: EpgMatchKind.tvgId,
      ),
  });
  await db.sourcesDao.markEpgFetched(sourceId, guideNow);
  return (sourceId: sourceId, epgSourceId: epgSourceId);
}

/// Requests handed to the player.
class PlayerLog {
  final requests = <PlayRequest>[];

  Future<void> call(BuildContext context, PlayRequest request) async =>
      requests.add(request);
}

/// Pumps the real app on [db] with the guide's collaborators faked: the
/// clock at [guideNow], [epg] for refreshes, [player] for playback.
Future<void> pumpGuideApp(
  WidgetTester tester, {
  required AppDatabase db,
  required PlayerLog player,
  EpgService? epg,
  DeviceCaps caps = tvCaps,
  bool rtl = false,
  Size? logicalSize,
}) async {
  final size =
      logicalSize ?? (caps.isTv ? const Size(960, 540) : const Size(390, 800));
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
        deviceCapsProvider.overrideWithValue(caps),
        initialSettingsProvider.overrideWithValue(
          AppSettings(locale: rtl ? AppLocaleSetting.ar : AppLocaleSetting.en),
        ),
        ringLogProvider.overrideWithValue(RingLog()),
        autoSyncOnStartProvider.overrideWithValue(false),
        clockProvider.overrideWithValue(FakeClock(guideNow)),
        epgServiceProvider.overrideWithValue(epg ?? FakeEpgService()),
        epgAutoRefreshIntervalProvider.overrideWithValue(null),
        guidePlayerProvider.overrideWithValue(player.call),
      ],
      child: const IptvApp(),
    ),
  );
  await settle(tester);
}
