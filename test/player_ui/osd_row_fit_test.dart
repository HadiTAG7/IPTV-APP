// The live OSD's buttons, Stats included, fit the TV canvas and an
// 800 dp landscape phone. All data is synthetic.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_harness.dart';

const _osd = ValueKey('player-osd');
const _stats = ValueKey('player-osd-stats');

ScrollPosition _rowPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.ancestor(
          of: find.byKey(_stats),
          matching: find.byType(SingleChildScrollView),
        ),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

void main() {
  testWidgets('TV: every live OSD button is on screen', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpPlayerApp(tester, rig);
    await openPlayerFor(tester, liveRequest(id));
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.byKey(_osd), findsOneWidget);
    final stats = tester.getRect(find.byKey(_stats));
    expect(_rowPosition(tester).maxScrollExtent, 0);
    expect(stats.right, lessThanOrEqualTo(960 - 48 - 16));
    await disposeRig(tester, rig);
  });

  testWidgets('800 x 360 landscape phone: every live OSD button is on screen', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpPlayerApp(tester, rig, tv: false);
    tester.view.physicalSize = const Size(800, 360) * 2;
    await tester.pump();
    await openPlayerFor(tester, liveRequest(id));
    await tester.tapAt(const Offset(400, 180));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.byKey(_osd), findsOneWidget);
    final stats = tester.getRect(find.byKey(_stats));
    expect(_rowPosition(tester).maxScrollExtent, 0);
    expect(stats.right, lessThanOrEqualTo(800 - 16));
    await disposeRig(tester, rig);
  });
}
