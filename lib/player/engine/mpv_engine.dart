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

/// libmpv through media_kit. One [Player] is reused for the whole session.
///
/// Constructing it needs `MediaKit.ensureInitialized()` and native libraries,
/// so unit tests use [MpvEngine.withPlayer] with a fake platform player.
class MpvEngine implements PlayerEngine {
  MpvEngine({
    this.lite = false,
    this.hardwareDecoding = true,
    this.preferredLanguages = kDefaultPreferredLanguages,
  }) : _player = Player(
         configuration: PlayerConfiguration(
           bufferSize: (lite ? 32 : 64) * _mib,
           logLevel: MPVLogLevel.warn,
         ),
       ),
       _readProperty = null {
    _video = VideoController(
      _player,
      configuration: mpvVideoConfiguration(
        hardwareDecoding: hardwareDecoding,
        android: defaultTargetPlatform == TargetPlatform.android,
      ),
    );
    _listen();
  }

  /// Wraps an existing [Player] without a video surface. [readProperty]
  /// stands in for libmpv property reads.
  @visibleForTesting
  MpvEngine.withPlayer(
    this._player, {
    this.lite = false,
    this.hardwareDecoding = true,
    this.preferredLanguages = kDefaultPreferredLanguages,
    this._readProperty,
  }) {
    _listen();
  }

  /// Smaller demuxer cache for low-RAM devices.
  final bool lite;
  final bool hardwareDecoding;
  final List<String> preferredLanguages;

  final Player _player;
  final MpvPropertyReader? _readProperty;
  VideoController? _video;

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
    final langs = preferredLanguages.join(',');
    final props = {
      'user-agent': userAgent,
      'network-timeout': '15',
      'stream-lavf-o':
          'reconnect_streamed=1,reconnect_on_network_error=1,'
          'reconnect_delay_max=5',
      'cache-pause-wait': '2',
      'alang': langs,
      'slang': langs,
    };
    for (final MapEntry(:key, :value) in props.entries) {
      try {
        await native.setProperty(key, value);
      } catch (_) {
        // Unknown option on this libmpv build; keep going.
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
      'cache': '${lite ? 32 : 64} MB',
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
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    try {
      await _player.dispose();
    } catch (_) {
      // Native side already gone.
    }
    _video = null;
    await _events.close();
    _state.dispose();
  }
}
