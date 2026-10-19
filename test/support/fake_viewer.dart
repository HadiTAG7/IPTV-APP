// Fake viewer processes for the detached-window tests: a process that
// connects to the app's real loopback server like the viewer does.
// Synthetic data only.
import 'dart:async';
import 'dart:io';

import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';

/// A viewer process that never started an engine: it connects, says hello
/// and ready, records what the app sends and exits when told to close.
class FakeViewerProcess implements ViewerProcess {
  FakeViewerProcess(this.args);

  final ViewerLaunchArgs args;
  final _exit = Completer<int>();
  bool killed = false;

  /// Exits when the app sends close (as the real viewer does).
  bool obeysClose = true;

  Socket? socket;
  SocketViewerChannel? channel;
  final received = <ViewerMessage>[];

  @override
  int get pid => 4242;

  @override
  Future<int> get exitCode => _exit.future;

  bool get exited => _exit.isCompleted;

  @override
  bool kill() {
    killed = true;
    exit(-9);
    return true;
  }

  /// Ends the process (its connection closes with it).
  void exit(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
    channel?.close();
  }

  /// Connects to the app; [token] replaces the right one.
  Future<void> connect({String? token, bool ready = true}) async {
    final s = socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      args.port,
    );
    final c = channel = SocketViewerChannel(s, acceptFromViewer: false);
    c.messages.listen((m) {
      received.add(m);
      if (m is CloseMessage && obeysClose) exit(0);
    });
    c.send(HelloMessage(token: token ?? args.token));
    if (ready) c.send(const ReadyMessage());
    await c.flush();
  }

  void send(ViewerMessage message) => channel!.send(message);
}

/// Starts [FakeViewerProcess]es; [autoConnect] makes each connect at once.
class FakeViewerLauncher implements ViewerLauncher {
  final processes = <FakeViewerProcess>[];
  final lines = <List<String>>[];

  /// Thrown by the next launches (with the arguments, like Process.start).
  bool fail = false;
  bool autoConnect = true;

  FakeViewerProcess get last => processes.last;

  @override
  Future<ViewerProcess> launch(List<String> args) async {
    lines.add(args);
    if (fail) throw ProcessException('iptv_player.exe', args, 'denied', 5);
    final p = FakeViewerProcess(ViewerLaunchArgs.parse(args));
    processes.add(p);
    if (autoConnect) unawaited(p.connect());
    return p;
  }
}

/// Waits (real time) until [condition] holds.
Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('until');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
