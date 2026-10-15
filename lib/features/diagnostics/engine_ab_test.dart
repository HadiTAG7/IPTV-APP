import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/log/ring_log.dart';
import '../../core/net/redact.dart';
import '../../core/time/clock.dart';
import '../../player/engine/engine_factory.dart';
import '../../player/engine/player_engine.dart';
import '../../player/player_providers.dart';
import '../../sources/models.dart';

/// A public, legal test stream for the engine A/B test.
@immutable
class DiagnosticsTestStream {
  const DiagnosticsTestStream({required this.name, required this.url});

  final String name;
  final String url;
}

/// Apple's bipbop sample and Mux's public HLS test stream.
const kDiagnosticsTestStreams = [
  DiagnosticsTestStream(
    name: 'Apple bipbop 4:3 (HLS)',
    url:
        'https://devstreaming-cdn.apple.com/videos/streaming/examples/'
        'bipbop_4x3/bipbop_4x3_variant.m3u8',
  ),
  DiagnosticsTestStream(
    name: 'Mux x36xhzz (HLS)',
    url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  ),
];

enum EngineTestStatus { pending, running, passed, failed, timedOut, cancelled }

/// The outcome of one engine on one test stream.
@immutable
class EngineTestResult {
  const EngineTestResult({
    required this.engine,
    required this.stream,
    this.status = EngineTestStatus.pending,
    this.firstFrame,
    this.message,
  });

  final EngineKind engine;

  /// Index into the test streams.
  final int stream;
  final EngineTestStatus status;

  /// Time from open to the first frame when [status] is passed.
  final Duration? firstFrame;

  /// Redacted error text when [status] is failed.
  final String? message;

  EngineTestResult copyWith({
    EngineTestStatus? status,
    Duration? firstFrame,
    String? message,
  }) => EngineTestResult(
    engine: engine,
    stream: stream,
    status: status ?? this.status,
    firstFrame: firstFrame ?? this.firstFrame,
    message: message ?? this.message,
  );

  @override
  String toString() {
    final ms = firstFrame?.inMilliseconds;
    return '${engine.name} #${stream + 1}: ${status.name}'
        '${ms == null ? '' : ' ($ms ms)'}'
        '${message == null ? '' : ' - $message'}';
  }
}

/// Plays each test stream on each engine, one at a time, and measures the
/// time to the first frame. Only one engine (one connection) exists at any
/// moment; each is stopped and disposed before the next starts.
class EngineAbTest extends ChangeNotifier {
  EngineAbTest({
    required this.buildFactory,
    required this.engines,
    required this.streams,
    required this.options,
    this.clock = const SystemClock(),
    this.timeout = const Duration(seconds: 20),
    RingLog? log,
    this._exoViewType = VideoViewType.textureView,
  }) : _log = log ?? RingLog.instance {
    _reset();
  }

  final EngineFactoryBuilder buildFactory;

  /// Engines to compare (ExoPlayer is Android only).
  final List<EngineKind> engines;
  final List<DiagnosticsTestStream> streams;

  /// Engine options for a view type (the rest comes from Settings).
  final EngineOptions Function(VideoViewType exoViewType) options;
  final Clock clock;
  final Duration timeout;
  final RingLog _log;

  VideoViewType _exoViewType;
  List<EngineTestResult> _results = const [];
  bool _running = false;
  bool _cancelled = false;
  bool _disposed = false;
  PlayerEngine? _active;
  Completer<EngineEvent?>? _waiting;

  List<EngineTestResult> get results => _results;
  bool get running => _running;

  /// The engine playing now (for a small preview), or null.
  PlayerEngine? get activeEngine => _active;

  /// ExoPlayer texture view (default) or platform view for the next run.
  VideoViewType get exoViewType => _exoViewType;

  set exoViewType(VideoViewType value) {
    if (_running || value == _exoViewType) return;
    _exoViewType = value;
    _notify();
  }

  void _reset() {
    _results = [
      for (final e in engines)
        for (var i = 0; i < streams.length; i++)
          EngineTestResult(engine: e, stream: i),
    ];
  }

  /// Runs every engine on every stream. Completes when done or cancelled.
  Future<void> run() async {
    if (_running || _disposed) return;
    _running = true;
    _cancelled = false;
    _reset();
    _notify();
    final factory = buildFactory(options(_exoViewType));
    _log.info(
      'Diagnostics: engine test (exo view ${_exoViewType.name}) started',
    );
    for (var i = 0; i < _results.length; i++) {
      if (_cancelled || _disposed) break;
      _set(i, _results[i].copyWith(status: EngineTestStatus.running));
      final result = await _runOne(factory, _results[i]);
      if (_disposed) return;
      _set(i, result);
      _log.info('Diagnostics: $result');
    }
    if (_cancelled) {
      _results = [
        for (final r in _results)
          r.status == EngineTestStatus.pending ||
                  r.status == EngineTestStatus.running
              ? r.copyWith(status: EngineTestStatus.cancelled)
              : r,
      ];
    }
    _running = false;
    _notify();
  }

  Future<EngineTestResult> _runOne(
    EngineFactory factory,
    EngineTestResult pending,
  ) async {
    final stream = streams[pending.stream];
    final PlayerEngine engine;
    try {
      engine = factory(pending.engine);
    } on Object catch (e) {
      return pending.copyWith(
        status: EngineTestStatus.failed,
        message: redact('$e'),
      );
    }
    _active = engine;
    _notify();
    final waiting = Completer<EngineEvent?>();
    _waiting = waiting;
    final sub = engine.events.listen((e) {
      if (waiting.isCompleted) return;
      if (e is FirstFrameEvent || (e is ErrorEvent && e.fatal)) {
        waiting.complete(e);
      }
    });
    final timer = Timer(timeout, () {
      if (!waiting.isCompleted) waiting.complete(null);
    });
    final started = clock.now();
    // Not awaited: an engine whose open never returns still times out.
    unawaited(
      Future<void>.sync(
        () => engine.open(
          StreamRequest(
            url: stream.url,
            kind: PlayableKind.movie,
            isHls: stream.url.contains('.m3u8'),
            title: stream.name,
          ),
        ),
      ).catchError((Object e) {
        if (!waiting.isCompleted) waiting.complete(ErrorEvent(redact('$e')));
      }),
    );
    final event = await waiting.future;
    final elapsed = clock.now().difference(started);
    timer.cancel();
    _waiting = null;
    // Not awaited: a cancel can stay pending until the stream closes.
    unawaited(sub.cancel());
    if (identical(_active, engine)) _active = null;
    _notify();
    await _close(engine);
    if (_cancelled && event == null) {
      return pending.copyWith(status: EngineTestStatus.cancelled);
    }
    return switch (event) {
      FirstFrameEvent() => pending.copyWith(
        status: EngineTestStatus.passed,
        firstFrame: elapsed,
      ),
      ErrorEvent(:final message) => pending.copyWith(
        status: EngineTestStatus.failed,
        message: redact(message),
      ),
      _ => pending.copyWith(status: EngineTestStatus.timedOut),
    };
  }

  Future<void> _close(PlayerEngine engine) async {
    try {
      await engine.stop();
    } on Object catch (_) {
      // Closing is best-effort.
    }
    try {
      await engine.dispose();
    } on Object catch (_) {
      // Native side already gone.
    }
  }

  /// Stops the running test after the current stream closes.
  void cancel() {
    if (!_running) return;
    _cancelled = true;
    final waiting = _waiting;
    if (waiting != null && !waiting.isCompleted) waiting.complete(null);
  }

  void _set(int i, EngineTestResult r) {
    _results = [..._results]..[i] = r;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Cancels a running test; its current engine is closed when the stream
  /// in progress returns.
  @override
  void dispose() {
    cancel();
    _disposed = true;
    super.dispose();
  }
}
