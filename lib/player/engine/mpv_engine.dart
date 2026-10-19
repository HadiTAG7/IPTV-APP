import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/net/http.dart' show kDefaultUserAgent;
import '../../core/net/redact.dart';
import '../../sources/models.dart';
import 'engine_policy.dart';
import 'player_engine.dart';

/// Audio and subtitle languages mpv prefers by default.
const kDefaultPreferredLanguages = ['ara', 'ar', 'en'];

const _mib = 1024 * 1024;

/// Errors after which mpv has given up on the file.
final _fatalPattern = RegExp(
  'failed to open|failed to recognize|loading failed|no video or audio|'
  'unrecognized file format|error opening|http error|server returned|'
  'forbidden|not found|connection refused|connection timed out|'
  'could not resolve|network is unreachable|handshake|certificate|'
  r'\b(?:tls|ssl)\b',
  caseSensitive: false,
);

/// Maps an [AspectMode] to the `fit` used by media_kit's `Video`.
@visibleForTesting
BoxFit mpvFit(AspectMode aspect) => switch (aspect) {
  AspectMode.fit => BoxFit.contain,
  AspectMode.fill => BoxFit.cover,
  AspectMode.stretch ||
  AspectMode.ratio16x9 ||
  AspectMode.ratio4x3 => BoxFit.fill,
};

/// Video output settings for the Hardware/Software decoding setting.
///
/// On Android media_kit derives `hwdec` from `enableHardwareAcceleration`
/// (`auto-safe` or `no`, and always `no` in emulators). On desktop that flag
/// only picks GPU or CPU rendering and `hwdec` defaults to `auto`, so it is
/// set explicitly and rendering stays on the GPU.
@visibleForTesting
VideoControllerConfiguration mpvVideoConfiguration({
  required bool hardwareDecoding,
  required bool android,
}) => android
    ? VideoControllerConfiguration(enableHardwareAcceleration: hardwareDecoding)
    : VideoControllerConfiguration(
        hwdec: hardwareDecoding ? 'auto-safe' : 'no',
      );

/// Reads an mpv property as a string; null when unavailable.
typedef MpvPropertyReader = Future<String?> Function(String name);

/// mpv `alang` / `slang` values: [audio] for both unless [subtitles] gives
/// a separate subtitle order.
Map<String, String> mpvLanguageProperties(
  List<String> audio,
  List<String>? subtitles,
) => {'alang': audio.join(','), 'slang': (subtitles ?? audio).join(',')};

/// Creates an mpv [Player]; [lite] picks the smaller demuxer cache.
typedef MpvPlayerBuilder = Player Function({required bool lite});

/// Creates the video output of a new [Player]; null for none (tests).
typedef MpvVideoBuilder = VideoController? Function(
  Player player, {
  required bool hardwareDecoding,
});

Player _newPlayer({required bool lite}) => Player(
  configuration: PlayerConfiguration(
    bufferSize: (lite ? 32 : 64) * _mib,
    logLevel: MPVLogLevel.warn,
  ),
);

VideoController _newVideo(Player player, {required bool hardwareDecoding}) =>
    VideoController(
      player,
      configuration: mpvVideoConfiguration(
        hardwareDecoding: hardwareDecoding,
        android: defaultTargetPlatform == TargetPlatform.android,
      ),
    );

/// The app's long-lived libmpv core, lent to one [MpvEngine] at a time.
///
/// libmpv sends FFmpeg's log lines (HTTP status, TLS details, `tcp:`
/// errors) only to the core that was alive when FFmpeg logging was set up,
/// and media_kit destroys a disposed core 5 s after [Player.dispose]. A core
/// created within those 5 s never gets those lines. So engines borrow this
/// core and stop it when they are done instead of disposing it; it lives
/// until the app exits.
class MpvCore {
  MpvCore({MpvPlayerBuilder? createPlayer, MpvVideoBuilder? createVideo})
    : _createPlayer = createPlayer ?? _newPlayer,
      _createVideo = createVideo ?? _newVideo;

  /// The core every production [MpvEngine] borrows (created on first use).
  static final shared = MpvCore();

  final MpvPlayerBuilder _createPlayer;
  final MpvVideoBuilder _createVideo;

  Player? _player;
  VideoController? _video;
  bool? _hardwareDecoding;
  bool _lent = false;
  Future<void> _idle = Future<void>.value();

  /// Whether an engine holds the core now.
  bool get isLent => _lent;

  /// Lends the core to a new engine, creating it on first use. While another
  /// engine still holds it, the new engine gets a player of its own.
  MpvLease lease({required bool lite, required bool hardwareDecoding}) {
    if (_lent) {
      final player = _createPlayer(lite: lite);
      return MpvLease._(
        player,
        _createVideo(player, hardwareDecoding: hardwareDecoding),
      );
    }
    _lent = true;
    final properties = <String, String>{};
    var player = _player;
    if (player == null) {
      player = _player = _createPlayer(lite: lite);
      _video = _createVideo(player, hardwareDecoding: hardwareDecoding);
    } else {
      // The previous engine's track and volume choices go, as with a new
      // core.
      properties.addAll({
        'aid': 'auto',
        'sid': 'auto',
        'volume': '100',
        'mute': 'no',
      });
      if (_hardwareDecoding != hardwareDecoding) {
        properties['hwdec'] = hardwareDecoding ? 'auto-safe' : 'no';
      }
    }
    _hardwareDecoding = hardwareDecoding;
    return MpvLease._(
      player,
      _video,
      core: this,
      ready: _idle,
      properties: properties,
    );
  }

  /// Stops [player] and takes it back at once; the next engine waits for
  /// the stop ([MpvLease.ready]) before it opens anything.
  Future<void> _release(Player player) {
    final done = _stop(player);
    _idle = done;
    _lent = false;
    return done;
  }

  static Future<void> _stop(Player player) async {
    try {
      await player.stop();
    } on Object catch (_) {
      // Player already torn down.
    }
  }

  /// Disposes the idle core (tests; the app keeps it until exit).
  @visibleForTesting
  Future<void> dispose() async {
    final player = _player;
    if (player == null || _lent) return;
    _player = null;
    _video = null;
    await _idle;
    await player.dispose();
  }
}

/// A [Player] (with its video output) held by one [MpvEngine].
class MpvLease {
  MpvLease._(
    this.player,
    this.video, {
    this._core,
    Future<void>? ready,
    this.properties = const {},
  }) : ready = ready ?? Future<void>.value();

  /// A player the engine owns and disposes.
  MpvLease.owned(Player player) : this._(player, null);

  final Player player;
  final VideoController? video;
  final MpvCore? _core;

  /// Completes once the previous holder of the core has stopped it.
  final Future<void> ready;

  /// mpv properties to set before the first open.
  final Map<String, String> properties;

  /// Whether [player] is the shared core (stopped, not disposed, on release).
  bool get shared => _core != null;

  /// Returns the shared core or disposes an owned player. A shared core is
  /// free again as soon as this is called.
  Future<void> release() async {
    final core = _core;
    if (core != null) return core._release(player);
    try {
      await player.dispose();
    } on Object catch (_) {
      // Native side already gone.
    }
  }
}

/// libmpv through media_kit. One [Player] is reused for the whole session,
/// and production engines borrow it from [MpvCore.shared].
///
/// Constructing it needs `MediaKit.ensureInitialized()` and native libraries,
/// so unit tests use [MpvEngine.withPlayer] with a fake platform player.
class MpvEngine implements PlayerEngine {
  MpvEngine({
    bool lite = false,
    bool hardwareDecoding = true,
    List<String> preferredLanguages = kDefaultPreferredLanguages,
    List<String>? subtitleLanguages,
    MpvCore? core,
  }) : this._(
         (core ?? MpvCore.shared).lease(
           lite: lite,
           hardwareDecoding: hardwareDecoding,
         ),
         lite: lite,
         hardwareDecoding: hardwareDecoding,
         preferredLanguages: preferredLanguages,
         subtitleLanguages: subtitleLanguages,
       );

  /// Wraps an existing [Player] without a video surface; [dispose] disposes
  /// it. [readProperty] stands in for libmpv property reads.
  @visibleForTesting
  MpvEngine.withPlayer(
    Player player, {
    bool lite = false,
    bool hardwareDecoding = true,
    List<String> preferredLanguages = kDefaultPreferredLanguages,
    List<String>? subtitleLanguages,
    MpvPropertyReader? readProperty,
  }) : this._(
         MpvLease.owned(player),
         lite: lite,
         hardwareDecoding: hardwareDecoding,
         preferredLanguages: preferredLanguages,
         subtitleLanguages: subtitleLanguages,
         readProperty: readProperty,
       );

  MpvEngine._(
    this._lease, {
    required this._lite,
    required this.hardwareDecoding,
    required this.preferredLanguages,
    this.subtitleLanguages,
    this._readProperty,
  }) : _player = _lease.player,
       _video = _lease.video,
       _leaseProperties = _lease.properties {
    _listen();
  }

  /// Smaller demuxer cache for low-RAM devices (and split-screen tiles
  /// without sound, [setLite]).
  bool get lite => _lite;
  bool _lite;
  final bool hardwareDecoding;
  final List<String> preferredLanguages;

  /// Subtitle language order (`slang`); null uses [preferredLanguages].
  final List<String>? subtitleLanguages;

  final MpvLease _lease;
  final Player _player;
  final MpvPropertyReader? _readProperty;
  VideoController? _video;

  /// Set before the first open of a borrowed core, then cleared.
  Map<String, String> _leaseProperties;

  final _state = ValueNotifier<PlaybackState>(PlaybackState.idle);
  final _events = StreamController<EngineEvent>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];

  bool _active = false;
  bool _disposed = false;
  bool _isLive = false;
  bool _firstFrameSent = false;
  bool _endedSent = false;
  bool _fatalSent = false;
  int? _width;
  int? _height;
  int? _lastHttpStatus;
  String? _errorDetail;

  @override
  EngineKind get kind => EngineKind.mpv;

  @override
  ValueListenable<PlaybackState> get state => _state;

  @override
  Stream<EngineEvent> get events => _events.stream;

  void _listen() {
    final s = _player.stream;
    _subs.addAll([
      s.position.listen(_onPosition),
      s.duration.listen(_onDuration),
      s.buffering.listen((b) => _update(_state.value.copyWith(buffering: b))),
      s.playing.listen((p) => _update(_state.value.copyWith(playing: p))),
      s.width.listen((w) => _onSize(w, _height)),
      s.height.listen((h) => _onSize(_width, h)),
      s.completed.listen(_onCompleted),
      s.error.listen(_onError),
      s.log.listen(_onLog),
    ]);
  }

  void _update(PlaybackState next) {
    if (!_active || _disposed) return;
    _state.value = next;
  }

  void _onPosition(Duration p) {
    if (!_active) return;
    _update(_state.value.copyWith(position: p));
    _maybeFirstFrame();
  }

  void _onDuration(Duration d) {
    _update(_state.value.copyWith(duration: _isLive ? Duration.zero : d));
  }

  void _onSize(int? w, int? h) {
    if (!_active) return;
    _width = w;
    _height = h;
    if ((w ?? 0) > 0 && (h ?? 0) > 0) {
      _update(
        _state.value.copyWith(videoSize: Size(w!.toDouble(), h!.toDouble())),
      );
    }
    _maybeFirstFrame();
  }

  void _maybeFirstFrame() {
    if (!_active || _firstFrameSent) return;
    if ((_width ?? 0) > 0 || _state.value.position > Duration.zero) {
      _firstFrameSent = true;
      _update(_state.value.copyWith(hasFirstFrame: true));
      _emit(const FirstFrameEvent());
    }
  }

  void _onCompleted(bool completed) {
    if (!_active) return;
    if (!completed) {
      _endedSent = false;
      return;
    }
    _update(_state.value.copyWith(playing: false, buffering: false));
    if (!_endedSent) {
      _endedSent = true;
      _emit(const EndedEvent());
    }
  }

  void _onLog(PlayerLog log) {
    if (!_active) return;
    if (log.level != 'error' && log.level != 'warn' && log.level != 'fatal') {
      return;
    }
    final status = httpStatusFromMessage(log.text);
    if (status != null) _lastHttpStatus = status;
    if (status != null || looksLikeTlsError(log.text)) {
      _errorDetail = log.text;
    }
  }

  void _onError(String raw) {
    if (!_active) return;
    final fatal = _fatalPattern.hasMatch(raw);
    if (!fatal) {
      final message = redact(raw);
      _emit(
        ErrorEvent(
          message,
          fatal: false,
          httpStatus: httpStatusFromMessage(message),
        ),
      );
      return;
    }
    if (_fatalSent) return;
    _fatalSent = true;
    _update(_state.value.copyWith(playing: false, buffering: false));
    // The log line explaining the failure (HTTP status, TLS) goes with this
    // error only; an old TLS warning must not turn a later error into one.
    final detail = _errorDetail;
    final status = _lastHttpStatus;
    _errorDetail = null;
    _lastHttpStatus = null;
    final text = detail != null && !raw.contains(detail)
        ? '$raw ($detail)'
        : raw;
    final message = redact(text);
    _emit(
      ErrorEvent(message, httpStatus: httpStatusFromMessage(message) ?? status),
    );
  }

  void _emit(EngineEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  @override
  Future<void> open(StreamRequest request) async {
    if (_disposed) throw StateError('MpvEngine is disposed');
    _active = true;
    _isLive = request.isLive;
    _firstFrameSent = false;
    _endedSent = false;
    _fatalSent = false;
    _width = null;
    _height = null;
    _lastHttpStatus = null;
    _errorDetail = null;
    _state.value = const PlaybackState(buffering: true);
    // A borrowed core may still be stopping for its previous engine.
    await _lease.ready;
    if (_disposed || !_active) return;

    final headers = <String, String>{};
    String? userAgent;
    request.headers.forEach((k, v) {
      if (k.toLowerCase() == 'user-agent') {
        userAgent = v;
      } else {
        headers[k] = v;
      }
    });
    await _configure(userAgent ?? kDefaultUserAgent);

    final startAt = request.startAt;
    try {
      await _player.open(
        Media(
          request.url,
          httpHeaders: headers,
          start: !request.isLive && startAt != null && startAt > Duration.zero
              ? startAt
              : null,
        ),
      );
    } catch (e) {
      _onError('Failed to open: $e');
    }
  }

  /// Network and language options, set before every open.
  Future<void> _configure(String userAgent) async {
    final native = _player.platform;
    if (native is! NativePlayer) return;
    final props = {
      ..._leaseProperties,
      'user-agent': userAgent,
      'network-timeout': '15',
      'stream-lavf-o':
          'reconnect_streamed=1,reconnect_on_network_error=1,'
          'reconnect_delay_max=5',
      'cache-pause-wait': '2',
      // A borrowed core keeps the cache size of the engine that created it.
      'demuxer-max-bytes': '$_cacheBytes',
      'demuxer-max-back-bytes': '$_cacheBytes',
      ...mpvLanguageProperties(preferredLanguages, subtitleLanguages),
    };
    _leaseProperties = const {};
    for (final MapEntry(:key, :value) in props.entries) {
      try {
        await native.setProperty(key, value);
      } catch (_) {
        // Unknown option on this libmpv build; keep going.
      }
    }
  }

  int get _cacheBytes => (_lite ? 32 : 64) * _mib;

  /// Sizes the demuxer cache at once while a stream is open (mpv applies
  /// it on the fly), else from the next open ([_configure]).
  @override
  Future<void> setLite(bool lite) async {
    if (_disposed || lite == _lite) return;
    _lite = lite;
    final native = _player.platform;
    if (!_active || native is! NativePlayer) return;
    for (final name in const ['demuxer-max-bytes', 'demuxer-max-back-bytes']) {
      try {
        await native.setProperty(name, '$_cacheBytes');
      } catch (_) {
        // Player torn down.
      }
    }
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    await _player.play();
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_disposed || _isLive) return;
    _endedSent = false;
    await _player.seek(position);
  }

  @override
  Future<void> stop() async {
    _active = false;
    if (_disposed) return;
    try {
      await _player.stop();
    } catch (_) {
      // Player already torn down.
    }
    _state.value = PlaybackState.idle;
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    // An explicit level wins over the borrowed core's reset.
    _leaseProperties = {..._leaseProperties}..remove('volume');
    try {
      await _player.setVolume(volume.clamp(0.0, 1.0) * 100);
    } catch (_) {
      // Player torn down, or a platform player without volume.
    }
  }

  @override
  Future<void> setMuted(bool muted) async {
    if (_disposed) return;
    _leaseProperties = {..._leaseProperties}..remove('mute');
    final native = _player.platform;
    if (native is! NativePlayer) return;
    try {
      await native.setProperty('mute', muted ? 'yes' : 'no');
    } catch (_) {
      // Player torn down.
    }
  }

  Iterable<T> _real<T>(List<T> tracks, String Function(T) id) =>
      tracks.where((t) => id(t) != 'auto' && id(t) != 'no');

  Future<String?> _property(String name) async {
    try {
      final read = _readProperty;
      if (read != null) return await read(name);
      final native = _player.platform;
      return native is NativePlayer ? await native.getProperty(name) : null;
    } catch (_) {
      return null; // Unknown property, or the player is gone.
    }
  }

  /// The track id mpv actually plays. media_kit only records explicit
  /// selections and reports `auto` otherwise (e.g. after `alang` picked one),
  /// so ask mpv (`aid` / `sid`, which read back the chosen id or `no`).
  Future<String> _selectedId(String recorded, String property) async {
    if (recorded != 'auto') return recorded;
    final id = (await _property(property))?.trim();
    return id == null || id.isEmpty ? 'auto' : id;
  }

  @override
  Future<List<TrackInfo>> audioTracks() async {
    if (_disposed) return const [];
    final selected = await _selectedId(_player.state.track.audio.id, 'aid');
    return [
      for (final t in _real(_player.state.tracks.audio, (t) => t.id))
        TrackInfo(
          id: t.id,
          language: t.language,
          label: t.title,
          codec: t.codec,
          selected: t.id == selected,
        ),
    ];
  }

  @override
  Future<void> selectAudio(String id) async {
    if (_disposed) return;
    for (final t in _player.state.tracks.audio) {
      if (t.id == id) return _player.setAudioTrack(t);
    }
  }

  @override
  Future<List<TrackInfo>> subtitleTracks() async {
    if (_disposed) return const [];
    final selected = await _selectedId(_player.state.track.subtitle.id, 'sid');
    return [
      for (final t in _real(_player.state.tracks.subtitle, (t) => t.id))
        TrackInfo(
          id: t.id,
          language: t.language,
          label: t.title,
          codec: t.codec,
          selected: t.id == selected,
        ),
    ];
  }

  @override
  Future<void> selectSubtitle(String? id) async {
    if (_disposed) return;
    if (id == null) return _player.setSubtitleTrack(SubtitleTrack.no());
    for (final t in _player.state.tracks.subtitle) {
      if (t.id == id) return _player.setSubtitleTrack(t);
    }
  }

  @override
  Future<Map<String, String>> stats() async {
    if (_disposed) return const {'engine': 'mpv'};
    final state = _player.state;
    final video = _real(state.tracks.video, (t) => t.id).firstOrNull;
    final audioId = await _selectedId(state.track.audio.id, 'aid');
    final audio = _real(
      state.tracks.audio,
      (t) => t.id,
    ).where((t) => t.id == audioId || audioId == 'auto').firstOrNull;
    var hwdec = hardwareDecoding ? 'auto-safe' : 'no';
    if (_active) {
      // Unavailable before the first frame.
      final current = await _property('hwdec-current');
      if (current != null && current.isNotEmpty) hwdec = current;
    }
    return {
      'engine': 'mpv',
      'hwdec': hwdec,
      'cache': '${_lite ? 32 : 64} MB',
      if ((_width ?? 0) > 0 && (_height ?? 0) > 0)
        'resolution': '${_width}x$_height',
      if (video?.codec != null) 'video': video!.codec!,
      if (audio?.codec != null) 'audio': audio!.codec!,
    };
  }

  @override
  Widget buildView({AspectMode aspect = AspectMode.fit}) {
    final controller = _video;
    if (controller == null) {
      return const ColoredBox(
        color: Color(0xFF000000),
        child: SizedBox.expand(),
      );
    }
    final view = Video(
      controller: controller,
      controls: null, // NoVideoControls (typed as dynamic upstream).
      wakelock: false,
      pauseUponEnteringBackgroundMode: false,
      fit: mpvFit(aspect),
    );
    final ratio = switch (aspect) {
      AspectMode.ratio16x9 => 16 / 9,
      AspectMode.ratio4x3 => 4 / 3,
      _ => null,
    };
    if (ratio == null) return view;
    return ColoredBox(
      color: const Color(0xFF000000),
      child: Center(
        child: AspectRatio(aspectRatio: ratio, child: view),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _active = false;
    _disposed = true;
    // A shared core is free for the next engine right away.
    final released = _lease.release();
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await released;
    _video = null;
    await _events.close();
    _state.dispose();
  }
}
