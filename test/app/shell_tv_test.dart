import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/app/shell_tv.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/sources/source_repository.dart';
import 'package:iptv_player/sources/sync/sync_progress.dart';

import 'app_harness.dart';

const _rail = ValueKey('rail-live');
Key _railKey(HomeTab tab) => ValueKey('rail-${tab.name}');
Key _item(HomeTab tab, String s) => ValueKey('${tab.name}-$s');

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  Future<AppDatabase> pumpTvShell(
    WidgetTester tester,
    AppSettings settings, {
    void Function()? onExit,
    Clock? clock,
  }) async {
    final db = openAppTestDb();
    await addTestSource(db, lastSyncAt: DateTime.now());
    await pumpApp(
      tester,
      db: db,
      caps: tvCaps,
      settings: settings,
      fakePages: true,
      onExit: onExit,
      clock: clock,
    );
    expect(find.byType(TvShell), findsOneWidget);
    return db;
  }

  for (final rtl in [false, true]) {
    final name = rtl ? 'ar (RTL)' : 'en';
    final toContent = rtl
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight;
    final toRail = rtl
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;

    testWidgets('$name: rail and content cross with mirrored arrows', (
      tester,
    ) async {
      final db = await pumpTvShell(
        tester,
        AppSettings(locale: rtl ? AppLocaleSetting.ar : AppLocaleSetting.en),
      );
      final l10n = rtl ? ar : en;
      expect(find.text(l10n.navGuide), findsOneWidget);

      // The rail is on the start side: left in English, right in Arabic.
      final railX = tester.getCenter(find.byKey(_rail)).dx;
      final pageX = tester.getCenter(find.byKey(_item(HomeTab.live, 'A'))).dx;
      expect(rtl ? railX > pageX : railX < pageX, isTrue);

      // Initial focus: the selected rail item.
      expect(focusedIn(_rail), isTrue);

      // Down moves through the rail and shows each tab.
      expect(find.text('guide-A'), findsNothing);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(_railKey(HomeTab.guide)), isTrue);
      expect(find.text('guide-A'), findsOneWidget);
      expect(find.text('live-A'), findsNothing); // kept, but offstage

      // Toward the content enters the page at its first item.
      await press(tester, toContent);
      expect(focusedIn(_item(HomeTab.guide, 'A')), isTrue);
      await press(tester, toContent);
      expect(focusedIn(_item(HomeTab.guide, 'B')), isTrue);
      // At the far edge nothing happens.
      await press(tester, toContent);
      expect(focusedIn(_item(HomeTab.guide, 'B')), isTrue);

      // Toward the rail walks back, then crosses to the selected rail item.
      await press(tester, toRail);
      expect(focusedIn(_item(HomeTab.guide, 'A')), isTrue);
      await press(tester, toRail);
      expect(focusedIn(_railKey(HomeTab.guide)), isTrue);
      // The rail's own edge does nothing.
      await press(tester, toRail);
      expect(focusedIn(_railKey(HomeTab.guide)), isTrue);

      // Each tab remembers its focused item (Back jumps to the rail).
      await press(tester, toContent);
      await press(tester, toContent);
      expect(focusedIn(_item(HomeTab.guide, 'B')), isTrue);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(focusedIn(_railKey(HomeTab.guide)), isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedIn(_rail), isTrue);
      expect(find.text('live-A'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, toContent);
      expect(focusedIn(_item(HomeTab.guide, 'B')), isTrue);

      // OK on a rail item opens that tab and moves into it.
      await press(tester, toRail);
      await press(tester, toRail);
      for (var i = 0; i < 5; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(focusedIn(_railKey(HomeTab.settings)), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(focusedIn(_item(HomeTab.settings, 'A')), isTrue);
      final shell = tester.state<TvShellState>(find.byType(TvShell));
      expect(shell.current, HomeTab.settings);

      // Up from the first rail item reaches the source switcher.
      await press(tester, toRail);
      for (var i = 0; i < 7; i++) {
        await press(tester, LogicalKeyboardKey.arrowUp);
      }
      expect(focusedIn(const ValueKey('rail-source')), isTrue);
      await disposeApp(tester, db);
    });
  }

  testWidgets('back: content -> rail -> press again to exit', (tester) async {
    final clock = FakeClock(DateTime.utc(2026, 10, 15, 20));
    var exits = 0;
    final db = await pumpTvShell(
      tester,
      const AppSettings(locale: AppLocaleSetting.en),
      onExit: () => exits++,
      clock: clock,
    );
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedIn(_item(HomeTab.live, 'A')), isTrue);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(focusedIn(_rail), isTrue);
    expect(find.text(en.commonPressBackAgainToExit), findsNothing);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text(en.commonPressBackAgainToExit), findsOneWidget);
    expect(exits, 0);

    // Too late: the window is 2 s, so this only shows the hint again.
    clock.advance(const Duration(seconds: 3));
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(exits, 0);

    clock.advance(const Duration(seconds: 1));
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(exits, 1);
    await disposeApp(tester, db);
  });

  testWidgets('a page handles Back before the shell', (tester) async {
    final db = openAppTestDb();
    await addTestSource(db, lastSyncAt: DateTime.now());
    var pending = 1;
    var calls = 0;
    await pumpApp(
      tester,
      db: db,
      caps: tvCaps,
      pages: (tab) => HomeTabBackHandler(
        onBack: () {
          calls++;
          return pending-- > 0;
        },
        child: FakeTabPage(tab),
      ),
    );
    // On the rail the page is not asked.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(calls, 0);
    expect(find.text(en.commonPressBackAgainToExit), findsOneWidget);

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedIn(_item(HomeTab.live, 'A')), isTrue);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(calls, 1);
    expect(focusedIn(_item(HomeTab.live, 'A')), isTrue);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(calls, 2);
    expect(focusedIn(_rail), isTrue);
    await disposeApp(tester, db);
  });

  testWidgets('source switcher lists sources and sets the active one', (
    tester,
  ) async {
    final db = openAppTestDb();
    final now = DateTime.now();
    await addTestSource(db, name: 'Home', lastSyncAt: now);
    final second = await addTestSource(db, name: 'Cabin', lastSyncAt: now);
    await pumpApp(tester, db: db, caps: tvCaps, fakePages: true);
    expect(find.text('Home'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedIn(const ValueKey('rail-source')), isTrue);
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text(en.navSwitchSource), findsOneWidget);
    expect(focusedIn(const ValueKey('source-1')), isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedIn(ValueKey('source-$second')), isTrue);
    await press(tester, LogicalKeyboardKey.select);
    await settle(tester);

    expect(find.text(en.navSwitchSource), findsNothing);
    expect(find.text('Cabin'), findsOneWidget);
    expect(await db.sourcesDao.activeSourceId(), second);
    // Focus came back to the switcher after the dialog closed.
    expect(focusedIn(const ValueKey('rail-source')), isTrue);

    // Reopened, the dialog starts on the active source.
    await press(tester, LogicalKeyboardKey.select);
    expect(focusedIn(ValueKey('source-$second')), isTrue);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text(en.navSwitchSource), findsNothing);
    expect(await db.sourcesDao.activeSourceId(), second);
    await disposeApp(tester, db);
  });

  testWidgets('auto-sync on start shows progress, then a failure', (
    tester,
  ) async {
    final db = openAppTestDb();
    final id = await addTestSource(db);
    final runner = ManualSyncRunner();
    await pumpApp(
      tester,
      db: db,
      caps: tvCaps,
      fakePages: true,
      autoSync: true,
      runner: runner,
    );
    expect(runner.tasks.single.sourceId, id);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    runner.finish(
      SyncProgress(
        sourceId: id,
        phase: SyncPhase.failed,
        error: const VerifyError(VerifyErrorReason.unreachable),
      ),
    );
    await settle(tester);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text(en.errorUnreachable), findsOneWidget);
    // Once per launch: the failed source is not retried in a loop.
    expect(runner.tasks, hasLength(1));
    await disposeApp(tester, db);
  });

  testWidgets('no auto-sync when the catalog is fresh', (tester) async {
    final db = openAppTestDb();
    await addTestSource(
      db,
      lastSyncAt: DateTime.now().subtract(const Duration(hours: 2)),
    );
    final runner = ManualSyncRunner();
    await pumpApp(
      tester,
      db: db,
      caps: tvCaps,
      fakePages: true,
      autoSync: true,
      runner: runner,
    );
    expect(runner.tasks, isEmpty);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await disposeApp(tester, db);
  });

  testWidgets('the real feature stubs render in every tab', (tester) async {
    final db = openAppTestDb();
    await addTestSource(db, lastSyncAt: DateTime.now());
    await pumpApp(tester, db: db, caps: tvCaps);
    for (final tab in HomeTab.tvTabs.skip(1)) {
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(
        find.text(tab.label(en)),
        findsNWidgets(2), // rail label + page title
        reason: tab.name,
      );
    }
    await disposeApp(tester, db);
  });
}
