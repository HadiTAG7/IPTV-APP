/// A playback position as `m:ss`, or `h:mm:ss` from one hour on.
String formatPlayPosition(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// Whole minutes of a runtime in seconds, at least 1; null when unknown.
int? runtimeMinutes(int? seconds) {
  if (seconds == null || seconds <= 0) return null;
  final minutes = (seconds / 60).round();
  return minutes < 1 ? 1 : minutes;
}

/// The release year from [year], else from the start of a date such as
/// `2019-05-01`.
int? releaseYear(int? year, String? releaseDate) {
  if (year != null && year > 0) return year;
  final match = RegExp(r'^\s*(\d{4})').firstMatch(releaseDate ?? '');
  final parsed = match == null ? null : int.tryParse(match.group(1)!);
  return parsed != null && parsed > 1800 ? parsed : null;
}

/// A 0-10 rating with one decimal ("7.5"), or null when unrated.
String? formatRating(double? rating) =>
    rating == null || rating <= 0 ? null : rating.toStringAsFixed(1);
