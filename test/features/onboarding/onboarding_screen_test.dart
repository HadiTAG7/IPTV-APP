import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/app.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/features/onboarding/onboarding_screen.dart';
import 'package:iptv_player/features/sources/source_editor_screen.dart';

import '../sources/support.dart';

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(IptvApp)));

/// A recognisable page for Help (the real one belongs to another feature).
Widget _pages(HomeTab tab) => tab == HomeTab.help
    ? const Center(child: Text('HELP PAGE'))
    : FakeTabPage(tab);

void main() {
  for (final rtl in [false, true]) {
    final name = rtl ? 'ar' : 'en';
    final l10n = rtl ? arL10n : enL10n;
    // Toward the reading end of a row: right in English, left in Arabic.
    final toEnd = rtl
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight;
    final toStart = rtl
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;

    testWidgets('TV $name: remote-only walk through onboarding', (
      tester,
    ) async {
      final db = openAppTestDb();
      await pumpApp(
        tester,
        db: db,
        caps: tvCaps,
        settings: AppSettings(
          locale: rtl ? AppLocaleSetting.ar : AppLocaleSetting.en,
        ),
        pages: _pages,
      );
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text(l10n.onboardingWelcomeTitle), findsOneWidget);
      expect(find.text(l10n.onboardingDisclaimer), findsOneWidget);
      final current = rtl ? 'onboarding-lang-ar' : 'onboarding-lang-en';
      final other = rtl ? 'onboarding-lang-en' : 'onboarding-lang-ar';
      // The current language has the focus.
      expectFocus(current);

      // Arabic is the first button of the row: on the start side, so
      // left in English and right in Arabic.
      final arX = tester
          .getCenter(find.byKey(const ValueKey('onboarding-lang-ar')))
          .dx;
      final enX = tester
          .getCenter(find.byKey(const ValueKey('onboarding-lang-en')))
          .dx;
      expect(rtl ? arX > enX : arX < enX, isTrue);

      // Mirrored arrows move between the two buttons; the row's edges are
      // dead ends.
      final towardOther = rtl ? toEnd : toStart;
      final towardCurrent = rtl ? toStart : toEnd;
      await press(tester, towardCurrent);
      expectFocus(current);
      await press(tester, towardOther);
      expectFocus(other);
      await press(tester, towardOther);
      expectFocus(other);
      await press(tester, towardCurrent);
      expectFocus(current);

      // Down: Learn more, then Add a source; Up comes back.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocus('onboarding-learn-more');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocus('onboarding-add-source');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocus('onboarding-add-source');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expectFocus('onboarding-learn-more');

      // Learn more opens Help; Back returns to the same button.
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text('HELP PAGE'), findsOneWidget);
      await back(tester);
      expect(find.text('HELP PAGE'), findsNothing);
      expectFocus('onboarding-learn-more');

      // Add a source opens the editor focused on the source type.
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(SourceEditorScreen), findsOneWidget);
      expectFocus('type-m3uUrl');
      await back(tester);
      expect(find.byType(SourceEditorScreen), findsNothing);
      expectFocus('onboarding-add-source');
      expect(_container(tester).read(onboardingHoldProvider), isFalse);
      await disposeApp(tester, db);
    });

    testWidgets('TV $name: picking the other language switches the app', (
      tester,
    ) async {
      final db = openAppTestDb();
      await pumpApp(
        tester,
        db: db,
        caps: tvCaps,
        settings: AppSettings(
          locale: rtl ? AppLocaleSetting.ar : AppLocaleSetting.en,
        ),
      );
      final other = rtl ? 'onboarding-lang-en' : 'onboarding-lang-ar';
      await press(tester, rtl ? toEnd : toStart);
      expectFocus(other);
      await press(tester, LogicalKeyboardKey.select);

      final switched = rtl ? enL10n : arL10n;
      expect(find.text(switched.onboardingWelcomeTitle), findsOneWidget);
      final context = tester.element(find.byType(OnboardingScreen));
      expect(
        Directionality.of(context),
        rtl ? TextDirection.ltr : TextDirection.rtl,
      );
      // Focus stays on the pressed button through the rebuild.
      expectFocus(other);
      final settings = _container(tester).read(settingsProvider);
      expect(settings.locale, rtl ? AppLocaleSetting.en : AppLocaleSetting.ar);
      // And it is saved.
      expect((await loadAppSettings(db.settingsDao)).locale, settings.locale);
      await disposeApp(tester, db);
    });

    testWidgets('phone $name: tap through onboarding', (tester) async {
      final db = openAppTestDb();
      await pumpApp(
        tester,
        db: db,
        settings: AppSettings(
          locale: rtl ? AppLocaleSetting.ar : AppLocaleSetting.en,
        ),
        pages: _pages,
      );
      expect(find.text(l10n.onboardingAddSourceTitle), findsOneWidget);
      await tapKey(tester, 'onboarding-learn-more');
      expect(find.text('HELP PAGE'), findsOneWidget);
      await back(tester);
      await tapKey(tester, 'onboarding-add-source');
      expect(find.byType(SourceEditorScreen), findsOneWidget);
      expect(find.text(l10n.settingsAddSource), findsOneWidget);
      await disposeApp(tester, db);
    });
  }
}
