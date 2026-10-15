import 'dart:collection';

import '../net/redact.dart';
import '../time/clock.dart';

/// In-memory log of the most recent [capacity] lines for Diagnostics.
///
/// Every line goes through [redact] (plus any [addSecret] values) before it
/// is stored, so URLs with credentials, Xtream path segments and known
/// passwords never reach the buffer. Multi-line messages (stack traces) are
/// split into one entry per line. Nothing is written to disk.
///
/// The app uses [RingLog.instance]; tests and widgets can inject their own.
class RingLog {
  RingLog({this.capacity = defaultCapacity, this._clock = const SystemClock()})
    : assert(capacity > 0);

  static const defaultCapacity = 500;

  /// Shared log used by bootstrap error hooks and services.
  static RingLog instance = RingLog();

  final int capacity;
  final Clock _clock;
  final _lines = ListQueue<String>();
  final _secrets = <String>{};

  /// Masks [secret] (for example a password) in every later line.
  /// Values shorter than 3 characters are ignored, as in [redact].
  void addSecret(String? secret) {
    if (secret != null && secret.length >= 3) _secrets.add(secret);
  }

  /// Appends `<UTC time> <LEVEL> <message>`, redacted.
  void log(String level, String msg) {
    final stamp = _clock.now().toUtc().toIso8601String();
    final tag = level.trim().toUpperCase();
    final text = redact(msg, secrets: _secrets);
    final parts = text.split('\n');
    for (final (i, part) in parts.indexed) {
      final line = part.trimRight();
      if (i > 0 && line.isEmpty) continue;
      _add(i == 0 ? '$stamp $tag $line' : '  $line');
    }
  }

  void debug(String msg) => log('debug', msg);

  void info(String msg) => log('info', msg);

  void warn(String msg) => log('warn', msg);

  /// Logs [msg] with an optional error and stack trace (first 20 frames).
  void error(String msg, [Object? error, StackTrace? stack]) {
    final buffer = StringBuffer(msg);
    if (error != null) buffer.write(': $error');
    if (stack != null) {
      final frames = stack.toString().split('\n').where((l) => l.isNotEmpty);
      for (final frame in frames.take(20)) {
        buffer.write('\n$frame');
      }
    }
    log('error', buffer.toString());
  }

  void _add(String line) {
    _lines.addLast(line);
    while (_lines.length > capacity) {
      _lines.removeFirst();
    }
  }

  /// Stored lines, oldest first.
  List<String> get lines => List.unmodifiable(_lines);

  int get length => _lines.length;

  void clear() => _lines.clear();

  /// The last [last] lines (all by default) as one text block for reports.
  String dump({int? last}) {
    final count = last == null ? _lines.length : last.clamp(0, _lines.length);
    return _lines.skip(_lines.length - count).join('\n');
  }
}
