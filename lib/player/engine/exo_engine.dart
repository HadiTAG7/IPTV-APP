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

/// Durations above this are treated as unknown (ExoPlayer reports
/// `C.TIME_UNSET` for live and some progressive streams).
const _maxSaneDuration = Duration(days: 30);

/// Maps a `video_player` value to the engine-neutral [PlaybackState].
@visibleForTesting
PlaybackState mapExoValue(VideoPlayerValue v, {required bool isLive}) {
  final duration = v.duration;
  final saneDuration =
      isLive || duration <= Duration.zero || duration > _maxSaneDuration
      ? Duration.zero
      : duration;
  final size = v.size;
  return PlaybackState(
    position: v.position < Duration.zero ? Duration.zero : v.position,
    duration: saneDuration,
    buffering: !v.hasError && (!v.isInitialized || v.isBuffering),
    playing: v.isPlaying,
    videoSize: size.width > 0 && size.height > 0 ? size : null,
    hasFirstFrame:
        v.isInitialized && (v.isPlaying || v.position > Duration.zero),
  );
}

/// Adds the app User-Agent unless [headers] already carry one, so panels
/// never see ExoPlayer's library default.
@visibleForTesting
Map<String, String> withDefaultUserAgent(Map<String, String> headers) {
  if (headers.keys.any((k) => k.toLowerCase() == 'user-agent')) return headers;
  return {...headers, 'User-Agent': kDefaultUserAgent};
}

/// ExoPlayer (Media3) through `video_player`. Android only.
///
/// `video_player` cannot change the source of a controller, so every [open]
/// disposes the previous controller and creates a new one.
class ExoEngine implements PlayerEngine {
  ExoEngine({
    this.viewType = VideoViewType.textureView,
    ExoControllerFactory? controllerFactory,
  }) : _createController = controllerFactory ?? _defaultControllerFactory;

  final VideoViewType viewType;
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
    try {
      final startAt = request.startAt;
      if (!request.isLive && startAt != null && startAt > Duration.zero) {
        await c.seekTo(startAt);
      }
      if (gen != _generation) return;
      await c.play();
    } catch (e) {
      if (gen == _generation && !_errorSent) _emitError(_describe(e));
    }
  }

  void _onValue() {
    final c = _controller.value;
    if (c == null || _disposed) return;
    final v = c.value;
    final isLive = _request?.isLive ?? false;

    if (v.hasError) {
      _state.value = _state.value.copyWith(playing: false, buffering: false);
      if (!_errorSent) _emitError(v.errorDescription ?? 'Playback error');
      return;
    }

    final mapped = mapExoValue(v, isLive: isLive);
    _state.value = _firstFrameSent
        ? mapped.copyWith(hasFirstFrame: true)
        : mapped;

    if (mapped.hasFirstFrame && !_firstFrameSent) {
      _firstFrameSent = true;
      _events.add(const FirstFrameEvent());
    }

    if (v.isPlaying) _endedSent = false;
    if (!_endedSent && _isEnded(v, isLive: isLive)) {
      _endedSent = true;
      _events.add(const EndedEvent());
    }
  }

  bool _isEnded(VideoPlayerValue v, {required bool isLive}) {
    if (!v.isInitialized) return false;
    if (v.isCompleted) return true;
    if (isLive || v.isPlaying) return false;
    final d = mapExoValue(v, isLive: false).duration;
    return d > Duration.zero &&
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
    final c = _controller.value;
    if (c != null && c.value.isInitialized) await c.play();
  }

  @override
  Future<void> pause() async {
    final c = _controller.value;
    if (c != null && c.value.isInitialized) await c.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    final c = _controller.value;
    if (c == null || !c.value.isInitialized) return;
    if (_request?.isLive ?? false) return;
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
