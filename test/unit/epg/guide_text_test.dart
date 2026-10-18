import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/epg/epg_models.dart';

void main() {
  group('unescapeGuideText', () {
    test('turns literal escapes into line breaks', () {
      expect(
        unescapeGuideText(r'The season is live.\r\nThe champions return.'),
        'The season is live.\nThe champions return.',
      );
      expect(unescapeGuideText(r'One\nTwo\rThree'), 'One\nTwo\nThree');
    });

    test('collapses runs of blank lines and trims', () {
      expect(
        unescapeGuideText(r'First.\r\n\r\n\r\n\r\nSecond.\r\n'),
        'First.\n\nSecond.',
      );
    });

    test('leaves other text alone', () {
      const plain = 'نشرة الأخبار\nLate Show';
      expect(identical(unescapeGuideText(plain), plain), isTrue);
      expect(unescapeGuideText(r'AC\DC live'), r'AC\DC live');
    });
  });
}
