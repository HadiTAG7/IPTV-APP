import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/sources/xtream/json_array_stream.dart';

/// Splits [bytes] into chunks of random size (1..maxChunk).
Stream<List<int>> chunked(List<int> bytes, Random rnd, {int maxChunk = 64}) {
  final chunks = <List<int>>[];
  var i = 0;
  while (i < bytes.length) {
    final n = 1 + rnd.nextInt(maxChunk);
    final end = min(i + n, bytes.length);
    chunks.add(bytes.sublist(i, end));
    i = end;
  }
  return Stream.fromIterable(chunks);
}

Future<List<Map<String, Object?>>> decodeText(
  String text, {
  int chunk = 1 << 20,
}) =>
    jsonArrayStream(Stream.fromIterable(_split(utf8.encode(text), chunk)))
        .toList();

Iterable<List<int>> _split(List<int> bytes, int size) sync* {
  for (var i = 0; i < bytes.length; i += size) {
    yield bytes.sublist(i, min(i + size, bytes.length));
  }
}

/// Expected output computed with plain [jsonDecode].
List<Object?> expected(String text) {
  final v = jsonDecode(text);
  final items = v is Map ? v.values.toList() : (v as List<Object?>);
  return items.whereType<Map<String, Object?>>().toList();
}

const _alphabet = [
  'a', 'Z', '0', ' ', '[', ']', '{', '}', ',', ':', '"', r'\', '/', //
  '\n', '\t', '\u0000', '\u001f', 'ع', 'ر', 'ب', 'ي', 'ة', 'é', '€', //
  '\u{1F4FA}', '\u{1F600}', '\u200f', '\uFEFF', 'null', 'true', r'\"', //
  r'\\', '\\u0041', '}]', '[{', '",', '":"',
];

String randomString(Random rnd) {
  final len = rnd.nextInt(12);
  final sb = StringBuffer();
  for (var i = 0; i < len; i++) {
    sb.write(_alphabet[rnd.nextInt(_alphabet.length)]);
  }
  return sb.toString();
}

Object? randomValue(Random rnd, int depth) {
  final pick = rnd.nextInt(depth > 3 ? 5 : 8);
  switch (pick) {
    case 0:
      return randomString(rnd);
    case 1:
      return rnd.nextInt(1 << 31) - (1 << 30);
    case 2:
      return rnd.nextDouble() * 1000;
    case 3:
      return rnd.nextBool();
    case 4:
      return null;
    case 5:
    case 6:
      return randomObject(rnd, depth + 1);
    default:
      return [
        for (var i = 0; i < rnd.nextInt(4); i++) randomValue(rnd, depth + 1),
      ];
  }
}

Map<String, Object?> randomObject(Random rnd, int depth) => {
  for (var i = 0; i < rnd.nextInt(6); i++)
    randomString(rnd): randomValue(rnd, depth),
};

void main() {
  group('arrays', () {
    test('yields each object', () async {
      final items = await decodeText(
        '[{"stream_id":1,"name":"A"},{"stream_id":"2","name":"قناة"}]',
      );
      expect(items, [
        {'stream_id': 1, 'name': 'A'},
        {'stream_id': '2', 'name': 'قناة'},
      ]);
    });

    test('[] and whitespace-only bodies yield nothing', () async {
      expect(await decodeText('[]'), isEmpty);
      expect(await decodeText('  [ \n ]  '), isEmpty);
      expect(await decodeText(''), isEmpty);
      expect(await decodeText(' \r\n\t '), isEmpty);
    });

    test('BOM and surrounding whitespace are skipped', () async {
      final items = await decodeText('\uFEFF \n [ {"a":1} , {"b":2} ] \n');
      expect(items, [
        {'a': 1},
        {'b': 2},
      ]);
    });

    test('non-object elements are skipped', () async {
      final items = await decodeText(
        '[1, "x", null, [{"nested":true}], {"a":[1,{"b":"]"}]}, true]',
      );
      expect(items, [
        {
          'a': [
            1,
            {'b': ']'},
          ],
        },
      ]);
    });

    test('structural characters inside strings are ignored', () async {
      const text = r'[{"n":"a,b]}{[\"q\" \\"},{"n":"\\"},{"n":"\u005d\u007d"}]';
      expect(await decodeText(text), expected(text));
      expect(await decodeText(text, chunk: 1), expected(text));
    });

    test('trailing data after the array is ignored', () async {
      expect(await decodeText('[{"a":1}] \n'), [
        {'a': 1},
      ]);
    });
  });

  group('objects', () {
    test('object-shaped lists yield their values', () async {
      const text = '{"0":{"stream_id":1},"1":{"stream_id":2},"2":"skip"}';
      expect(await decodeText(text), [
        {'stream_id': 1},
        {'stream_id': 2},
      ]);
      expect(await decodeText(text, chunk: 3), hasLength(2));
    });

    test('{} and null yield nothing', () async {
      expect(await decodeText('{}'), isEmpty);
      expect(await decodeText(' { } '), isEmpty);
      expect(await decodeText('null'), isEmpty);
    });
  });

  group('malformed input', () {
    test('truncated array throws', () {
      expect(decodeText('[{"a":1},{"b":'), throwsFormatException);
      expect(decodeText('['), throwsFormatException);
    });

    test('bad element throws', () {
      expect(decodeText('[{"a":1},{b:2}]'), throwsFormatException);
    });

    test('unbalanced closing brace throws', () {
      expect(decodeText('[{"a":1}}]'), throwsFormatException);
    });

    test('HTML error page throws', () {
      expect(
        decodeText('<html><body>502 Bad Gateway</body></html>'),
        throwsFormatException,
      );
    });

    test('top-level scalar throws', () {
      expect(decodeText('"error"'), throwsFormatException);
      expect(decodeText('42'), throwsFormatException);
    });
  });

  group('chunk boundaries', () {
    test('every split point of a multi-byte document', () async {
      const text =
          '[{"name":"قناة العربية 📺","x":"\\"]"},{"name":"€ – é","y":[{}]}]';
      final bytes = utf8.encode(text);
      final want = expected(text);
      for (var i = 0; i <= bytes.length; i++) {
        final got = await jsonArrayStream(
          Stream.fromIterable([bytes.sublist(0, i), bytes.sublist(i)]),
        ).toList();
        expect(got, want, reason: 'split at $i');
      }
    });

    test('one byte at a time', () async {
      const text = '[{"t":"مرحبا بالعالم"},{"t":"\\u0645"}]';
      final got = await jsonArrayStream(
        Stream.fromIterable(utf8.encode(text).map((b) => [b])),
      ).toList();
      expect(got, expected(text));
    });
  });

  group('fuzz against jsonDecode', () {
    test('random arrays, random chunking', () async {
      final rnd = Random(20261014);
      for (var round = 0; round < 400; round++) {
        final list = [
          for (var i = 0; i < rnd.nextInt(8); i++)
            rnd.nextInt(6) == 0 ? randomValue(rnd, 0) : randomObject(rnd, 0),
        ];
        final text = rnd.nextBool()
            ? jsonEncode(list)
            : const JsonEncoder.withIndent('  ').convert(list);
        final got = await jsonArrayStream(
          chunked(utf8.encode(text), rnd, maxChunk: 1 + rnd.nextInt(40)),
        ).toList();
        expect(got, expected(text), reason: 'round $round: $text');
      }
    });

    test('random object-shaped lists, random chunking', () async {
      final rnd = Random(7);
      for (var round = 0; round < 150; round++) {
        final map = {
          for (var i = 0; i < rnd.nextInt(6); i++) '$i': randomObject(rnd, 0),
        };
        final text = jsonEncode(map);
        final got = await jsonArrayStream(
          chunked(utf8.encode(text), rnd, maxChunk: 16),
        ).toList();
        expect(got, expected(text), reason: 'round $round: $text');
      }
    });
  });

  test('large list stays streaming', () async {
    final rnd = Random(1);
    final list = [
      for (var i = 0; i < 20000; i++)
        {'stream_id': i, 'name': 'Channel $i ${randomString(rnd)}'},
    ];
    final bytes = utf8.encode(jsonEncode(list));
    var count = 0;
    await for (final item in jsonArrayStream(
      Stream.fromIterable(_split(bytes, 65536)),
    )) {
      expect(item['stream_id'], count);
      count++;
    }
    expect(count, 20000);
  });
}
