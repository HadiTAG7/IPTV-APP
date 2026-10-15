import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/app/shell_phone.dart';
import 'package:iptv_player/features/guide/guide_screen.dart';
import 'package:iptv_player/features/live/live_screen.dart';
import 'package:iptv_player/features/search/search_screen.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/sources/sync/sync_progress.dart';

import 'app_harness.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  testWidgets('bottom navigation switches tabs and keeps them', (tester) async {
    final db = openAppTestDb();
    await addTestSource(db, lastSyncAt: DateTime.now());
    await pumpApp(tester, db: db);
    expect(find.byType(PhoneShell), findsOneWidget);
    final bar = find.byType(NavigationBar);
    for (final label in [
      en.navLive,
      en.navGuide,
      en.navMovies,
      en.navSeries,
      en.navMore,
    ]) {
      expect(
        find.descendant(of: bar, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(find.byType(LiveScreen), findsOneWidget);
    expect(find.byType(GuideScreen), findsNothing); // built on first visit

    await tester.tap(find.byKey(const ValueKey('nav-guide')));
    await settle(tester);
    expect(find.byType(GuideScreen), findsOneWidget);
    expect(find.byType(LiveScreen), findsNothing); // offstage, still alive
    expect(find.byType(LiveScreen, skipOffstage: false), findsOneWidget);

    // Back on another tab returns to Live first.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(LiveScreen), findsOneWidget);
    expect(find.byType(GuideScreen, skipOffstage: false), findsOneWidget);
    await disposeApp(tester, db);
  });

  testWidgets('More lists the other destinations and pushes them', (
    tester,
  ) async {
    final db = openAppTestDb();
    await addTestSource(db, name: 'Home', lastSyncAt: DateTime.now());
    await pumpApp(tester, db: db);
    await tester.tap(find.byKey(const ValueKey('nav-more')));
    await settle(tester);
    expect(find.byType(MorePage), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    for (final item in HomeTab.phoneMoreItems) {
      expect(find.byKey(ValueKey('more-${item.name}')), findsOneWidget);
    }
    expect(find.text(en.helpTitle), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('more-search')));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(en.navSearch),
      ),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsNothing);
    expect(find.byType(MorePage), findsOneWidget);
    await disposeApp(tester, db);
  });

  testWidgets('switching the active source from More', (tester) async {
    final db = openAppTestDb();
    final now = DateTime.now();
    await addTestSource(db, name: 'Home', lastSyncAt: now);
    final cabin = await addTestSource(db, name: 'Cabin', lastSyncAt: now);
    await pumpApp(tester, db: db);
    await tester.tap(find.byKey(const ValueKey('nav-more')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('more-source')));
    await tester.pumpAndSettle();
    expect(find.text(en.navSwitchSource), findsNWidgets(2)); // tile + title
    await tester.tap(find.byKey(ValueKey('source-$cabin')));
    await tester.pumpAndSettle();
    expect(await db.sourcesDao.activeSourceId(), cabin);
    expect(find.text('Cabin'), findsOneWidget);
    await disposeApp(tester, db);
  });

  testWidgets('double back exits; Arabic labels', (tester) async {
    final db = openAppTestDb();
    await addTestSource(db, lastSyncAt: DateTime.now());
    var exits = 0;
    await pumpApp(
      tester,
      db: db,
      settings: const AppSettings(locale: AppLocaleSetting.ar),
      onExit: () => exits++,
    );
    expect(find.text(ar.navMore), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text(ar.commonPressBackAgainToExit), findsOneWidget);
    expect(exits, 0);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(exits, 1);
    await disposeApp(tester, db);
  });

  testWidgets('a slim progress bar while the active source syncs', (
    tester,
  ) async {
    final db = openAppTestDb();
    final id = await addTestSource(
      db,
      lastSyncAt: DateTime.now().subtract(const Duration(days: 2)),
    );
    final runner = ManualSyncRunner();
    await pumpApp(tester, db: db, autoSync: true, runner: runner);
    expect(runner.tasks.single.sourceId, id);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel(en.importTitle), findsOneWidget);

    runner.finish(SyncProgress(sourceId: id, phase: SyncPhase.done));
    await settle(tester);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await disposeApp(tester, db);
  });
}
