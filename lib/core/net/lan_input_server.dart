/// "Type on your phone": a one-shot web form on the local network.
///
/// The TV starts a [LanInputServer] on its LAN address and shows
/// `http://<ip>:<port>/?t=<token>` as a QR code. The phone's browser gets a
/// small bilingual form (Xtream login, M3U link or `.m3u` upload, or search
/// text) and the first valid submission is handed back to the app; then the
/// server stops. Nothing a phone sends is logged.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../log/ring_log.dart';

/// Which form the phone gets.
enum LanForm {
  /// Xtream login, M3U link or M3U file upload (the source editor).
  source,

  /// One free-text field (search).
  search,
}

/// Where a [LanInputServer] is.
enum LanInputStatus {
  /// Listening for the phone.
  waiting,

  /// A submission arrived; the server has stopped.
  received,

  /// The code expired (lifetime over, or too many wrong codes); the server
  /// has stopped.
  expired,

  /// Stopped by the app ([LanInputServer.close]).
  closed,
}

/// What the phone sent.
enum LanSubmissionKind { xtream, m3uUrl, m3uFile, search }

/// One submission from the phone.
///
/// [fields] holds `server`, `username` and `password` ([LanSubmissionKind.
/// xtream]), `url` ([LanSubmissionKind.m3uUrl]) or `text`
/// ([LanSubmissionKind.search]), trimmed (the password is kept as typed).
/// An uploaded playlist ([LanSubmissionKind.m3uFile]) is at [filePath], a
/// temporary file the receiver owns: import it, then [deleteTempUpload].
class LanSubmission {
  const LanSubmission({
    required this.kind,
    this.fields = const {},
    this.filePath,
    this.fileName,
  });

  final LanSubmissionKind kind;
  final Map<String, String> fields;
  final String? filePath;

  /// The uploaded file's name as the phone reported it (sanitised).
  final String? fileName;

  /// A non-empty field value, or null.
  String? operator [](String name) {
    final value = fields[name];
    return value == null || value.isEmpty ? null : value;
  }

  /// Never prints values: they are credentials.
  @override
  String toString() =>
      'LanSubmission(${kind.name}, fields: ${fields.keys.toList()}'
      '${filePath == null ? '' : ', file'})';
}

/// No usable local network address (no Wi-Fi or Ethernet).
class LanNoNetworkException implements Exception {
  const LanNoNetworkException();

  @override
  String toString() => 'LanNoNetworkException: no local IPv4 address';
}

/// Lists network interfaces; [NetworkInterface.list] in the app.
typedef InterfaceLister = Future<List<NetworkInterface>> Function({
  bool includeLoopback,
  bool includeLinkLocal,
  InternetAddressType type,
});

/// The device's LAN IPv4 address, or null when there is none.
///
/// Takes the first non-loopback IPv4 address of [list], preferring private
/// ranges (`10/8`, `172.16/12`, `192.168/16`) over others such as carrier
/// NAT. When that finds nothing, all interfaces are listed again with
/// link-local addresses included.
Future<InternetAddress?> findLanAddress({
  InterfaceLister list = NetworkInterface.list,
}) async {
  InternetAddress? pick(List<NetworkInterface> interfaces) {
    final candidates = [
      for (final i in interfaces)
        for (final a in i.addresses)
          if (a.type == InternetAddressType.IPv4 && !a.isLoopback) a,
    ];
    return candidates.where(isPrivateIPv4).firstOrNull ??
        candidates.firstOrNull;
  }

  try {
    final found = pick(await list(type: InternetAddressType.IPv4));
    if (found != null) return found;
  } on Object {
    // Fall through to the wider listing.
  }
  try {
    return pick(await list(includeLinkLocal: true));
  } on Object {
    return null;
  }
}

/// Whether [address] is in a private IPv4 range.
bool isPrivateIPv4(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) return false;
  final b = address.rawAddress;
  return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168);
}

/// A one-time web form for the phone. See the library documentation.
///
/// * Bound to the LAN address only, on a random free port.
/// * Every request needs the 6-digit one-time token (`?t=`), else 403;
///   [maxBadTokens] wrong tokens stop the server (brute force).
/// * Lives for [lifetime] (10 minutes by default), then [result] completes
///   with null and [status] becomes [LanInputStatus.expired].
/// * Stops after the first valid submission, which [result] delivers.
/// * Form posts are `application/x-www-form-urlencoded` (at most
///   [maxFormBytes]); a playlist upload is the raw file body of
///   `POST /upload`, streamed to a temporary file and limited to
///   [maxUploadBytes] (50 MB by default).
/// * Request bodies, tokens and submitted values are never logged.
class LanInputServer {
  LanInputServer._({
    required this._server,
    required this.form,
    required this.token,
    required this.maxUploadBytes,
    required this._uploadDir,
    required this._random,
    required this._log,
  });

  static const defaultLifetime = Duration(minutes: 10);
  static const defaultMaxUploadBytes = 50 * 1024 * 1024;
  static const maxFormBytes = 16 * 1024;
  static const maxFieldLength = 2048;
  static const maxBadTokens = 20;

  /// Starts the server and returns once it listens.
  ///
  /// [address] defaults to [findLanAddress] (throws
  /// [LanNoNetworkException] when there is none); tests pass the loopback
  /// address. [uploadDir] defaults to the system temp directory.
  static Future<LanInputServer> start({
    LanForm form = LanForm.source,
    InternetAddress? address,
    InterfaceLister listInterfaces = NetworkInterface.list,
    Duration lifetime = defaultLifetime,
    int maxUploadBytes = defaultMaxUploadBytes,
    String? uploadDir,
    Random? random,
    RingLog? log,
  }) async {
    final bindTo = address ?? await findLanAddress(list: listInterfaces);
    if (bindTo == null) throw const LanNoNetworkException();
    final rng = random ?? Random.secure();
    final server = await HttpServer.bind(bindTo, 0);
    server
      ..autoCompress = false
      ..idleTimeout = const Duration(seconds: 30);
    final lan = LanInputServer._(
      server: server,
      form: form,
      token: _newToken(rng),
      maxUploadBytes: maxUploadBytes,
      uploadDir: uploadDir ?? Directory.systemTemp.path,
      random: rng,
      log: log ?? RingLog.instance,
    );
    lan
      ..address
      ..port
      .._listen(lifetime);
    lan._log.info('Phone input page started on port ${server.port}');
    return lan;
  }

  final HttpServer _server;
  final LanForm form;

  /// The one-time code (6 digits) that every request must carry.
  final String token;
  final int maxUploadBytes;
  final String _uploadDir;
  final Random _random;
  final RingLog _log;

  final _result = Completer<LanSubmission?>();
  final _statusChanges = StreamController<LanInputStatus>.broadcast();
  StreamSubscription<HttpRequest>? _requests;
  Timer? _expiry;
  LanInputStatus _status = LanInputStatus.waiting;
  var _badTokens = 0;
  var _accepting = true;
  Future<void>? _stopping;

  /// The bound address and port (kept after the server stops).
  late final InternetAddress address = _server.address;
  late final int port = _server.port;

  /// The page to open on the phone (also the QR code's content).
  String get url {
    final host = address.type == InternetAddressType.IPv6
        ? '[${address.address}]'
        : address.address;
    return 'http://$host:$port/?t=$token';
  }

  LanInputStatus get status => _status;

  /// Status changes after the current [status].
  Stream<LanInputStatus> get statusChanges => _statusChanges.stream;

  /// The first valid submission, or null when the code expired or the
  /// server was closed first.
  Future<LanSubmission?> get result => _result.future;

  /// Stops the server (idempotent). [result] completes with null if nothing
  /// arrived.
  Future<void> close() => _stop(LanInputStatus.closed);

  static String _newToken(Random random) =>
      random.nextInt(1000000).toString().padLeft(6, '0');

  void _listen(Duration lifetime) {
    _expiry = Timer(lifetime, () => unawaited(_stop(LanInputStatus.expired)));
    _requests = _server.listen(
      (request) => unawaited(_handle(request)),
      onError: (Object e) => _log.warn('Phone input page: ${e.runtimeType}'),
    );
  }

  Future<void> _stop(LanInputStatus reason) => _stopping ??= () async {
    _accepting = false;
    _expiry?.cancel();
    if (_status == LanInputStatus.waiting) _setStatus(reason);
    if (!_result.isCompleted) _result.complete(null);
    await _requests?.cancel();
    await _server.close(force: true);
    await _statusChanges.close();
    _log.info('Phone input page stopped (${_status.name})');
  }();

  void _setStatus(LanInputStatus status) {
    _status = status;
    if (!_statusChanges.isClosed) _statusChanges.add(status);
  }

  bool _tokenMatches(String? candidate) {
    if (candidate == null || candidate.length != token.length) return false;
    var diff = 0;
    for (var i = 0; i < token.length; i++) {
      diff |= token.codeUnitAt(i) ^ candidate.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('X-Frame-Options', 'DENY')
      ..set('Referrer-Policy', 'no-referrer')
      ..set(
        'Content-Security-Policy',
        "default-src 'none'; style-src 'unsafe-inline'; "
            "script-src 'unsafe-inline'; connect-src 'self'; "
            "form-action 'self'",
      );
    try {
      final path = request.uri.path;
      const known = {'/', '/submit', '/upload'};
      if (!known.contains(path)) {
        return await _page(response, HttpStatus.notFound, _Page.notFound);
      }
      final Map<String, String> query;
      try {
        query = request.uri.queryParameters;
      } on FormatException {
        return await _page(response, HttpStatus.badRequest, _Page.invalid);
      }
      if (!_tokenMatches(query['t'])) {
        if (++_badTokens >= maxBadTokens) {
          unawaited(_stop(LanInputStatus.expired));
        }
        return await _page(response, HttpStatus.forbidden, _Page.badCode);
      }
      if (!_accepting) {
        return await _page(response, HttpStatus.gone, _Page.done);
      }
      switch ((request.method, path)) {
        case ('GET' || 'HEAD', '/'):
          await _send(response, HttpStatus.ok, _formPage());
        case ('POST', '/submit'):
          await _submitForm(request);
        case ('POST', '/upload') when form == LanForm.source:
          await _upload(request, query['name']);
        default:
          await _page(response, HttpStatus.methodNotAllowed, _Page.invalid);
      }
    } on Object catch (e) {
      // Never log the request: it may carry credentials.
      _log.warn('Phone input request failed: ${e.runtimeType}');
      try {
        await _page(response, HttpStatus.internalServerError, _Page.invalid);
      } on Object {
        // The connection is gone.
      }
    }
  }

  Future<void> _submitForm(HttpRequest request) async {
    final response = request.response;
    final type = request.headers.contentType?.mimeType;
    // Bodies that are refused are never read: the connection is dropped
    // after the answer instead.
    if (type != 'application/x-www-form-urlencoded') {
      return _page(response, HttpStatus.unsupportedMediaType, _Page.invalid);
    }
    if (request.contentLength > maxFormBytes) {
      return _page(response, HttpStatus.requestEntityTooLarge, _Page.tooBig);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in request) {
      bytes.add(chunk);
      if (bytes.length > maxFormBytes) {
        return _page(response, HttpStatus.requestEntityTooLarge, _Page.tooBig);
      }
    }
    final Map<String, String> params;
    try {
      params = Uri.splitQueryString(
        utf8.decode(bytes.takeBytes(), allowMalformed: true),
      );
    } on FormatException {
      return _page(response, HttpStatus.badRequest, _Page.invalid);
    }
    final submission = parseLanForm(form, params);
    if (submission == null) {
      return _page(response, HttpStatus.badRequest, _Page.missing);
    }
    if (!_accepting) return _page(response, HttpStatus.gone, _Page.done);
    await _deliver(response, submission);
  }

  Future<void> _upload(HttpRequest request, String? rawName) async {
    final response = request.response;
    if (request.contentLength > maxUploadBytes) {
      return _page(response, HttpStatus.requestEntityTooLarge, _Page.tooBig);
    }
    final file = File(_tempPath());
    final sink = file.openWrite();
    var total = 0;
    var tooBig = false;
    try {
      await for (final chunk in request) {
        total += chunk.length;
        if (total > maxUploadBytes) {
          tooBig = true;
          break;
        }
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }
    if (tooBig || total == 0 || !_accepting) {
      await deleteTempUpload(file.path);
      return _page(
        response,
        tooBig
            ? HttpStatus.requestEntityTooLarge
            : total == 0
            ? HttpStatus.badRequest
            : HttpStatus.gone,
        tooBig
            ? _Page.tooBig
            : total == 0
            ? _Page.missing
            : _Page.done,
      );
    }
    await _deliver(
      response,
      LanSubmission(
        kind: LanSubmissionKind.m3uFile,
        filePath: file.path,
        fileName: sanitizeFileName(rawName),
      ),
    );
  }

  /// Hands [submission] over, answers the phone, then stops the server.
  Future<void> _deliver(HttpResponse response, LanSubmission submission) async {
    _accepting = false;
    _expiry?.cancel();
    _setStatus(LanInputStatus.received);
    if (!_result.isCompleted) _result.complete(submission);
    try {
      await _page(response, HttpStatus.ok, _Page.received);
    } finally {
      unawaited(_stop(LanInputStatus.received));
    }
  }

  String _tempPath() {
    final id = [
      for (var i = 0; i < 8; i++)
        _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    return '$_uploadDir${Platform.pathSeparator}lan_upload_$id.m3u';
  }

  Future<void> _page(HttpResponse response, int status, _Page page) =>
      _send(response, status, _messagePage(page));

  static Future<void> _send(HttpResponse response, int status, String html) {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.html
      ..write(html);
    return response.close();
  }

  String _formPage() => switch (form) {
    LanForm.source => _sourceFormHtml(token, maxUploadBytes),
    LanForm.search => _searchFormHtml(token),
  };
}

/// Builds a submission from posted form [params], or null when required
/// fields are missing or the kind does not belong to [form].
LanSubmission? parseLanForm(LanForm form, Map<String, String> params) {
  String value(String key, {bool trim = true}) {
    final raw = params[key] ?? '';
    final v = trim ? raw.trim() : raw;
    return v.length > LanInputServer.maxFieldLength
        ? v.substring(0, LanInputServer.maxFieldLength)
        : v;
  }

  final kind = params['kind'];
  switch ((form, kind)) {
    case (LanForm.source, 'xtream'):
      final fields = {
        'server': value('server'),
        'username': value('username'),
        'password': value('password', trim: false),
      };
      if (fields.values.any((v) => v.isEmpty)) return null;
      return LanSubmission(kind: LanSubmissionKind.xtream, fields: fields);
    case (LanForm.source, 'm3u'):
      final url = value('url');
      if (url.isEmpty) return null;
      return LanSubmission(
        kind: LanSubmissionKind.m3uUrl,
        fields: {'url': url},
      );
    case (LanForm.search, 'search'):
      final text = value('text');
      if (text.isEmpty) return null;
      return LanSubmission(
        kind: LanSubmissionKind.search,
        fields: {'text': text},
      );
    default:
      return null;
  }
}

/// The base name of [name] without control characters, at most 100
/// characters; `playlist.m3u` when nothing is left.
String sanitizeFileName(String? name) {
  var base = (name ?? '').split(RegExp(r'[/\\]')).last;
  base = base.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
  if (base.length > 100) base = base.substring(base.length - 100);
  return base.isEmpty || base == '.' || base == '..' ? 'playlist.m3u' : base;
}

/// Copies [bytes] to a new temporary file (for a picked playlist that has no
/// local path) and returns its path. Throws a [FileSystemException] when
/// more than [maxBytes] arrive; the partial file is removed.
Future<String> writeTempUpload(
  Stream<List<int>> bytes, {
  int maxBytes = LanInputServer.defaultMaxUploadBytes,
  String? dir,
}) async {
  final random = Random.secure();
  final id = [
    for (var i = 0; i < 8; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
  final file = File(
    '${dir ?? Directory.systemTemp.path}${Platform.pathSeparator}'
    'picked_$id.m3u',
  );
  final sink = file.openWrite();
  var total = 0;
  try {
    await for (final chunk in bytes) {
      total += chunk.length;
      if (total > maxBytes) {
        throw FileSystemException('Playlist too large', file.path);
      }
      sink.add(chunk);
    }
    await sink.close();
    return file.path;
  } on Object {
    await sink.close().catchError((Object _) {});
    await deleteTempUpload(file.path);
    rethrow;
  }
}

/// Deletes a temporary upload; never throws.
Future<void> deleteTempUpload(String? path) async {
  if (path == null) return;
  try {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  } on Object {
    // Temp files are cleaned up by the system eventually.
  }
}

enum _Page { received, missing, invalid, badCode, done, tooBig, notFound }

String _messagePage(_Page page) {
  final (ar, en) = switch (page) {
    _Page.received => (
      'تم الاستلام. يمكنك إغلاق هذه الصفحة.',
      'Received. You can close this page.',
    ),
    _Page.missing => (
      'بعض الحقول المطلوبة فارغة. ارجع وأكملها.',
      'Some required fields are empty. Go back and fill them in.',
    ),
    _Page.invalid => ('طلب غير صالح.', 'Invalid request.'),
    _Page.badCode => (
      'الرمز غير صالح أو منتهي. امسح الرمز من التلفزيون مرة أخرى.',
      'This code is wrong or has expired. Scan the code on the TV again.',
    ),
    _Page.done => (
      'تم استلام البيانات مسبقاً.',
      'The details were already received.',
    ),
    _Page.tooBig => (
      'الملف أو الطلب كبير جداً.',
      'The file or request is too large.',
    ),
    _Page.notFound => ('الصفحة غير موجودة.', 'Page not found.'),
  };
  return '$_head<main><p>$ar</p><p class="en">$en</p></main></body></html>';
}

const _head =
    '<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width,initial-scale=1">'
    '<meta name="referrer" content="no-referrer">'
    '<title>IPTV Player</title><style>'
    'body{font-family:system-ui,-apple-system,"Segoe UI",Tahoma,sans-serif;'
    'background:#0b0e13;color:#f3f5f9;margin:0;padding:16px;line-height:1.5}'
    'main{max-width:480px;margin:0 auto}'
    'h1{font-size:20px;margin:8px 0 16px}h2{font-size:17px;margin:0 0 8px}'
    'section{background:#151a22;border-radius:12px;padding:12px 16px;'
    'margin:0 0 16px}'
    'label{display:block;margin:12px 0 4px;color:#b4bcc8}'
    'input{width:100%;box-sizing:border-box;padding:12px;font-size:16px;'
    'border-radius:8px;border:1px solid #3a4352;background:#1f2632;'
    'color:#f3f5f9}'
    'button{margin-top:12px;width:100%;padding:12px;font-size:16px;border:0;'
    'border-radius:8px;background:#ffb020;color:#1a1200;font-weight:bold}'
    '.en{display:block;direction:ltr;text-align:left;color:#b4bcc8;'
    'font-size:14px}'
    '</style></head><body>';

const _inputAttrs =
    'dir="ltr" autocomplete="off" autocapitalize="off" spellcheck="false"';

String _sourceFormHtml(String token, int maxBytes) =>
    '$_head<main>'
    '<h1>أرسل إلى التلفزيون<span class="en">Send to your TV</span></h1>'
    '<section><h2>Xtream Codes</h2>'
    '<form method="post" action="/submit?t=$token">'
    '<input type="hidden" name="kind" value="xtream">'
    '<label for="server">الخادم<span class="en">Server</span></label>'
    '<input id="server" name="server" inputmode="url" required '
    'placeholder="http://example.com:8080" $_inputAttrs>'
    '<label for="username">اسم المستخدم<span class="en">Username</span>'
    '</label><input id="username" name="username" required $_inputAttrs>'
    '<label for="password">كلمة المرور<span class="en">Password</span>'
    '</label><input id="password" name="password" type="password" required '
    '$_inputAttrs>'
    '<button type="submit">إرسال · Send</button></form></section>'
    '<section><h2>رابط M3U<span class="en">M3U link</span></h2>'
    '<form method="post" action="/submit?t=$token">'
    '<input type="hidden" name="kind" value="m3u">'
    '<input id="url" name="url" type="url" required '
    'placeholder="http://example.com/playlist.m3u" $_inputAttrs>'
    '<button type="submit">إرسال · Send</button></form></section>'
    '<section><h2>ملف M3U<span class="en">M3U file (50 MB max)</span></h2>'
    '<input id="file" type="file" accept=".m3u,.m3u8,.txt">'
    '<button id="upload" type="button">رفع · Upload</button>'
    '<p id="state" aria-live="polite"></p></section>'
    '<script>'
    'document.getElementById("upload").onclick=function(){'
    'var f=document.getElementById("file").files[0],'
    's=document.getElementById("state");if(!f){return}'
    'if(f.size>$maxBytes){s.textContent="الملف كبير جداً · The file is too '
    'large";return}'
    's.textContent="…";'
    'fetch("/upload?t=$token&name="+encodeURIComponent(f.name),'
    '{method:"POST",headers:{"Content-Type":"application/octet-stream"},'
    'body:f}).then(function(r){s.textContent=r.ok?'
    '"تم الاستلام · Received":"خطأ · Error "+r.status})'
    '.catch(function(){s.textContent="خطأ · Error"})};'
    '</script></main></body></html>';

String _searchFormHtml(String token) =>
    '$_head<main>'
    '<h1>ابحث من جوالك<span class="en">Search from your phone</span></h1>'
    '<section><form method="post" action="/submit?t=$token">'
    '<input type="hidden" name="kind" value="search">'
    '<label for="text">النص<span class="en">Text</span></label>'
    '<input id="text" name="text" required dir="auto" autocomplete="off">'
    '<button type="submit">إرسال · Send</button></form></section>'
    '</main></body></html>';
