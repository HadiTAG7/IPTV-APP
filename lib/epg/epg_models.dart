// Guide models produced by the XMLTV parser and Xtream short EPG.

/// Literal `\r\n`, `\n` and `\r` escapes (a backslash and a letter, not
/// line breaks) that some guides leave in their text.
final _escapedBreaks = RegExp(r'(?:\\r)?\\n|\\r');
final _blankLines = RegExp(r'\n{3,}');

/// Guide [text] with literal line-break escapes turned into line breaks.
String unescapeGuideText(String text) => !text.contains(r'\')
    ? text
    : text
          .replaceAll(_escapedBreaks, '\n')
          .replaceAll(_blankLines, '\n\n')
          .trim();

class EpgChannel {
  const EpgChannel({required this.id, this.displayNames = const [], this.icon});

  /// XMLTV `channel@id`.
  final String id;
  final List<String> displayNames;
  final String? icon;
}

class EpgProgramme {
  const EpgProgramme({
    required this.channelId,
    required this.start,
    required this.stop,
    required this.title,
    this.subTitle,
    this.desc,
    this.category,
    this.icon,
  });

  /// XMLTV `programme@channel` (or Xtream `epg_channel_id`).
  final String channelId;

  /// UTC.
  final DateTime start;

  /// UTC.
  final DateTime stop;
  final String title;
  final String? subTitle;
  final String? desc;
  final String? category;
  final String? icon;

  bool isOnAt(DateTime t) => !t.isBefore(start) && t.isBefore(stop);
}
