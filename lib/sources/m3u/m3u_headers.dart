/// Request-header helpers for M3U entries and `#EXTM3U` attribute values.
///
/// Playlists attach headers in several ways: a `url|User-Agent=..&Referer=..`
/// suffix, `#EXTVLCOPT:http-user-agent=..`, `#EXTHTTP:{json}`,
/// `#KODIPROP:inputstream.adaptive.stream_headers=..` and attributes such as
/// `http-user-agent="..."` on `#EXTINF`. Names are canonicalised so later
/// sources override earlier ones regardless of case.
library;

import 'dart:convert';

/// Canonical spelling of an HTTP header name (`user-agent` -> `User-Agent`,
/// `referrer` -> `Referer`, `x-foo` -> `X-Foo`).
String canonicalHeaderName(String name) {
  final lower = name.trim().toLowerCase();
  switch (lower) {
    case 'user-agent' || 'useragent':
      return 'User-Agent';
    case 'referer' || 'referrer':
      return 'Referer';
  }
  final parts = lower.split('-');
  for (var i = 0; i < parts.length; i++) {
    final p = parts[i];
    if (p.isNotEmpty) parts[i] = p[0].toUpperCase() + p.substring(1);
  }
  return parts.join('-');
}

/// Copies [from] into [into] with canonical names; later values win. Blank
/// values are ignored so they never mask an earlier User-Agent or Referer.
void mergeHeaders(Map<String, String> into, Map<String, String> from) {
  from.forEach((k, v) {
    final name = canonicalHeaderName(k);
    if (name.isNotEmpty && v.trim().isNotEmpty) into[name] = v;
  });
}

/// Splits `url|Name=value&Name2=value2` into the bare URL and its headers.
///
/// Names may carry a leading `!` (Kodi syntax) and any case; values are
/// URL-decoded when possible.
({String url, Map<String, String> headers}) splitPipeHeaders(String line) {
  final bar = line.indexOf('|');
  if (bar < 0) return (url: line, headers: const {});
  return (
    url: line.substring(0, bar).trim(),
    headers: parseHeaderPairs(line.substring(bar + 1)),
  );
}

final _pairSeparator = RegExp('[&|]');

/// Parses `Name=value&Name2=value2` (also `|`-separated) into headers.
/// Pairs with a blank value are dropped.
Map<String, String> parseHeaderPairs(String input) {
  final out = <String, String>{};
  for (final part in input.split(_pairSeparator)) {
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    var name = part.substring(0, eq).trim();
    while (name.startsWith('!')) {
      name = name.substring(1);
    }
    final value = _decode(part.substring(eq + 1).trim()).trim();
    if (name.isEmpty || value.isEmpty) continue;
    out[canonicalHeaderName(name)] = value;
  }
  return out;
}

String _decode(String v) {
  if (!v.contains('%')) return v;
  try {
    return Uri.decodeComponent(v);
  } catch (_) {
    return v; // Invalid percent-encoding or UTF-8: keep the raw value.
  }
}

String _unquote(String v) {
  final t = v.trim();
  if (t.length >= 2) {
    final q = t[0];
    if ((q == '"' || q == "'") && t.endsWith(q)) {
      return t.substring(1, t.length - 1);
    }
  }
  return t;
}

/// Header named by an `#EXTVLCOPT` / `#EXTINF` option such as
/// `http-user-agent`, or null when the option is not a header.
String? headerForOption(String option) {
  switch (option.trim().toLowerCase()) {
    case 'http-user-agent' || 'user-agent':
      return 'User-Agent';
    case 'http-referrer' || 'http-referer' || 'referrer' || 'referer':
      return 'Referer';
    case 'http-origin' || 'origin':
      return 'Origin';
    case 'http-cookie' || 'cookie':
      return 'Cookie';
  }
  return null;
}

/// Parses the body of `#EXTVLCOPT:name=value`; null if not a header option.
MapEntry<String, String>? parseVlcOpt(String body) {
  final eq = body.indexOf('=');
  if (eq <= 0) return null;
  final name = headerForOption(body.substring(0, eq));
  if (name == null) return null;
  final value = _unquote(body.substring(eq + 1)).trim();
  return value.isEmpty ? null : MapEntry(name, value);
}

/// Parses the body of `#EXTHTTP:{"User-Agent":"..",...}`. Invalid JSON yields
/// an empty map; blank values are dropped.
Map<String, String> parseExtHttp(String body) {
  final out = <String, String>{};
  try {
    final decoded = jsonDecode(body.trim());
    if (decoded is Map) {
      decoded.forEach((k, v) {
        if (k is String && (v is String || v is num || v is bool)) {
          final value = '$v'.trim();
          final name = canonicalHeaderName(k);
          if (name.isNotEmpty && value.isNotEmpty) out[name] = value;
        }
      });
    }
  } on FormatException {
    // Ignore malformed JSON; the entry still plays without these headers.
  }
  return out;
}

const _kodiHeaderProps = {
  'inputstream.adaptive.stream_headers',
  'inputstream.adaptive.manifest_headers',
  'inputstream.adaptive.common_headers',
};

/// Headers carried by a `#KODIPROP` line (`inputstream.adaptive.*_headers`),
/// or an empty map for any other property.
Map<String, String> parseKodiPropHeaders(String body) {
  final eq = body.indexOf('=');
  if (eq <= 0) return const {};
  final key = body.substring(0, eq).trim().toLowerCase();
  if (!_kodiHeaderProps.contains(key)) return const {};
  return parseHeaderPairs(body.substring(eq + 1));
}

/// Splits a comma-separated guide URL list, trimming and dropping blanks.
List<String> splitUrlList(String? value) {
  if (value == null) return const [];
  return [
    for (final part in value.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

/// Largest `tvg-shift` accepted, in hours; larger values are garbage.
const kMaxTvgShiftHours = 48;

/// `tvg-shift` in hours (may be fractional, `+2`, `-3.5`, `5,5`) to minutes.
/// Null when missing, malformed, non-finite or beyond [kMaxTvgShiftHours].
int? parseShiftMinutes(String? value) {
  if (value == null) return null;
  final hours = double.tryParse(value.trim().replaceAll(',', '.'));
  if (hours == null || !hours.isFinite || hours.abs() > kMaxTvgShiftHours) {
    return null;
  }
  return (hours * 60).round();
}
