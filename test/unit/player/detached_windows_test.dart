// DetachedWindows over a real loopback server with fake viewer processes.
// Synthetic data only (127.0.0.1 URLs, made-up credentials).
import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/player/connection_budget.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';
import 'package:iptv_player/player/ui/play_request.dart';
import 'package:iptv_player/sources/models.dart';

import '../../support/fake_viewer.dart';

/// Short, with room for a loaded test machine (real sockets and time).
const _fast = ViewerTimeouts(
  start: Duration(seconds: 2),
  handshake: Duration(seconds: 2),
  close: Duration(milliseconds: 800),
);

DetachRequest _request({String key = '501', String title = 'Panel News'}) =>
    DetachRequest(
      sourceId: 7,
      channelKey: key,
      title: title,
      logo: 'http://127.0.0.1:9/logo/$key.png',
      stream: StreamRequest(
        url: 'http://127.0.0.1:9/live/viewer7/Secret-Pass-9/$key.ts',
        kind: PlayableKind.live,
        headers: const {'User-Agent': 'Panel/1.0'},
      ),
      maxConnections: 1,
      secrets: const {'viewer7', 'Secret-Pass-9'},
      locale: 'ar',
    );

class _Rig {
  _Rig({AppDatabase? db, ViewerTimeouts timeouts = _fast}) {
    container = ProviderContainer(
      overrides: [
        viewerLauncherProvider.overrideWithValue(launcher),
        viewerTimeoutsProvider.overrideWithValue(timeouts),
        ringLogProvider.overrideWithValue(log),
        initialSettingsProvider.overrideWithValue(
          const AppSettings(hwdec: false),
        ),
        if (db != null) databaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);
  }

  final launcher = FakeViewerLauncher();
  final log = RingLog();
  late final ProviderContainer container;

  DetachedWindows get windows =>
      container.read(detachedWindowsProvider.notifier);

  List<DetachedViewer> get state => container.read(detachedWindowsProvider);

  String get logText => log.dump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'detach starts a viewer, checks its token and sends the stream',
    () async {
      final rig = _Rig();
      final id = await rig.windows.detach(_request());
      expect(id, 1);
      final p = rig.launcher.last;
      // Only the port and the language on the command line; the token in
      // the environment.
      expect(rig.launcher.lines.single, [
        '--viewer',
        '--port=${p.args.port}',
        '--locale=ar',
      ]);
      expect(rig.launcher.lines.single.join(' '), isNot(contains('127.0.0.1')));
      expect(rig.launcher.environments.single, {
        kViewerTokenEnvironment: p.args.token,
      });
      expect(p.args.token.length, greaterThanOrEqualTo(22));

      await until(() => p.received.isNotEmpty);
      final play = p.received.single as PlayMessage;
      expect(
        play.stream.url,
        'http://127.0.0.1:9/live/viewer7/Secret-Pass-9/501.ts',
      );
      expect(play.stream.headers, {'User-Agent': 'Panel/1.0'});
      expect(play.title, 'Panel News');
      expect(play.channelKey, '501');
      expect(play.maxConnections, 1);
      // Engine options from Settings.
      expect(play.hardwareDecoding, isFalse);
      expect(play.secrets, unorderedEquals(['viewer7', 'Secret-Pass-9']));

      expect(rig.state.single.status, ViewerStatus.opening);
      expect(rig.state.single.sourceId, 7);
      p.send(const PlayingMessage());
      await until(() => rig.state.single.status == ViewerStatus.playing);

      // One viewer per server: nobody else can connect now.
      await expectLater(
        Socket.connect(InternetAddress.loopbackIPv4, p.args.port),
        throwsA(isA<SocketException>()),
      );
      // Logs never carry the URL, the credentials or the token.
      expect(rig.logText, isNot(contains('Secret-Pass-9')));
      expect(rig.logText, isNot(contains(p.args.token)));
    },
  );

  test('a wrong token or junk is refused; the viewer still gets in', () async {
    final rig = _Rig(
      timeouts: const ViewerTimeouts(
        start: Duration(seconds: 10),
        handshake: Duration(seconds: 10),
      ),
    )..launcher.autoConnect = false;
    final detaching = rig.windows.detach(_request());
    await until(() => rig.launcher.processes.isNotEmpty);
    final p = rig.launcher.last;

    final intruder = FakeViewerProcess(
      ViewerLaunchArgs(port: p.args.port, token: 'A' * 43),
    );
    await intruder.connect();
    await until(() => intruder.channel!.isClosed);
    expect(intruder.received, isEmpty);

    final junk = await Socket.connect(
      InternetAddress.loopbackIPv4,
      p.args.port,
    );
    junk.write('GET / HTTP/1.1\r\n\r\n');
    await junk.flush();
    final closed = Completer<void>();
    junk.listen((_) {}, onDone: closed.complete, onError: (Object _) {});
    await closed.future.timeout(const Duration(seconds: 5));
    junk.destroy();

    expect(rig.logText, contains('connection refused'));
    expect(rig.state.single.status, ViewerStatus.starting);
    await p.connect();
    expect(await detaching, 1);
    await until(() => p.received.isNotEmpty);
    expect(p.received.single, isA<PlayMessage>());
  });

  test('replace plays another channel in the same window', () async {
    final rig = _Rig();
    final id = await rig.windows.detach(_request());
    final p = rig.launcher.last;
    p.send(const PlayingMessage());
    await until(() => rig.state.single.status == ViewerStatus.playing);

    expect(
      rig.windows.replace(id, _request(key: '502', title: 'Panel Sport')),
      isTrue,
    );
    await until(() => p.received.length == 2);
    final play = p.received.last as PlayMessage;
    expect(play.stream.url, endsWith('/502.ts'));
    expect(play.title, 'Panel Sport');
    final window = rig.state.single;
    expect(window.channelKey, '502');
    expect(window.title, 'Panel Sport');
    expect(window.status, ViewerStatus.opening);
    expect(rig.windows.replace(99, _request()), isFalse);
  });

  test('close asks the viewer to stop and waits for it to exit', () async {
    final rig = _Rig();
    final id = await rig.windows.detach(_request());
    final p = rig.launcher.last;
    await rig.windows.close(id);
    expect(p.received.whereType<CloseMessage>(), hasLength(1));
    expect(p.exited, isTrue);
    expect(p.killed, isFalse);
    expect(rig.state, isEmpty);
    expect(rig.windows.replace(id, _request()), isFalse);
  });

  test('a viewer that does not exit is killed', () async {
    final rig = _Rig()..launcher.autoConnect = false;
    final detaching = rig.windows.detach(_request());
    await until(() => rig.launcher.processes.isNotEmpty);
    final p = rig.launcher.last..obeysClose = false;
    await p.connect();
    final id = await detaching;
    await rig.windows.close(id);
    expect(p.killed, isTrue);
    expect(rig.state, isEmpty);
    expect(rig.logText, contains('did not exit'));
  });

  test('a viewer that exits on its own goes away', () async {
    final rig = _Rig();
    await rig.windows.detach(_request());
    expect(rig.container.read(connectionBudgetProvider).fits(7), isFalse);
    rig.launcher.last.exit(3);
    await until(() => rig.state.isEmpty);
    expect(rig.logText, contains('exited (code 3)'));
    // Its connection is free again.
    expect(rig.container.read(connectionBudgetProvider).fits(7), isTrue);
  });

  test('a closed connection removes the window and kills a lingering '
      'process', () async {
    final rig = _Rig();
    await rig.windows.detach(_request());
    final p = rig.launcher.last;
    p.channel!.close();
    await until(() => rig.state.isEmpty);
    expect(p.killed, isFalse);
    await until(() => p.killed);
  });

  test('the user closing the window', () async {
    final rig = _Rig();
    await rig.windows.detach(_request());
    final p = rig.launcher.last;
    p.send(const ClosedMessage());
    await until(() => rig.state.isEmpty);
    expect(rig.logText, contains('closed by the user'));
    p.exit(0);
  });

  test('closeAll closes every window', () async {
    final rig = _Rig();
    await rig.windows.detach(_request());
    await rig.windows.detach(_request(key: '502'));
    expect(rig.state.map((w) => w.id), [1, 2]);
    await rig.windows.closeAll();
    expect(rig.state, isEmpty);
    for (final p in rig.launcher.processes) {
      expect(p.received.whereType<CloseMessage>(), hasLength(1));
      expect(p.exited, isTrue);
    }
  });

  test('the app exiting closes every window first', () async {
    final rig = _Rig();
    await rig.windows.detach(_request());
    final p = rig.launcher.last;
    final response = await TestWidgetsFlutterBinding.instance
        .handleRequestAppExit();
    expect(response, AppExitResponse.exit);
    expect(p.received.whereType<CloseMessage>(), hasLength(1));
    expect(p.exited, isTrue);
    expect(rig.state, isEmpty);
    // Without windows nothing waits on the way out.
    expect(
      await TestWidgetsFlutterBinding.instance.handleRequestAppExit(),
      AppExitResponse.exit,
    );
  });

  test('a viewer that cannot start: an error, nothing left behind', () async {
    final rig = _Rig()..launcher.fail = true;
    await expectLater(
      rig.windows.detach(_request()),
      throwsA(isA<ViewerLaunchException>()),
    );
    expect(rig.state, isEmpty);
    final token = rig.launcher.environments.single[kViewerTokenEnvironment]!;
    expect(rig.logText, contains('could not start'));
    // ProcessException repeats the arguments: never logged.
    expect(rig.logText, isNot(contains(token)));
  });

  test('a viewer that never answers is given up and killed', () async {
    final rig = _Rig()..launcher.autoConnect = false;
    await expectLater(
      rig.windows.detach(_request()),
      throwsA(
        isA<ViewerLaunchException>().having(
          (e) => e.reason,
          'reason',
          'timeout',
        ),
      ),
    );
    expect(rig.state, isEmpty);
    await until(() => rig.launcher.last.killed);
  });

  test('a viewer that exits before it is ready fails detach', () async {
    final rig = _Rig()..launcher.autoConnect = false;
    final detaching = rig.windows.detach(_request());
    await until(() => rig.launcher.processes.isNotEmpty);
    rig.launcher.last.exit(1);
    await expectLater(
      detaching,
      throwsA(
        isA<ViewerLaunchException>().having(
          (e) => e.reason,
          'reason',
          'exited',
        ),
      ),
    );
    expect(rig.state, isEmpty);
  });

  test(
    'a playback error is logged redacted and frees the connection',
    () async {
      final rig = _Rig();
      final id = await rig.windows.detach(_request());
      final p = rig.launcher.last;
      expect(rig.container.read(connectionBudgetProvider).fits(7), isFalse);
      p.send(
        const ViewerErrorMessage(
          'Failed to open http://127.0.0.1:9/live/viewer7/Secret-Pass-9/501.ts '
          '(HTTP error 403)',
        ),
      );
      await until(() => rig.state.single.status == ViewerStatus.failed);
      expect(rig.logText, contains('playback failed'));
      expect(rig.logText, contains('403'));
      expect(rig.logText, isNot(contains('Secret-Pass-9')));
      expect(rig.logText, isNot(contains('viewer7')));
      expect(rig.container.read(connectionBudgetProvider).fits(7), isTrue);
      // Opening again takes it again.
      p.send(const OpeningMessage());
      await until(() => rig.state.single.status == ViewerStatus.opening);
      expect(rig.container.read(connectionBudgetProvider).fits(7), isFalse);
      p.send(const PlayingMessage());
      await until(() => rig.state.single.status == ViewerStatus.playing);
      expect(rig.container.read(connectionBudgetProvider).fits(7), isFalse);
      await rig.windows.close(id);
      expect(rig.container.read(connectionBudgetProvider).fits(7), isTrue);
    },
  );

  test('malformed lines from the viewer are ignored', () async {
    final rig = _Rig();
    await rig.windows.detach(_request());
    final p = rig.launcher.last;
    p.socket!.write(
      '{"type": "play", "url": "http://127.0.0.1/x"}\nnot json\n',
    );
    p.send(const PlayingMessage());
    await until(() => rig.state.single.status == ViewerStatus.playing);
    expect(rig.logText, contains('ignored'));
    expect(rig.state, hasLength(1));
  });

  test('disposing the app kills the viewers', () async {
    final rig = _Rig();
    await rig.windows.detach(_request());
    final p = rig.launcher.last;
    rig.container.dispose();
    expect(p.killed, isTrue);
  });

  test(
    'the process launcher starts the executable and reports its exit',
    () async {
      const launcher = ProcessViewerLauncher(executable: '/bin/sh');
      final process = await launcher.launch([
        '-c',
        // More output than a pipe buffer holds (64 KiB on Linux).
        'head -c 300000 /dev/zero; head -c 300000 /dev/zero >&2; exit 3',
      ]);
      expect(process.pid, greaterThan(0));
      // The output is drained: a full pipe never blocks the viewer.
      expect(await process.exitCode, 3);
      // The environment is the app's plus what is given.
      final env = await launcher.launch(
        ['-c', r'test "$IPTV_TEST_TOKEN" = t0k3n && test -n "$PATH"'],
        environment: const {'IPTV_TEST_TOKEN': 't0k3n'},
      );
      expect(await env.exitCode, 0);
      final sleeper = await launcher.launch(['-c', 'sleep 30']);
      expect(sleeper.kill(), isTrue);
      expect(await sleeper.exitCode, isNot(0));
    },
    skip: !Platform.isLinux,
  );

  test('playInWindow resolves the channel like the player', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final sourceId = await db.sourcesDao.create(
      const SourceConfig(
        kind: SourceKind.m3uUrl,
        url: 'http://127.0.0.1:9/list.m3u',
        name: 'Home',
      ),
    );
    final gen = await db.catalogDao.beginGeneration(sourceId);
    await db.catalogDao.upsertChannels(sourceId, gen, const [
      ChannelData(
        key: 'ch2',
        name: 'Channel 2',
        url: 'http://127.0.0.1:9/live/ch2.ts',
        logo: 'http://127.0.0.1:9/ch2.png',
      ),
    ]);
    await db.catalogDao.commitGeneration(sourceId, gen);

    final rig = _Rig(db: db);
    final id = await rig.windows.detach(_request());
    final p = rig.launcher.last;
    await until(() => p.received.isNotEmpty);
    final ok = await rig.windows.playInWindow(
      id,
      PlayRequest(
        sourceId: sourceId,
        item: const PlayableRef(kind: PlayableKind.live, key: 'ch2'),
      ),
    );
    expect(ok, isTrue);
    await until(() => p.received.length == 2);
    final play = p.received.last as PlayMessage;
    expect(play.stream.url, 'http://127.0.0.1:9/live/ch2.ts');
    expect(play.title, 'Channel 2');
    expect(play.logo, 'http://127.0.0.1:9/ch2.png');
    expect(rig.state.single.sourceId, sourceId);
    expect(rig.state.single.channelKey, 'ch2');

    // An unknown source fails, logged without throwing.
    expect(
      await rig.windows.playInWindow(
        id,
        const PlayRequest(
          sourceId: 999,
          item: PlayableRef(kind: PlayableKind.live, key: 'ch2'),
        ),
      ),
      isFalse,
    );
    expect(rig.logText, contains('cannot resolve'));
    await rig.windows.close(id);
  });
}
