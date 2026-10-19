// Detach waits for the player's stream to stop before the window opens it.
// Meanwhile the player takes no more clicks, and when the stop is done
// Detach closes the player's own route, never a dialog above it.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/player/ui/player_screen.dart';
import 'package:iptv_player/tv/dpad_shortcuts.dart';

import '../support/fake_engine.dart';
import 'support/fake_detached_windows.dart';
import 'support/player_harness.dart';

/// An engine whose stop waits for [gate] (a stalled stream closing).
class _SlowStopEngine extends FakeEngine {
  _SlowStopEngine(super.kind, {super.log});

  Completer<void>? gate;

  @override
  Future<void> stop() async {
    final g = gate;
    if (g != null) await g.future;
    await super.stop();
  }
}

class _SlowFactory extends FakeEngineFactory {
  @override
  PlayerEngine call(EngineKind kind) {
    final engine = _SlowStopEngine(kind, log: log);
    log.add('${kind.name}.create');
    created.add(engine);
    if (alive > maxAlive) maxAlive = alive;
    onCreate?.call(engine);
    return engine;
  }
}

class _Rig extends PlayerRig {
  @override
  // ignore: overridden_fields
  final engines = _SlowFactory();
}

/// Opens Panel News, shows the OSD with the mouse and clicks Separate
/// window while the stream takes long to stop; returns the stop's gate.
Future<Completer<void>> _detachSlowly(
  WidgetTester tester,
  _Rig rig,
  RecordingDetachedWindows windows,
) async {
  final id = await seedXtream(rig);
  await pumpPlayerApp(
    tester,
    rig,
    tv: false,
    platform: TargetPlatform.windows,
    overrides: [detachedWindowsProvider.overrideWith(() => windows)],
  );
  await openPlayerFor(tester, xtreamRequest(id, '501'));
  await tester.pump(const Duration(seconds: 1));
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: const Offset(600, 300));
  await mouse.moveTo(const Offset(640, 360));
  await settle(tester);
  expect(find.byKey(const ValueKey('player-osd-aspect')), findsOneWidget);

  final gate = Completer<void>();
  (rig.engine as _SlowStopEngine).gate = gate;
  await tester.tap(find.byKey(const ValueKey('player-osd-detach')));
  await settle(tester);
  // Still stopping: the player is up, the window not opened yet.
  expect(find.byType(PlayerScreen), findsOneWidget);
  expect(windows.detached, isEmpty);
  return gate;
}

void main() {
  testWidgets('while the stream stops the player takes no more clicks or '
      'keys; then it closes and the window opens', (tester) async {
    final rig = _Rig()..autoPlay();
    final windows = RecordingDetachedWindows(rig);
    final gate = await _detachSlowly(tester, rig, windows);

    // The OSD is gone; the mouse and the options key open nothing.
    expect(find.byKey(const ValueKey('player-osd')), findsNothing);
    await tester.tapAt(const Offset(640, 360));
    await settle(tester);
    await tester.sendKeyEvent(menuKey);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(windows.detached, hasLength(1));
    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(launcherKey), findsOneWidget);
    await disposeRig(tester, rig);
  });

  testWidgets('a dialog that opened above the player meanwhile stays; the '
      'player under it closes', (tester) async {
    final rig = _Rig()..autoPlay();
    final windows = RecordingDetachedWindows(rig);
    final gate = await _detachSlowly(tester, rig, windows);

    // Something else in the app shows a dialog on top meanwhile.
    unawaited(
      showDialog<void>(
        context: tester.element(find.byKey(launcherKey, skipOffstage: false)),
        builder: (_) => const AlertDialog(content: Text('Elsewhere')),
      ),
    );
    await settle(tester);
    expect(find.text('Elsewhere'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(windows.detached, hasLength(1));
    expect(find.byType(PlayerScreen, skipOffstage: false), findsNothing);
    expect(find.text('Elsewhere'), findsOneWidget);

    // Leaving the dialog shows the page the player was opened from.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Elsewhere'), findsNothing);
    expect(find.byType(PlayerScreen, skipOffstage: false), findsNothing);
    expect(find.byKey(launcherKey), findsOneWidget);
    await disposeRig(tester, rig);
  });
}
