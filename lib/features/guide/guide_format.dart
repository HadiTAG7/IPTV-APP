// Time and date text of the guide, in the device's time zone. Arabic uses
// Western digits, matching the remote's keys: Flutter's own `ar` date
// symbols (loaded by the Material localizations) would print Arabic-Indic
// digits, so every format here turns native digits off.
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../epg/epg_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Clock times: 24-hour when the device asks for it, else the locale's
/// default (`8:30 PM`, `8:30 م`), always with Western digits.
DateFormat guideTimeFormat(BuildContext context) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final format = MediaQuery.alwaysUse24HourFormatOf(context)
      ? DateFormat.Hm(locale)
      : DateFormat.jm(locale);
  return format..useNativeDigits = false;
}

bool _isEasternDigit(int unit) =>
    (unit >= 0x0660 && unit <= 0x0669) || (unit >= 0x06F0 && unit <= 0x06F9);

/// [text] with Arabic-Indic and Persian digits replaced by Western ones
/// (for localized messages that format dates themselves).
String westernDigits(String text) {
  if (!text.codeUnits.any(_isEasternDigit)) return text;
  return String.fromCharCodes([
    for (final unit in text.codeUnits)
      _isEasternDigit(unit)
          ? 0x30 + unit - (unit >= 0x06F0 ? 0x06F0 : 0x0660)
          : unit,
  ]);
}

/// "Guide updated (date)" with Western digits.
String guideUpdatedText(AppLocalizations l10n, DateTime updatedAt) =>
    westernDigits(l10n.guideUpdated(updatedAt.toLocal()));

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Local midnight starting the day of [t] (as UTC), and the next one.
({DateTime start, DateTime end}) localDayOf(DateTime t, {int offset = 0}) {
  final l = t.toLocal();
  return (
    start: DateTime(l.year, l.month, l.day + offset).toUtc(),
    end: DateTime(l.year, l.month, l.day + offset + 1).toUtc(),
  );
}

/// "Today", "Tomorrow" or a short date for the local day of [t].
String guideDayLabel(
  AppLocalizations l10n,
  String locale,
  DateTime t,
  DateTime now,
) {
  final day = _day(t.toLocal());
  final today = _day(now.toLocal());
  if (day == today) return l10n.guideToday;
  if (day == DateTime(today.year, today.month, today.day + 1)) {
    return l10n.guideTomorrow;
  }
  return (DateFormat.MMMEd(locale)..useNativeDigits = false).format(day);
}

/// `20:00 – 21:30` (local times).
String guideTimeRange(DateFormat format, DateTime start, DateTime stop) =>
    '${format.format(start.toLocal())} – ${format.format(stop.toLocal())}';

/// The time line of a programme: its times, its day when that is not
/// today, and the minutes left while it is on.
String guideProgrammeTimes(
  AppLocalizations l10n,
  String locale,
  DateFormat format,
  EpgProgramme p,
  DateTime now,
) {
  final parts = [guideTimeRange(format, p.start, p.stop)];
  final day = guideDayLabel(l10n, locale, p.start, now);
  if (day != l10n.guideToday) parts.add(day);
  if (p.isOnAt(now)) {
    parts.add(l10n.guideMinutesLeft(p.stop.difference(now).inMinutes));
  }
  return parts.join(' · ');
}

/// How far [now] is into [p], 0..1.
double guideProgress(EpgProgramme p, DateTime now) {
  final total = p.stop.difference(p.start).inSeconds;
  if (total <= 0) return 0;
  return (now.difference(p.start).inSeconds / total).clamp(0.0, 1.0);
}
