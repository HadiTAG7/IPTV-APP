import 'dart:async';

import 'package:flutter/foundation.dart';

/// Loads `limit` items starting at `offset`.
typedef PageLoader<T> = Future<List<T>> Function(int offset, int limit);

/// A long list read from the database one page at a time.
///
/// [itemAt] answers from memory, or returns null and asks for the item's
/// page. Requests are collected for [debounce] and only the most recently
/// requested [maxConcurrent] pages are read, so fast scrolling through a
/// 50k-item grid does not queue a query for every page it passed. At most
/// [maxPages] pages stay in memory (least recently used dropped first).
/// Listeners are notified when a page arrives.
///
/// A page whose read failed is not asked for again until [retryBackoff]
/// has passed (doubling with each failure in a row, up to
/// [maxRetryBackoff]), [retry] or [refresh]; [error] stays set until every
/// failed page has been read.
class PagedItems<T> extends ChangeNotifier {
  PagedItems({
    required int count,
    required this._load,
    this.pageSize = 200,
    this.maxPages = 10,
    this.maxConcurrent = 3,
    this.debounce = const Duration(milliseconds: 120),
    this.retryBackoff = const Duration(seconds: 2),
    this.maxRetryBackoff = const Duration(seconds: 30),
  }) : _count = count {
    if (count > 0) unawaited(_loadPage(0));
  }

  /// Number of items in the list.
  int get count => _count;
  int _count;
  final int pageSize;
  final int maxPages;
  final int maxConcurrent;
  final Duration debounce;
  final Duration retryBackoff;
  final Duration maxRetryBackoff;
  final PageLoader<T> _load;

  // Insertion order is recency order: touched pages move to the end.
  final _pages = <int, List<T>>{};
  final _loading = <int>{};
  final _wanted = <int>{};

  /// Failures in a row per page, until the page is read.
  final _failures = <int, int>{};

  /// Failed pages waiting for their backoff; [itemAt] does not ask for them.
  final _blocked = <int, Timer>{};
  Timer? _timer;
  bool _disposed = false;
  int _loads = 0;

  /// The last load failure, cleared once every failed page has been read.
  Object? error;

  /// Pages read so far (including failed reads).
  @visibleForTesting
  int get loads => _loads;

  /// Pages held in memory.
  @visibleForTesting
  Set<int> get loadedPages => _pages.keys.toSet();

  /// Whether any page is being read or waiting to be read.
  bool get isLoading => _loading.isNotEmpty || _wanted.isNotEmpty;

  /// Whether nothing has been read yet.
  bool get isEmpty => _pages.isEmpty;

  /// The item at [index], or null while its page is not in memory (the page
  /// is then requested).
  T? itemAt(int index) {
    if (index < 0 || index >= count) return null;
    final page = index ~/ pageSize;
    final items = _pages.remove(page);
    if (items == null) {
      if (!_blocked.containsKey(page)) _request(page);
      return null;
    }
    _pages[page] = items;
    final i = index - page * pageSize;
    return i < items.length ? items[i] : null;
  }

  /// Reads the pages in memory again (after a sync), keeping their items
  /// until the new ones arrive. Failed pages may be asked for at once.
  /// [count], when given, is the list's new length: pages past it are
  /// dropped. Completes when the pages have been read.
  Future<void> refresh({int? count}) async {
    if (_disposed) return;
    if (count != null && count != _count) {
      _count = count;
      final pages = count == 0 ? 0 : (count - 1) ~/ pageSize + 1;
      _pages.removeWhere((page, _) => page >= pages);
      _wanted.removeWhere((page) => page >= pages);
      if (_pages.isEmpty && count > 0) _request(0);
    }
    // Earlier failures are stale now; pages on screen are asked for again.
    _unblockAll();
    _failures.clear();
    error = null;
    await Future.wait([
      for (final page in _pages.keys.toList())
        if (!_loading.contains(page)) _loadPage(page),
    ]);
  }

  /// The index of the first item in memory that passes [test], if any.
  int? indexWhereLoaded(bool Function(T item) test) {
    for (final MapEntry(key: page, value: items) in _pages.entries) {
      for (final (i, item) in items.indexed) {
        if (test(item)) return page * pageSize + i;
      }
    }
    return null;
  }

  /// Reads the requested pages again after a failure, without waiting for
  /// their backoff.
  void retry() {
    if (_disposed) return;
    error = null;
    _unblockAll();
    _failures.clear();
    if (_pages.isEmpty && count > 0) _request(0);
    notifyListeners();
  }

  void _unblockAll() {
    for (final timer in _blocked.values) {
      timer.cancel();
    }
    _blocked.clear();
  }

  void _block(int page) {
    final failures = _failures[page] = (_failures[page] ?? 0) + 1;
    var wait = retryBackoff * (1 << (failures - 1).clamp(0, 16));
    if (wait > maxRetryBackoff) wait = maxRetryBackoff;
    _blocked[page]?.cancel();
    _blocked[page] = Timer(wait, () {
      _blocked.remove(page);
      // Listeners rebuild; a page still on screen is asked for again.
      if (!_disposed) notifyListeners();
    });
  }

  void _request(int page) {
    if (_disposed || _loading.contains(page)) return;
    _wanted
      ..remove(page)
      ..add(page);
    _timer ??= Timer(debounce, _flush);
  }

  void _flush() {
    _timer = null;
    if (_disposed) return;
    final pages = _wanted.toList().reversed.take(maxConcurrent).toList();
    _wanted.clear();
    for (final page in pages) {
      unawaited(_loadPage(page));
    }
  }

  Future<void> _loadPage(int page) {
    _loading.add(page);
    _loads++;
    return _read(page);
  }

  Future<void> _read(int page) async {
    try {
      final items = await _load(page * pageSize, pageSize);
      if (_disposed) return;
      _pages[page] = items;
      _failures.remove(page);
      if (_failures.isEmpty) error = null;
      while (_pages.length > maxPages) {
        _pages.remove(_pages.keys.first);
      }
    } on Object catch (e) {
      if (_disposed) return;
      error = e;
      _block(page);
    } finally {
      _loading.remove(page);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _unblockAll();
    super.dispose();
  }
}
