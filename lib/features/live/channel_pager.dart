import 'dart:async';

import 'package:flutter/foundation.dart';

import 'channel_source.dart';
import 'live_models.dart';

/// Index range `[first, last]` of the rows on screen.
typedef RowWindow = ({int first, int last});

/// Pages a [ChannelListSource] for a lazy list: [entryAt] answers from
/// loaded pages of [pageSize] rows and asks for missing ones.
///
/// * Missing pages are loaded once requests have been quiet for [loadDelay]
///   (the first load is immediate), and only those near [window], so a fast
///   fling never queries the pages it flew past.
/// * At most [maxPages] pages stay in memory (least recently used first
///   out; pages on screen are never dropped).
/// * [reset] re-reads the source after a data change while still showing
///   the old rows, so the list never flickers to placeholders.
class ChannelPager extends ChangeNotifier {
  ChannelPager(
    this.source,
    this._length, {
    this.pageSize = 200,
    this.maxPages = 10,
    this.loadDelay = const Duration(milliseconds: 120),
    this.window,
    this.onError,
  });

  final ChannelListSource source;
  final int pageSize;
  final int maxPages;
  final Duration loadDelay;

  /// The rows on screen now, or null when unknown (no filtering).
  final RowWindow? Function()? window;

  /// Called when a page fails to load (the page stays missing).
  final void Function(Object error, StackTrace stack)? onError;

  int _length;
  final _pages = <int, List<LiveEntry>>{}; // insertion order = LRU order
  final _stale = <int>{};
  final _wanted = <int>{};
  Timer? _timer;
  bool _loading = false;
  bool _loadedOnce = false;
  bool _disposed = false;
  int _epoch = 0;

  /// Number of rows.
  int get length => _length;

  /// Pages held in memory, for tests.
  @visibleForTesting
  Set<int> get loadedPages => _pages.keys.toSet();

  /// Page queries run so far, for tests.
  @visibleForTesting
  int loadCount = 0;

  /// The entry at [index], or null while its page is loading.
  LiveEntry? entryAt(int index) {
    if (index < 0 || index >= _length) return null;
    final p = index ~/ pageSize;
    final page = _pages.remove(p);
    if (page == null) {
      _want(p);
      return null;
    }
    _pages[p] = page; // most recently used
    if (_stale.contains(p)) _want(p);
    final i = index - p * pageSize;
    return i < page.length ? page[i] : null;
  }

  /// Re-reads the source after its data changed; [length] is the new row
  /// count. Old rows stay visible until their page is reloaded.
  void reset(int length) {
    _epoch++;
    _length = length;
    _stale.addAll(_pages.keys);
    _wanted.clear();
    _loading = false;
    notifyListeners();
  }

  void _want(int page) {
    if (!_wanted.add(page)) return;
    _timer?.cancel();
    _timer = Timer(_loadedOnce ? loadDelay : Duration.zero, _pump);
  }

  ({int first, int last})? _pageWindow() {
    final w = window?.call();
    if (w == null) return null;
    const margin = 20;
    return (
      first: (w.first - margin).clamp(0, _length) ~/ pageSize,
      last: (w.last + margin).clamp(0, _length) ~/ pageSize,
    );
  }

  Future<void> _pump() async {
    if (_loading || _disposed) return;
    final near = _pageWindow();
    final targets = [
      for (final p in _wanted)
        if (near == null || (p >= near.first && p <= near.last)) p,
    ]..sort();
    _wanted.clear();
    if (targets.isEmpty) return;
    _loading = true;
    final epoch = _epoch;
    for (final p in targets) {
      if (_pages.containsKey(p) && !_stale.contains(p)) continue;
      List<LiveEntry> rows;
      try {
        rows = await source.page(p * pageSize, pageSize);
      } on Object catch (e, st) {
        if (_disposed || epoch != _epoch) return;
        onError?.call(e, st);
        continue;
      }
      if (_disposed || epoch != _epoch) return;
      loadCount++;
      _loadedOnce = true;
      _pages.remove(p);
      _pages[p] = rows;
      _stale.remove(p);
      _evict(near);
      notifyListeners();
    }
    _loading = false;
    if (_wanted.isNotEmpty && !_disposed) {
      _timer?.cancel();
      _timer = Timer(Duration.zero, _pump);
    }
  }

  void _evict(({int first, int last})? near) {
    while (_pages.length > maxPages) {
      final victim = _pages.keys.firstWhere(
        (p) => near == null || p < near.first || p > near.last,
        orElse: () => -1,
      );
      if (victim < 0) return;
      _pages.remove(victim);
      _stale.remove(victim);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
