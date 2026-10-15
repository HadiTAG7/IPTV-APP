// Small local XMLTV server for EpgService tests: a fixed body with optional
// gzip, ETag / Last-Modified validators answered with 304, a forced status,
// a stall point and a dropped connection. All guide data is synthetic.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One request as the server saw it.
class GuideRequest {
  const GuideRequest({
    required this.uri,
    this.userAgent,
    this.ifNoneMatch,
    this.ifModifiedSince,
  });

  final Uri uri;
  final String? userAgent;
  final String? ifNoneMatch;
  final String? ifModifiedSince;

  bool get isConditional => ifNoneMatch != null || ifModifiedSince != null;
}

class GuideServer {
  GuideServer._(this._server);

  static Future<GuideServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final guide = GuideServer._(server);
    server.listen((req) => unawaited(guide._handle(req)));
    return guide;
  }

  final HttpServer _server;

  /// XMLTV text served with status 200.
  String body = '';
  bool gzipped = false;

  /// Answered instead of the guide when not 200.
  int status = 200;
  String? etag;
  String? lastModified;

  /// When set, the body stops after this many bytes until [release].
  int? stallAfterBytes;

  /// When set, the connection is closed after this many bytes of a body
  /// announced in full (`Content-Length`).
  int? dropAfterBytes;
  Completer<void> _release = Completer<void>();

  final requests = <GuideRequest>[];

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  /// Lets a stalled body finish.
  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  /// Stalls the next bodies again.
  void rearm() => _release = Completer<void>();

  Future<void> close() async {
    release();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final ifNoneMatch = req.headers.value(HttpHeaders.ifNoneMatchHeader);
    final ifModifiedSince = req.headers.value(
      HttpHeaders.ifModifiedSinceHeader,
    );
    requests.add(
      GuideRequest(
        uri: req.uri,
        userAgent: req.headers.value(HttpHeaders.userAgentHeader),
        ifNoneMatch: ifNoneMatch,
        ifModifiedSince: ifModifiedSince,
      ),
    );
    final res = req.response..bufferOutput = false;
    try {
      if (status != 200) {
        res
          ..statusCode = status
          ..write('Internal error');
        await res.close();
        return;
      }
      final notModified =
          (etag != null && ifNoneMatch == etag) ||
          (etag == null &&
              lastModified != null &&
              ifModifiedSince == lastModified);
      if (notModified) {
        res.statusCode = HttpStatus.notModified;
        await res.close();
        return;
      }
      if (etag case final tag?) res.headers.set(HttpHeaders.etagHeader, tag);
      if (lastModified case final lm?) {
        res.headers.set(HttpHeaders.lastModifiedHeader, lm);
      }
      res.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
      final bytes = utf8.encode(body);
      final payload = gzipped ? gzip.encode(bytes) : bytes;
      final drop = dropAfterBytes;
      if (drop != null && drop < payload.length) {
        res.contentLength = payload.length;
        final socket = await res.detachSocket();
        socket.add(payload.sublist(0, drop));
        await socket.flush();
        socket.destroy();
        return;
      }
      final stall = stallAfterBytes;
      if (stall != null && stall < payload.length) {
        res.add(payload.sublist(0, stall));
        await res.flush();
        await _release.future;
        res.add(payload.sublist(stall));
      } else {
        res.add(payload);
      }
      await res.close();
    } on Object {
      // The client went away (cancelled download); nothing to answer.
    }
  }
}

/// XMLTV `yyyyMMddHHmmss ±HHMM` for [utc] shown at [offsetMin].
String xmltvTime(DateTime utc, [int offsetMin = 0]) {
  String two(int v) => v.toString().padLeft(2, '0');
  final t = utc.toUtc().add(Duration(minutes: offsetMin));
  final sign = offsetMin < 0 ? '-' : '+';
  final off = offsetMin.abs();
  return '${t.year}${two(t.month)}${two(t.day)}'
      '${two(t.hour)}${two(t.minute)}${two(t.second)} '
      '$sign${two(off ~/ 60)}${two(off % 60)}';
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String channelXml(String id, List<String> names) =>
    '<channel id="${_esc(id)}">'
    '${[for (final n in names) '<display-name>${_esc(n)}</display-name>'].join()}'
    '</channel>';

String programmeXml(
  String channel,
  DateTime start,
  DateTime stop,
  String title, {
  int offsetMin = 0,
}) =>
    '<programme start="${xmltvTime(start, offsetMin)}" '
    'stop="${xmltvTime(stop, offsetMin)}" channel="${_esc(channel)}">'
    '<title lang="en">${_esc(title)}</title></programme>';

/// Hourly programmes of [channel] starting at [from], [count] of them,
/// titled `<channel> <n>`.
List<String> hourly(String channel, DateTime from, int count) => [
  for (var i = 0; i < count; i++)
    programmeXml(
      channel,
      from.add(Duration(hours: i)),
      from.add(Duration(hours: i + 1)),
      '$channel $i',
    ),
];

String xmltvDoc(Iterable<String> elements) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<tv generator-info-name="guide_server">\n'
    '${elements.join('\n')}\n'
    '</tv>\n';
