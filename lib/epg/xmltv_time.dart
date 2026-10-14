// `YYYYMMDD[hh[mm[ss[.fff]]]]` then an optional `±HHMM`, `±HH:MM` or `±HH`.
// Anything after that (`Z`, `UTC`, junk) is ignored.
final _xmltvTime = RegExp(
  r'^\s*(\d{4})(\d\d)(\d\d)(\d\d)?(\d\d)?(\d\d)?(?:[.,]\d+)?\s*'
  r'(?:([+-])(\d\d)(?::?(\d\d))?)?',
);

/// Parses an XMLTV timestamp such as `20261014193000 +0300` into UTC.
///
/// Accepts partial times (`YYYYMMDD`, `YYYYMMDDhh`, `YYYYMMDDhhmm`), fractional
/// seconds, offsets written as `+0300`, `+03:00` or `+03`, and tolerates
/// trailing junk. A missing offset means UTC. Returns `null` when the text
/// does not start with a valid date.
DateTime? parseXmltvTime(String s) {
  final m = _xmltvTime.firstMatch(s);
  if (m == null) return null;
  int part(int group) {
    final v = m.group(group);
    return v == null ? 0 : int.parse(v);
  }

  final year = part(1);
  final month = part(2);
  final day = part(3);
  final hour = part(4);
  final minute = part(5);
  final second = part(6);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (hour > 23 || minute > 59 || second > 59) return null;

  final local = DateTime.utc(year, month, day, hour, minute, second);
  // Reject dates that DateTime silently rolled over, such as 31 February.
  if (local.day != day) return null;

  final sign = m.group(7);
  if (sign == null) return local;
  final offHours = part(8);
  final offMinutes = part(9);
  if (offHours > 23 || offMinutes > 59) return null;
  final offset = offHours * 60 + offMinutes;
  return local.subtract(Duration(minutes: sign == '-' ? -offset : offset));
}
