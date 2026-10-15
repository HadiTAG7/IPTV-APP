import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/shell_phone.dart';
import 'package:iptv_player/app/shell_tv.dart';

import 'app_harness.dart';

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
}
