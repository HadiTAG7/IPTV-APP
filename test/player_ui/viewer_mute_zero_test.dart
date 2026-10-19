// At volume 0 the speaker button shows "muted" and says Unmute; pressing it
// (or M) brings the sound back at an audible volume. Synthetic data only.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';
import 'package:iptv_player/player/detach/viewer_screen.dart';

import '../support/fake_engine.dart';
import 'support/viewer_harness.dart';

const _speaker = ValueKey('viewer-mute');

Future<FakeEngine> _playing(WidgetTester tester) async {
  final channel = FakeViewerChannel();
  final engines = FakeEngineFactory()
    ..onCreate = (e) => e.onOpen = (e, _) => e.emitFirstFrame();
  await pumpViewer(tester, channel: channel, engines: engines);
  channel.deliver(
    const PlayMessage(url: 'http://127.0.0.1:9/live/501.ts', title: 'News'),
  );
  await settleViewer(tester);
  return engines.last;
}

/// Down (or the wheel) all the way to 0: ten steps from full volume.
Future<void> _toZero(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  }
  await settleViewer(tester);
}

void main() {
  testWidgets('the crossed-out speaker at volume 0 says Unmute and brings '
      'the sound back', (tester) async {
    final engine = await _playing(tester);
    await _toZero(tester);
    // Ten steps of 0.1 leave no rounding crumbs: exactly silent.
    expect(engine.volume, 0);

    await hoverViewer(tester);
    expect(
      find.descendant(
        of: find.byKey(_speaker),
        matching: find.byIcon(Icons.volume_off),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Unmute'), findsOneWidget);

    await tester.tap(find.byKey(_speaker));
    await settleViewer(tester);
    expect(engine.muted, isFalse);
    expect(engine.volume, ViewerScreen.unmuteVolume);
    expect(
      find.descendant(
        of: find.byKey(_speaker),
        matching: find.byIcon(Icons.volume_up),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Mute'), findsOneWidget);
    await unmountViewer(tester);
  });

  testWidgets('M at volume 0 while muted unmutes, audibly', (tester) async {
    final engine = await _playing(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await settleViewer(tester);
    expect(engine.muted, isTrue);
    await _toZero(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await settleViewer(tester);
    expect(engine.muted, isFalse);
    expect(engine.volume, greaterThanOrEqualTo(ViewerScreen.unmuteVolume));
    await unmountViewer(tester);
  });

  testWidgets('a louder volume than the default comes back as it was', (
    tester,
  ) async {
    final engine = await _playing(tester);
    // Full volume, then the slider straight to 0.
    await hoverViewer(tester);
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('viewer-volume')),
    );
    slider.onChanged!(0);
    await settleViewer(tester);
    expect(engine.volume, 0);

    await tester.tap(find.byKey(_speaker));
    await settleViewer(tester);
    expect(engine.volume, 1);
    expect(engine.muted, isFalse);
    await unmountViewer(tester);
  });
}
