import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/net/http.dart';
import 'package:iptv_player/sources/m3u/byte_source.dart';
import 'package:iptv_player/sources/m3u/m3u_adapter.dart';
import 'package:iptv_player/sources/models.dart';

void main() {
  group('HttpByteSource against a local server', () {
    late HttpServer server;
    late String base;
    final requests = <HttpRequest>[];
    final held = <HttpResponse>[];
    final playlist = File('test/fixtures/m3u/mixed.m3u').readAsBytesSync();

    setUp(() async {
      requests.clear();
      held.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        requests.add(req);
        final res = req.response;
        switch (req.uri.path) {
          case '/list.m3u':
            res.headers.contentType = ContentType('audio', 'x-mpegurl');
            res.add(playlist);
            await res.close();
          case '/forbidden':
            res.statusCode = HttpStatus.forbidden;
            await res.close();
          case '/endless':
            // Sends a header and lots of filler, then never finishes.
            held.add(res);
            res.write('#EXTM3U\n');
            for (var i = 0; i < 40; i++) {
              res.write('${'#' * 4095}\n');
            }
            unawaited(res.flush().catchError((Object _) {}));
            unawaited(res.done.catchError((Object _) {}));
          default:
            res.statusCode = HttpStatus.notFound;
            await res.close();
        }
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('M3U URL source syncs over HTTP with source headers', () async {
      final adapter = M3uAdapter(
        SourceConfig(
          kind: SourceKind.m3uUrl,
          url: '$base/list.m3u',
          userAgent: 'SourceUA/1.0',
          referer: 'http://ref.example.com/',
        ),
        dio: createDio(),
      );
      expect((await adapter.verify()).status, AccountStatus.active);
      final batches = await adapter.fetchCatalog().toList();
      expect(batches.whereType<ChannelsBatch>().single.items, hasLength(3));
      expect(batches.whereType<EpisodesBatch>().single.items, hasLength(4));
      expect(requests.last.headers.value('user-agent'), 'SourceUA/1.0');
      expect(requests.last.headers.value('referer'), 'http://ref.example.com/');
      adapter.close();
    });

    test('dio defaults apply when the source has no User-Agent', () async {
      final source = HttpByteSource(createDio(), '$base/list.m3u');
      final bytes = await source.open().expand((c) => c).toList();
      expect(bytes, playlist);
      expect(requests.single.headers.value('user-agent'), kDefaultUserAgent);
    });

    test('HTTP errors map to SourceFailures without credentials', () async {
      final source = HttpByteSource(
        createDio(),
        '$base/missing.m3u?username=bob&password=s3cret',
      );
      final error = await source.open().drain<void>().then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      expect(
        error,
        isA<NetworkFailure>().having((f) => f.statusCode, 'status', 404),
      );
      final message = (error! as SourceFailure).message;
      expect(message, isNot(contains('s3cret')));
      expect(message, isNot(contains('bob')));
    });

    test('403 is an AuthFailure', () async {
      final source = HttpByteSource(createDio(), '$base/forbidden');
      await expectLater(
        source.open().drain<void>(),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('connection refused is a NetworkFailure', () async {
      final port = server.port;
      await server.close(force: true);
      final source = HttpByteSource(
        createDio(connectTimeout: const Duration(seconds: 2)),
        'http://127.0.0.1:$port/list.m3u',
      );
      await expectLater(
        source.open().drain<void>(),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('verify stops after the first 64 KB of an endless body', () async {
      final adapter = M3uAdapter(
        SourceConfig(kind: SourceKind.m3uUrl, url: '$base/endless'),
        dio: createDio(),
      );
      final info = await adapter.verify().timeout(const Duration(seconds: 10));
      expect(info.status, AccountStatus.active);
    });

    test('cancel() aborts a download in progress', () async {
      final source = HttpByteSource(createDio(), '$base/endless');
      final error = Completer<Object>();
      source.open().listen(
        (_) => source.cancel(),
        onError: (Object e) {
          if (!error.isCompleted) error.complete(e);
        },
      );
      expect(
        await error.future.timeout(const Duration(seconds: 10)),
        isA<CancelledFailure>(),
      );
    });

    test('adapter close() aborts a running fetch', () async {
      final adapter = M3uAdapter(
        SourceConfig(kind: SourceKind.m3uUrl, url: '$base/endless'),
        dio: createDio(),
      );
      final result = adapter.fetchCatalog().toList();
      while (requests.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      adapter.close();
      await expectLater(
        result.timeout(const Duration(seconds: 10)),
        throwsA(isA<CancelledFailure>()),
      );
    });

    test('a cancelled parent token fails new reads at once', () async {
      final parent = CancelToken()..cancel();
      final source = HttpByteSource(
        createDio(),
        '$base/list.m3u',
        cancelToken: parent,
      );
      await expectLater(
        source.open().drain<void>(),
        throwsA(isA<CancelledFailure>()),
      );
      expect(requests, isEmpty);
    });
  });

  group('FileByteSource', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('m3u_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('reads the file', () async {
      final file = File('${dir.path}/list.m3u')..writeAsStringSync('#EXTM3U\n');
      final bytes = await FileByteSource(file.path)
          .open()
          .expand((c) => c)
          .toList();
      expect(utf8.decode(bytes), '#EXTM3U\n');
    });

    test('missing file is a SourceFailure', () async {
      await expectLater(
        FileByteSource('${dir.path}/nope.m3u').open().drain<void>(),
        throwsA(isA<SourceFailure>()),
      );
    });

    test('cancel() stops a read in progress', () async {
      final file = File('${dir.path}/big.m3u')
        ..writeAsBytesSync(List.filled(1024 * 1024, 0x23));
      final source = FileByteSource(file.path);
      await expectLater(
        source.open().map((chunk) {
          source.cancel();
          return chunk;
        }).drain<void>(),
        throwsA(isA<CancelledFailure>()),
      );
    });
  });

  test('MemoryByteSource chunks and cancels', () async {
    final source = MemoryByteSource(List.filled(10, 1), chunkSize: 4);
    expect((await source.open().toList()).map((c) => c.length), [4, 4, 2]);
    await expectLater(
      source.open().map((c) {
        source.cancel();
        return c;
      }).drain<void>(),
      throwsA(isA<CancelledFailure>()),
    );
  });
}
