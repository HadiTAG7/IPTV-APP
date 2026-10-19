// Closing a window that is still starting ("Close the window and play
// here") ends its pending detach with 'closed', and the player that asked
// for it reports no failure: the user closed it on purpose.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';
import 'package:iptv_player/player/ui/player_screen.dart';
import 'package:iptv_player/sources/models.dart';

import '../support/fake_viewer.dart';
import 'support/fake_detached_windows.dart';
import 'support/player_harness.dart';

/// Like [DetachedWindows] for a viewer still starting: [detach] waits for
/// the viewer's ready; [close] before that fails it with 'closed', as the
/// real one does (the tests below).
class _StartingWindows extends RecordingDetachedWindows {
  _StartingWindows(super.rig);

  final _ready = Completer<int>();

  @override
  Future<int> detach(DetachRequest request) {
    detached.add(request);
    state = [
      ...state,
      DetachedViewer(
        id: 1,
        sourceId: request.sourceId,
        channelKey: request.channelKey,
        title: request.title,
        maxConnections: request.maxConnections,
      ),
    ];
    return _ready.future;
  }

  @override
  Future<void> close(int viewerId, {Duration? wait}) async {
    closed.add(viewerId);
    state = [
      for (final w in state)
        if (w.id != viewerId) w,
    ];
    if (!_ready.isCompleted) {
      _ready.completeError(const ViewerLaunchException('closed'));
    }
  }
}

ProviderContainer _container(FakeViewerLauncher launcher) {
  final container = ProviderContainer(
    overrides: [
      viewerLauncherProvider.overrideWithValue(launcher),
      viewerTimeoutsProvider.overrideWithValue(
        const ViewerTimeouts(close: Duration(milliseconds: 300)),
      ),
      ringLogProvider.overrideWithValue(RingLog()),
      initialSettingsProvider.overrideWithValue(const AppSettings()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

const _request = DetachRequest(
  sourceId: 7,
  channelKey: '501',
  title: 'Panel News',
  stream: StreamRequest(
    url: 'http://127.0.0.1:9/live/viewer7/Secret-Pass-9/501.ts',
    kind: PlayableKind.live,
  ),
  maxConnections: 1,
);

/// Runs [detach] and catches what it ends with.
Future<Object?> Function() _outcome(Future<int> detach) {
  Object? outcome;
  var done = false;
  unawaited(
    detach.then<void>(
      (id) {
        outcome = id;
        done = true;
      },
      onError: (Object e) {
        outcome = e;
        done = true;
      },
    ),
  );
  return () async {
    await until(() => done);
    return outcome;
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final closedOnPurpose = isA<ViewerLaunchException>()
      .having((e) => e.reason, 'reason', 'closed')
      .having((e) => e.closedOnPurpose, 'closedOnPurpose', isTrue);

  test('a window closed before it connected ends its detach with '
      '"closed"', () async {
    final launcher = FakeViewerLauncher()..autoConnect = false;
    final container = _container(launcher);
    final windows = container.read(detachedWindowsProvider.notifier);
    final outcome = _outcome(windows.detach(_request));
    await until(() => launcher.processes.isNotEmpty);
    await windows.close(container.read(detachedWindowsProvider).single.id);
    expect(await outcome(), closedOnPurpose);
  });

  test('a window closed after its hello, before ready, ends its detach '
      'with "closed" too', () async {
    final launcher = FakeViewerLauncher()..autoConnect = false;
    final container = _container(launcher);
    final windows = container.read(detachedWindowsProvider.notifier);
    final outcome = _outcome(windows.detach(_request));
    await until(() => launcher.processes.isNotEmpty);
    final p = launcher.last;
    await p.connect(ready: false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // It stops and closes its connection when told (before it exits).
    await windows.close(1);
    expect(p.received.single, isA<CloseMessage>());
    expect(await outcome(), closedOnPurpose);
  });

  testWidgets('closing a starting window on purpose shows no failure', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedXtream(rig);
    final windows = _StartingWindows(rig);
    await pumpPlayerApp(
      tester,
      rig,
      tv: false,
      platform: TargetPlatform.windows,
      overrides: [detachedWindowsProvider.overrideWith(() => windows)],
    );
    await openPlayerFor(tester, xtreamRequest(id, '501'));
    await press(tester, LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsNothing);
    expect(windows.state.single.status, ViewerStatus.starting);

    // Before the window shows, the user picks another channel and closes
    // the window to play it here.
    await openPlayerFor(tester, xtreamRequest(id, '502'));
    await tester.tap(find.text('Close the window and play here'));
    await settle(tester);
    expect(windows.closed, [1]);
    expect(find.byType(PlayerScreen), findsOneWidget);

    expect(find.text("Couldn't open the separate window."), findsNothing);
    expect(rig.log.dump(), contains('closed while it started'));
    expect(rig.log.dump(), isNot(contains('separate window failed')));
    await disposeRig(tester, rig);
  });
}
