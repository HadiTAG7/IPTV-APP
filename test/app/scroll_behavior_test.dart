import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/scroll_behavior.dart';

const _back = ValueKey('row-scroll-back');
const _forward = ValueKey('row-scroll-forward');

/// A 400-wide screen with a 30-chip row (100 each), on its own or above a
/// tall list in a vertical page.
Future<({ScrollController row, ScrollController page})> _pump(
  WidgetTester tester, {
  TextDirection direction = TextDirection.ltr,
  bool inPage = false,
}) async {
  tester.view.physicalSize = const Size(400, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final row = ScrollController();
  final page = ScrollController();
  addTearDown(row.dispose);
  addTearDown(page.dispose);
  final chips = SizedBox(
    height: 52,
    child: ListView.builder(
      controller: row,
      scrollDirection: Axis.horizontal,
      itemCount: 30,
      itemExtent: 100,
      itemBuilder: (_, i) => Center(child: Text('chip $i')),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: inPage
              ? ListView(
                  controller: page,
                  children: [
                    chips,
                    for (var i = 0; i < 30; i++)
                      SizedBox(height: 80, child: Text('row $i')),
                  ],
                )
              : Column(children: [chips]),
        ),
      ),
    ),
  );
  await tester.pump();
  return (row: row, page: page);
}

Future<void> _wheel(WidgetTester tester, Offset at, double dy) async {
  final mouse = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(mouse.hover(at));
  await tester.sendEventToBinding(mouse.scroll(Offset(0, dy)));
  await tester.pump();
}

void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.windows);

  testWidgets('the wheel moves a row on its own sideways', (tester) async {
    final c = await _pump(tester);
    await _wheel(tester, const Offset(200, 26), 120);
    expect(c.row.offset, 120);
    await _wheel(tester, const Offset(200, 26), -120);
    expect(c.row.offset, 0);
    // Nothing to move toward the start: nothing happens.
    await _wheel(tester, const Offset(200, 26), -120);
    expect(c.row.offset, 0);
  }, variant: desktop);

  testWidgets('inside a page the page scrolls first, then the row', (
    tester,
  ) async {
    final c = await _pump(tester, inPage: true);
    await _wheel(tester, const Offset(200, 26), 120);
    expect(c.page.offset, 120);
    expect(c.row.offset, 0);

    // At the top of the page, wheeling up moves the row back.
    c.page.jumpTo(0);
    c.row.jumpTo(200);
    await tester.pump();
    await _wheel(tester, const Offset(200, 26), -120);
    expect(c.page.offset, 0);
    expect(c.row.offset, 80);
  }, variant: desktop);

  testWidgets('arrows page the row and show only where there is more', (
    tester,
  ) async {
    final c = await _pump(tester);
    expect(find.byKey(_back), findsNothing);
    expect(find.byKey(_forward), findsOneWidget);
    expect(tester.getCenter(find.byKey(_forward)).dx, greaterThan(300));

    await tester.tap(find.byKey(_forward));
    await tester.pumpAndSettle();
    expect(c.row.offset, closeTo(320, 0.1));
    expect(find.byKey(_back), findsOneWidget);

    await tester.tap(find.byKey(_back));
    await tester.pumpAndSettle();
    expect(c.row.offset, 0);
    expect(find.byKey(_back), findsNothing);

    c.row.jumpTo(c.row.position.maxScrollExtent);
    await tester.pump();
    expect(find.byKey(_forward), findsNothing);
  }, variant: desktop);

  testWidgets('right to left: more lies to the left', (tester) async {
    final c = await _pump(tester, direction: TextDirection.rtl);
    expect(find.byKey(_back), findsNothing);
    expect(tester.getCenter(find.byKey(_forward)).dx, lessThan(100));
    await _wheel(tester, const Offset(200, 26), 120);
    expect(c.row.offset, 120);
    expect(find.byKey(_back), findsOneWidget);
    expect(tester.getCenter(find.byKey(_back)).dx, greaterThan(300));
  }, variant: desktop);

  testWidgets('a row that fits shows no arrows and lets the page scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final page = ScrollController();
    addTearDown(page.dispose);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: ListView(
            controller: page,
            children: [
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: const [Text('one'), Text('two')],
                ),
              ),
              for (var i = 0; i < 30; i++) const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(_forward), findsNothing);
    await _wheel(tester, const Offset(200, 26), 120);
    expect(page.offset, 120);
  }, variant: desktop);

  testWidgets('phones and TVs keep touch and the remote only', (tester) async {
    final c = await _pump(tester);
    expect(find.byKey(_forward), findsNothing);
    await _wheel(tester, const Offset(200, 26), 120);
    expect(c.row.offset, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
