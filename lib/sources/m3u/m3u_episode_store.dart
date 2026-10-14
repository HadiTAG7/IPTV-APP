/// Compact copy of the episodes seen during an M3U fetch, kept so
/// `M3uAdapter.seriesDetail` can answer without downloading the playlist
/// again.
///
/// Episodes are not kept as objects. Each one is encoded (varint numbers,
/// UTF-8 strings) into shared 64 KB byte pages, and a series keeps only the
/// positions of its records. The URL, title and still are stored as the part
/// that differs from the previous episode of the same series (they usually
/// share long prefixes), the key relative to the URL, and a header map equal
/// to the previous one is not repeated. A typical episode takes a few dozen
/// bytes instead of an [EpisodeData] object graph.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../models.dart';

const _pageSize = 64 * 1024;

// Record flags.
const _keyIsUrl = 1;
const _sameHeaders = 2;
const _hasDuration = 4;

/// Append-only, per-series store of [EpisodeData].
class M3uEpisodeStore {
  final _series = <String, _SeriesRecords>{};
  final _pages = <Uint8List>[];
  final _writer = _Writer();
  int _pos = 0;
  int _length = 0;

  /// Number of episodes stored.
  int get length => _length;

  /// Number of series with at least one episode.
  int get seriesCount => _series.length;

  /// Bytes allocated for encoded records.
  int get pageBytes {
    var total = 0;
    for (final p in _pages) {
      total += p.length;
    }
    return total;
  }

  bool containsSeries(String seriesKey) => _series.containsKey(seriesKey);

  void add(EpisodeData e) {
    final series = _series[e.seriesKey] ??= _SeriesRecords();
    final first = series.positions.isEmpty;
    final duration = e.durationSec;
    var flags = 0;
    if (e.url != null && e.key == e.url) flags |= _keyIsUrl;
    if (!first && _sameMap(e.headers, series.lastHeaders)) {
      flags |= _sameHeaders;
    }
    if (duration != null) flags |= _hasDuration;

    final w = _writer..reset();
    w
      ..uint(flags)
      ..sint(e.season)
      ..sint(e.number);
    if (duration != null) w.sint(duration);
    w
      ..delta(e.url, series.lastUrl)
      ..delta(e.title, series.lastTitle)
      ..delta(e.still, series.lastStill);
    if (flags & _keyIsUrl == 0) w.delta(e.key, e.url);
    w
      ..str(e.ext)
      ..str(e.plot);
    if (flags & _sameHeaders == 0) {
      w.uint(e.headers.length);
      e.headers.forEach((k, v) {
        w
          ..str(k)
          ..str(v);
      });
    }

    series.positions.add(_append(w));
    series
      ..lastUrl = e.url
      ..lastTitle = e.title
      ..lastStill = e.still
      ..lastHeaders = e.headers;
    _length++;
  }

  /// Episodes of [seriesKey] in insertion order, or null when unknown.
  List<EpisodeData>? episodesOf(String seriesKey) {
    final series = _series[seriesKey];
    if (series == null) return null;
    final out = <EpisodeData>[];
    String? url;
    String? title;
    String? still;
    var headers = const <String, String>{};
    for (final at in series.positions) {
      final r = _Reader(_pages[at >> 16], at & 0xFFFF);
      final flags = r.uint();
      final season = r.sint();
      final number = r.sint();
      final duration = flags & _hasDuration != 0 ? r.sint() : null;
      url = r.delta(url);
      title = r.delta(title);
      still = r.delta(still);
      final key = flags & _keyIsUrl != 0 ? null : r.delta(url);
      final ext = r.str();
      final plot = r.str();
      if (flags & _sameHeaders == 0) headers = r.headers();
      out.add(
        EpisodeData(
          seriesKey: seriesKey,
          key: key ?? url!,
          season: season,
          number: number,
          title: title,
          ext: ext,
          url: url,
          headers: headers,
          durationSec: duration,
          plot: plot,
          still: still,
        ),
      );
    }
    return out;
  }

  /// Drops every record.
  void clear() {
    _series.clear();
    _pages.clear();
    _pos = 0;
    _length = 0;
  }

  /// Copies the encoded record into the current page (a new one when it does
  /// not fit) and returns its position: page index << 16 | offset.
  int _append(_Writer w) {
    final n = w.length;
    if (_pages.isEmpty || _pos + n > _pages.last.length) {
      _pages.add(Uint8List(n > _pageSize ? n : _pageSize));
      _pos = 0;
    }
    _pages.last.setRange(_pos, _pos + n, w.bytes);
    final at = ((_pages.length - 1) << 16) | _pos;
    _pos += n;
    return at;
  }
}

bool _sameMap(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

class _SeriesRecords {
  final positions = <int>[];
  String? lastUrl;
  String? lastTitle;
  String? lastStill;
  Map<String, String> lastHeaders = const {};
}

/// Growable scratch buffer for one record.
class _Writer {
  Uint8List bytes = Uint8List(512);
  int length = 0;

  void reset() => length = 0;

  void _ensure(int extra) {
    final need = length + extra;
    if (need <= bytes.length) return;
    var cap = bytes.length * 2;
    while (cap < need) {
      cap *= 2;
    }
    bytes = Uint8List(cap)..setRange(0, length, bytes);
  }

  /// Unsigned LEB128.
  void uint(int v) {
    _ensure(10);
    var x = v;
    while ((x & ~0x7F) != 0) {
      bytes[length++] = (x & 0x7F) | 0x80;
      x = x >>> 7;
    }
    bytes[length++] = x;
  }

  /// Zigzag-encoded signed integer.
  void sint(int v) => uint((v << 1) ^ (v >> 63));

  /// Length + 1 (0 for null), then UTF-8 bytes.
  void str(String? s) {
    if (s == null) {
      uint(0);
      return;
    }
    final n = s.length;
    var ascii = true;
    for (var i = 0; i < n; i++) {
      if (s.codeUnitAt(i) > 0x7F) {
        ascii = false;
        break;
      }
    }
    if (ascii) {
      uint(n + 1);
      _ensure(n);
      for (var i = 0; i < n; i++) {
        bytes[length++] = s.codeUnitAt(i);
      }
      return;
    }
    final encoded = utf8.encode(s);
    uint(encoded.length + 1);
    _ensure(encoded.length);
    bytes.setRange(length, length + encoded.length, encoded);
    length += encoded.length;
  }

  /// [s] as the length of its common prefix with [base] + 1 (0 for null),
  /// then the remaining suffix.
  void delta(String? s, String? base) {
    if (s == null) {
      uint(0);
      return;
    }
    final b = base ?? '';
    final max = s.length < b.length ? s.length : b.length;
    var p = 0;
    while (p < max && s.codeUnitAt(p) == b.codeUnitAt(p)) {
      p++;
    }
    // Never split a surrogate pair between prefix and suffix.
    if (p > 0 && p < s.length && _isLeadSurrogate(s.codeUnitAt(p - 1))) p--;
    uint(p + 1);
    str(s.substring(p));
  }
}

bool _isLeadSurrogate(int c) => c >= 0xD800 && c <= 0xDBFF;

class _Reader {
  _Reader(this.bytes, this.pos);

  final Uint8List bytes;
  int pos;

  int uint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final b = bytes[pos++];
      result |= (b & 0x7F) << shift;
      if (b < 0x80) return result;
      shift += 7;
    }
  }

  int sint() {
    final z = uint();
    return (z >>> 1) ^ -(z & 1);
  }

  String? str() {
    final n = uint();
    if (n == 0) return null;
    final end = pos + n - 1;
    final s = utf8.decode(Uint8List.sublistView(bytes, pos, end));
    pos = end;
    return s;
  }

  String? delta(String? base) {
    final n = uint();
    if (n == 0) return null;
    final suffix = str()!;
    return n == 1 ? suffix : base!.substring(0, n - 1) + suffix;
  }

  Map<String, String> headers() {
    final count = uint();
    if (count == 0) return const {};
    final out = <String, String>{};
    for (var i = 0; i < count; i++) {
      final k = str()!;
      out[k] = str()!;
    }
    return Map.unmodifiable(out);
  }
}
