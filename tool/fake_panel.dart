/// Runs the fake IPTV panel until killed.
///
/// ```
/// dart run tool/fake_panel.dart [--port 8899] [--public] [--user user]
///   [--pass pass] [--max-connections 1] [--live 50] [--vod 30] [--series 10]
///   [--auth good|expired|banned|disabled|auth0WithHttp200|emptyArray]
///   [--media-dir test/media] [--no-media] [--bytes-per-second N]
///   [--full-list-delay-ms N] [--hls-segment-seconds 2]
///   [--hls-session-ms N] [--epg-hours 24]
/// ```
///
/// `--public` binds all interfaces so an Android emulator can reach the panel
/// at `http://10.0.2.2:<port>`.
library;

import 'dart:async';
import 'dart:io';

import '../test/support/fake_panel.dart';

const _usage = '''
Usage: dart run tool/fake_panel.dart [options]
  --port N                 Port to listen on (default 8899, 0 = any free port)
  --public                 Bind 0.0.0.0 (emulator access via 10.0.2.2)
  --user NAME              Xtream username (default user)
  --pass PASS              Xtream password (default pass)
  --max-connections N      Concurrent stream limit, 0 = unlimited (default 1)
  --live N / --vod N / --series N   Catalog sizes (default 50 / 30 / 10)
  --auth MODE              good, expired, banned, disabled, auth0WithHttp200, emptyArray
  --media-dir DIR          Generated media directory (default test/media)
  --no-media               Serve synthetic media only
  --bytes-per-second N     Live TS rate (default: media bitrate)
  --full-list-delay-ms N   Delay full catalog lists (per-category stays fast)
  --hls-segment-seconds N  HLS segment length (default 2)
  --hls-session-ms N       Idle time before an HLS viewer's connection is
                           released (default 2 segments; 0 = per request)
  --epg-hours N            How far ahead xmltv.php lists programmes (default 24)
  --help                   Show this help''';

Future<void> main(List<String> args) async {
  final opts = <String, String>{};
  final flags = <String>{};
  const booleans = {'public', 'no-media', 'help'};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) return _fail('Unexpected argument: $a');
    final eq = a.indexOf('=');
    final name = a.substring(2, eq < 0 ? null : eq);
    if (booleans.contains(name)) {
      flags.add(name);
    } else if (eq >= 0) {
      opts[name] = a.substring(eq + 1);
    } else if (i + 1 < args.length) {
      opts[name] = args[++i];
    } else {
      return _fail('Missing value for --$name');
    }
  }
  if (flags.contains('help')) {
    stdout.writeln(_usage);
    return;
  }

  int intOpt(String name, int fallback) {
    final v = opts.remove(name);
    if (v == null) return fallback;
    return int.tryParse(v) ??
        (throw FormatException('--$name expects a number'));
  }

  final FakePanel panel;
  try {
    final authName = opts.remove('auth') ?? 'good';
    final auth = FakeAuthMode.values.where((m) => m.name == authName);
    if (auth.isEmpty) throw FormatException('Unknown --auth $authName');
    final bps = intOpt('bytes-per-second', 0);
    final user = opts.remove('user') ?? 'user';
    final pass = opts.remove('pass') ?? 'pass';
    final mediaDir = opts.remove('media-dir') ?? 'test/media';
    final port = intOpt('port', 8899);
    final maxConnections = intOpt('max-connections', 1);
    final live = intOpt('live', 50);
    final vod = intOpt('vod', 30);
    final series = intOpt('series', 10);
    final delayMs = intOpt('full-list-delay-ms', 0);
    final hlsSeconds = intOpt('hls-segment-seconds', 2);
    final hlsSessionMs = intOpt('hls-session-ms', -1);
    final epgHours = intOpt('epg-hours', 24);
    if (opts.isNotEmpty) {
      throw FormatException('Unknown option --${opts.keys.first}');
    }
    panel = await FakePanel.start(
      username: user,
      password: pass,
      maxConnections: maxConnections,
      auth: auth.first,
      liveCount: live,
      vodCount: vod,
      seriesCount: series,
      port: port,
      anyIPv4: flags.contains('public'),
      fullListDelay: Duration(milliseconds: delayMs),
      liveBytesPerSecond: bps > 0 ? bps : null,
      hlsSegmentDuration: Duration(seconds: hlsSeconds < 1 ? 1 : hlsSeconds),
      hlsSessionTimeout: hlsSessionMs < 0
          ? null
          : Duration(milliseconds: hlsSessionMs),
      epgSpan: Duration(hours: epgHours),
      mediaDir: flags.contains('no-media') ? null : mediaDir,
    );
  } on FormatException catch (e) {
    return _fail(e.message);
  } on SocketException catch (e) {
    return _fail('Cannot listen: ${e.message} ${e.osError ?? ''}'.trim());
  }

  final base = panel.baseUrl;
  final first = panel.catalog.live.isEmpty ? null : panel.catalog.live.first;
  stdout
    ..writeln(
      'Fake panel listening on $base (${panel.username} / ${panel.password})',
    )
    ..writeln(
      flags.contains('public')
          ? '  Android emulator: http://10.0.2.2:${panel.port}'
          : '  Loopback only; pass --public for emulator access',
    )
    ..writeln('  Xtream login: ${panel.playerApiUrl()}')
    ..writeln('  M3U:          ${panel.m3uUrl()}')
    ..writeln('  XMLTV (gzip): ${panel.xmltvUrl}')
    ..writeln('  XMLTV plain:  ${panel.plainEpgUrl}');
  if (first != null) {
    final media = panel.liveUsesMediaFile(first.id)
        ? 'media file'
        : 'synthetic null packets';
    stdout
      ..writeln('  Live TS:      ${panel.liveUrl(first.id)}  ($media)')
      ..writeln('  Live HLS:     ${panel.liveUrl(first.id, ext: 'm3u8')}');
  }
  stdout
    ..writeln('  Stats:        $base/__stats')
    ..writeln(
      '  Chaos:        $base/__chaos?mode=drop&after=10 | mode=403&for=5 | '
      'mode=stall&for=20 | mode=off',
    )
    ..writeln('Press Ctrl+C to stop.');

  final stop = Completer<void>();
  for (final signal in [
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ]) {
    signal.watch().listen((_) {
      if (!stop.isCompleted) stop.complete();
    });
  }
  await stop.future;
  await panel.close();
  exit(0);
}

void _fail(String message) {
  stderr
    ..writeln(message)
    ..writeln(_usage);
  exitCode = 64;
}
