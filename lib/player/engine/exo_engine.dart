import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../../core/net/http.dart' show kDefaultUserAgent;
import '../../core/net/redact.dart';
import '../../sources/models.dart';
import 'engine_policy.dart';
import 'player_engine.dart';

/// Creates the `video_player` controller for one stream. Injectable for tests.
typedef ExoControllerFactory = VideoPlayerController Function(
  Uri uri, {
  required Map<String, String> httpHeaders,
  required VideoFormat? formatHint,
  required VideoViewType viewType,
});

VideoPlayerController _defaultControllerFactory(
  Uri uri, {
  required Map<String, String> httpHeaders,
  required VideoFormat? formatHint,
  required VideoViewType viewType,
}) => VideoPlayerController.networkUrl(
  uri,
  httpHeaders: httpHeaders,
  formatHint: formatHint,
  viewType: viewType,
);

/// ExoPlayer reports `C.TIME_UNSET` (Long.MIN_VALUE + 1) for live TS and
/// other streams of unknown length; video_player turns it into 1 ms. Anything
/// at or below this, or above [_maxSaneDuration], is not a real length.
const _minSaneDuration = Duration(seconds: 1);
const _maxSaneDuration = Duration(days: 30);

/// True when [d] is a real media length rather than ExoPlayer's "unset".
@visibleForTesting
bool isKnownExoDuration(Duration d) =>
    d > _minSaneDuration && d <= _maxSaneDuration;

/// Maps a `video_player` value to the engine-neutral [PlaybackState].
///
/// [position] replaces `v.position`, which video_player clamps to the
/// (possibly fake) duration.
@visibleForTesting
PlaybackState mapExoValue(
  VideoPlayerValue v, {
  required bool isLive,
  Duration? position,
}) {
  final duration = v.duration;
  final pos = position ?? v.position;
  final size = v.size;
  return PlaybackState(
    position: pos < Duration.zero ? Duration.zero : pos,
    duration: isLive || !isKnownExoDuration(duration)
        ? Duration.zero
        : duration,
    buffering: !v.hasError && (!v.isInitialized || v.isBuffering),
    playing: v.isPlaying,
    videoSize: size.width > 0 && size.height > 0 ? size : null,
    hasFirstFrame: v.isInitialized && (v.isPlaying || pos > Duration.zero),
  );
}

/// Puts the User-Agent under the exact key `User-Agent` (the only one
/// video_player_android reads; any other spelling is replaced by
/// "ExoPlayer"), adding the app default when none is given.
@visibleForTesting
Map<String, String> withDefaultUserAgent(Map<String, String> headers) {
  String? userAgent;
  final out = <String, String>{};
  headers.forEach((k, v) {
    if (k.toLowerCase() == 'user-agent') {
      userAgent ??= v;
    } else {
      out[k] = v;
    }
  });
  out['User-Agent'] = userAgent ?? kDefaultUserAgent;
  return out;
}

/// ExoPlayer (Media3) through `video_player`. Android only.
///
/// `video_player` cannot change the source of a controller, so every [open]
/// disposes the previous controller and creates a new one.
///
/// For live and unknown-length streams video_player's position, duration and
/// completion flag are meaningless (see [isKnownExoDuration]), so the raw
/// platform position is polled instead and an end is only reported once the
/// player has stayed stopped and completed for two polls.
class ExoEngine implements PlayerEngine {
  ExoEngine({
    this.viewType = VideoViewType.textureView,
    this.positionPollInterval = const Duration(milliseconds: 500),
    ExoControllerFactory? controllerFactory,
  }) : _createController = controllerFactory ?? _defaultControllerFactory;

  final VideoViewType viewType;

  /// How often the raw position is read for live and unknown-length streams.
  final Duration positionPollInterval;
  final ExoControllerFactory _createController;

  final _state = ValueNotifier<PlaybackState>(PlaybackState.idle);
  final _events = StreamController<EngineEvent>.broadcast();
  final _controller = ValueNotifier<VideoPlayerController?>(null);

  StreamRequest? _request;
  int _generation = 0;
  bool _firstFrameSent = false;
  bool _endedSent = false;
  bool _errorSent = false;
  bool _disposed = false;

  /// Whether playback should run once the controller is ready; [pause]
  /// before `initialize()` completes clears it.
  bool _playWhenReady = true;

  /// [setVolume] and [setMuted]; every new controller starts at full.
  double _volume = 1;
  bool _muted = false;

  /// Live or unknown length: the position comes from [_poll].
  Duration? _rawPosition;
  Timer? _poll;
  int _endedPolls = 0;

  @override
  EngineKind get kind => EngineKind.exo;

  @override
  ValueListenable<PlaybackState> get state => _state;

  @override
  Stream<EngineEvent> get events => _events.stream;

  /// The live controller, for tests and diagnostics.
  @visibleForTesting
  VideoPlayerController? get controller => _controller.value;

  @override
  Future<void> open(StreamRequest request) async {
    if (_disposed) throw StateError('ExoEngine is disposed');
    final gen = ++_generation;
    await _release();
    if (gen != _generation) return;

    _request = request;
    _firstFrameSent = false;
    _endedSent = false;
    _errorSent = false;
    _playWhenReady = true;
    _state.value = const PlaybackState(buffering: true);

    final Uri uri;
    try {
      uri = Uri.parse(request.url);
    } on FormatException {
      _emitError('Invalid stream URL: ${redact(request.url)}');
      return;
    }

    final c = _createController(
      uri,
      httpHeaders: withDefaultUserAgent(request.headers),
      formatHint: request.isHls ? VideoFormat.hls : null,
      viewType: viewType,
    );
    c.addListener(_onValue);
    _controller.value = c;
    // initialize() completes on first data, which may take seconds; open()
    // only starts it so a newer open/stop is never blocked behind it.
    unawaited(_start(c, gen, request));
  }

  Future<void> _start(
    VideoPlayerController c,
    int gen,
    StreamRequest request,
  ) async {
    try {
      await c.initialize();
    } catch (e) {
      if (gen == _generation && !_errorSent) {
        _emitError(_describe(e));
      }
      return;
    }
    if (gen != _generation) return;
    final raw = _isRaw(c.value);
    if (raw) {
      _poll = Timer.periodic(positionPollInterval, (_) {
        unawaited(_pollPosition(c, gen));
      });
    }
    try {
      final startAt = request.startAt;
      // Seeks are clamped to the duration, so an unknown length can't seek.
      if (!raw && startAt != null && startAt > Duration.zero) {
        await c.seekTo(startAt);
      }
      if (_volume != 1 || _muted) await _applyVolume();
      if (gen != _generation || !_playWhenReady) return;
      await _resume(c);
    } catch (e) {
      if (gen == _generation && !_errorSent) _emitError(_describe(e));
    }
  }

  /// Live, or a length ExoPlayer does not know: video_player's position and
  /// completion flag are clamped to a fake duration and must be ignored.
  bool _isRaw(VideoPlayerValue v) =>
      (_request?.isLive ?? false) ||
      (v.isInitialized && !isKnownExoDuration(v.duration));

  Future<void> _resume(VideoPlayerController c) async {
    final v = c.value;
    // video_player restarts from 0 when position == duration, which is always
    // true once an unknown length was clamped to its fake 1 ms.
    if (_isRaw(v) && v.position == v.duration) {
      c.value = v.copyWith(position: Duration.zero);
    }
    await c.play();
  }

  /// Reads the unclamped platform position and detects a real end.
  Future<void> _pollPosition(VideoPlayerController c, int gen) async {
    Duration? raw;
    try {
      raw = await c.position;
    } catch (_) {
      // Platform call raced a dispose; the next poll (if any) retries.
    }
    if (gen != _generation || _disposed || !identical(_controller.value, c)) {
      return;
    }
    if (raw != null && raw >= Duration.zero) _rawPosition = raw;
    final v = c.value;
    // A real end makes video_player pause itself and flag completion. A
    // rebuffer also drops isPlaying, but only briefly and while buffering.
    final endedLike =
        _playWhenReady &&
        v.isInitialized &&
        !v.hasError &&
        v.isCompleted &&
        !v.isPlaying &&
        !v.isBuffering;
    _endedPolls = endedLike ? _endedPolls + 1 : 0;
    _onValue();
    if (_endedPolls >= 2 && !_endedSent) {
      _endedSent = true;
      _events.add(const EndedEvent());
    }
  }

  void _onValue() {
    final c = _controller.value;
    if (c == null || _disposed) return;
    final v = c.value;

    if (v.hasError) {
      _state.value = _state.value.copyWith(playing: false, buffering: false);
      if (!_errorSent) _emitError(v.errorDescription ?? 'Playback error');
      return;
    }

    final raw = _isRaw(v);
    final mapped = mapExoValue(
      v,
      isLive: _request?.isLive ?? false,
      position: raw ? (_rawPosition ?? Duration.zero) : null,
    );
    _state.value = _firstFrameSent
        ? mapped.copyWith(hasFirstFrame: true)
        : mapped;

    if (mapped.hasFirstFrame && !_firstFrameSent) {
      _firstFrameSent = true;
      _events.add(const FirstFrameEvent());
    }

    if (v.isPlaying) {
      _endedSent = false;
      _endedPolls = 0;
    }
    if (!raw && !_endedSent && _isEnded(v)) {
      _endedSent = true;
      _events.add(const EndedEvent());
    }
  }

  /// End of a VOD with a known length. video_player also sets isCompleted
  /// when a poll overshoots the duration while still playing, so only a
  /// stopped player counts.
  bool _isEnded(VideoPlayerValue v) {
    if (!v.isInitialized || v.isPlaying || v.isBuffering) return false;
    if (v.isCompleted) return true;
    final d = v.duration;
    return isKnownExoDuration(d) &&
        v.position >= d - const Duration(milliseconds: 500);
  }

  void _emitError(String raw) {
    _errorSent = true;
    final message = redact(raw);
    if (_events.isClosed) return;
    _events.add(
      ErrorEvent(message, httpStatus: httpStatusFromMessage(message)),
    );
  }

  String _describe(Object e) => switch (e) {
    PlatformException(:final message?) => message,
    _ => '$e',
  };

  /// Pauses and disposes the current controller, closing its connection.
  Future<void> _release() async {
    _poll?.cancel();
    _poll = null;
    _rawPosition = null;
    _endedPolls = 0;
    final c = _controller.value;
    if (c == null) return;
    _controller.value = null;
    c.removeListener(_onValue);
    try {
      if (c.value.isInitialized) await c.pause();
    } catch (_) {
      // Already broken; dispose below still frees the player.
    }
    try {
      await c.dispose();
    } catch (_) {
      // Disposing a failed controller can throw on some platforms.
    }
  }

  @override
  Future<void> play() async {
    _playWhenReady = true;
    final c = _controller.value;
    if (c != null && c.value.isInitialized) await _resume(c);
  }

  @override
  Future<void> pause() async {
    _playWhenReady = false;
    final c = _controller.value;
    if (c != null && c.value.isInitialized) await c.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    final c = _controller.value;
    if (c == null || !c.value.isInitialized || _isRaw(c.value)) return;
    _endedSent = false;
    await c.seekTo(position);
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _release();
    if (!_disposed) _state.value = PlaybackState.idle;
  }

  @override
  Future<List<TrackInfo>> audioTracks() async {
    final c = _controller.value;
    if (c == null || !c.value.isInitialized) return const [];
    try {
      final tracks = await c.getAudioTracks();
      return [
        for (final t in tracks)
          TrackInfo(
            id: t.id,
            language: t.language,
            label: t.label,
            codec: t.codec,
            selected: t.isSelected,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> selectAudio(String id) async {
    final c = _controller.value;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.selectAudioTrack(id);
    } catch (_) {
      // Unknown id or platform without track selection.
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _applyVolume();
  }

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    await _applyVolume();
  }

  /// video_player has no mute: a muted controller plays at volume 0.
  Future<void> _applyVolume() async {
    final c = _controller.value;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.setVolume(_muted ? 0 : _volume);
    } catch (_) {
      // Controller disposed meanwhile.
    }
  }

  @override
  Future<List<TrackInfo>> subtitleTracks() async => const [];

  @override
  Future<void> selectSubtitle(String? id) async {}

  @override
  Future<Map<String, String>> stats() async {
    final c = _controller.value;
    final size = _state.value.videoSize;
    final audio = (await audioTracks()).where((t) => t.selected);
    return {
      'engine': 'ExoPlayer',
      'view': viewType == VideoViewType.platformView ? 'platform' : 'texture',
      'format': (_request?.isHls ?? false) ? 'hls' : 'auto',
      if (size != null)
        'resolution': '${size.width.round()}x${size.height.round()}',
      if (audio.isNotEmpty && audio.first.codec != null)
        'audio': audio.first.codec!,
      if (c != null && c.value.hasError)
        'error': redact(c.value.errorDescription!),
    };
  }

  @override
  Widget buildView({AspectMode aspect = AspectMode.fit}) =>
      _ExoView(controller: _controller, aspect: aspect);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _events.close();
    _controller.dispose();
    _state.dispose();
  }
}

class _ExoView extends StatelessWidget {
  const _ExoView({required this.controller, required this.aspect});

  final ValueListenable<VideoPlayerController?> controller;
  final AspectMode aspect;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF000000),
      child: ValueListenableBuilder<VideoPlayerController?>(
        valueListenable: controller,
        builder: (context, c, _) {
          if (c == null) return const SizedBox.expand();
          return ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (context, v, _) => exoSurface(
              VideoPlayer(c, key: ObjectKey(c)),
              aspect: aspect,
              videoSize: v.size,
            ),
          );
        },
      ),
    );
  }
}

/// Lays out [video] for an [AspectMode]: fit = contain, fill = cover,
/// stretch = fill the box, or a fixed 16:9 / 4:3 frame.
@visibleForTesting
Widget exoSurface(
  Widget video, {
  required AspectMode aspect,
  required Size videoSize,
}) {
  final known = videoSize.width > 0 && videoSize.height > 0;
  final ratio = known ? videoSize.width / videoSize.height : 16 / 9;
  return switch (aspect) {
    AspectMode.fit => Center(
      child: AspectRatio(aspectRatio: ratio, child: video),
    ),
    AspectMode.fill => SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: known ? videoSize.width : 1920,
          height: known ? videoSize.height : 1080,
          child: video,
        ),
      ),
    ),
    AspectMode.stretch => SizedBox.expand(child: video),
    AspectMode.ratio16x9 => Center(
      child: AspectRatio(aspectRatio: 16 / 9, child: video),
    ),
    AspectMode.ratio4x3 => Center(
      child: AspectRatio(aspectRatio: 4 / 3, child: video),
    ),
  };
}
