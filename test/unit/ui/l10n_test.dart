import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';

Map<String, Object?> _arb(String name) =>
    (jsonDecode(File('lib/l10n/$name').readAsStringSync()) as Map)
        .cast<String, Object?>();

Iterable<String> _messageKeys(Map<String, Object?> arb) =>
    arb.keys.where((k) => !k.startsWith('@'));

final _placeholder = RegExp(r'\{(\w+)[,}]');

Set<String> _placeholdersIn(String message) =>
    _placeholder.allMatches(message).map((m) => m.group(1)!).toSet();

void main() {
  final enArb = _arb('app_en.arb');
  final arArb = _arb('app_ar.arb');

  group('ARB catalog', () {
    test('Arabic covers exactly the English keys', () {
      expect(_messageKeys(arArb).toSet(), _messageKeys(enArb).toSet());
    });

    test('placeholders match between languages', () {
      for (final key in _messageKeys(enArb)) {
        final en = _placeholdersIn(enArb[key]! as String);
        final ar = _placeholdersIn(arArb[key]! as String);
        expect(ar, en, reason: key);
        if (en.isNotEmpty) {
          expect(enArb['@$key'], isA<Map<String, Object?>>(), reason: key);
        }
      }
    });

    test('no message is empty', () {
      for (final arb in [enArb, arArb]) {
        for (final key in _messageKeys(arb)) {
          expect((arb[key]! as String).trim(), isNotEmpty, reason: key);
        }
      }
    });

    test('covers every area of the app', () {
      const prefixes = [
        'common',
        'onboarding',
        'sourceType',
        'field',
        'error',
        'import',
        'nav',
        'live',
        'guide',
        'vod',
        'player',
        'aspect',
        'settings',
        'help',
        'diag',
        'lan',
      ];
      final keys = _messageKeys(enArb);
      for (final p in prefixes) {
        expect(keys.any((k) => k.startsWith(p)), isTrue, reason: p);
      }
    });
  });

  group('generated localizations', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final ar = lookupAppLocalizations(const Locale('ar'));

    setUpAll(() async {
      await initializeDateFormatting('en');
      await initializeDateFormatting('ar');
    });

    test('supports en and ar', () {
      expect(
        AppLocalizations.supportedLocales.map((l) => l.languageCode),
        containsAll(['en', 'ar']),
      );
    });

    test('Arabic plural forms zero/one/two/few/many/other', () {
      expect(ar.importLiveCount(0), 'لا توجد قنوات مباشرة');
      expect(ar.importLiveCount(1), 'قناة مباشرة واحدة');
      expect(ar.importLiveCount(2), 'قناتان مباشرتان');
      expect(ar.importLiveCount(3), '3 قنوات مباشرة');
      expect(ar.importLiveCount(10), '10 قنوات مباشرة');
      expect(ar.importLiveCount(11), '11 قناة مباشرة');
      expect(ar.importLiveCount(99), '99 قناة مباشرة');
      expect(ar.importLiveCount(100), '100 قناة مباشرة');
      expect(ar.importLiveCount(52341), '52341 قناة مباشرة');

      expect(ar.importMoviesCount(2), 'فيلمان');
      expect(ar.importMoviesCount(5), '5 أفلام');
      expect(ar.importMoviesCount(25), '25 فيلماً');
      expect(ar.importSeriesCount(1), 'مسلسل واحد');
      expect(ar.importSeriesCount(14), '14 مسلسلاً');
      expect(ar.vodNextEpisodeIn(2), 'الحلقة التالية خلال ثانيتين');
      expect(ar.vodNextEpisodeIn(7), 'الحلقة التالية خلال 7 ثوانٍ');
      expect(ar.settingsExpiresInDays(0), 'ينتهي اليوم');
      expect(ar.settingsExpiresInDays(3), 'ينتهي خلال 3 أيام');
    });

    test('English plurals', () {
      expect(en.importLiveCount(0), 'No live channels');
      expect(en.importLiveCount(1), '1 live channel');
      expect(en.importLiveCount(250), '250 live channels');
      expect(en.importSeriesCount(1), '1 series');
      expect(en.vodNextEpisodeIn(1), 'Next episode in 1 second');
      expect(en.vodNextEpisodeIn(10), 'Next episode in 10 seconds');
      expect(en.settingsExpiresInDays(1), 'Expires in 1 day');
    });

    test('placeholders render', () {
      expect(en.playerReconnecting(3, 8), 'Reconnecting… (3/8)');
      expect(ar.playerReconnecting(3, 8), 'جارٍ إعادة الاتصال… (3/8)');
      expect(en.vodResumeFrom('42:10'), 'Resume from 42:10');
      expect(ar.vodResumeFrom('42:10'), 'استكمال من 42:10');
      expect(en.vodSeasonN(2), 'Season 2');
      expect(ar.vodEpisodeN(5), 'الحلقة 5');
      expect(en.settingsDeleteSourceConfirm('Home'), contains('Home'));
      final date = DateTime.utc(2026, 11, 3);
      expect(
        en.errorExpired(date),
        'This subscription expired on Nov 3, 2026.',
      );
      expect(ar.errorExpired(date), startsWith('انتهى هذا الاشتراك بتاريخ'));
      expect(en.settingsAccountExpires(date), contains('2026'));
    });

    test('player-only disclaimer and legal help text', () {
      expect(
        en.onboardingDisclaimer,
        'The app is a player only and provides no content.',
      );
      expect(ar.onboardingDisclaimer, 'التطبيق مشغّل فقط ولا يوفّر أي محتوى.');
      for (final l in [en, ar]) {
        expect(l.helpLegalBody, contains('iptv-org'));
        expect(l.helpLegalBody, contains('M3U'));
        expect(l.helpLegalBody, contains('OSN+'));
        expect(l.helpLegalBody, contains('2026'));
      }
      expect(ar.helpLegalBody, startsWith('التطبيق مشغّل فقط'));
    });
  });
}
