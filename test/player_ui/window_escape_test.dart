// docs/INSTALL_AR.md says the first Esc leaves fullscreen and the second
// goes back; that holds after the mouse showed the OSD too.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/ui/player_screen.dart';

import 'support/player_harness.dart';

void main() {
  testWidgets('two Escapes leave the player after the mouse moved', (
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
    // Past the moment mouse moves are ignored after the window changed.
    await tester.pump(const Duration(seconds: 1));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(600, 300));
    await mouse.moveTo(const Offset(640, 360));
    await settle(tester);
    expect(find.byKey(const ValueKey('player-osd')), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    expect(rig.window, ['enter', 'exit']);
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsNothing);
    await disposeRig(tester, rig);
  });
}
