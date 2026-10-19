// The player's Back on a slow server: its stream counts against a
// one-connection subscription until its engine has closed it (dispose
// stops it after an open still running), not only until the controller is
// disposed. A failed separate window's Retry waits for that. Synthetic
// data only.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/connection_budget.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';
import 'package:iptv_player/player/ui/player_screen.dart';
import 'package:iptv_player/sources/models.dart';

import '../support/fake_engine.dart';
import '../support/fake_viewer.dart';
import 'support/player_harness.dart';

Future<void> _until(
  WidgetTester tester,
  bool Function() done,
  String what,
) async {
  for (var i = 0; i < 400; i++) {
    if (done()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  fail('timed out: $what');
}

Future<(ProviderContainer, FakeViewerProcess, int)> _failedWindow(
  WidgetTester tester,
  PlayerRig rig,
  FakeViewerLauncher launcher,
) async {
  final xtream = await seedXtream(rig);
  await pumpPlayerApp(
    tester,
    rig,
    tv: false,
    platform: TargetPlatform.windows,
    overrides: [
      viewerLauncherProvider.overrideWithValue(launcher),
      viewerTimeoutsProvider.overrideWithValue(
        const ViewerTimeouts(
          start: Duration(hours: 1),
          handshake: Duration(hours: 1),
          close: Duration(milliseconds: 1),
        ),
      ),
    ],
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byKey(launcherKey)),
  );
  unawaited(
    container
        .read(detachedWindowsProvider.notifier)
        .detach(
          DetachRequest(
            sourceId: xtream,
            channelKey: '501',
            title: 'Panel News',
            stream: const StreamRequest(
              url: 'http://127.0.0.1:9/live/viewer7/Secret-Pass-9/501.ts',
              kind: PlayableKind.live,
            ),
            maxConnections: 1,
            secrets: const {'viewer7', 'Secret-Pass-9'},
          ),
        )
        .then<void>((_) {}, onError: (Object _) {}),
  );
  await _until(
    tester,
    () => launcher.processes.isNotEmpty && launcher.last.received.isNotEmpty,
    'window ready',
  );
  final p = launcher.last
    ..send(const OpeningMessage())
    ..send(const ViewerErrorMessage('HTTP error 404'));
  await _until(
    tester,
    () =>
        container.read(detachedWindowsProvider).single.status ==
        ViewerStatus.failed,
    'window failed',
  );
  return (container, p, xtream);
}

Future<void> _back(WidgetTester tester, ProviderContainer container) async {
  for (var i = 0; i < 3; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    if (container.read(connectionDrainsProvider).isNotEmpty) break;
  }
  expect(container.read(connectionDrainsProvider), hasLength(1));
}

/// Pumps 15 s; returns whether the player's engine still had its stream
/// open when the window was told to play again (null: it never was).
Future<bool?> _openWhenWindowPlays(
  WidgetTester tester,
  FakeViewerProcess p,
  FakeEngine sport,
  ProviderContainer container,
) async {
  bool? open;
  for (var i = 0; i < 150; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    if (p.received.whereType<PlayMessage>().length == 2 && open == null) {
      open = sport.streamOpen;
    }
  }
  return open;
}

void main() {
  testWidgets('Back while Panel Sport still opens, its engine slow to go '
      '(dispose stops the stream, 3 s): the window\'s Retry never plays '
      'while the player\'s stream is open', (tester) async {
    final rig = PlayerRig();
    final launcher = FakeViewerLauncher();
    final (container, p, xtream) = await _failedWindow(tester, rig, launcher);
    FakeEngine? sport;
    rig.engines.onCreate = (e) {
      // Like MpvEngine on media_kit: dispose stops the core under the
      // player's lock, which the open still running holds (~9 s).
      e.disposeDelay = const Duration(seconds: 9);
      e.onOpen = (e, r) async {
        if (r.url.contains('/502.') && sport == null) {
          sport = e;
          await Future<void>.delayed(const Duration(seconds: 9));
        }
        e.emitFirstFrame();
      };
    };
    await openPlayerFor(tester, xtreamRequest(xtream, '502'));
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(sport!.streamOpen, isTrue);

    await _back(tester, container);
    p.send(const RetryMessage());
    await _until(
      tester,
      () => rig.log.dump().contains('retry waits for a stream to stop'),
      'retry waiting',
    );
    final open = await _openWhenWindowPlays(tester, p, sport!, container);
    expect(open, isNotNull, reason: 'the Retry never played');
    expect(
      open,
      isFalse,
      reason: 'the window played while the player\'s stream was still open',
    );
    await tester.pump(const Duration(seconds: 10));
    await tester.runAsync(
      container.read(detachedWindowsProvider.notifier).closeAll,
    );
    await disposeRig(tester, rig);
  });

  testWidgets('Back while Panel Sport plays, its stop slow (3 s; dispose '
      'waits for it): the window\'s Retry never plays while the player\'s '
      'stream is open', (tester) async {
    final rig = PlayerRig();
    final launcher = FakeViewerLauncher();
    final (container, p, xtream) = await _failedWindow(tester, rig, launcher);
    FakeEngine? sport;
    rig.engines.onCreate = (e) {
      e
        ..stopDelay = const Duration(seconds: 3)
        ..disposeDelay = const Duration(seconds: 3);
      e.onOpen = (e, r) async {
        if (r.url.contains('/502.')) sport = e;
        e.emitFirstFrame();
      };
    };
    await openPlayerFor(tester, xtreamRequest(xtream, '502'));
    await settle(tester);
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(sport!.streamOpen, isTrue);

    await _back(tester, container);
    p.send(const RetryMessage());
    await _until(
      tester,
      () => rig.log.dump().contains('retry waits for a stream to stop'),
      'retry waiting',
    );
    final open = await _openWhenWindowPlays(tester, p, sport!, container);
    expect(open, isNotNull, reason: 'the Retry never played');
    expect(
      open,
      isFalse,
      reason: 'the window played while the player\'s stream was still open',
    );
    await tester.pump(const Duration(seconds: 10));
    await tester.runAsync(
      container.read(detachedWindowsProvider.notifier).closeAll,
    );
    await disposeRig(tester, rig);
  });
}
