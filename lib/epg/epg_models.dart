// Guide models produced by the XMLTV parser and Xtream short EPG.

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
