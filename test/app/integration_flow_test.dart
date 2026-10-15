// The whole app on a phone against the fake panel, in English and Arabic:
// onboarding adds an Xtream source and imports it (the launch auto-sync
// leaves it alone, the guide is imported after it), Live lists channels,
// the player (fake engines) plays and zaps, Recent remembers the channels,
// Movies lists the newest title first and opens its detail page, Search
// finds a movie and opens its detail page, and Help's "Add as source"
// opens the editor filled in.
@Timeout(Duration(seconds: 180))
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/app/shell_tv.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/epg/epg_providers.dart';
import 'package:iptv_player/features/guide/guide_screen.dart';
import 'package:iptv_player/features/help/help_screen.dart';
import 'package:iptv_player/features/help/providers.dart';
import 'package:iptv_player/features/live/live_screen.dart';
import 'package:iptv_player/features/movies/movie_detail_screen.dart';
import 'package:iptv_player/features/onboarding/onboarding_screen.dart';
import 'package:iptv_player/features/search/search_screen.dart';
import 'package:iptv_player/features/settings/settings_screen.dart';
import 'package:iptv_player/features/sources/source_editor_screen.dart';
import 'package:iptv_player/player/player_providers.dart';
import 'package:iptv_player/player/ui/player_screen.dart';
import 'package:iptv_player/sources/sync/sync_service.dart';
import 'package:iptv_player/widgets/channel_tile.dart';
import 'package:iptv_player/widgets/poster_card.dart';

import '../features/sources/support.dart';
import '../support/fake_engine.dart';
import '../support/fake_panel.dart';
import '../support/real_http.dart';

const _user = 'flowUser';
const _pass = 'Flow-Pw-42';

/// Counts the syncs the app starts (the import, or an auto-sync after it).
class _CountingRunner implements SyncRunner {
  _CountingRunner(this.inner);

  final SyncRunner inner;
  final started = <int>[];

  @override
  SyncExecution start(
    AppDatabase db,
    SyncTask task,
    void Function(SyncProgress progress) onProgress,
  ) {
    started.add(task.sourceId);
    return inner.start(db, task, onProgress);
  }
}

/// Waits for the movie page's details, fetched from the panel.
Future<void> _detailsLoaded(WidgetTester tester) async {
  await pumpUntil(
    tester,
    () =>
        find.byKey(const ValueKey('vod-plot')).evaluate().isNotEmpty ||
        find.byKey(const ValueKey('vod-details-failed')).evaluate().isNotEmpty,
    reason: 'the movie details',
  );
  expect(find.byKey(const ValueKey('vod-details-failed')), findsNothing);
}

void main() {
  useRealHttp();

  for (final rtl in [false, true]) {
    final lang = rtl ? 'ar' : 'en';
    final l10n = rtl ? arL10n : enL10n;

    testWidgets('phone $lang: from onboarding to playing, Recent, Movies, '
        'Search and Help', (tester) async {
      final panel = (await tester.runAsync(
        () => FakePanel.start(
          username: _user,
          password: _pass,
          mediaDir: null,
          liveCount: 12,
          vodCount: 6,
          seriesCount: 3,
        ),
      ))!;
      addTearDown(() => tester.runAsync(panel.close));
      final db = openAppTestDb();
      final runner = _CountingRunner(inlineRunner());
      final engines = FakeEngineFactory(
        onCreate: (e) => e.onOpen = (e, _) => e.emitFirstFrame(),
      );
      await pumpApp(
        tester,
        db: db,
        settings: AppSettings(
          locale: rtl ? AppLocaleSetting.ar : AppLocaleSetting.en,
        ),
        runner: runner,
        // The launch auto-sync is on, as in the app.
        autoSync: true,
        realGuide: true,
        overrides: [
          engineFactoryBuilderProvider.overrideWithValue((_) => engines.call),
          playerWakelockProvider.overrideWithValue((_) {}),
        ],
      );
      final container = containerOf(tester);

      // --- Onboarding: add the Xtream source and import it.
      expect(find.byType(OnboardingScreen), findsOneWidget);
      await tapKey(tester, 'onboarding-add-source');
      await settleRoute(tester);
      await tapKey(tester, 'type-xtream');
      await typeInto(tester, 'field-server', panel.baseUrl);
      await typeInto(tester, 'field-username', _user);
      await typeInto(tester, 'field-password', _pass);
      await tapKey(tester, 'save');
      await pumpUntil(
        tester,
        () => find.byType(HomeShell).evaluate().isNotEmpty,
        reason: 'the home shell',
      );
      await settleRoute(tester);
      expect(find.byType(SourceEditorScreen), findsNothing);
      final id = container.read(activeSourceIdProvider)!;
      expect(runner.started, [id]);

      // --- Live lists the channels.
      await pumpUntil(
        tester,
        () => find.byType(ChannelTile).evaluate().isNotEmpty,
        reason: 'channel rows',
      );
      final channels = (await tester.runAsync(
        () => db.catalogDao.allChannelsPage(id, 0, 50),
      ))!;
      expect(channels, hasLength(12));
      final firstRow = tester.widget<ChannelTile>(
        find.byType(ChannelTile).first,
      );
      final first = channels.firstWhere((c) => c.name == firstRow.name);

      // The launch auto-sync does not import the fresh source again, and
      // the guide schedule imported the guide after the first sync.
      await pumpUntil(
        tester,
        () => container.read(guideRefreshProvider(id)) is GuideRefreshDone,
        reason: 'the guide import after the first sync',
      );
      final guide =
          container.read(guideRefreshProvider(id)) as GuideRefreshDone;
      expect(guide.result.imported, greaterThan(0));
      expect(runner.started, [id]);
      // Rows show what is on now.
      await pumpUntil(
        tester,
        () => tester
            .widgetList<ChannelTile>(find.byType(ChannelTile))
            .any((t) => t.nowTitle != null),
        reason: 'now/next in the rows',
      );

      // --- Play the first row, zap once, Back.
      await tester.tap(find.byType(ChannelTile).first);
      await settleRoute(tester);
      expect(find.byType(PlayerScreen), findsOneWidget);
      await pumpUntil(
        tester,
        () => engines.created.isNotEmpty && engines.last.opened.isNotEmpty,
        reason: 'the stream to open',
      );
      expect(engines.last.opened.last.url, contains('/live/$_user/$_pass/'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await pumpUntil(
        tester,
        () =>
            {
              for (final e in engines.created)
                for (final r in e.opened) r.url,
            }.length >=
            2,
        reason: 'the zap',
      );
      await back(tester);
      await settleRoute(tester);
      expect(find.byType(PlayerScreen), findsNothing);
      expect(find.byType(LiveView), findsOneWidget);

      // --- Recent has both channels, the zapped-to one first.
      final recent = (await tester.runAsync(
        () => db.recentDao.recentChannelKeys(id),
      ))!;
      expect(recent, hasLength(2));
      expect(recent.last, first.key);
      await tapKey(tester, 'live-chip-recent');
      await settle(tester);
      final recentRows = tester
          .widgetList<ChannelTile>(find.byType(ChannelTile))
          .map((t) => t.name)
          .toList();
      expect(recentRows, hasLength(2));
      expect(recentRows.last, first.name);

      // --- Movies: the newest title comes first and opens its page.
      await tester.tap(find.byKey(const ValueKey('nav-movies')));
      await settle(tester);
      await pumpUntil(
        tester,
        () =>
            find.byKey(const ValueKey('vod-grid-0')).evaluate().isNotEmpty &&
            tester
                .widget<PosterCard>(find.byKey(const ValueKey('vod-grid-0')))
                .title
                .isNotEmpty,
        reason: 'the movie grid',
      );
      final newest = panel.catalog.movies.last;
      expect(
        tester
            .widget<PosterCard>(find.byKey(const ValueKey('vod-grid-0')))
            .title,
        newest.name,
      );
      await tester.tap(find.byKey(const ValueKey('vod-grid-0')));
      await settleRoute(tester);
      expect(
        tester
            .widget<MovieDetailScreen>(find.byType(MovieDetailScreen))
            .movieKey,
        '${newest.id}',
      );
      await _detailsLoaded(tester);
      await back(tester);
      expect(find.byType(MovieDetailScreen), findsNothing);

      // --- Search (More) finds a movie and opens its detail page.
      final wanted = panel.catalog.movies[3]; // 'Test Movie 4'
      await tester.tap(find.byKey(const ValueKey('nav-more')));
      await settle(tester);
      await tapKey(tester, 'more-search');
      await settleRoute(tester);
      expect(find.byType(SearchScreen), findsOneWidget);
      await typeInto(tester, 'search-field', wanted.name);
      final result = find.byKey(ValueKey('search-movie-${wanted.id}'));
      await pumpUntil(
        tester,
        () => result.evaluate().isNotEmpty,
        reason: 'the search result',
      );
      await tapKey(tester, 'search-movie-${wanted.id}');
      await settleRoute(tester);
      expect(
        tester
            .widget<MovieDetailScreen>(find.byType(MovieDetailScreen))
            .movieKey,
        '${wanted.id}',
      );
      await _detailsLoaded(tester);
      await back(tester);
      expect(find.byType(SearchScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(SearchScreen), findsNothing);

      // --- Settings -> Help -> "Add as source": the editor, filled in.
      await tapKey(tester, 'more-settings');
      await settleRoute(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-help')),
        200,
        scrollable: find
            .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tapKey(tester, 'settings-help');
      await settleRoute(tester);
      expect(find.byType(HelpScreen), findsOneWidget);
      await tapKey(tester, 'help-url-sa');
      await settleRoute(tester);
      final editor = tester.widget<SourceEditorScreen>(
        find.byType(SourceEditorScreen),
      );
      expect(editor.onboarding, isFalse);
      expect(fieldText(tester, 'field-url'), kIptvOrgSaudiUrl);
      expect(
        fieldText(tester, 'field-name'),
        'iptv-org: ${l10n.help_iptvOrgSaudi}',
      );
      for (var i = 0; i < 3; i++) {
        await back(tester);
      }
      expect(find.byType(SourceEditorScreen), findsNothing);
      expect(find.byType(SettingsScreen), findsNothing);
      // Nothing was added, and nothing synced again.
      expect(await tester.runAsync(db.sourcesDao.all), hasLength(1));
      expect(runner.started, [id]);
      expect(container.read(ringLogProvider).dump(), isNot(contains(_pass)));

      await drainNetworkTimers(tester);
      await disposeApp(tester, db);
    });
  }

  testWidgets('TV en: the remote plays a Live channel; the Guide key '
      'closes the player on the Guide tab', (tester) async {
    final panel = (await tester.runAsync(
      () => FakePanel.start(
        username: _user,
        password: _pass,
        mediaDir: null,
        liveCount: 12,
        vodCount: 6,
        seriesCount: 3,
      ),
    ))!;
    addTearDown(() => tester.runAsync(panel.close));
    final db = openAppTestDb();
    final runner = _CountingRunner(inlineRunner());
    final engines = FakeEngineFactory(
      onCreate: (e) => e.onOpen = (e, _) => e.emitFirstFrame(),
    );
    await pumpApp(
      tester,
      db: db,
      caps: tvCaps,
      runner: runner,
      autoSync: true,
      realGuide: true,
      overrides: [
        engineFactoryBuilderProvider.overrideWithValue((_) => engines.call),
        playerWakelockProvider.overrideWithValue((_) {}),
      ],
    );
    final container = containerOf(tester);
    await tapKey(tester, 'onboarding-add-source');
    await settleRoute(tester);
    await tapKey(tester, 'type-xtream');
    await typeInto(tester, 'field-server', panel.baseUrl);
    await typeInto(tester, 'field-username', _user);
    await typeInto(tester, 'field-password', _pass);
    await tapKey(tester, 'save');
    await pumpUntil(
      tester,
      () => find.byType(HomeShell).evaluate().isNotEmpty,
      reason: 'the home shell',
    );
    await settleRoute(tester);
    final id = container.read(activeSourceIdProvider)!;
    await pumpUntil(
      tester,
      () => container.read(guideRefreshProvider(id)) is GuideRefreshDone,
      reason: 'the guide import after the first sync',
    );
    await pumpUntil(
      tester,
      () => find.byType(ChannelTile).evaluate().isNotEmpty,
      reason: 'channel rows',
    );

    // The rail has the focus; Right enters Live on a channel, OK plays it.
    expectFocus('rail-live');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedIn(const ValueKey('rail-live')), isFalse);
    await press(tester, LogicalKeyboardKey.select);
    await settleRoute(tester);
    expect(find.byType(PlayerScreen), findsOneWidget);
    await pumpUntil(
      tester,
      () => engines.created.isNotEmpty && engines.last.opened.isNotEmpty,
      reason: 'the stream to open',
    );

    await tester.sendKeyEvent(
      LogicalKeyboardKey.guide,
      physicalKey: PhysicalKeyboardKey.f1,
    );
    await settleRoute(tester);
    expect(find.byType(PlayerScreen), findsNothing);
    expect(
      tester.state<TvShellState>(find.byType(TvShell)).current,
      HomeTab.guide,
    );
    expect(find.byType(GuideScreen), findsOneWidget);
    // Focus moved into the guide page, not back to the rail.
    expect(focusedIn(const ValueKey('rail-guide')), isFalse);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<GuideScreen>(),
      isNotNull,
    );
    final recent = (await tester.runAsync(
      () => db.recentDao.recentChannelKeys(id),
    ))!;
    expect(recent, hasLength(1));
    expect(runner.started, [id]);

    await drainNetworkTimers(tester);
    await disposeApp(tester, db);
  });
}
