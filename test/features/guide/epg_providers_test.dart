// When the guide is refreshed in the background, and the refresh status
// the UI sees. The EpgService is a fake; the sync service is real with a
// runner the test finishes by hand.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/epg/epg_models.dart';
import 'package:iptv_player/epg/epg_progress.dart';
import 'package:iptv_player/epg/epg_providers.dart';
import 'package:iptv_player/epg/epg_service.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/sources/source_repository.dart';
import 'package:iptv_player/sources/sync/sync_progress.dart';

import '../../app/app_harness.dart' show ManualSyncRunner;
import 'support/guide_fixtures.dart';

void main() {
  late AppDatabase db;
  late FakeEpgService epg;
  late ManualSyncRunner runner;
  late FakeClock clock;
  late ProviderContainer container;

  ProviderContainer makeContainer({
    Duration? every,
    AppSettings settings = const AppSettings(epgRefreshHours: 6),
  }) => ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      databaseProvider.overrideWithValue(db),
      initialSettingsProvider.overrideWithValue(settings),
      ringLogProvider.overrideWithValue(RingLog()),
      syncRunnerProvider.overrideWithValue(runner),
      clockProvider.overrideWithValue(clock),
      epgServiceProvider.overrideWithValue(epg),
      epgAutoRefreshIntervalProvider.overrideWithValue(every),
    ],
  );

  setUp(() {
    db = openGuideDb();
    epg = FakeEpgService();
    runner = ManualSyncRunner();
    clock = FakeClock(guideNow);
    container = makeContainer();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// Keeps the schedule alive and lets the sources load.
  Future<EpgAutoRefresh> startSchedule() async {
    final sub = container.listen(epgAutoRefreshProvider, (_, _) {});
    addTearDown(sub.close);
    await pumpEventQueue();
    return container.read(epgAutoRefreshProvider);
  }

  Future<void> syncAndFinish(int id, SyncPhase phase) async {
    container.read(syncServiceProvider).sync(id);
    await pumpEventQueue();
    runner.finish(SyncProgress(sourceId: id, phase: phase));
    await pumpEventQueue();
  }

  group('launch check', () {
    test('a due guide is refreshed once, with the Settings interval', () async {
      final id = (await seedGuide(db)).sourceId;
      epg.due.add(id);
      final auto = await startSchedule();
      expect(epg.needsCalls, [id]);
      expect(epg.calls, [
        (sourceId: id, force: false, lite: false, refreshHours: 6),
      ]);
      expect(auto.checked(id), isTrue);
      expect(container.read(guideRefreshProvider(id)).isRunning, isTrue);

      // Once per launch.
      await auto.checkSource(id);
      expect(epg.needsCalls, [id]);
      expect(epg.calls, hasLength(1));
    });

    test('a current guide is left alone', () async {
      final id = (await seedGuide(db)).sourceId;
      await startSchedule();
      expect(epg.needsCalls, [id]);
      expect(epg.calls, isEmpty);
      expect(container.read(guideRefreshProvider(id)), isA<GuideRefreshIdle>());
    });

    test('a source without a catalog waits for its first sync', () async {
      final id = await db.sourcesDao.create(
        const SourceConfig(
          kind: SourceKind.m3uUrl,
          url: 'http://127.0.0.1:9/new.m3u',
          name: 'New',
        ),
      );
      epg.due.add(id);
      final auto = await startSchedule();
      expect(epg.needsCalls, isEmpty);
      expect(epg.calls, isEmpty);
      expect(auto.checked(id), isFalse);

      await syncAndFinish(id, SyncPhase.done);
      expect(epg.calls.single.sourceId, id);
      expect(auto.checked(id), isTrue);
    });

    test('a running sync decides: failed runs the check', () async {
      final id = (await seedGuide(db)).sourceId;
      epg.due.add(id);
      container.read(syncServiceProvider).sync(id);
      await pumpEventQueue();
      final auto = await startSchedule();
      expect(epg.needsCalls, isEmpty);

      runner.finish(
        SyncProgress(
          sourceId: id,
          phase: SyncPhase.failed,
          error: const VerifyError(VerifyErrorReason.timeout),
        ),
      );
      await pumpEventQueue();
      expect(epg.needsCalls, [id]);
      expect(epg.calls.single.force, isFalse);
      expect(auto.checked(id), isTrue);
    });

    test('a running sync decides: done refreshes without a check', () async {
      final id = (await seedGuide(db)).sourceId;
      container.read(syncServiceProvider).sync(id);
      await pumpEventQueue();
      await startSchedule();
      runner.finish(SyncProgress(sourceId: id, phase: SyncPhase.done));
      await pumpEventQueue();
      expect(epg.needsCalls, isEmpty);
      expect(epg.calls.single.sourceId, id);
    });

    test('switching sources checks the new one', () async {
      final a = (await seedGuide(db)).sourceId;
      final b = await db.sourcesDao.create(
        const SourceConfig(
          kind: SourceKind.m3uUrl,
          url: 'http://127.0.0.1:9/b.m3u',
          name: 'B',
        ),
      );
      await db.catalogDao.commitGeneration(
        b,
        await db.catalogDao.beginGeneration(b),
      );
      epg.due.addAll([a, b]);
      await startSchedule();
      expect(epg.calls.map((c) => c.sourceId), [a]);
      await container.read(activeSourceIdProvider.notifier).select(b);
      await pumpEventQueue();
      expect(epg.calls.map((c) => c.sourceId), [a, b]);
    });
  });

  group('after a sync', () {
    test('every successful sync refreshes; failures do not', () async {
      final id = (await seedGuide(db)).sourceId;
      await startSchedule();
      expect(epg.calls, isEmpty);

      await syncAndFinish(id, SyncPhase.done);
      expect(epg.calls, hasLength(1));
      expect(epg.calls.single.force, isFalse);
      await epg.finish(id);
      await pumpEventQueue();

      await syncAndFinish(id, SyncPhase.cancelled);
      expect(epg.calls, hasLength(1));
    });

    test('a refresh already running is followed by a new one', () async {
      final id = (await seedGuide(db)).sourceId;
      epg.due.add(id);
      await startSchedule();
      expect(epg.calls, hasLength(1)); // launch check

      // It matched the old channel list: run again once it ends.
      await syncAndFinish(id, SyncPhase.done);
      expect(epg.calls, hasLength(1));
      await epg.finish(id);
      await pumpEventQueue();
      expect(epg.calls, hasLength(2));
      await epg.finish(id);
      await pumpEventQueue();
      expect(epg.calls, hasLength(2));
      expect(container.read(guideRefreshProvider(id)), isA<GuideRefreshDone>());
    });

    test('a refresh started elsewhere is joined, then run again', () async {
      final id = (await seedGuide(db)).sourceId;
      await startSchedule();
      epg.refresh(id, force: true); // e.g. Settings after an offset change
      await syncAndFinish(id, SyncPhase.done);
      expect(epg.calls, hasLength(2)); // joined
      await epg.finish(id);
      await pumpEventQueue();
      expect(epg.calls, hasLength(3));
    });
  });

  group('fullscreen playback on a Lite device', () {
    const lite = AppSettings(lite: LiteSetting.on, epgRefreshHours: 6);

    void playing(bool active) =>
        container.read(fullscreenPlaybackProvider.notifier).set(active);

    test('a due launch check waits for playback to end', () async {
      container.dispose();
      container = makeContainer(settings: lite);
      final id = (await seedGuide(db)).sourceId;
      epg.due.add(id);
      playing(true);
      expect(container.read(epgImportsPausedProvider), isTrue);
      final auto = await startSchedule();
      expect(epg.needsCalls, [id]);
      expect(epg.calls, isEmpty);
      expect(auto.held, {id});

      playing(false);
      await pumpEventQueue();
      expect(epg.calls, [
        (sourceId: id, force: false, lite: true, refreshHours: 6),
      ]);
      expect(auto.held, isEmpty);
      expect(container.read(guideRefreshProvider(id)).isRunning, isTrue);
    });

    test('a sync ending during playback refreshes after it', () async {
      container.dispose();
      container = makeContainer(settings: lite);
      final id = (await seedGuide(db)).sourceId;
      final auto = await startSchedule();
      playing(true);
      await syncAndFinish(id, SyncPhase.done);
      expect(epg.calls, isEmpty);
      expect(auto.held, {id});

      playing(false);
      await pumpEventQueue();
      expect(epg.calls.single.force, isFalse);
      expect(auto.held, isEmpty);
    });

    test('running imports stop and run again, in full, afterwards', () async {
      container.dispose();
      container = makeContainer(settings: lite);
      final id = (await seedGuide(db)).sourceId;
      final auto = await startSchedule();
      // "Refresh guide", then the user starts watching.
      container.read(guideRefreshProvider(id).notifier).refresh(force: true);
      expect(epg.calls.single.force, isTrue);
      playing(true);
      await pumpEventQueue();
      expect(epg.cancelled, [id]);
      final cancelled = container.read(guideRefreshProvider(id));
      expect((cancelled as GuideRefreshFailed).cancelled, isTrue);
      expect(auto.held, {id});

      // Zapping or leaving and re-entering keeps it held.
      playing(true);
      await pumpEventQueue();
      expect(epg.calls, hasLength(1));

      playing(false);
      await pumpEventQueue();
      expect(epg.calls, hasLength(2));
      expect(epg.calls.last.force, isTrue);
      final running = container.read(guideRefreshProvider(id));
      expect((running as GuideRefreshRunning).forced, isTrue);

      // A background run is cancelled too and run again afterwards.
      await epg.finish(id);
      await pumpEventQueue();
      epg.refresh(id); // e.g. started by the launch check of another screen
      playing(true);
      await pumpEventQueue();
      expect(epg.cancelled, [id, id]);
      playing(false);
      await pumpEventQueue();
      expect(epg.calls, hasLength(4));
      expect(epg.calls.last.force, isFalse);
    });

    test('the periodic check waits while playing', () async {
      container.dispose();
      container = makeContainer(
        settings: lite,
        every: const Duration(milliseconds: 20),
      );
      final id = (await seedGuide(db)).sourceId;
      await startSchedule();
      playing(true);
      epg.due.add(id);
      epg.needsCalls.clear();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      await pumpEventQueue();
      expect(epg.needsCalls, isEmpty);
      expect(epg.calls, isEmpty);

      playing(false);
      await pumpEventQueue();
      expect(epg.calls, hasLength(1));
    });

    test('without Lite, playback does not hold imports', () async {
      final id = (await seedGuide(db)).sourceId;
      final auto = await startSchedule();
      playing(true);
      expect(container.read(epgImportsPausedProvider), isFalse);
      container.read(guideRefreshProvider(id).notifier).refresh(force: true);
      await pumpEventQueue();
      expect(epg.cancelled, isEmpty);
      await epg.finish(id);
      await pumpEventQueue();
      await syncAndFinish(id, SyncPhase.done);
      expect(epg.calls, hasLength(2));
      expect(auto.held, isEmpty);
    });
  });

  test('the periodic check refreshes the active source when due', () async {
    container.dispose();
    container = makeContainer(every: const Duration(milliseconds: 20));
    final id = (await seedGuide(db)).sourceId;
    await startSchedule();
    expect(epg.calls, isEmpty);
    epg.due.add(id);
    await Future<void>.delayed(const Duration(milliseconds: 70));
    await pumpEventQueue();
    expect(epg.calls, hasLength(1)); // not again while it runs
    await epg.finish(id);
    epg.due.clear();
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(epg.calls, hasLength(1));
  });

  group('refresh status', () {
    test('follows a run to done', () async {
      final id = (await seedGuide(db)).sourceId;
      final status = <GuideRefreshStatus>[];
      container.listen(
        guideRefreshProvider(id),
        (_, next) => status.add(next),
        fireImmediately: true,
      );
      container.read(guideRefreshProvider(id).notifier).refresh(force: true);
      expect(epg.calls.single.force, isTrue);
      expect(status.last, isA<GuideRefreshRunning>());
      expect((status.last as GuideRefreshRunning).forced, isTrue);

      const started = EpgGuideStarted(
        1,
        epgSourceId: 1,
        url: 'http://127.0.0.1:9/guide.xml',
        origin: EpgOrigin.manual,
        index: 0,
        total: 1,
      );
      epg.emit(id, started);
      await pumpEventQueue();
      final running = status.last as GuideRefreshRunning;
      expect(running.latest, same(started));
      expect(running.forced, isTrue);

      clock.advance(const Duration(minutes: 2));
      await epg.finish(id);
      await pumpEventQueue();
      final done = status.last as GuideRefreshDone;
      expect(done.result.imported, 1);
      expect(done.finishedAt, guideNow.add(const Duration(minutes: 2)));
      expect(status.first, isA<GuideRefreshIdle>());
    });

    test('failures and cancellation', () async {
      final id = (await seedGuide(db)).sourceId;
      final sub = container.listen(guideRefreshProvider(id), (_, _) {});
      addTearDown(sub.close);
      final controller = container.read(guideRefreshProvider(id).notifier);

      controller.refresh();
      await epg.finish(id, EpgRefreshFailed(id, message: 'HTTP 500'));
      await pumpEventQueue();
      final failed = container.read(guideRefreshProvider(id));
      expect(failed, isA<GuideRefreshFailed>());
      expect((failed as GuideRefreshFailed).message, 'HTTP 500');
      expect(failed.cancelled, isFalse);

      controller.refresh();
      await controller.cancel();
      await pumpEventQueue();
      expect(epg.cancelled, [id]);
      final cancelled = container.read(guideRefreshProvider(id));
      expect((cancelled as GuideRefreshFailed).cancelled, isTrue);
    });

    test('Lite mode and the Settings interval reach the service', () async {
      container.dispose();
      container = makeContainer(
        settings: const AppSettings(lite: LiteSetting.on, epgRefreshHours: 24),
      );
      final id = (await seedGuide(db)).sourceId;
      container.read(guideRefreshProvider(id).notifier).refresh();
      expect(epg.calls.single, (
        sourceId: id,
        force: false,
        lite: true,
        refreshHours: 24,
      ));
    });
  });

  test('the service provider builds one real service', () {
    final real = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        ringLogProvider.overrideWithValue(RingLog()),
        epgRunInIsolateProvider.overrideWithValue(false),
      ],
    );
    addTearDown(real.dispose);
    final service = real.read(epgServiceProvider);
    expect(service, isA<EpgService>());
    expect(service.runInIsolate, isFalse);
    expect(real.read(epgServiceProvider), same(service));
    expect(service.isRefreshing(1), isFalse);
  });

  test('programmes seeded for the guide are readable', () async {
    final seeded = await seedGuide(db, channels: 3, withGuide: 2);
    final map = await db.epgDao.programmesForChannels(
      seeded.sourceId,
      ['c1', 'c2', 'c3'],
      guideViewStart,
      guideViewStart.add(const Duration(hours: 1)),
    );
    expect(map.keys, unorderedEquals(['c1', 'c2']));
    expect(map['c1']!.first, isA<EpgProgramme>());
    expect(map['c1']!.first.title, progTitle(1, 0));
  });
}
