// Pure helpers behind the Settings screen: guide offset stepping and
// formatting, refresh intervals, language choices and URL checks.

/// Earliest guide offset: 12 hours back.
const kMinEpgOffsetMin = -12 * 60;

/// Latest guide offset: 14 hours ahead.
const kMaxEpgOffsetMin = 14 * 60;

/// One step of the guide offset.
const kEpgOffsetStepMin = 30;

/// Guide refresh intervals offered in Settings, in hours.
const kEpgRefreshHourChoices = [3, 6, 12, 24, 48];

/// Audio and subtitle languages offered in Settings (ISO 639-1).
const kPreferredLanguageCodes = ['ar', 'en', 'fr', 'tr'];

/// [current] moved by [steps] offset steps, snapped to the 30-minute grid and
/// kept within [kMinEpgOffsetMin]..[kMaxEpgOffsetMin].
int stepEpgOffset(int current, int steps) {
  final snapped = (current / kEpgOffsetStepMin).round() * kEpgOffsetStepMin;
  return (snapped + steps * kEpgOffsetStepMin).clamp(
    kMinEpgOffsetMin,
    kMaxEpgOffsetMin,
  );
}

/// A guide offset as a signed `H:MM` value, e.g. `+1:30`, `-12:00`, `0:00`.
/// Uses ASCII signs and digits so it reads the same in every language.
String formatEpgOffset(int minutes) {
  final sign = minutes > 0
      ? '+'
      : minutes < 0
      ? '-'
      : '';
  final abs = minutes.abs();
  final mm = (abs % 60).toString().padLeft(2, '0');
  return '$sign${abs ~/ 60}:$mm';
}

/// Refresh-interval choices with [current] included (and sorted in) when a
/// saved value is not one of [kEpgRefreshHourChoices].
List<int> epgRefreshChoicesWith(int current) =>
    {...kEpgRefreshHourChoices, current}.toList()..sort();

/// Language choices with [current] appended when it is not one of
/// [kPreferredLanguageCodes].
List<String> languageChoicesWith(String current) => [
  ...kPreferredLanguageCodes,
  if (!kPreferredLanguageCodes.contains(current)) current,
];

/// The trimmed [input] when it is an absolute http(s) URL with a host, else
/// null.
String? parseGuideUrl(String input) {
  final text = input.trim();
  if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  return text;
}
