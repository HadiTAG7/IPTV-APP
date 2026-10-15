import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/shell_phone.dart';
import 'package:iptv_player/app/shell_tv.dart';
import 'package:iptv_player/features/diagnostics/diagnostics_screen.dart';
import 'package:iptv_player/features/help/help_screen.dart';
import 'package:iptv_player/features/settings/settings_screen.dart';
import 'package:iptv_player/features/sources/sources_screen.dart';
import 'package:iptv_player/theme/tokens.dart';

import 'app_harness.dart';

/// Pages opened with [pushHomePage], and their screen types.
const _pushedPages = {
  HomeTab.settings: SettingsScreen,
  HomeTab.help: HelpScreen,
  HomeTab.sources: SourcesScreen,
  HomeTab.diagnostics: DiagnosticsScreen,
};

/// The real screens, with a Live page that pushes each of [_pushedPages].
Widget _openerPages(HomeTab tab) => tab == HomeTab.live
    ? Consumer(
        builder: (context, ref, _) => Wrap(
          children: [
            for (final page in _pushedPages.keys)
              TextButton(
                key: ValueKey('open-${page.name}'),
                onPressed: () => unawaited(pushHomePage(context, ref, page)),
                child: Text(page.name),
              ),
          ],
        ),
      )
    : defaultHomePage(tab);

/// Lets a route transition finish.
Future<void> _settleRoute(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The scaffold of the pushed page (the one with the app bar).
Finder get _pushedScaffold =>
    find.ancestor(of: find.byType(AppBar), matching: find.byType(Scaffold));

/// A page with a counter, to see whether its state survives.
class _CounterPage extends StatefulWidget {
  const _CounterPage(this.tab);

  final HomeTab tab;

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.topStart,
    child: TextButton(
      key: ValueKey('${widget.tab.name}-count'),
      onPressed: () => setState(() => _count++),
      child: Text('${widget.tab.name}:$_count'),
    ),
  );
}

void main() {
  const portrait = Size(800, 1280);
  const landscape = Size(1280, 800);

  Future<void> rotate(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 2;
    await settle(tester);
  }

  testWidgets('rotating a tablet keeps the selected tab and page state', (
    tester,
  ) async {
    final db = openAppTestDb();
    await addTestSource(db, lastSyncAt: DateTime.now());
    await pumpApp(
      tester,
      db: db,
      logicalSize: portrait,
      pages: _CounterPage.new,
    );
    expect(find.byType(PhoneShell), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-movies')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('movies-count')));
    await tester.tap(find.byKey(const ValueKey('movies-count')));
    await settle(tester);
    expect(find.text('movies:2'), findsOneWidget);

    await rotate(tester, landscape);
    expect(find.byType(TvShell), findsOneWidget);
    expect(
      tester.state<TvShellState>(find.byType(TvShell)).current,
      HomeTab.movies,
    );
    expect(find.text('movies:2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('movies-count')));
    await settle(tester);

    await rotate(tester, portrait);
    expect(find.byType(PhoneShell), findsOneWidget);
    expect(
      tester.state<PhoneShellState>(find.byType(PhoneShell)).current,
      HomeTab.movies,
    );
    expect(find.text('movies:3'), findsOneWidget);
    // Live (visited first) kept its state too.
    expect(find.text('live:0', skipOffstage: false), findsOneWidget);
    await disposeApp(tester, db);
  });

  testWidgets('a large-layout tab without a bar slot maps to More and back', (
    tester,
  ) async {
    final db = openAppTestDb();
    await addTestSource(db, lastSyncAt: DateTime.now());
    await pumpApp(
      tester,
      db: db,
      logicalSize: landscape,
      pages: _CounterPage.new,
    );
    expect(find.byType(TvShell), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rail-search')));
    await settle(tester);
    expect(find.text('search:0'), findsOneWidget);

    await rotate(tester, portrait);
    expect(
      tester.state<PhoneShellState>(find.byType(PhoneShell)).current,
      HomeTab.more,
    );
    expect(find.byKey(const ValueKey('more-search')), findsOneWidget);

    await rotate(tester, landscape);
    expect(
      tester.state<TvShellState>(find.byType(TvShell)).current,
      HomeTab.search,
    );
    expect(find.text('search:0'), findsOneWidget);

    // Back from a page on the phone still reaches its shell.
    await rotate(tester, portrait);
    await tester.tap(find.byKey(const ValueKey('nav-guide')));
    await settle(tester);
    expect(
      tester.state<PhoneShellState>(find.byType(PhoneShell)).handleBack(),
      isTrue,
    );
    await settle(tester);
    expect(
      tester.state<PhoneShellState>(find.byType(PhoneShell)).current,
      HomeTab.live,
    );
    await disposeApp(tester, db);
  });

  testWidgets('pages pushed on TV keep clear of the overscan, app bar too', (
    tester,
  ) async {
    final db = openAppTestDb();
    await addTestSource(db, lastSyncAt: DateTime.now());
    await pumpApp(tester, db: db, caps: tvCaps, pages: _openerPages);
    const screen = Size(960, 540);
    for (final MapEntry(key: tab, value: type) in _pushedPages.entries) {
      await tester.tap(find.byKey(ValueKey('open-${tab.name}')));
      await _settleRoute(tester);
      expect(find.byType(type), findsOneWidget, reason: tab.name);

      final bar = tester.getRect(find.byType(AppBar));
      expect(
        bar.topLeft.dx,
        greaterThanOrEqualTo(TvLayout.overscanHorizontal),
        reason: tab.name,
      );
      expect(
        bar.topLeft.dy,
        greaterThanOrEqualTo(TvLayout.overscanVertical),
        reason: tab.name,
      );
      expect(
        bar.right,
        lessThanOrEqualTo(screen.width - TvLayout.overscanHorizontal),
        reason: tab.name,
      );
      final page = tester.getRect(_pushedScaffold);
      expect(
        page.bottom,
        lessThanOrEqualTo(screen.height - TvLayout.overscanVertical),
        reason: tab.name,
      );

      // The screen adds no overscan margins of its own on top.
      final scroll = tester.widget<SingleChildScrollView>(
        find
            .descendant(
              of: find.byType(type),
              matching: find.byType(SingleChildScrollView),
            )
            .first,
      );
      final padding = scroll.padding!.resolve(TextDirection.ltr);
      expect(
        padding.left,
        lessThan(TvLayout.overscanHorizontal),
        reason: tab.name,
      );
      expect(
        padding.right,
        lessThan(TvLayout.overscanHorizontal),
        reason: tab.name,
      );
      expect(
        padding.bottom,
        lessThan(TvLayout.overscanVertical),
        reason: tab.name,
      );

      await tester.binding.handlePopRoute();
      await _settleRoute(tester);
      expect(find.byType(type), findsNothing, reason: tab.name);
    }
    await disposeApp(tester, db);
  });

  testWidgets('pages pushed on a phone fill the screen', (tester) async {
    final db = openAppTestDb();
    await addTestSource(db, lastSyncAt: DateTime.now());
    await pumpApp(tester, db: db, pages: _openerPages);
    for (final MapEntry(key: tab, value: type) in _pushedPages.entries) {
      await tester.tap(find.byKey(ValueKey('open-${tab.name}')));
      await _settleRoute(tester);
      expect(find.byType(type), findsOneWidget, reason: tab.name);
      expect(
        tester.getTopLeft(find.byType(AppBar)),
        Offset.zero,
        reason: tab.name,
      );
      expect(
        tester.getRect(_pushedScaffold),
        Offset.zero & const Size(390, 800),
        reason: tab.name,
      );
      await tester.binding.handlePopRoute();
      await _settleRoute(tester);
      expect(find.byType(type), findsNothing, reason: tab.name);
    }
    await disposeApp(tester, db);
  });
}
