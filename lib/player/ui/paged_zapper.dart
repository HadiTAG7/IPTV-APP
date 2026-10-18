import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/db/app_db.dart';
import '../../core/db/queries/player_ui_queries.dart';

/// A zapping list read in windows, so a 50k-channel category or source is
/// never held in memory: only its size, a few pages of keys and numbers, and
/// single lookups (position of a channel, first channel with a number).
abstract class ZapList {
  /// Number of entries, and how many have a channel number.
  Future<ZapListCount> count();

  /// Up to [limit] entries from list index [offset].
  Future<List<ZapEntry>> range(int offset, int limit);

  /// List index of [key], or null when it is not in the list.
  Future<int?> indexOf(String key);

  /// The first entry numbered [number], with its list index.
  Future<(ZapEntry, int)?> findNumber(int number);
}

/// A list the caller already holds (favourites, recent channels).
class MemoryZapList implements ZapList {
  MemoryZapList(List<ZapEntry> entries) : _entries = List.unmodifiable(entries);

  final List<ZapEntry> _entries;

  @override
  Future<ZapListCount> count() async => (
    total: _entries.length,
    numbered: _entries.where((e) => e.num != null).length,
  );

  @override
  Future<List<ZapEntry>> range(int offset, int limit) async {
    final from = offset.clamp(0, _entries.length);
    final to = (from + limit).clamp(from, _entries.length);
    return _entries.sublist(from, to);
  }

  @override
  Future<int?> indexOf(String key) async {
    final i = _entries.indexWhere((e) => e.key == key);
    return i < 0 ? null : i;
  }

  @override
  Future<(ZapEntry, int)?> findNumber(int number) async {
    final i = _entries.indexWhere((e) => e.num == number);
    return i < 0 ? null : (_entries[i], i);
  }
}

/// The channels of a live category, in list order.
class CategoryZapList implements ZapList {
  CategoryZapList(this.db, this.sourceId, this.categoryKey);

  final AppDatabase db;
  final int sourceId;
  final String categoryKey;

  @override
  Future<ZapListCount> count() => db.zapCountInCategory(sourceId, categoryKey);

  @override
  Future<List<ZapEntry>> range(int offset, int limit) =>
      db.zapRangeInCategory(sourceId, categoryKey, offset, limit);

  @override
  Future<int?> indexOf(String key) =>
      db.zapIndexInCategory(sourceId, categoryKey, key);

  @override
  Future<(ZapEntry, int)?> findNumber(int number) =>
      db.zapNumberInCategory(sourceId, categoryKey, number);
}

/// Every channel of a source, in the "All channels" order.
class AllChannelsZapList implements ZapList {
  AllChannelsZapList(this.db, this.sourceId);

  final AppDatabase db;
  final int sourceId;
  int? _numbered;

  @override
  Future<ZapListCount> count() async {
    final count = await db.zapCountAll(sourceId);
    _numbered = count.numbered;
    return count;
  }

  @override
  Future<List<ZapEntry>> range(int offset, int limit) async {
    final numbered = _numbered ?? (await count()).numbered;
    return db.zapRangeAll(sourceId, offset, limit, numbered: numbered);
  }

  @override
  Future<int?> indexOf(String key) => db.zapIndexAll(sourceId, key);

  @override
  Future<(ZapEntry, int)?> findNumber(int number) =>
      db.zapNumberAll(sourceId, number);
}

/// What the channel banner and the number badge show while zapping.
@immutable
class ZapView {
  const ZapView({
    this.item,
    this.index = -1,
    this.digits = '',
    this.pending = false,
    this.searching = false,
    this.matched = false,
  });

  /// The channel the banner points at: the target while [pending], the
  /// typed number's channel when [matched], else the channel playing. Null
  /// while the target's page is still being read.
  final ZapEntry? item;

  /// List index of [item], or -1 when it is not in the list.
  final int index;

  /// Number typed so far (empty when not entering a number).
  final String digits;

  /// True while a tune waits for the debounce or the number timeout.
  final bool pending;

  /// The typed number is being looked up.
  final bool searching;

  /// The typed number found a channel ([item]).
  final bool matched;

  @override
  bool operator ==(Object other) =>
      other is ZapView &&
      other.item == item &&
      other.index == index &&
      other.digits == digits &&
      other.pending == pending &&
      other.searching == searching &&
      other.matched == matched;

  @override
  int get hashCode =>
      Object.hash(item, index, digits, pending, searching, matched);
}

/// Channel zapping over a [ZapList] read in pages.
///
/// Same behaviour as the list-based zapper: [next]/[previous] move the
/// banner at once and tune after [debounce] (holding a key never opens the
/// channels in between, and the list wraps around); digits build a number
/// that tunes after [numberTimeout] or [commit]; a lone `0` recalls the
/// previous channel. Only [maxPages] pages of [pageSize] entries are kept,
/// and the pages around the banner are read ahead.
class PagedZapper {
  PagedZapper({
    required this.list,
    required this.onTune,
    this.onError,
    this.debounce = const Duration(milliseconds: 350),
    this.numberTimeout = const Duration(milliseconds: 1500),
    this.maxDigits = 5,
    this.pageSize = 200,
    this.maxPages = 5,
    this.readAhead = 20,
  }) : assert(pageSize > readAhead && maxPages >= 3);

  final ZapList list;

  /// Opens a channel. Called after the debounce, never for the channel
  /// already playing.
  final void Function(ZapEntry entry) onTune;

  /// A page or a lookup could not be read.
  final void Function(Object error)? onError;
  final Duration debounce;
  final Duration numberTimeout;
  final int maxDigits;
  final int pageSize;
  final int maxPages;

  /// Entries read ahead on both sides of the banner.
  final int readAhead;

  final _preview = ValueNotifier<ZapView>(const ZapView());
  final _pages = <int, List<ZapEntry>>{};
  final _loading = <int, Future<void>>{};
  final _numbers = <int, (ZapEntry, int)?>{};

  int _total = 0;
  bool _hasNumbers = false;
  bool _ready = false;
  bool _closed = false;
  ZapEntry? _tuned;
  int _tunedIndex = -1;
  (ZapEntry, int)? _previous;
  int _targetIndex = -1;
  String _digits = '';
  Future<(ZapEntry, int)?>? _numberLookup;
  Timer? _debounceTimer;
  Timer? _numberTimer;

  /// Bumped by every key; async work started before a newer key is dropped.
  int _action = 0;

  ValueListenable<ZapView> get preview => _preview;

  /// Entries in the list (0 until [init] finished).
  int get length => _total;

  /// Whether the list has channel numbers (else positions are used).
  bool get hasNumbers => _hasNumbers;

  /// The channel playing now and its list index (-1 when not in the list).
  ZapEntry? get current => _tuned;
  int get currentIndex => _tunedIndex;

  /// The channel a lone `0` returns to.
  ZapEntry? get previousEntry => _previous?.$1;

  /// Entry at [index] when its page is in memory.
  ZapEntry? entryAt(int index) {
    if (index < 0 || index >= _total) return null;
    final p = index ~/ pageSize;
    final page = _pages.remove(p);
    if (page == null) return null;
    _pages[p] = page;
    final i = index % pageSize;
    return i < page.length ? page[i] : null;
  }

  /// Reads the list size and the page of [current] (the channel playing).
  /// [previous] is the channel a lone `0` returns to (the one watched
  /// before, when this zapper replaces another).
  Future<void> init(ZapEntry current, {ZapEntry? previous}) async {
    final count = await list.count();
    if (_closed) return;
    _total = count.total;
    _hasNumbers = count.numbered > 0;
    final index = _total == 0 ? null : await list.indexOf(current.key);
    if (_closed) return;
    if (previous != null && previous.key != current.key) {
      final p = _total == 0 ? null : await list.indexOf(previous.key);
      if (_closed) return;
      _previous = (previous, p ?? -1);
    }
    final i = index ?? -1;
    // A channel outside the list starts zapping at its first entry.
    final anchor = i >= 0 ? i : 0;
    if (_total > 0) await _ensurePage(anchor ~/ pageSize);
    if (_closed) return;
    _tuned = (i >= 0 ? entryAt(i) : null) ?? current;
    _tunedIndex = i;
    _ready = true;
    _publish(item: _tuned, index: i);
    _readAround(anchor);
  }

  void next() => _step(1);

  void previous() => _step(-1);

  void _step(int delta) {
    if (_closed || !_ready || _total == 0) return;
    _action++;
    _clearNumber();
    final from = _debounceTimer != null ? _targetIndex : _tunedIndex;
    final n = _total;
    final to = from < 0
        ? (delta > 0 ? 0 : n - 1)
        : ((from + delta) % n + n) % n;
    _targetIndex = to;
    _publishTarget(to);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      unawaited(_tuneIndex(_targetIndex));
    });
    _readAround(to);
  }

  void _publishTarget(int index) {
    final item = entryAt(index);
    _publish(item: item, index: index, pending: true);
    if (item != null) return;
    final action = _action;
    unawaited(
      _ensurePage(index ~/ pageSize).then((_) {
        if (_closed || action != _action) return;
        _publish(item: entryAt(index), index: index, pending: true);
      }),
    );
  }

  /// Adds one digit (0-9) to the number being typed.
  void digit(int d) {
    assert(d >= 0 && d <= 9);
    if (_closed || !_ready) return;
    _action++;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _digits += '$d';
    final digits = _digits;
    _numberTimer?.cancel();
    _numberTimer = null;
    if (digits == '0') {
      _numberLookup = null;
      _publish(item: _tuned, index: _tunedIndex, digits: digits, pending: true);
    } else {
      final lookup = _lookupNumber(int.parse(digits));
      _numberLookup = lookup;
      _publish(
        item: _tuned,
        index: _tunedIndex,
        digits: digits,
        pending: true,
        searching: true,
      );
      final action = _action;
      unawaited(
        lookup.then((match) {
          if (_closed || action != _action) return;
          _publish(
            item: match?.$1 ?? _tuned,
            index: match?.$2 ?? _tunedIndex,
            digits: digits,
            pending: true,
            matched: match != null,
          );
        }),
      );
    }
    if (digits.length >= maxDigits) {
      commit();
    } else {
      _numberTimer = Timer(numberTimeout, commit);
    }
  }

  /// Tunes the typed number now (OK key). A lone `0` recalls.
  void commit() => unawaited(_commit());

  Future<void> _commit() async {
    _numberTimer?.cancel();
    _numberTimer = null;
    final digits = _digits;
    _digits = '';
    if (digits.isEmpty || _closed) return;
    if (digits == '0') {
      recall();
      return;
    }
    final action = ++_action;
    final lookup = _numberLookup ?? _lookupNumber(int.parse(digits));
    _numberLookup = null;
    final match = await lookup;
    if (_closed || action != _action) return;
    if (match == null) {
      _publish(item: _tuned, index: _tunedIndex);
      return;
    }
    _tune(match.$1, match.$2);
  }

  /// Drops a half-typed number (also one whose lookup is still running).
  /// False when no number was being typed.
  bool cancelNumber() {
    if (_closed || _preview.value.digits.isEmpty) return false;
    _action++;
    _clearNumber();
    _publish(item: _tuned, index: _tunedIndex);
    return true;
  }

  /// Drops a pending zap and a half-typed number (also one whose lookup is
  /// still running): nothing is tuned, the banner shows the tuned channel.
  void cancelPending() {
    if (_closed) return;
    _action++;
    _cancelPending();
    _publish(item: _tuned, index: _tunedIndex);
  }

  /// Returns to the previously watched channel.
  void recall() {
    if (_closed) return;
    _action++;
    _cancelPending();
    final previous = _previous;
    if (previous == null) {
      _publish(item: _tuned, index: _tunedIndex);
      return;
    }
    _tune(previous.$1, previous.$2);
  }

  /// Stops for good: pending tunes, number entry and reads are dropped and
  /// nothing is tuned any more. The [preview] keeps its last value.
  void close() {
    if (_closed) return;
    _closed = true;
    _action++;
    _cancelPending();
  }

  void dispose() {
    close();
    _preview.dispose();
  }

  Future<(ZapEntry, int)?> _lookupNumber(int number) async {
    if (!_hasNumbers) {
      if (number < 1 || number > _total) return null;
      final i = number - 1;
      await _ensurePage(i ~/ pageSize);
      final entry = entryAt(i);
      return entry == null ? null : (entry, i);
    }
    if (_numbers.containsKey(number)) return _numbers[number];
    try {
      final match = await list.findNumber(number);
      _numbers[number] = match;
      while (_numbers.length > 64) {
        _numbers.remove(_numbers.keys.first);
      }
      return match;
    } on Object catch (e) {
      onError?.call(e);
      return null;
    }
  }

  Future<void> _tuneIndex(int index) async {
    if (_closed || index < 0 || index >= _total) return;
    var entry = entryAt(index);
    if (entry == null) {
      final action = _action;
      await _ensurePage(index ~/ pageSize);
      if (_closed || action != _action) return;
      entry = entryAt(index);
      if (entry == null) {
        _publish(item: _tuned, index: _tunedIndex);
        return;
      }
    }
    _tune(entry, index);
  }

  void _tune(ZapEntry entry, int index) {
    final changed = entry != _tuned;
    if (changed && _tuned != null) _previous = (_tuned!, _tunedIndex);
    _tuned = entry;
    _tunedIndex = index;
    _publish(item: entry, index: index);
    _readAround(index);
    if (changed) onTune(entry);
  }

  /// Reads the pages [readAhead] entries before and after [index].
  void _readAround(int index) {
    if (index < 0 || _total == 0) return;
    final n = _total;
    for (final d in [0, -readAhead, readAhead]) {
      final i = ((index + d) % n + n) % n;
      final p = i ~/ pageSize;
      if (!_pages.containsKey(p)) unawaited(_ensurePage(p));
    }
  }

  Future<void> _ensurePage(int page) {
    if (_pages.containsKey(page)) return Future.value();
    final loading = _loading[page];
    if (loading != null) return loading;
    final future = _readPage(page);
    _loading[page] = future;
    return future;
  }

  Future<void> _readPage(int page) async {
    try {
      final entries = await list.range(page * pageSize, pageSize);
      if (_closed) return;
      _pages[page] = entries;
      while (_pages.length > maxPages) {
        _pages.remove(_pages.keys.first);
      }
    } on Object catch (e) {
      onError?.call(e);
    } finally {
      // The entry is this very future: dropping it, not waiting for it.
      unawaited(_loading.remove(page));
    }
  }

  void _publish({
    required ZapEntry? item,
    required int index,
    String digits = '',
    bool pending = false,
    bool searching = false,
    bool matched = false,
  }) {
    if (_closed) return;
    _preview.value = ZapView(
      item: item,
      index: index,
      digits: digits,
      pending: pending,
      searching: searching,
      matched: matched,
    );
  }

  void _clearNumber() {
    _numberTimer?.cancel();
    _numberTimer = null;
    _digits = '';
    _numberLookup = null;
  }

  void _cancelPending() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _clearNumber();
  }
}
