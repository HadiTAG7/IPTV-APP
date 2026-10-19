// Every caller of close() for a window waits for that window to exit, so
// "Close the window and play here" never plays while it still streams.
// Real loopback server, fake viewer processes. Synthetic data only.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';
import 'package:iptv_player/sources/models.dart';

import '../../support/fake_viewer.dart';

DetachRequest _request() => DetachRequest(
  sourceId: 7,
  channelKey: '501',
  title: 'Panel News',
  stream: StreamRequest(
    url: 'http://127.0.0.1:9/live/viewer7/Secret-Pass-9/501.ts',
    kind: PlayableKind.live,
  ),
  maxConnections: 1,
  secrets: const {'viewer7', 'Secret-Pass-9'},
);

ProviderContainer _container(FakeViewerLauncher launcher) {
  final container = ProviderContainer(
    overrides: [
      viewerLauncherProvider.overrideWithValue(launcher),
      viewerTimeoutsProvider.overrideWithValue(
        const ViewerTimeouts(
          start: Duration(seconds: 5),
          handshake: Duration(seconds: 2),
          close: Duration(milliseconds: 800),
        ),
      ),
      ringLogProvider.overrideWithValue(RingLog()),
      initialSettingsProvider.overrideWithValue(const AppSettings()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// A viewer that takes 300 ms to stop its stream after close, then exits.
void _slowToExit(FakeViewerProcess p) {
  p.obeysClose = false;
  unawaited(() async {
    await until(() => p.received.whereType<CloseMessage>().isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    p.exit(0);
  }());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a second close() waits for the window to exit like the first',
    () async {
      final launcher = FakeViewerLauncher();
      final container = _container(launcher);
      final windows = container.read(detachedWindowsProvider.notifier);
      final id = await windows.detach(_request());
      final p = launcher.last;
      _slowToExit(p);

      final first = windows.close(id);
      var secondDone = false;
      final second = windows.close(id).then((_) => secondDone = true);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // The viewer still runs (and holds the connection), so the second
      // caller still waits.
      expect(p.exited, isFalse);
      expect(container.read(detachedWindowsProvider), hasLength(1));
      expect(secondDone, isFalse);
      await first;
      await second;
      expect(p.exited, isTrue);
      expect(p.killed, isFalse);
      expect(p.received.whereType<CloseMessage>(), hasLength(1));
      expect(container.read(detachedWindowsProvider), isEmpty);
      // Closed: nothing more to wait for.
      await windows.close(id);
    },
  );

  test('closeAll during a close waits for that window too', () async {
    final launcher = FakeViewerLauncher();
    final container = _container(launcher);
    final windows = container.read(detachedWindowsProvider.notifier);
    final id = await windows.detach(_request());
    final p = launcher.last;
    _slowToExit(p);

    unawaited(windows.close(id));
    await windows.closeAll();
    expect(p.exited, isTrue);
    expect(container.read(detachedWindowsProvider), isEmpty);
  });
}
