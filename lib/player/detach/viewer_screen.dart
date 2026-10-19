import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/log/ring_log.dart';
import '../../core/net/redact.dart';
import '../../core/platform/window_controls.dart';
import '../../core/time/clock.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';
import '../../widgets/bidi_text.dart';
import '../engine/engine_factory.dart';
import '../engine/engine_policy.dart';
import '../engine/player_engine.dart';
import '../session/playback_controller.dart';
import '../session/reconnect_watchdog.dart';
import '../ui/player_format.dart';
import '../ui/player_overlays.dart';
import 'viewer_protocol.dart';

/// Builds the engine factory for the engine options of a [PlayMessage].
typedef ViewerEngines = EngineFactory Function(EngineOptions options);

/// The detached window's only screen: the channel the app sent, full
/// window, with a mouse-shown bar (channel name, mute and volume, keep on
/// top, small window, fullscreen, close).
///
/// Plays through a [PlaybackController] of its own, so a dropped stream
/// reconnects and a connection the account still holds is retried as in
/// the app's player. Keys: F, F11 and double clicks toggle fullscreen,
/// Escape leaves it, M mutes, Up and Down (and the mouse wheel) change the
/// volume.
///
/// The process ends ([exitProcess]) when the user closes the window (the
/// app hears [ClosedMessage]), when the app asks ([CloseMessage]) and when
/// the connection to the app closes (it quit or crashed): the stream is
/// stopped first, so the account's connection is free.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({
    super.key,
    required this.channel,
    required this.window,
    required this.exitProcess,
    this.engines = defaultEngineFactory,
    this.platform,
    this.wakelock,
    this.log,
    this.clock = const SystemClock(),
    this.reconnectBackoff = kReconnectBackoff,
  });

  /// The connection to the app.
  final ViewerChannel channel;
  final WindowControls window;

  /// Ends the process.
  final Future<void> Function() exitProcess;
  final ViewerEngines engines;

  /// For the engine policy; null: [defaultTargetPlatform].
  final TargetPlatform? platform;
  final ValueChanged<bool>? wakelock;
  final RingLog? log;
  final Clock clock;
  final List<Duration> reconnectBackoff;

  /// The bar hides after this long without the mouse moving.
  static const osdTimeout = Duration(seconds: 4);

  /// Longest wait for the stream to stop before the process ends.
  static const stopTimeout = Duration(seconds: 3);

  /// Volume step of Up, Down and one mouse wheel notch.
  static const volumeStep = 0.1;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late final RingLog _log;
  late final PlaybackController _controller;
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<ViewerMessage>? _messages;

  final _rootNode = FocusNode(debugLabel: 'viewer');
  final _retryNode = FocusNode(debugLabel: 'viewer:retry');

  EngineOptions _options = const EngineOptions();
  PlayMessage? _play;

  /// The last of playing / failed told to the app since the last play.
  PlaybackPhase? _reported;
  bool _failureShown = false;

  bool _pinned = false;
  bool _compact = false;
  bool _fullscreen = false;
  bool _muted = false;
  double _volume = 1;

  bool _osdVisible = false;
  Timer? _osdTimer;

  /// Mouse moves are ignored for a moment after the window changed size:
  /// Windows reports one when the window moves under a still cursor.
  bool _hoverMuted = false;
  Timer? _hoverMuteTimer;

  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _log = widget.log ?? RingLog.instance;
    final platform = targetPlatformKindOf(
      widget.platform ?? defaultTargetPlatform,
    );
    _controller = PlaybackController(
      factory: (kind) => widget.engines(_options)(kind),
      policyInput: () => EnginePolicyInput(platform: platform),
      clock: widget.clock,
      onWakelockChanged: widget.wakelock,
      reconnectBackoff: widget.reconnectBackoff,
    )..addListener(_onController);
    // The window's close button: stop, tell the app, then let it exit.
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    _messages = widget.channel.messages.listen(_onMessage);
    unawaited(widget.channel.done.then((_) => _onDisconnected()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closing) widget.channel.send(const ReadyMessage());
    });
  }

  @override
  void dispose() {
    // Nothing more is sent or started: the process is ending.
    _closing = true;
    _lifecycle.dispose();
    unawaited(_messages?.cancel());
    _osdTimer?.cancel();
    _hoverMuteTimer?.cancel();
    _controller
      ..removeListener(_onController)
      ..dispose();
    widget.channel.close();
    _rootNode.dispose();
    _retryNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // The app.

  void _onMessage(ViewerMessage message) {
    if (_closing) return;
    switch (message) {
      case PlayMessage():
        _startPlay(message);
      case CloseMessage():
        unawaited(_close(notifyApp: false));
      default:
        break;
    }
  }

  void _startPlay(PlayMessage play) {
    _play = play;
    _options = play.engineOptions;
    _reported = null;
    for (final secret in play.secrets) {
      _log.addSecret(secret);
    }
    _log.info('Viewer: playing "${play.redactText(play.title)}"');
    if (play.title.isNotEmpty) unawaited(widget.window.setTitle(play.title));
    if (mounted) setState(() {});
    unawaited(
      _controller.play(
        play.stream,
        itemKey: play.channelKey,
        maxConnections: play.maxConnections,
      ),
    );
  }

  /// Tells the app when the stream plays or failed (once per change).
  void _onController() {
    if (_closing || !mounted) return;
    final phase = _controller.phase;
    if (phase != _reported) {
      if (phase == PlaybackPhase.playing) {
        _reported = phase;
        widget.channel.send(const PlayingMessage());
      } else if (phase == PlaybackPhase.failed) {
        _reported = phase;
        widget.channel.send(
          ViewerErrorMessage(_redact(_controller.errorMessage ?? '')),
        );
      }
    }
    final failed = phase == PlaybackPhase.failed;
    if (failed != _failureShown) {
      _failureShown = failed;
      if (failed) {
        _hideOsd();
        _focusAfterBuild(_retryNode);
      } else {
        _focusAfterBuild(_rootNode);
      }
    }
    setState(() {});
  }

  void _onDisconnected() {
    if (_closing) return;
    _log.info('Viewer: the app is gone; closing');
    unawaited(_close(notifyApp: false));
  }

  Future<AppExitResponse> _onExitRequested() async {
    await _close(notifyApp: true, exit: false);
    return AppExitResponse.exit;
  }

  /// Stops the stream (bounded), tells the app when [notifyApp], closes
  /// the connection and, with [exit], ends the process.
  Future<void> _close({required bool notifyApp, bool exit = true}) async {
    if (_closing) return;
    _closing = true;
    _osdTimer?.cancel();
    if (mounted) setState(() => _osdVisible = false);
    try {
      await _controller.stop().timeout(ViewerScreen.stopTimeout);
    } on Object catch (_) {
      // Stuck engine: the process ends anyway, closing the connection.
    }
    if (notifyApp && widget.channel.send(const ClosedMessage())) {
      await widget.channel.flush();
    }
    widget.channel.close();
    if (exit) await widget.exitProcess();
  }

  String _redact(String text) =>
      hideUrlPaths(_play?.redactText(text) ?? redact(text));

  // ---------------------------------------------------------------------
  // Window and sound.

  void _muteHover() {
    _hoverMuted = true;
    _hoverMuteTimer?.cancel();
    _hoverMuteTimer = Timer(
      const Duration(milliseconds: 600),
      () => _hoverMuted = false,
    );
  }

  Future<void> _togglePin() async {
    if (_closing) return;
    final pinned = !_pinned;
    setState(() => _pinned = pinned);
    _restartOsdTimer();
    await widget.window.setAlwaysOnTop(pinned);
  }

  Future<void> _toggleCompact() async {
    if (_closing) return;
    final compact = !_compact;
    final wasFullscreen = _fullscreen;
    setState(() {
      _compact = compact;
      if (compact) _fullscreen = false;
    });
    _muteHover();
    _restartOsdTimer();
    if (compact) {
      // The Windows runner leaves fullscreen itself; GTK's does not.
      if (wasFullscreen) await widget.window.fullscreen.exit();
      await widget.window.enterCompact();
    } else {
      await widget.window.exitCompact();
    }
  }

  Future<void> _toggleFullscreen() async {
    if (_closing) return;
    await _setFullscreen(!_fullscreen);
  }

  Future<void> _setFullscreen(bool on) async {
    if (on == _fullscreen) return;
    final wasCompact = _compact;
    setState(() {
      _fullscreen = on;
      if (on) _compact = false;
    });
    _muteHover();
    _restartOsdTimer();
    // Fullscreen from the small window leaves it first, so leaving
    // fullscreen later brings back the normal window.
    if (on && wasCompact) await widget.window.exitCompact();
    await (on
        ? widget.window.fullscreen.enter()
        : widget.window.fullscreen.exit());
  }

  Future<void> _toggleMute() async {
    if (_closing) return;
    final muted = !_muted;
    setState(() => _muted = muted);
    _restartOsdTimer();
    await _controller.setMuted(muted);
  }

  Future<void> _setVolume(double volume) async {
    if (_closing) return;
    final v = volume.clamp(0.0, 1.0);
    final unmute = _muted && v > 0;
    setState(() {
      _volume = v;
      if (unmute) _muted = false;
    });
    _restartOsdTimer();
    if (unmute) await _controller.setMuted(false);
    await _controller.setVolume(v);
  }

  Future<void> _retry() async {
    _reported = null;
    await _controller.retry();
  }

  // ---------------------------------------------------------------------
  // OSD, keys and mouse.

  void _showOsd() {
    if (_closing || _controller.phase == PlaybackPhase.failed) return;
    if (!_osdVisible) setState(() => _osdVisible = true);
    _restartOsdTimer();
  }

  void _hideOsd() {
    _osdTimer?.cancel();
    _osdTimer = null;
    if (!_osdVisible) return;
    if (_rootNode.hasFocus && !_rootNode.hasPrimaryFocus) {
      _rootNode.requestFocus();
    }
    if (mounted) setState(() => _osdVisible = false);
  }

  void _restartOsdTimer() {
    if (!_osdVisible) return;
    _osdTimer?.cancel();
    _osdTimer = Timer(ViewerScreen.osdTimeout, _hideOsd);
  }

  void _onHover() {
    if (_hoverMuted) return;
    _showOsd();
  }

  void _focusAfterBuild(FocusNode node) {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted && node.context != null) node.requestFocus();
      })
      ..ensureVisualUpdate();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_closing) return KeyEventResult.handled;
    final key = event.logicalKey;
    final down = event is KeyDownEvent;
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.f11 || key == LogicalKeyboardKey.keyF) {
      if (down) unawaited(_toggleFullscreen());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (!_fullscreen) return KeyEventResult.ignored;
      if (down) unawaited(_setFullscreen(false));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      if (down) unawaited(_toggleMute());
      return KeyEventResult.handled;
    }
    // Up and Down move between the bar's buttons once one has focus.
    if (_rootNode.hasPrimaryFocus &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      final step = key == LogicalKeyboardKey.arrowUp
          ? ViewerScreen.volumeStep
          : -ViewerScreen.volumeStep;
      unawaited(_setVolume(_volume + step));
      _showOsd();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _closing) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    _showOsd();
    unawaited(
      _setVolume(_volume + (dy < 0 ? 1 : -1) * ViewerScreen.volumeStep),
    );
  }

  // ---------------------------------------------------------------------
  // Build.

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final failed = _controller.phase == PlaybackPhase.failed;
    final topBarHeight = OsdIconButton.size + 2 * Spacing.md;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _rootNode,
        autofocus: true,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          key: const ValueKey('viewer-mouse'),
          cursor: _osdVisible || failed
              ? MouseCursor.defer
              : SystemMouseCursors.none,
          onHover: (_) => _onHover(),
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: Stack(
              fit: StackFit.expand,
              children: [
                KeyedSubtree(
                  key: const ValueKey('viewer-video'),
                  child: _controller.buildView(),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('viewer-gestures'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _osdVisible ? _hideOsd() : _showOsd(),
                    onDoubleTap: () => unawaited(_toggleFullscreen()),
                  ),
                ),
                if (!failed) _buffering(),
                if (_osdVisible && !failed) _osd(l10n),
                SafeArea(
                  minimum: const EdgeInsets.all(Spacing.md),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: _osdVisible ? topBarHeight : 0,
                          ),
                          child: PlayerReconnectBanner(
                            status: _controller.reconnectStatus,
                          ),
                        ),
                      ),
                      if (failed)
                        Center(
                          child: SingleChildScrollView(
                            child: PlayerFailureCard(
                              message: l10n.playerPlaybackFailed,
                              details: _redact(_controller.errorMessage ?? ''),
                              retryNode: _retryNode,
                              onRetry: () => unawaited(_retry()),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A spinner while nothing was sent yet, the stream opens or rebuffers.
  Widget _buffering() => ValueListenableBuilder<PlaybackState>(
    valueListenable: _controller.state,
    builder: (context, st, _) {
      final phase = _controller.phase;
      final waiting =
          phase == PlaybackPhase.idle && !_closing ||
          phase == PlaybackPhase.opening ||
          (st.buffering && phase == PlaybackPhase.playing);
      if (!waiting) return const SizedBox.shrink();
      return const Center(
        key: ValueKey('viewer-buffering'),
        child: SizedBox.square(
          dimension: 40,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    },
  );

  /// The top bar; the title and the volume slider make way in a small
  /// window.
  Widget _osd(AppLocalizations l10n) {
    final title = _play?.title ?? '';
    Widget button({
      required String id,
      required IconData icon,
      required String label,
      required VoidCallback onSelect,
    }) => Padding(
      padding: const EdgeInsetsDirectional.only(start: Spacing.sm),
      child: OsdIconButton(
        key: ValueKey('viewer-$id'),
        icon: icon,
        label: label,
        onFocus: _restartOsdTimer,
        onSelect: onSelect,
      ),
    );

    return Positioned(
      key: const ValueKey('viewer-osd'),
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xCC000000), Color(0x00000000)],
          ),
        ),
        padding: const EdgeInsets.all(Spacing.md),
        child: LayoutBuilder(
          builder: (context, c) {
            final showTitle = c.maxWidth >= 420;
            final showSlider = c.maxWidth >= 600;
            return Row(
              children: [
                if (showTitle)
                  Expanded(
                    child: BidiText(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  )
                else
                  const Spacer(),
                button(
                  id: 'mute',
                  icon: _muted || _volume == 0
                      ? Icons.volume_off
                      : Icons.volume_up,
                  label: _muted ? l10n.viewerUnmute : l10n.viewerMute,
                  onSelect: () => unawaited(_toggleMute()),
                ),
                if (showSlider)
                  SizedBox(
                    width: 120,
                    child: Slider(
                      key: const ValueKey('viewer-volume'),
                      value: _muted ? 0 : _volume,
                      label: l10n.viewerVolume,
                      semanticFormatterCallback: (v) => '${(v * 100).round()}%',
                      onChanged: (v) => unawaited(_setVolume(v)),
                    ),
                  ),
                button(
                  id: 'pin',
                  icon: _pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  label: _pinned ? l10n.viewerUnpin : l10n.viewerPin,
                  onSelect: () => unawaited(_togglePin()),
                ),
                button(
                  id: 'compact',
                  icon: _compact
                      ? Icons.open_in_full
                      : Icons.picture_in_picture_alt_outlined,
                  label: _compact ? l10n.viewerNormalSize : l10n.viewerCompact,
                  onSelect: () => unawaited(_toggleCompact()),
                ),
                button(
                  id: 'fullscreen',
                  icon: _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  label: _fullscreen
                      ? l10n.playerExitFullscreen
                      : l10n.playerFullscreen,
                  onSelect: () => unawaited(_toggleFullscreen()),
                ),
                button(
                  id: 'close',
                  icon: Icons.close,
                  label: l10n.commonClose,
                  onSelect: () => unawaited(_close(notifyApp: true)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
