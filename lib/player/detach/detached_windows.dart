// Live channels detached into windows of their own (Windows and Linux).
//
// Each detached window is a second process of the app's executable in
// viewer mode (one Flutter engine and one libmpv per process). The app
// binds a loopback server, starts the viewer with the port and a one-time
// token, and sends it the resolved stream once it said hello (with the
// token) and ready. The viewer exits when the connection closes, so a
// crashed or closed app never leaves one holding the account's connection.
import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../core/log/ring_log.dart';
import '../../core/net/redact.dart';
import '../../sources/models.dart';
import '../player_providers.dart';
import '../ui/play_request.dart';
import '../ui/player_format.dart';
import 'viewer_protocol.dart';

/// A started viewer process.
abstract interface class ViewerProcess {
  int get pid;

  /// Completes when the process has exited.
  Future<int> get exitCode;

  /// Ends the process at once.
  bool kill();
}

/// Starts viewer processes; tests use a fake.
abstract interface class ViewerLauncher {
  /// Starts the app's executable with [args] (a [ViewerLaunchArgs] line).
  Future<ViewerProcess> launch(List<String> args);
}

/// Starts [executable] (default: this app's own) as a separate process,
/// draining its output so it never blocks on a full pipe.
class ProcessViewerLauncher implements ViewerLauncher {
  const ProcessViewerLauncher({this.executable});

  final String? executable;

  @override
  Future<ViewerProcess> launch(List<String> args) async {
    final exe = executable ?? Platform.resolvedExecutable;
    final process = await Process.start(
      exe,
      args,
      workingDirectory: File(exe).parent.path,
      mode: ProcessStartMode.normal,
    );
    unawaited(process.stdout.drain<void>().catchError((Object _) {}));
    unawaited(process.stderr.drain<void>().catchError((Object _) {}));
    return _OsProcess(process);
  }
}

class _OsProcess implements ViewerProcess {
  _OsProcess(this._process);

  final Process _process;

  @override
  int get pid => _process.pid;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool kill() => _process.kill();
}

/// How viewers are started (overridden in tests).
final viewerLauncherProvider = Provider<ViewerLauncher>(
  (ref) => const ProcessViewerLauncher(),
  name: 'viewerLauncherProvider',
);

/// How long the app waits for viewers.
@immutable
class ViewerTimeouts {
  const ViewerTimeouts({
    this.start = const Duration(seconds: 20),
    this.handshake = const Duration(seconds: 5),
    this.close = const Duration(seconds: 3),
  });

  /// From starting the process to its ready message.
  final Duration start;

  /// From a connection to its hello (the token).
  final Duration handshake;

  /// For a viewer to stop and exit before it is killed.
  final Duration close;
}

final viewerTimeoutsProvider = Provider<ViewerTimeouts>(
  (ref) => const ViewerTimeouts(),
  name: 'viewerTimeoutsProvider',
);

/// Detaching or replacing failed; [reason] never holds a URL or the token.
class ViewerLaunchException implements Exception {
  const ViewerLaunchException(this.reason);

  final String reason;

  @override
  String toString() => 'ViewerLaunchException($reason)';
}

/// What a detached window should play: the channel and its resolved
/// stream.
@immutable
class DetachRequest {
  const DetachRequest({
    required this.sourceId,
    required this.channelKey,
    required this.title,
    required this.stream,
    this.logo,
    this.maxConnections,
    this.secrets = const {},
    this.locale = 'en',
  });

  final int sourceId;
  final String channelKey;
  final String title;
  final String? logo;
  final StreamRequest stream;

  /// The source's connection limit (the viewer's held-connection retries).
  final int? maxConnections;

  /// The source's credentials, masked in what the viewer shows.
  final Set<String> secrets;

  /// `ar` or `en`, for a new window.
  final String locale;

  @override
  String toString() => 'DetachRequest(source $sourceId)';
}

/// Resolves the live channel of [request] the way the player does
/// ([PlayerSource.resolveLive] on the channel's catalog row).
Future<DetachRequest> resolveDetachRequest(
  PlayRequest request, {
  required PlayerSourceLoader loadSource,
  required CatalogDao catalog,
  String locale = 'en',
}) async {
  final source = await loadSource(request.sourceId);
  try {
    final row = await catalog.channelByKey(request.sourceId, request.item.key);
    final item = row?.toPlayable() ?? request.item;
    return DetachRequest(
      sourceId: request.sourceId,
      channelKey: item.key,
      title: row?.name ?? request.displayTitle ?? '',
      logo: row?.logo,
      stream: source.resolveLive(item),
      maxConnections: source.maxConnections,
      secrets: source.secrets,
      locale: locale,
    );
  } finally {
    source.close();
  }
}

/// Where a detached window is.
enum ViewerStatus {
  /// The process is starting.
  starting,

  /// The stream is opening (or reconnecting).
  opening,
  playing,

  /// Playback failed; the window shows Retry and holds no connection.
  failed,
}

/// One detached window, as the UI and [connectionBudgetProvider] see it.
@immutable
class DetachedViewer {
  const DetachedViewer({
    required this.id,
    required this.sourceId,
    required this.channelKey,
    required this.title,
    this.logo,
    this.maxConnections,
    this.status = ViewerStatus.starting,
  });

  final int id;
  final int sourceId;
  final String channelKey;
  final String title;
  final String? logo;
  final int? maxConnections;
  final ViewerStatus status;

  /// Whether it holds (or is about to open) a stream connection.
  bool get holdsConnection => status != ViewerStatus.failed;

  DetachedViewer copyWith({
    int? sourceId,
    String? channelKey,
    String? title,
    String? logo,
    int? maxConnections,
    ViewerStatus? status,
  }) => DetachedViewer(
    id: id,
    sourceId: sourceId ?? this.sourceId,
    channelKey: channelKey ?? this.channelKey,
    title: title ?? this.title,
    logo: logo ?? this.logo,
    maxConnections: maxConnections ?? this.maxConnections,
    status: status ?? this.status,
  );

  @override
  bool operator ==(Object other) =>
      other is DetachedViewer &&
      other.id == id &&
      other.sourceId == sourceId &&
      other.channelKey == channelKey &&
      other.title == title &&
      other.logo == logo &&
      other.maxConnections == maxConnections &&
      other.status == status;

  @override
  int get hashCode => Object.hash(
    id,
    sourceId,
    channelKey,
    title,
    logo,
    maxConnections,
    status,
  );

  @override
  String toString() => 'DetachedViewer($id, source $sourceId, ${status.name})';
}

/// The detached windows, oldest first.
final detachedWindowsProvider =
    NotifierProvider<DetachedWindows, List<DetachedViewer>>(
      DetachedWindows.new,
      name: 'detachedWindowsProvider',
    );

/// The app's side of one viewer.
class _Viewer {
  _Viewer({
    required this.id,
    required this.server,
    required this.token,
    required this.request,
    required this.log,
    required this.timeouts,
  }) {
    // The caller of detach() hears of failures; nobody else has to.
    ready.future.ignore();
  }

  final int id;
  final ServerSocket server;
  final String token;
  final RingLog log;
  final ViewerTimeouts timeouts;
  DetachRequest request;

  StreamSubscription<Socket>? accepts;

  /// Connections that have not said hello yet.
  final pending = <ViewerChannel>{};
  ViewerProcess? process;
  ViewerChannel? channel;

  /// Sent once the viewer is ready.
  PlayMessage? pendingPlay;
  bool readySeen = false;
  bool exited = false;
  bool closing = false;
  bool dropped = false;
  int attempts = 0;
  Timer? startTimer;
  final ready = Completer<void>();
}

/// Opens, feeds and closes the detached windows.
///
/// * [detach] starts a viewer and sends it the stream once it is ready.
/// * [replace] (and [playInWindow]) plays another channel in a window.
/// * [close] asks a viewer to stop and exit (killing it if it does not),
///   [closeAll] closes them all; the app does that when it exits.
/// * A window disappears from the state when its process exits, its
///   connection closes or it says the user closed it.
class DetachedWindows extends Notifier<List<DetachedViewer>> {
  final _viewers = <int, _Viewer>{};
  final _timers = <Timer>{};
  int _nextId = 1;
  AppLifecycleListener? _exitHook;

  /// Wrong-token or junk connections a server takes before it gives up.
  static const _maxAttempts = 8;

  @override
  List<DetachedViewer> build() {
    ref.onDispose(_disposeAll);
    return const [];
  }

  RingLog get _log => ref.read(ringLogProvider);

  /// Opens a window playing [request]. Completes with its id once the
  /// viewer is ready and has the stream; throws a [ViewerLaunchException]
  /// when it could not be started or never answered.
  Future<int> detach(DetachRequest request) async {
    final launcher = ref.read(viewerLauncherProvider);
    final timeouts = ref.read(viewerTimeoutsProvider);
    final log = _log;
    final ServerSocket server;
    try {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    } on Object catch (e) {
      log.warn('Detached window: no loopback server: ${e.runtimeType}');
      throw const ViewerLaunchException('server');
    }
    if (!ref.mounted) {
      unawaited(server.close());
      throw const ViewerLaunchException('disposed');
    }
    final id = _nextId++;
    final viewer = _Viewer(
      id: id,
      server: server,
      token: newViewerToken(),
      request: request,
      log: log,
      timeouts: timeouts,
    )..pendingPlay = _playMessage(request);
    _viewers[id] = viewer;
    _ensureExitHook();
    state = [
      ...state,
      DetachedViewer(
        id: id,
        sourceId: request.sourceId,
        channelKey: request.channelKey,
        title: request.title,
        logo: request.logo,
        maxConnections: request.maxConnections,
      ),
    ];
    viewer.accepts = server.listen(
      (socket) => _onConnection(viewer, socket),
      onError: (Object _) {},
    );
    final args = ViewerLaunchArgs(
      port: server.port,
      token: viewer.token,
      locale: request.locale,
    ).toArgs();
    final ViewerProcess process;
    try {
      process = await launcher.launch(args);
    } on Object catch (e) {
      // ProcessException.toString() repeats the arguments (the token).
      log.warn('Detached window $id: could not start (${e.runtimeType})');
      _drop(viewer, const ViewerLaunchException('start'));
      throw const ViewerLaunchException('start');
    }
    if (viewer.dropped) {
      process.kill();
    } else {
      viewer.process = process;
      log.info('Detached window $id: started (source ${request.sourceId})');
      unawaited(
        process.exitCode.then(
          (code) => _onExit(viewer, code),
          onError: (Object _) => _onExit(viewer, -1),
        ),
      );
      if (!viewer.readySeen) {
        viewer.startTimer = Timer(timeouts.start, () {
          if (viewer.readySeen) return;
          log.warn('Detached window $id: no answer');
          _drop(viewer, const ViewerLaunchException('timeout'));
        });
      }
    }
    await viewer.ready.future;
    return id;
  }

  /// Plays [request] in the window [viewerId] instead of its channel.
  /// False when that window is gone or closing.
  bool replace(int viewerId, DetachRequest request) {
    final viewer = _viewers[viewerId];
    if (viewer == null || viewer.closing || viewer.dropped) return false;
    final play = _playMessage(request);
    if (viewer.readySeen) {
      final channel = viewer.channel;
      if (channel == null || !channel.send(play)) return false;
    } else {
      viewer.pendingPlay = play;
    }
    viewer.request = request;
    _log.info('Detached window $viewerId: new channel');
    _update(
      viewerId,
      (v) => v.copyWith(
        sourceId: request.sourceId,
        channelKey: request.channelKey,
        title: request.title,
        logo: request.logo,
        maxConnections: request.maxConnections,
        status: viewer.readySeen ? ViewerStatus.opening : null,
      ),
    );
    return true;
  }

  /// Resolves the live channel of [request] like the player and plays it
  /// in the window [viewerId]. False when that failed (logged).
  Future<bool> playInWindow(int viewerId, PlayRequest request) async {
    final DetachRequest detach;
    try {
      detach = await resolveDetachRequest(
        request,
        loadSource: ref.read(playerSourceLoaderProvider),
        catalog: ref.read(catalogDaoProvider),
      );
    } on Object catch (e) {
      if (ref.mounted) {
        _log.warn(
          'Detached window $viewerId: cannot resolve: '
          '${hideUrlPaths(redact('$e'))}',
        );
      }
      return false;
    }
    if (!ref.mounted) return false;
    return replace(viewerId, detach);
  }

  /// Asks the window [viewerId] to stop and exit, and waits until it has
  /// (its connection is free then); after [wait] (default
  /// [ViewerTimeouts.close]) it is killed.
  Future<void> close(int viewerId, {Duration? wait}) async {
    final viewer = _viewers[viewerId];
    if (viewer == null || viewer.closing) return;
    viewer.closing = true;
    final timeout = wait ?? viewer.timeouts.close;
    final channel = viewer.channel;
    if (channel != null && channel.send(const CloseMessage())) {
      await channel.flush();
    }
    final process = viewer.process;
    if (process != null && !viewer.exited) {
      final exited = await process.exitCode
          .then((_) => true, onError: (Object _) => true)
          .timeout(timeout, onTimeout: () => false);
      if (!exited) {
        viewer.log.warn('Detached window $viewerId: did not exit; killed');
        process.kill();
      }
    }
    _drop(viewer, const ViewerLaunchException('closed'));
  }

  /// Closes every window ([close]) at once; the app calls it on exit.
  Future<void> closeAll({Duration? wait}) async {
    final ids = [..._viewers.keys];
    if (ids.isEmpty) return;
    _log.info('Detached windows: closing ${ids.length}');
    await Future.wait([for (final id in ids) close(id, wait: wait)]);
  }

  // ---------------------------------------------------------------------

  PlayMessage _playMessage(DetachRequest request) => PlayMessage.of(
    request.stream,
    title: request.title,
    logo: request.logo,
    channelKey: request.channelKey,
    maxConnections: request.maxConnections,
    options: ref.read(engineOptionsProvider),
    secrets: request.secrets,
  );

  /// A connection to [viewer]'s server: it must say hello with the token
  /// first, then it is the viewer's channel and the server closes.
  void _onConnection(_Viewer viewer, Socket socket) {
    if (viewer.dropped || viewer.channel != null) {
      socket.destroy();
      return;
    }
    if (++viewer.attempts > _maxAttempts) {
      socket.destroy();
      _closeServer(viewer);
      return;
    }
    final log = viewer.log;
    var authenticated = false;
    late final SocketViewerChannel channel;
    channel = SocketViewerChannel(
      socket,
      acceptFromViewer: true,
      onMalformed: (reason) {
        if (authenticated) {
          log.warn('Detached window ${viewer.id}: $reason ignored');
        } else {
          // Anything but a hello first is not the viewer.
          log.warn('Detached window ${viewer.id}: connection refused');
          channel.close();
        }
      },
    );
    viewer.pending.add(channel);
    late final Timer handshake;
    handshake = Timer(viewer.timeouts.handshake, () {
      _timers.remove(handshake);
      channel.close();
    });
    _timers.add(handshake);
    void endHandshake() {
      handshake.cancel();
      _timers.remove(handshake);
      viewer.pending.remove(channel);
    }

    channel.messages.listen((message) {
      if (authenticated) {
        _onMessage(viewer, message);
        return;
      }
      endHandshake();
      if (message is HelloMessage &&
          message.version == kViewerProtocolVersion &&
          tokensMatch(viewer.token, message.token) &&
          viewer.channel == null &&
          !viewer.dropped) {
        authenticated = true;
        viewer.channel = channel;
        // One viewer per server: nothing else may connect now.
        _closeServer(viewer);
      } else {
        log.warn('Detached window ${viewer.id}: connection refused');
        channel.close();
      }
    });
    unawaited(
      channel.done.then((_) {
        endHandshake();
        if (!identical(viewer.channel, channel) || viewer.dropped) return;
        if (!viewer.closing) {
          log.info('Detached window ${viewer.id}: connection closed');
        }
        _drop(viewer, const ViewerLaunchException('disconnected'));
      }),
    );
  }

  void _closeServer(_Viewer viewer) {
    unawaited(viewer.accepts?.cancel());
    unawaited(viewer.server.close().then<void>((_) {}, onError: (Object _) {}));
  }

  void _onMessage(_Viewer viewer, ViewerMessage message) {
    if (viewer.dropped) return;
    final id = viewer.id;
    switch (message) {
      case ReadyMessage():
        if (viewer.readySeen) return;
        viewer.readySeen = true;
        viewer.startTimer?.cancel();
        final play = viewer.pendingPlay;
        viewer.pendingPlay = null;
        if (play != null && !(viewer.channel?.send(play) ?? false)) {
          _drop(viewer, const ViewerLaunchException('disconnected'));
          return;
        }
        _update(id, (v) => v.copyWith(status: ViewerStatus.opening));
        if (!viewer.ready.isCompleted) viewer.ready.complete();
      case PlayingMessage():
        _update(id, (v) => v.copyWith(status: ViewerStatus.playing));
      case ViewerErrorMessage(:final message):
        final secrets = viewer.request.secrets;
        viewer.log.warn(
          'Detached window $id: playback failed: '
          '${hideUrlPaths(redact(message, secrets: secrets))}',
        );
        _update(id, (v) => v.copyWith(status: ViewerStatus.failed));
      case ClosedMessage():
        viewer.log.info('Detached window $id: closed by the user');
        viewer.closing = true;
        _drop(viewer, const ViewerLaunchException('closed'));
      case HelloMessage() || PlayMessage() || CloseMessage():
        break;
    }
  }

  void _onExit(_Viewer viewer, int code) {
    viewer.exited = true;
    if (viewer.dropped) return;
    if (!viewer.closing) {
      viewer.log.warn('Detached window ${viewer.id}: exited (code $code)');
    }
    _drop(viewer, const ViewerLaunchException('exited'));
  }

  /// Forgets [viewer]: closes its server and channel, fails a pending
  /// [detach] with [failure], and kills the process if it does not exit by
  /// itself (it does once its channel is closed).
  void _drop(_Viewer viewer, ViewerLaunchException failure) {
    if (viewer.dropped) return;
    viewer.dropped = true;
    viewer.startTimer?.cancel();
    _viewers.remove(viewer.id);
    _closeServer(viewer);
    _closeChannels(viewer);
    if (!viewer.ready.isCompleted) viewer.ready.completeError(failure);
    final process = viewer.process;
    if (process != null && !viewer.exited) {
      late final Timer reaper;
      reaper = Timer(viewer.timeouts.close, () {
        _timers.remove(reaper);
        if (!viewer.exited) process.kill();
      });
      _timers.add(reaper);
    }
    if (ref.mounted) {
      state = [
        for (final v in state)
          if (v.id != viewer.id) v,
      ];
    }
    if (_viewers.isEmpty) {
      _exitHook?.dispose();
      _exitHook = null;
    }
  }

  void _closeChannels(_Viewer viewer) {
    viewer.channel?.close();
    for (final c in [...viewer.pending]) {
      c.close();
    }
    viewer.pending.clear();
  }

  void _update(int id, DetachedViewer Function(DetachedViewer) change) {
    if (!ref.mounted) return;
    state = [for (final v in state) v.id == id ? change(v) : v];
  }

  /// Closes the windows when the app is asked to exit (window closed,
  /// Back on the home screen) or is torn down.
  void _ensureExitHook() {
    _exitHook ??= AppLifecycleListener(
      onExitRequested: () async {
        await closeAll(wait: const Duration(milliseconds: 1500));
        return AppExitResponse.exit;
      },
      onDetach: () => unawaited(closeAll()),
    );
  }

  void _disposeAll() {
    _exitHook?.dispose();
    _exitHook = null;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    for (final viewer in [..._viewers.values]) {
      viewer
        ..dropped = true
        ..startTimer?.cancel();
      viewer.channel?.send(const CloseMessage());
      _closeChannels(viewer);
      _closeServer(viewer);
      if (!viewer.exited) viewer.process?.kill();
      if (!viewer.ready.isCompleted) {
        viewer.ready.completeError(const ViewerLaunchException('disposed'));
      }
    }
    _viewers.clear();
  }
}
