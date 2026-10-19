// Junk connections from another local process do not make the app give up
// its loopback port (which an impostor could then bind and feed the viewer
// any URL), and the viewer plays only http(s) stream URLs. Synthetic data
// only.
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';
import 'package:iptv_player/sources/models.dart';

import '../../support/fake_viewer.dart';

const _url = 'http://127.0.0.1:9/live/viewer7/Secret-Pass-9/501.ts';

DetachRequest _request() => DetachRequest(
  sourceId: 7,
  channelKey: '501',
  title: 'Panel News',
  stream: StreamRequest(url: _url, kind: PlayableKind.live),
  maxConnections: 1,
  secrets: const {'viewer7', 'Secret-Pass-9'},
);

({ProviderContainer container, FakeViewerLauncher launcher}) _rig() {
  final launcher = FakeViewerLauncher()..autoConnect = false;
  final container = ProviderContainer(
    overrides: [
      viewerLauncherProvider.overrideWithValue(launcher),
      viewerTimeoutsProvider.overrideWithValue(
        const ViewerTimeouts(
          start: Duration(seconds: 10),
          handshake: Duration(seconds: 10),
          close: Duration(milliseconds: 500),
        ),
      ),
      ringLogProvider.overrideWithValue(RingLog()),
      initialSettingsProvider.overrideWithValue(const AppSettings()),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, launcher: launcher);
}

/// Opens [count] idle connections to [port] (any local process can see
/// the port: netstat, /proc/net/tcp).
Future<List<Socket>> _junk(int port, int count) async => [
  for (var i = 0; i < count; i++)
    await Socket.connect(InternetAddress.loopbackIPv4, port),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('idle junk connections never make the app give up its port, so no '
      'impostor can take it', () async {
    final rig = _rig();
    final detaching = rig.container
        .read(detachedWindowsProvider.notifier)
        .detach(_request());
    unawaited(detaching.then((_) {}, onError: (Object _) {}));
    await until(() => rig.launcher.processes.isNotEmpty);
    final viewer = rig.launcher.last;
    final port = viewer.args.port;

    final junk = await _junk(port, 12);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // The impostor tries to take the port: the app still listens on it.
    await expectLater(
      ServerSocket.bind(InternetAddress.loopbackIPv4, port),
      throwsA(isA<SocketException>()),
    );
    for (final s in junk) {
      s.destroy();
    }

    // The real viewer starts late and gets in: the app's stream only.
    await viewer.connect();
    expect(await detaching, 1);
    await until(() => viewer.received.isNotEmpty);
    expect(viewer.received.single, isA<PlayMessage>());
    expect((viewer.received.single as PlayMessage).url, _url);
  });

  test('more junk than the app waits on at once is refused; the viewer '
      'still gets in once it is gone', () async {
    final rig = _rig();
    final detaching = rig.container
        .read(detachedWindowsProvider.notifier)
        .detach(_request());
    unawaited(detaching.then((_) {}, onError: (Object _) {}));
    await until(() => rig.launcher.processes.isNotEmpty);
    final viewer = rig.launcher.last;
    final junk = await _junk(viewer.args.port, 9);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    for (final s in junk) {
      s.destroy();
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    // The real viewer, slower to start, connects now.
    await viewer.connect();
    expect(await detaching, 1);
  });

  test('the viewer refuses play URLs that are not http(s) streams', () {
    for (final url in [
      'file://localhost/etc/passwd',
      'file:///etc/passwd',
      'fd://3',
      'edl://%3%abc',
      'smb://host/share/a.ts',
      'rtmp://127.0.0.1/live/1',
      'udp://@:1234',
      'http://',
    ]) {
      expect(isViewerStreamUrl(url), isFalse, reason: url);
      final line = encodeViewerMessage(PlayMessage(url: url)).trim();
      expect(decodeViewerMessage(line), isNull, reason: url);
    }
    for (final url in [_url, 'HTTPS://cdn.example/live/1.m3u8?t=abc']) {
      expect(isViewerStreamUrl(url), isTrue, reason: url);
      final line = encodeViewerMessage(PlayMessage(url: url)).trim();
      expect(decodeViewerMessage(line), isA<PlayMessage>(), reason: url);
    }
  });
}
