/// Classification of M3U entries into live channels, movies and episodes,
/// plus the stable-key and URL helpers shared by the M3U adapter.
library;

import '../../core/text/normalize.dart';

/// What an M3U entry represents.
enum M3uItemKind { live, movie, episode }

/// Series name, season and episode parsed from an episode title.
typedef EpisodeMatch = ({String series, int season, int episode});

const _movieExtensions = {'mp4', 'mkv', 'avi', 'mov', 'm4v'};

final _episodeRe = RegExp(
  r'(.*?)[ ._-]*S(\d{1,2})[ ._-]*E(\d{1,3})',
  caseSensitive: false,
);
final _trailingSeparators = RegExp(r'[\s._\-|:]+$');
final _dotsOrUnderscores = RegExp(r'[._]+');
final _spaces = RegExp(r'\s+');
final _yearRe = RegExp(r'\((\d{4})\)');
final _alnum = RegExp(r'^[a-z0-9]+$');

/// [url] without its query string and fragment.
String stripQuery(String url) {
  var end = url.length;
  final q = url.indexOf('?');
  if (q >= 0) end = q;
  final h = url.indexOf('#');
  if (h >= 0 && h < end) end = h;
  return url.substring(0, end);
}

/// Path part of [url] (no scheme, authority, query or fragment).
String urlPath(String url) {
  final s = stripQuery(url);
  final scheme = s.indexOf('://');
  if (scheme < 0) return s;
  final slash = s.indexOf('/', scheme + 3);
  return slash < 0 ? '' : s.substring(slash);
}

/// Lower-cased file extension of the URL path (`mkv`), or null.
String? urlExtension(String url) {
  final path = urlPath(url);
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot < path.lastIndexOf('/')) return null;
  final ext = path.substring(dot + 1).toLowerCase();
  if (ext.isEmpty || ext.length > 5 || !_alnum.hasMatch(ext)) return null;
  return ext;
}

/// Last non-empty path segment of [url], URL-decoded when possible.
String lastPathSegment(String url) {
  final segments = urlPath(url).split('/');
  for (var i = segments.length - 1; i >= 0; i--) {
    final s = segments[i].trim();
    if (s.isEmpty) continue;
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }
  return '';
}

/// True when [url] looks like an HLS playlist.
bool looksLikeHls(String url) {
  if (urlPath(url).toLowerCase().endsWith('.m3u8')) return true;
  return url.toLowerCase().contains('m3u8');
}

/// Classifies an entry by its URL: `/movie/` and common file extensions are
/// movies, `/series/` is an episode, everything else (and radio) is live.
M3uItemKind classifyM3uUrl(String url, {bool isRadio = false}) {
  if (isRadio) return M3uItemKind.live;
  final path = urlPath(url).toLowerCase();
  if (path.contains('/movie/')) return M3uItemKind.movie;
  if (path.contains('/series/')) return M3uItemKind.episode;
  final ext = urlExtension(url);
  if (ext != null &&
      _movieExtensions.contains(ext) &&
      !path.contains('/live/')) {
    return M3uItemKind.movie;
  }
  return M3uItemKind.live;
}

/// Extracts series name, season and episode from titles such as
/// `Show Name S01E02`, `Show.Name.s1.e2` or `Show - S01 E002`.
///
/// Returns null when there is no `SxxEyy` marker or no series name.
EpisodeMatch? matchEpisode(String title) {
  final m = _episodeRe.firstMatch(title);
  if (m == null) return null;
  var name = m[1]!.trim().replaceFirst(_trailingSeparators, '');
  if (!name.contains(' ')) {
    name = name.replaceAll(_dotsOrUnderscores, ' ').trim();
  }
  name = name.replaceAll(_spaces, ' ');
  if (name.isEmpty) return null;
  return (series: name, season: int.parse(m[2]!), episode: int.parse(m[3]!));
}

/// Stable series key derived from the series name.
String seriesKeyFor(String seriesName) =>
    'series:${normalizeForSearch(seriesName)}';

/// Stable item key before collision handling: the URL without its query, or
/// `lower(tvg-id)|name` when that is empty.
String baseStableKey(String url, {String? tvgId, required String name}) {
  final key = stripQuery(url).trim();
  if (key.isNotEmpty) return key;
  return '${(tvgId ?? '').toLowerCase()}|$name';
}

/// Release year written as `(2019)` in a title, or null.
int? extractYear(String title) {
  for (final m in _yearRe.allMatches(title).toList().reversed) {
    final y = int.parse(m[1]!);
    if (y >= 1900 && y <= 2100) return y;
  }
  return null;
}
