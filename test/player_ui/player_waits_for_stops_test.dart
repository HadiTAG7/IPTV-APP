// The player opened while a stream of its one-connection subscription is
// still stopping waits for it, and holds its place meanwhile: a failed
// separate window's Retry is told that the main window uses the
// connection, and once the stream has stopped only the player plays.
// Synthetic data only (127.0.0.1 URLs, made-up credentials).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/connection_budget.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';
import 'package:iptv_player/player/ui/player_screen.dart';
import 'package:iptv_player/sources/models.dart';

import '../support/fake_viewer.dart';
import 'support/player_harness.dart';

/// Pumps, with real time for the loopback sockets, until [done].
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

void main() {
  testWidgets('a failed window\'s Retry while the player waits is refused '
      'as in use in the main window; then only the player plays', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final launcher = FakeViewerLauncher();
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
    final windows = container.read(detachedWindowsProvider.notifier);

    // A separate window on the subscription (one connection), failed: it
    // holds no connection.
    unawaited(
      windows
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

    // A split-screen tile's stream of the subscription still stopping.
    final stopped = Completer<void>();
    container
        .read(connectionDrainsProvider.notifier)
        .add(xtream, stopped.future);

    // Panel Sport in the main window waits, and holds its place.
    await openPlayerFor(tester, xtreamRequest(xtream, '502'));
    expect(find.byKey(const ValueKey('player-wait-stops')), findsOneWidget);
    expect(find.byType(PlayerScreen), findsNothing);
    expect(container.read(mainPlayerSourceProvider), xtream);

    p.send(const RetryMessage());
    await _until(
      tester,
      () => p.received.whereType<InUseMessage>().isNotEmpty,
      'window answered',
    );
    expect(
      p.received.whereType<InUseMessage>().single.by,
      ConnectionInUseBy.mainWindow,
    );
    expect(p.received.whereType<PlayMessage>(), hasLength(1));

    stopped.complete();
    await settle(tester);
    await _until(
      tester,
      () => rig.openedUrls.any((u) => u.contains('/502.')),
      'player opened',
    );
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(p.received.whereType<PlayMessage>(), hasLength(1));
    expect(
      container.read(detachedWindowsProvider).single.status,
      ViewerStatus.failed,
    );
    await tester.runAsync(windows.closeAll);
    await disposeRig(tester, rig);
  });
}
