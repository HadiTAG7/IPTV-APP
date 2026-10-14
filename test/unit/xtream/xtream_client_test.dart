import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/sources/xtream/xtream_client.dart';
import 'package:iptv_player/sources/xtream/xtream_urls.dart';

import 'support/fake_http_adapter.dart';

const _user = 'demo user';
const _pass = 'p@ss/w rd';

/// Every spelling of the credentials that must never leak.
const _leaks = [
  _user,
  _pass,
  'demo%20user',
  'p%40ss%2Fw%20rd',
  'demo+user',
  'p%40ss%2Fw+rd',
];

void expectNoSecrets(String text) {
  for (final s in _leaks) {
    expect(text, isNot(contains(s)), reason: 'leaked "$s" in: $text');
  }
}

void main() {
  late FakeHttpAdapter adapter;
  late XtreamClient client;
  final now = FakeClock(DateTime.utc(2025, 10, 14, 12));

  setUp(() {
    adapter = FakeHttpAdapter();
    client = XtreamClient(
      XtreamUrls('http://panel.example.com:8080/', _user, _pass),
      fakeDio(adapter),
      clock: now,
    );
  });

  Future<SourceFailure> failureOf(Future<Object?> f) async {
    try {
      await f;
    } on SourceFailure catch (e) {
      return e;
    }
    fail('expected a SourceFailure');
  }

  group('authenticate', () {
    test('good login maps every field', () async {
      adapter.routes[''] = FakeReply.fixture('auth_ok.json');
      final info = await client.authenticate();
      expect(info.status, AccountStatus.active);
      expect(info.expiresAt, DateTime.utc(2030));
      expect(info.maxConnections, 1);
      expect(info.activeConnections, 0);
      expect(info.allowedFormats, ['m3u8', 'ts', 'rtmp']);
      expect(info.isTrial, isFalse);
      expect(info.serverTimezone, 'Asia/Riyadh');

      final req = adapter.requests.single;
      expect(req.uri.path, '/player_api.php');
      expect(req.uri.queryParameters, {'username': _user, 'password': _pass});
      expect(req.uri.toString(), contains('password=p%40ss%2Fw%20rd'));
    });

    test('expired by status', () async {
      adapter.routes[''] = FakeReply.fixture('auth_expired_status.json');
      final info = await client.authenticate();
      expect(info.status, AccountStatus.expired);
      expect(info.expiresAt, DateTime.utc(2023, 11, 14, 22, 13, 20));
      expect(info.isTrial, isTrue);
      expect(info.allowedFormats, ['ts']);
      expect(info.serverTimezone, 'UTC');
    });

    test('expired by date even when status says Active', () async {
      adapter.routes[''] = FakeReply.fixture('auth_expired_date.json');
      final info = await client.authenticate();
      expect(info.status, AccountStatus.expired);
      expect(info.maxConnections, 2);
      expect(info.activeConnections, 1);
      expect(info.allowedFormats, isEmpty);
      expect(info.serverTimezone, isNull);
    });

    test('banned, never expires, formats as a map', () async {
      adapter.routes[''] = FakeReply.fixture('auth_banned.json');
      final info = await client.authenticate();
      expect(info.status, AccountStatus.banned);
      expect(info.expiresAt, isNull);
      expect(info.allowedFormats, ['m3u8', 'ts']);
    });

    test('disabled and unknown statuses', () async {
      adapter.routes[''] = FakeReply.json({
        'user_info': {'auth': 1, 'status': 'Disabled', 'exp_date': '0'},
      });
      expect((await client.authenticate()).status, AccountStatus.disabled);
      adapter.routes[''] = FakeReply.json({
        'user_info': {'auth': 1, 'status': 'Weird', 'exp_date': ''},
      });
      final info = await client.authenticate();
      expect(info.status, AccountStatus.unknown);
      expect(info.expiresAt, isNull);
    });

    test('missing status with auth 1 is active', () async {
      adapter.routes[''] = FakeReply.json({
        'user_info': {'auth': '1'},
      });
      expect((await client.authenticate()).status, AccountStatus.active);
    });

    test('auth 0 with HTTP 200 is an AuthFailure', () async {
      adapter.routes[''] = FakeReply.fixture('auth_zero.json');
      final f = await failureOf(client.authenticate());
      expect(f, isA<AuthFailure>());
      expect((f as AuthFailure).status, AccountStatus.unknown);
    });

    test('auth 0 keeps a known status', () async {
      adapter.routes[''] = FakeReply.json({
        'user_info': {'auth': 0, 'status': 'Banned'},
      });
      final f = await failureOf(client.authenticate());
      expect((f as AuthFailure).status, AccountStatus.banned);
    });

    for (final (name, body) in [
      ('[] body', '[]'),
      ('{} body', '{}'),
      ('empty body', ''),
      ('whitespace body', ' \n '),
      ('null body', 'null'),
      ('missing user_info', '{"server_info":{"timezone":"UTC"}}'),
      ('user_info []', '{"user_info":[]}'),
      ('scalar list', '[1,2]'),
    ]) {
      test('$name with HTTP 200 is an AuthFailure', () async {
        adapter.routes[''] = FakeReply.text(body, contentType: 'text/plain');
        expect(await failureOf(client.authenticate()), isA<AuthFailure>());
      });
    }

    test('HTML error page with HTTP 200 is a ParseFailure', () async {
      adapter.routes[''] = FakeReply.text(
        '<html><body><h1>Welcome to nginx!</h1></body></html>',
      );
      final f = await failureOf(client.authenticate());
      expect(f, isA<ParseFailure>());
      expectNoSecrets(f.message);
      expect(f.message, contains('panel.example.com'));
    });

    test('HTML error page with HTTP 404 is a NetworkFailure', () async {
      adapter.routes[''] = FakeReply.text(
        '<html>Not Found</html>',
        status: 404,
      );
      final f = await failureOf(client.authenticate());
      expect(f, isA<NetworkFailure>());
      expect((f as NetworkFailure).statusCode, 404);
      expectNoSecrets(f.message);
    });

    test('HTTP 403 is an AuthFailure', () async {
      adapter.routes[''] = FakeReply.text('Forbidden', status: 403);
      expect(await failureOf(client.authenticate()), isA<AuthFailure>());
    });

    test('BOM before JSON is tolerated', () async {
      adapter.routes[''] = FakeReply.text(
        '﻿${xtreamFixture('auth_ok.json')}',
        contentType: 'application/json',
      );
      expect((await client.authenticate()).status, AccountStatus.active);
    });
  });

  group('redaction', () {
    test('connection errors never contain credentials', () async {
      adapter.routes[''] = (RequestOptions r) =>
          throw DioException.connectionError(
            requestOptions: r,
            reason: 'Connection refused for ${r.uri} (user $_user / $_pass)',
          );
      final f = await failureOf(client.authenticate());
      expect(f, isA<NetworkFailure>());
      expectNoSecrets(f.message);
      expectNoSecrets(f.toString());
      expect(f.message, contains('panel.example.com'));
    });

    test('stream failures never contain credentials', () async {
      adapter.routes['get_live_streams'] = FakeReply.text('oops', status: 500);
      final f = await failureOf(client.getLiveStreams().toList());
      expect(f, isA<NetworkFailure>());
      expect((f as NetworkFailure).statusCode, 500);
      expectNoSecrets(f.message);
    });

    test('parse failures in streams never contain credentials', () async {
      adapter.routes['get_vod_streams'] = FakeReply.text('<html>error</html>');
      final f = await failureOf(client.getVodStreams().toList());
      expect(f, isA<ParseFailure>());
      expectNoSecrets(f.message);
    });

    test('timeouts never contain credentials', () async {
      adapter.routes['get_series'] = FakeReply.json(
        [],
        delay: const Duration(seconds: 5),
      );
      final f = await failureOf(
        client
            .getSeries(idleTimeout: const Duration(milliseconds: 50))
            .toList(),
      );
      expect(f, isA<TimeoutFailure>());
      expectNoSecrets(f.message);
    });
  });

  group('categories', () {
    test('live, vod and series categories', () async {
      adapter.routes
        ..['get_live_categories'] = FakeReply.fixture('live_categories.json')
        ..['get_vod_categories'] = FakeReply.fixture('vod_categories.json')
        ..['get_series_categories'] = FakeReply.fixture(
          'series_categories.json',
        );
      expect(await client.getLiveCategories(), hasLength(4));
      expect(await client.getVodCategories(), hasLength(2));
      expect((await client.getSeriesCategories()).single['category_id'], '500');
      expect(adapter.calls, [
        'get_live_categories',
        'get_vod_categories',
        'get_series_categories',
      ]);
    });

    test('object-shaped and empty responses', () async {
      adapter.routes['get_live_categories'] = FakeReply.json({
        '0': {'category_id': '1', 'category_name': 'A'},
        '1': {'category_id': '2', 'category_name': 'B'},
      });
      expect(await client.getLiveCategories(), hasLength(2));
      adapter.routes['get_live_categories'] = FakeReply.text(
        '',
        contentType: 'application/json',
      );
      expect(await client.getLiveCategories(), isEmpty);
      adapter.routes['get_live_categories'] = FakeReply.json({});
      expect(await client.getLiveCategories(), isEmpty);
    });
  });

  group('streams', () {
    test('streams list items across small chunks', () async {
      adapter.routes['get_live_streams'] = FakeReply.fixture(
        'live_streams.json',
        chunkSize: 7,
      );
      final items = await client.getLiveStreams().toList();
      expect(items, hasLength(6));
      expect(items[1]['name'], 'قناة الأخبار التجريبية');
      expect(adapter.calls, ['get_live_streams']);
    });

    test('category filter and action names', () async {
      adapter.routes
        ..['get_live_streams'] = FakeReply.json([])
        ..['get_vod_streams'] = FakeReply.json([])
        ..['get_series'] = FakeReply.json([]);
      await client.getLiveStreams(categoryId: '10').toList();
      await client.getVodStreams(categoryId: '100').toList();
      await client.getSeries(categoryId: '500').toList();
      expect(adapter.calls, [
        'get_live_streams?category_id=10',
        'get_vod_streams?category_id=100',
        'get_series?category_id=500',
      ]);
    });

    test('object-shaped stream list', () async {
      adapter.routes['get_vod_streams'] = FakeReply.json({
        '0': {'stream_id': 1},
        '1': {'stream_id': 2},
      }, chunkSize: 5);
      expect(await client.getVodStreams().toList(), hasLength(2));
    });

    test('idle timeout before headers', () async {
      adapter.routes['get_live_streams'] = FakeReply.json(
        [],
        delay: const Duration(seconds: 10),
      );
      final sw = Stopwatch()..start();
      final f = await failureOf(
        client
            .getLiveStreams(idleTimeout: const Duration(milliseconds: 80))
            .toList(),
      );
      expect(f, isA<TimeoutFailure>());
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      await pumpEventQueue();
      expect(adapter.cancelledCount, 1);
    });

    test('idle timeout mid-body', () async {
      adapter.routes['get_live_streams'] = FakeReply.fixture(
        'live_streams.json',
        chunkSize: 400,
        chunkDelay: const Duration(seconds: 10),
      );
      final got = <Map<String, Object?>>[];
      final f = await failureOf(
        client
            .getLiveStreams(idleTimeout: const Duration(milliseconds: 80))
            .forEach(got.add),
      );
      expect(f, isA<TimeoutFailure>());
      expect(got, isNotEmpty);
      expect(got.length, lessThan(6));
    });

    test('no idle timeout lets slow responses finish', () async {
      adapter.routes['get_live_streams'] = FakeReply.fixture(
        'live_streams.json',
        delay: const Duration(milliseconds: 100),
        chunkSize: 300,
        chunkDelay: const Duration(milliseconds: 20),
      );
      expect(await client.getLiveStreams().toList(), hasLength(6));
    });

    test('truncated body is a ParseFailure', () async {
      adapter.routes['get_live_streams'] = FakeReply.text(
        '[{"stream_id":1},{"stream_id":',
        contentType: 'application/json',
      );
      expect(
        await failureOf(client.getLiveStreams().toList()),
        isA<ParseFailure>(),
      );
    });

    test('cancelling the subscription cancels the request', () async {
      adapter.routes['get_live_streams'] = FakeReply.fixture(
        'live_streams.json',
        chunkSize: 600,
        chunkDelay: const Duration(seconds: 10),
      );
      final sw = Stopwatch()..start();
      final first = await client.getLiveStreams().first;
      expect(first['stream_id'], 101);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      await pumpEventQueue();
      expect(adapter.cancelledCount, 1);
    });
  });

  group('details and short EPG', () {
    test('get_vod_info', () async {
      adapter.routes['get_vod_info'] = FakeReply.fixture('vod_info.json');
      final info = await client.getVodInfo('1001');
      expect((info['movie_data']! as Map)['container_extension'], 'mkv');
      expect(adapter.calls, ['get_vod_info?vod_id=1001']);
    });

    test('get_vod_info with [] is empty', () async {
      adapter.routes['get_vod_info'] = FakeReply.json([]);
      expect(await client.getVodInfo('1'), isEmpty);
    });

    test('get_series_info', () async {
      adapter.routes['get_series_info'] = FakeReply.fixture(
        'series_info_map.json',
      );
      final info = await client.getSeriesInfo('5001');
      expect(info['episodes'], isA<Map<String, Object?>>());
      expect(adapter.calls, ['get_series_info?series_id=5001']);
    });

    test('get_short_epg', () async {
      adapter.routes['get_short_epg'] = FakeReply.fixture('short_epg.json');
      final list = await client.getShortEpg('101', limit: 2);
      expect(list.map((p) => p.title), ['نشرة الأخبار', 'Evening Show']);
      expect(adapter.calls, ['get_short_epg?stream_id=101&limit=2']);
    });

    test('get_short_epg without limit', () async {
      adapter.routes['get_short_epg'] = FakeReply.json({'epg_listings': []});
      expect(await client.getShortEpg('5'), isEmpty);
      expect(adapter.calls, ['get_short_epg?stream_id=5']);
    });
  });

  group('invalid server address', () {
    late XtreamClient bad;
    setUp(() {
      bad = XtreamClient(
        XtreamUrls('host:8O80', _user, _pass),
        fakeDio(adapter),
        clock: now,
      );
    });

    Future<void> expectParseFailure(Future<Object?> f) async {
      final e = await failureOf(f);
      expect(e, isA<ParseFailure>());
      expect(e.message, startsWith('Invalid server address'));
      expectNoSecrets(e.toString());
    }

    test('every call fails with a redacted ParseFailure, no request', () async {
      await expectParseFailure(bad.authenticate());
      await expectParseFailure(bad.getLiveCategories());
      await expectParseFailure(bad.getVodInfo('1'));
      await expectParseFailure(bad.getSeriesInfo('1'));
      await expectParseFailure(bad.getShortEpg('1', limit: 2));
      await expectParseFailure(bad.getLiveStreams().toList());
      await expectParseFailure(
        bad
            .getSeries(
              categoryId: '7',
              idleTimeout: const Duration(milliseconds: 50),
            )
            .toList(),
      );
      expect(adapter.requests, isEmpty);
    });

    test('close still applies afterwards', () async {
      await expectParseFailure(bad.authenticate());
      await expectParseFailure(bad.getVodStreams().toList());
      bad.close();
      expect(await failureOf(bad.authenticate()), isA<CancelledFailure>());
    });
  });

  group('out-of-range timestamps', () {
    test('a huge exp_date reads as never expiring', () async {
      adapter.routes[''] = FakeReply.json({
        'user_info': {'auth': 1, 'exp_date': '9999999999999999'},
      });
      final info = await client.authenticate();
      expect(info.status, AccountStatus.active);
      expect(info.expiresAt, isNull);
    });

    test('short EPG entries with huge timestamps are skipped', () async {
      adapter.routes['get_short_epg'] = FakeReply.json({
        'epg_listings': [
          {
            'title': 'VGVzdA==',
            'start_timestamp': '9999999999999999',
            'stop_timestamp': '99999999999999999',
          },
          {
            'title': 'RXZlbmluZyBTaG93',
            'start_timestamp': '1760443200',
            'stop_timestamp': '1760446800',
          },
        ],
      });
      final list = await client.getShortEpg('1');
      expect(list.map((p) => p.title), ['Evening Show']);
    });
  });

  group('guardParse', () {
    test('returns the result', () {
      expect(guardParse('x', () => 3), 3);
    });

    test('unexpected errors become a ParseFailure', () {
      expect(
        () => guardParse<int>('get_vod_info', () => throw RangeError('9999')),
        throwsA(
          isA<ParseFailure>().having(
            (e) => e.message,
            'message',
            'Unexpected get_vod_info response (RangeError)',
          ),
        ),
      );
      expect(
        () => guardParse<int>('x', () => throw StateError(_pass)),
        throwsA(
          isA<ParseFailure>().having(
            (e) => e.message,
            'message',
            isNot(contains(_pass)),
          ),
        ),
      );
    });

    test('SourceFailures pass through', () {
      expect(
        () => guardParse<int>('login', () => throw const AuthFailure('no')),
        throwsA(isA<AuthFailure>()),
      );
    });
  });

  group('close', () {
    test('cancels in-flight requests and rejects new ones', () async {
      adapter.routes['get_live_streams'] = FakeReply.json(
        [],
        delay: const Duration(seconds: 10),
      );
      adapter.routes[''] = FakeReply.fixture('auth_ok.json');
      final pending = failureOf(client.getLiveStreams().toList());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      client.close();
      expect(await pending, isA<CancelledFailure>());
      expect(await failureOf(client.authenticate()), isA<CancelledFailure>());
      expect(
        await failureOf(client.getVodStreams().toList()),
        isA<CancelledFailure>(),
      );
    });
  });
}
