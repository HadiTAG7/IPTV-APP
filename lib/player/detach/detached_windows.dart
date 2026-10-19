// Live channels detached into windows of their own (Windows and Linux).
//
// Each detached window is a second process of the app's executable in
// viewer mode (one Flutter engine and one libmpv per process). The app
// binds a loopback server, starts the viewer with the port (and a one-time
// token in its environment), and sends it the resolved stream once it said
// hello (with the token) and ready. The viewer exits when the connection
// closes, so a crashed or closed app never leaves one holding the
// account's connection.
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
import '../connection_budget.dart';
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
  /// Starts the app's executable with [args] (a [ViewerLaunchArgs] line),
  /// adding [environment] (the token) to the app's own environment.
  Future<ViewerProcess> launch(
    List<String> args, {
    Map<String, String> environment = const {},
  });
}

/// Starts [executable] (default: this app's own) as a separate process,
/// draining its output so it never blocks on a full pipe.
class ProcessViewerLauncher implements ViewerLauncher {
  const ProcessViewerLauncher({this.executable});

  final String? executable;

  @override
  Future<ViewerProcess> launch(
    List<String> args, {
    Map<String, String> environment = const {},
  }) async {
    final exe = executable ?? Platform.resolvedExecutable;
    final process = await Process.start(
      exe,
      args,
      workingDirectory: File(exe).parent.path,
      // Only the process's own user can read its environment (unlike its
      // command line).
      environment: environment,
      includeParentEnvironment: true,
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

  /// The window was closed on purpose ([DetachedWindows.close], the user)
  /// or the app is going away; nothing went wrong.
  bool get closedOnPurpose => reason == 'closed' || reason == 'disposed';

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
  /// Retry asks the app first ([RetryMessage]).
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

/// Completes [listed] once [container] lists a window for [request] that
/// is not listed now ([DetachedWindows.detach] lists it once its server is
/// up; from then on it counts against its source). A stream handed over to
/// a separate window counts until then ([ConnectionDrains]). Close the
/// subscription once the detach is over. Throws a [StateError] once the
/// app's providers are disposed.
ProviderSubscription<List<DetachedViewer>> listenForWindow(
  ProviderContainer container,
  DetachRequest request,
  Completer<void> listed,
) {
  final before = {
    for (final w in container.read(detachedWindowsProvider)) w.id,
  };
  return container.listen<List<DetachedViewer>>(detachedWindowsProvider, (
    _,
    windows,
  ) {
    if (listed.isCompleted) return;
    if (windows.any(
      (w) =>
          !before.contains(w.id) &&
          w.sourceId == request.sourceId &&
          w.channelKey == request.channelKey,
    )) {
      listed.complete();
    }
  });
}

/// The app's side of one viewer.
class _Viewer {
  _Viewer({
    required this.id,
    required this.server,
    required this.token,
    required this.request,
    required this.play,
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

  /// What the window plays ([request]'s message): sent once the viewer is
  /// ready, and again when a Retry is allowed.
  PlayMessage play;

  StreamSubscription<Socket>? accepts;

  /// Connections that have not said hello yet.
  final pending = <ViewerChannel>{};
  ViewerProcess? process;
  ViewerChannel? channel;

  bool readySeen = false;
  bool exited = false;
  bool closing = false;
  bool dropped = false;
  Timer? startTimer;
  final ready = Completer<void>();
}

/// Opens, feeds and closes the detached windows.
///
/// * [detach] starts a viewer and sends it the stream once it is ready.
/// * [replace] (and [playInWindow]) plays another channel in a window.
/// * A failed window's Retry plays its channel again only when its source
///   has a connection free ([connectionBudgetProvider]); otherwise the
///   window is told what uses it ([InUseMessage]).
/// * [close] asks a viewer to stop and exit (killing it if it does not),
///   [closeAll] closes them all; the app does that when it exits.
/// * A window disappears from the state when its process exits, its
///   connection closes or it says the user closed it.
class DetachedWindows extends Notifier<List<DetachedViewer>> {
  final _viewers = <int, _Viewer>{};
  final _timers = <Timer>{};

  /// The [close] in progress of each window, which later callers share.
  final _closes = <int, Future<void>>{};
  int _nextId = 1;
  AppLifecycleListener? _exitHook;

  /// Connections waiting for their hello at once; more are refused (the
  /// server keeps listening for the viewer).
  static const _maxPending = 8;

  @override
  List<DetachedViewer> build() {
    ref.onDispose(_disposeAll);
    return const [];
  }

  RingLog get _log => ref.read(ringLogProvider);

  /// Whether a window plays [request]'s stream ([isViewerStreamUrl]);
  /// [detach] refuses it otherwise. Logged when not.
  bool canPlay(DetachRequest request) => _playMessage(request) != null;

  /// Opens a window playing [request]. Completes with its id once the
  /// viewer is ready and has the stream; throws a [ViewerLaunchException]
  /// when a window cannot play the stream ([isViewerStreamUrl]), it could
  /// not be started, never answered or was closed meanwhile.
  Future<int> detach(DetachRequest request) async {
    final launcher = ref.read(viewerLauncherProvider);
    final timeouts = ref.read(viewerTimeoutsProvider);
    final log = _log;
    final play = _playMessage(request);
    if (play == null) throw const ViewerLaunchException('stream');
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
      play: play,
      log: log,
      timeouts: timeouts,
    );
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
    );
    final ViewerProcess process;
    try {
      process = await launcher.launch(
        args.toArgs(),
        environment: args.environment,
      );
    } on Object catch (e) {
      // Only the type: ProcessException.toString() repeats the command.
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
  /// False when that window is gone or closing, or cannot play the stream.
  bool replace(int viewerId, DetachRequest request) {
    final viewer = _viewers[viewerId];
    if (viewer == null || viewer.closing || viewer.dropped) return false;
    final play = _playMessage(request);
    if (play == null) return false;
    if (viewer.readySeen) {
      final channel = viewer.channel;
      if (channel == null || !channel.send(play)) return false;
    }
    viewer
      ..play = play
      ..request = request;
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
  /// [ViewerTimeouts.close]) it is killed. A window that has not connected
  /// yet is shut out and killed at once: it never gets the stream. Every
  /// caller waits for the same close.
  Future<void> close(int viewerId, {Duration? wait}) {
    final closing = _closes[viewerId];
    if (closing != null) return closing;
    final viewer = _viewers[viewerId];
    if (viewer == null || viewer.closing) return Future.value();
    final done = _close(viewer, wait ?? viewer.timeouts.close);
    _closes[viewerId] = done;
    unawaited(done.whenComplete(() => _closes.remove(viewerId)));
    return done;
  }

  Future<void> _close(_Viewer viewer, Duration timeout) async {
    final viewerId = viewer.id;
    viewer.closing = true;
    final channel = viewer.channel;
    if (channel == null) {
      // Still starting: nothing may connect any more, and with nothing to
      // stop it can go at once.
      _closeServer(viewer);
      _closeChannels(viewer);
      if (!viewer.exited) viewer.process?.kill();
    } else if (channel.send(const CloseMessage())) {
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

  /// The play line for [request]; null (logged) when a window cannot play
  /// its stream.
  PlayMessage? _playMessage(DetachRequest request) {
    try {
      return PlayMessage.of(
        request.stream,
        title: request.title,
        logo: request.logo,
        channelKey: request.channelKey,
        maxConnections: request.maxConnections,
        options: ref.read(engineOptionsProvider),
        secrets: request.secrets,
      );
    } on FormatException catch (e) {
      // The message names the field, never its value.
      _log.warn(
        'Detached window: source ${request.sourceId} stream refused '
        '(${e.message})',
      );
      return null;
    }
  }

  /// A connection to [viewer]'s server: it must say hello with the token
  /// first, then it is the viewer's channel and the server closes.
  void _onConnection(_Viewer viewer, Socket socket) {
    if (viewer.dropped || viewer.closing || viewer.channel != null) {
      socket.destroy();
      return;
    }
    // Junk keeps the server busy only until its handshake times out; the
    // server keeps listening, so the viewer still gets in.
    if (viewer.pending.length >= _maxPending) {
      socket.destroy();
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
          !viewer.dropped &&
          !viewer.closing) {
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
        if (viewer.closing) {
          // Closed while it started: it never gets the stream (close()
          // has told it to exit).
          if (!viewer.ready.isCompleted) {
            viewer.ready.completeError(const ViewerLaunchException('closed'));
          }
          return;
        }
        if (!(viewer.channel?.send(viewer.play) ?? false)) {
          _drop(viewer, const ViewerLaunchException('disconnected'));
          return;
        }
        _update(id, (v) => v.copyWith(status: ViewerStatus.opening));
        if (!viewer.ready.isCompleted) viewer.ready.complete();
      case OpeningMessage():
        _update(id, (v) => v.copyWith(status: ViewerStatus.opening));
      case PlayingMessage():
        _update(id, (v) => v.copyWith(status: ViewerStatus.playing));
      case ViewerErrorMessage(:final message):
        final secrets = viewer.request.secrets;
        viewer.log.warn(
          'Detached window $id: playback failed: '
          '${hideUrlPaths(redact(message, secrets: secrets))}',
        );
        _update(id, (v) => v.copyWith(status: ViewerStatus.failed));
      case RetryMessage():
        _onRetry(viewer);
      case ClosedMessage():
        viewer.log.info('Detached window $id: closed by the user');
        viewer.closing = true;
        _drop(viewer, const ViewerLaunchException('closed'));
      case HelloMessage() || PlayMessage() || InUseMessage() || CloseMessage():
        break;
    }
  }

  /// Retry in [viewer]'s failed window: its channel plays again only when
  /// its source has a connection free without this window (the main
  /// player or another window may have taken it since it failed); else the
  /// window hears what uses it and opens nothing. A source full only
  /// because of streams still stopping ([ConnectionDrains]) is asked again
  /// once they have stopped ([waited]).
  void _onRetry(_Viewer viewer, {bool waited = false}) {
    final id = viewer.id;
    final channel = viewer.channel;
    final status = state.where((v) => v.id == id).firstOrNull?.status;
    // Not failed: a new channel is already on its way to the window.
    if (channel == null ||
        viewer.closing ||
        viewer.dropped ||
        status != ViewerStatus.failed) {
      return;
    }
    final sourceId = viewer.request.sourceId;
    // As connectionBudgetProvider counts (it depends on this notifier, so
    // it cannot be read from here).
    final others = connectionBudgetOf(
      sources: ref.read(sourcesProvider).value ?? const [],
      viewers: state,
      player: ref.read(mainPlayerSourceProvider),
      tiles: ref.read(multiViewTilesProvider),
      stopping: [
        for (final d in ref.read(connectionDrainsProvider)) d.sourceId,
      ],
    ).without(viewerId: id);
    if (!waited && others.waitsForStops(sourceId)) {
      viewer.log.info('Detached window $id: retry waits for a stream to stop');
      unawaited(
        ref.read(connectionDrainsProvider.notifier).settled(sourceId).then((_) {
          if (ref.mounted) _onRetry(viewer, waited: true);
        }),
      );
      return;
    }
    if (!others.fits(sourceId)) {
      // The player and the split screen's tiles are in the main window, and
      // so are the streams still stopping (a tile's or the player's, or one
      // on its way to a window or to the split screen).
      final inMain =
          others.usedOn(sourceId, holder: ConnectionHolder.player) +
          others.usedOn(sourceId, holder: ConnectionHolder.tile) +
          others.usedOn(sourceId, holder: ConnectionHolder.stopping);
      final by = inMain > 0
          ? ConnectionInUseBy.mainWindow
          : ConnectionInUseBy.otherWindow;
      viewer.log.info(
        'Detached window $id: retry refused, the connection is in use '
        '(${by.name})',
      );
      channel.send(InUseMessage(by));
      return;
    }
    if (!channel.send(viewer.play)) {
      _drop(viewer, const ViewerLaunchException('disconnected'));
      return;
    }
    viewer.log.info('Detached window $id: playing again');
    _update(id, (v) => v.copyWith(status: ViewerStatus.opening));
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
  /// [detach] with [failure] (with 'closed' for a window being closed), and
  /// kills the process if it does not exit by itself (it does once its
  /// channel is closed).
  void _drop(_Viewer viewer, ViewerLaunchException failure) {
    if (viewer.dropped) return;
    viewer.dropped = true;
    viewer.startTimer?.cancel();
    _viewers.remove(viewer.id);
    _closeServer(viewer);
    _closeChannels(viewer);
    if (!viewer.ready.isCompleted) {
      viewer.ready.completeError(
        viewer.closing ? const ViewerLaunchException('closed') : failure,
      );
    }
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
