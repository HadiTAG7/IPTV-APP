import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_harness.dart';

const _osd = ValueKey('player-osd');

String _url(String key) => 'http://127.0.0.1:9/live/$key.ts';

void main() {
  testWidgets('a desktop click shows the OSD and arrows still zap', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpPlayerApp(
      tester,
      rig,
      tv: false,
      platform: TargetPlatform.windows,
    );
    await openPlayerFor(tester, liveRequest(id));
    await tester.pump(const Duration(seconds: 1));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(640, 360));
    await mouse.down(const Offset(640, 360));
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.byKey(_osd), findsOneWidget);
    expect(focusLabel, 'player');

    await press(tester, LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(rig.openedUrls.last, _url('ch2'));
    expect(focusedIn(const ValueKey('player-osd-back')), isFalse);

    // OK hands the keyboard to the OSD.
    await mouse.moveTo(const Offset(650, 360));
    await settle(tester);
    await press(tester, LogicalKeyboardKey.enter);
    expect(focusLabel, 'player:osd-first');
    await disposeRig(tester, rig);
  });

  testWidgets('a key right after Right opens the OSD never zaps', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpPlayerApp(tester, rig);
    await openPlayerFor(tester, liveRequest(id));
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);
    // No frame between the two keys: focus has not reached the OSD yet.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(rig.openedUrls, [_url('ch1')]);
    expect(find.byKey(_osd), findsOneWidget);
    await disposeRig(tester, rig);
  });

  testWidgets('a key right after OK opens the channel panel never zaps', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpPlayerApp(tester, rig);
    await openPlayerFor(tester, liveRequest(id));
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);
    // No frame between the keys: the panel is not even built yet.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.channelUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);
    expect(rig.openedUrls, [_url('ch1')]);
    expect(find.byKey(const ValueKey('channel-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-number-badge')), findsNothing);
    await disposeRig(tester, rig);
  });

  testWidgets('a player removed in fullscreen leaves no timer behind', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpPlayerApp(
      tester,
      rig,
      tv: false,
      platform: TargetPlatform.windows,
    );
    await openPlayerFor(tester, liveRequest(id));
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);
    expect(rig.window, ['enter']);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(rig.window, ['enter', 'exit']);
    await tester.pump(const Duration(milliseconds: 100));
    await rig.db.close();
    // The test framework fails here if a timer is still pending.
  });
}
