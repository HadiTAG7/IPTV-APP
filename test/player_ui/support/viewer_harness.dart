// What the detached-window viewer tests share: an in-memory connection to
// the app and a pumped [ViewerScreen] with fake engines. Synthetic data
// only.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/core/platform/window_controls.dart';
import 'package:iptv_player/core/platform/window_fullscreen.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/player/detach/viewer_app.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';
import 'package:iptv_player/player/detach/viewer_screen.dart';

import '../../support/fake_engine.dart';

/// The app's end of the connection, in memory.
class FakeViewerChannel implements ViewerChannel {
  final _incoming = StreamController<ViewerMessage>();
  final _done = Completer<void>();
  final sent = <ViewerMessage>[];
  bool _closed = false;

  @override
  Stream<ViewerMessage> get messages => _incoming.stream;

  @override
  Future<void> get done => _done.future;

  @override
  bool get isClosed => _closed;

  @override
  bool send(ViewerMessage message) {
    if (_closed) return false;
    sent.add(message);
    return true;
  }

  @override
  Future<void> flush() async {}

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _done.complete();
    unawaited(_incoming.close());
  }

  /// A message from the app.
  void deliver(ViewerMessage message) => _incoming.add(message);

  List<String> get sentTypes => [for (final m in sent) m.type];
}

/// Window controls that record their calls in [calls].
WindowControls recordingWindowControls(
  List<String> calls, {
  bool supportsCompactAndPin = true,
  Stream<void> compactEnded = const Stream<void>.empty(),
}) => WindowControls(
  setAlwaysOnTop: (on) async => calls.add('top $on'),
  setTitle: (title) async => calls.add('title $title'),
  enterCompact: () async => calls.add('enterCompact'),
  exitCompact: () async => calls.add('exitCompact'),
  fullscreen: WindowFullscreen(
    enter: () async => calls.add('enterFullscreen'),
    exit: () async => calls.add('exitFullscreen'),
  ),
  supportsCompactAndPin: supportsCompactAndPin,
  compactEnded: compactEnded,
);

/// Pumps a 960x540 English [ViewerScreen] on [channel] with [engines].
/// Counts the process exits in [exits] when given.
Future<void> pumpViewer(
  WidgetTester tester, {
  required FakeViewerChannel channel,
  required FakeEngineFactory engines,
  WindowControls? window,
  TargetPlatform platform = TargetPlatform.windows,
  List<int>? exits,
}) async {
  tester.view
    ..physicalSize = const Size(960, 540) * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ViewerApp(
      locale: const Locale('en'),
      home: ViewerScreen(
        channel: channel,
        window: window ?? recordingWindowControls([]),
        exitProcess: () async => exits?.add(1),
        engines: (_) => engines.call,
        platform: platform,
        log: RingLog(),
        clock: FakeClock(DateTime.utc(2026, 10, 19, 20)),
      ),
    ),
  );
  await tester.pump();
}

/// Lets frames and fake engine events settle (fake time moves 250 ms).
Future<void> settleViewer(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Plays [play] on engines that always fail (a 404), until the window
/// gives up and shows its failure card: a one-connection stream is retried
/// twice first.
Future<void> failViewer(
  WidgetTester tester,
  FakeViewerChannel channel,
  FakeEngineFactory engines,
  PlayMessage play,
) async {
  engines.onCreate = (e) =>
      e.onOpen = (e, r) =>
          e.emitError('Failed to open ${r.url} (HTTP error 404 Not Found)');
  channel.deliver(play);
  await settleViewer(tester);
  await tester.pump(const Duration(seconds: 1));
  await settleViewer(tester);
  await tester.pump(const Duration(seconds: 2));
  await settleViewer(tester);
  expect(find.byKey(const ValueKey('player-failure')), findsOneWidget);
}

/// Moves a mouse over the window (shows the bar unless the stream failed).
Future<TestGesture> hoverViewer(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: const Offset(100, 100));
  await mouse.moveTo(const Offset(110, 105));
  await settleViewer(tester);
  return mouse;
}

/// Ends the viewer (its engines are disposed).
Future<void> unmountViewer(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
