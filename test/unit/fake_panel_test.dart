@Timeout(Duration(seconds: 30))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import '../support/fake_panel.dart';

void main() {
  group('player_api auth', () {
    late FakePanel panel;
    setUp(() async => panel = await FakePanel.start(mediaDir: null));
    tearDown(() => panel.close());

    test('good login reports an active account', () async {
      final json = await _json(panel.playerApiUrl());
      final user = json['user_info'] as Map<String, Object?>;
      expect(user['auth'], 1);
      expect(user['status'], 'Active');
      expect(user['max_connections'], '1');
      expect(user['allowed_output_formats'], containsAll(['ts', 'm3u8']));
      final exp = int.parse(user['exp_date']! as String);
      expect(exp * 1000, greaterThan(DateTime.now().millisecondsSinceEpoch));
      final server = json['server_info'] as Map<String, Object?>;
      expect(server['url'], '127.0.0.1');
      expect(server['port'], '${panel.port}');
      expect(server['timestamp_now'], isA<int>());
      expect(panel.address, InternetAddress.loopbackIPv4);
    });

    test('server_info url and port both follow the Host header', () async {
      Future<Map<String, Object?>> serverInfo(String host) async =>
          ((await _get(panel.playerApiUrl(), headers: {'host': host})).json!
                  as Map<String, Object?>)['server_info']
              as Map<String, Object?>;

      var server = await serverInfo('10.0.2.2:5555');
      expect(server['url'], '10.0.2.2');
      expect(server['port'], '5555');
      server = await serverInfo('panel.example');
      expect(server['url'], 'panel.example');
      expect(server['port'], '80');
    });

    test('expired, banned and disabled accounts', () async {
      panel.auth = FakeAuthMode.expired;
      var user =
          (await _json(panel.playerApiUrl()))['user_info']
              as Map<String, Object?>;
      expect(user['auth'], 1);
      expect(user['status'], 'Expired');
      final exp = int.parse(user['exp_date']! as String);
      expect(exp * 1000, lessThan(DateTime.now().millisecondsSinceEpoch));

      panel.auth = FakeAuthMode.banned;
      user =
          (await _json(panel.playerApiUrl()))['user_info']
              as Map<String, Object?>;
      expect(user['status'], 'Banned');
      expect(user['exp_date'], isNull);

      panel.auth = FakeAuthMode.disabled;
      user =
          (await _json(panel.playerApiUrl()))['user_info']
              as Map<String, Object?>;
      expect(user['status'], 'Disabled');
    });

    test('auth 0 and empty array still answer HTTP 200', () async {
      panel.auth = FakeAuthMode.auth0WithHttp200;
      var res = await _get(panel.playerApiUrl());
      expect(res.status, 200);
      expect(res.json, {
        'user_info': {'auth': 0},
      });

      panel.auth = FakeAuthMode.emptyArray;
      res = await _get(panel.playerApiUrl(action: 'get_live_streams'));
      expect(res.status, 200);
      expect(res.json, isEmpty);
      expect(res.json, isA<List<Object?>>());
    });

    test('wrong password gets auth 0 for login and actions', () async {
      final bad = panel.playerApiUrl().replaceFirst(
        'password=pass',
        'password=nope',
      );
      expect((await _get(bad)).json, {
        'user_info': {'auth': 0},
      });
      final badAction = panel
          .playerApiUrl(action: 'get_live_streams')
          .replaceFirst('username=user', 'username=other');
      expect((await _get(badAction)).json, {
        'user_info': {'auth': 0},
      });
    });

    test('blocked accounts get the login body instead of catalogs', () async {
      panel.auth = FakeAuthMode.expired;
      final json = await _json(panel.playerApiUrl(action: 'get_live_streams'));
      expect((json['user_info'] as Map<String, Object?>)['status'], 'Expired');
    });

    test('auth mode and limits switch at runtime via /__config', () async {
      final res = await _get(
        '${panel.baseUrl}/__config?auth=banned&maxConnections=3'
        '&fullListDelayMs=5&liveBytesPerSecond=5000',
      );
      expect(res.status, 200);
      expect(panel.auth, FakeAuthMode.banned);
      expect(panel.maxConnections, 3);
      expect(panel.fullListDelay, const Duration(milliseconds: 5));
      expect(panel.liveBytesPerSecond, 5000);
      final user =
          (await _json(panel.playerApiUrl()))['user_info']
              as Map<String, Object?>;
      expect(user['status'], 'Banned');
      expect(user['max_connections'], '3');

      expect((await _get('${panel.baseUrl}/__config?auth=nope')).status, 400);
    });
  });

  group('catalog quirks', () {
    late FakePanel panel;
    setUpAll(() async => panel = await FakePanel.start(mediaDir: null));
    tearDownAll(() => panel.close());

    test('live categories mix string and int ids and Arabic names', () async {
      final cats = await _list(
        panel.playerApiUrl(action: 'get_live_categories'),
      );
      expect(cats, hasLength(panel.catalog.liveCategories.length));
      final ids = cats.map((c) => c['category_id']).toList();
      expect(ids.whereType<String>(), isNotEmpty);
      expect(ids.whereType<int>(), [3]);
      expect(cats.first['category_name'], 'أخبار');
      expect(cats.first['parent_id'], 0);
    });

    test('live streams use quirky field types', () async {
      final streams = await _list(
        panel.playerApiUrl(action: 'get_live_streams'),
      );
      expect(streams, hasLength(50));
      expect(streams[0]['name'], 'قناة اختبار 1');
      expect(streams[1]['name'], 'Test News 2');
      expect(streams[3]['name'], 'Test News 4 HD');
      final ids = streams.map((s) => s['stream_id']).toList();
      expect(ids.whereType<int>(), isNotEmpty);
      expect(ids.whereType<String>(), isNotEmpty);
      expect(ids.map((id) => int.parse('$id')), [
        for (var i = 1; i <= 50; i++) 1000 + i,
      ]);
      expect(streams.map((s) => s['num']).whereType<String>(), isNotEmpty);
      expect(streams.every((s) => s['category_ids'] is List<Object?>), isTrue);
      expect(streams[9]['epg_channel_id'], '');
      expect(streams[19]['epg_channel_id'], isNull);
      expect(streams[0]['epg_channel_id'], 'test1.example');
      expect(streams[4]['stream_icon'], '');
      expect(streams[0]['stream_icon'], '${panel.baseUrl}/logo/live1001.png');
      expect(streams[8]['tv_archive'], '1');
    });

    test('per-category lists include multi-category channels', () async {
      final news = await _list(
        panel.playerApiUrl(
          action: 'get_live_streams',
          params: {'category_id': '1'},
        ),
      );
      expect(news, hasLength(panel.catalog.liveInCategory('1').length));
      expect(
        news.every((s) => (s['category_ids']! as List<Object?>).contains(1)),
        isTrue,
      );
      // Channel 7 is primarily in category 3 but also listed under 1.
      final seven = news.firstWhere((s) => s['name'] == 'قناة اختبار 7');
      expect(seven['category_id'], '3');
      expect(seven['category_ids'], [3, 1]);

      final empty = await _list(
        panel.playerApiUrl(
          action: 'get_live_streams',
          params: {'category_id': '5'},
        ),
      );
      expect(empty, isEmpty);
    });

    test('VOD lists and details', () async {
      final cats = await _list(
        panel.playerApiUrl(action: 'get_vod_categories'),
      );
      expect(cats.map((c) => c['category_id']), ['10', '11', '12']);
      final vod = await _list(panel.playerApiUrl(action: 'get_vod_streams'));
      expect(vod, hasLength(30));
      expect(vod.map((v) => v['container_extension']).toSet(), {'mkv', 'mp4'});
      expect(vod[3]['rating'], '');
      expect(vod[0]['rating'], 6.5);
      expect(vod[1]['rating'], '7.5');
      final kids = await _list(
        panel.playerApiUrl(
          action: 'get_vod_streams',
          params: {'category_id': '12'},
        ),
      );
      expect(
        kids.map((v) => v['name']),
        everyElement(startsWith('Test Movie')),
      );

      final info = await _json(
        panel.playerApiUrl(action: 'get_vod_info', params: {'vod_id': '2001'}),
      );
      expect((info['info'] as Map<String, Object?>)['duration_secs'], '5400');
      expect((info['movie_data'] as Map<String, Object?>)['stream_id'], 2001);
      expect(
        (info['movie_data'] as Map<String, Object?>)['container_extension'],
        'mkv',
      );
      final missing = await _get(
        panel.playerApiUrl(action: 'get_vod_info', params: {'vod_id': '9'}),
      );
      expect(missing.json, isEmpty);
    });

    test(
      'series episodes come as a map, a flat list or with info []',
      () async {
        final series = await _list(panel.playerApiUrl(action: 'get_series'));
        expect(series, hasLength(10));
        expect(series[0]['name'], 'مسلسل اختبار 1');
        expect(series[1]['series_id'], '3002');

        Future<Map<String, Object?>> info(int id) => _json(
          panel.playerApiUrl(
            action: 'get_series_info',
            params: {'series_id': '$id'},
          ),
        );

        final odd = await info(3001);
        final byseason = odd['episodes']! as Map<String, Object?>;
        expect(byseason.keys, ['1', '2']);
        expect(byseason['1'], hasLength(3));
        expect(odd['seasons'], hasLength(2));
        expect(
          ((odd['seasons']! as List<Object?>).first
              as Map<String, Object?>)['name'],
          'الموسم 1',
        );

        final even = await info(3002);
        final flat = (even['episodes']! as List<Object?>)
            .cast<Map<String, Object?>>();
        expect(flat, hasLength(9));
        expect(flat.map((e) => e['season']).toSet(), {1, '2', 3});
        expect(flat.first['info'], isEmpty);
        expect(flat.first['id'], '300211');
        expect(
          flat.map((e) => e['episode_num']).whereType<String>(),
          isNotEmpty,
        );

        final last = await info(3010);
        expect(last['info'], isA<List<Object?>>());
        expect(last['info'], isEmpty);
        expect(last['seasons'], isEmpty);
        expect(last['episodes'], isA<List<Object?>>()); // even index
        expect(last['episodes'], isNotEmpty);
      },
    );

    test('get_short_epg sends base64 titles incl. Arabic', () async {
      final json = await _json(
        panel.playerApiUrl(
          action: 'get_short_epg',
          params: {'stream_id': '1001', 'limit': '2'},
        ),
      );
      final listings = (json['epg_listings']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(listings, hasLength(2));
      final title = utf8.decode(base64.decode(listings[0]['title']! as String));
      expect(title, startsWith('برنامج '));
      final start = int.parse(listings[0]['start_timestamp']! as String);
      final stop = int.parse(listings[0]['stop_timestamp']! as String);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(start, lessThanOrEqualTo(now));
      expect(stop, greaterThan(now));
      expect(listings[1]['start_timestamp'], '$stop');
      expect(listings[0]['now_playing'], 1);

      final english = await _json(
        panel.playerApiUrl(
          action: 'get_short_epg',
          params: {'stream_id': '1002'},
        ),
      );
      final first =
          (english['epg_listings']! as List<Object?>).first
              as Map<String, Object?>;
      expect(
        utf8.decode(base64.decode(first['description']! as String)),
        contains('News & weather'),
      );
      expect(english['epg_listings'], hasLength(4));

      final noEpg = await _json(
        panel.playerApiUrl(
          action: 'get_short_epg',
          params: {'stream_id': '1010'},
        ),
      );
      expect(noEpg['epg_listings'], isEmpty);
    });

    test('unknown actions return []', () async {
      expect(
        (await _get(panel.playerApiUrl(action: 'get_nothing'))).json,
        isEmpty,
      );
    });
  });

  test('full-list delay leaves per-category calls fast', () async {
    final panel = await FakePanel.start(
      mediaDir: null,
      fullListDelay: const Duration(milliseconds: 400),
    );
    addTearDown(panel.close);
    final sw = Stopwatch()..start();
    await _list(panel.playerApiUrl(action: 'get_live_streams'));
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(400));
    sw.reset();
    await _list(
      panel.playerApiUrl(
        action: 'get_live_streams',
        params: {'category_id': '2'},
      ),
    );
    await _list(
      panel.playerApiUrl(action: 'get_series', params: {'category_id': '20'}),
    );
    expect(sw.elapsedMilliseconds, lessThan(400));
  });

  test('custom catalog sizes', () async {
    final panel = await FakePanel.start(
      mediaDir: null,
      liveCount: 3,
      vodCount: 1,
      seriesCount: 1,
    );
    addTearDown(panel.close);
    expect(
      await _list(panel.playerApiUrl(action: 'get_live_streams')),
      hasLength(3),
    );
    expect(
      await _list(panel.playerApiUrl(action: 'get_vod_streams')),
      hasLength(1),
    );
    final info = await _json(
      panel.playerApiUrl(
        action: 'get_series_info',
        params: {'series_id': '3001'},
      ),
    );
    expect(info['info'], isEmpty);
    expect(info['episodes'], isA<Map<String, Object?>>());
  });

  group('get.php', () {
    late FakePanel panel;
    setUpAll(
      () async => panel = await FakePanel.start(
        mediaDir: null,
        liveCount: 3,
        vodCount: 2,
        seriesCount: 2,
      ),
    );
    tearDownAll(() => panel.close());

    test('m3u_plus lists live, movies and episodes on this server', () async {
      final res = await _get(panel.m3uUrl());
      expect(res.status, 200);
      final lines = const LineSplitter().convert(res.text);
      final base = panel.baseUrl;
      expect(
        lines.first,
        '#EXTM3U url-tvg="$base/xmltv.php?username=user&password=pass" '
        'x-tvg-url="$base/xmltv.php?username=user&password=pass"',
      );
      // 3 live + 2 movies + (6 + 9) episodes.
      expect(lines.where((l) => l.startsWith('#EXTINF')), hasLength(20));
      expect(
        lines[1],
        '#EXTINF:-1 tvg-id="test1.example" tvg-name="قناة اختبار 1" '
        'tvg-logo="$base/logo/live1001.png" group-title="أخبار",قناة اختبار 1',
      );
      expect(lines[2], '$base/live/user/pass/1001.ts');
      expect(lines, contains('$base/movie/user/pass/2001.mkv'));
      expect(lines, contains('$base/series/user/pass/300111.mp4'));
      expect(lines, contains('$base/series/user/pass/300212.mkv'));
      expect(
        lines.where((l) => l.startsWith('#EXTINF') && l.endsWith('S01 E01')),
        hasLength(2),
      );
    });

    test('output=m3u8 and plain m3u', () async {
      final hls = await _get(panel.m3uUrl(output: 'm3u8'));
      expect(hls.text, contains('/live/user/pass/1001.m3u8\n'));
      expect(hls.text, isNot(contains('/live/user/pass/1001.ts')));
      final plain = await _get(panel.m3uUrl(type: 'm3u'));
      final lines = const LineSplitter().convert(plain.text);
      expect(lines.first, '#EXTM3U');
      expect(lines[1], '#EXTINF:-1,قناة اختبار 1');
    });

    test('URLs follow the Host header (emulator access)', () async {
      final res = await _get(
        panel.m3uUrl(),
        headers: {'host': '10.0.2.2:5555'},
      );
      expect(res.text, contains('url-tvg="http://10.0.2.2:5555/xmltv.php?'));
      expect(res.text, contains('http://10.0.2.2:5555/live/user/pass/1001.ts'));
    });

    test('rejects wrong credentials and blocked accounts', () async {
      final bad = panel.m3uUrl().replaceFirst('password=pass', 'password=x');
      expect((await _get(bad)).status, 401);
      panel.auth = FakeAuthMode.expired;
      addTearDown(() => panel.auth = FakeAuthMode.good);
      expect((await _get(panel.m3uUrl())).status, 403);
    });

    test('names the download after the user', () async {
      final res = await _get(panel.m3uUrl());
      expect(
        res.headers.value('content-disposition'),
        'attachment; filename="tv_channels_user_plus.m3u"',
      );
    });
  });

  test('non-ASCII usernames work for get.php and streams', () async {
    const user = 'مستخدم';
    final encoded = Uri.encodeComponent(user);
    final panel = await FakePanel.start(
      mediaDir: null,
      username: user,
      liveCount: 2,
      liveBytesPerSecond: 18800,
    );
    addTearDown(panel.close);
    final res = await _get(panel.m3uUrl());
    expect(res.status, 200);
    expect(
      res.headers.value('content-disposition'),
      'attachment; filename="tv_channels_${encoded}_plus.m3u"',
    );
    expect(res.text, contains('/live/$encoded/pass/1001.ts\n'));
    final user0 =
        (await _json(panel.playerApiUrl()))['user_info']
            as Map<String, Object?>;
    expect(user0['username'], user);
    final s = await _Stream.open(panel.liveUrl(1001));
    addTearDown(s.close);
    expect(s.status, 200);
    await s.waitFor(188);
  });

  test('large catalogs stream M3U and XMLTV without stalling', () async {
    final panel = await FakePanel.start(
      mediaDir: null,
      liveCount: 3000,
      maxConnections: 0,
      liveBytesPerSecond: 18800,
    );
    addTearDown(panel.close);
    // Timers and other sockets keep running while the guide is generated.
    var last = DateTime.now();
    var maxGap = Duration.zero;
    final ticker = Timer.periodic(const Duration(milliseconds: 5), (_) {
      final now = DateTime.now();
      final gap = now.difference(last);
      if (gap > maxGap) maxGap = gap;
      last = now;
    });
    addTearDown(ticker.cancel);
    final live = await _Stream.open(panel.liveUrl(1001));
    addTearDown(live.close);
    await live.waitFor(188);

    final res = await _get(panel.xmltvUrl);
    ticker.cancel();
    expect(maxGap, lessThan(const Duration(milliseconds: 250)));
    expect(res.headers.contentType?.mimeType, 'application/gzip');
    final xml = utf8.decode(gzip.decode(res.body));
    expect('<channel '.allMatches(xml), hasLength(3000));
    // Odd channels: 24 one-hour slots; even channels: 48 half-hour slots
    // (one more of each when the clock is not on a slot boundary).
    expect(
      '<programme '.allMatches(xml).length,
      inInclusiveRange(1500 * 72, 1500 * 74),
    );
    expect(xml, endsWith('</tv>\n'));
    expect(live.done.isCompleted, isFalse);

    final m3u = await _get(panel.m3uUrl());
    final lines = const LineSplitter().convert(m3u.text);
    expect(
      lines.where((l) => l.startsWith('#EXTINF')),
      hasLength(3000 + 30 + 60),
    );
    expect(lines.last, startsWith('${panel.baseUrl}/series/'));
  });

  test('an aborted guide download leaves the panel serving', () async {
    final panel = await FakePanel.start(mediaDir: null, liveCount: 3000);
    addTearDown(panel.close);
    final client = HttpClient();
    final res = await (await client.getUrl(Uri.parse(panel.xmltvUrl))).close();
    final first = Completer<void>();
    final sub = res.listen((_) {
      if (!first.isCompleted) first.complete();
    }, onError: (Object _) {});
    await first.future;
    await sub.cancel();
    client.close(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect((await _get(panel.playerApiUrl())).status, 200);
    expect((await _get(panel.plainEpgUrl)).status, 200);
  });

  test('epgSpan limits how far ahead the guide reaches', () async {
    final now = DateTime.utc(2026, 1, 1, 12);
    final panel = await FakePanel.start(
      mediaDir: null,
      liveCount: 4,
      epgSpan: const Duration(hours: 2),
      now: () => now,
    );
    addTearDown(panel.close);
    final xml = XmlDocument.parse((await _get(panel.plainEpgUrl)).text);
    // 2 one-hour slots on odd channels, 4 half-hour slots on even ones.
    expect(xml.findAllElements('programme'), hasLength(2 * 2 + 2 * 4));
    expect(panel.programmes(panel.catalog.live.first), hasLength(2));
    await _get('${panel.baseUrl}/__config?epgHours=1');
    expect(panel.epgSpan, const Duration(hours: 1));
  });

  group('XMLTV', () {
    late FakePanel panel;
    final now = DateTime.utc(2026, 1, 1, 12);
    setUpAll(
      () async => panel = await FakePanel.start(
        mediaDir: null,
        liveCount: 6,
        now: () => now,
      ),
    );
    tearDownAll(() => panel.close());

    test('xmltv.php is gzip with application/gzip', () async {
      final res = await _get(panel.xmltvUrl);
      expect(res.status, 200);
      expect(res.headers.contentType?.mimeType, 'application/gzip');
      expect(res.headers.value('content-encoding'), isNull);
      expect(res.body.sublist(0, 2), [0x1f, 0x8b]);
      final doc = XmlDocument.parse(utf8.decode(gzip.decode(res.body)));
      final channels = doc.findAllElements('channel').toList();
      expect(channels, hasLength(6));
      expect(channels.first.getAttribute('id'), 'test1.example');
      expect(
        channels.first.getElement('display-name')?.innerText,
        'قناة اختبار 1',
      );
      final programmes = doc.findAllElements('programme').toList();
      // Odd channels: 24 one-hour slots; even channels: 48 half-hour slots.
      expect(programmes, hasLength(3 * 24 + 3 * 48));
      final first = programmes.first;
      expect(first.getAttribute('start'), '20260101120000 +0000');
      expect(first.getAttribute('stop'), '20260101130000 +0000');
      expect(first.getElement('title')?.innerText, 'برنامج 12:00');
      expect(first.getElement('title')?.getAttribute('lang'), 'ar');
      final third = programmes.firstWhere(
        (p) => p.getAttribute('channel') == 'test3.example',
      );
      expect(third.getAttribute('start'), '20260101150000 +0300');
      final english = programmes.firstWhere(
        (p) => p.getAttribute('channel') == 'test2.example',
      );
      expect(
        english.getElement('desc')?.innerText,
        'News & weather <live> at 12:00 on Test News 2',
      );
      expect(
        panel.programmes(panel.catalog.live[1]).last.stop,
        now.add(const Duration(hours: 24)),
      );
    });

    test('epg_plain.xml is uncompressed XML', () async {
      final res = await _get(panel.plainEpgUrl);
      expect(res.status, 200);
      expect(res.headers.contentType?.mimeType, 'application/xml');
      expect(res.text, startsWith('<?xml'));
      expect(
        XmlDocument.parse(res.text).findAllElements('programme'),
        isNotEmpty,
      );
    });

    test('channels without epg ids keep a name-only guide entry', () async {
      final big = await FakePanel.start(mediaDir: null, liveCount: 10);
      addTearDown(big.close);
      final xml = utf8.decode(gzip.decode((await _get(big.xmltvUrl)).body));
      expect(xml, contains('<channel id="noid10.example">'));
      expect(xml, contains('<display-name>Test News 10</display-name>'));
    });

    test('xmltv.php checks credentials', () async {
      final bad = panel.xmltvUrl.replaceFirst('username=user', 'username=x');
      expect((await _get(bad)).status, 401);
    });
  });

  group('live TS', () {
    late FakePanel panel;
    setUp(
      () async => panel = await FakePanel.start(
        mediaDir: null,
        liveBytesPerSecond: 18800,
      ),
    );
    tearDown(() => panel.close());

    test('synthetic stream is aligned null packets, throttled', () async {
      final sw = Stopwatch()..start();
      final s = await _Stream.open(panel.liveUrl(1001));
      addTearDown(s.close);
      expect(s.status, 200);
      expect(s.response.headers.contentType?.mimeType, 'video/mp2t');
      expect(s.response.headers.contentLength, -1);
      await s.waitFor(188 * 100);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final head = s.head;
      for (var o = 0; o + 188 <= head.length; o += 188) {
        expect(head[o], 0x47);
        expect(((head[o + 1] & 0x1F) << 8) | head[o + 2], 0x1FFF);
      }
      final allowed = 18800 + 18800 * sw.elapsedMicroseconds / 1e6 + 10000;
      expect(s.received, lessThan(allowed));
      expect(panel.liveUsesMediaFile(1001), isFalse);
    });

    test('wrong credentials, unknown ids and blocked accounts', () async {
      final bad = panel.liveUrl(1001).replaceFirst('/pass/', '/nope/');
      expect((await _get(bad)).status, 401);
      expect((await _get(panel.liveUrl(999))).status, 404);
      expect((await _get(panel.liveUrl(1001, ext: 'mp4'))).status, 404);
      panel.auth = FakeAuthMode.banned;
      expect((await _get(panel.liveUrl(1001))).status, 403);
    });

    test('HEAD does not open a connection', () async {
      final res = await _get(panel.liveUrl(1001), method: 'HEAD');
      expect(res.status, 200);
      expect(panel.stats.acceptedStreams, 0);
    });

    test(
      'maxConnections: a second channel gets 403 until the first closes',
      () async {
        final a = await _Stream.open(panel.liveUrl(1001));
        addTearDown(a.close);
        expect(a.status, 200);
        await a.waitFor(188);
        expect(panel.stats.activeConnections, 1);

        expect((await _get(panel.liveUrl(1002))).status, 403);
        expect((await _get(panel.liveUrl(1002, ext: 'm3u8'))).status, 403);

        // A second request for the same stream counts as the same connection.
        final again = await _Stream.open(panel.liveUrl(1001));
        expect(again.status, 200);
        await again.waitFor(188);
        var stats = panel.stats;
        expect(stats.activeConnections, 1);
        expect(stats.openStreams, 2);
        await again.close();

        await a.close();
        await panel.waitForStats((s) => s.activeConnections == 0);
        final b = await _Stream.open(panel.liveUrl(1002));
        addTearDown(b.close);
        expect(b.status, 200);
        await b.waitFor(188);

        stats = FakePanelStats.fromJson(
          await _json('${panel.baseUrl}/__stats'),
        );
        expect(stats.activeConnections, 1);
        expect(stats.maxConcurrentSeen, 1);
        // The refused requests show the client tried to hold two at once.
        expect(stats.maxConcurrentAttempted, 2);
        expect(stats.maxOpenStreamsSeen, 2);
        expect(stats.rejectedStreams, 2);
        expect(stats.acceptedStreams, 3);
      },
    );

    test('sequential zaps keep maxConcurrentAttempted at 1', () async {
      for (final id in [1001, 1002, 1003]) {
        final s = await _Stream.open(panel.liveUrl(id));
        expect(s.status, 200);
        await s.waitFor(188);
        await s.close();
        await panel.waitForStats((st) => st.activeConnections == 0);
      }
      final stats = panel.stats;
      expect(stats.maxConcurrentAttempted, 1);
      expect(stats.rejectedStreams, 0);
    });

    test('maxConnections 2 admits two channels; 0 is unlimited', () async {
      panel.maxConnections = 2;
      final a = await _Stream.open(panel.liveUrl(1001));
      final b = await _Stream.open(panel.liveUrl(1002));
      addTearDown(a.close);
      addTearDown(b.close);
      expect([a.status, b.status], [200, 200]);
      await b.waitFor(188);
      expect((await _get(panel.liveUrl(1003))).status, 403);
      panel.maxConnections = 0;
      final c = await _Stream.open(panel.liveUrl(1003));
      addTearDown(c.close);
      expect(c.status, 200);
      await c.waitFor(188);
      expect(panel.stats.maxConcurrentSeen, 3);
    });
  });

  group('HLS', () {
    late FakePanel panel;
    var now = DateTime.utc(2026, 1, 1);
    const session = Duration(seconds: 1);
    setUp(() async {
      now = DateTime.utc(2026, 1, 1);
      panel = await FakePanel.start(
        mediaDir: null,
        liveBytesPerSecond: 18800,
        hlsWindowSize: 3,
        hlsSessionTimeout: session,
        now: () => now,
      );
    });
    tearDown(() => panel.close());

    test('an HLS viewer holds its connection between requests', () async {
      final base = panel.baseUrl;
      expect((await _get(panel.liveUrl(1001, ext: 'm3u8'))).status, 200);
      var stats = panel.stats;
      expect(stats.activeConnections, 1);
      expect(stats.openStreams, 0);
      expect(
        (await _json(panel.playerApiUrl()))['user_info'],
        containsPair('active_cons', '1'),
      );

      // Idle between requests, as a player is: still one connection.
      await Future<void>.delayed(session * 0.6);
      expect(panel.stats.activeConnections, 1);
      expect((await _get(panel.liveUrl(1002))).status, 403);
      expect((await _get('$base/hls/1001/0.ts')).status, 200);
      // The segment extended the session past the playlist's expiry.
      await Future<void>.delayed(session * 0.6);
      expect(panel.stats.activeConnections, 1);

      // The player stopped: the panel releases it after the timeout.
      await panel.waitForStats((s) => s.activeConnections == 0);
      final s = await _Stream.open(panel.liveUrl(1002));
      addTearDown(s.close);
      expect(s.status, 200);
      await s.waitFor(188);
      stats = panel.stats;
      expect(stats.maxConcurrentSeen, 1);
      expect(stats.maxConcurrentAttempted, 2);
      expect(stats.rejectedStreams, 1);
    });

    test('chaos drop, panel.close and a zero timeout end sessions', () async {
      expect((await _get(panel.liveUrl(1001, ext: 'm3u8'))).status, 200);
      expect(panel.stats.activeConnections, 1);
      panel.setChaos(FakeChaosMode.drop);
      expect(panel.stats.activeConnections, 0);
      expect((await _get(panel.liveUrl(1002, ext: 'm3u8'))).status, 200);

      panel.hlsSessionTimeout = Duration.zero;
      panel.setChaos(FakeChaosMode.drop);
      expect((await _get(panel.liveUrl(1001, ext: 'm3u8'))).status, 200);
      expect((await _get('${panel.baseUrl}/hls/1001/0.ts')).status, 200);
      expect(panel.stats.activeConnections, 0);

      panel.hlsSessionTimeout = const Duration(minutes: 1);
      expect((await _get(panel.liveUrl(1001, ext: 'm3u8'))).status, 200);
      expect(panel.stats.activeConnections, 1);
      await panel.close();
      expect(panel.stats.activeConnections, 0);
    });

    test('blocked accounts get 403 for segments too', () async {
      final seg = '${panel.baseUrl}/hls/1001/0.ts';
      for (final mode in [
        FakeAuthMode.banned,
        FakeAuthMode.expired,
        FakeAuthMode.disabled,
      ]) {
        panel.auth = mode;
        expect((await _get(seg)).status, 403, reason: mode.name);
        expect((await _get(seg, method: 'HEAD')).status, 403);
        expect((await _get(panel.liveUrl(1001, ext: 'm3u8'))).status, 403);
      }
      panel.auth = FakeAuthMode.good;
      expect((await _get(seg)).status, 200);
    });

    test('playlist slides with the clock', () async {
      final url = panel.liveUrl(1001, ext: 'm3u8');
      var res = await _get(url);
      expect(res.status, 200);
      expect(
        res.headers.contentType?.mimeType,
        'application/vnd.apple.mpegurl',
      );
      expect(
        res.text,
        '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:2\n'
        '#EXT-X-MEDIA-SEQUENCE:0\n'
        '#EXTINF:2.000,\n/hls/1001/0.ts\n'
        '#EXTINF:2.000,\n/hls/1001/1.ts\n'
        '#EXTINF:2.000,\n/hls/1001/2.ts\n',
      );
      expect(res.text, isNot(contains('#EXT-X-ENDLIST')));

      now = now.add(const Duration(seconds: 5));
      res = await _get(url);
      expect(res.text, contains('#EXT-X-MEDIA-SEQUENCE:2\n'));
      final uris = const LineSplitter()
          .convert(res.text)
          .where((l) => !l.startsWith('#'))
          .toList();
      expect(uris, ['/hls/1001/2.ts', '/hls/1001/3.ts', '/hls/1001/4.ts']);

      final seg = await _get(Uri.parse(url).resolve(uris[1]).toString());
      expect(seg.status, 200);
      expect(seg.headers.contentType?.mimeType, 'video/mp2t');
      expect(seg.body.length, 200 * 188); // 2 s at 18800 B/s.
      expect(seg.body[0], 0x47);
      expect(seg.body[188], 0x47);
    });

    test('segments outside the window are 404', () async {
      now = now.add(const Duration(seconds: 20)); // first sequence 10
      final base = panel.baseUrl;
      expect((await _get('$base/hls/1001/7.ts')).status, 200);
      expect((await _get('$base/hls/1001/6.ts')).status, 404);
      expect((await _get('$base/hls/1001/12.ts')).status, 200);
      expect((await _get('$base/hls/1001/13.ts')).status, 404);
      expect((await _get('$base/hls/9999/10.ts')).status, 404);
    });

    test('playlist and segment requests count as one connection', () async {
      final live = await _Stream.open(panel.liveUrl(1002));
      addTearDown(live.close);
      await live.waitFor(188);
      expect((await _get(panel.liveUrl(1001, ext: 'm3u8'))).status, 403);
      expect((await _get('${panel.baseUrl}/hls/1001/0.ts')).status, 403);
      await live.close();
      await panel.waitForStats((s) => s.activeConnections == 0);
      expect((await _get(panel.liveUrl(1001, ext: 'm3u8'))).status, 200);
      expect((await _get('${panel.baseUrl}/hls/1001/0.ts')).status, 200);
      await panel.waitForStats((s) => s.activeConnections == 0);
    });
  });

  group('VOD ranges', () {
    late FakePanel panel;
    const size = 10000;
    setUpAll(
      () async => panel = await FakePanel.start(
        mediaDir: null,
        syntheticVodBytes: size,
      ),
    );
    tearDownAll(() => panel.close());

    void expectPattern(Uint8List body, int start) {
      for (var i = 0; i < body.length; i++) {
        expect(body[i], FakePanel.syntheticVodByte(start + i), reason: '@$i');
      }
    }

    test('full body advertises byte ranges', () async {
      final res = await _get(panel.movieUrl(2001));
      expect(res.status, 200);
      expect(res.headers.value('accept-ranges'), 'bytes');
      expect(res.headers.contentType?.mimeType, 'video/x-matroska');
      expect(res.headers.contentLength, size);
      expect(res.body, hasLength(size));
      expectPattern(res.body, 0);
      expect(panel.vodUsesMediaFile, isFalse);
    });

    test('206 for explicit, open-ended and suffix ranges', () async {
      Future<_Res> range(String spec) =>
          _get(panel.movieUrl(2001), headers: {'range': 'bytes=$spec'});

      var res = await range('0-99');
      expect(res.status, 206);
      expect(res.headers.value('content-range'), 'bytes 0-99/$size');
      expect(res.body, hasLength(100));
      expectPattern(res.body, 0);

      res = await range('9990-');
      expect(res.status, 206);
      expect(res.headers.value('content-range'), 'bytes 9990-9999/$size');
      expectPattern(res.body, 9990);

      res = await range('-5');
      expect(res.headers.value('content-range'), 'bytes 9995-9999/$size');
      expect(res.body, hasLength(5));

      res = await range('9000-20000');
      expect(res.headers.value('content-range'), 'bytes 9000-9999/$size');
      expect(res.body, hasLength(1000));
      expectPattern(res.body, 9000);
    });

    test('416 when unsatisfiable; malformed ranges are ignored', () async {
      var res = await _get(
        panel.movieUrl(2001),
        headers: {'range': 'bytes=$size-'},
      );
      expect(res.status, 416);
      expect(res.headers.value('content-range'), 'bytes */$size');

      res = await _get(panel.movieUrl(2001), headers: {'range': 'bytes=50-10'});
      expect(res.status, 200);
      expect(res.body, hasLength(size));

      res = await _get(panel.movieUrl(2001), headers: {'range': 'items=1-2'});
      expect(res.status, 200);
    });

    test('episodes, HEAD, credentials and unknown ids', () async {
      final ep = panel.catalog.series.first.episodes.first;
      var res = await _get(
        panel.episodeUrl(ep.id),
        headers: {'range': 'bytes=10-19'},
      );
      expect(res.status, 206);
      expect(res.headers.contentType?.mimeType, 'video/mp4');
      expectPattern(res.body, 10);

      res = await _get(panel.movieUrl(2001), method: 'HEAD');
      expect(res.status, 200);
      expect(res.headers.contentLength, size);
      expect(res.body, isEmpty);

      final bad = panel.movieUrl(2001).replaceFirst('/user/', '/intruder/');
      expect((await _get(bad)).status, 401);
      expect((await _get(panel.movieUrl(1999, ext: 'mkv'))).status, 404);
      expect((await _get(panel.episodeUrl(2001, ext: 'mp4'))).status, 404);
      await panel.waitForStats((s) => s.activeConnections == 0);
    });
  });

  group('chaos', () {
    late FakePanel panel;
    setUp(
      () async => panel = await FakePanel.start(
        mediaDir: null,
        liveBytesPerSecond: 37600,
        syntheticVodBytes: 1000,
      ),
    );
    tearDown(() => panel.close());

    test('mode=403 refuses streams for a while, not the API', () async {
      final res = await _get('${panel.baseUrl}/__chaos?mode=403&for=0.3');
      expect(res.json, {'chaos': '403'});
      expect(panel.chaosMode, FakeChaosMode.forbidden);
      expect((await _get(panel.liveUrl(1001))).status, 403);
      expect((await _get(panel.liveUrl(1001, ext: 'm3u8'))).status, 403);
      expect((await _get(panel.movieUrl(2001))).status, 403);
      expect((await _get(panel.playerApiUrl())).status, 200);
      await panel.waitForStats((s) => s.chaos == 'off');
      final s = await _Stream.open(panel.liveUrl(1001));
      addTearDown(s.close);
      expect(s.status, 200);
      expect(panel.stats.rejectedStreams, 3);
    });

    test('mode=drop closes open streams after a delay, once', () async {
      final s = await _Stream.open(panel.liveUrl(1001));
      addTearDown(s.close);
      await s.waitFor(188);
      final sw = Stopwatch()..start();
      await _get('${panel.baseUrl}/__chaos?mode=drop&after=0.2');
      expect(panel.chaosMode, FakeChaosMode.drop);
      await s.done.future.timeout(const Duration(seconds: 3));
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(150));
      final stats = await panel.waitForStats((s) => s.activeConnections == 0);
      expect(stats.chaos, 'off');
      // Reconnecting works straight away.
      final again = await _Stream.open(panel.liveUrl(1001));
      addTearDown(again.close);
      expect(again.status, 200);
      await again.waitFor(188);
    });

    test('mode=stall pauses bytes on open streams, then resumes', () async {
      final s = await _Stream.open(panel.liveUrl(1001));
      addTearDown(s.close);
      await s.waitFor(188);
      panel.setChaos(
        FakeChaosMode.stall,
        duration: const Duration(milliseconds: 700),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final before = s.received;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(s.received, before);
      expect(s.done.isCompleted, isFalse);
      await panel.waitForStats((st) => st.chaos == 'off');
      await s.waitFor(before + 188 * 10);
    });

    test('mode=off cancels a pending fault; bad modes are 400', () async {
      panel.setChaos(FakeChaosMode.forbidden);
      expect((await _get('${panel.baseUrl}/__chaos?mode=off')).status, 200);
      expect(panel.chaosMode, FakeChaosMode.off);
      expect((await _get('${panel.baseUrl}/__chaos?mode=boom')).status, 400);
      expect(FakeChaosMode.parse('403'), FakeChaosMode.forbidden);
      expect(FakeChaosMode.parse('stall'), FakeChaosMode.stall);
    });
  });

  group('stats', () {
    late FakePanel panel;
    setUp(() async => panel = await FakePanel.start(mediaDir: null));
    tearDown(() => panel.close());

    test('captures User-Agent and Referer per path prefix', () async {
      const headers = {
        'user-agent': 'UnitTestUA/1.0',
        'referer': 'http://ref.example/',
      };
      await _get(panel.playerApiUrl(), headers: headers);
      await _get(
        panel.playerApiUrl(action: 'get_live_streams'),
        headers: {'user-agent': 'OtherUA/2'},
      );
      final s = await _Stream.open(
        panel.liveUrl(1001),
        headers: {
          'user-agent': 'PlayerUA/3',
          'referer': 'http://player.example/',
        },
      );
      addTearDown(s.close);
      await s.waitFor(188);

      final stats = FakePanelStats.fromJson(await _json(panel.statsUrl));
      expect(stats.userAgents['/player_api.php'], 'OtherUA/2');
      expect(stats.referers['/player_api.php'], 'http://ref.example/');
      expect(stats.userAgents['/live'], 'PlayerUA/3');
      expect(stats.referers['/live'], 'http://player.example/');
      expect(stats.requestsByPath['/player_api.php'], 2);
      expect(stats.requestsByPath['/live/user/pass/1001.ts'], 1);
      expect(stats.requestsWithPrefix('/live/'), 1);
      expect(stats.requestsByAction, {'login': 1, 'get_live_streams': 1});
      expect(
        stats.requestsByPath.keys.where((k) => k.startsWith('/__')),
        isEmpty,
      );
      expect(stats.toJson(), panel.stats.toJson());
    });

    test('reset keeps open connections counted', () async {
      final s = await _Stream.open(panel.liveUrl(1001));
      addTearDown(s.close);
      await s.waitFor(188);
      final before = await _json('${panel.statsUrl}?reset=1');
      expect(before['acceptedStreams'], 1);
      final after = panel.stats;
      expect(after.acceptedStreams, 0);
      expect(after.requestsByPath, isEmpty);
      expect(after.activeConnections, 1);
      expect(after.maxConcurrentSeen, 1);
      expect(after.maxConcurrentAttempted, 1);
    });

    test('waitForStats times out', () async {
      await expectLater(
        panel.waitForStats(
          (_) => false,
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('serves PNG logos', () async {
      final res = await _get('${panel.baseUrl}/logo/live1001.png');
      expect(res.headers.contentType?.mimeType, 'image/png');
      expect(res.body.sublist(1, 4), utf8.encode('PNG'));
      expect((await _get('${panel.baseUrl}/nope')).status, 404);
    });
  });

  test('encoded credentials and anyIPv4 binding', () async {
    final panel = await FakePanel.start(
      mediaDir: null,
      username: 'a b',
      password: 'p@ss/1',
      anyIPv4: true,
      syntheticVodBytes: 100,
    );
    addTearDown(panel.close);
    expect(panel.address, InternetAddress.anyIPv4);
    expect(panel.liveUrl(1001), contains('/live/a%20b/p%40ss%2F1/1001.ts'));
    final user =
        (await _json(panel.playerApiUrl()))['user_info']
            as Map<String, Object?>;
    expect(user['auth'], 1);
    expect((await _get(panel.movieUrl(2001))).status, 200);
    final m3u = await _get(panel.m3uUrl());
    expect(m3u.text, contains('/live/a%20b/p%40ss%2F1/1001.ts'));

    // Reachable through a non-loopback interface, when the host has one.
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final external = interfaces
        .expand((i) => i.addresses)
        .where((a) => !a.isLoopback)
        .firstOrNull;
    if (external != null) {
      final url = panel.playerApiUrl().replaceFirst(
        '127.0.0.1',
        external.address,
      );
      final res = await _get(url);
      expect(res.status, 200);
      final server = (res.json! as Map<String, Object?>)['server_info'];
      expect(server, containsPair('url', external.address));
    }
  });

  group('TsLoop', () {
    test('synthetic packets are null packets', () {
      final loop = TsLoop.synthetic();
      expect(loop.isSynthetic, isTrue);
      expect(loop.nominalBytesPerSecond, isNull);
      final b = loop.read(5, 3);
      expect(b, hasLength(3 * 188));
      for (var o = 0; o < b.length; o += 188) {
        expect(b.sublist(o, o + 4), [0x47, 0x1F, 0xFF, 0x10]);
      }
      final seg = loop.segment(2, const Duration(seconds: 1), 18800);
      expect([seg.firstPacket, seg.packetCount], [200, 100]);
      expect(
        loop.segmentAt(
          const Duration(milliseconds: 2500),
          const Duration(seconds: 1),
        ),
        2,
      );
    });

    test('rejects non-TS data', () {
      expect(TsLoop.tryParse(Uint8List(100)), isNull);
      expect(TsLoop.tryParse(Uint8List(188 * 3)), isNull);
    });

    test('loops shift PCR, PTS, DTS and continuity counters', () {
      final loop = TsLoop.tryParse(_syntheticTs())!;
      expect(loop.packetCount, 10);
      expect(loop.loopTicks, 18000);
      expect(loop.nominalBytesPerSecond, 10 * 188 * 90000 ~/ 18000);
      final pass0 = loop.read(0, 10);
      final pass1 = loop.read(10, 10);
      expect(_pts(pass1, 2), _pts(pass0, 2) + 18000);
      expect(_dts(pass1, 2), _dts(pass0, 2) + 18000);
      expect(_pcr(pass1, 2), _pcr(pass0, 2) + 18000);
      expect(_pts(pass1, 3), _pts(pass0, 3) + 18000);
      // Video PID carries 4 payload packets per pass, PAT and audio 2.
      expect(_cc(pass1, 2), 4);
      expect(_cc(pass1, 9), 7);
      expect(_cc(pass1, 0), 2);
      expect(_cc(pass1, 3), 2);
      expect(_cc(loop.read(42, 1), 0), 0); // pass 4 wraps the video CC
      // Payload bytes are untouched.
      expect(
        pass1.sublist(188 * 9 + 30, 188 * 10),
        pass0.sublist(188 * 9 + 30),
      );
    });

    test('timestamps wrap at 33 bits', () {
      const base = 0x1FFFFFFFF - 20000;
      final loop = TsLoop.tryParse(_syntheticTs(videoPts: base))!;
      expect(loop.loopTicks, 18000);
      final pass1 = loop.read(10, 10);
      expect(_pts(pass1, 2), base + 18000);
      expect(_pts(pass1, 9), (base + 10800 + 18000) & 0x1FFFFFFFF);
      expect(_pts(pass1, 9), lessThan(10000));
    });

    test('HLS segments start at PAT/PMT before keyframes', () {
      final loop = TsLoop.tryParse(_syntheticTs())!;
      expect(loop.hasKeyframeIndex, isTrue);
      const target = Duration(milliseconds: 100);
      final s0 = loop.segment(0, target, 0);
      final s1 = loop.segment(1, target, 0);
      final s2 = loop.segment(2, target, 0);
      expect([s0.firstPacket, s0.packetCount], [0, 5]);
      expect([s1.firstPacket, s1.packetCount], [5, 5]);
      expect([s2.firstPacket, s2.packetCount], [10, 5]);
      expect(s0.duration, const Duration(milliseconds: 120));
      expect(s1.duration, const Duration(milliseconds: 80));
      final pat = loop.read(s1.firstPacket, 1);
      expect([pat[1] & 0x1F, pat[2]], [0, 0]);
      expect(loop.segmentAt(const Duration(milliseconds: 130), target), 1);
      expect(loop.segmentAt(const Duration(milliseconds: 250), target), 2);
      expect(loop.targetDurationSeconds(target), 1);
      // A long target groups both GOPs into one segment per pass.
      final whole = loop.segment(1, const Duration(seconds: 1), 0);
      expect([whole.firstPacket, whole.packetCount], [10, 10]);
    });

    test(
      'generated media loops seamlessly',
      skip: File('test/media/h264_aac.ts').existsSync()
          ? false
          : 'run tool/gen_media.sh first',
      () {
        final loop = TsLoop.tryParse(
          File('test/media/h264_aac.ts').readAsBytesSync(),
        )!;
        expect(loop.loopTicks / 90000, closeTo(20, 0.1));
        expect(loop.hasKeyframeIndex, isTrue);
        final seg = loop.segment(3, const Duration(seconds: 2), 0);
        expect(seg.duration.inMilliseconds, closeTo(2000, 50));
        final first = loop.read(seg.firstPacket, 1);
        expect(((first[1] & 0x1F) << 8) | first[2], 0); // PAT
      },
    );
  });

  group('media files', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('fake_panel_media');
      File('${dir.path}/h264_aac.ts').writeAsBytesSync(_syntheticTs());
      File('${dir.path}/vod_2audio_ara_eng_srt.mkv')
          .writeAsBytesSync(List.generate(3000, (i) => (i * 7) & 0xFF));
    });
    tearDown(() => dir.delete(recursive: true));

    test('live, HLS and VOD use files from mediaDir', () async {
      final panel = await FakePanel.start(
        mediaDir: dir.path,
        hlsSegmentDuration: const Duration(milliseconds: 100),
        hlsSessionTimeout: const Duration(milliseconds: 500),
        now: () => DateTime.utc(2026),
      );
      addTearDown(panel.close);
      expect(panel.liveUsesMediaFile(1001), isTrue);
      // 1002 maps to h264_mp2.ts, which is missing: falls back to the default.
      expect(panel.liveUsesMediaFile(1002), isTrue);
      expect(panel.vodUsesMediaFile, isTrue);

      final s = await _Stream.open(panel.liveUrl(1002));
      addTearDown(s.close);
      await s.waitFor(188 * 20);
      final head = s.head;
      expect(_pts(head, 12), _pts(head, 2) + 18000); // second pass

      final playlist = await _get(panel.liveUrl(1001, ext: 'm3u8'));
      expect(playlist.status, 403); // still streaming 1002
      await s.close();
      await panel.waitForStats((st) => st.activeConnections == 0);
      final text = (await _get(panel.liveUrl(1001, ext: 'm3u8'))).text;
      expect(text, contains('#EXTINF:0.120,\n/hls/1001/0.ts\n'));
      expect(text, contains('#EXTINF:0.080,\n/hls/1001/1.ts\n'));
      final seg = await _get('${panel.baseUrl}/hls/1001/1.ts');
      expect(seg.body, hasLength(5 * 188));
      // The HLS viewer holds the only connection until its session ends.
      expect((await _get(panel.movieUrl(2002))).status, 403);
      await panel.waitForStats((st) => st.activeConnections == 0);

      final vod = await _get(
        panel.movieUrl(2002),
        headers: {'range': 'bytes=100-103'},
      );
      expect(vod.headers.value('content-range'), 'bytes 100-103/3000');
      expect(vod.body, [for (var i = 100; i < 104; i++) (i * 7) & 0xFF]);
    });

    test('VOD is read from disk per request, not cached whole', () async {
      final panel = await FakePanel.start(mediaDir: dir.path);
      addTearDown(panel.close);
      final file = File('${dir.path}/vod_2audio_ara_eng_srt.mkv');
      var res = await _get(panel.movieUrl(2001));
      expect(res.body, hasLength(3000));
      expect(res.body.sublist(0, 3), [0, 7, 14]);
      // Same length, new bytes: the next request serves them.
      file.writeAsBytesSync(List.filled(3000, 0xAB));
      res = await _get(panel.movieUrl(2001), headers: {'range': 'bytes=2990-'});
      expect(res.status, 206);
      expect(res.body, List.filled(10, 0xAB));
    });

    test(
      'large VOD files are served without loading them',
      skip: Platform.isWindows ? 'needs sparse files' : false,
      () async {
        const size = 3 << 30; // 3 GiB, sparse.
        final file = File('${dir.path}/vod_2audio_ara_eng_srt.mkv');
        final raf = file.openSync(mode: FileMode.write)
          ..truncateSync(size)
          ..setPositionSync(size - 4)
          ..writeFromSync([1, 2, 3, 4]);
        raf.closeSync();
        final panel = await FakePanel.start(mediaDir: dir.path);
        addTearDown(panel.close);
        final rss = ProcessInfo.currentRss;

        var res = await _get(panel.movieUrl(2001), method: 'HEAD');
        expect(res.headers.contentLength, size);
        res = await _get(panel.movieUrl(2001), headers: {'range': 'bytes=-6'});
        expect(res.status, 206);
        expect(
          res.headers.value('content-range'),
          'bytes ${size - 6}-${size - 1}/$size',
        );
        expect(res.body, [0, 0, 1, 2, 3, 4]);
        res = await _get(
          panel.movieUrl(2001),
          headers: {'range': 'bytes=${1 << 31}-${(1 << 31) + 99}'},
        );
        expect(res.body, List.filled(100, 0));
        expect(ProcessInfo.currentRss - rss, lessThan(256 << 20));
      },
    );
  });
}

// ------------------------------------------------------------------ helpers

class _Res {
  _Res(this.status, this.headers, this.body);

  final int status;
  final HttpHeaders headers;
  final Uint8List body;

  String get text => utf8.decode(body);
  Object? get json => jsonDecode(text);
}

Future<_Res> _get(
  String url, {
  Map<String, String> headers = const {},
  String method = 'GET',
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client.openUrl(method, Uri.parse(url));
    headers.forEach(req.headers.set);
    final res = await req.close();
    final body = BytesBuilder(copy: false);
    await for (final chunk in res) {
      body.add(chunk);
    }
    return _Res(res.statusCode, res.headers, body.takeBytes());
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> _json(String url) async =>
    (await _get(url)).json! as Map<String, Object?>;

Future<List<Map<String, Object?>>> _list(String url) async =>
    ((await _get(url)).json! as List<Object?>).cast<Map<String, Object?>>();

/// An open streaming response that keeps reading in the background.
class _Stream {
  _Stream._(this._client, this.response);

  static Future<_Stream> open(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(url));
    headers.forEach(req.headers.set);
    final s = _Stream._(client, await req.close());
    s._sub = s.response.listen(
      (chunk) {
        if (s._head.length < 64 * 1024) s._head.add(chunk);
        s.received += chunk.length;
      },
      onError: (Object _) => s._finish(),
      onDone: s._finish,
      cancelOnError: true,
    );
    return s;
  }

  final HttpClient _client;
  final HttpClientResponse response;
  final _head = BytesBuilder();
  late final StreamSubscription<List<int>> _sub;
  final done = Completer<void>();
  int received = 0;

  int get status => response.statusCode;

  /// First bytes received (up to 64 KiB).
  Uint8List get head => _head.toBytes();

  void _finish() {
    if (!done.isCompleted) done.complete();
  }

  Future<void> waitFor(int bytes) async {
    final sw = Stopwatch()..start();
    while (received < bytes) {
      if (done.isCompleted || sw.elapsed > const Duration(seconds: 5)) {
        fail('Stream gave $received of $bytes bytes');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> close() async {
    await _sub.cancel();
    _client.close(force: true);
    _finish();
  }
}

// MPEG-TS fixtures: PAT, PMT, video (0x100) and audio (0x101) PES packets.

const _pmtPid = 0x1000;

/// One pass of 10 packets: two GOPs, video 4 frames of 3600 ticks, audio
/// 2 PES starting 3600 ticks earlier, so a pass lasts 18000 ticks.
Uint8List _syntheticTs({int videoPts = 900000}) {
  final v = videoPts;
  final a = (videoPts - 3600) & 0x1FFFFFFFF;
  final packets = [
    _packet(0x0000, 0, pusi: true, payload: _pat()),
    _packet(_pmtPid, 0, pusi: true, payload: [0x00, 0x02, 0xB0, 0x0D]),
    _packet(
      0x100,
      0,
      pusi: true,
      pcr: v - 3600,
      rai: true,
      payload: _pes(0xE0, v, v - 3600),
    ),
    _packet(0x101, 0, pusi: true, payload: _pes(0xC0, a)),
    _packet(0x100, 1, pusi: true, payload: _pes(0xE0, v + 3600)),
    _packet(0x0000, 1, pusi: true, payload: _pat()),
    _packet(_pmtPid, 1, pusi: true, payload: [0x00, 0x02, 0xB0, 0x0D]),
    _packet(0x100, 2, pusi: true, rai: true, payload: _pes(0xE0, v + 7200)),
    _packet(0x101, 1, pusi: true, payload: _pes(0xC0, a + 7200)),
    _packet(0x100, 3, pusi: true, payload: _pes(0xE0, v + 10800)),
  ];
  return Uint8List.fromList(packets.expand((p) => p).toList());
}

List<int> _pat() => [
  0x00, // pointer_field
  0x00, 0xB0, 0x0D, 0x00, 0x01, 0xC1, 0x00, 0x00, // header, length 13
  0x00, 0x01, 0xE0 | (_pmtPid >> 8), _pmtPid & 0xFF, // program 1 -> PMT
  0x00, 0x00, 0x00, 0x00, // CRC (unchecked)
];

List<int> _pes(int streamId, int pts, [int? dts]) => [
  0x00, 0x00, 0x01, streamId, 0x00, 0x00, 0x80, //
  dts == null ? 0x80 : 0xC0, dts == null ? 5 : 10,
  ..._timestamp(dts == null ? 0x2 : 0x3, pts),
  if (dts != null) ..._timestamp(0x1, dts),
];

List<int> _timestamp(int prefix, int v) => [
  (prefix << 4) | (((v >> 30) & 0x07) << 1) | 1,
  (v >> 22) & 0xFF,
  (((v >> 15) & 0x7F) << 1) | 1,
  (v >> 7) & 0xFF,
  ((v & 0x7F) << 1) | 1,
];

List<int> _packet(
  int pid,
  int cc, {
  bool pusi = false,
  int? pcr,
  bool rai = false,
  List<int> payload = const [],
}) {
  final b = Uint8List(188)..fillRange(0, 188, 0xFF);
  b[0] = 0x47;
  b[1] = (pusi ? 0x40 : 0) | ((pid >> 8) & 0x1F);
  b[2] = pid & 0xFF;
  final adaptation = pcr != null || rai;
  b[3] = (adaptation ? 0x30 : 0x10) | (cc & 0x0F);
  var p = 4;
  if (adaptation) {
    final length = pcr != null ? 7 : 1;
    b[4] = length;
    b[5] = (rai ? 0x40 : 0) | (pcr != null ? 0x10 : 0);
    if (pcr != null) {
      b[6] = (pcr >> 25) & 0xFF;
      b[7] = (pcr >> 17) & 0xFF;
      b[8] = (pcr >> 9) & 0xFF;
      b[9] = (pcr >> 1) & 0xFF;
      b[10] = ((pcr & 1) << 7) | 0x7E;
      b[11] = 0;
    }
    p = 5 + length;
  }
  b.setRange(p, p + payload.length, payload);
  return b;
}

int _cc(Uint8List b, int packet) => b[packet * 188 + 3] & 0x0F;

/// PES header offset in [packet] (after an optional adaptation field).
int _pesAt(Uint8List b, int packet) {
  final o = packet * 188;
  return (b[o + 3] & 0x20) != 0 ? o + 5 + b[o + 4] : o + 4;
}

int _readTimestamp(Uint8List b, int p) =>
    (((b[p] >> 1) & 0x07) << 30) |
    (b[p + 1] << 22) |
    ((b[p + 2] >> 1) << 15) |
    (b[p + 3] << 7) |
    (b[p + 4] >> 1);

int _pts(Uint8List b, int packet) => _readTimestamp(b, _pesAt(b, packet) + 9);

int _dts(Uint8List b, int packet) => _readTimestamp(b, _pesAt(b, packet) + 14);

int _pcr(Uint8List b, int packet) {
  final p = packet * 188 + 6;
  return (b[p] << 25) |
      (b[p + 1] << 17) |
      (b[p + 2] << 9) |
      (b[p + 3] << 1) |
      (b[p + 4] >> 7);
}
