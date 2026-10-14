import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/sources/xtream/coerce.dart';

void main() {
  group('asInt', () {
    test('accepts ints, doubles, numeric strings and bools', () {
      expect(asInt(5), 5);
      expect(asInt(5.9), 5);
      expect(asInt(-2.5), -2);
      expect(asInt('42'), 42);
      expect(asInt(' 42 '), 42);
      expect(asInt('12.0'), 12);
      expect(asInt('-7'), -7);
      expect(asInt(true), 1);
      expect(asInt(false), 0);
    });

    test('rejects junk', () {
      expect(asInt(null), isNull);
      expect(asInt(''), isNull);
      expect(asInt('  '), isNull);
      expect(asInt('abc'), isNull);
      expect(asInt('12abc'), isNull);
      expect(asInt(double.nan), isNull);
      expect(asInt(double.infinity), isNull);
      expect(asInt('NaN'), isNull);
      expect(asInt(const []), isNull);
      expect(asInt(const {'a': 1}), isNull);
    });
  });

  group('asDouble', () {
    test('accepts numbers and numeric strings', () {
      expect(asDouble(3), 3.0);
      expect(asDouble(3.7), 3.7);
      expect(asDouble('7.4'), 7.4);
      expect(asDouble(' 8 '), 8.0);
      expect(asDouble('7,5'), 7.5);
    });

    test('rejects junk', () {
      expect(asDouble(null), isNull);
      expect(asDouble(''), isNull);
      expect(asDouble('n/a'), isNull);
      expect(asDouble(double.nan), isNull);
      expect(asDouble('Infinity'), isNull);
      expect(asDouble(true), isNull);
    });
  });

  group('asBool', () {
    test('truthy values', () {
      for (final v in [
        true,
        1,
        2,
        -1,
        0.5,
        '1',
        'true',
        'TRUE',
        ' yes ',
        'on',
      ]) {
        expect(asBool(v), isTrue, reason: '$v');
      }
    });

    test('falsy values', () {
      for (final v in <Object?>[
        false,
        0,
        0.0,
        '0',
        '',
        'false',
        'no',
        'off',
        'maybe',
        null,
        const [],
        const {},
      ]) {
        expect(asBool(v), isFalse, reason: '$v');
      }
    });
  });

  group('asList', () {
    test('lists pass through, map values count as a list', () {
      expect(asList([1, 'a']), [1, 'a']);
      expect(asList({'0': 'x', '1': 'y'}), ['x', 'y']);
      expect(asList({1: 'x'}), ['x']);
    });

    test('anything else is empty', () {
      expect(asList(null), isEmpty);
      expect(asList(''), isEmpty);
      expect(asList('a,b'), isEmpty);
      expect(asList(3), isEmpty);
    });
  });

  group('asMap', () {
    test('string-keyed maps pass through', () {
      final m = <String, Object?>{'a': 1};
      expect(identical(asMap(m), m), isTrue);
    });

    test('non-string keys are stringified', () {
      expect(asMap({1: 'a', true: 'b'}), {'1': 'a', 'true': 'b'});
    });

    test('[] and null become {}', () {
      expect(asMap(const []), isEmpty);
      expect(asMap(null), isEmpty);
      expect(asMap(''), isEmpty);
      expect(asMap(7), isEmpty);
    });

    test('a non-empty list becomes an index-keyed map', () {
      expect(asMap(['a', 'b']), {'0': 'a', '1': 'b'});
    });
  });

  group('asStrList', () {
    test('from lists, maps and comma strings', () {
      expect(asStrList(['m3u8', 'ts', '', null, 7]), ['m3u8', 'ts', '7']);
      expect(asStrList({'0': 'ts', '1': 'm3u8'}), ['ts', 'm3u8']);
      expect(asStrList('ts, m3u8,,'), ['ts', 'm3u8']);
      expect(asStrList([10, 20.0]), ['10', '20']);
    });

    test('empty for null and nested values', () {
      expect(asStrList(null), isEmpty);
      expect(asStrList(''), isEmpty);
      expect(
        asStrList([
          ['x'],
          {'a': 1},
        ]),
        isEmpty,
      );
    });
  });

  group('asStr', () {
    test('trims and drops empty', () {
      expect(asStr(' News '), 'News');
      expect(asStr(''), isNull);
      expect(asStr('   '), isNull);
      expect(asStr(null), isNull);
    });

    test('stringifies scalars', () {
      expect(asStr(101), '101');
      expect(asStr(401.0), '401');
      expect(asStr(7.5), '7.5');
      expect(asStr(true), 'true');
      expect(asStr(double.nan), isNull);
    });

    test('maps and lists give null', () {
      expect(asStr(const []), isNull);
      expect(asStr(const {'a': 1}), isNull);
    });

    test('keeps Arabic text intact', () {
      expect(asStr(' قناة الأخبار '), 'قناة الأخبار');
    });
  });

  group('asEpoch', () {
    test('seconds as int or string, in UTC', () {
      final t = asEpoch('1700000000')!;
      expect(t.isUtc, isTrue);
      expect(t, DateTime.utc(2023, 11, 14, 22, 13, 20));
      expect(asEpoch(1700000000), t);
      expect(asEpoch(1700000000.0), t);
    });

    test("'' , '0', 0, null and negatives are null", () {
      expect(asEpoch(''), isNull);
      expect(asEpoch('0'), isNull);
      expect(asEpoch(0), isNull);
      expect(asEpoch(null), isNull);
      expect(asEpoch(-5), isNull);
      expect(asEpoch('null'), isNull);
      expect(asEpoch(true), isNull);
    });

    test('milliseconds are detected', () {
      expect(asEpoch(1700000000000), DateTime.utc(2023, 11, 14, 22, 13, 20));
    });

    test('date strings are read as UTC', () {
      expect(asEpoch('2024-05-01 20:00:00'), DateTime.utc(2024, 5, 1, 20));
      expect(asEpoch('2024-05-01T20:00:00Z'), DateTime.utc(2024, 5, 1, 20));
    });

    test('values beyond the DateTime range are null, not a RangeError', () {
      for (final v in <Object>[
        '9999999999999999',
        9999999999999999,
        9e15,
        '1e30',
        1e30,
        '8640000000000001',
        '275760-09-13 01:00:00',
      ]) {
        expect(asEpoch(v), isNull, reason: '$v');
      }
    });

    test('the largest representable instant is kept', () {
      expect(asEpoch(8640000000000000), DateTime.utc(275760, 9, 13));
      expect(asEpoch('8640000000000000'), DateTime.utc(275760, 9, 13));
    });
  });
}
