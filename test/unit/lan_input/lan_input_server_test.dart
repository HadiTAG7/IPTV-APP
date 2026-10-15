@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/core/net/lan_input_server.dart';

import '../../support/real_http.dart';

class _Addr implements InterfaceAddress {
  _Addr(String address) : _address = InternetAddress(address);

  final InternetAddress _address;

  @override
  String get address => _address.address;

  @override
  InternetAddressType get type => _address.type;

  @override
  bool get isLoopback => _address.isLoopback;

  @override
  Uint8List get rawAddress => _address.rawAddress;

  @override
  int get prefixLength => 24;

  @override
  InternetAddress? get broadcast => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Iface implements NetworkInterface {
  _Iface(this.name, List<String> addresses)
    : addresses = [for (final a in addresses) _Addr(a)];

  @override
  final String name;

  @override
  final List<InterfaceAddress> addresses;

  @override
  int get index => 0;
}

/// Status and body of a request, or null when the connection failed.
typedef _Reply = ({int status, String body})?;

Future<_Reply> _request(
  String method,
  Uri uri, {
  Map<String, String>? form,
  List<int>? body,
  int? declaredLength,
  ContentType? contentType,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, uri);
    if (form != null) {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(Uri(queryParameters: form).query);
    } else if (body != null) {
      request.headers.contentType =
          contentType ?? ContentType('application', 'octet-stream');
      if (declaredLength != null) request.contentLength = declaredLength;
      request.add(body);
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    return (status: response.statusCode, body: text);
  } on IOException {
    return null;
  } finally {
    client.close(force: true);
  }
}

void main() {
  useRealHttp();

  late Directory uploads;
  late RingLog log;
  final servers = <LanInputServer>[];

  setUp(() async {
    uploads = await Directory.systemTemp.createTemp('lan_test');
    log = RingLog();
  });

  tearDown(() async {
    for (final s in servers) {
      await s.close();
    }
    servers.clear();
    if (uploads.existsSync()) await uploads.delete(recursive: true);
  });

  Future<LanInputServer> start({
    LanForm form = LanForm.source,
    Duration lifetime = LanInputServer.defaultLifetime,
    int maxUploadBytes = LanInputServer.defaultMaxUploadBytes,
  }) async {
    final server = await LanInputServer.start(
      form: form,
      address: InternetAddress.loopbackIPv4,
      lifetime: lifetime,
      maxUploadBytes: maxUploadBytes,
      uploadDir: uploads.path,
      log: log,
    );
    servers.add(server);
    return server;
  }

  Uri at(LanInputServer s, String path, [Map<String, String>? query]) => Uri(
    scheme: 'http',
    host: s.address.address,
    port: s.port,
    path: path,
    queryParameters: query,
  );

  Uri withToken(LanInputServer s, String path, [Map<String, String>? extra]) =>
      at(s, path, {'t': s.token, ...?extra});

  group('start', () {
    test('binds and returns a one-time URL with a 6-digit token', () async {
      final server = await start();
      expect(server.token, matches(RegExp(r'^\d{6}$')));
      expect(server.port, greaterThan(0));
      expect(server.url, 'http://127.0.0.1:${server.port}/?t=${server.token}');
      expect(server.status, LanInputStatus.waiting);

      final page = await _request('GET', Uri.parse(server.url));
      expect(page!.status, HttpStatus.ok);
      expect(page.body, contains('Xtream Codes'));
      expect(page.body, contains('/submit?t=${server.token}'));
      expect(page.body, contains('/upload?t=${server.token}'));
      expect(page.body, contains('dir="rtl"'));
    });

    test('tokens differ between servers', () async {
      final a = await LanInputServer.start(
        address: InternetAddress.loopbackIPv4,
        random: Random(1),
      );
      final b = await LanInputServer.start(
        address: InternetAddress.loopbackIPv4,
        random: Random(2),
      );
      servers.addAll([a, b]);
      expect(a.token, isNot(b.token));
      expect(a.port, isNot(b.port));
    });

    test('no network: LanNoNetworkException', () async {
      Future<List<NetworkInterface>> none({
        bool includeLoopback = false,
        bool includeLinkLocal = false,
        InternetAddressType type = InternetAddressType.any,
      }) async => [];
      expect(
        LanInputServer.start(listInterfaces: none),
        throwsA(isA<LanNoNetworkException>()),
      );
    });

    test('the search form has one text field', () async {
      final server = await start(form: LanForm.search);
      final page = await _request('GET', Uri.parse(server.url));
      expect(page!.body, contains('name="text"'));
      expect(page.body, isNot(contains('name="password"')));
    });
  });

  group('token', () {
    test('required on every path (403 without or with a wrong one)', () async {
      final server = await start();
      final wrong = server.token == '000000' ? '111111' : '000000';
      for (final uri in [
        at(server, '/'),
        at(server, '/', {'t': wrong}),
        at(server, '/', {'t': '${server.token}0'}),
      ]) {
        final reply = await _request('GET', uri);
        expect(reply!.status, HttpStatus.forbidden, reason: '$uri');
        expect(reply.body, isNot(contains('password')));
      }
      final post = await _request(
        'POST',
        at(server, '/submit', {'t': wrong}),
        form: {'kind': 'm3u', 'url': 'http://example.com/a.m3u'},
      );
      expect(post!.status, HttpStatus.forbidden);
      final upload = await _request(
        'POST',
        at(server, '/upload'),
        body: utf8.encode('#EXTM3U\n'),
      );
      expect(upload!.status, HttpStatus.forbidden);
      expect(server.status, LanInputStatus.waiting);
      expect(uploads.listSync(), isEmpty);
    });

    test('too many wrong codes stop the server', () async {
      final server = await start();
      final wrong = server.token == '000000' ? '111111' : '000000';
      for (var i = 0; i < LanInputServer.maxBadTokens; i++) {
        await _request('GET', at(server, '/', {'t': wrong}));
      }
      expect(await server.result, isNull);
      expect(server.status, LanInputStatus.expired);
      final after = await _request('GET', Uri.parse(server.url));
      expect(after?.status, anyOf(isNull, isNot(HttpStatus.ok)));
    });

    test('unknown paths are 404 and do not count as guesses', () async {
      final server = await start();
      for (var i = 0; i < LanInputServer.maxBadTokens + 5; i++) {
        final reply = await _request('GET', at(server, '/favicon.ico'));
        expect(reply!.status, HttpStatus.notFound);
      }
      expect(server.status, LanInputStatus.waiting);
    });
  });

  group('submit', () {
    test('Xtream fields round-trip; the password is kept as typed', () async {
      final server = await start();
      const password = ' p@ss wörd&=+ ';
      final reply = await _request(
        'POST',
        withToken(server, '/submit'),
        form: {
          'kind': 'xtream',
          'server': '  http://panel.example.com:8080 ',
          'username': 'user name',
          'password': password,
        },
      );
      expect(reply!.status, HttpStatus.ok);
      final submission = await server.result;
      expect(submission!.kind, LanSubmissionKind.xtream);
      expect(submission['server'], 'http://panel.example.com:8080');
      expect(submission['username'], 'user name');
      expect(submission['password'], password);
      expect(submission.toString(), isNot(contains('panel')));
      expect(server.status, LanInputStatus.received);
      // Nothing the phone sent reaches the log.
      final dump = log.dump();
      expect(dump, isNot(contains('wörd')));
      expect(dump, isNot(contains('user name')));
      expect(dump, isNot(contains(server.token)));
    });

    test('an M3U link and search text round-trip', () async {
      final source = await start();
      await _request(
        'POST',
        withToken(source, '/submit'),
        form: {
          'kind': 'm3u',
          'url': 'http://h.example/get.php?username=u&password=p',
        },
      );
      final link = await source.result;
      expect(link!.kind, LanSubmissionKind.m3uUrl);
      expect(link['url'], 'http://h.example/get.php?username=u&password=p');

      final search = await start(form: LanForm.search);
      await _request(
        'POST',
        withToken(search, '/submit'),
        form: {'kind': 'search', 'text': 'قناة الأخبار News'},
      );
      final text = await search.result;
      expect(text!.kind, LanSubmissionKind.search);
      expect(text['text'], 'قناة الأخبار News');
    });

    test(
      'missing fields or a foreign kind are refused; it keeps waiting',
      () async {
        final server = await start();
        for (final form in [
          {'kind': 'xtream', 'server': 'http://h', 'username': 'u'},
          {'kind': 'm3u', 'url': '   '},
          {'kind': 'search', 'text': 'x'},
          {'url': 'http://h/a.m3u'},
        ]) {
          final reply = await _request(
            'POST',
            withToken(server, '/submit'),
            form: form,
          );
          expect(reply!.status, HttpStatus.badRequest, reason: '$form');
        }
        final json = await _request(
          'POST',
          withToken(server, '/submit'),
          body: utf8.encode('{"kind":"m3u"}'),
          contentType: ContentType.json,
        );
        expect(json!.status, HttpStatus.unsupportedMediaType);
        expect(server.status, LanInputStatus.waiting);
      },
    );

    test('only the first submission counts; then the server stops', () async {
      final server = await start();
      final first = await _request(
        'POST',
        withToken(server, '/submit'),
        form: {'kind': 'm3u', 'url': 'http://one.example/a.m3u'},
      );
      expect(first!.status, HttpStatus.ok);
      final submission = await server.result;
      expect(submission!['url'], 'http://one.example/a.m3u');
      final second = await _request(
        'POST',
        withToken(server, '/submit'),
        form: {'kind': 'm3u', 'url': 'http://two.example/b.m3u'},
      );
      expect(second?.status, anyOf(isNull, HttpStatus.gone));
      expect(await server.result, same(submission));
      expect(server.status, LanInputStatus.received);
    });

    test('a form body over the limit is refused', () async {
      final server = await start();
      final reply = await _request(
        'POST',
        withToken(server, '/submit'),
        form: {'kind': 'm3u', 'url': 'http://h/${'a' * 20000}'},
      );
      expect(reply?.status, anyOf(isNull, HttpStatus.requestEntityTooLarge));
      expect(server.status, LanInputStatus.waiting);
    });
  });

  group('expiry', () {
    test('after its lifetime the code expires and the server stops', () async {
      final server = await start(lifetime: const Duration(milliseconds: 200));
      final statuses = <LanInputStatus>[];
      final sub = server.statusChanges.listen(statuses.add);
      expect(await server.result, isNull);
      await sub.cancel();
      expect(server.status, LanInputStatus.expired);
      expect(statuses, [LanInputStatus.expired]);
      final reply = await _request('GET', Uri.parse(server.url));
      expect(reply?.status, anyOf(isNull, isNot(HttpStatus.ok)));
    });

    test('close stops it and delivers null', () async {
      final server = await start();
      await server.close();
      expect(await server.result, isNull);
      expect(server.status, LanInputStatus.closed);
      expect(await _request('GET', Uri.parse(server.url)), isNull);
    });
  });

  group('upload', () {
    test('a playlist upload is streamed to a temp file', () async {
      final server = await start();
      final content = '#EXTM3U\n#EXTINF:-1,One\nhttp://h/1.ts\n' * 200;
      final reply = await _request(
        'POST',
        withToken(server, '/upload', {'name': '../../evil/My list.m3u'}),
        body: utf8.encode(content),
      );
      expect(reply!.status, HttpStatus.ok);
      final submission = await server.result;
      expect(submission!.kind, LanSubmissionKind.m3uFile);
      expect(submission.fileName, 'My list.m3u');
      final file = File(submission.filePath!);
      expect(file.parent.path, uploads.path);
      expect(await file.readAsString(), content);
      await deleteTempUpload(file.path);
      expect(file.existsSync(), isFalse);
    });

    test('the size limit is enforced; nothing is kept', () async {
      final server = await start(maxUploadBytes: 1024);
      // Streamed without a length: cut off once over the limit.
      final big = await _request(
        'POST',
        withToken(server, '/upload', {'name': 'big.m3u'}),
        body: List.filled(4096, 0x41),
      );
      expect(big?.status, anyOf(isNull, HttpStatus.requestEntityTooLarge));
      // A declared length over the limit is refused before reading.
      final declared = await _request(
        'POST',
        withToken(server, '/upload', {'name': 'big.m3u'}),
        body: List.filled(2048, 0x41),
        declaredLength: 2048,
      );
      expect(declared?.status, anyOf(isNull, HttpStatus.requestEntityTooLarge));
      expect(server.status, LanInputStatus.waiting);
      expect(uploads.listSync(), isEmpty);

      // A file within the limit still works afterwards.
      final ok = await _request(
        'POST',
        withToken(server, '/upload', {'name': 'small.m3u'}),
        body: utf8.encode('#EXTM3U\n'),
      );
      expect(ok!.status, HttpStatus.ok);
      final submission = await server.result;
      expect(File(submission!.filePath!).lengthSync(), 8);
    });

    test('an empty upload is refused', () async {
      final server = await start();
      final reply = await _request(
        'POST',
        withToken(server, '/upload'),
        body: const [],
      );
      expect(reply!.status, HttpStatus.badRequest);
      expect(server.status, LanInputStatus.waiting);
      expect(uploads.listSync(), isEmpty);
    });

    test('the search form takes no uploads', () async {
      final server = await start(form: LanForm.search);
      final reply = await _request(
        'POST',
        withToken(server, '/upload'),
        body: utf8.encode('#EXTM3U\n'),
      );
      expect(reply!.status, HttpStatus.methodNotAllowed);
      expect(uploads.listSync(), isEmpty);
    });

    test('writeTempUpload copies a stream and enforces its limit', () async {
      final path = await writeTempUpload(
        Stream.fromIterable([
          utf8.encode('#EXTM3U\n'),
          utf8.encode('#EXTINF:-1,A\n'),
        ]),
        dir: uploads.path,
      );
      expect(await File(path).readAsString(), '#EXTM3U\n#EXTINF:-1,A\n');
      await expectLater(
        writeTempUpload(
          Stream.fromIterable([List.filled(10, 1), List.filled(10, 1)]),
          maxBytes: 15,
          dir: uploads.path,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(uploads.listSync().map((e) => e.path), [path]);
    });
  });

  group('helpers', () {
    test('findLanAddress prefers a private IPv4 and skips loopback', () async {
      Future<List<NetworkInterface>> list({
        bool includeLoopback = false,
        bool includeLinkLocal = false,
        InternetAddressType type = InternetAddressType.any,
      }) async => [
        _Iface('lo', ['127.0.0.1']),
        _Iface('rmnet0', ['100.64.3.4']),
        _Iface('wlan0', ['192.168.1.23', 'fe80::1']),
      ];
      final address = await findLanAddress(list: list);
      expect(address!.address, '192.168.1.23');
    });

    test('findLanAddress falls back to listing everything', () async {
      final calls = <bool>[];
      Future<List<NetworkInterface>> list({
        bool includeLoopback = false,
        bool includeLinkLocal = false,
        InternetAddressType type = InternetAddressType.any,
      }) async {
        calls.add(includeLinkLocal);
        return includeLinkLocal
            ? [
                _Iface('eth0', ['169.254.10.20']),
              ]
            : [
                _Iface('lo', ['127.0.0.1']),
              ];
      }

      final address = await findLanAddress(list: list);
      expect(address!.address, '169.254.10.20');
      expect(calls, [false, true]);
    });

    test('findLanAddress: null when nothing is usable', () async {
      Future<List<NetworkInterface>> list({
        bool includeLoopback = false,
        bool includeLinkLocal = false,
        InternetAddressType type = InternetAddressType.any,
      }) async => throw const SocketException('no interfaces');
      expect(await findLanAddress(list: list), isNull);
    });

    test('isPrivateIPv4', () {
      for (final a in [
        '10.0.0.1',
        '172.16.0.1',
        '172.31.255.1',
        '192.168.0.9',
      ]) {
        expect(isPrivateIPv4(InternetAddress(a)), isTrue, reason: a);
      }
      for (final a in ['172.32.0.1', '100.64.0.1', '8.8.8.8', '::1']) {
        expect(isPrivateIPv4(InternetAddress(a)), isFalse, reason: a);
      }
    });

    test('sanitizeFileName', () {
      expect(sanitizeFileName(r'C:\Users\me\list.m3u'), 'list.m3u');
      expect(sanitizeFileName('a/b/../..'), 'playlist.m3u');
      expect(sanitizeFileName('bad\u0000name\n.m3u'), 'badname.m3u');
      expect(sanitizeFileName(null), 'playlist.m3u');
      expect(sanitizeFileName('x' * 300).length, 100);
    });

    test('parseLanForm trims, caps and checks the kind', () {
      final xtream = parseLanForm(LanForm.source, {
        'kind': 'xtream',
        'server': ' s ',
        'username': ' u ',
        'password': ' p ',
      });
      expect(xtream!.fields, {
        'server': 's',
        'username': 'u',
        'password': ' p ',
      });
      final long = parseLanForm(LanForm.source, {
        'kind': 'm3u',
        'url': 'h' * 5000,
      });
      expect(long!['url']!.length, LanInputServer.maxFieldLength);
      expect(parseLanForm(LanForm.search, {'kind': 'm3u', 'url': 'x'}), isNull);
      expect(
        parseLanForm(LanForm.source, {'kind': 'search', 'text': 'x'}),
        isNull,
      );
    });
  });
}
