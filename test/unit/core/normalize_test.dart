import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/text/normalize.dart';

void main() {
  group('normalizeForSearch', () {
    test('folds Arabic letter variants and strips diacritics', () {
      expect(normalizeForSearch('أَلْجَزِيرَة'), 'الجزيره');
      expect(normalizeForSearch('إخبارية'), 'اخباريه');
      expect(normalizeForSearch('مـــصر'), 'مصر');
      expect(normalizeForSearch('على'), 'علي');
      expect(normalizeForSearch('مؤتمر'), 'موتمر');
    });

    test('converts Arabic-Indic digits and lower-cases Latin', () {
      expect(normalizeForSearch('MBC ٢'), 'mbc 2');
      expect(normalizeForSearch('Channel ۳'), 'channel 3');
    });

    test('collapses whitespace', () {
      expect(normalizeForSearch('  Al   Arabiya \t HD '), 'al arabiya hd');
    });
  });

  group('normalizeForEpg', () {
    test('strips quality and country tags', () {
      expect(normalizeForEpg('AR: Al Jazeera HD'), 'al jazeera');
      expect(normalizeForEpg('|SA| MBC 1 FHD'), 'mbc 1');
      expect(normalizeForEpg('Sky News Arabia (1080p)'), 'sky news arabia');
      expect(normalizeForEpg('France 24 Arabic @SD'), 'france 24 arabic');
      expect(normalizeForEpg('العربية HD'), 'العربيه');
    });

    test('keeps numbers that are part of the name', () {
      expect(normalizeForEpg('MBC 4 HD'), 'mbc 4');
      expect(normalizeForEpg('Rotana Cinema 4K'), 'rotana cinema');
    });
  });
}
