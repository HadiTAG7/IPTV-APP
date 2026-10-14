import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/theme/tokens.dart';
import 'package:iptv_player/widgets/bidi_text.dart';
import 'package:iptv_player/widgets/logo_image.dart';

void main() {
  group('initialsFor', () {
    const cases = {
      'Example News HD': 'EN',
      'example sports 1': 'ES',
      'Channel 2': 'C2',
      'AR: Sample Drama': 'SD',
      '|SA| Demo Kids FHD': 'DK',
      'العربية التجريبية': 'ع',
      'قناة تجريبية': 'ق',
      'Test-TV': 'TT',
      'x': 'X',
      '24': '2',
      '   ': '?',
      '': '?',
      '★★★': '?',
      'HD': 'H',
    };
    cases.forEach((name, expected) {
      test('"$name" -> "$expected"', () {
        expect(initialsFor(name), expected);
      });
    });

    test('Latin first token followed by Arabic keeps one letter', () {
      expect(initialsFor('Demo قناة'), 'D');
    });
  });

  test('avatar colour is stable and from the palette', () {
    final c = avatarColorFor('Example News');
    expect(avatarColorFor('Example News'), c);
    expect(AppColors.avatarPalette, contains(c));
    expect(AppColors.avatarPalette, contains(avatarColorFor('')));
  });

  group('FailedImageCache', () {
    setUp(FailedImageCache.clear);

    test('remembers and caps entries, oldest first out', () {
      FailedImageCache.add('http://127.0.0.1/a.png');
      expect(FailedImageCache.contains('http://127.0.0.1/a.png'), isTrue);
      for (var i = 0; i < FailedImageCache.maxEntries; i++) {
        FailedImageCache.add('http://127.0.0.1/$i.png');
      }
      expect(FailedImageCache.length, FailedImageCache.maxEntries);
      expect(FailedImageCache.contains('http://127.0.0.1/a.png'), isFalse);
      expect(FailedImageCache.contains('http://127.0.0.1/0.png'), isTrue);
      FailedImageCache.clear();
      expect(FailedImageCache.length, 0);
    });
  });

  test('textDirectionFor detects per-string direction', () {
    expect(textDirectionFor('Example News'), TextDirection.ltr);
    expect(textDirectionFor('قناة الأخبار'), TextDirection.rtl);
    expect(textDirectionFor('Demo قناة الأخبار'), TextDirection.rtl);
    expect(textDirectionFor('123'), TextDirection.ltr);
  });
}
