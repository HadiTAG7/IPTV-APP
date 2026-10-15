import 'dart:async';

import 'package:flutter/foundation.dart';

/// Collects seek key presses into one target and commits a single seek
/// [commitDelay] after the last press, so a burst of Left/Right presses (or
/// a held key) never floods the engine with seeks.
class SeekAccumulator extends ChangeNotifier {
  SeekAccumulator({
    required this.onCommit,
    this.commitDelay = const Duration(milliseconds: 600),
  });

  /// Performs the seek.
  final void Function(Duration target) onCommit;
  final Duration commitDelay;

  Duration? _target;
  Timer? _timer;
  bool _disposed = false;

  /// Where the next commit seeks to, while presses are being collected.
  Duration? get target => _target;
  bool get pending => _target != null;

  /// Moves the target by [delta] from the pending target (or [current]),
  /// clamped to `[0, duration]` when the duration is known.
  void step(
    Duration delta, {
    required Duration current,
    required Duration duration,
  }) {
    final base = _target ?? current;
    var next = base + delta;
    if (next.isNegative) next = Duration.zero;
    if (duration > Duration.zero && next > duration) next = duration;
    jumpTo(next);
  }

  /// Sets the target directly (seek bar drag or tap).
  void jumpTo(Duration target) {
    if (_disposed) return;
    _target = target;
    _timer?.cancel();
    _timer = Timer(commitDelay, commit);
    notifyListeners();
  }

  /// Seeks to the pending target now.
  void commit() {
    _timer?.cancel();
    _timer = null;
    final target = _target;
    if (target == null || _disposed) return;
    _target = null;
    onCommit(target);
    notifyListeners();
  }

  /// Drops the pending target without seeking.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    if (_target == null) return;
    _target = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
