/// URL builders for the Xtream Codes API and stream endpoints.
///
/// The base is always the one the user typed, never `server_info.url`.
/// Credentials are percent-encoded in both path segments and query strings
/// (the same encoding `redact` looks for).
library;

import '../../core/net/redact.dart';
import '../models.dart';

final _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://');
final _trailingSlashes = RegExp(r'/+$');
final _endpoint = RegExp(
  r'/(player_api|panel_api|get|xmltv)\.php$',
  caseSensitive: false,
);

class XtreamUrls {
  XtreamUrls(String base, this.username, this.password)
    : base = normalizeBase(base);

  /// `scheme://host[:port][/prefix]`, without a trailing slash.
  final String base;
  final String username;
  final String password;

  /// [base] parsed, or null when it is not a usable `http(s)://host[:port]`
  /// address (a typo such as `host:8O80` or `host:80,`).
  late final Uri? baseUri = parseBase(base);

  String get _u => Uri.encodeComponent(username);
  String get _p => Uri.encodeComponent(password);
  String get _credQuery => 'username=$_u&password=$_p';

  /// Trims whitespace, query, fragment, trailing slashes and a pasted
  /// `player_api.php`/`get.php`/`xmltv.php`; adds `http://` when no scheme is
  /// given. The port and any path prefix are kept.
  static String normalizeBase(String input) {
    var s = input.trim();
    if (!_scheme.hasMatch(s)) s = 'http://$s';
    final sep = s.indexOf('://');
    // Only the part after the scheme is trimmed, so `http://` stays intact.
    var rest = s.substring(sep + 3);
    final cut = rest.indexOf(RegExp('[?#]'));
    if (cut >= 0) rest = rest.substring(0, cut);
    rest = rest
        .replaceFirst(_trailingSlashes, '')
        .replaceFirst(_endpoint, '')
        .replaceFirst(_trailingSlashes, '');
    return '${s.substring(0, sep).toLowerCase()}://$rest';
  }

  /// Parses a [normalizeBase] result; null unless it is an `http`/`https`
  /// URL with a plain host and, when given, a port in 1–65535.
  static Uri? parseBase(String base) {
    final uri = Uri.tryParse(base);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    // Spaces and other characters that are invalid in a host come back
    // percent-encoded.
    if (uri.host.isEmpty || uri.host.contains('%')) return null;
    if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) return null;
    return uri;
  }

  /// `player_api.php` with credentials, an optional [action] and extra
  /// [params].
  ///
  /// Throws a credential-free [ParseFailure] when [base] is invalid.
  Uri playerApi({String? action, Map<String, String> params = const {}}) {
    final q = StringBuffer(_credQuery);
    if (action != null) q.write('&action=${Uri.encodeComponent(action)}');
    params.forEach((k, v) {
      q.write('&${Uri.encodeComponent(k)}=${Uri.encodeComponent(v)}');
    });
    final uri = baseUri == null
        ? null
        : Uri.tryParse('$base/player_api.php?$q');
    if (uri == null) {
      throw ParseFailure(
        'Invalid server address: '
        '${redact(base, secrets: [username, password])}',
      );
    }
    return uri;
  }

  /// Full XMLTV guide for this account.
  String xmltv() => '$base/xmltv.php?$_credQuery';

  /// M3U export of the account (`type=m3u_plus`, `output=ts|m3u8`).
  String getPhp({String type = 'm3u_plus', String output = 'ts'}) =>
      '$base/get.php?$_credQuery'
      '&type=${Uri.encodeComponent(type)}'
      '&output=${Uri.encodeComponent(output)}';

  String live(String streamId, String ext) => _media('live', streamId, ext);

  String movie(String streamId, String ext) => _media('movie', streamId, ext);

  String episode(String id, String ext) => _media('series', id, ext);

  /// Catch-up URL; [startLocal] is the programme start in the panel's time
  /// zone.
  String timeshift(String streamId, int durationMin, DateTime startLocal) {
    String two(int v) => v.toString().padLeft(2, '0');
    final t = startLocal;
    final start =
        '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
        ':${two(t.hour)}-${two(t.minute)}';
    return '$base/timeshift/$_u/$_p/$durationMin/$start/'
        '${Uri.encodeComponent(streamId)}.ts';
  }

  String _media(String kind, String id, String ext) {
    final e = ext.startsWith('.') ? ext.substring(1) : ext;
    return '$base/$kind/$_u/$_p/${Uri.encodeComponent(id)}.$e';
  }
}
