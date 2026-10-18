// On desktop the end fade of a scrolling row lets clicks and hover through
// to the chip under it; only the round arrow pages the row.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/scroll_behavior.dart';

/// A 400-wide window with a row of 100-wide chips: the forward arrow's fade
/// strip covers x 344..400, its 32 px circle x 364..396 / y 10..42, and
/// chip 3 spans x 300..400.
Future<({List<int> tapped, List<int> hovered})> _pump(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(400, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final tapped = <int>[];
  final hovered = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: 52,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 30,
              itemExtent: 100,
              itemBuilder: (_, i) => MouseRegion(
                onEnter: (_) => hovered.add(i),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => tapped.add(i),
                  child: Center(child: Text('chip $i')),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(find.byKey(const ValueKey('row-scroll-forward')), findsOneWidget);
  return (tapped: tapped, hovered: hovered);
}

void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.windows);

  testWidgets(
    'a click on a chip under the end fade, off the circle, presses it',
    (tester) async {
      final r = await _pump(tester);
      await tester.tapAt(const Offset(320, 26)); // control: outside the strip
      expect(r.tapped, [3]);
      await tester.tapAt(const Offset(350, 26)); // in the strip, left of circle
      expect(r.tapped, [3, 3]);
    },
    variant: desktop,
  );

  testWidgets('a chip under the end fade gets hover', (tester) async {
    final r = await _pump(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(200, 300));
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(const Offset(350, 26));
    await tester.pump();
    expect(r.hovered, [3]);
  }, variant: desktop);
}
