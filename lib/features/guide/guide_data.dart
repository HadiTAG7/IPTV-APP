// Data behind the guide screens: the channel list of a filter, paged from
// the database, and the programmes of the rows around the visible ones.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/db/app_db.dart';
import '../../epg/epg_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../sources/models.dart';

/// Which channels the guide lists.
enum GuideFilterKind { favorites, all, category }

/// The guide's channel filter: favourites, all channels or one category.
@immutable
class GuideFilter {
  const GuideFilter._(this.kind, [this.categoryKey]);

  const GuideFilter.category(String key)
    : this._(GuideFilterKind.category, key);

  static const favorites = GuideFilter._(GuideFilterKind.favorites);
  static const all = GuideFilter._(GuideFilterKind.all);

  final GuideFilterKind kind;

  /// The category of [GuideFilterKind.category].
  final String? categoryKey;

  /// Display name; [categories] gives category names.
  String label(AppLocalizations l10n, List<CategoryRow> categories) =>
      switch (kind) {
        GuideFilterKind.favorites => l10n.liveFavorites,
        GuideFilterKind.all => l10n.liveAllChannels,
        GuideFilterKind.category =>
          categories.where((c) => c.key == categoryKey).firstOrNull?.name ??
              l10n.liveAllChannels,
      };

  @override
  bool operator ==(Object other) =>
      other is GuideFilter &&
      other.kind == kind &&
      other.categoryKey == categoryKey;

  @override
  int get hashCode => Object.hash(kind, categoryKey);

  @override
  String toString() => 'GuideFilter(${kind.name}${categoryKey ?? ''})';
}

/// Loads `limit` channels from `offset`.
typedef ChannelPageLoader = Future<List<ChannelRow>> Function(
  int offset,
  int limit,
);

/// A channel list read from the database in pages of [pageSize] rows, with
/// at most [maxPages] pages in memory (least recently used dropped first),
/// so even 50k-channel lists stay cheap. Listeners are told when the count
/// or a page arrives.
class GuideChannelPager extends ChangeNotifier {
  GuideChannelPager({
    required this._count,
    required this._load,
    this.pageSize = 200,
    this.maxPages = 10,
  });

  /// A list held in memory as a whole (favourites).
  factory GuideChannelPager.fixed(Future<List<ChannelRow>> Function() rows) {
    List<ChannelRow> all = const [];
    return GuideChannelPager(
      count: () async => (all = await rows()).length,
      load: (offset, limit) async => all.sublist(
        offset.clamp(0, all.length),
        (offset + limit).clamp(0, all.length),
      ),
    );
  }

  /// The channels the guide shows for [filter]. [favoriteKeys] gives the
  /// favourite order at each (re)load; unavailable favourites are skipped.
  factory GuideChannelPager.forFilter(
    AppDatabase db,
    int sourceId,
    GuideFilter filter, {
    List<String> Function()? favoriteKeys,
  }) {
    final catalog = db.catalogDao;
    return switch (filter.kind) {
      GuideFilterKind.favorites => GuideChannelPager.fixed(
        () => catalog.channelsByKeys(sourceId, favoriteKeys?.call() ?? []),
      ),
      GuideFilterKind.all => GuideChannelPager(
        count: () => catalog.totalCount(sourceId, ContentKind.live),
        load: (offset, limit) =>
            catalog.allChannelsPage(sourceId, offset, limit),
      ),
      GuideFilterKind.category => GuideChannelPager(
        count: () =>
            catalog.itemCount(sourceId, ContentKind.live, filter.categoryKey!),
        load: (offset, limit) =>
            catalog.channelsPage(sourceId, filter.categoryKey!, offset, limit),
      ),
    };
  }

  final Future<int> Function() _count;
  final ChannelPageLoader _load;
  final int pageSize;
  final int maxPages;

  /// Loaded pages, least recently used first.
  final _pages = <int, List<ChannelRow>>{};
  final _loading = <int>{};
  int? _length;
  Object? _error;
  int _epoch = 0;
  bool _disposed = false;

  /// Number of channels; null until [init] has counted them.
  int? get length => _length;

  /// The last load failure, if any.
  Object? get error => _error;

  /// Counts the channels and loads the first page.
  Future<void> init() async {
    final epoch = _epoch;
    try {
      final n = await _count();
      if (_disposed || epoch != _epoch) return;
      _length = n;
      _error = null;
      if (n > 0) await _fetch(0, epoch);
    } on Object catch (e) {
      if (_disposed || epoch != _epoch) return;
      _error = e;
    }
    if (!_disposed && epoch == _epoch) notifyListeners();
  }

  /// Forgets everything and loads again (the catalog changed).
  Future<void> reload() {
    _epoch++;
    _pages.clear();
    _loading.clear();
    return init();
  }

  /// The channel at [index], or null while its page loads (the load is
  /// started here).
  ChannelRow? rowAt(int index) {
    final n = _length;
    if (n == null || index < 0 || index >= n) return null;
    final p = index ~/ pageSize;
    final page = _pages.remove(p);
    if (page == null) {
      unawaited(_fetch(p, _epoch));
      return null;
    }
    _pages[p] = page; // most recently used last
    final i = index - p * pageSize;
    return i < page.length ? page[i] : null;
  }

  /// Starts loading the pages of rows `[from, to]`.
  void ensure(int from, int to) {
    final n = _length;
    if (n == null || n == 0) return;
    final first = from.clamp(0, n - 1) ~/ pageSize;
    final last = to.clamp(0, n - 1) ~/ pageSize;
    for (var p = first; p <= last; p++) {
      if (!_pages.containsKey(p)) unawaited(_fetch(p, _epoch));
    }
  }

  /// Keys of the loaded rows in `[from, to]`.
  List<String> keysIn(int from, int to) {
    final n = _length ?? 0;
    final keys = <String>[];
    for (var i = from < 0 ? 0 : from; i <= to && i < n; i++) {
      final page = _pages[i ~/ pageSize];
      final j = i % pageSize;
      if (page != null && j < page.length) keys.add(page[j].key);
    }
    return keys;
  }

  /// Keys of the loaded rows, in order: only pages still in memory, so not
  /// a zap list.
  List<String> loadedKeys() => keysIn(0, (_length ?? 0) - 1);

  Future<void> _fetch(int page, int epoch) async {
    if (!_loading.add(page)) return;
    try {
      final rows = await _load(page * pageSize, pageSize);
      if (_disposed || epoch != _epoch) return;
      _pages[page] = rows;
      while (_pages.length > maxPages) {
        _pages.remove(_pages.keys.first);
      }
      _error = null;
    } on Object catch (e) {
      if (_disposed || epoch != _epoch) return;
      _error = e;
    } finally {
      if (epoch == _epoch) _loading.remove(page);
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Loads the programmes of [keys] overlapping `[from, to)`.
typedef ProgrammeLoader = Future<Map<String, List<EpgProgramme>>> Function(
  List<String> keys,
  DateTime from,
  DateTime to,
);

/// Programmes of one block of rows (the visible ones plus a margin) over a
/// time range, from ONE query per block. [request] replaces the block;
/// requests made while scrolling are debounced. Listeners are told when a
/// block arrives.
class GuideProgrammeStore extends ChangeNotifier {
  GuideProgrammeStore(
    this._load, {
    this.debounce = const Duration(milliseconds: 150),
  });

  final ProgrammeLoader _load;
  final Duration debounce;

  Map<String, List<EpgProgramme>> _data = const {};
  Set<String> _keys = const {};
  DateTime? _from;
  DateTime? _to;

  /// The latest requested block (pending or delivered).
  ({Set<String> keys, DateTime from, DateTime to})? _wanted;
  Timer? _timer;
  int _request = 0;
  int _version = 0;
  Object? _error;
  bool _disposed = false;

  /// Bumped whenever a new block arrives.
  int get version => _version;

  Object? get error => _error;

  /// Programmes of [key] by start time; null when its row is not loaded.
  List<EpgProgramme>? programmesOf(String key) =>
      _keys.contains(key) ? _data[key] ?? const [] : null;

  /// Whether the latest request covers [keys] over `[from, to)`.
  bool covers(Iterable<String> keys, DateTime from, DateTime to) {
    final wanted = _wanted;
    return wanted != null &&
        !wanted.from.isAfter(from) &&
        !wanted.to.isBefore(to) &&
        wanted.keys.containsAll(keys);
  }

  /// Time range of the delivered block; null before the first one.
  ({DateTime from, DateTime to})? get range {
    final f = _from;
    final t = _to;
    return f == null || t == null ? null : (from: f, to: t);
  }

  /// Whether the delivered block covers the time range `[from, to)`.
  bool hasRange(DateTime from, DateTime to) {
    final f = _from;
    final t = _to;
    return f != null && t != null && !f.isAfter(from) && !t.isBefore(to);
  }

  /// Loads [keys] over `[from, to)` as the new block: after [debounce], or
  /// at once with [immediate].
  void request(
    List<String> keys,
    DateTime from,
    DateTime to, {
    bool immediate = false,
  }) {
    _wanted = (keys: keys.toSet(), from: from, to: to);
    _timer?.cancel();
    if (immediate) {
      unawaited(_run());
    } else {
      _timer = Timer(debounce, () => unawaited(_run()));
    }
  }

  /// Loads the current block again (the guide was refreshed).
  void reload() {
    final wanted = _wanted;
    if (wanted == null) return;
    request(wanted.keys.toList(), wanted.from, wanted.to, immediate: true);
  }

  Future<void> _run() async {
    final wanted = _wanted;
    if (wanted == null || _disposed) return;
    final id = ++_request;
    try {
      final data = await _load(wanted.keys.toList(), wanted.from, wanted.to);
      if (_disposed || id != _request) return;
      _data = data;
      _keys = wanted.keys;
      _from = wanted.from;
      _to = wanted.to;
      _error = null;
    } on Object catch (e) {
      if (_disposed || id != _request) return;
      _error = e;
      _wanted = null; // Let the next request try again.
    }
    _version++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
