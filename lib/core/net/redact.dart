/// Removes credentials from URLs and free text before logging or display.
///
/// Xtream puts the username and password in query strings
/// (`?username=u&password=p`) and in path segments
/// (`/live/u/p/1.ts`, `/movie/u/p/2.mkv`, `/series/u/p/3.mp4`,
/// `/timeshift/u/p/...`). M3U URLs may embed `user:pass@host` too.
library;

const redactedMark = '***';

final _queryCred = RegExp(
  r'((?:^|[?&;])(?:username|user|password|pass|pwd|token|auth|key)=)[^&#\s]*',
  caseSensitive: false,
);
final _pathCred = RegExp(
  r'(/(?:live|movie|series|timeshift)/)[^/\s]+/[^/\s]+/',
  caseSensitive: false,
);
final _userInfo = RegExp(
  r'(\b[a-z][a-z0-9+.-]*://)[^/@\s]+@',
  caseSensitive: false,
);

/// Redacts one URL or any text containing URLs.
String redact(String input, {Iterable<String> secrets = const []}) {
  var s = input
      .replaceAllMapped(_userInfo, (m) => '${m[1]}$redactedMark@')
      .replaceAllMapped(_queryCred, (m) => '${m[1]}$redactedMark')
      .replaceAllMapped(
        _pathCred,
        (m) => '${m[1]}$redactedMark/$redactedMark/',
      );
  for (final secret in secrets) {
    if (secret.length >= 3) {
      s = s.replaceAll(secret, redactedMark);
      final encoded = Uri.encodeComponent(secret);
      if (encoded != secret) s = s.replaceAll(encoded, redactedMark);
    }
  }
  return s;
}
