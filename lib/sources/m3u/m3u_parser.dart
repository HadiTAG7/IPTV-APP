/// Streaming parser for extended M3U playlists (IPTV flavour).
///
/// Bytes are decoded as lenient UTF-8 and split on CRLF, LF or CR. A BOM is
/// stripped and `#EXTM3U` is optional. `#EXTINF` lines are read by a
/// character scanner: quoted (double or single) and bare attribute values,
/// lower-cased keys, and a title after the first comma outside quotes.
library;

import 'dart:convert';

import 'm3u_classify.dart';
import 'm3u_headers.dart';

/// Group used when an entry has no `group-title` and no `#EXTGRP`.
const kUncategorizedGroup = 'Uncategorized';

/// One record produced while parsing: the playlist header or an entry.
sealed class M3uRecord {
  const M3uRecord();
}

/// Attributes of the `#EXTM3U` line(s), merged when a file repeats it.
class M3uHeader extends M3uRecord {
  const M3uHeader({
    this.attrs = const {},
    this.epgUrls = const [],
    this.urlLogo,
    this.tvgShiftMin = 0,
    this.catchup,
    this.catchupDays = 0,
    this.catchupSource,
  });

  /// Builds a header from lower-cased attributes. [epgUrls] overrides the
  /// list derived from `x-tvg-url`, `url-tvg` and `tvg-url`.
  factory M3uHeader.fromAttrs(
    Map<String, String> attrs, {
    List<String>? epgUrls,
  }) {
    return M3uHeader(
      attrs: Map.unmodifiable(attrs),
      epgUrls: List.unmodifiable(epgUrls ?? epgUrlsFromAttrs(attrs)),
      urlLogo: _nonEmpty(attrs['url-logo']),
      tvgShiftMin: parseShiftMinutes(attrs['tvg-shift']) ?? 0,
      catchup: _nonEmpty(attrs['catchup']),
      catchupDays: _parseInt(attrs['catchup-days'] ?? attrs['tvg-rec']) ?? 0,
      catchupSource: _nonEmpty(attrs['catchup-source']),
    );
  }

  /// All header attributes, keys lower-cased.
  final Map<String, String> attrs;

  /// Guide URLs in order of appearance, without duplicates.
  final List<String> epgUrls;

  /// Base for relative `tvg-logo` values.
  final String? urlLogo;

  /// Default guide shift for entries without their own `tvg-shift`.
  final int tvgShiftMin;
  final String? catchup;
  final int catchupDays;
  final String? catchupSource;
}

/// Guide URLs from header attributes (`x-tvg-url`, `url-tvg`, `tvg-url`).
List<String> epgUrlsFromAttrs(Map<String, String> attrs) {
  final out = <String>[];
  for (final key in const ['x-tvg-url', 'url-tvg', 'tvg-url']) {
    for (final url in splitUrlList(attrs[key])) {
      if (!out.contains(url)) out.add(url);
    }
  }
  return out;
}

/// One playable entry with fallbacks and header defaults already applied.
class M3uEntry extends M3uRecord {
  const M3uEntry({
    required this.url,
    required this.name,
    this.title = '',
    this.duration,
    this.attrs = const {},
    this.groups = const [kUncategorizedGroup],
    this.headers = const {},
    this.kodiProps = const [],
    this.tvgId,
    this.tvgName,
    this.logo,
    this.chno,
    this.isRadio = false,
    this.tvgShiftMin = 0,
    this.catchup,
    this.catchupDays = 0,
    this.catchupSource,
  });

  /// Stream URL with any `|Header=..` suffix removed.
  final String url;

  /// Display name: title, else `tvg-name`, else the last URL path segment.
  final String name;

  /// Raw title after the comma (may be empty).
  final String title;

  /// `#EXTINF` duration in seconds (`-1` for live), if present.
  final double? duration;

  /// `#EXTINF` attributes, keys lower-cased.
  final Map<String, String> attrs;

  /// `group-title` split on `;`, else the sticky `#EXTGRP`, else
  /// [kUncategorizedGroup]. Never empty.
  final List<String> groups;

  /// Request headers from attributes, `#EXTVLCOPT`, `#EXTHTTP`, `#KODIPROP`
  /// and the URL pipe suffix, with canonical names.
  final Map<String, String> headers;

  /// Raw `#KODIPROP` bodies (`key=value`).
  final List<String> kodiProps;
  final String? tvgId;
  final String? tvgName;

  /// Logo URL, resolved against the header `url-logo` when relative.
  final String? logo;

  /// Channel number from `tvg-chno` or `ch-number`.
  final int? chno;
  final bool isRadio;

  /// Guide shift in minutes (entry `tvg-shift`, else the header default).
  final int tvgShiftMin;
  final String? catchup;
  final int catchupDays;
  final String? catchupSource;
}

/// A parsed `#EXTINF` line.
class ExtInf {
  const ExtInf({this.duration, this.attrs = const {}, this.title = ''});

  final double? duration;
  final Map<String, String> attrs;
  final String title;
}

const _hash = 0x23;
const _colon = 0x3A;
const _comma = 0x2C;
const _eq = 0x3D;
const _dq = 0x22;
const _sq = 0x27;

bool _isWs(int c) => c == 0x20 || c == 0x09;

bool _isNumChar(int c) =>
    (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x2B || c == 0x2E;

int _skipWs(String s, int i) {
  while (i < s.length && _isWs(s.codeUnitAt(i))) {
    i++;
  }
  return i;
}

/// Parses the text after `#EXTINF:` (`-1 tvg-id="x" group-title="y",Title`).
ExtInf parseExtInf(String body) {
  var i = _skipWs(body, 0);
  final start = i;
  while (i < body.length && _isNumChar(body.codeUnitAt(i))) {
    i++;
  }
  final duration = i > start ? double.tryParse(body.substring(start, i)) : null;
  final attrs = <String, String>{};
  final comma = _scanAttributes(body, i, attrs, stopAtComma: true);
  final title = comma < body.length ? body.substring(comma + 1).trim() : '';
  return ExtInf(duration: duration, attrs: attrs, title: title);
}

/// Parses `key="value" key2='v' key3=bare` pairs (keys lower-cased). Bare
/// values end at whitespace, so commas are allowed in header URL lists.
Map<String, String> parseM3uAttributes(String text) {
  final out = <String, String>{};
  _scanAttributes(text, 0, out, stopAtComma: false);
  return out;
}

/// Scans attributes from [start]; returns the index of the first comma
/// outside quotes when [stopAtComma], else the end of [s].
int _scanAttributes(
  String s,
  int start,
  Map<String, String> out, {
  required bool stopAtComma,
}) {
  final n = s.length;
  var i = start;
  while (i < n) {
    var c = s.codeUnitAt(i);
    if (_isWs(c)) {
      i++;
      continue;
    }
    if (c == _comma) {
      if (stopAtComma) return i;
      i++;
      continue;
    }
    if (c == _dq || c == _sq) {
      // Stray quoted text outside a value: skip it (or just the quote).
      final close = s.indexOf(String.fromCharCode(c), i + 1);
      i = close < 0 ? i + 1 : close + 1;
      continue;
    }
    final keyStart = i;
    while (i < n) {
      c = s.codeUnitAt(i);
      if (c == _eq || c == _comma || c == _dq || c == _sq || _isWs(c)) break;
      i++;
    }
    final key = s.substring(keyStart, i).toLowerCase();
    var j = _skipWs(s, i);
    if (j >= n || s.codeUnitAt(j) != _eq) {
      if (key.isNotEmpty) out.putIfAbsent(key, () => '');
      continue;
    }
    j = _skipWs(s, j + 1);
    String value;
    final q = j < n ? s.codeUnitAt(j) : 0;
    if (q == _dq || q == _sq) {
      final close = s.indexOf(String.fromCharCode(q), j + 1);
      if (close >= 0) {
        value = s.substring(j + 1, close);
        i = close + 1;
      } else {
        // Unterminated quote: recover at the next comma so the title survives.
        final comma = stopAtComma ? s.indexOf(',', j + 1) : -1;
        final stop = comma < 0 ? n : comma;
        value = s.substring(j + 1, stop);
        i = stop;
      }
    } else {
      final valueStart = j;
      while (j < n) {
        c = s.codeUnitAt(j);
        if (_isWs(c) || (stopAtComma && c == _comma)) break;
        j++;
      }
      value = s.substring(valueStart, j);
      i = j;
    }
    if (key.isNotEmpty) out[key] = value.trim();
  }
  return n;
}

/// True when [line] starts with [tag] (upper-case, starting with `#`),
/// ignoring case, followed by end of line, `:` or whitespace.
bool _hasTag(String line, String tag) {
  if (line.length < tag.length) return false;
  for (var i = 1; i < tag.length; i++) {
    var c = line.codeUnitAt(i);
    if (c >= 0x61 && c <= 0x7A) c -= 0x20;
    if (c != tag.codeUnitAt(i)) return false;
  }
  if (line.length == tag.length) return true;
  final next = line.codeUnitAt(tag.length);
  return next == _colon || _isWs(next);
}

String _tagBody(String line, int tagLength) {
  var i = tagLength;
  if (i < line.length && line.codeUnitAt(i) == _colon) i++;
  return line.substring(i).trim();
}

String? _nonEmpty(String? v) {
  if (v == null) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

int? _parseInt(String? v) {
  final t = _nonEmpty(v);
  if (t == null) return null;
  return int.tryParse(t) ?? double.tryParse(t)?.round();
}

bool _isTrue(String? v) {
  switch (v?.trim().toLowerCase()) {
    case 'true' || '1' || 'yes':
      return true;
  }
  return false;
}

List<String> _splitGroups(String? value) {
  if (value == null) return const [];
  final out = <String>[];
  for (final part in value.split(';')) {
    final g = part.trim();
    if (g.isNotEmpty && !out.contains(g)) out.add(g);
  }
  return out;
}

final _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:');

/// Line-at-a-time M3U state machine. Feed every line to [addLine].
class M3uParser {
  final _headerAttrs = <String, String>{};
  final _epgUrls = <String>[];
  M3uHeader _header = const M3uHeader();

  ExtInf? _extinf;
  List<String> _stickyGroups = const [];
  Map<String, String>? _vlcHeaders;
  Map<String, String>? _httpHeaders;
  Map<String, String>? _kodiHeaders;
  List<String>? _kodiProps;

  /// Header attributes merged from every `#EXTM3U` line seen so far.
  M3uHeader get header => _header;

  /// Consumes one line; returns a record when the line completes one.
  M3uRecord? addLine(String raw) {
    var line = raw;
    if (line.isNotEmpty && line.codeUnitAt(0) == 0xFEFF) {
      line = line.substring(1);
    }
    line = line.trim();
    if (line.isEmpty) return null;
    if (line.codeUnitAt(0) != _hash) return _entry(line);

    if (_hasTag(line, '#EXTINF')) {
      _extinf = parseExtInf(_tagBody(line, 7));
    } else if (_hasTag(line, '#EXTM3U')) {
      return _mergeHeader(parseM3uAttributes(_tagBody(line, 7)));
    } else if (_hasTag(line, '#EXTGRP')) {
      _stickyGroups = _splitGroups(_tagBody(line, 7));
    } else if (_hasTag(line, '#EXTVLCOPT')) {
      final opt = parseVlcOpt(_tagBody(line, 10));
      if (opt != null) (_vlcHeaders ??= {})[opt.key] = opt.value;
    } else if (_hasTag(line, '#KODIPROP')) {
      final body = _tagBody(line, 9);
      (_kodiProps ??= []).add(body);
      final h = parseKodiPropHeaders(body);
      if (h.isNotEmpty) (_kodiHeaders ??= {}).addAll(h);
    } else if (_hasTag(line, '#EXTHTTP')) {
      final h = parseExtHttp(_tagBody(line, 8));
      if (h.isNotEmpty) (_httpHeaders ??= {}).addAll(h);
    }
    return null;
  }

  M3uHeader _mergeHeader(Map<String, String> attrs) {
    _headerAttrs.addAll(attrs);
    for (final url in epgUrlsFromAttrs(attrs)) {
      if (!_epgUrls.contains(url)) _epgUrls.add(url);
    }
    return _header = M3uHeader.fromAttrs(_headerAttrs, epgUrls: _epgUrls);
  }

  M3uEntry _entry(String line) {
    final split = splitPipeHeaders(line);
    final url = split.url;
    final inf = _extinf;
    final attrs = inf?.attrs ?? const <String, String>{};

    // Lowest to highest precedence.
    final headers = <String, String>{...?_kodiHeaders};
    attrs.forEach((k, v) {
      final name = headerForOption(k);
      if (name != null && v.isNotEmpty) headers[name] = v;
    });
    headers
      ..addAll(_vlcHeaders ?? const {})
      ..addAll(_httpHeaders ?? const {})
      ..addAll(split.headers);

    final tvgId = _nonEmpty(attrs['tvg-id']);
    final tvgName = _nonEmpty(attrs['tvg-name']);
    final title = inf?.title ?? '';
    var name = title.isNotEmpty ? title : (tvgName ?? lastPathSegment(url));
    if (name.isEmpty) name = url;

    final explicitGroups = _splitGroups(attrs['group-title']);
    final groups = explicitGroups.isNotEmpty
        ? explicitGroups
        : (_stickyGroups.isNotEmpty
              ? _stickyGroups
              : const [kUncategorizedGroup]);

    final entry = M3uEntry(
      url: url,
      name: name,
      title: title,
      duration: inf?.duration,
      attrs: attrs,
      groups: groups,
      headers: headers,
      kodiProps: _kodiProps ?? const [],
      tvgId: tvgId,
      tvgName: tvgName,
      logo: _resolveLogo(
        _nonEmpty(attrs['tvg-logo']) ?? _nonEmpty(attrs['logo']),
      ),
      chno: _parseInt(_nonEmpty(attrs['tvg-chno']) ?? attrs['ch-number']),
      isRadio: _isTrue(attrs['radio']),
      tvgShiftMin: parseShiftMinutes(attrs['tvg-shift']) ?? _header.tvgShiftMin,
      catchup: _nonEmpty(attrs['catchup']) ?? _header.catchup,
      catchupDays:
          _parseInt(_nonEmpty(attrs['catchup-days']) ?? attrs['tvg-rec']) ??
          _header.catchupDays,
      catchupSource:
          _nonEmpty(attrs['catchup-source']) ?? _header.catchupSource,
    );
    _extinf = null;
    _vlcHeaders = null;
    _httpHeaders = null;
    _kodiHeaders = null;
    _kodiProps = null;
    return entry;
  }

  String? _resolveLogo(String? logo) {
    final base = _header.urlLogo;
    if (logo == null || base == null) return logo;
    if (_scheme.hasMatch(logo) || logo.startsWith('//')) return logo;
    final prefix = base.endsWith('/') ? base : '$base/';
    return prefix + (logo.startsWith('/') ? logo.substring(1) : logo);
  }
}

/// Parses an M3U byte stream lazily. Errors from [bytes] pass through.
Stream<M3uRecord> parseM3uStream(Stream<List<int>> bytes) =>
    parseM3uChunks(bytes).expand((records) => records);

/// Parses an M3U byte stream, emitting the records completed by each input
/// chunk as one list. Lines are decoded and parsed synchronously per chunk,
/// which avoids one stream event per line on large playlists.
Stream<List<M3uRecord>> parseM3uChunks(Stream<List<int>> bytes) async* {
  final parser = M3uParser();
  final lines = <String>[];
  final input = const Utf8Decoder(allowMalformed: true).startChunkedConversion(
    const LineSplitter().startChunkedConversion(_LineSink(lines)),
  );

  List<M3uRecord> drain() {
    final out = <M3uRecord>[];
    for (final line in lines) {
      final record = parser.addLine(line);
      if (record != null) out.add(record);
    }
    lines.clear();
    return out;
  }

  await for (final chunk in bytes) {
    input.add(chunk);
    final records = drain();
    if (records.isNotEmpty) yield records;
  }
  input.close();
  final records = drain();
  if (records.isNotEmpty) yield records;
}

class _LineSink implements Sink<String> {
  _LineSink(this.lines);

  final List<String> lines;

  @override
  void add(String line) => lines.add(line);

  @override
  void close() {}
}

/// Parses a playlist already held in memory.
Iterable<M3uRecord> parseM3uString(String text) sync* {
  final parser = M3uParser();
  for (final line in const LineSplitter().convert(text)) {
    final record = parser.addLine(line);
    if (record != null) yield record;
  }
}

/// Quick check on the start of a file: `#EXTM3U` first, or any `#EXTINF`.
bool looksLikeM3u(String head) {
  var s = head;
  if (s.startsWith('\uFEFF')) s = s.substring(1);
  s = s.trimLeft();
  if (s.length >= 7 && s.substring(0, 7).toUpperCase() == '#EXTM3U') {
    return true;
  }
  return s.toUpperCase().contains('#EXTINF');
}
