import 'models.dart';

/// Xtream credentials found inside a pasted playlist URL.
///
/// `http://host:8080/get.php?username=U&password=P&type=m3u_plus&output=ts`
/// and `.../player_api.php?username=U&password=P` both identify an Xtream
/// panel; saving it as an Xtream source gives VOD details, short EPG and
/// `xmltv.php`.
class XtreamLink {
  const XtreamLink({
    required this.base,
    required this.username,
    required this.password,
    this.output,
  });

  /// `scheme://host[:port]`, plus any path prefix in front of the script.
  final String base;
  final String username;
  final String password;

  /// `output=` value (`ts`, `m3u8`, `hls`), if present.
  final String? output;

  /// Live format implied by [output]; `ts` when absent or unknown.
  LiveFormat get liveFormat => switch (output?.toLowerCase()) {
    'm3u8' || 'hls' => LiveFormat.m3u8,
    _ => LiveFormat.ts,
  };

  /// A new Xtream [SourceConfig] carrying these credentials.
  SourceConfig toSourceConfig({String name = ''}) => SourceConfig(
    kind: SourceKind.xtream,
    url: base,
    name: name,
    username: username,
    password: password,
    liveFormat: liveFormat,
  );

  @override
  String toString() => 'XtreamLink($base, user: ***)';
}

const _scripts = ['get.php', 'player_api.php'];

/// Detects an Xtream `get.php` / `player_api.php` URL with credentials.
///
/// Returns null for anything else, including links with an empty username
/// or password. Parameter names match case-insensitively; values are
/// URL-decoded.
XtreamLink? parseXtreamLink(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if ((scheme != 'http' && scheme != 'https') || uri.host.isEmpty) {
    return null;
  }
  final segments = uri.pathSegments;
  if (segments.isEmpty || !_scripts.contains(segments.last.toLowerCase())) {
    return null;
  }
  final Map<String, String> params;
  try {
    params = {
      for (final e in uri.queryParameters.entries) e.key.toLowerCase(): e.value,
    };
  } catch (_) {
    return null; // Malformed percent-encoding.
  }
  final username = params['username'] ?? '';
  final password = params['password'] ?? '';
  if (username.isEmpty || password.isEmpty) return null;

  final prefix = segments
      .sublist(0, segments.length - 1)
      .where((s) => s.isNotEmpty)
      .map(Uri.encodeComponent)
      .join('/');
  final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  final port = uri.hasPort ? ':${uri.port}' : '';
  final base = '$scheme://$host$port${prefix.isEmpty ? '' : '/$prefix'}';
  final output = params['output'];
  return XtreamLink(
    base: base,
    username: username,
    password: password,
    output: output == null || output.isEmpty ? null : output,
  );
}
