import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/ui/player_screen.dart';

import 'support/player_harness.dart';

const _osd = ValueKey('player-osd');

String _url(String key) => 'http://127.0.0.1:9/live/$key.ts';

void main() {
  // Windows sends WM_MOUSEMOVE when SetWindowPos moves/resizes the window
  // under a resting cursor (the client origin moves, so the client
  // coordinates change); the embedder forwards it as a hover.
  testWidgets('the hover from the fullscreen resize does not steal the '
      'keyboard (Up still zaps)', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpPlayerApp(
      tester,
      rig,
      tv: false,
      platform: TargetPlatform.windows,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(590, 269));
    await settle(tester);

    await openPlayerFor(tester, liveRequest(id));
    expect(rig.window, ['enter']);
    // OS mouse move after enter(): same screen point, new client coords.
    await mouse.moveTo(const Offset(608, 300));
    await settle(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(rig.openedUrls.last, _url('ch2'), reason: 'Up should zap');
    await disposeRig(tester, rig);
  });

  testWidgets('two Escapes leave the player even with the hover from the '
      'restore resize', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpPlayerApp(
      tester,
      rig,
      tv: false,
      platform: TargetPlatform.windows,
    );
    await openPlayerFor(tester, liveRequest(id));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(600, 300));
    await settle(tester);
    expect(find.byKey(_osd), findsNothing);

    await press(tester, LogicalKeyboardKey.escape);
    expect(rig.window, ['enter', 'exit']);
    // OS mouse move after the window shrinks back under the resting cursor.
    await mouse.moveTo(const Offset(582, 259));
    await settle(tester);

    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.byType(PlayerScreen),
      findsNothing,
      reason: 'second Escape should be Back',
    );
    await disposeRig(tester, rig);
  });
}
