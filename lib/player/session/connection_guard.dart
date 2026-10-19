import 'dart:async';

import '../../core/time/clock.dart';
import '../engine/player_engine.dart';

/// One stop-then-open switch, kept so a held-connection retry can replay it.
class _Switch {
  const _Switch(this.stop, this.open, this.maxConnections);

  final Future<void> Function() stop;
  final Future<void> Function() open;
  final int? maxConnections;
}

/// Keeps at most one stream connection open on single-connection panels.
///
/// Every switch runs `stop → (gap) → open`, serialized with older switches.
/// The latest request wins: a switch superseded before its open never opens.
/// An HTTP 4xx right after an open usually means the panel still holds the
/// previous connection, so it is retried after 1 s and then 2 s without being
/// reported as a stream failure. On single-connection panels any 4xx counts,
/// and so does an error without a status (ExoPlayer reports only "Source
/// error"); elsewhere 404/410 and unknown statuses go straight to fallback.
class ConnectionGuard {
  ConnectionGuard({
    this._clock = const SystemClock(),
    this.singleConnectionGap = const Duration(milliseconds: 150),
    this.heldWindow = const Duration(seconds: 3),
    this.heldRetryDelays = const [Duration(seconds: 1), Duration(seconds: 2)],
    this.stepTimeout = defaultStepTimeout,
  });

  /// The [stepTimeout] of the app's guards.
  static const defaultStepTimeout = Duration(seconds: 10);

  /// Pause between closing and opening when the panel allows 1 connection.
  final Duration singleConnectionGap;

  /// How long after an open a 4xx counts as "connection still held".
  final Duration heldWindow;
  final List<Duration> heldRetryDelays;

  /// Upper bound for one stop or open step, so a stuck engine call never
  /// blocks later switches.
  final Duration stepTimeout;
  final Clock _clock;

  int _seq = 0;
  Future<void> _tail = Future<void>.value();
  _Switch? _last;
  DateTime? _openedAt;
  int _heldRetries = 0;
  Timer? _retryTimer;

  /// True while a held-connection retry is scheduled.
  bool get retryPending => _retryTimer != null;

  /// Stops the current stream, waits [singleConnectionGap] when
  /// [maxConnections] is 1, then opens the next one.
  ///
  /// Completes with false when a newer switch superseded this one.
  Future<bool> switchTo({
    required Future<void> Function() stop,
    required Future<void> Function() open,
    int? maxConnections,
  }) {
    _cancelRetry();
    _heldRetries = 0;
    final spec = _Switch(stop, open, maxConnections);
    _last = spec;
    return _enqueue(spec);
  }

  /// Supersedes pending switches and stops, serialized after the running one.
  Future<void> stop(Future<void> Function() stop) {
    _cancelRetry();
    _last = null;
    _openedAt = null;
    final id = ++_seq;
    final run = _tail.then((_) async {
      if (id != _seq) return;
      await _step(stop);
    });
    _tail = run.catchError((Object _) {});
    return _tail;
  }

  /// Offers a fatal error to the guard. Returns true when it may be a held
  /// connection soon after an open and a retry has been scheduled (the caller
  /// should not treat it as a failure).
  bool handleError(ErrorEvent e) {
    final spec = _last;
    if (!e.fatal || spec == null) return false;
    if (!_mayBeHeld(e.httpStatus, single: spec.maxConnections == 1)) {
      return false;
    }
    if (_retryTimer != null) return true;
    final openedAt = _openedAt;
    if (openedAt == null) return false;
    if (_clock.now().difference(openedAt) > heldWindow) return false;
    if (_heldRetries >= heldRetryDelays.length) return false;
    final delay = heldRetryDelays[_heldRetries++];
    _openedAt = null;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (identical(_last, spec)) unawaited(_enqueue(spec));
    });
    return true;
  }

  static bool _mayBeHeld(int? status, {required bool single}) {
    if (status == null) return single;
    if (status < 400 || status > 499) return false;
    // 404/410 rarely clear up by waiting unless the panel allows only one
    // connection (some answer the second one with 404).
    return single || (status != 404 && status != 410);
  }

  /// Drops pending switches and retries without stopping anything.
  void cancel() {
    _cancelRetry();
    _last = null;
    _openedAt = null;
    _seq++;
  }

  void dispose() => cancel();

  Future<bool> _enqueue(_Switch spec) {
    final id = ++_seq;
    final run = _tail.then((_) => _run(id, spec));
    _tail = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<bool> _run(int id, _Switch spec) async {
    if (id != _seq) return false;
    _openedAt = null;
    await _step(spec.stop);
    if (spec.maxConnections == 1) {
      await Future<void>.delayed(singleConnectionGap);
    }
    if (id != _seq) return false;
    _openedAt = _clock.now();
    await _step(spec.open);
    return id == _seq;
  }

  Future<void> _step(Future<void> Function() action) async {
    try {
      await action().timeout(stepTimeout);
    } catch (_) {
      // A failing stop/open must not wedge the queue; engines report stream
      // errors on their event streams.
    }
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}
