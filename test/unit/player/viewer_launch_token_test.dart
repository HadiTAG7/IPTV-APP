// The viewer's one-time token travels in its environment, which only its
// own user can read, never on its command line, which every local user can
// (/proc/<pid>/cmdline). Whoever reads the command line and races the
// viewer to the loopback server gets nothing. Synthetic data only
// (127.0.0.1 URLs, made-up credentials). Linux only (procfs).
import 'dart:io';

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
    headers: const {'User-Agent': 'Panel/1.0'},
  ),
  maxConnections: 1,
  secrets: const {'viewer7', 'Secret-Pass-9'},
);

/// The pid and command line of the viewer started from [marker], as any
/// local user can see them in /proc.
(int, List<String>)? _findViewer(String marker) {
  for (final entry in Directory('/proc').listSync()) {
    final pid = int.tryParse(entry.uri.pathSegments.lastWhere((s) => s != ''));
    if (pid == null) continue;
    try {
      final raw = File('/proc/$pid/cmdline').readAsBytesSync();
      final args = String.fromCharCodes(raw).split('\x00');
      if (args.contains(marker) && ViewerLaunchArgs.isViewer(args)) {
        return (pid, args);
      }
    } on FileSystemException {
      continue;
    }
  }
  return null;
}

Map<String, String> _environmentOf(int pid) => {
  for (final entry in String.fromCharCodes(
    File('/proc/$pid/environ').readAsBytesSync(),
  ).split('\x00'))
    if (entry.contains('='))
      entry.substring(0, entry.indexOf('=')): entry.substring(
        entry.indexOf('=') + 1,
      ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the token is in the environment only; the command line lets nobody in',
    () async {
      // A "viewer" that is slow to start, like the real one (Flutter engine
      // plus libmpv before it connects).
      final dir = await Directory.systemTemp.createTemp('viewer_launch');
      addTearDown(() => dir.delete(recursive: true));
      final exe = File('${dir.path}/slow_viewer.sh')
        ..writeAsStringSync('#!/bin/sh\nwhile :; do sleep 0.1; done\n');
      await Process.run('chmod', ['+x', exe.path]);

      final container = ProviderContainer(
        overrides: [
          viewerLauncherProvider.overrideWithValue(
            ProcessViewerLauncher(executable: exe.path),
          ),
          viewerTimeoutsProvider.overrideWithValue(
            const ViewerTimeouts(
              start: Duration(seconds: 10),
              handshake: Duration(seconds: 5),
              close: Duration(milliseconds: 500),
            ),
          ),
          ringLogProvider.overrideWithValue(RingLog()),
          initialSettingsProvider.overrideWithValue(const AppSettings()),
        ],
      );
      addTearDown(container.dispose);
      final detaching = container
          .read(detachedWindowsProvider.notifier)
          .detach(_request());

      (int, List<String>)? found;
      final end = DateTime.now().add(const Duration(seconds: 5));
      while (found == null && DateTime.now().isBefore(end)) {
        found = _findViewer(exe.path);
        if (found == null) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }
      expect(found, isNotNull, reason: 'viewer process not found in /proc');
      final (pid, args) = found!;

      // Its environment: readable by its own user only, with the token
      // added to the app's own.
      final mode = FileStat.statSync('/proc/$pid/environ').mode;
      expect(mode & 0x3F, 0, reason: 'group and others cannot read it');
      final env = _environmentOf(pid);
      final token = env[kViewerTokenEnvironment];
      expect(token, isNotNull);
      expect(env['PATH'], Platform.environment['PATH']);

      // Its command line: no token.
      expect(args.join(' '), isNot(contains(token!)));
      expect(args.where((a) => a.startsWith('--token')), isEmpty);
      expect(() => ViewerLaunchArgs.parse(args), throwsFormatException);

      // Another process with the command line only races the viewer to
      // the server: refused, it gets nothing.
      final port = ViewerLaunchArgs.parse(
        args,
        environment: {kViewerTokenEnvironment: 'A' * 43},
      ).port;
      final intruder = FakeViewerProcess(
        ViewerLaunchArgs(port: port, token: 'A' * 43),
      );
      await intruder.connect();
      await until(() => intruder.channel!.isClosed);
      expect(intruder.received, isEmpty);

      // The viewer, with the token from its environment, gets the stream.
      final viewer = FakeViewerProcess(
        ViewerLaunchArgs.parse(args, environment: env),
      );
      await viewer.connect();
      expect(await detaching, 1);
      await until(() => viewer.received.isNotEmpty);
      expect(viewer.received.single, isA<PlayMessage>());
    },
    skip: !Platform.isLinux,
  );
}
