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
class PagedItems<T> extends ChangeNotifier {
  PagedItems({
    required this.count,
    required this._load,
    this.pageSize = 200,
    this.maxPages = 10,
    this.maxConcurrent = 3,
    this.debounce = const Duration(milliseconds: 120),
  }) {
    if (count > 0) _loadPage(0);
  }

  /// Number of items in the list.
  final int count;
  final int pageSize;
  final int maxPages;
  final int maxConcurrent;
  final Duration debounce;
  final PageLoader<T> _load;

  // Insertion order is recency order: touched pages move to the end.
  final _pages = <int, List<T>>{};
  final _loading = <int>{};
  final _wanted = <int>{};
  Timer? _timer;
  bool _disposed = false;
  int _loads = 0;

  /// The last load failure, cleared by a successful load.
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
      _request(page);
      return null;
    }
    _pages[page] = items;
    final i = index - page * pageSize;
    return i < items.length ? items[i] : null;
  }

  /// Reads the pages in memory again (after a sync), keeping their items
  /// until the new ones arrive.
  void refresh() {
    if (_disposed) return;
    for (final page in _pages.keys.toList()) {
      if (!_loading.contains(page)) _loadPage(page);
    }
  }

  /// Reads the requested pages again after a failure.
  void retry() {
    error = null;
    if (_pages.isEmpty && count > 0) _request(0);
    notifyListeners();
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
      _loadPage(page);
    }
  }

  void _loadPage(int page) {
    _loading.add(page);
    _loads++;
    unawaited(_read(page));
  }

  Future<void> _read(int page) async {
    try {
      final items = await _load(page * pageSize, pageSize);
      if (_disposed) return;
      _pages[page] = items;
      error = null;
      while (_pages.length > maxPages) {
        _pages.remove(_pages.keys.first);
      }
    } on Object catch (e) {
      if (_disposed) return;
      error = e;
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
    super.dispose();
  }
}
