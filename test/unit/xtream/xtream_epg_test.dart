import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/sources/xtream/xtream_epg.dart';

import 'support/fake_http_adapter.dart';

void main() {
  group('decodeXtreamText', () {
    test('decodes base64 Arabic', () {
      expect(
        decodeXtreamText('2YbYtNix2Kkg2KfZhNij2K7YqNin2LE='),
        'نشرة الأخبار',
      );
    });

    test('decodes base64 Latin text', () {
      expect(decodeXtreamText('RXZlbmluZyBTaG93'), 'Evening Show');
    });

    test('accepts missing padding, surrounding space and line breaks', () {
      expect(
        decodeXtreamText(' 2YbYtNix2Kkg2KfZhNij2K7YqNin2LE '),
        'نشرة الأخبار',
      );
      final wrapped = base64.encode(utf8.encode('نشرة الأخبار' * 6));
      final withBreaks = [
        for (var i = 0; i < wrapped.length; i += 20)
          wrapped.substring(i, (i + 20).clamp(0, wrapped.length)),
      ].join('\r\n');
      expect(decodeXtreamText(withBreaks), 'نشرة الأخبار' * 6);
    });

    test('url-safe alphabet is accepted', () {
      final encoded = base64Url.encode(utf8.encode('أخبار؟ >>> ~~~'));
      expect(decodeXtreamText(encoded), 'أخبار؟ >>> ~~~');
    });

    test('plain text falls back unchanged', () {
      for (final s in [
        'Hello World',
        'News',
        'Test',
        'Sports',
        'Movies',
        'Live',
        'Hello',
        'نشرة الأخبار',
        'Match: A vs B (Live)',
        '',
        '   ',
      ]) {
        expect(decodeXtreamText(s), s, reason: s);
      }
    });

    test('valid base64 of invalid UTF-8 falls back', () {
      final s = base64.encode([0xFF, 0xFE, 0x41]);
      expect(decodeXtreamText(s), s);
    });

    test('decodings with control characters fall back', () {
      expect(decodeXtreamText('AAAA'), 'AAAA');
    });
  });

  group('parseShortEpg', () {
    test('parses the fixture, sorted by start, decoding base64', () {
      final list = parseShortEpg(jsonDecode(xtreamFixture('short_epg.json')));
      expect(list, hasLength(2));
      final first = list.first;
      expect(first.channelId, 'news.example');
      expect(first.title, 'نشرة الأخبار');
      expect(first.desc, 'موجز لأهم الأخبار المحلية والعالمية.');
      expect(first.start, DateTime.utc(2025, 10, 14, 12));
      expect(first.stop, DateTime.utc(2025, 10, 14, 13));
      expect(first.start.isUtc, isTrue);
      expect(list.last.title, 'Evening Show');
      expect(list.last.desc, 'A synthetic evening programme.');
      expect(list.last.start, DateTime.utc(2025, 10, 14, 13));
      expect(first.isOnAt(DateTime.utc(2025, 10, 14, 12, 30)), isTrue);
    });

    test('epg_listings as a map, plain text titles', () {
      final list = parseShortEpg({
        'epg_listings': {
          '0': {
            'epg_id': '55',
            'title': 'Morning Show',
            'description': '',
            'start_timestamp': '1760443200',
            'stop_timestamp': '1760446800',
          },
        },
      });
      expect(list.single.title, 'Morning Show');
      expect(list.single.desc, isNull);
      expect(list.single.channelId, '55');
    });

    test('falls back to the given channel id', () {
      final list = parseShortEpg({
        'epg_listings': [
          {'title': 'X', 'start_timestamp': 100, 'stop_timestamp': 200},
        ],
      }, channelId: 'chan.example');
      expect(list.single.channelId, 'chan.example');
      expect(list.single.start, DateTime.utc(1970, 1, 1, 0, 1, 40));
    });

    test('accepts a bare list', () {
      expect(
        parseShortEpg([
          {'title': 'X', 'start_timestamp': 100, 'stop_timestamp': 200},
        ]),
        hasLength(1),
      );
    });

    test('skips entries with missing or inverted times', () {
      final list = parseShortEpg({
        'epg_listings': [
          {'title': 'no stop', 'start_timestamp': '100'},
          {'title': 'zero', 'start_timestamp': '0', 'stop_timestamp': '0'},
          {'title': 'empty', 'start_timestamp': '', 'stop_timestamp': ''},
          {'title': 'inverted', 'start_timestamp': 300, 'stop_timestamp': 200},
          {
            'title': 'only start/end strings',
            'start': '2025-10-14 12:00:00',
            'end': '2025-10-14 13:00:00',
          },
          'garbage',
          {'title': 'ok', 'start_timestamp': 100, 'stop_timestamp': 200},
        ],
      });
      expect(list.map((p) => p.title), ['ok']);
    });

    test('garbage input gives an empty list', () {
      expect(parseShortEpg(null), isEmpty);
      expect(parseShortEpg(const []), isEmpty);
      expect(parseShortEpg(const {}), isEmpty);
      expect(parseShortEpg('nope'), isEmpty);
      expect(parseShortEpg({'epg_listings': null}), isEmpty);
    });
  });
}
