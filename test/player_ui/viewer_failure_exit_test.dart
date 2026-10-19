// A detached window whose stream failed while fullscreen: the frameless
// fullscreen window has no title bar or X, so its failure card offers Exit
// fullscreen and Close to the mouse and the keyboard; Escape still leaves
// fullscreen first. Synthetic data only.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';

import '../support/fake_engine.dart';
import 'support/viewer_harness.dart';

const _play = PlayMessage(
  url: 'http://127.0.0.1:9/live/viewer7/Secret-Pass-9/501.ts',
  title: 'Panel News',
  channelKey: '501',
  maxConnections: 1,
  secrets: ['viewer7', 'Secret-Pass-9'],
);

const _exitFullscreen = ValueKey('player-exit-fullscreen');
const _close = ValueKey('player-close');

void main() {
  late FakeViewerChannel channel;
  late FakeEngineFactory engines;
  late List<String> window;
  late List<int> exits;

  /// Fullscreen on the second monitor, then the stream fails for good (the
  /// panel refuses it).
  Future<void> failInFullscreen(WidgetTester tester) async {
    channel = FakeViewerChannel();
    engines = FakeEngineFactory();
    window = [];
    exits = [];
    await pumpViewer(
      tester,
      channel: channel,
      engines: engines,
      window: recordingWindowControls(window),
      exits: exits,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await settleViewer(tester);
    expect(window, ['enterFullscreen']);
    await failViewer(tester, channel, engines, _play);
  }

  testWidgets('the mouse reaches Exit fullscreen and Close', (tester) async {
    await failInFullscreen(tester);
    // A mouse user moves the mouse, as for the bar.
    await hoverViewer(tester);
    expect(find.byKey(_exitFullscreen), findsOneWidget);
    expect(find.byKey(_close), findsOneWidget);

    await tester.tap(find.byKey(_exitFullscreen));
    await settleViewer(tester);
    expect(window.last, 'exitFullscreen');
    // Out of fullscreen: the window's own X is back; Close stays.
    expect(find.byKey(_exitFullscreen), findsNothing);
    expect(find.byKey(const ValueKey('player-failure')), findsOneWidget);

    await tester.tap(find.byKey(_close));
    await settleViewer(tester);
    expect(channel.sentTypes.last, 'closed');
    expect(exits, [1]);
    await unmountViewer(tester);
  });

  testWidgets('Escape leaves fullscreen first; the keyboard reaches Close', (
    tester,
  ) async {
    await failInFullscreen(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleViewer(tester);
    expect(window.last, 'exitFullscreen');
    expect(exits, isEmpty);
    expect(channel.sentTypes.last, 'error');

    // Retry has the keyboard; the next button is Close.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await settleViewer(tester);
    expect(
      Focus.of(tester.element(find.text('Close'))).hasPrimaryFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settleViewer(tester);
    expect(channel.sentTypes.last, 'closed');
    expect(exits, [1]);
    await unmountViewer(tester);
  });
}
