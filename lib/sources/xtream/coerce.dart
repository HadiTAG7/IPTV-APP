/// Tolerant JSON field coercion for Xtream panels.
///
/// Panels disagree on types: ids and counters arrive as numbers or strings,
/// booleans as `1`/`"1"`/`true`, lists as maps keyed by index and empty
/// objects as `[]`. Every field read from a panel goes through these helpers.
library;

/// Integer from an int, integral double, numeric string or bool.
int? asInt(Object? v) {
  switch (v) {
    case int():
      return v;
    case double():
      return v.isFinite ? v.truncate() : null;
    case bool():
      return v ? 1 : 0;
    case String():
      final s = v.trim();
      if (s.isEmpty) return null;
      final i = int.tryParse(s);
      if (i != null) return i;
      final d = double.tryParse(s);
      return (d != null && d.isFinite) ? d.truncate() : null;
  }
  return null;
}

/// Double from a number or numeric string (a decimal comma is accepted).
double? asDouble(Object? v) {
  switch (v) {
    case num():
      final d = v.toDouble();
      return d.isFinite ? d : null;
    case String():
      final s = v.trim();
      if (s.isEmpty) return null;
      final d = double.tryParse(s) ?? double.tryParse(s.replaceAll(',', '.'));
      return (d != null && d.isFinite) ? d : null;
  }
  return null;
}

const _truthy = {'1', 'true', 'yes', 'y', 'on'};

/// True for `true`, non-zero numbers and `"1"`/`"true"`/`"yes"`/`"on"`.
bool asBool(Object? v) => switch (v) {
  bool() => v,
  num() => v != 0,
  String() => _truthy.contains(v.trim().toLowerCase()),
  _ => false,
};

/// A list; a map counts as the list of its values. Anything else is empty.
List<Object?> asList(Object? v) => switch (v) {
  List<Object?>() => v,
  Map<Object?, Object?>() => v.values.toList(),
  _ => const [],
};

/// A string-keyed map. `[]`, `null` and scalars become `{}`; a non-empty list
/// becomes a map keyed by index.
Map<String, Object?> asMap(Object? v) {
  switch (v) {
    case Map<String, Object?>():
      return v;
    case Map<Object?, Object?>():
      return {for (final e in v.entries) '${e.key}': e.value};
    case List<Object?>():
      return {for (var i = 0; i < v.length; i++) '$i': v[i]};
  }
  return {};
}

/// Non-empty strings from a list, a map's values or a comma-separated string.
List<String> asStrList(Object? v) {
  if (v is String) {
    return [
      for (final part in v.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }
  return [for (final e in asList(v)) ?asStr(e)];
}

/// Trimmed string, or null when empty. Numbers and bools are stringified
/// (integral doubles without `.0`); maps and lists give null.
String? asStr(Object? v) {
  final String s;
  switch (v) {
    case String():
      s = v.trim();
    case int():
      return '$v';
    case double():
      if (!v.isFinite) return null;
      return v == v.truncateToDouble() ? '${v.truncate()}' : '$v';
    case bool():
      return '$v';
    default:
      return null;
  }
  return s.isEmpty ? null : s;
}

/// UTC time from epoch seconds. Empty, zero and negative values give null.
///
/// Values large enough to be milliseconds are treated as such, and date
/// strings such as `2024-05-01 20:00:00` (read as UTC) are accepted too.
DateTime? asEpoch(Object? v) {
  if (v is bool) return null;
  final n = asInt(v);
  if (n == null) {
    if (v is! String) return null;
    final parsed = DateTime.tryParse(v.trim());
    if (parsed == null) return null;
    return parsed.isUtc
        ? parsed
        : DateTime.utc(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
          );
  }
  if (n <= 0) return null;
  final ms = n > 100000000000 ? n : n * 1000;
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}
