// The detached-window protocol between the app and its viewer processes.
//
// A detached channel plays in a second process of the same executable,
// started in viewer mode (`--viewer --port=N --locale=ar|en`, the one-time
// token in the [kViewerTokenEnvironment] environment variable). The viewer
// connects to the app's loopback server, sends the token first
// ([HelloMessage]) and then exchanges one JSON object per line:
//
// * app -> viewer: [PlayMessage] (the resolved stream and engine options),
//   [InUseMessage] (Retry refused), [CloseMessage].
// * viewer -> app: [HelloMessage], [ReadyMessage], [OpeningMessage],
//   [PlayingMessage], [ViewerErrorMessage] (redacted), [RetryMessage],
//   [ClosedMessage].
//
// Stream URLs, credentials and the token never travel on the command line
// (other local users can read it; a process's environment only its own
// user can). Malformed lines are dropped.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../core/net/redact.dart';
import '../../sources/models.dart';
import '../engine/engine_factory.dart';
import '../engine/mpv_engine.dart' show kDefaultPreferredLanguages;

/// Version of the line protocol; the app refuses a viewer of another one
/// (an update replaced the executable while the app ran).
const kViewerProtocolVersion = 2;

/// The environment variable that carries a viewer's one-time token.
const kViewerTokenEnvironment = 'IPTV_VIEWER_TOKEN';

/// Longest line either side accepts; a longer one closes the connection.
const kMaxViewerLineBytes = 256 * 1024;

const _maxUrlLength = 8 * 1024;
const _maxHeaderLength = 4 * 1024;
const _maxTextLength = 1024;
const _maxTitleLength = 512;
const _maxListLength = 32;

// ---------------------------------------------------------------------------
// Command line.

/// How a viewer process is started. Its command line ([toArgs]) carries no
/// stream URL, credential or token, only the loopback port and the
/// language; the one-time token goes in its environment ([environment]).
@immutable
class ViewerLaunchArgs {
  const ViewerLaunchArgs({
    required this.port,
    required this.token,
    this.locale = 'en',
  });

  static const flag = '--viewer';

  /// The app's loopback server.
  final int port;

  /// One-time secret the viewer sends first ([HelloMessage]).
  final String token;

  /// `ar` or `en`: the viewer's language and text direction.
  final String locale;

  static final _token = RegExp(r'^[A-Za-z0-9_-]{22,128}$');

  /// Whether [args] start a viewer rather than the app.
  static bool isViewer(List<String> args) => args.contains(flag);

  /// The command line (without the token).
  List<String> toArgs() => [flag, '--port=$port', '--locale=$locale'];

  /// What the viewer's environment adds to the app's: the token.
  Map<String, String> get environment => {kViewerTokenEnvironment: token};

  /// Reads a viewer command line, and the token from [environment] (the
  /// process's own); throws a [FormatException] (without the token) when
  /// the port or token is missing or invalid. An unknown locale falls back
  /// to English.
  static ViewerLaunchArgs parse(
    List<String> args, {
    Map<String, String> environment = const {},
  }) {
    if (!isViewer(args)) throw const FormatException('Not a viewer');
    String? value(String name) {
      final prefix = '--$name=';
      for (final a in args) {
        if (a.startsWith(prefix)) return a.substring(prefix.length);
      }
      return null;
    }

    final port = int.tryParse(value('port') ?? '');
    if (port == null || port <= 0 || port > 65535) {
      throw const FormatException('Viewer: bad port');
    }
    final token = environment[kViewerTokenEnvironment] ?? '';
    if (!_token.hasMatch(token)) {
      throw const FormatException('Viewer: bad token');
    }
    final locale = value('locale');
    return ViewerLaunchArgs(
      port: port,
      token: token,
      locale: locale == 'ar' ? 'ar' : 'en',
    );
  }

  @override
  String toString() => 'ViewerLaunchArgs(port $port, $locale)';
}

/// A random one-time token: 32 bytes (256 bits) from [Random.secure],
/// base64url without padding.
String newViewerToken() {
  final rng = Random.secure();
  final bytes = Uint8List.fromList([
    for (var i = 0; i < 32; i++) rng.nextInt(256),
  ]);
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Compares [given] with [expected] in time that depends only on
/// [expected]'s length, not on where they differ.
bool tokensMatch(String expected, String given) {
  final a = utf8.encode(expected);
  final b = utf8.encode(given);
  var diff = a.length ^ b.length;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ (i < b.length ? b[i] : 0);
  }
  return diff == 0;
}

// ---------------------------------------------------------------------------
// Messages.

/// One line of the protocol.
sealed class ViewerMessage {
  const ViewerMessage();

  /// The `type` field.
  String get type;

  /// Whether the viewer sends it (else the app does).
  bool get fromViewer;

  Map<String, Object?> toJson();
}

/// Viewer -> app, first line: the one-time token.
final class HelloMessage extends ViewerMessage {
  const HelloMessage({
    required this.token,
    this.version = kViewerProtocolVersion,
  });

  final String token;
  final int version;

  @override
  String get type => 'hello';

  @override
  bool get fromViewer => true;

  @override
  Map<String, Object?> toJson() => {'token': token, 'version': version};

  @override
  String toString() => 'HelloMessage(v$version)';
}

/// Viewer -> app: the window is up and waits for [PlayMessage].
final class ReadyMessage extends ViewerMessage {
  const ReadyMessage();

  @override
  String get type => 'ready';

  @override
  bool get fromViewer => true;

  @override
  Map<String, Object?> toJson() => const {};
}

/// Viewer -> app: the stream is opening (or opening again); the window
/// holds a connection from now on.
final class OpeningMessage extends ViewerMessage {
  const OpeningMessage();

  @override
  String get type => 'opening';

  @override
  bool get fromViewer => true;

  @override
  Map<String, Object?> toJson() => const {};
}

/// Viewer -> app: the current stream shows pictures.
final class PlayingMessage extends ViewerMessage {
  const PlayingMessage();

  @override
  String get type => 'playing';

  @override
  bool get fromViewer => true;

  @override
  Map<String, Object?> toJson() => const {};
}

/// Viewer -> app: playback failed (the connection is closed). [message] is
/// redacted by the viewer.
final class ViewerErrorMessage extends ViewerMessage {
  const ViewerErrorMessage(this.message);

  final String message;

  @override
  String get type => 'error';

  @override
  bool get fromViewer => true;

  /// Longer messages are cut, so the line stays valid.
  @override
  Map<String, Object?> toJson() => {'message': _clip(message, _maxTextLength)};

  @override
  String toString() => 'ViewerErrorMessage(${redact(message)})';
}

/// Viewer -> app: the user pressed Retry after a failure. The viewer opens
/// nothing by itself: the app answers with [PlayMessage] when the source
/// has a connection free, else with [InUseMessage].
final class RetryMessage extends ViewerMessage {
  const RetryMessage();

  @override
  String get type => 'retry';

  @override
  bool get fromViewer => true;

  @override
  Map<String, Object?> toJson() => const {};
}

/// Viewer -> app: the user closed the window; the viewer exits.
final class ClosedMessage extends ViewerMessage {
  const ClosedMessage();

  @override
  String get type => 'closed';

  @override
  bool get fromViewer => true;

  @override
  Map<String, Object?> toJson() => const {};
}

/// What holds the connection an [InUseMessage] is about.
enum ConnectionInUseBy {
  /// The player of the app's main window.
  mainWindow,

  /// Another detached window.
  otherWindow,
}

/// App -> viewer: Retry was refused; the source's connection is in use
/// ([by]). The window keeps its failure card.
final class InUseMessage extends ViewerMessage {
  const InUseMessage(this.by);

  final ConnectionInUseBy by;

  @override
  String get type => 'in-use';

  @override
  bool get fromViewer => false;

  @override
  Map<String, Object?> toJson() => {'by': by.name};

  @override
  String toString() => 'InUseMessage(${by.name})';
}

/// App -> viewer: stop and exit.
final class CloseMessage extends ViewerMessage {
  const CloseMessage();

  @override
  String get type => 'close';

  @override
  bool get fromViewer => false;

  @override
  Map<String, Object?> toJson() => const {};
}

/// App -> viewer: play this live stream (replacing what plays).
///
/// The stream fields are those of a [StreamRequest] (the `User-Agent`
/// header travels as [userAgent]); the engine fields those of
/// [EngineOptions]. [secrets] are the source's credentials, only for
/// masking them in what the viewer shows and reports.
final class PlayMessage extends ViewerMessage {
  const PlayMessage({
    required this.url,
    this.headers = const {},
    this.userAgent,
    this.isHls = false,
    this.title = '',
    this.logo,
    this.channelKey,
    this.maxConnections,
    this.hardwareDecoding = true,
    this.lite = false,
    this.preferredLanguages = kDefaultPreferredLanguages,
    this.subtitleLanguages,
    this.secrets = const [],
  });

  /// The message for [stream] with [options], within the protocol's
  /// limits: a long title is cut; an oversized logo or key, a header the
  /// viewer would refuse, unusable secrets and an unknown connection limit
  /// (0 or less) are left out. Throws a [FormatException] when the viewer
  /// would still refuse it ([checkViewerPlay]: a stream URL it does not
  /// play, see [isViewerStreamUrl]) or the line would be too long.
  factory PlayMessage.of(
    StreamRequest stream, {
    required String title,
    String? logo,
    String? channelKey,
    int? maxConnections,
    EngineOptions options = const EngineOptions(),
    Iterable<String> secrets = const [],
  }) {
    bool fits(String s, int max) => s.isNotEmpty && s.length <= max;
    bool header(String s) => fits(s, _maxHeaderLength) && !_control.hasMatch(s);
    final headers = <String, String>{};
    String? userAgent;
    stream.headers.forEach((k, v) {
      if (!header(k) || !header(v)) return;
      if (k.toLowerCase() == 'user-agent') {
        userAgent = v;
      } else if (headers.length < _maxListLength) {
        headers[k] = v;
      }
    });
    String? optional(String? s) =>
        s != null && fits(s, _maxUrlLength) ? s : null;
    List<String> languages(List<String> list) => [
      for (final l in list.take(_maxListLength))
        if (fits(l, _maxTextLength)) l,
    ];
    final subtitles = options.subtitleLanguages;
    final play = PlayMessage(
      url: stream.url,
      headers: headers,
      userAgent: userAgent,
      isHls: stream.isHls,
      title: _clip(title, _maxTitleLength),
      logo: optional(logo),
      channelKey: optional(channelKey),
      maxConnections: maxConnections != null && maxConnections > 0
          ? maxConnections
          : null,
      hardwareDecoding: options.hardwareDecoding,
      lite: options.lite,
      preferredLanguages: languages(options.preferredLanguages),
      subtitleLanguages: subtitles == null ? null : languages(subtitles),
      secrets: [
        for (final s in secrets)
          if (s.length >= 3 && s.length <= _maxTextLength) s,
      ].take(_maxListLength).toList(),
    );
    checkViewerPlay(play);
    if (utf8.encode(encodeViewerMessage(play)).length > kMaxViewerLineBytes) {
      throw const FormatException('line');
    }
    return play;
  }

  final String url;
  final Map<String, String> headers;
  final String? userAgent;
  final bool isHls;
  final String title;
  final String? logo;
  final String? channelKey;
  final int? maxConnections;
  final bool hardwareDecoding;
  final bool lite;
  final List<String> preferredLanguages;
  final List<String>? subtitleLanguages;
  final List<String> secrets;

  @override
  String get type => 'play';

  @override
  bool get fromViewer => false;

  /// The live stream to open.
  StreamRequest get stream => StreamRequest(
    url: url,
    kind: PlayableKind.live,
    headers: {...headers, 'User-Agent': ?userAgent},
    isHls: isHls,
    title: title,
  );

  EngineOptions get engineOptions => EngineOptions(
    lite: lite,
    hardwareDecoding: hardwareDecoding,
    preferredLanguages: preferredLanguages,
    subtitleLanguages: subtitleLanguages,
  );

  /// [text] with URL credentials and [secrets] masked.
  String redactText(String text) => redact(text, secrets: secrets);

  @override
  Map<String, Object?> toJson() => {
    'url': url,
    'headers': headers,
    'userAgent': ?userAgent,
    'isHls': isHls,
    'title': title,
    'logo': ?logo,
    'channelKey': ?channelKey,
    'maxConnections': ?maxConnections,
    'hardwareDecoding': hardwareDecoding,
    'lite': lite,
    'preferredLanguages': preferredLanguages,
    'subtitleLanguages': ?subtitleLanguages,
    'secrets': secrets,
  };

  /// Never shows the URL.
  @override
  String toString() => 'PlayMessage(${isHls ? 'hls' : 'stream'})';
}

/// One line for [message] (JSON plus `\n`; JSON escapes line breaks).
String encodeViewerMessage(ViewerMessage message) =>
    '${jsonEncode({'type': message.type, ...message.toJson()})}\n';

/// The message on [line], or null when it is not valid JSON, not an
/// object, of an unknown type or has a field of the wrong type or size.
ViewerMessage? decodeViewerMessage(String line) {
  if (line.length > kMaxViewerLineBytes) return null;
  final Object? json;
  try {
    json = jsonDecode(line);
  } on FormatException {
    return null;
  }
  if (json is! Map<String, Object?>) return null;
  try {
    return switch (json['type']) {
      'hello' => HelloMessage(
        token: _string(json['token'], max: 256),
        version: _int(json['version']),
      ),
      'ready' => const ReadyMessage(),
      'opening' => const OpeningMessage(),
      'playing' => const PlayingMessage(),
      'error' => ViewerErrorMessage(_string(json['message'], empty: true)),
      'retry' => const RetryMessage(),
      'closed' => const ClosedMessage(),
      'in-use' => InUseMessage(_inUseBy(json['by'])),
      'close' => const CloseMessage(),
      'play' => _play(json),
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

/// Whether a detached window plays [url]: an `http` or `https` URL with a
/// host, of at most 8 KiB. That is what the sources build for live
/// channels; anything else (a local file, `fd://`, `edl://`...) is refused.
bool isViewerStreamUrl(String url) {
  if (url.isEmpty || url.length > _maxUrlLength) return false;
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return false;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

/// The viewer's rules for a [PlayMessage], shared by the app
/// ([PlayMessage.of]) and the viewer ([decodeViewerMessage]) so the app
/// never sends a play the viewer would drop. Throws a [FormatException].
void checkViewerPlay(PlayMessage play) {
  if (!isViewerStreamUrl(play.url)) throw const FormatException('url');
  final maxConnections = play.maxConnections;
  if (maxConnections != null && maxConnections < 0) {
    throw const FormatException('maxConnections');
  }
}

ConnectionInUseBy _inUseBy(Object? value) {
  for (final by in ConnectionInUseBy.values) {
    if (by.name == value) return by;
  }
  throw const FormatException('by');
}

PlayMessage _play(Map<String, Object?> json) {
  final maxConnections = json['maxConnections'];
  if (maxConnections != null && maxConnections is! int) {
    throw const FormatException('maxConnections');
  }
  final subtitles = json['subtitleLanguages'];
  final play = PlayMessage(
    url: _string(json['url'], max: _maxUrlLength),
    headers: _headers(json['headers']),
    userAgent: _optionalString(json['userAgent'], max: _maxHeaderLength),
    isHls: _bool(json['isHls']),
    title: _string(json['title'], empty: true),
    logo: _optionalString(json['logo'], max: _maxUrlLength),
    channelKey: _optionalString(json['channelKey'], max: _maxUrlLength),
    maxConnections: maxConnections as int?,
    hardwareDecoding: _bool(json['hardwareDecoding']),
    lite: _bool(json['lite']),
    preferredLanguages: _strings(json['preferredLanguages']),
    subtitleLanguages: subtitles == null ? null : _strings(subtitles),
    secrets: _strings(json['secrets']),
  );
  checkViewerPlay(play);
  return play;
}

final _control = RegExp(r'[\x00-\x1f\x7f]');

/// [s] cut to [max] UTF-16 units, never inside a surrogate pair.
String _clip(String s, int max) {
  if (s.length <= max) return s;
  var end = max;
  final last = s.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end--;
  return s.substring(0, end);
}

String _string(Object? value, {int max = _maxTextLength, bool empty = false}) {
  if (value is! String || value.length > max || (!empty && value.isEmpty)) {
    throw const FormatException('string');
  }
  return value;
}

String? _optionalString(Object? value, {int max = _maxTextLength}) =>
    value == null ? null : _string(value, max: max);

bool _bool(Object? value) =>
    value is bool ? value : throw const FormatException('bool');

int _int(Object? value) =>
    value is int ? value : throw const FormatException('int');

List<String> _strings(Object? value) {
  if (value is! List<Object?> || value.length > _maxListLength) {
    throw const FormatException('list');
  }
  return [for (final v in value) _string(v)];
}

/// HTTP headers: string names and values without line breaks or other
/// control characters (they would split the header block).
Map<String, String> _headers(Object? value) {
  if (value is! Map<String, Object?> || value.length > _maxListLength) {
    throw const FormatException('headers');
  }
  return {
    for (final MapEntry(:key, :value) in value.entries)
      _headerPart(key): _headerPart(value),
  };
}

String _headerPart(Object? value) {
  final s = _string(value, max: _maxHeaderLength);
  if (_control.hasMatch(s)) throw const FormatException('header');
  return s;
}

// ---------------------------------------------------------------------------
// Framing.

/// A line longer than [kMaxViewerLineBytes] arrived.
class ViewerLineTooLong implements Exception {
  const ViewerLineTooLong();

  @override
  String toString() => 'ViewerLineTooLong';
}

/// Splits a byte stream into `\n`-terminated UTF-8 lines (a trailing `\r`
/// is dropped). A line that is not valid UTF-8 comes out as null; one
/// longer than [maxLineBytes] throws [ViewerLineTooLong].
class ViewerLineDecoder {
  ViewerLineDecoder({this.maxLineBytes = kMaxViewerLineBytes});

  final int maxLineBytes;
  final _pending = BytesBuilder(copy: true);

  /// The lines completed by [chunk].
  List<String?> add(List<int> chunk) {
    final lines = <String?>[];
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] != 0x0A) continue;
      if (_pending.length + i - start > maxLineBytes) {
        throw const ViewerLineTooLong();
      }
      _pending.add(chunk.sublist(start, i));
      lines.add(_decode(_pending.takeBytes()));
      start = i + 1;
    }
    if (start < chunk.length) {
      if (_pending.length + chunk.length - start > maxLineBytes) {
        throw const ViewerLineTooLong();
      }
      _pending.add(chunk.sublist(start));
    }
    return lines;
  }

  static String? _decode(Uint8List bytes) {
    var end = bytes.length;
    if (end > 0 && bytes[end - 1] == 0x0D) end--;
    try {
      return utf8.decode(Uint8List.sublistView(bytes, 0, end));
    } on FormatException {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Connection.

/// One side's end of the connection: decoded messages in, encoded out.
abstract interface class ViewerChannel {
  /// Messages from the other side, in order (single subscription).
  Stream<ViewerMessage> get messages;

  /// Completes once the connection is closed, by either side.
  Future<void> get done;

  bool get isClosed;

  /// Sends [message]; false when the connection is closed.
  bool send(ViewerMessage message);

  /// Waits (bounded) until what was sent has been handed to the system.
  Future<void> flush();

  /// Closes the connection at once.
  void close();
}

/// A [ViewerChannel] over a [Socket]. Only messages for this side pass
/// ([acceptFromViewer]: the app's end takes viewer messages); malformed,
/// misdirected or non-UTF-8 lines go to [onMalformed] (with their length
/// only) and are dropped. A line over [kMaxViewerLineBytes] closes it.
class SocketViewerChannel implements ViewerChannel {
  SocketViewerChannel(
    this._socket, {
    required this.acceptFromViewer,
    this.onMalformed,
    int maxLineBytes = kMaxViewerLineBytes,
  }) : _lines = ViewerLineDecoder(maxLineBytes: maxLineBytes) {
    _sub = _socket.listen(
      _onData,
      onError: (Object _) => close(),
      onDone: close,
      cancelOnError: true,
    );
    // Write errors surface here; the channel just closes.
    unawaited(_socket.done.then<void>((_) {}, onError: (Object _) {}));
  }

  final Socket _socket;
  final bool acceptFromViewer;

  /// Told about a dropped line (never its content: it may hold a URL).
  final void Function(String reason)? onMalformed;

  final ViewerLineDecoder _lines;
  late final StreamSubscription<Uint8List> _sub;
  final _messages = StreamController<ViewerMessage>();
  final _done = Completer<void>();
  bool _closed = false;

  @override
  Stream<ViewerMessage> get messages => _messages.stream;

  @override
  Future<void> get done => _done.future;

  @override
  bool get isClosed => _closed;

  void _onData(Uint8List chunk) {
    if (_closed) return;
    final List<String?> lines;
    try {
      lines = _lines.add(chunk);
    } on ViewerLineTooLong {
      onMalformed?.call('line too long');
      close();
      return;
    }
    for (final line in lines) {
      if (_closed) return;
      if (line == null || line.trim().isEmpty) {
        if (line == null) onMalformed?.call('not UTF-8');
        continue;
      }
      final message = decodeViewerMessage(line);
      if (message == null || message.fromViewer != acceptFromViewer) {
        onMalformed?.call('malformed line of ${line.length} chars');
        continue;
      }
      _messages.add(message);
    }
  }

  @override
  bool send(ViewerMessage message) {
    if (_closed) return false;
    try {
      _socket.write(encodeViewerMessage(message));
      return true;
    } on Object catch (_) {
      close();
      return false;
    }
  }

  @override
  Future<void> flush() async {
    if (_closed) return;
    try {
      await _socket.flush().timeout(const Duration(seconds: 1));
    } on Object catch (_) {
      // Closed or stuck: nothing more to wait for.
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    unawaited(_sub.cancel());
    _socket.destroy();
    unawaited(_messages.close());
    _done.complete();
  }
}
