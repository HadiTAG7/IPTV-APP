// The app (PlayMessage.of) and the viewer (decodeViewerMessage) apply the
// same rules to a play line, so a play is never dropped by the viewer
// after the app sent it (the window would spin forever while detach
// reported success): what a window cannot play fails before any window
// starts. Synthetic data only.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';
import 'package:iptv_player/sources/models.dart';

import '../../support/fake_viewer.dart';

StreamRequest _stream(String url) =>
    StreamRequest(url: url, kind: PlayableKind.live);

DetachRequest _request(String url, {int? maxConnections}) => DetachRequest(
  sourceId: 7,
  channelKey: '501',
  title: 'Panel News',
  stream: _stream(url),
  maxConnections: maxConnections,
);

({ProviderContainer container, FakeViewerLauncher launcher, RingLog log})
_rig() {
  final launcher = FakeViewerLauncher();
  final log = RingLog();
  final container = ProviderContainer(
    overrides: [
      viewerLauncherProvider.overrideWithValue(launcher),
      viewerTimeoutsProvider.overrideWithValue(
        const ViewerTimeouts(
          start: Duration(seconds: 5),
          handshake: Duration(seconds: 5),
          close: Duration(milliseconds: 500),
        ),
      ),
      ringLogProvider.overrideWithValue(log),
      initialSettingsProvider.overrideWithValue(const AppSettings()),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, launcher: launcher, log: log);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what the app builds, the viewer accepts; anything else fails at '
      'the app', () {
    final cases = <String, (StreamRequest, int?)>{
      'M3U multicast UDP (empty host)': (_stream('udp://@:1234'), null),
      'M3U RTMP': (_stream('rtmp://127.0.0.1/live/1'), null),
      'M3U local file': (_stream('file:///srv/tv/loop.ts'), null),
      'long tokenised URL': (
        _stream('http://127.0.0.1:9/live/1.m3u8?token=${'a' * 9000}'),
        null,
      ),
      'panel max_connections -1': (
        _stream('http://127.0.0.1:9/live/u/p/1.ts'),
        -1,
      ),
      'panel max_connections 0': (
        _stream('http://127.0.0.1:9/live/u/p/1.ts'),
        0,
      ),
      'a plain channel': (_stream('https://127.0.0.1:9/live/u/p/1.m3u8'), 1),
    };
    cases.forEach((name, input) {
      test(name, () {
        final (stream, maxConnections) = input;
        final PlayMessage play;
        try {
          play = PlayMessage.of(
            stream,
            title: 'News',
            maxConnections: maxConnections,
          );
        } on FormatException {
          // Refused before anything is sent.
          expect(isViewerStreamUrl(stream.url), isFalse);
          return;
        }
        final back = decodeViewerMessage(encodeViewerMessage(play).trim());
        expect(back, isA<PlayMessage>());
        // An unknown limit (0 or less) is left out.
        expect(
          (back! as PlayMessage).maxConnections,
          maxConnections != null && maxConnections > 0 ? maxConnections : null,
        );
      });
    });
  });

  test(
    'a negative connection limit still opens the window and plays',
    () async {
      final rig = _rig();
      final windows = rig.container.read(detachedWindowsProvider.notifier);
      final id = await windows.detach(
        _request('http://127.0.0.1:9/live/u/p/501.ts', maxConnections: -1),
      );
      final viewer = rig.launcher.last;
      await until(() => viewer.received.isNotEmpty);
      final play = viewer.received.single as PlayMessage;
      expect(play.maxConnections, isNull);
      await windows.close(id);
    },
  );

  test('a stream a window cannot play fails detach before any window '
      'starts, and replace refuses it', () async {
    final rig = _rig();
    final windows = rig.container.read(detachedWindowsProvider.notifier);
    const rtmp = 'rtmp://127.0.0.1/live/viewer7/Secret-Pass-9/1';
    expect(windows.canPlay(_request(rtmp)), isFalse);
    await expectLater(
      windows.detach(_request(rtmp)),
      throwsA(
        isA<ViewerLaunchException>().having(
          (e) => e.reason,
          'reason',
          'stream',
        ),
      ),
    );
    expect(rig.launcher.processes, isEmpty);
    expect(rig.container.read(detachedWindowsProvider), isEmpty);
    expect(rig.log.dump(), contains('stream refused'));
    // The log names no URL or credential.
    expect(rig.log.dump(), isNot(contains('Secret-Pass-9')));

    const http = 'http://127.0.0.1:9/live/viewer7/Secret-Pass-9/1.ts';
    expect(windows.canPlay(_request(http)), isTrue);
    final id = await windows.detach(_request(http));
    expect(windows.replace(id, _request(rtmp)), isFalse);
    expect(
      rig.container.read(detachedWindowsProvider).single.channelKey,
      '501',
    );
    await windows.close(id);
  });
}
