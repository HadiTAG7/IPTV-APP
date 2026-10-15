import 'dart:async';

import '../core/time/clock.dart';
import 'epg_models.dart';

typedef _Key = (int sourceId, String channelKey);

class _Entry {
  const _Entry(this.programmes, this.expiresAt);

  final List<EpgProgramme> programmes;
  final DateTime expiresAt;
}

/// In-memory cache of short guide listings (Xtream `get_short_epg`), the
/// fallback for channels without XMLTV data, keyed by (source, channel key).
///
/// - A listing is reused for [ttl] (15 minutes) and only while it still has
///   a programme that has not ended; programmes that have ended are left out
///   of results.
/// - Concurrent requests for one channel share a single load.
/// - A load that throws an [Exception] (network, auth, parse) yields an empty
///   list, cached for [errorTtl] so failing rows are not retried on every
///   rebuild. [Error]s are rethrown and not cached.
/// - At most [maxEntries] channels are kept; the least recently used go
///   first.
class ShortEpgCache {
  ShortEpgCache({
    this._clock = const SystemClock(),
    this.ttl = const Duration(minutes: 15),
    this.errorTtl = const Duration(minutes: 1),
    this.maxEntries = 512,
  });

  final Duration ttl;
  final Duration errorTtl;
  final int maxEntries;
  final Clock _clock;

  /// Insertion order is recency order (oldest first).
  final _entries = <_Key, _Entry>{};
  final _pending = <_Key, Future<List<EpgProgramme>>>{};

  /// Bumped by [invalidate] and [clear]; loads started before a bump are
  /// returned to their callers but not cached.
  var _epoch = 0;

  /// Channels currently cached (fresh or not yet evicted).
  int get length => _entries.length;

  /// The cached programmes of a channel that have not ended, or null when
  /// nothing fresh is cached.
  List<EpgProgramme>? peek(int sourceId, String channelKey) {
    final key = (sourceId, channelKey);
    final entry = _entries.remove(key);
    if (entry == null) return null;
    final now = _clock.now();
    if (!now.isBefore(entry.expiresAt)) return null;
    final visible = _visible(entry.programmes, now);
    // A listing whose programmes have all ended is useless: load again.
    if (visible.isEmpty && entry.programmes.isNotEmpty) return null;
    _entries[key] = entry; // Most recently used.
    return visible;
  }

  /// Cached programmes of a channel, or the result of [loader] (then cached).
  Future<List<EpgProgramme>> get(
    int sourceId,
    String channelKey,
    Future<List<EpgProgramme>> Function() loader,
  ) {
    final cached = peek(sourceId, channelKey);
    if (cached != null) return Future.value(cached);
    final key = (sourceId, channelKey);
    final pending = _pending[key];
    if (pending != null) return pending;
    final completer = Completer<List<EpgProgramme>>();
    _pending[key] = completer.future;
    unawaited(_load(key, loader, completer));
    return completer.future;
  }

  /// Drops the cached listings of [sourceId], or of one channel.
  void invalidate(int sourceId, [String? channelKey]) {
    _epoch++;
    bool hit(_Key k) =>
        k.$1 == sourceId && (channelKey == null || k.$2 == channelKey);
    _entries.removeWhere((k, _) => hit(k));
    _pending.removeWhere((k, _) => hit(k));
  }

  void clear() {
    _epoch++;
    _entries.clear();
    _pending.clear();
  }

  Future<void> _load(
    _Key key,
    Future<List<EpgProgramme>> Function() loader,
    Completer<List<EpgProgramme>> completer,
  ) async {
    final epoch = _epoch;
    try {
      final programmes = List<EpgProgramme>.unmodifiable(await loader());
      final now = _clock.now();
      if (epoch == _epoch) _put(key, _Entry(programmes, now.add(ttl)));
      completer.complete(_visible(programmes, now));
    } on Exception {
      if (epoch == _epoch) {
        _put(key, _Entry(const [], _clock.now().add(errorTtl)));
      }
      completer.complete(const []);
    } catch (error, stack) {
      completer.completeError(error, stack);
    } finally {
      if (identical(_pending[key], completer.future)) {
        unawaited(_pending.remove(key));
      }
    }
  }

  void _put(_Key key, _Entry entry) {
    _entries
      ..remove(key)
      ..[key] = entry;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  static List<EpgProgramme> _visible(
    List<EpgProgramme> programmes,
    DateTime now,
  ) => programmes.every((p) => p.stop.isAfter(now))
      ? programmes
      : List.unmodifiable(programmes.where((p) => p.stop.isAfter(now)));
}
