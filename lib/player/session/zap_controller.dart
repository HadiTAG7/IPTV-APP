import 'dart:async';

import 'package:flutter/foundation.dart';

/// What the channel banner shows while zapping.
@immutable
class ZapPreview<T> {
  const ZapPreview({
    required this.item,
    required this.index,
    this.digits = '',
    this.pending = false,
  });

  /// The channel the banner points at (the target while [pending]).
  final T? item;

  /// Position of [item] in the zap list, or -1 when it is not in it.
  final int index;

  /// Number typed so far (empty when not entering a number).
  final String digits;

  /// True while a tune is waiting for the debounce or number timeout.
  final bool pending;

  @override
  bool operator ==(Object other) =>
      other is ZapPreview<T> &&
      other.item == item &&
      other.index == index &&
      other.digits == digits &&
      other.pending == pending;

  @override
  int get hashCode => Object.hash(item, index, digits, pending);
}

/// List-based channel zapping for the fullscreen live player.
///
/// [next]/[previous] move the banner at once and tune after [debounce], so
/// holding a key never opens intermediate channels. Digits build a number
/// that tunes after [numberTimeout] or [commit]; a lone `0` recalls the
/// previous channel.
class ZapController<T> {
  ZapController({
    required this.onTune,
    List<T> items = const [],
    int initialIndex = -1,
    this.numberOf,
    this.debounce = const Duration(milliseconds: 350),
    this.numberTimeout = const Duration(milliseconds: 1500),
    this.maxDigits = 5,
  }) : _items = List.of(items),
       _tunedIndex = initialIndex,
       _preview = ValueNotifier(
         ZapPreview<T>(
           item: initialIndex >= 0 && initialIndex < items.length
               ? items[initialIndex]
               : null,
           index: initialIndex,
         ),
       ) {
    if (initialIndex >= 0 && initialIndex < items.length) {
      _tuned = items[initialIndex];
    }
  }

  /// Opens [item]. Called after the debounce, never for a repeat of the
  /// channel already playing.
  final void Function(T item) onTune;

  /// Channel number of an item; null uses the 1-based list position.
  final int? Function(T item)? numberOf;
  final Duration debounce;
  final Duration numberTimeout;
  final int maxDigits;

  List<T> _items;
  T? _tuned;
  int _tunedIndex;
  T? _previous;
  int _targetIndex = -1;
  String _digits = '';
  Timer? _debounceTimer;
  Timer? _numberTimer;
  final ValueNotifier<ZapPreview<T>> _preview;

  ValueListenable<ZapPreview<T>> get preview => _preview;

  /// The channel currently playing.
  T? get current => _tuned;
  int get currentIndex => _tunedIndex;

  /// The channel a lone `0` returns to.
  T? get previousChannel => _previous;
  List<T> get items => List.unmodifiable(_items);

  /// Replaces the zap list (e.g. category change), keeping the current item.
  void setItems(List<T> items, {T? current}) {
    _items = List.of(items);
    if (current != null) _tuned = current;
    final tuned = _tuned;
    _tunedIndex = tuned == null ? -1 : _items.indexOf(tuned);
    _cancelPending();
    _publish(item: tuned, index: _tunedIndex);
  }

  /// Records a channel opened outside the zapper (e.g. from the list).
  void markTuned(T item) {
    _cancelPending();
    _setTuned(item);
    _publish(item: item, index: _tunedIndex);
  }

  void next() => _step(1);

  void previous() => _step(-1);

  void _step(int delta) {
    if (_items.isEmpty) return;
    _clearNumber();
    final from = _debounceTimer != null ? _targetIndex : _tunedIndex;
    final n = _items.length;
    final to = from < 0
        ? (delta > 0 ? 0 : n - 1)
        : ((from + delta) % n + n) % n;
    _targetIndex = to;
    _publish(item: _items[to], index: to, pending: true);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      _tuneIndex(_targetIndex);
    });
  }

  /// Adds one digit (0-9) to the number being typed.
  void digit(int d) {
    assert(d >= 0 && d <= 9);
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _digits += '$d';
    final match = _digits == '0' ? null : _findNumber(int.parse(_digits));
    _publish(
      item: match?.$1 ?? _tuned,
      index: match?.$2 ?? _tunedIndex,
      digits: _digits,
      pending: true,
    );
    _numberTimer?.cancel();
    if (_digits.length >= maxDigits) {
      commit();
    } else {
      _numberTimer = Timer(numberTimeout, commit);
    }
  }

  /// Tunes the typed number now (OK key). A lone `0` recalls.
  void commit() {
    _numberTimer?.cancel();
    _numberTimer = null;
    final digits = _digits;
    _digits = '';
    if (digits.isEmpty) return;
    if (digits == '0') {
      recall();
      return;
    }
    final match = _findNumber(int.parse(digits));
    if (match == null) {
      _publish(item: _tuned, index: _tunedIndex);
      return;
    }
    _tuneIndex(match.$2);
  }

  /// Drops a half-typed number.
  void cancelNumber() {
    if (_digits.isEmpty && _numberTimer == null) return;
    _clearNumber();
    _publish(item: _tuned, index: _tunedIndex);
  }

  /// Returns to the previously watched channel.
  void recall() {
    _cancelPending();
    final prev = _previous;
    if (prev == null) {
      _publish(item: _tuned, index: _tunedIndex);
      return;
    }
    _tune(prev);
  }

  (T, int)? _findNumber(int number) {
    final numberOf = this.numberOf;
    if (numberOf == null) {
      if (number < 1 || number > _items.length) return null;
      return (_items[number - 1], number - 1);
    }
    for (var i = 0; i < _items.length; i++) {
      if (numberOf(_items[i]) == number) return (_items[i], i);
    }
    return null;
  }

  void _tuneIndex(int index) {
    if (index < 0 || index >= _items.length) return;
    _tune(_items[index]);
  }

  void _tune(T item) {
    final changed = item != _tuned;
    _setTuned(item);
    _publish(item: item, index: _tunedIndex);
    if (changed) onTune(item);
  }

  void _setTuned(T item) {
    if (item != _tuned && _tuned != null) _previous = _tuned;
    _tuned = item;
    _tunedIndex = _items.indexOf(item);
  }

  void _publish({
    required T? item,
    required int index,
    String digits = '',
    bool pending = false,
  }) {
    _preview.value = ZapPreview<T>(
      item: item,
      index: index,
      digits: digits,
      pending: pending,
    );
  }

  void _clearNumber() {
    _numberTimer?.cancel();
    _numberTimer = null;
    _digits = '';
  }

  void _cancelPending() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _clearNumber();
  }

  void dispose() {
    _cancelPending();
    _preview.dispose();
  }
}
