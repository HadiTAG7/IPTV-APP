import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/time/clock.dart';
import '../../sources/models.dart';
import '../engine/engine_factory.dart';
import '../engine/engine_policy.dart';
import '../engine/player_engine.dart';
import 'connection_guard.dart';
import 'progress_saver.dart';
import 'reconnect_watchdog.dart';

/// Coarse lifecycle of the current item, for the player UI.
enum PlaybackPhase {
  idle,

  /// Opening (or falling back) until the first frame.
  opening,
  playing,

  /// A movie or episode reached its end.
  ended,

  /// Every engine failed or reconnecting gave up; see
  /// [PlaybackController.errorMessage].
  failed,
}

/// Saves the engine that worked for a channel (`channel_prefs.engine`).
typedef EnginePreferenceCallback = void Function(
  String channelKey,
  EngineKind kind,
);

/// Persists VOD progress for [itemKey].
typedef ItemProgressCallback = Future<void> Function(
  String itemKey,
  Duration position,
  Duration duration,
);

class _Session {
  _Session({
    required this.original,
    required this.itemKey,
    required this.maxConnections,
    required this.channelPref,
  }) : request = original;

  final StreamRequest original;

  /// What is opened now (the HLS hint may have been added).
  StreamRequest request;
  final String? itemKey;
  final int? maxConnections;

  /// The engine this item prefers. A manual switch or the silent-audio
  /// switch updates it, so [PlaybackController.retry] keeps that choice.
  EngineKind? channelPref;

  /// Engines tried since the last successful start or manual switch.
  Set<EngineKind> tried = {};
  bool hlsRetried = false;

  /// A first frame was seen; later errors go to the reconnect watchdog.
  bool everPlayed = false;

  /// A first frame was seen since the last open. Only errors before it can
  /// be a refused (held) connection.
  bool framedSinceOpen = false;
  bool silentChecked = false;

  /// The silent-audio check came due in the background; run it on return.
  bool silentPending = false;

  /// Engines left because they played without sound; automatic switches
  /// never go back to them.
  final silentEngines = <EngineKind>{};

  /// The mid-stream TLS switch to Exo happens at most once per item.
  bool tlsSwitched = false;
  bool userPaused = false;
  bool backgrounded = false;
  bool resumeOnForeground = false;
  Duration lastPosition = Duration.zero;

  /// Where the last early end ([PlaybackController._endedEarly]) happened.
  Duration? earlyEndAt;

  bool get isLive => original.isLive;
}

/// Orchestrates one playback session for the UI: engine choice and fallback,
/// connection hygiene, reconnecting, VOD progress and app lifecycle.
///
/// Owns at most one [PlayerEngine]; switching engine kinds disposes the old
/// engine before the factory creates the new one.
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required this._factory,
    required this._policyInput,
    this._policy = const EnginePolicy(),
    this._clock = const SystemClock(),
    this.onEnginePreferenceLearned,
    this.onProgress,
    this.onWakelockChanged,
    ConnectionGuard? guard,
    List<Duration> reconnectBackoff = kReconnectBackoff,
    this.silentAudioCheckDelay = const Duration(seconds: 2),
    this.progressInterval = const Duration(seconds: 10),
  }) : _guard = guard ?? ConnectionGuard(clock: _clock) {
    _watchdog = ReconnectWatchdog(
      reconnect: _reconnect,
      onGiveUp: _onGiveUp,
      clock: _clock,
      backoff: reconnectBackoff,
    );
  }

  final EngineFactory _factory;
  final EnginePolicyInput Function() _policyInput;
  final EnginePolicy _policy;
  final Clock _clock;
  final ConnectionGuard _guard;
  late final ReconnectWatchdog _watchdog;

  final EnginePreferenceCallback? onEnginePreferenceLearned;
  final ItemProgressCallback? onProgress;

  /// Called with true while something is playing or loading, false otherwise.
  final ValueChanged<bool>? onWakelockChanged;
  final Duration silentAudioCheckDelay;
  final Duration progressInterval;

  final _state = ValueNotifier<PlaybackState>(PlaybackState.idle);
  final _events = StreamController<EngineEvent>.broadcast();

  PlayerEngine? _engine;
  StreamSubscription<EngineEvent>? _engineSub;
  _Session? _session;
  _Session? _lastSession;
  ProgressSaver? _progress;
  Timer? _silentTimer;
  PlaybackPhase _phase = PlaybackPhase.idle;
  String? _error;
  DateTime? _openStartedAt;
  Duration? _ttff;
  bool _online = true;
  bool _wakelock = false;
  bool _disposed = false;

  /// Completes once the controller is disposed and its engine is gone (its
  /// dispose done), and the stream with it ([gone]).
  final _gone = Completer<void>();
  double _volume = 1;
  bool _muted = false;

  /// The cache size [setLite] chose; null leaves engines as created.
  bool? _lite;

  /// The app is in the background ([onBackground] .. [onForeground]), with
  /// or without a session: items started meanwhile start backgrounded.
  bool _appBackground = false;

  /// Mirrors the current engine's state.
  ValueListenable<PlaybackState> get state => _state;

  /// Engine events of the current engine.
  Stream<EngineEvent> get events => _events.stream;
  ValueListenable<ReconnectStatus> get reconnectStatus => _watchdog.status;
  PlaybackPhase get phase => _phase;

  /// Redacted reason when [phase] is [PlaybackPhase.failed].
  String? get errorMessage => _error;
  PlayerEngine? get engine => _engine;
  EngineKind? get engineKind => _engine?.kind;

  /// The request being played (with any HLS hint the fallback added).
  StreamRequest? get request => _session?.request;
  String? get itemKey => _session?.itemKey;

  /// Time from the last open to its first frame.
  Duration? get timeToFirstFrame => _ttff;

  /// Starts [request], stopping whatever played before (latest call wins).
  ///
  /// [itemKey] identifies the channel or title for learned engine
  /// preferences and progress. [maxConnections] of 1 adds a gap between
  /// closing and opening. [channelPref] overrides the policy's channel
  /// preference.
  Future<void> play(
    StreamRequest request, {
    String? itemKey,
    int? maxConnections,
    EngineKind? channelPref,
  }) async {
    if (_disposed) return;
    _endSession();
    final s = _Session(
      original: request,
      itemKey: itemKey,
      maxConnections: maxConnections,
      channelPref: channelPref,
    );
    // Started in the background (a zap or the next episode that came due
    // there): live waits for onForeground, VOD opens paused.
    if (_appBackground) {
      s
        ..backgrounded = true
        ..resumeOnForeground = true;
    }
    _session = s;
    _lastSession = s;
    final kind = _policy.pick(request.kind, _input(s));
    s.tried.add(kind);
    _error = null;
    _setPhase(PlaybackPhase.opening);
    _restartWatchdog(s);
    final onProgress = this.onProgress;
    if (!request.isLive && itemKey != null && onProgress != null) {
      _progress = ProgressSaver(
        save: (p, d) => onProgress(itemKey, p, d),
        interval: progressInterval,
      )..start();
    }
    await _open(s, kind, s.request);
  }

  /// Plays the current item with the other engine and remembers that choice
  /// for the channel. No-op where only one engine exists.
  Future<void> switchEngine() async {
    final s = _session;
    final engine = _engine;
    if (s == null || engine == null || _disposed) return;
    final target = _policy.fallbackFor(engine.kind, _input(s));
    if (target == null) return;
    final key = s.itemKey;
    if (key != null) onEnginePreferenceLearned?.call(key, target);
    s
      ..channelPref = target
      ..silentEngines.remove(target);
    await _switchEngine(s, target);
  }

  /// Stops playback, saves progress and closes the connection. The engine
  /// instance is kept for the next [play]. Completes once the stream is
  /// stopped: its stop has run (after an open still running), or the
  /// controller was disposed meanwhile (the engine went, and the stream
  /// with it).
  Future<void> stop() async {
    if (_disposed) return;
    _endSession();
    _session = null;
    _setPhase(PlaybackPhase.idle);
    await Future.any([_guard.stop(() async => _engine?.stop()), _gone.future]);
    // Disposed meanwhile: the guard's stop found no engine to stop, and the
    // stream goes with the engine's dispose.
    if (_disposed) return _gone.future;
    _state.value = PlaybackState.idle;
    _setWakelock(false);
  }

  /// Replays the last item from scratch (after a failure or give-up).
  Future<void> retry() async {
    final s = _session ?? _lastSession;
    if (s == null || _disposed) return;
    final resumeAt = !s.isLive && s.lastPosition > Duration.zero
        ? s.lastPosition
        : s.original.startAt;
    await play(
      s.original.copyWith(startAt: resumeAt),
      itemKey: s.itemKey,
      maxConnections: s.maxConnections,
      channelPref: s.channelPref,
    );
  }

  /// Whether the current item is meant to be playing: what Play/Pause
  /// toggles and shows. Unlike `state.playing` it stays true while
  /// ExoPlayer rebuffers. Listeners hear when the user pauses or resumes;
  /// otherwise it changes with [phase] and [state].
  bool get playIntended {
    final s = _session;
    return s == null ? _state.value.playing : _meantToPlay(s);
  }

  /// Pauses what is meant to be playing (also while it rebuffers), else
  /// resumes.
  Future<void> togglePlayPause() async {
    if (playIntended) {
      await pause();
    } else {
      await resume();
    }
  }

  /// Whether [s] is meant to be playing: opening, or started and not paused
  /// by the user, with the engine playing or buffering. ExoPlayer reports
  /// `playing` false while it rebuffers, which is no pause.
  bool _meantToPlay(_Session s) {
    if (s.userPaused) return false;
    final state = _state.value;
    return switch (_phase) {
      PlaybackPhase.opening => true,
      PlaybackPhase.playing => state.playing || state.buffering,
      _ => false,
    };
  }

  Future<void> pause() async {
    _setUserPaused(true);
    await _engine?.pause();
  }

  Future<void> resume() async {
    _setUserPaused(false);
    _rearmAfterEnd();
    await _engine?.play();
  }

  void _setUserPaused(bool paused) {
    final s = _session;
    if (s == null || s.userPaused == paused) return;
    s.userPaused = paused;
    if (!_disposed) notifyListeners();
  }

  Future<void> seek(Duration position) async {
    _rearmAfterEnd();
    await _engine?.seek(position);
  }

  Future<List<TrackInfo>> audioTracks() async =>
      await _engine?.audioTracks() ?? const [];

  Future<void> selectAudio(String id) async => _engine?.selectAudio(id);

  Future<List<TrackInfo>> subtitleTracks() async =>
      await _engine?.subtitleTracks() ?? const [];

  Future<void> selectSubtitle(String? id) async => _engine?.selectSubtitle(id);

  /// Completes once this controller is disposed and its engine is gone:
  /// its stream is closed then, even when a stop of it was superseded (a
  /// newer stop, or the dispose itself, takes over from an older one).
  Future<void> get gone => _gone.future;

  /// Volume (0 to 1) and mute, kept for later engines too; untouched they
  /// stay at the engines' defaults (full, unmuted).
  double get volume => _volume;
  bool get muted => _muted;

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _engine?.setVolume(_volume);
  }

  Future<void> setMuted(bool muted) async {
    _muted = muted;
    await _engine?.setMuted(muted);
  }

  /// The Lite (smaller) or normal cache for this engine and later ones
  /// ([PlayerEngine.setLite]); untouched, engines keep the size they were
  /// created with.
  bool? get lite => _lite;

  Future<void> setLite(bool lite) async {
    _lite = lite;
    await _engine?.setLite(lite);
  }

  /// Engine stats plus session timing for the stats overlay.
  Future<Map<String, String>> stats() async {
    final base = await _engine?.stats() ?? const <String, String>{};
    final ttff = _ttff;
    return {
      ...base,
      if (ttff != null) 'ttff': '${ttff.inMilliseconds} ms',
      'reconnects': '${_watchdog.attempts}',
    };
  }

  /// The current engine's video surface (black before the first play).
  Widget buildView({AspectMode aspect = AspectMode.fit}) =>
      _engine?.buildView(aspect: aspect) ??
      const ColoredBox(color: Color(0xFF000000), child: SizedBox.expand());

  /// Network availability (connectivity_plus). Offline pauses reconnecting.
  void setOnline(bool online) {
    _online = online;
    _syncWatchdogPause();
  }

  /// App went to the background: live is stopped to free the connection,
  /// VOD is paused and its position saved. Nothing reopened meanwhile (by a
  /// fallback or reconnect) or started by [play] meanwhile plays until
  /// [onForeground].
  Future<void> onBackground() async {
    if (_disposed) return;
    _appBackground = true;
    final s = _session;
    if (s == null || s.backgrounded) return;
    s.backgrounded = true;
    _syncWatchdogPause();
    _setWakelock(false);
    if (s.isLive) {
      s.resumeOnForeground = _phase != PlaybackPhase.failed;
      _cancelSilentCheck();
      await _guard.stop(() async => _engine?.stop());
    } else {
      s.resumeOnForeground = _meantToPlay(s);
      if (_silentTimer != null) {
        _cancelSilentCheck();
        s.silentPending = true;
      }
      await _engine?.pause();
      await _progress?.flush();
    }
  }

  /// Back in the foreground: reopens live, resumes VOD if it was playing.
  Future<void> onForeground() async {
    if (_disposed) return;
    _appBackground = false;
    final s = _session;
    if (s == null || !s.backgrounded) return;
    s.backgrounded = false;
    if (s.isLive) {
      if (!s.resumeOnForeground) return;
      _setPhase(PlaybackPhase.opening);
      _restartWatchdog(s);
      final kind = _engine?.kind ?? _policy.pick(s.original.kind, _input(s));
      // A fallback skipped in the background must not use up that engine.
      s.tried = {kind};
      await _open(s, kind, s.request);
    } else {
      _syncWatchdogPause();
      if (s.resumeOnForeground) await _engine?.play();
      final engine = _engine;
      if (s.silentPending && engine != null && _isCurrent(s)) {
        s.silentPending = false;
        _scheduleSilentCheck(s, engine);
      }
    }
  }

  // ---------------------------------------------------------------------

  EnginePolicyInput _input(_Session s) {
    final input = _policyInput();
    final pref = s.channelPref;
    return pref == null ? input : input.copyWith(channelPref: pref);
  }

  /// Ends the previous item: saves progress and cancels its timers. The
  /// stream itself is closed by the next switch (or [stop]).
  void _endSession() {
    _cancelSilentCheck();
    _watchdog.cancel();
    final saver = _progress;
    _progress = null;
    if (saver != null) unawaited(saver.stop());
  }

  void _restartWatchdog(_Session s) {
    _watchdog.watch(isLive: s.isLive);
    _syncWatchdogPause();
  }

  void _syncWatchdogPause() {
    final backgrounded = _session?.backgrounded ?? false;
    if (_online && !backgrounded) {
      _watchdog.resume();
    } else {
      _watchdog.pause();
    }
  }

  /// Seeking or playing again after the end resumes normal monitoring.
  void _rearmAfterEnd() {
    final s = _session;
    if (s == null || _phase != PlaybackPhase.ended) return;
    _setPhase(PlaybackPhase.playing);
    _restartWatchdog(s);
  }

  StreamRequest _resumeRequest(_Session s) {
    if (s.isLive || s.lastPosition <= Duration.zero) return s.request;
    return s.request.copyWith(startAt: s.lastPosition);
  }

  bool _isCurrent(_Session s) => identical(_session, s) && !_disposed;

  /// VOD the user paused or left in the background stays paused across
  /// reopens (fallbacks, reconnects, engine switches).
  bool _holdPaused(_Session s) => !s.isLive && (s.backgrounded || s.userPaused);

  Future<void> _open(_Session s, EngineKind kind, StreamRequest request) async {
    _cancelSilentCheck();
    await _guard.switchTo(
      stop: () async => _engine?.stop(),
      open: () async {
        if (!_isCurrent(s)) return;
        // Live stays closed in the background; onForeground reopens it.
        if (s.isLive && s.backgrounded) return;
        final engine = await _ensureEngine(kind);
        if (engine == null || !_isCurrent(s)) return;
        _openStartedAt = _clock.now();
        _ttff = null;
        s.framedSinceOpen = false;
        await engine.open(request);
        if (_isCurrent(s) && identical(_engine, engine) && _holdPaused(s)) {
          await engine.pause();
        }
      },
      maxConnections: s.maxConnections,
    );
  }

  Future<void> _switchEngine(_Session s, EngineKind kind) async {
    s.tried = {kind};
    s.everPlayed = false;
    _setPhase(PlaybackPhase.opening);
    _restartWatchdog(s);
    await _open(s, kind, _resumeRequest(s));
  }

  /// The engine of [kind], replacing (and disposing) another kind first.
  /// Null when the controller was disposed meanwhile.
  Future<PlayerEngine?> _ensureEngine(EngineKind kind) async {
    final current = _engine;
    if (current != null && current.kind == kind) return current;
    if (current != null) {
      _detach(current);
      _engine = null;
      await current.dispose();
      // dispose() may have run meanwhile and seen no engine to dispose.
      if (_disposed) return null;
      if (_engine != null) return _ensureEngine(kind);
    }
    final engine = _factory(kind);
    _engine = engine;
    engine.state.addListener(_onEngineState);
    _engineSub = engine.events.listen((e) => _onEngineEvent(engine, e));
    if (_volume != 1) unawaited(engine.setVolume(_volume));
    if (_muted) unawaited(engine.setMuted(true));
    final lite = _lite;
    if (lite != null) unawaited(engine.setLite(lite));
    if (!_disposed) {
      _state.value = engine.state.value;
      notifyListeners();
    }
    return engine;
  }

  void _detach(PlayerEngine engine) {
    engine.state.removeListener(_onEngineState);
    unawaited(_engineSub?.cancel());
    _engineSub = null;
  }

  void _onEngineState() {
    final engine = _engine;
    if (engine == null || _disposed) return;
    final st = engine.state.value;
    _state.value = st;
    final s = _session;
    if (s == null) return;
    if (!s.isLive && st.position > Duration.zero) s.lastPosition = st.position;
    _watchdog.onState(st);
    _progress?.update(st);
    if (!s.backgrounded) _setWakelock(st.playing || st.buffering);
  }

  void _onEngineEvent(PlayerEngine engine, EngineEvent e) {
    if (!identical(engine, _engine) || _disposed) return;
    final s = _session;
    if (s == null) return;
    _events.add(e);
    switch (e) {
      case FirstFrameEvent():
        _onFirstFrame(s, engine, e);
      case ErrorEvent():
        _onError(s, engine, e);
      case EndedEvent():
        _onEnded(s, e);
    }
  }

  void _onFirstFrame(_Session s, PlayerEngine engine, FirstFrameEvent e) {
    s.everPlayed = true;
    s.framedSinceOpen = true;
    s.tried = {engine.kind};
    final started = _openStartedAt;
    if (started != null) _ttff = _clock.now().difference(started);
    _setPhase(PlaybackPhase.playing);
    _watchdog.onEvent(e);
    if (_holdPaused(s)) unawaited(engine.pause());
    if (engine.kind == EngineKind.exo && !s.silentChecked) {
      s.silentChecked = true;
      if (s.backgrounded) {
        s.silentPending = true;
      } else {
        _scheduleSilentCheck(s, engine);
      }
    }
  }

  void _scheduleSilentCheck(_Session s, PlayerEngine engine) {
    _cancelSilentCheck();
    _silentTimer = Timer(silentAudioCheckDelay, () {
      _silentTimer = null;
      unawaited(_checkSilentAudio(s, engine));
    });
  }

  /// ExoPlayer skips audio formats it cannot decode (AC3/MP2 on many boxes):
  /// tracks exist but none is selected. mpv decodes them in software.
  /// Never runs in the background: the switch would start mpv playing there.
  Future<void> _checkSilentAudio(_Session s, PlayerEngine engine) async {
    bool current() => _isCurrent(s) && identical(_engine, engine);
    if (!current()) return;
    if (s.backgrounded) {
      s.silentPending = true;
      return;
    }
    final tracks = await engine.audioTracks();
    if (!current()) return;
    if (s.backgrounded) {
      s.silentPending = true;
      return;
    }
    if (tracks.isEmpty || tracks.any((t) => t.selected)) return;
    final target = _policy.fallbackFor(EngineKind.exo, _input(s));
    if (target != EngineKind.mpv) return;
    final key = s.itemKey;
    if (key != null) onEnginePreferenceLearned?.call(key, EngineKind.mpv);
    s
      ..channelPref = EngineKind.mpv
      ..silentEngines.add(EngineKind.exo);
    await _switchEngine(s, EngineKind.mpv);
  }

  void _onError(_Session s, PlayerEngine engine, ErrorEvent e) {
    if (!e.fatal) return;
    if (!s.framedSinceOpen && _guard.handleError(e)) return;
    final kind = engine.kind;
    if (!s.everPlayed) {
      if (kind == EngineKind.exo &&
          !s.hlsRetried &&
          !s.request.isHls &&
          !hasKnownMediaExtension(s.request.url)) {
        s.hlsRetried = true;
        s.request = s.request.copyWith(isHls: true);
        unawaited(_open(s, EngineKind.exo, s.request));
        return;
      }
      final fallback = _policy.fallbackFor(kind, _input(s));
      if (fallback != null && !s.tried.contains(fallback)) {
        s.tried.add(fallback);
        unawaited(_open(s, fallback, _resumeRequest(s)));
        return;
      }
      _fail(s, e.message);
      return;
    }
    // Once per item, and never back to a silent Exo: otherwise an Exo that
    // cannot open and an mpv that keeps hitting TLS errors ping-pong forever
    // outside the watchdog's attempt count.
    if (kind == EngineKind.mpv &&
        !s.tlsSwitched &&
        !s.silentEngines.contains(EngineKind.exo) &&
        looksLikeTlsError(e.message) &&
        _policy.fallbackFor(kind, _input(s)) == EngineKind.exo) {
      s.tlsSwitched = true;
      unawaited(_switchEngine(s, EngineKind.exo));
      return;
    }
    _watchdog.onEvent(e);
  }

  void _onEnded(_Session s, EndedEvent e) {
    if (s.isLive) {
      _watchdog.onEvent(e);
      return;
    }
    if (_endedEarly(s)) {
      // A dropped connection the engine took for the end of the file (mpv
      // after ffmpeg's own reconnects give up): reopen at the last position
      // instead of ending, auto-playing the next episode or restarting.
      s.earlyEndAt = s.lastPosition;
      _watchdog.report(ReconnectReason.ended);
      return;
    }
    _watchdog.cancel();
    _setPhase(PlaybackPhase.ended);
    final progress = _progress;
    if (progress != null) unawaited(progress.flush());
  }

  /// Gap of playback after a reopen that makes another early end count as
  /// a new drop. Ending again sooner (a file whose duration is wrong) is
  /// the real end.
  static const _earlyEndProgress = Duration(seconds: 5);

  /// Whether a VOD end came well before the known duration (not even
  /// [ProgressSaver.isFinished]). Unknown durations end normally.
  bool _endedEarly(_Session s) {
    final duration = _state.value.duration;
    final at = s.lastPosition;
    if (duration <= Duration.zero || at <= Duration.zero) return false;
    if (ProgressSaver.isFinished(at, duration)) return false;
    final previous = s.earlyEndAt;
    return previous == null || at - previous >= _earlyEndProgress;
  }

  Future<void> _reconnect(int attempt) async {
    final s = _session;
    final engine = _engine;
    if (s == null || _disposed) return;
    final kind = engine?.kind ?? _policy.pick(s.original.kind, _input(s));
    await _open(s, kind, _resumeRequest(s));
  }

  void _onGiveUp() {
    final s = _session;
    if (s == null) return;
    _fail(
      s,
      'Stream lost: gave up after ${_watchdog.attempts} attempts',
      keepReconnectStatus: true,
    );
  }

  void _fail(_Session s, String message, {bool keepReconnectStatus = false}) {
    if (!identical(_session, s)) return;
    _cancelSilentCheck();
    // After a give-up the watchdog already stopped and shows its status.
    if (!keepReconnectStatus) _watchdog.cancel();
    _error = message;
    _setPhase(PlaybackPhase.failed);
    _setWakelock(false);
    unawaited(_guard.stop(() async => _engine?.stop()));
  }

  void _cancelSilentCheck() {
    _silentTimer?.cancel();
    _silentTimer = null;
  }

  void _setPhase(PlaybackPhase phase) {
    if (_phase == phase || _disposed) return;
    _phase = phase;
    notifyListeners();
  }

  void _setWakelock(bool on) {
    if (_wakelock == on) return;
    _wakelock = on;
    onWakelockChanged?.call(on);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _endSession();
    _disposed = true;
    _session = null;
    _watchdog.dispose();
    _guard.dispose();
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      _detach(engine);
      // The stream is gone once the engine is: its dispose stops it, after
      // an open still running (mpv runs both under one lock).
      unawaited(engine.dispose().whenComplete(_gone.complete));
    } else {
      _gone.complete();
    }
    _setWakelock(false);
    unawaited(_events.close());
    _state.dispose();
    super.dispose();
  }
}
