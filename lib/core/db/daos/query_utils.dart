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

/// Position used for "no digit" in [naturalOrderSql]; beyond any name.
const _noDigit = 1000000;

/// `ORDER BY` terms that sort the text [column] (a normalized name, so its
/// digits are Western) in natural order: the text before its first digit,
/// then the number that starts there, then the whole text. So `movie 2`
/// comes before `movie 10`, and `movie` before `movie 2`.
///
/// Plain SQL (no custom function), so every connection and isolate can run
/// it; it needs a sort, so use it on queries limited to one source.
String naturalOrderSql(String column) {
  final digits = [
    for (var d = 0; d <= 9; d++)
      "coalesce(nullif(instr($column, '$d'), 0), $_noDigit)",
  ];
  final first = 'min(${digits.join(', ')})';
  return 'substr($column, 1, $first - 1), '
      'CAST(substr($column, $first) AS INTEGER), $column';
}
