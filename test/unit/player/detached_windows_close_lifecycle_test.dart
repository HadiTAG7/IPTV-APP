// close() of a window that is still starting: it never gets the stream,
// and it ends at once instead of at the close timeout. Real loopback
// server, fake viewer processes. Synthetic data only (127.0.0.1 URLs,
// made-up credentials).
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';
import 'package:iptv_player/sources/models.dart';

import '../../support/fake_viewer.dart';

const _closeTimeout = Duration(milliseconds: 800);

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
  final c = ProviderContainer(
    overrides: [
      viewerLauncherProvider.overrideWithValue(launcher),
      viewerTimeoutsProvider.overrideWithValue(
        const ViewerTimeouts(
          start: Duration(seconds: 5),
          handshake: Duration(seconds: 2),
          close: _closeTimeout,
        ),
      ),
      ringLogProvider.overrideWithValue(RingLog()),
      initialSettingsProvider.overrideWithValue(const AppSettings()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// What [detach] ended with (its id or its error), once it has.
Future<Object?> _settled(Future<int> detach) =>
    detach.then<Object?>((id) => id, onError: (Object e) => e);

final _closed = isA<ViewerLaunchException>().having(
  (e) => e.reason,
  'reason',
  'closed',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a window closed before it connected is shut out and ended at '
      'once; it never gets the stream', () async {
    final launcher = FakeViewerLauncher()..autoConnect = false;
    final container = _container(launcher);
    final windows = container.read(detachedWindowsProvider.notifier);
    final detaching = _settled(windows.detach(_request()));
    await until(() => launcher.processes.isNotEmpty);
    // Let detach() take the process (it resumes after launch()).
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final p = launcher.last;

    // "Close the window and play here" while the window is still starting.
    final sw = Stopwatch()..start();
    final closing = windows.close(1);
    // The viewer finishes starting during the close: it cannot get in.
    try {
      await p.connect();
    } on SocketException {
      // Refused: the server is closed.
    }
    await closing;
    sw.stop();

    expect(p.killed, isTrue);
    expect(sw.elapsed, lessThan(_closeTimeout));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(p.received.whereType<PlayMessage>(), isEmpty);
    // detach() does not report a window that is being closed as opened.
    expect(await detaching, _closed);
    expect(container.read(detachedWindowsProvider), isEmpty);
  });

  test('a window closed after its hello never gets the stream, even when '
      'it says ready afterwards', () async {
    final launcher = FakeViewerLauncher()..autoConnect = false;
    final container = _container(launcher);
    final windows = container.read(detachedWindowsProvider.notifier);
    final detaching = _settled(windows.detach(_request()));
    await until(() => launcher.processes.isNotEmpty);
    // Connected, still starting, and slow to obey.
    final p = launcher.last..obeysClose = false;
    await p.connect(ready: false);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final closing = windows.close(1);
    await until(() => p.received.isNotEmpty);
    p.send(const ReadyMessage());
    await closing;

    expect(p.received.single, isA<CloseMessage>());
    expect(await detaching, _closed);
    expect(p.killed, isTrue);
  });
}
