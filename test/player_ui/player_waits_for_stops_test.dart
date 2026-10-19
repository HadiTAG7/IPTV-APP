// The player and a failed separate window on the same one-connection
// subscription. The player opened while a stream of the subscription is
// still stopping waits for it, and holds its place meanwhile. The player
// giving up a stream still opening (Back, D, S) counts it until it has
// stopped, and after D or S until the window or the split screen's first
// tile has it: a window's Retry meanwhile waits, and never plays while that
// stream is open. Synthetic data only (127.0.0.1 URLs, made-up
// credentials).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/connection_budget.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';
import 'package:iptv_player/player/multiview/multiview_screen.dart';
import 'package:iptv_player/player/ui/player_screen.dart';
import 'package:iptv_player/sources/models.dart';

import '../support/fake_engine.dart';
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

/// The app with a separate window on the Xtream subscription (one
/// connection) that failed: it holds no connection. Returns the app's
/// providers, the window's process and the subscription.
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

/// The player plays Panel Sport (502) on a slow server: its first open
/// takes 9 s. Returns its engine.
Future<FakeEngine> _slowSport(
  WidgetTester tester,
  PlayerRig rig,
  ProviderContainer container,
  int xtream,
) async {
  FakeEngine? sport;
  rig.engines.onCreate = (e) => e.onOpen = (e, r) async {
    if (r.url.contains('/502.') && sport == null) {
      sport = e;
      await Future<void>.delayed(const Duration(seconds: 9));
    }
    e.emitFirstFrame();
  };
  await openPlayerFor(tester, xtreamRequest(xtream, '502'));
  expect(find.byType(PlayerScreen), findsOneWidget);
  expect(sport!.streamOpen, isTrue);
  expect(container.read(connectionBudgetProvider).usedOn(xtream), 1);
  return sport!;
}

/// The window's Retry (sent while the player's stream still opens) waits
/// for that stream: nothing plays in the window yet.
Future<void> _retryWaits(
  WidgetTester tester,
  PlayerRig rig,
  FakeViewerProcess p,
) async {
  p.send(const RetryMessage());
  await _until(
    tester,
    () => rig.log.dump().contains('retry waits for a stream to stop'),
    'retry waiting',
  );
  expect(p.received.whereType<PlayMessage>(), hasLength(1));
  expect(p.received.whereType<InUseMessage>(), isEmpty);
}

Future<void> _done(
  WidgetTester tester,
  PlayerRig rig,
  ProviderContainer container,
) async {
  await tester.runAsync(
    container.read(detachedWindowsProvider.notifier).closeAll,
  );
  await disposeRig(tester, rig);
}

void main() {
  testWidgets('a failed window\'s Retry while the player waits is refused '
      'as in use in the main window; then only the player plays', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final launcher = FakeViewerLauncher();
    final (container, p, xtream) = await _failedWindow(tester, rig, launcher);

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
    await _done(tester, rig, container);
  });

  group('the player gives up a stream still opening', () {
    testWidgets('D: counted until the new window has it; the failed '
        'window\'s Retry is then refused, and only one window plays', (
      tester,
    ) async {
      final rig = PlayerRig();
      final launcher = FakeViewerLauncher();
      final (container, p, xtream) = await _failedWindow(tester, rig, launcher);
      final sport = await _slowSport(tester, rig, container, xtream);

      await press(tester, LogicalKeyboardKey.keyD);
      // The player stays until its stream has stopped; the stream counts.
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(sport.streamOpen, isTrue);
      expect(container.read(mainPlayerSourceProvider), isNull);
      final budget = container.read(connectionBudgetProvider);
      expect(budget.usedOn(xtream), 1);
      expect(budget.usedOn(xtream, holder: ConnectionHolder.stopping), 1);
      await _retryWaits(tester, rig, p);

      // The open ends, the stream stops, then the new window opens it.
      await tester.pump(const Duration(seconds: 10));
      await settle(tester);
      expect(sport.streamOpen, isFalse);
      await _until(
        tester,
        () =>
            launcher.processes.length == 2 &&
            launcher.last.received.whereType<PlayMessage>().isNotEmpty,
        'the new window playing',
      );
      await _until(
        tester,
        () => p.received.whereType<InUseMessage>().isNotEmpty,
        'the failed window answered',
      );
      expect(
        p.received.whereType<InUseMessage>().single.by,
        ConnectionInUseBy.otherWindow,
      );
      expect(p.received.whereType<PlayMessage>(), hasLength(1));
      expect(find.byType(PlayerScreen), findsNothing);
      expect(container.read(connectionDrainsProvider), isEmpty);
      expect(container.read(connectionBudgetProvider).usedOn(xtream), 1);
      expect(rig.log.dump(), isNot(contains('did not stop')));
      await _done(tester, rig, container);
    });

    testWidgets('S: counted until the first tile has it; the failed '
        'window\'s Retry is then refused as in use in the main window, and '
        'the tile plays', (tester) async {
      final rig = PlayerRig();
      final launcher = FakeViewerLauncher();
      final (container, p, xtream) = await _failedWindow(tester, rig, launcher);
      final sport = await _slowSport(tester, rig, container, xtream);

      await press(tester, LogicalKeyboardKey.keyS);
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(sport.streamOpen, isTrue);
      expect(container.read(mainPlayerSourceProvider), isNull);
      expect(
        container
            .read(connectionBudgetProvider)
            .usedOn(xtream, holder: ConnectionHolder.stopping),
        1,
      );
      await _retryWaits(tester, rig, p);

      await tester.pump(const Duration(seconds: 10));
      await settle(tester);
      expect(sport.streamOpen, isFalse);
      await _until(
        tester,
        () => p.received.whereType<InUseMessage>().isNotEmpty,
        'the failed window answered',
      );
      expect(
        p.received.whereType<InUseMessage>().single.by,
        ConnectionInUseBy.mainWindow,
      );
      await _until(
        tester,
        () => rig.openedUrls.where((u) => u.contains('/502.')).length == 2,
        'the first tile opened',
      );
      expect(find.byType(MultiViewScreen), findsOneWidget);
      expect(find.byType(PlayerScreen), findsNothing);
      expect(p.received.whereType<PlayMessage>(), hasLength(1));
      expect(container.read(connectionDrainsProvider), isEmpty);
      expect(
        container
            .read(connectionBudgetProvider)
            .usedOn(xtream, holder: ConnectionHolder.tile),
        1,
      );
      await _done(tester, rig, container);
    });

    testWidgets('Back: counted until the stream goes with the route (not '
        'until the open would have ended); then the window\'s Retry plays', (
      tester,
    ) async {
      final rig = PlayerRig();
      final launcher = FakeViewerLauncher();
      final (container, p, xtream) = await _failedWindow(tester, rig, launcher);
      final sport = await _slowSport(tester, rig, container, xtream);

      // Back (the first Escape may only leave the window's fullscreen); no
      // time passes, so the route is still fading out.
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        if (container.read(connectionDrainsProvider).isNotEmpty) break;
      }
      expect(container.read(mainPlayerSourceProvider), isNull);
      expect(
        container
            .read(connectionBudgetProvider)
            .usedOn(xtream, holder: ConnectionHolder.stopping),
        1,
      );
      expect(sport.streamOpen, isTrue);
      await _retryWaits(tester, rig, p);

      // The route is gone, and its controller and engine with it.
      await settle(tester);
      expect(find.byType(PlayerScreen), findsNothing);
      await _until(
        tester,
        () => p.received.whereType<PlayMessage>().length == 2,
        'the window playing again',
      );
      expect(sport.disposed, isTrue);
      expect(sport.streamOpen, isFalse);
      expect(container.read(connectionDrainsProvider), isEmpty);
      expect(p.received.whereType<InUseMessage>(), isEmpty);
      // The disposed engine's open runs out.
      await tester.pump(const Duration(seconds: 10));
      await _done(tester, rig, container);
    });
  });
}
