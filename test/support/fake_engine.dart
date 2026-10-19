import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/sources/models.dart';

/// Scriptable [PlayerEngine] for unit and widget tests.
///
/// Records every call (in [calls], and with the engine kind prefixed in the
/// shared [log]) and lets tests drive state and events.
class FakeEngine implements PlayerEngine {
  FakeEngine(this.kind, {List<String>? log}) : log = log ?? <String>[];

  @override
  final EngineKind kind;

  /// Shared, ordered log such as `exo.open http://…`, `exo.stop`.
  final List<String> log;

  /// This engine's calls: `open`, `play`, `pause`, `seek 1000`, `stop`, ...
  final calls = <String>[];
  final opened = <StreamRequest>[];

  /// Returned by [audioTracks] / [subtitleTracks].
  List<TrackInfo> audio = const [];
  List<TrackInfo> subtitles = const [];
  Map<String, String> statsMap = const {};

  /// Runs at the end of [open], e.g. to emit an error or a first frame.
  FutureOr<void> Function(FakeEngine engine, StreamRequest request)? onOpen;

  /// Makes [open] take this long (a fake timer under fake_async).
  Duration openDelay = Duration.zero;

  /// Makes [dispose] take this long, like ExoEngine awaiting the platform.
  Duration disposeDelay = Duration.zero;

  bool disposed = false;
  bool _disposing = false;
  String? selectedAudio;
  String? selectedSubtitle;

  final _state = ValueNotifier<PlaybackState>(PlaybackState.idle);
  final _events = StreamController<EngineEvent>.broadcast();

  String get _tag => kind.name;

  int count(String call) => calls.where((c) => c == call).length;

  StreamRequest? get lastRequest => opened.isEmpty ? null : opened.last;

  @override
  ValueListenable<PlaybackState> get state => _state;

  @override
  Stream<EngineEvent> get events => _events.stream;

  @override
  Future<void> open(StreamRequest request) async {
    _checkAlive();
    calls.add('open');
    log.add('$_tag.open ${request.url}');
    opened.add(request);
    _state.value = const PlaybackState(buffering: true);
    if (openDelay > Duration.zero) await Future<void>.delayed(openDelay);
    await onOpen?.call(this, request);
  }

  @override
  Future<void> play() async {
    calls.add('play');
    _state.value = _state.value.copyWith(playing: true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _state.value = _state.value.copyWith(playing: false);
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek ${position.inMilliseconds}');
    _state.value = _state.value.copyWith(position: position);
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    log.add('$_tag.stop');
    if (!disposed) _state.value = PlaybackState.idle;
  }

  @override
  Future<List<TrackInfo>> audioTracks() async {
    calls.add('audioTracks');
    return audio;
  }

  @override
  Future<void> selectAudio(String id) async {
    calls.add('selectAudio $id');
    selectedAudio = id;
  }

  @override
  Future<List<TrackInfo>> subtitleTracks() async => subtitles;

  @override
  Future<void> selectSubtitle(String? id) async {
    calls.add('selectSubtitle $id');
    selectedSubtitle = id;
  }

  @override
  Future<Map<String, String>> stats() async => {'engine': _tag, ...statsMap};

  /// Set by [setVolume] and [setMuted].
  double volume = 1;
  bool muted = false;

  @override
  Future<void> setVolume(double volume) async {
    calls.add('setVolume $volume');
    this.volume = volume;
  }

  @override
  Future<void> setMuted(bool muted) async {
    calls.add('setMuted $muted');
    this.muted = muted;
  }

  /// Set by [setLite]; null until called.
  bool? lite;

  @override
  Future<void> setLite(bool lite) async {
    calls.add('setLite $lite');
    this.lite = lite;
  }

  @override
  Widget buildView({AspectMode aspect = AspectMode.fit}) =>
      SizedBox.expand(key: ValueKey('fake-$_tag-${aspect.name}'));

  @override
  Future<void> dispose() async {
    if (disposed || _disposing) return;
    _disposing = true;
    calls.add('dispose');
    log.add('$_tag.dispose');
    if (disposeDelay > Duration.zero) await Future<void>.delayed(disposeDelay);
    disposed = true;
    await _events.close();
  }

  // ---- scripting -------------------------------------------------------

  /// Playback started: first frame shown, playing, not buffering.
  void emitFirstFrame() {
    _state.value = _state.value.copyWith(
      hasFirstFrame: true,
      playing: true,
      buffering: false,
    );
    _emit(const FirstFrameEvent());
  }

  void emitError(String message, {int? httpStatus, bool fatal = true}) {
    _state.value = _state.value.copyWith(playing: false, buffering: false);
    _emit(ErrorEvent(message, httpStatus: httpStatus, fatal: fatal));
  }

  void emitEnded() {
    _state.value = _state.value.copyWith(playing: false);
    _emit(const EndedEvent());
  }

  /// Replaces parts of the published state.
  void setState({
    Duration? position,
    Duration? duration,
    bool? buffering,
    bool? playing,
    bool? hasFirstFrame,
  }) {
    _state.value = _state.value.copyWith(
      position: position,
      duration: duration,
      buffering: buffering,
      playing: playing,
      hasFirstFrame: hasFirstFrame,
    );
  }

  void _emit(EngineEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  void _checkAlive() {
    if (disposed) throw StateError('$_tag engine used after dispose');
  }
}

/// [EngineFactory] that hands out [FakeEngine]s and remembers them.
class FakeEngineFactory {
  FakeEngineFactory({this.onCreate});

  /// Scripts each new engine (set [FakeEngine.onOpen], tracks, ...).
  void Function(FakeEngine engine)? onCreate;

  final log = <String>[];
  final created = <FakeEngine>[];

  /// Highest number of undisposed engines seen at creation time.
  int maxAlive = 0;

  FakeEngine get last => created.last;

  int get alive => created.where((e) => !e.disposed).length;

  PlayerEngine call(EngineKind kind) {
    final engine = FakeEngine(kind, log: log);
    log.add('${kind.name}.create');
    created.add(engine);
    if (alive > maxAlive) maxAlive = alive;
    onCreate?.call(engine);
    return engine;
  }
}
