import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/time/clock.dart';
import '../engine/player_engine.dart';

/// Backoff between reconnect attempts: 1, 2, 4, 8, 16, 30, 30, 30 s.
const kReconnectBackoff = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 16),
  Duration(seconds: 30),
  Duration(seconds: 30),
  Duration(seconds: 30),
];

/// Why a reconnect was scheduled.
enum ReconnectReason { error, ended, buffering, stalled }

/// What the reconnect banner shows.
sealed class ReconnectStatus {
  const ReconnectStatus();

  static const idle = ReconnectIdle();
}

final class ReconnectIdle extends ReconnectStatus {
  const ReconnectIdle();

  @override
  bool operator ==(Object other) => other is ReconnectIdle;

  @override
  int get hashCode => (ReconnectIdle).hashCode;

  @override
  String toString() => 'ReconnectIdle';
}

/// Attempt [attempt] of [maxAttempts] runs after [delay] (or immediately once
/// the network returns when [paused]).
final class ReconnectWaiting extends ReconnectStatus {
  const ReconnectWaiting({
    required this.attempt,
    required this.maxAttempts,
    required this.delay,
    required this.reason,
    this.paused = false,
  });

  final int attempt;
  final int maxAttempts;
  final Duration delay;
  final ReconnectReason reason;

  /// Offline: the attempt waits for [ReconnectWatchdog.resume].
  final bool paused;

  ReconnectWaiting copyWith({bool? paused}) => ReconnectWaiting(
    attempt: attempt,
    maxAttempts: maxAttempts,
    delay: delay,
    reason: reason,
    paused: paused ?? this.paused,
  );

  @override
  bool operator ==(Object other) =>
      other is ReconnectWaiting &&
      other.attempt == attempt &&
      other.maxAttempts == maxAttempts &&
      other.delay == delay &&
      other.reason == reason &&
      other.paused == paused;

  @override
  int get hashCode => Object.hash(attempt, maxAttempts, delay, reason, paused);

  @override
  String toString() =>
      'ReconnectWaiting($attempt/$maxAttempts, $delay, $reason'
      '${paused ? ', paused' : ''})';
}

/// All attempts failed; the UI offers a manual retry.
final class ReconnectGaveUp extends ReconnectStatus {
  const ReconnectGaveUp(this.attempts);

  final int attempts;

  @override
  bool operator ==(Object other) =>
      other is ReconnectGaveUp && other.attempts == attempts;

  @override
  int get hashCode => Object.hash(ReconnectGaveUp, attempts);

  @override
  String toString() => 'ReconnectGaveUp($attempts)';
}

/// Detects dead streams and reopens them with exponential backoff.
///
/// Feed it with [onState] and [onEvent]. Triggers: a fatal [ErrorEvent], an
/// [EndedEvent] on live, buffering longer than [bufferingLimit], or a position
/// that does not move for [stallLimit] while playing. After [maxAttempts]
/// failed attempts it gives up; [stableReset] of healthy playback clears the
/// counter. Engine-neutral and timer driven (works under `fake_async`).
class ReconnectWatchdog {
  ReconnectWatchdog({
    required this.reconnect,
    this.onGiveUp,
    this._clock = const SystemClock(),
    this.backoff = kReconnectBackoff,
    this.maxAttempts = 8,
    this.bufferingLimit = const Duration(seconds: 12),
    this.stallLimit = const Duration(seconds: 15),
    this.stableReset = const Duration(seconds: 60),
    this.tick = const Duration(seconds: 1),
  }) : assert(backoff.isNotEmpty);

  /// Fully stops and reopens the stream; [attempt] is 1-based.
  final Future<void> Function(int attempt) reconnect;
  final VoidCallback? onGiveUp;
  final List<Duration> backoff;
  final int maxAttempts;
  final Duration bufferingLimit;
  final Duration stallLimit;
  final Duration stableReset;
  final Duration tick;
  final Clock _clock;

  final _status = ValueNotifier<ReconnectStatus>(ReconnectStatus.idle);

  bool _watching = false;
  bool _isLive = false;
  bool _paused = false;
  bool _resumePending = false;
  int _attempts = 0;
  Timer? _ticker;
  Timer? _retryTimer;

  DateTime? _bufferingSince;
  DateTime? _progressAt;
  DateTime? _stableSince;
  PlaybackState? _last;

  ValueListenable<ReconnectStatus> get status => _status;

  /// Attempts made since the last reset.
  int get attempts => _attempts;
  bool get isWatching => _watching;
  bool get isPaused => _paused;

  /// Starts monitoring a new item. Resets the attempt counter.
  void watch({required bool isLive}) {
    _cancelTimers();
    _watching = true;
    _isLive = isLive;
    _attempts = 0;
    _resumePending = false;
    _last = null;
    _resetMonitors();
    _status.value = ReconnectStatus.idle;
    _ticker = Timer.periodic(tick, (_) => _onTick());
  }

  /// Stops monitoring and forgets any pending attempt.
  void cancel() {
    _cancelTimers();
    _watching = false;
    _resumePending = false;
    _attempts = 0;
    _resetMonitors();
    _status.value = ReconnectStatus.idle;
  }

  void onState(PlaybackState s) {
    if (!_watching) return;
    final now = _clock.now();
    if (s.buffering) {
      _bufferingSince ??= now;
    } else {
      _bufferingSince = null;
    }
    if (!s.playing) {
      _progressAt = null;
    } else if (s.position != _last?.position || _progressAt == null) {
      _progressAt = now;
    }
    _last = s;
    if (s.playing && !s.buffering && s.hasFirstFrame) {
      _stableSince ??= now;
    } else {
      _stableSince = null;
    }
  }

  void onEvent(EngineEvent e) {
    if (!_watching) return;
    switch (e) {
      case FirstFrameEvent():
        if (_retryTimer == null && !_resumePending) {
          _status.value = ReconnectStatus.idle;
        }
      case ErrorEvent(:final fatal):
        if (fatal) report(ReconnectReason.error);
      case EndedEvent():
        if (_isLive) report(ReconnectReason.ended);
    }
  }

  /// Schedules the next attempt unless one is already pending.
  void report(ReconnectReason reason) {
    if (!_watching || _retryTimer != null || _resumePending) return;
    _resetMonitors();
    if (_attempts >= maxAttempts) {
      _giveUp();
      return;
    }
    _attempts++;
    final delay = backoff[math.min(_attempts, backoff.length) - 1];
    _status.value = ReconnectWaiting(
      attempt: _attempts,
      maxAttempts: maxAttempts,
      delay: delay,
      reason: reason,
      paused: _paused,
    );
    if (_paused) {
      _resumePending = true;
    } else {
      _retryTimer = Timer(delay, _fire);
    }
  }

  /// Network lost: holds any pending attempt and suspends the detectors.
  void pause() {
    if (_paused) return;
    _paused = true;
    if (_retryTimer != null) {
      _retryTimer!.cancel();
      _retryTimer = null;
      _resumePending = true;
    }
    final s = _status.value;
    if (s is ReconnectWaiting) _status.value = s.copyWith(paused: true);
  }

  /// Network back: a held attempt runs at once.
  void resume() {
    if (!_paused) return;
    _paused = false;
    _resetMonitors();
    final s = _status.value;
    if (s is ReconnectWaiting) _status.value = s.copyWith(paused: false);
    if (_resumePending && _watching) {
      _resumePending = false;
      _fire();
    }
  }

  void _onTick() {
    if (!_watching || _paused || _retryTimer != null || _resumePending) {
      return;
    }
    final now = _clock.now();
    final buffering = _bufferingSince;
    final progress = _progressAt;
    final stable = _stableSince;
    if (buffering != null && now.difference(buffering) > bufferingLimit) {
      report(ReconnectReason.buffering);
    } else if (progress != null && now.difference(progress) > stallLimit) {
      report(ReconnectReason.stalled);
    } else if (stable != null &&
        _attempts > 0 &&
        now.difference(stable) >= stableReset) {
      _attempts = 0;
    }
  }

  void _fire() {
    _retryTimer = null;
    _resetMonitors();
    final attempt = _attempts;
    unawaited(
      reconnect(attempt).catchError((Object _) {
        report(ReconnectReason.error);
      }),
    );
  }

  void _giveUp() {
    _cancelTimers();
    _watching = false;
    _status.value = ReconnectGaveUp(_attempts);
    onGiveUp?.call();
  }

  /// Restarts the detectors from the last known state, so a frozen engine
  /// that never reports again is still caught.
  void _resetMonitors() {
    final last = _last;
    final now = _clock.now();
    _bufferingSince = (last?.buffering ?? false) ? now : null;
    _progressAt = (last?.playing ?? false) ? now : null;
    _stableSince = null;
  }

  void _cancelTimers() {
    _ticker?.cancel();
    _ticker = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void dispose() {
    _cancelTimers();
    _watching = false;
    _status.dispose();
  }
}
