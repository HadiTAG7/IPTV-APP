// How the features are connected in the app (lib/app/wiring.dart and the
// hooks whose defaults are the real implementations).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:iptv_player/app/app.dart';
import 'package:iptv_player/app/bootstrap.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/app/shell_phone.dart';
import 'package:iptv_player/app/shell_tv.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/epg/epg_providers.dart';
import 'package:iptv_player/features/favorites/vod_navigation.dart';
import 'package:iptv_player/features/help/help_screen.dart';
import 'package:iptv_player/features/help/licenses.dart';
import 'package:iptv_player/features/help/providers.dart';
import 'package:iptv_player/features/live/live_actions.dart';
import 'package:iptv_player/features/movies/movie_detail_screen.dart';
import 'package:iptv_player/features/onboarding/onboarding_screen.dart';
import 'package:iptv_player/features/series/series_detail_screen.dart';
import 'package:iptv_player/features/settings/providers.dart';
import 'package:iptv_player/features/sources/source_editor_screen.dart';
import 'package:iptv_player/player/player_providers.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/sources/sync/sync_progress.dart';
import 'package:iptv_player/sources/sync/sync_service.dart';

import '../features/sources/support.dart';
import '../support/fake_epg_service.dart';
import '../unit/db/db_test_utils.dart'
    show category, movie, series, syncCatalog;

/// A Live tab with two buttons that open a movie and a series the way
/// Favorites and Search do.
class _VodLauncher extends ConsumerWidget {
  const _VodLauncher(this.sourceId);

  final int sourceId;

  Future<void> _open(BuildContext context, WidgetRef ref, String key) async {
    final catalog = ref.read(catalogDaoProvider);
    final target = key.startsWith('m')
        ? VodTarget.movie(
            sourceId: sourceId,
            movie: (await catalog.movieByKey(sourceId, key))!,
          )
        : VodTarget.series(
            sourceId: sourceId,
            series: (await catalog.seriesByKey(sourceId, key))!,
          );
    if (!context.mounted) return;
    await ref.read(vodDetailNavigatorProvider)(context, ref, target);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    children: [
      TextButton(
        key: const ValueKey('open-m1'),
        onPressed: () => _open(context, ref, 'm1'),
        child: const Text('movie'),
      ),
      TextButton(
        key: const ValueKey('open-s1'),
        onPressed: () => _open(context, ref, 's1'),
        child: const Text('series'),
      ),
    ],
  );
}

/// The real Help page, stand-ins elsewhere.
Widget _helpOrFake(HomeTab tab) =>
    tab == HomeTab.help ? const HelpScreen() : FakeTabPage(tab);

Future<int> _seedVod(AppDatabase db) async {
  final id = await addTestSource(db, lastSyncAt: DateTime.now());
  await syncCatalog(
    db,
    id,
    categories: [
      category(ContentKind.movie, 'films'),
      category(ContentKind.series, 'shows'),
    ],
    movies: [movie('m1', name: 'First movie')],
    seriesList: [series('s1', name: 'First series')],
  );
  return id;
}

void main() {
  group('Favorites and Search open the detail pages', () {
    testWidgets('a movie and a series', (tester) async {
      final db = openAppTestDb();
      final id = await _seedVod(db);
      await pumpApp(
        tester,
        db: db,
        pages: (tab) =>
            tab == HomeTab.live ? _VodLauncher(id) : const SizedBox.shrink(),
      );

      await tester.tap(find.byKey(const ValueKey('open-m1')));
      await settleRoute(tester);
      final movieDetail = tester.widget<MovieDetailScreen>(
        find.byType(MovieDetailScreen),
      );
      expect((movieDetail.sourceId, movieDetail.movieKey), (id, 'm1'));
      expect(
        ModalRoute.of(tester.element(find.byType(MovieDetailScreen)))
            ?.settings
            .name,
        '/movie',
      );
      await back(tester);
      expect(find.byType(MovieDetailScreen), findsNothing);

      await tester.tap(find.byKey(const ValueKey('open-s1')));
      await settleRoute(tester);
      final seriesDetail = tester.widget<SeriesDetailScreen>(
        find.byType(SeriesDetailScreen),
      );
      expect((seriesDetail.sourceId, seriesDetail.seriesKey), (id, 's1'));
      await back(tester);
      expect(find.byType(SeriesDetailScreen), findsNothing);
      expect(find.byKey(const ValueKey('open-m1')), findsOneWidget);
      await disposeApp(tester, db);
    });
  });

  group('Recent channels', () {
    test('the player and the Live screens share one action', () async {
      final db = openAppTestDb();
      addTearDown(db.close);
      final id = await addTestSource(db);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          ringLogProvider.overrideWithValue(RingLog()),
        ],
      );
      addTearDown(container.dispose);
      expect(
        identical(
          container.read(markChannelPlayedProvider),
          container.read(onChannelPlayedProvider),
        ),
        isTrue,
      );
      // The player (every tuned or zapped channel), then Live.
      await container.read(onChannelPlayedProvider)(id, 'ch1');
      await container.read(onChannelPlayedProvider)(id, 'ch2');
      await container.read(markChannelPlayedProvider)(id, 'ch3');
      expect(await db.recentDao.recentChannelKeys(id), ['ch3', 'ch2', 'ch1']);
      await db.close();
      // Never throws (a closed database is logged, without the key).
      await container.read(onChannelPlayedProvider)(id, 'ch4');
    });
  });

  group("Settings' Refresh guide", () {
    test('runs the source guide refresh with the Settings interval and '
        'Lite mode, and completes when it ends', () async {
      final db = openAppTestDb();
      addTearDown(db.close);
      final id = await addTestSource(db);
      final epg = FakeEpgService();
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          databaseProvider.overrideWithValue(db),
          ringLogProvider.overrideWithValue(RingLog()),
          initialSettingsProvider.overrideWithValue(
            const AppSettings(lite: LiteSetting.on, epgRefreshHours: 6),
          ),
          epgServiceProvider.overrideWithValue(epg),
        ],
      );
      addTearDown(container.dispose);

      var finished = false;
      final run = container
          .read(refreshGuideActionProvider)(id, force: true)
          .then((_) => finished = true);
      await pumpEventQueue();
      expect(epg.calls, [
        (sourceId: id, force: true, lite: true, refreshHours: 6),
      ]);
      // The Guide screen sees the same run.
      final running = container.read(guideRefreshProvider(id));
      expect((running as GuideRefreshRunning).forced, isTrue);
      expect(finished, isFalse);

      await epg.finish(id);
      await run;
      expect(container.read(guideRefreshProvider(id)), isA<GuideRefreshDone>());

      // A failed or cancelled run ends the call too.
      final again = container.read(refreshGuideActionProvider)(
        id,
        force: false,
      );
      await pumpEventQueue();
      await epg.cancel(id);
      await again;
      expect(epg.calls.last.force, isFalse);
    });
  });

  group("Help's Add as source", () {
    testWidgets('opens the source editor with the playlist link filled in', (
      tester,
    ) async {
      final db = openAppTestDb();
      await addTestSource(db, lastSyncAt: DateTime.now());
      await pumpApp(tester, db: db, pages: _helpOrFake);
      expect(
        containerOf(tester).read(addSourcePrefillProvider),
        isNotNull,
        reason: 'wired by appWiring',
      );
      await tester.tap(find.byKey(const ValueKey('nav-more')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('more-help')));
      await settleRoute(tester);
      expect(find.byType(HelpScreen), findsOneWidget);

      await tapKey(tester, 'help-url-sa');
      await settleRoute(tester);
      final editor = tester.widget<SourceEditorScreen>(
        find.byType(SourceEditorScreen),
      );
      expect(editor.sourceId, isNull);
      expect(editor.onboarding, isFalse);
      expect(fieldText(tester, 'field-url'), kIptvOrgSaudiUrl);
      expect(
        fieldText(tester, 'field-name'),
        'iptv-org: ${enL10n.help_iptvOrgSaudi}',
      );
      // Nothing is saved until the user presses Test & save.
      expect(await tester.runAsync(db.sourcesDao.all), hasLength(1));

      await back(tester);
      expect(find.byType(SourceEditorScreen), findsNothing);
      expect(find.byType(HelpScreen), findsOneWidget);
      await disposeApp(tester, db);
    });

    testWidgets('before the first source it runs the first-run flow', (
      tester,
    ) async {
      final db = openAppTestDb();
      await pumpApp(tester, db: db, pages: _helpOrFake);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      await tapKey(tester, 'onboarding-learn-more');
      await settleRoute(tester);
      await tapKey(tester, 'help-url-ara');
      await settleRoute(tester);
      final editor = tester.widget<SourceEditorScreen>(
        find.byType(SourceEditorScreen),
      );
      expect(editor.onboarding, isTrue);
      expect(fieldText(tester, 'field-url'), kIptvOrgArabicUrl);
      await back(tester);
      await back(tester);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      await disposeApp(tester, db);
    });
  });

  group('the guide schedule', () {
    testWidgets('runs from app start: a finished sync refreshes the guide', (
      tester,
    ) async {
      final db = openAppTestDb();
      final epg = FakeEpgService();
      final runner = ManualSyncRunner();
      await pumpApp(tester, db: db, fakePages: true, runner: runner, epg: epg);
      // Alive on the onboarding screen already (the first import counts).
      expect(find.byType(OnboardingScreen), findsOneWidget);
      final container = containerOf(tester);
      expect(container.exists(epgAutoRefreshProvider), isTrue);

      final id = await tester.runAsync(() => addTestSource(db));
      await settle(tester);
      container.read(syncServiceProvider).sync(id!);
      await settle(tester);
      expect(epg.calls, isEmpty);
      runner.finish(SyncProgress(sourceId: id, phase: SyncPhase.done));
      await settle(tester);
      expect(epg.calls.map((c) => c.sourceId), [id]);
      expect(container.read(guideRefreshProvider(id)).isRunning, isTrue);
      await disposeApp(tester, db);
    });
  });

  group('the home shell', () {
    testWidgets('TV: showTab selects a tab and enters it', (tester) async {
      final db = openAppTestDb();
      await addTestSource(db, lastSyncAt: DateTime.now());
      await pumpApp(tester, db: db, caps: tvCaps, fakePages: true);
      tester
          .state<HomeShellState>(find.byType(HomeShell))
          .showTab(HomeTab.settings, enter: true);
      await settle(tester);
      expect(
        tester.state<TvShellState>(find.byType(TvShell)).current,
        HomeTab.settings,
      );
      expect(focusedIn(const ValueKey('settings-A')), isTrue);
      await disposeApp(tester, db);
    });

    testWidgets('phone: showTab selects a bar tab', (tester) async {
      final db = openAppTestDb();
      await addTestSource(db, lastSyncAt: DateTime.now());
      await pumpApp(tester, db: db, fakePages: true);
      tester
          .state<HomeShellState>(find.byType(HomeShell))
          .showTab(HomeTab.guide);
      await settle(tester);
      expect(
        tester.state<PhoneShellState>(find.byType(PhoneShell)).current,
        HomeTab.guide,
      );
      expect(find.text('guide-A'), findsOneWidget);
      await disposeApp(tester, db);
    });
  });

  group('launch auto-sync', () {
    testWidgets('re-checks the saved source: an import that just finished '
        'is not repeated', (tester) async {
      final db = openAppTestDb();
      final id = await addTestSource(db);
      // The row the shell is built with predates the import's sync time
      // (the onboarding import saved it right before the shell appeared).
      final stale = (await db.sourcesDao.byId(id))!;
      expect(stale.lastSyncAt, isNull);
      await db.sourcesDao.markSynced(id, DateTime.now());
      final runner = ManualSyncRunner();
      await pumpApp(
        tester,
        db: db,
        fakePages: true,
        autoSync: true,
        runner: runner,
        overrides: [
          sourcesProvider.overrideWith((ref) => Stream.value([stale])),
        ],
      );
      expect(find.byType(HomeShell), findsOneWidget);
      await settle(tester);
      expect(runner.tasks, isEmpty);
      await disposeApp(tester, db);
    });

    testWidgets('syncs a source whose saved catalog is old', (tester) async {
      final db = openAppTestDb();
      final id = await addTestSource(
        db,
        lastSyncAt: DateTime.now().subtract(const Duration(days: 2)),
      );
      final runner = ManualSyncRunner();
      await pumpApp(
        tester,
        db: db,
        fakePages: true,
        autoSync: true,
        runner: runner,
      );
      expect(runner.tasks.map((t) => t.sourceId), [id]);
      runner.finish(SyncProgress(sourceId: id, phase: SyncPhase.cancelled));
      await settle(tester);
      await disposeApp(tester, db);
    });
  });

  group('app start', () {
    tearDown(() {
      LicenseRegistry.reset();
      resetFontLicensesForTest();
      setUpAppGlobals();
    });

    test('registers the font licence and Western digits', () async {
      LicenseRegistry.reset();
      resetFontLicensesForTest();
      DateFormat.useNativeDigitsByDefaultFor('ar', true);
      setUpAppGlobals();
      final licences = await LicenseRegistry.licenses.toList();
      expect(
        licences.where((l) => l.packages.contains(kTajawalLicensePackage)),
        hasLength(1),
      );
      expect(
        DateFormat.yMMMd('ar').format(DateTime(2026, 10, 15)),
        contains('2026'),
      );
    });
  });

  test('the app keeps its wiring in one place', () {
    // IptvApp is what bootstrap and the app tests run.
    expect(const IptvApp(), isA<ConsumerWidget>());
  });
}
