import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/form_factor.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/core/platform/device_caps.dart';
import 'package:iptv_player/core/secure/secret_store.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/sources/sync/sync_service.dart';

import 'app_harness.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late ManualSyncRunner runner;

  ProviderContainer makeContainer({
    DeviceCaps caps = phoneCaps,
    AppSettings settings = const AppSettings(),
    TargetPlatform platform = TargetPlatform.android,
    void Function(int sourceId)? onSynced,
  }) => ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      if (onSynced != null) onSourceSyncedProvider.overrideWithValue(onSynced),
      databaseProvider.overrideWithValue(db),
      deviceCapsProvider.overrideWithValue(caps),
      initialSettingsProvider.overrideWithValue(settings),
      targetPlatformProvider.overrideWithValue(platform),
      ringLogProvider.overrideWithValue(RingLog()),
      syncRunnerProvider.overrideWithValue(runner),
    ],
  );

  setUp(() {
    db = openAppTestDb();
    runner = ManualSyncRunner();
    container = makeContainer();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// Keeps [provider] alive and lets its streams deliver.
  Future<T> readSettled<T>(ProviderListenable<T> provider) async {
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    await pumpEventQueue();
    return container.read(provider);
  }

  group('active source', () {
    test('null without sources, else the stored or the first one', () async {
      expect(await readSettled(activeSourceIdProvider), isNull);
      expect(container.read(activeSourceProvider), isNull);

      final a = await addTestSource(db, name: 'A');
      final b = await addTestSource(db, name: 'B');
      expect(await readSettled(activeSourceIdProvider), a);
      expect((await readSettled(activeSourceProvider))!.name, 'A');

      await container.read(activeSourceIdProvider.notifier).select(b);
      expect(container.read(activeSourceIdProvider), b);
      expect(await db.sourcesDao.activeSourceId(), b);
      expect((await readSettled(activeSourceProvider))!.name, 'B');

      // A deleted active source falls back to the first one.
      await db.sourcesDao.deleteSource(b);
      expect(await readSettled(activeSourceIdProvider), a);
      expect(container.read(sourcesProvider).value, hasLength(1));
    });

    test('unresolved until the stored choice has loaded', () async {
      await addTestSource(db, name: 'A');
      final b = await addTestSource(db, name: 'B');
      await db.sourcesDao.setActive(b);
      final seen = <int?>[];
      container.listen(
        activeSourceIdProvider,
        (_, next) => seen.add(next),
        fireImmediately: true,
      );
      await pumpEventQueue();
      expect(container.read(activeSourceReadyProvider), isTrue);
      expect(container.read(activeSourceIdProvider), b);
      // Never the first source on the way.
      expect(seen.whereType<int>().toSet(), {b});
    });

    test('a stale stored id is ignored', () async {
      final a = await addTestSource(db);
      await db.settingsDao.setInt(SettingKeys.activeSourceId, a + 50);
      expect(await readSettled(activeSourceIdProvider), a);
    });
  });

  group('sync', () {
    test('status per source: idle, running with progress, done', () async {
      final id = await addTestSource(db);
      final statuses = <SyncStatus>[];
      container.listen(
        syncStatusProvider(id),
        (_, next) => statuses.add(next),
        fireImmediately: true,
      );
      expect(statuses.single, const SyncIdle());

      final service = container.read(syncServiceProvider);
      final done = service.syncAndWait(id);
      await pumpEventQueue();
      expect(runner.tasks.single.sourceId, id);
      expect(runner.tasks.single.config.url, contains('Home.m3u'));
      final running = container.read(syncStatusProvider(id));
      expect(running, isA<SyncRunning>());
      expect((running as SyncRunning).progress.channels, 5);
      expect(container.read(syncStatusProvider(id + 1)), const SyncIdle());

      runner.finish(SyncProgress(sourceId: id, phase: SyncPhase.done));
      expect((await done).isDone, isTrue);
      await pumpEventQueue();
      expect(container.read(syncStatusProvider(id)), isA<SyncDone>());
      expect(statuses.whereType<SyncRunning>(), isNotEmpty);
    });

    test('onSourceSyncedProvider is called after a successful sync', () async {
      final synced = <int>[];
      container.dispose();
      container = makeContainer(onSynced: synced.add);
      final id = await addTestSource(db);
      final done = container.read(syncServiceProvider).syncAndWait(id);
      await pumpEventQueue();
      runner.finish(SyncProgress(sourceId: id, phase: SyncPhase.done));
      await done;
      expect(synced, [id]);
    });

    test('deleting a source cancels its running sync first', () async {
      final id = await addTestSource(db);
      final service = container.read(syncServiceProvider);
      final run = service.syncAndWait(id);
      await pumpEventQueue();
      expect(service.isRunning(id), isTrue);
      await container.read(sourceRepositoryProvider).delete(id);
      expect((await run).phase, SyncPhase.cancelled);
      expect(service.isRunning(id), isFalse);
      expect(await db.sourcesDao.byId(id), isNull);
    });

    test('needsAutoSync: never synced or older than a day', () {
      final now = DateTime.utc(2026, 10, 15, 12);
      SourceRow row(DateTime? last) => SourceRow(
        id: 1,
        name: 'x',
        kind: SourceKind.m3uUrl,
        url: 'http://127.0.0.1:9/x.m3u',
        lastSyncAt: last,
      );
      expect(needsAutoSync(row(null), now), isTrue);
      expect(
        needsAutoSync(row(now.subtract(const Duration(hours: 23))), now),
        isFalse,
      );
      expect(needsAutoSync(row(now.subtract(autoSyncMaxAge)), now), isTrue);
    });
  });

  group('form factor', () {
    test('TV caps, overrides and desktop platforms', () {
      container.dispose();
      container = makeContainer(caps: tvCaps);
      expect(container.read(tvModeProvider), isTrue);
      expect(
        container.read(formFactorProvider(const Size(960, 540))),
        FormFactor.tv,
      );

      container.dispose();
      container = makeContainer(
        caps: tvCaps,
        settings: const AppSettings(formFactor: FormFactorOverride.phone),
      );
      expect(container.read(tvModeProvider), isFalse);

      container.dispose();
      container = makeContainer(
        caps: const DeviceCaps.desktop(),
        platform: TargetPlatform.windows,
      );
      expect(
        container.read(formFactorProvider(const Size(1280, 720))),
        FormFactor.desktop,
      );
      expect(container.read(tvModeProvider), isFalse);
    });
  });

  group('exit', () {
    late List<String> calls;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call.method);
            return call.method == 'System.exitApplication'
                ? {'response': 'exit'}
                : null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
    });

    test('Android pops the activity', () async {
      container.dispose();
      container = makeContainer();
      container.read(appExitProvider)();
      await pumpEventQueue();
      expect(calls, ['SystemNavigator.pop']);
    });

    test('desktop asks for an application exit, not a pop', () async {
      final log = RingLog();
      container.dispose();
      container = makeContainer(platform: TargetPlatform.windows);
      container.read(appExitProvider)();
      await pumpEventQueue();
      // The test binding answers exitApplication itself; the Windows
      // embedder would ignore SystemNavigator.pop.
      expect(calls, isNot(contains('SystemNavigator.pop')));

      final used = <String>[];
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.android,
      ]) {
        await exitApp(
          platform,
          log: log,
          pop: () async => used.add('pop ${platform.name}'),
          desktopExit: () async => used.add('exit ${platform.name}'),
        );
      }
      expect(used, ['exit windows', 'exit linux', 'exit macOS', 'pop android']);
      expect(log.dump(), isEmpty);
    });

    test('a failing exit is logged, not thrown', () async {
      final log = RingLog();
      await exitApp(
        TargetPlatform.windows,
        log: log,
        desktopExit: () async => throw PlatformException(code: 'nope'),
      );
      expect(log.dump(), contains('Exit failed'));
    });
  });

  group('secrets', () {
    test('saved sources register their credentials with the log', () async {
      final log = RingLog();
      container.dispose();
      container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          databaseProvider.overrideWithValue(db),
          ringLogProvider.overrideWithValue(log),
          syncRunnerProvider.overrideWithValue(runner),
        ],
      );
      await db.sourcesDao.create(
        const SourceConfig(
          kind: SourceKind.m3uUrl,
          url: 'http://tv.example/get.php?username=alice77&password=S3cretPw',
        ),
        secrets: DbSecretStore(db),
      );
      expect(await readSettled(sourcesProvider), isA<AsyncData<Object?>>());
      log.warn('open http://tv.example/alice77/S3cretPw/1 failed');
      expect(log.dump(), isNot(contains('S3cretPw')));
    });
  });

  test('the database must be overridden', () {
    final bare = ProviderContainer();
    addTearDown(bare.dispose);
    expect(() => bare.read(databaseProvider), throwsA(anything));
    expect(bare.read(deviceCapsProvider), const DeviceCaps());
    expect(bare.read(settingsProvider), const AppSettings());
    expect(bare.read(autoSyncOnStartProvider), isTrue);
    expect(bare.read(syncRunnerProvider), isA<IsolateSyncRunner>());
  });
}
