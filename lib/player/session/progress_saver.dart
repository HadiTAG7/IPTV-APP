import 'dart:async';

import '../engine/player_engine.dart';

/// Persists a VOD position (and duration, zero when unknown).
typedef ProgressSink = Future<void> Function(Duration position, Duration dur);

/// Saves VOD progress every [interval] while playing, and on pause, stop,
/// dispose and app backgrounding (via [flush]).
class ProgressSaver {
  ProgressSaver({
    required this.save,
    this.interval = const Duration(seconds: 10),
  });

  final ProgressSink save;
  final Duration interval;

  Timer? _timer;
  PlaybackState? _latest;
  (Duration, Duration)? _lastSaved;
  bool _wasPlaying = false;
  bool _closed = false;

  /// A title counts as watched above 95% or with under 2 minutes left.
  static bool isFinished(Duration position, Duration duration) {
    if (duration <= Duration.zero || position <= Duration.zero) return false;
    if (position.inMilliseconds >= duration.inMilliseconds * 0.95) return true;
    return duration - position < const Duration(minutes: 2);
  }

  /// The resume prompt appears past 30 s for titles not yet finished.
  static bool shouldOfferResume(Duration position, Duration duration) =>
      position > const Duration(seconds: 30) && !isFinished(position, duration);

  /// Starts periodic saving.
  void start() {
    _closed = false;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      if (_latest?.playing ?? false) unawaited(flush());
    });
  }

  /// Feeds the latest engine state; a play → pause transition saves.
  ///
  /// States at position zero (opening, reconnecting, stopped) keep the last
  /// real position so they never overwrite saved progress.
  void update(PlaybackState s) {
    if (_closed) return;
    final latest = _latest;
    _latest = s.position > Duration.zero || latest == null
        ? s
        : latest.copyWith(playing: s.playing);
    if (_wasPlaying && !s.playing) unawaited(flush());
    _wasPlaying = s.playing;
  }

  /// Saves the latest position now (skipped when nothing changed or before
  /// playback moved).
  Future<void> flush() async {
    final s = _latest;
    if (s == null || s.position <= Duration.zero) return;
    final entry = (s.position, s.duration);
    if (entry == _lastSaved) return;
    _lastSaved = entry;
    try {
      await save(s.position, s.duration);
    } catch (_) {
      // Storage errors must not break playback; the next tick retries.
      _lastSaved = null;
    }
  }

  /// Final save and timer stop. Later [update]s are ignored until [start].
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final saving = flush();
    _closed = true;
    _wasPlaying = false;
    await saving;
  }

  /// Saves one last time (fire and forget) and stops.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (!_closed) unawaited(flush());
    _closed = true;
  }
}
