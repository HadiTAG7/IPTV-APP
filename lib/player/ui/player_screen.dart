import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/form_factor.dart';
import '../../app/providers.dart';
import '../../core/db/queries/player_ui_queries.dart';
import '../../core/net/redact.dart';
import '../../core/platform/window_fullscreen.dart';
import '../../core/time/clock.dart';
import '../../epg/epg_providers.dart';
import '../../features/channel_lists/channel_list_dialogs.dart';
import '../../features/diagnostics/providers.dart';
import '../../features/live/channel_source.dart';
import '../../features/live/live_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../sources/models.dart';
import '../../theme/tokens.dart';
import '../../tv/dpad_shortcuts.dart';
import '../../tv/focus_watchdog.dart';
import '../../tv/key_repeat.dart';
import '../../widgets/bidi_text.dart';
import '../connection_budget.dart';
import '../detach/detached_windows.dart';
import '../engine/player_engine.dart';
import '../player_providers.dart';
import '../session/playback_controller.dart';
import 'channel_panel.dart';
import 'paged_zapper.dart';
import 'play_request.dart';
import 'player_dialogs.dart';
import 'player_format.dart';
import 'player_overlays.dart';
import 'player_route.dart';
import 'player_session.dart';
import 'seek_accumulator.dart';

/// Actions of the OSD and the Menu-key options list.
enum PlayerAction {
  channels,

  /// Desktop live: plays the channel in a window of its own.
  detach,
  audio,
  subtitles,
  aspect,
  favorite,
  addToList,
  switchPlayer,
  guide,
  stats,
}

/// Fullscreen player for live channels, movies and episodes.
///
/// * Video from the engine ([PlaybackController.buildView]) with the item's
///   aspect ratio (saved per channel, default from Settings).
/// * Live: channel banner, number entry, zapping (Up/Down, CH+/CH-,
///   PageUp/PageDown) within the request's list, OSD with now/next, clock
///   and Channels, Audio, Subtitles, Aspect, Favourite, Add to list, Switch
///   player, Guide, Stats.
/// * Live channel panel ([ChannelPanel]; OK, the Channels button or
///   option): the Live screen's lists and channels beside the playing
///   video. Picking a channel tunes it like a zap and makes its list the
///   zapping list ([PlayerSession.tuneTo]); Back, a click beside it or 15 s
///   without input close it.
/// * VOD: OSD with an LTR seek bar, ±10 s seeking (accelerating while held,
///   one seek 600 ms after the last press), FF/RW ±30 s, the resume prompt
///   and the next-episode countdown.
/// * Reconnect banner, failure card (Retry, Try other format, Copy report),
///   stats overlay. Back only through [PopScope]: it closes the channel
///   panel and hides the OSD first.
/// * Phones: tap toggles the OSD, double-tap seeks, landscape is forced
///   while the player is open. TVs never touch the orientation.
/// * Desktop: the window turns truly fullscreen (no title bar, over the
///   taskbar) while the player is open, unless the user last chose a
///   window; the fullscreen button, F, F11 and double clicks toggle it and
///   Escape leaves it. Moving the mouse shows the OSD; the cursor hides
///   with it. Live channels can be detached (Separate window, D) into a
///   window of their own ([DetachedWindows]): the player closes, and only
///   once its stream is stopped does the window open it.
/// * Phones and desktop: the OSD's top bar has a Back button.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.request});

  final PlayRequest request;

  /// The OSD hides after this long without a key press.
  static const osdTimeout = Duration(seconds: 5);

  /// The channel panel closes after this long without a key press or
  /// mouse or touch activity.
  static const panelTimeout = Duration(seconds: 15);

  /// How long the channel banner stays after zapping or opening.
  static const bannerTimeout = Duration(seconds: 4);

  /// Seek step of Left/Right (and phone double taps).
  static const seekStep = Duration(seconds: 10);

  /// Seek step of the FF/RW keys.
  static const fastSeekStep = Duration(seconds: 30);

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final ProviderSubscription<PlaybackController> _controllerSub;
  late final PlaybackController _controller;
  late final PlayerSession _session;
  late final SeekAccumulator _seek;
  late final AppLifecycleListener _lifecycle;

  /// Whether the engine is playing (the play/pause button follows it
  /// without rebuilding the whole screen on every position update).
  final _playing = ValueNotifier<bool>(false);
  late final Clock _clock;
  StreamSubscription<bool>? _onlineSub;

  final _rootNode = FocusNode(debugLabel: 'player');
  final _osdFirstNode = FocusNode(debugLabel: 'player:osd-first');
  final _seekBarNode = FocusNode(debugLabel: 'player:seek-bar');
  final _retryNode = FocusNode(debugLabel: 'player:retry');
  final _resumeNode = FocusNode(debugLabel: 'player:resume');
  final _nextNode = FocusNode(debugLabel: 'player:next-episode');

  bool _osdVisible = false;

  /// The OSD shows without having taken focus (the mouse showed it): keys
  /// act as if it were hidden while focus stays on the player.
  bool _osdByMouse = false;
  bool _statsVisible = false;
  bool _bannerVisible = false;
  Timer? _osdTimer;
  Timer? _bannerTimer;

  final _panel = GlobalKey<ChannelPanelState>();
  bool _panelVisible = false;
  Timer? _panelTimer;

  /// Bumped when the panel closes or a channel is picked in it: a pick
  /// still reading its list's zapping keys is dropped.
  int _panelTuneSeq = 0;
  int _dialogs = 0;
  bool _exiting = false;

  bool _failureShown = false;
  bool _resumeShown = false;
  bool _countdownShown = false;

  ValueListenable<ZapView>? _zapPreview;
  FocusWatchdogState? _watchdog;
  bool _depsReady = false;
  bool _landscapeLocked = false;

  DateTime? _seekHeldSince;
  DateTime? _lastSeekRepeat;
  double? _doubleTapFraction;

  /// The phone player holding the landscape lock. A closing player gives
  /// the orientation back only while it still holds it, so it never undoes
  /// the lock of a player opened during its exit transition.
  static Object? _orientationOwner;

  /// The player reported as fullscreen playback (guide imports wait for it
  /// on Lite devices), with the same hand-over rule as the orientation.
  static Object? _fullscreenOwner;
  late final FullscreenPlayback _fullscreen;

  /// The connection budget's record of this player, handed over the same
  /// way.
  late final MainPlayerSource _mainPlayer;

  /// The desktop window ([playerWindowProvider]); null on Android.
  WindowFullscreen? _window;
  bool _windowFullscreen = false;

  /// The player holding the window fullscreen, with the same hand-over
  /// rule as the orientation.
  static Object? _windowOwner;

  /// Mouse moves are ignored for a moment after the window changed size:
  /// Windows reports one when the window moves under a still cursor.
  bool _hoverMuted = false;
  Timer? _hoverMuteTimer;

  bool get _failed =>
      _controller.phase == PlaybackPhase.failed || _session.error != null;

  @override
  void initState() {
    super.initState();
    _clock = ref.read(clockProvider);
    _controllerSub = ref.listenManual(playbackControllerProvider, (_, _) {});
    _controller = _controllerSub.read();
    _session = PlayerSession(
      request: widget.request,
      controller: _controller,
      db: ref.read(databaseProvider),
      loadSource: ref.read(playerSourceLoaderProvider),
      settings: () => ref.read(settingsProvider),
      clock: _clock,
      onChannelPlayed: ref.read(onChannelPlayedProvider),
      log: ref.read(ringLogProvider),
    )..addListener(_onSessionChanged);
    _controller.addListener(_onControllerChanged);
    _controller.state.addListener(_onPlaybackState);
    _seek = SeekAccumulator(
      onCommit: (target) => unawaited(_controller.seek(target)),
    )..addListener(_rebuild);
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    HardwareKeyboard.instance.addHandler(_onAnyKey);
    _onlineSub = ref.read(playerOnlineProvider)?.listen(_controller.setOnline);
    _fullscreen = ref.read(fullscreenPlaybackProvider.notifier);
    _mainPlayer = ref.read(mainPlayerSourceProvider.notifier);
    _fullscreenOwner = this;
    // Not while the route is being built.
    scheduleMicrotask(() {
      if (!identical(_fullscreenOwner, this)) return;
      _fullscreen.set(true);
      _mainPlayer.set(widget.request.sourceId);
    });
    _window = ref.read(playerWindowProvider);
    if (ref.read(playerOpensFullscreenProvider)) _setWindowFullscreen(true);
    // New guide data: the banner and OSD read now/next again.
    ref.listenManual<GuideRefreshStatus>(
      guideRefreshProvider(widget.request.sourceId),
      (previous, next) {
        if (next is GuideRefreshDone && previous is! GuideRefreshDone) {
          _session.reloadGuide();
        }
      },
    );
    unawaited(_session.start());
    _bannerVisible = true;
    _bannerTimer = Timer(PlayerScreen.bannerTimeout, () {
      if (mounted) setState(() => _bannerVisible = false);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final watchdog = FocusWatchdog.maybeOf(context);
    if (watchdog != _watchdog) {
      _watchdog?.unregister(_rootNode);
      _watchdog = watchdog?..register(_rootNode);
    }
    if (!_depsReady) {
      _depsReady = true;
      if (FormFactorScope.of(context) == FormFactor.phone) _lockLandscape();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    HardwareKeyboard.instance.removeHandler(_onAnyKey);
    _osdTimer?.cancel();
    _bannerTimer?.cancel();
    _panelTimer?.cancel();
    unawaited(_onlineSub?.cancel());
    _watchdog?.unregister(_rootNode);
    _zapPreview?.removeListener(_onZapPreview);
    _session
      ..removeListener(_onSessionChanged)
      ..dispose();
    _controller.removeListener(_onControllerChanged);
    _controller.state.removeListener(_onPlaybackState);
    _playing.dispose();
    _seek.dispose();
    for (final node in [
      _rootNode,
      _osdFirstNode,
      _seekBarNode,
      _retryNode,
      _resumeNode,
      _nextNode,
    ]) {
      node.dispose();
    }
    _releaseOrientation();
    _releaseFullscreen(later: true);
    _setWindowFullscreen(false);
    _hoverMuteTimer?.cancel();
    _controllerSub.close();
    super.dispose();
  }

  /// Ends the fullscreen playback report (and the player's place in the
  /// connection budget) while this player holds it; [later] when the
  /// widget tree is being finalized (providers cannot change then).
  void _releaseFullscreen({bool later = false}) {
    if (!identical(_fullscreenOwner, this)) return;
    _fullscreenOwner = null;
    final fullscreen = _fullscreen;
    final mainPlayer = _mainPlayer;
    void release() {
      fullscreen.set(false);
      mainPlayer.set(null);
    }

    if (later) {
      scheduleMicrotask(release);
    } else {
      release();
    }
  }

  // ---------------------------------------------------------------------
  // Platform: orientation and lifecycle.

  void _lockLandscape() {
    _landscapeLocked = true;
    _orientationOwner = this;
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  /// Gives back the orientation and system bars (on exit, or dispose when
  /// the route went away without [_exit]) unless another player took them.
  void _releaseOrientation() {
    if (!_landscapeLocked) return;
    _landscapeLocked = false;
    if (!identical(_orientationOwner, this)) return;
    _orientationOwner = null;
    unawaited(SystemChrome.setPreferredOrientations(const []));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }

  /// Makes the desktop window fullscreen ([on]) or gives it back. Only the
  /// player holding it gives it back, so a closing player never undoes the
  /// fullscreen of one opened during its exit transition.
  void _setWindowFullscreen(bool on) {
    final window = _window;
    if (window == null || on == _windowFullscreen) return;
    _windowFullscreen = on;
    _hoverMuted = true;
    _hoverMuteTimer?.cancel();
    _hoverMuteTimer = Timer(
      const Duration(milliseconds: 600),
      () => _hoverMuted = false,
    );
    if (on) {
      _windowOwner = this;
      unawaited(window.enter());
    } else if (identical(_windowOwner, this)) {
      _windowOwner = null;
      unawaited(window.exit());
    }
  }

  /// The fullscreen button, F, F11 and double clicks. The choice also
  /// decides how the next player opens.
  void _toggleWindowFullscreen() {
    if (_window == null || _exiting) return;
    _setWindowFullscreen(!_windowFullscreen);
    ref.read(playerOpensFullscreenProvider.notifier).set(_windowFullscreen);
    _restartOsdTimer();
    _rebuild();
  }

  /// Desktop: moving the mouse shows the OSD and keeps it up while the
  /// mouse moves. The keyboard stays with the player (arrows still zap):
  /// a nudged mouse must not take it.
  void _onMouseMoved() {
    if (_exiting || _cardShown || _hoverMuted) return;
    if (_panelVisible) {
      _restartPanelTimer();
      return;
    }
    if (_osdVisible) {
      _restartOsdTimer();
    } else {
      _showOsd(moveFocus: false);
    }
  }

  void _onLifecycle(AppLifecycleState state) {
    // A closing player leaves the shared controller to the next one.
    if (_exiting) return;
    switch (state) {
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _session.onBackground();
        unawaited(_controller.onBackground());
      case AppLifecycleState.resumed:
        unawaited(_controller.onForeground());
        _session.onForeground();
      case AppLifecycleState.inactive:
        break;
    }
  }

  // ---------------------------------------------------------------------
  // State changes.

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onSessionChanged() {
    if (_exiting) return;
    final preview = _session.zapPreview;
    if (preview != _zapPreview) {
      _zapPreview?.removeListener(_onZapPreview);
      _zapPreview = preview?..addListener(_onZapPreview);
    }
    _syncCards();
    _rebuild();
  }

  void _onControllerChanged() {
    // The controller may already play for the next player screen.
    if (_exiting) return;
    _onPlaybackState();
    _syncCards();
    // A title that ended (without a next episode) shows its controls.
    if (!_session.isLive &&
        _controller.phase == PlaybackPhase.ended &&
        !_osdVisible &&
        !_cardShown &&
        _session.nextEpisode == null) {
      _showOsd();
      return;
    }
    _rebuild();
  }

  /// Play/Pause shows what the user meant, not the engine's momentary state
  /// (ExoPlayer is "not playing" while it rebuffers).
  void _onPlaybackState() => _playing.value = _controller.playIntended;

  void _onZapPreview() {
    final p = _zapPreview?.value;
    if (p == null) return;
    if (p.pending || p.digits.isNotEmpty) {
      if (_osdVisible && p.digits.isEmpty) _hideOsd();
      _showBanner();
    }
  }

  /// Moves focus onto cards that appear (failure, resume prompt, next
  /// episode) and back to the player when they go.
  void _syncCards() {
    if (!mounted) return;
    final failed = _failed;
    if (failed != _failureShown) {
      _failureShown = failed;
      if (failed) {
        _closePanel();
        _hideOsd();
        _focusAfterBuild(_retryNode);
      } else {
        _focusRoot();
      }
    }
    final resume = _session.resumeOffer != null;
    if (resume != _resumeShown) {
      _resumeShown = resume;
      if (resume) {
        _hideOsd();
        _focusAfterBuild(_resumeNode);
      } else {
        _focusRoot();
      }
    }
    final countdown = _session.countdown != null;
    if (countdown != _countdownShown) {
      _countdownShown = countdown;
      if (countdown) {
        _hideOsd();
        _focusAfterBuild(_nextNode);
      } else {
        _focusRoot();
      }
    }
  }

  bool get _isCurrentRoute => ModalRoute.of(context)?.isCurrent ?? true;

  /// The primary button of the card on screen (failure, resume prompt,
  /// next-episode countdown), or null without a card.
  FocusNode? get _cardNode {
    if (_failed) return _retryNode;
    if (_session.resumeOffer != null) return _resumeNode;
    if (_session.countdown != null && _session.nextEpisode != null) {
      return _nextNode;
    }
    return null;
  }

  /// Puts focus back on the card's primary button, e.g. after a dialog
  /// closed: a card that appeared behind the dialog could not take focus.
  void _refocusCard() {
    final node = _cardNode;
    if (node == null || _exiting || !mounted) return;
    _focusAfterBuild(node);
  }

  void _focusRoot() {
    if (!mounted || !_isCurrentRoute) return;
    if (!_rootNode.hasPrimaryFocus) _rootNode.requestFocus();
  }

  void _focusAfterBuild(FocusNode node) {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted || node.context == null || !_isCurrentRoute) return;
        node.requestFocus();
      })
      ..ensureVisualUpdate();
  }

  // ---------------------------------------------------------------------
  // OSD, banner, stats.

  bool get _cardShown =>
      _failed || _session.resumeOffer != null || _session.countdown != null;

  /// Shows the OSD; [moveFocus] false leaves focus on the player (the
  /// mouse showed it).
  void _showOsd({FocusNode? focus, bool moveFocus = true}) {
    if (_cardShown || _panelVisible) return;
    final target = focus ?? (_session.isLive ? _osdFirstNode : _seekBarNode);
    setState(() {
      _osdVisible = true;
      _bannerVisible = false;
    });
    _osdByMouse = !moveFocus;
    _restartOsdTimer();
    if (moveFocus) _focusAfterBuild(target);
  }

  void _hideOsd() {
    _osdTimer?.cancel();
    _osdTimer = null;
    _osdByMouse = false;
    if (!_osdVisible) return;
    if (_rootNode.hasFocus) _focusRoot();
    if (mounted) setState(() => _osdVisible = false);
  }

  /// A tap or click on the picture. A desktop click leaves the keyboard on
  /// the player, as moving the mouse does.
  void _toggleOsd() =>
      _osdVisible ? _hideOsd() : _showOsd(moveFocus: _window == null);

  void _restartOsdTimer() {
    if (!_osdVisible) return;
    _osdTimer?.cancel();
    _osdTimer = Timer(PlayerScreen.osdTimeout, _onOsdTimeout);
  }

  void _onOsdTimeout() {
    if (!mounted) return;
    final st = _controller.state.value;
    final vodPaused =
        !_session.isLive &&
        !st.playing &&
        _controller.phase != PlaybackPhase.opening;
    if (_dialogs > 0 || _seek.pending || vodPaused) {
      _restartOsdTimer();
      return;
    }
    _hideOsd();
  }

  void _showBanner([Duration duration = PlayerScreen.bannerTimeout]) {
    _bannerTimer?.cancel();
    _bannerTimer = Timer(duration, () {
      if (mounted) setState(() => _bannerVisible = false);
    });
    if (!_bannerVisible && mounted) setState(() => _bannerVisible = true);
  }

  // ---------------------------------------------------------------------
  // Channel panel.

  /// Shows the channel panel (live only) on the zapping list and the
  /// channel playing. The OSD and the banner make way; the panel moves
  /// focus in once its entries are read.
  void _openPanel() {
    if (!_session.isLive || _cardShown || _exiting || _panelVisible) return;
    // The panel opens on the channel playing: nothing tunes behind it.
    _session.cancelPendingZap();
    _hideOsd();
    _bannerTimer?.cancel();
    setState(() {
      _panelVisible = true;
      _bannerVisible = false;
    });
    _restartPanelTimer();
  }

  /// Hides the channel panel; focus inside it goes back to the player.
  void _closePanel() {
    _panelTimer?.cancel();
    _panelTimer = null;
    _panelTuneSeq++;
    if (!_panelVisible) return;
    if (_rootNode.hasFocus) _focusRoot();
    if (mounted) setState(() => _panelVisible = false);
  }

  void _restartPanelTimer() {
    if (!_panelVisible || _exiting) return;
    _panelTimer?.cancel();
    _panelTimer = Timer(PlayerScreen.panelTimeout, _onPanelTimeout);
  }

  void _onPanelTimeout() {
    if (!mounted) return;
    if (_dialogs > 0) {
      _restartPanelTimer();
      return;
    }
    _closePanel();
  }

  /// Every key restarts the panel's timer, also those its rows and columns
  /// handle themselves (they never reach [_onKey]). Never handles a key.
  bool _onAnyKey(KeyEvent event) {
    _restartPanelTimer();
    return false;
  }

  /// The list the panel opens on: the one zapping walks, else (search
  /// results) All channels.
  LiveList _panelList() {
    final request = _session.request;
    final category = request.categoryKey;
    return request.list ??
        (category != null && request.zapKeys == null
            ? LiveList.category(category)
            : const LiveList.all());
  }

  /// A channel picked in the panel plays (the same path as a zap: one
  /// connection at a time) and its list becomes the zapping list.
  Future<void> _tuneFromPanel(ChannelListSource source, LiveEntry entry) async {
    final row = entry.row;
    if (row == null || _exiting || !_panelVisible) return;
    final seq = ++_panelTuneSeq;
    final PlayRequest request;
    try {
      // The list's own zapping request (keyed lists read their channels).
      request = await source.requestFor(row);
    } on Object catch (e) {
      ref.read(ringLogProvider).warn('Player: panel channel failed: $e');
      return;
    }
    if (!mounted || _exiting || seq != _panelTuneSeq || !_panelVisible) return;
    _closePanel();
    _showBanner();
    unawaited(_session.tuneTo(request, row: row));
  }

  /// Menu (or a held OK) on a channel of the panel: favourite, Add to list.
  Future<void> _panelChannelMenu(LiveEntry entry, bool favorite) async {
    final l10n = AppLocalizations.of(context);
    final action = await _dialog(
      () => showPlayerChoiceDialog<PlayerAction>(
        context,
        title: entry.row?.name ?? l10n.commonUnavailable,
        choices: [
          PlayerChoice(
            value: PlayerAction.favorite,
            label: favorite ? l10n.liveRemoveFavorite : l10n.liveAddFavorite,
            icon: favorite ? Icons.star : Icons.star_border,
          ),
          PlayerChoice(
            value: PlayerAction.addToList,
            label: l10n.liveAddToList,
            icon: Icons.playlist_add,
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    final s = _session;
    switch (action) {
      case PlayerAction.favorite:
        // The channel playing goes through the session (OSD star).
        if (entry.key == s.request.item.key) {
          await _toggleFavorite();
          return;
        }
        try {
          await ref
              .read(favoritesDaoProvider)
              .setFavorite(s.sourceId, ContentKind.live, entry.key, !favorite);
        } on Object catch (e) {
          ref.read(ringLogProvider).warn('Player: favourite failed: $e');
          return;
        }
        if (mounted) _showFavoriteSnack(added: !favorite);
      case PlayerAction.addToList:
        await _dialog<void>(
          () => showAddToListDialog(
            context,
            ref,
            sourceId: s.sourceId,
            channelKey: entry.key,
          ),
        );
      default:
        break;
    }
  }

  // ---------------------------------------------------------------------
  // Keys.

  static final _digitKeys = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.digit0: 0,
    LogicalKeyboardKey.digit1: 1,
    LogicalKeyboardKey.digit2: 2,
    LogicalKeyboardKey.digit3: 3,
    LogicalKeyboardKey.digit4: 4,
    LogicalKeyboardKey.digit5: 5,
    LogicalKeyboardKey.digit6: 6,
    LogicalKeyboardKey.digit7: 7,
    LogicalKeyboardKey.digit8: 8,
    LogicalKeyboardKey.digit9: 9,
    LogicalKeyboardKey.numpad0: 0,
    LogicalKeyboardKey.numpad1: 1,
    LogicalKeyboardKey.numpad2: 2,
    LogicalKeyboardKey.numpad3: 3,
    LogicalKeyboardKey.numpad4: 4,
    LogicalKeyboardKey.numpad5: 5,
    LogicalKeyboardKey.numpad6: 6,
    LogicalKeyboardKey.numpad7: 7,
    LogicalKeyboardKey.numpad8: 8,
    LogicalKeyboardKey.numpad9: 9,
  };

  static final _zapUpKeys = {
    LogicalKeyboardKey.channelUp,
    LogicalKeyboardKey.pageUp,
  };
  static final _zapDownKeys = {
    LogicalKeyboardKey.channelDown,
    LogicalKeyboardKey.pageDown,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_exiting) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (event is KeyUpEvent) {
      if (arrowDirection(key) != null) _seekHeldSince = null;
      return KeyEventResult.ignored;
    }
    final down = event is KeyDownEvent;
    _restartOsdTimer();
    final s = _session;
    final live = s.isLive;

    if (_window != null &&
        (key == LogicalKeyboardKey.f11 || key == LogicalKeyboardKey.keyF)) {
      if (down) _toggleWindowFullscreen();
      return KeyEventResult.handled;
    }
    if (_panelVisible) return _onPanelKey(event);
    if (key == LogicalKeyboardKey.keyD && _canDetach) {
      if (down) unawaited(_detach());
      return KeyEventResult.handled;
    }
    // Escape leaves window fullscreen (and the OSD) before it means Back.
    if (key == LogicalKeyboardKey.escape && _windowFullscreen) {
      if (down) {
        _setWindowFullscreen(false);
        _hideOsd();
        _rebuild();
      }
      return KeyEventResult.handled;
    }

    final digit = _digitKeys[key];
    if (digit != null && live) {
      if (down && !_cardShown) s.digit(digit);
      return KeyEventResult.handled;
    }
    if (live && (_zapUpKeys.contains(key) || _zapDownKeys.contains(key))) {
      if (!_cardShown && _zapAllowed(event)) {
        _zapUpKeys.contains(key) ? s.zapNext() : s.zapPrevious();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.info) {
      if (down) _onInfo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.guide) {
      if (down) _openGuide();
      return KeyEventResult.handled;
    }
    if (key == menuKey) {
      if (down && !_cardShown) unawaited(_openOptions());
      return KeyEventResult.handled;
    }
    if (!live) {
      final media = _onMediaKey(event);
      if (media != null) return media;
    }
    if (selectKeys.contains(key) && s.enteringNumber) {
      if (down) s.commitNumber();
      return KeyEventResult.handled;
    }
    final direction = arrowDirection(key);
    // An OSD the mouse showed leaves focus on the player: keys act as if
    // it were hidden (arrows zap, OK focuses it). One opened by a key has
    // its focus on the way.
    if (_osdVisible && !(_osdByMouse && _rootNode.hasPrimaryFocus)) {
      if (!live && _seekBarNode.hasPrimaryFocus) {
        if (direction == TraversalDirection.left ||
            direction == TraversalDirection.right) {
          _seekKey(event, direction == TraversalDirection.left ? -1 : 1);
          return KeyEventResult.handled;
        }
        // Down from the full-width seek bar goes to the first button.
        if (direction == TraversalDirection.down) {
          if (down) _osdFirstNode.requestFocus();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    }
    if (!_rootNode.hasPrimaryFocus) return KeyEventResult.ignored;
    if (_cardShown) {
      // Focus fell back to the player while a card is up (it appeared
      // behind a dialog): the D-pad and OK go to the card.
      if (direction != null || selectKeys.contains(key)) {
        if (down) _cardNode?.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (selectKeys.contains(key)) {
      // Live: OK opens the channel panel; an OSD the mouse showed takes
      // the keyboard instead.
      if (down) live && !_osdVisible ? _openPanel() : _showOsd();
      return KeyEventResult.handled;
    }
    if (direction != null) {
      if (live) {
        if (direction == TraversalDirection.up && _zapAllowed(event)) {
          s.zapNext();
        } else if (direction == TraversalDirection.down && _zapAllowed(event)) {
          s.zapPrevious();
        } else if (down &&
            (direction == TraversalDirection.left ||
                direction == TraversalDirection.right)) {
          _showOsd();
        }
      } else if (direction == TraversalDirection.left ||
          direction == TraversalDirection.right) {
        _seekKey(event, direction == TraversalDirection.left ? -1 : 1);
        _showOsd(focus: _seekBarNode);
      } else if (down) {
        _showOsd();
      }
      return KeyEventResult.handled;
    }
    if (!live && key == LogicalKeyboardKey.space) {
      if (down) unawaited(_controller.togglePlayPause());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Keys while the channel panel is open. The D-pad and OK move and pick
  /// in it (the app's shortcuts), Back and Escape close it through
  /// [PopScope]; zapping, numbers, Info and Menu never reach the channel
  /// playing behind it. Page Up/Down page its columns.
  KeyEventResult _onPanelKey(KeyEvent event) {
    final key = event.logicalKey;
    final down = event is KeyDownEvent;
    final primary = FocusManager.instance.primaryFocus;
    if ((primary == _rootNode || primary is FocusScopeNode) &&
        (arrowDirection(key) != null || selectKeys.contains(key))) {
      // Focus has not reached a row yet (the panel is still reading its
      // lists): the D-pad and OK take it there.
      if (down) _panel.currentState?.focusIn();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.guide) {
      if (down) _openGuide();
      return KeyEventResult.handled;
    }
    if (_digitKeys.containsKey(key) ||
        key == LogicalKeyboardKey.channelUp ||
        key == LogicalKeyboardKey.channelDown ||
        key == LogicalKeyboardKey.info ||
        key == menuKey) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Key-downs always zap; held keys zap at the throttled rate.
  bool _zapAllowed(KeyEvent event) =>
      event is KeyDownEvent || KeyRepeatThrottle.instance.stepFor(event) > 0;

  KeyEventResult? _onMediaKey(KeyEvent event) {
    final key = event.logicalKey;
    final down = event is KeyDownEvent;
    if (key == LogicalKeyboardKey.mediaPlayPause) {
      if (down) unawaited(_controller.togglePlayPause());
    } else if (key == LogicalKeyboardKey.mediaPlay) {
      if (down) unawaited(_controller.resume());
    } else if (key == LogicalKeyboardKey.mediaPause) {
      if (down) unawaited(_controller.pause());
    } else if (key == LogicalKeyboardKey.mediaFastForward ||
        key == LogicalKeyboardKey.mediaRewind) {
      if (_cardShown) return KeyEventResult.handled;
      final dir = key == LogicalKeyboardKey.mediaRewind ? -1 : 1;
      _seekKey(event, dir, step: PlayerScreen.fastSeekStep);
      if (!_osdVisible) _showOsd(focus: _seekBarNode);
    } else {
      return null;
    }
    return KeyEventResult.handled;
  }

  /// One seek press: ±[step], times 3 after a 1 s hold and 6 after 3 s.
  void _seekKey(
    KeyEvent event,
    int direction, {
    Duration step = PlayerScreen.seekStep,
  }) {
    final now = _clock.now();
    var multiplier = 1;
    if (event is KeyRepeatEvent && _seekHeldSince != null) {
      final last = _lastSeekRepeat;
      if (last != null &&
          now.difference(last) < const Duration(milliseconds: 150)) {
        return;
      }
      final held = now.difference(_seekHeldSince!);
      multiplier = held >= const Duration(seconds: 3)
          ? 6
          : held >= const Duration(seconds: 1)
          ? 3
          : 1;
    } else {
      _seekHeldSince = now;
    }
    _lastSeekRepeat = now;
    final st = _controller.state.value;
    _seek.step(
      step * (multiplier * direction),
      current: st.position,
      duration: st.duration,
    );
  }

  void _onDoubleTap() {
    final fraction = _doubleTapFraction;
    if (fraction == null || _session.isLive || _cardShown) return;
    final st = _controller.state.value;
    _seek.step(
      fraction < 0.5 ? -PlayerScreen.seekStep : PlayerScreen.seekStep,
      current: st.position,
      duration: st.duration,
    );
    if (!_osdVisible) _showOsd(focus: _seekBarNode);
  }

  // ---------------------------------------------------------------------
  // Back, guide, info.

  void _handleBack() {
    if (_exiting) return;
    if (_session.cancelNumber()) return;
    if (_session.countdown != null) {
      _session.cancelNextEpisode();
      return;
    }
    if (_panelVisible) {
      _closePanel();
      return;
    }
    if (_osdVisible) {
      _hideOsd();
      return;
    }
    if (_statsVisible) {
      setState(() => _statsVisible = false);
      return;
    }
    _exit();
  }

  /// Leaves the player. Everything that could still reach the shared
  /// controller stops first: during the exit transition a new player may
  /// already be using it.
  void _exit() {
    final stopped = _beginExit();
    if (stopped == null) return;
    unawaited(stopped);
    Navigator.of(context).pop();
  }

  /// Everything of [_exit] but closing the route. Returns when the stream
  /// is stopped (its connection closed), or null when already exiting.
  Future<void>? _beginExit() {
    if (_exiting) return null;
    setState(() {
      _exiting = true;
      _panelVisible = false;
    });
    _session.close();
    _osdTimer?.cancel();
    _bannerTimer?.cancel();
    _panelTimer?.cancel();
    _seek.cancel();
    unawaited(_onlineSub?.cancel());
    _onlineSub = null;
    _releaseOrientation();
    _releaseFullscreen();
    _setWindowFullscreen(false);
    return _controller.stop();
  }

  /// Whether the channel can go to a window of its own: live, on desktop.
  bool get _canDetach => _window != null && _session.isLive && !_exiting;

  /// Plays the channel in a detached window ([DetachedWindows.detach]):
  /// the player stops its stream and closes first, and only then does the
  /// window open the same stream, so a one-connection account never has
  /// two open. A snack bar tells when the window could not be opened.
  Future<void> _detach() async {
    if (!_canDetach) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final log = ref.read(ringLogProvider);
    void failed() {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.playerDetachFailed)));
    }

    final s = _session;
    final stream = _controller.request;
    final source = s.source;
    // Nothing resolved to hand over yet (or a zap is still on its way).
    if (stream == null ||
        source == null ||
        s.error != null ||
        _controller.itemKey != s.itemKey.encode()) {
      failed();
      return;
    }
    final request = DetachRequest(
      sourceId: s.sourceId,
      channelKey: s.request.item.key,
      title: s.channel?.name ?? s.title ?? '',
      logo: s.channel?.logo,
      stream: stream,
      maxConnections: source.maxConnections,
      secrets: source.secrets,
      locale: Localizations.localeOf(context).languageCode == 'ar'
          ? 'ar'
          : 'en',
    );
    final windows = ref.read(detachedWindowsProvider.notifier);
    log.info('Player: detaching the channel');
    final stopped = _beginExit();
    if (stopped == null) return;
    await stopped;
    if (mounted) Navigator.of(context).pop();
    try {
      await windows.detach(request);
    } on Object catch (e) {
      log.warn('Player: the separate window failed: $e');
      failed();
    }
  }

  /// The Guide button and key: closes the player and shows the home
  /// shell's Guide tab ([PlayerGuideScope]). A channel opened from a pushed
  /// page (no shell around it) just closes the player.
  void _openGuide() {
    if (_exiting) return;
    final open = PlayerGuideScope.maybeOf(context);
    if (open == null && !_session.isLive) return;
    _exit();
    open?.call();
  }

  void _onInfo() {
    if (_cardShown) return;
    if (_osdVisible) _hideOsd();
    _showBanner(const Duration(seconds: 5));
  }

  // ---------------------------------------------------------------------
  // Actions.

  Future<T?> _dialog<T>(Future<T?> Function() show) async {
    _dialogs++;
    try {
      return await show();
    } finally {
      _dialogs--;
      _restartOsdTimer();
      _refocusCard();
    }
  }

  Future<void> _perform(PlayerAction action) async {
    switch (action) {
      case PlayerAction.channels:
        _openPanel();
      case PlayerAction.detach:
        await _detach();
      case PlayerAction.audio:
        await _pickAudio();
      case PlayerAction.subtitles:
        await _pickSubtitles();
      case PlayerAction.aspect:
        await _pickAspect();
      case PlayerAction.favorite:
        await _toggleFavorite();
      case PlayerAction.addToList:
        await _dialog<void>(
          () => showAddToListDialog(
            context,
            ref,
            sourceId: _session.sourceId,
            channelKey: _session.request.item.key,
          ),
        );
      case PlayerAction.switchPlayer:
        await _session.switchEngine();
      case PlayerAction.guide:
        _openGuide();
      case PlayerAction.stats:
        setState(() => _statsVisible = !_statsVisible);
    }
  }

  Future<void> _pickAudio() async {
    final l10n = AppLocalizations.of(context);
    final tracks = await _controller.audioTracks();
    if (!mounted) return;
    final id = await _dialog(
      () => showPlayerChoiceDialog<String>(
        context,
        title: l10n.playerAudio,
        choices: [
          for (final (i, t) in tracks.indexed)
            PlayerChoice(
              value: t.id,
              label: _trackName(l10n, t, i),
              selected: t.selected,
            ),
        ],
      ),
    );
    if (id != null) await _controller.selectAudio(id);
  }

  Future<void> _pickSubtitles() async {
    final l10n = AppLocalizations.of(context);
    if (_controller.engineKind == EngineKind.exo) {
      final switchPlayer = await _dialog(
        () => showSubtitlesNeedMpvDialog(context),
      );
      if (switchPlayer ?? false) await _session.switchEngine();
      return;
    }
    final tracks = await _controller.subtitleTracks();
    if (!mounted) return;
    const off = '\u0000off';
    final id = await _dialog(
      () => showPlayerChoiceDialog<String>(
        context,
        title: l10n.playerSubtitles,
        choices: [
          PlayerChoice(
            value: off,
            label: l10n.playerOff,
            selected: !tracks.any((t) => t.selected),
          ),
          for (final (i, t) in tracks.indexed)
            PlayerChoice(
              value: t.id,
              label: _trackName(l10n, t, i),
              selected: t.selected,
            ),
        ],
      ),
    );
    if (id == null) return;
    await _controller.selectSubtitle(id == off ? null : id);
  }

  String _trackName(AppLocalizations l10n, TrackInfo t, int index) {
    final parts = [?t.label, ?t.language, ?t.codec];
    return parts.isEmpty ? l10n.playerTrackN(index + 1) : parts.join(' · ');
  }

  Future<void> _pickAspect() async {
    final l10n = AppLocalizations.of(context);
    final current = _session.aspect;
    final mode = await _dialog(
      () => showPlayerChoiceDialog<AspectMode>(
        context,
        title: l10n.playerAspectRatio,
        choices: [
          for (final m in AspectMode.values)
            PlayerChoice(
              value: m,
              label: aspectLabel(l10n, m),
              selected: m == current,
            ),
        ],
      ),
    );
    if (mode != null) await _session.setAspect(mode);
  }

  Future<void> _toggleFavorite() async {
    await _session.toggleFavorite();
    if (mounted) _showFavoriteSnack(added: _session.favorite);
  }

  void _showFavoriteSnack({required bool added}) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            added ? l10n.player_favoriteAdded : l10n.player_favoriteRemoved,
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _openOptions() async {
    final l10n = AppLocalizations.of(context);
    final action = await _dialog(
      () => showPlayerChoiceDialog<PlayerAction>(
        context,
        title: l10n.player_options,
        choices: [
          for (final a in _actions())
            PlayerChoice(value: a, label: _label(l10n, a), icon: _icon(a)),
        ],
      ),
    );
    if (action != null && mounted) await _perform(action);
  }

  /// The OSD's buttons and the options list, in order.
  List<PlayerAction> _actions() => [
    if (_session.isLive) PlayerAction.channels,
    if (_canDetach) PlayerAction.detach,
    PlayerAction.audio,
    PlayerAction.subtitles,
    PlayerAction.aspect,
    if (_session.isLive) PlayerAction.favorite,
    if (_session.isLive) PlayerAction.addToList,
    PlayerAction.switchPlayer,
    if (_session.isLive) PlayerAction.guide,
    PlayerAction.stats,
  ];

  String _label(AppLocalizations l10n, PlayerAction a) => switch (a) {
    PlayerAction.channels => l10n.playerChannels,
    PlayerAction.detach => l10n.playerDetach,
    PlayerAction.audio => l10n.playerAudio,
    PlayerAction.subtitles => l10n.playerSubtitles,
    PlayerAction.aspect => l10n.playerAspectRatio,
    PlayerAction.favorite =>
      _session.favorite ? l10n.liveRemoveFavorite : l10n.liveAddFavorite,
    PlayerAction.addToList => l10n.liveAddToList,
    PlayerAction.switchPlayer => l10n.playerSwitchPlayer,
    PlayerAction.guide => l10n.playerGuide,
    PlayerAction.stats => l10n.playerStats,
  };

  IconData _icon(PlayerAction a) => switch (a) {
    PlayerAction.channels => Icons.list,
    PlayerAction.detach => Icons.open_in_new,
    PlayerAction.audio => Icons.audiotrack_outlined,
    PlayerAction.subtitles => Icons.subtitles_outlined,
    PlayerAction.aspect => Icons.aspect_ratio,
    PlayerAction.favorite => _session.favorite ? Icons.star : Icons.star_border,
    PlayerAction.addToList => Icons.playlist_add,
    PlayerAction.switchPlayer => Icons.swap_horiz,
    PlayerAction.guide => Icons.view_timeline_outlined,
    PlayerAction.stats => Icons.query_stats,
  };

  Future<void> _copyReport() async {
    final versionFuture = ref.read(appVersionProvider.future);
    String? version;
    try {
      version = await versionFuture.timeout(const Duration(seconds: 2));
    } on Object catch (_) {
      // The report works without it.
    }
    final report = await _session.buildReport(appVersion: version);
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).commonCopied),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  // ---------------------------------------------------------------------
  // Build.

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formFactor = FormFactorScope.of(context);
    final overscan = overscanPadding(formFactor);
    final s = _session;
    final failed = _failed;
    final resume = s.resumeOffer;
    final countdown = s.countdown;
    final next = s.nextEpisode;
    final topBar = formFactor != FormFactor.tv || _window != null;
    // The OSD's top bar (Back, fullscreen) stays clickable: the stats and
    // the number badge in its corners move below it while it shows.
    final belowTopBar = EdgeInsetsDirectional.only(
      top: _osdVisible && !_cardShown && topBar
          ? OsdIconButton.size + Spacing.lg + Spacing.sm
          : 0,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // Escape (desktop Back) goes through the PopScope too: the app maps
        // it to BackIntent, which AppFrame turns into maybePop. In window
        // fullscreen [_onKey] takes it first.
        body: Focus(
          focusNode: _rootNode,
          autofocus: true,
          // Arrows never move focus onto the invisible player itself
          // (from a card or the OSD); it is only focused on purpose.
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: _mouse(
            Stack(
              fit: StackFit.expand,
              children: [
                KeyedSubtree(
                  key: const ValueKey('player-video'),
                  // A closing player stops showing the shared engine's
                  // surface (the next player may already show it).
                  child: _exiting
                      ? const ColoredBox(
                          color: Colors.black,
                          child: SizedBox.expand(),
                        )
                      : _controller.buildView(aspect: s.aspect),
                ),
                Positioned.fill(child: _gestures()),
                if (!failed && resume == null)
                  ValueListenableBuilder<PlaybackState>(
                    valueListenable: _controller.state,
                    builder: (context, st, _) {
                      final phase = _controller.phase;
                      final buffering =
                          phase == PlaybackPhase.opening ||
                          (st.buffering && phase == PlaybackPhase.playing);
                      if (!buffering) return const SizedBox.shrink();
                      return const Center(
                        key: ValueKey('player-buffering'),
                        child: SizedBox.square(
                          dimension: 44,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      );
                    },
                  ),
                if (_bannerVisible &&
                    !_osdVisible &&
                    !_cardShown &&
                    !_panelVisible)
                  Align(
                    alignment: AlignmentDirectional.bottomCenter,
                    child: Padding(
                      padding: overscan + const EdgeInsets.all(Spacing.lg),
                      child: _banner(),
                    ),
                  ),
                if (_osdVisible && !_cardShown)
                  _osd(l10n, overscan, topBar: topBar),
                SafeArea(
                  minimum: overscan + const EdgeInsets.all(Spacing.lg),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: PlayerReconnectBanner(
                          status: _controller.reconnectStatus,
                        ),
                      ),
                      if (_statsVisible)
                        Align(
                          alignment: AlignmentDirectional.topStart,
                          child: Padding(
                            padding: belowTopBar,
                            child: PlayerStatsOverlay(
                              controller: _controller,
                              redactValue: _redact,
                            ),
                          ),
                        ),
                      if (s.isLive)
                        Align(
                          alignment: AlignmentDirectional.topEnd,
                          child: Padding(
                            padding: belowTopBar,
                            child: _numberBadge(),
                          ),
                        ),
                      if (countdown != null && next != null && !failed)
                        Align(
                          alignment: AlignmentDirectional.bottomEnd,
                          child: PlayerNextEpisodeCard(
                            seconds: countdown,
                            episode: next,
                            playNode: _nextNode,
                            onPlay: () => unawaited(s.playNextEpisode()),
                            onCancel: s.cancelNextEpisode,
                          ),
                        ),
                      if (resume != null && !failed)
                        Center(
                          child: PlayerResumePrompt(
                            title: s.title,
                            position: resume.position,
                            resumeNode: _resumeNode,
                            onResume: () =>
                                unawaited(s.chooseResume(resume: true)),
                            onStartOver: () =>
                                unawaited(s.chooseResume(resume: false)),
                          ),
                        ),
                      if (failed)
                        Center(
                          child: PlayerFailureCard(
                            message: l10n.playerPlaybackFailed,
                            details: s.error != null
                                ? l10n.player_itemUnavailable
                                : _redact(_controller.errorMessage ?? ''),
                            retryNode: _retryNode,
                            onRetry: () => unawaited(s.retry()),
                            onTryOtherFormat: s.canTryOtherFormat
                                ? () => unawaited(s.tryOtherFormat())
                                : null,
                            onCopyReport: () => unawaited(_copyReport()),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_panelVisible)
                  Positioned.fill(
                    child: ChannelPanel(
                      key: _panel,
                      sourceId: s.sourceId,
                      list: _panelList(),
                      playingKey: s.request.item.key,
                      onTune: (source, entry) =>
                          unawaited(_tuneFromPanel(source, entry)),
                      onClose: _closePanel,
                      onChannelMenu: (entry, favorite) =>
                          unawaited(_panelChannelMenu(entry, favorite)),
                      onActivity: _restartPanelTimer,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Desktop: the mouse shows the OSD; the cursor hides while the OSD and
  /// cards are away.
  Widget _mouse(Widget child) {
    if (_window == null) return child;
    return MouseRegion(
      key: const ValueKey('player-mouse'),
      cursor: _osdVisible || _cardShown || _panelVisible || _exiting
          ? MouseCursor.defer
          : SystemMouseCursors.none,
      onHover: (_) => _onMouseMoved(),
      child: child,
    );
  }

  /// Engine errors and stats on screen: source secrets masked and no URL
  /// path at all ([hideUrlPaths]).
  String _redact(String value) =>
      hideUrlPaths(_session.source?.redactText(value) ?? redact(value));

  Widget _gestures() {
    // Desktop double clicks toggle fullscreen instead of seeking.
    final desktop = _window != null;
    final vod = !_session.isLive && !desktop;
    return LayoutBuilder(
      builder: (context, c) => GestureDetector(
        key: const ValueKey('player-gestures'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!_cardShown) _toggleOsd();
        },
        onDoubleTapDown: vod
            ? (d) => _doubleTapFraction = c.maxWidth <= 0
                  ? null
                  : d.localPosition.dx / c.maxWidth
            : null,
        onDoubleTap: desktop
            ? _toggleWindowFullscreen
            : vod
            ? _onDoubleTap
            : null,
      ),
    );
  }

  /// The live channel banner (zap target or current channel), or the VOD
  /// title.
  Widget _banner() {
    final s = _session;
    if (!s.isLive) {
      final title = s.title;
      if (title == null) return const SizedBox.shrink();
      return PlayerPanel(
        key: const ValueKey('player-banner'),
        child: BidiText(title, style: Theme.of(context).textTheme.titleLarge),
      );
    }
    final preview = s.zapPreview;
    if (preview == null) return _channelBanner(null, -1);
    return ValueListenableBuilder<ZapView>(
      valueListenable: preview,
      builder: (context, p, _) => _channelBanner(
        p.item,
        p.index,
        // The target's page is still being read: no name yet.
        loading: p.pending && p.item == null && p.digits.isEmpty,
      ),
    );
  }

  Widget _channelBanner(ZapEntry? entry, int index, {bool loading = false}) {
    final s = _session;
    if (loading) {
      return PlayerPanel(
        key: const ValueKey('player-banner'),
        maxWidth: 720,
        child: ChannelInfoRow(
          name: '',
          number: s.positionNumber(index),
          now: _clock.now(),
        ),
      );
    }
    final key = entry?.key ?? s.request.item.key;
    final current = key == s.request.item.key;
    final row = current ? (s.channel ?? s.channelFor(key)) : s.channelFor(key);
    final name = row?.name ?? (current ? s.title : null) ?? '';
    return PlayerPanel(
      key: const ValueKey('player-banner'),
      maxWidth: 720,
      child: ChannelInfoRow(
        name: name,
        number: row?.num ?? entry?.num ?? s.positionNumber(index),
        logo: row?.logo,
        nowNext: current ? s.nowNext : s.nowNextFor(key),
        now: _clock.now(),
        favorite: current && s.favorite,
      ),
    );
  }

  Widget _numberBadge() {
    final preview = _session.zapPreview;
    if (preview == null) return const SizedBox.shrink();
    return ValueListenableBuilder<ZapView>(
      valueListenable: preview,
      builder: (context, p, _) {
        if (p.digits.isEmpty) return const SizedBox.shrink();
        final item = p.item;
        final matched = item != null && _session.numberMatches(p);
        return PlayerNumberBadge(
          digits: p.digits,
          searching: p.searching,
          channelName: matched
              ? _session.channelFor(item.key)?.name ?? ''
              : null,
        );
      },
    );
  }

  /// The OSD; [topBar] adds Back (and on desktop the fullscreen button) for
  /// mouse and touch.
  Widget _osd(
    AppLocalizations l10n,
    EdgeInsets overscan, {
    required bool topBar,
  }) {
    final s = _session;
    final actions = _actions();
    final count = actions.length + (s.isLive ? 0 : 1);

    /// The row's buttons, [width] wide each.
    List<Widget> buttons(double width) {
      var first = true;
      FocusNode? firstNode() {
        if (!first) return null;
        first = false;
        return _osdFirstNode;
      }

      // Taken before the builder below runs (later, on every play/pause).
      final playNode = s.isLive ? null : firstNode();
      return [
        if (!s.isLive)
          ValueListenableBuilder<bool>(
            valueListenable: _playing,
            builder: (context, playing, _) => OsdButton(
              key: const ValueKey('player-osd-playPause'),
              focusNode: playNode,
              icon: playing ? Icons.pause : Icons.play_arrow,
              label: playing ? l10n.player_pause : l10n.vodPlay,
              width: width,
              onFocus: _restartOsdTimer,
              onSelect: () => unawaited(_controller.togglePlayPause()),
            ),
          ),
        for (final a in actions)
          OsdButton(
            key: ValueKey('player-osd-${a.name}'),
            focusNode: firstNode(),
            icon: _icon(a),
            label: _label(l10n, a),
            width: width,
            active: switch (a) {
              PlayerAction.favorite => s.favorite,
              PlayerAction.stats => _statsVisible,
              _ => false,
            },
            onFocus: _restartOsdTimer,
            onSelect: () => unawaited(_perform(a)),
          ),
      ];
    }

    final theme = Theme.of(context);
    final episode = s.episode;
    return Positioned.fill(
      key: const ValueKey('player-osd'),
      child: Column(
        children: [
          if (!s.isLive || topBar)
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCC000000), Color(0x00000000)],
                ),
              ),
              padding: overscan + const EdgeInsets.all(Spacing.lg),
              child: Row(
                children: [
                  if (topBar) ...[
                    OsdIconButton(
                      key: const ValueKey('player-osd-back'),
                      icon: Icons.arrow_back,
                      label: l10n.commonBack,
                      onFocus: _restartOsdTimer,
                      onSelect: _exit,
                    ),
                    const SizedBox(width: Spacing.md),
                  ],
                  Expanded(
                    child: s.isLive
                        ? const SizedBox.shrink()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              BidiText(
                                s.title ?? '',
                                style: theme.textTheme.titleLarge,
                              ),
                              if (episode != null)
                                Text(
                                  l10n.player_episodeLabel(
                                    episode.season,
                                    episode.number,
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                  ),
                  if (_window != null) ...[
                    const SizedBox(width: Spacing.md),
                    OsdIconButton(
                      key: const ValueKey('player-osd-fullscreen'),
                      icon: _windowFullscreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                      label: _windowFullscreen
                          ? l10n.playerExitFullscreen
                          : l10n.playerFullscreen,
                      onFocus: _restartOsdTimer,
                      onSelect: _toggleWindowFullscreen,
                    ),
                  ],
                ],
              ),
            ),
          const Spacer(),
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xE6000000), Color(0x00000000)],
              ),
            ),
            padding: overscan + const EdgeInsets.all(Spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (s.isLive)
                  ChannelInfoRow(
                    name: s.channel?.name ?? s.title ?? '',
                    number:
                        s.channel?.num ??
                        s.positionNumber(s.zapPreview?.value.index ?? -1),
                    logo: s.channel?.logo,
                    nowNext: s.nowNext,
                    now: _clock.now(),
                    favorite: s.favorite,
                  )
                else
                  ValueListenableBuilder<PlaybackState>(
                    valueListenable: _controller.state,
                    builder: (context, st, _) => PlayerSeekBar(
                      focusNode: _seekBarNode,
                      position: st.position,
                      duration: st.duration,
                      target: _seek.target,
                      onFocus: _restartOsdTimer,
                      onSeekTo: (t) {
                        _restartOsdTimer();
                        _seek.jumpTo(t);
                      },
                    ),
                  ),
                const SizedBox(height: Spacing.md),
                // The buttons share the row (narrower down to a limit), so
                // all of them show on TV and phones.
                LayoutBuilder(
                  builder: (context, c) {
                    final width = (c.maxWidth / count - 2 * Spacing.xs).clamp(
                      OsdButton.minWidth,
                      OsdButton.defaultWidth,
                    );
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: buttons(width)),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
