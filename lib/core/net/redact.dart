/// Removes credentials from URLs and free text before logging or display.
///
/// Xtream puts the username and password in query strings
/// (`?username=u&password=p`) and in path segments
/// (`/live/u/p/1.ts`, `/movie/u/p/2.mkv`, `/series/u/p/3.mp4`,
/// `/timeshift/u/p/...`). M3U URLs may embed `user:pass@host` or tokens
/// (`?access_token=`, `?api_key=`, `get.php?u=..&p=..`) too.
library;

const redactedMark = '***';

/// Query parameter names that carry credentials: `u` and `p`, user names,
/// and any name ending in a password, token, key, secret, auth or signature
/// word (`password`, `passwd`, `access_token`, `api_key`, `apikey`...).
const _credentialName =
    r'(?:u|p|user|username|login|[\w.-]*?'
    r'(?:pass(?:wd|word)?|pwd|token|key|secret|auth|sig(?:nature)?|'
    r'credentials?))';

final _queryCred = RegExp(
  '((?:^|[?&;])$_credentialName=)[^&#\\s]*',
  caseSensitive: false,
);
final _credentialParam = RegExp('^$_credentialName\$', caseSensitive: false);
final _pathCred = RegExp(
  r'(/(?:live|movie|series|timeshift)/)[^/\s]+/[^/\s]+/',
  caseSensitive: false,
);

/// Scheme, then the user info up to the last `@` of the authority (a
/// password may contain an unencoded `@`).
final _userInfo = RegExp(
  r'(\b[a-z][a-z0-9+.-]*://)([^/?#\s]+)@',
  caseSensitive: false,
);

/// Whether a query parameter called [name] carries a credential.
bool isCredentialParam(String name) => _credentialParam.hasMatch(name);

/// The raw `user:pass` part of [url] (up to the last `@` before the path),
/// or null when it has none.
String? urlUserInfo(String url) => _userInfo.matchAsPrefix(url.trim())?[2];

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
