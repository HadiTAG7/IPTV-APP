import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/epg/xmltv_time.dart';

void main() {
  group('parseXmltvTime', () {
    final cases = <String, DateTime>{
      // Offsets.
      '20261014193000 +0300': DateTime.utc(2026, 10, 14, 16, 30),
      '20261014193000 -0500': DateTime.utc(2026, 10, 15, 0, 30),
      '20261014193000 +05:30': DateTime.utc(2026, 10, 14, 14),
      '20261014193000 +0000': DateTime.utc(2026, 10, 14, 19, 30),
      '20261014193000 -0000': DateTime.utc(2026, 10, 14, 19, 30),
      '20261014193000+0300': DateTime.utc(2026, 10, 14, 16, 30),
      '20261014193000 +03': DateTime.utc(2026, 10, 14, 16, 30),
      '20261014193000 +1400': DateTime.utc(2026, 10, 14, 5, 30),
      '20261014000000 -1200': DateTime.utc(2026, 10, 14, 12),
      // No offset means UTC.
      '20261014193015': DateTime.utc(2026, 10, 14, 19, 30, 15),
      // Partial dates.
      '20261014': DateTime.utc(2026, 10, 14),
      '202610141930': DateTime.utc(2026, 10, 14, 19, 30),
      '202610141930 +0300': DateTime.utc(2026, 10, 14, 16, 30),
      '2026101419': DateTime.utc(2026, 10, 14, 19),
      '2026101419 +0300': DateTime.utc(2026, 10, 14, 16),
      // Crossing midnight and year ends.
      '20260101013000 +0300': DateTime.utc(2025, 12, 31, 22, 30),
      '20261231230000 -0200': DateTime.utc(2027, 1, 1, 1),
      // Leap day.
      '20280229120000 +0000': DateTime.utc(2028, 2, 29, 12),
      // Whitespace and trailing junk.
      '  20261014193000 +0300  ': DateTime.utc(2026, 10, 14, 16, 30),
      '20261014193000 +0300 (Riyadh)': DateTime.utc(2026, 10, 14, 16, 30),
      '20261014193000Z': DateTime.utc(2026, 10, 14, 19, 30),
      '20261014193000 UTC': DateTime.utc(2026, 10, 14, 19, 30),
      '20261014193000.250 +0300': DateTime.utc(2026, 10, 14, 16, 30),
    };

    cases.forEach((input, expected) {
      test('"$input"', () {
        final t = parseXmltvTime(input);
        expect(t, expected);
        expect(t!.isUtc, isTrue);
      });
    });

    test('rejects invalid input', () {
      for (final bad in [
        '',
        '   ',
        'bad',
        '2026-10-14T19:30:00Z',
        '202',
        '2026',
        '202610',
        '2026101',
        '20261314193000',
        '20261000193000',
        '20261032193000',
        '20260230120000',
        '20270229120000',
        '20261014243000',
        '20261014196000',
        '20261014193060',
        '20261014193000 +2500',
        '20261014193000 +0360',
      ]) {
        expect(parseXmltvTime(bad), isNull, reason: bad);
      }
    });
  });
}
