import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/db/app_db.dart';
import '../../core/time/clock.dart';
import '../../epg/epg_models.dart';

/// Loads now/next for channel keys at a time (`EpgDao.nowNext`).
typedef NowNextLoader = Future<Map<String, NowNext>> Function(
  List<String> keys,
  DateTime now,
);

/// Current and next programme of the channels on screen.
///
/// * [showing] is called whenever the visible rows change (scrolling, a page
///   arriving); one `IN` query runs once they have been still for [settle].
/// * Every [refreshEvery] the visible rows (and [pin]ned keys) are read
///   again, and listeners rebuild so progress bars move.
/// * Channels without guide data are remembered as such (`[]` is null but
///   [has] is true), so they are not queried on every scroll.
class NowNextStore extends ChangeNotifier {
  NowNextStore({
    required this.load,
    required this.clock,
    this.settle = const Duration(milliseconds: 150),
    this.refreshEvery = const Duration(minutes: 1),
    this.capacity = 600,
  });

  final NowNextLoader load;
  final Clock clock;
  final Duration settle;
  final Duration refreshEvery;

  /// Channels kept in memory (least recently fetched dropped first).
  final int capacity;

  final _data = <String, NowNext?>{}; // insertion order = age
  List<String> _visible = const [];
  final _pinned = <String>{};
  Timer? _settleTimer;
  Timer? _refreshTimer;
  bool _disposed = false;

  /// Queries run so far, for tests.
  @visibleForTesting
  int queries = 0;

  /// Keys of the last query, for tests.
  @visibleForTesting
  List<String> lastQuery = const [];

  /// Now/next of [key], or null when unknown or without guide data.
  NowNext? operator [](String key) => _data[key];

  /// Whether [key] has been looked up.
  bool has(String key) => _data.containsKey(key);

  /// The rows on screen are [keys]; they are queried after [settle] without
  /// further changes.
  void showing(List<String> keys) {
    if (_disposed) return;
    _visible = keys;
    _settleTimer?.cancel();
    _settleTimer = Timer(settle, () {
      final now = clock.now();
      final missing = [
        for (final k in _visible)
          if (!_data.containsKey(k) || _outdated(_data[k], now)) k,
      ];
      if (missing.isNotEmpty) unawaited(_fetch(missing));
    });
    _refreshTimer ??= Timer.periodic(refreshEvery, (_) => refresh());
  }

  /// Whether the cached [value] no longer describes [now] (its current
  /// programme ended or its next one started).
  static bool _outdated(NowNext? value, DateTime now) {
    if (value == null) return false;
    final current = value.now;
    if (current != null && !now.isBefore(current.stop)) return true;
    final next = value.next;
    return next != null && !now.isBefore(next.start);
  }

  /// Keeps [key] fresh even when it is not on screen (the info pane), and
  /// loads it now if it was never loaded.
  void pin(String? key) {
    _pinned
      ..clear()
      ..addAll([?key]);
    if (key != null && !_data.containsKey(key)) unawaited(_fetch([key]));
  }

  /// Re-reads the visible and pinned channels.
  Future<void> refresh() =>
      _fetch({..._visible, ..._pinned}.toList(), always: true);

  /// Forgets everything (after a guide refresh or a catalog change).
  void clear() {
    _data.clear();
    notifyListeners();
  }

  Future<void> _fetch(List<String> keys, {bool always = false}) async {
    if (_disposed || keys.isEmpty) {
      if (always && !_disposed) notifyListeners();
      return;
    }
    queries++;
    lastQuery = keys;
    Map<String, NowNext> result;
    try {
      result = await load(keys, clock.now());
    } on Object {
      return;
    }
    if (_disposed) return;
    for (final k in keys) {
      _data
        ..remove(k)
        ..[k] = result[k];
    }
    while (_data.length > capacity) {
      _data.remove(_data.keys.first);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _settleTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }
}

/// How far [programme] has run at [now], 0..1; null without a programme.
double? programmeProgress(EpgProgramme? programme, DateTime now) {
  if (programme == null) return null;
  final total = programme.stop.difference(programme.start).inSeconds;
  if (total <= 0) return null;
  final done = now.difference(programme.start).inSeconds;
  return (done / total).clamp(0.0, 1.0);
}
