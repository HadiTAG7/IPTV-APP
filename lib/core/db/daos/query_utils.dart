/// Escapes `\`, `%` and `_` for `LIKE ... ESCAPE '\'`.
String escapeLike(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

/// Splits a list for `IN (...)` so queries stay under SQLite's variable limit.
Iterable<List<T>> chunked<T>(List<T> items, [int size = 900]) sync* {
  for (var i = 0; i < items.length; i += size) {
    yield items.sublist(i, i + size > items.length ? items.length : i + size);
  }
}

/// `?first, ?first+1, ...` placeholders for [count] values.
String sqlParams(int count, int first) =>
    [for (var i = 0; i < count; i++) '?${first + i}'].join(', ');
