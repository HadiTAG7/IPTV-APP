import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/help/help_screen.dart';
import 'package:iptv_player/features/help/providers.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';

import '../settings/settings_harness.dart';

const _sectionOrder = [
  'help-intro',
  'help-player',
  'help-free',
  'help-url-sa',
  'help-url-ara',
  'help-receiver',
  'help-official',
  'help-warning',
  'help-updates',
  'help-url-apk',
];

/// TV: Settings, then Help & legal.
Future<void> _openHelpTv(WidgetTester tester) async {
  await openSettingsTv(tester);
  await moveTo(tester, const ValueKey('settings-help'));
  await press(tester, LogicalKeyboardKey.select);
  expect(find.byType(HelpScreen), findsOneWidget);
}

/// Phone: More, then Help & legal.
Future<void> _openHelpPhone(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav-more')));
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('more-help')));
  await settle(tester);
  expect(find.byType(HelpScreen), findsOneWidget);
}

double _scrollOffset(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(HelpScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position
    .pixels;

void _expectContent(WidgetTester tester, AppLocalizations l10n) {
  for (final text in [
    l10n.helpLegalBody,
    l10n.help_playerOnlyTitle,
    l10n.help_playerOnlyBody,
    l10n.help_freeSourcesTitle,
    l10n.help_iptvOrgSaudi,
    l10n.help_iptvOrgArabic,
    l10n.help_officialAppsTitle,
    l10n.help_officialAppsBody,
    l10n.helpWarningSignsTitle,
    l10n.help_updatesTitle,
    l10n.help_updatesBody,
  ]) {
    expect(find.text(text, skipOffstage: false), findsOneWidget, reason: text);
  }
  expect(
    find.textContaining(l10n.help_warningSignsMore, skipOffstage: false),
    findsOneWidget,
  );
  expect(
    find.textContaining(l10n.helpNotLegalAdvice, skipOffstage: false),
    findsOneWidget,
  );
  // The playlist and download links are plain text, left to right.
  for (final url in [kIptvOrgSaudiUrl, kIptvOrgArabicUrl, kLatestApkUrl]) {
    final text = find.text(url, skipOffstage: false);
    expect(text, findsOneWidget, reason: url);
    expect(tester.widget<Text>(text).textDirection, TextDirection.ltr);
  }
}

void main() {
  test('the iptv-org links are the public country and language lists', () {
    expect(
      kIptvOrgSaudiUrl,
      'https://iptv-org.github.io/iptv/countries/sa.m3u',
    );
    expect(
      kIptvOrgArabicUrl,
      'https://iptv-org.github.io/iptv/languages/ara.m3u',
    );
  });

  test('the warning signs do not flag how this app itself is updated', () {
    // Installing an APK from the project's releases page is the documented
    // update path, so "apps from outside the store" alone is no warning
    // sign; what is flagged is the seller's app or a modified copy.
    expect(en.help_warningSignsMore, isNot(contains('outside the store')));
    expect(en.help_warningSignsMore, contains('seller'));
    expect(en.help_warningSignsMore, contains('modified'));
    expect(ar.help_warningSignsMore, isNot(contains('خارج المتجر')));
    expect(ar.help_warningSignsMore, contains('معدّلة'));
    // The update note says where the app comes from and that it is not
    // sold.
    expect(en.help_updatesBody, contains('never sold'));
    expect(ar.help_updatesBody, contains('لا يُباع'));
  });

  for (final rtl in [false, true]) {
    final lang = rtl ? 'ar' : 'en';
    final l10n = rtl ? ar : en;
    final locale = Locale(lang);

    testWidgets('$lang TV: every section is a stop for the remote', (
      tester,
    ) async {
      final h = await pumpSettingsApp(tester, locale: locale);
      await _openHelpTv(tester);
      _expectContent(tester, l10n);
      // Without a source editor there is no "Add as source".
      expect(find.text(l10n.help_addAsSource), findsNothing);

      expect(focusedIn(const ValueKey('help-intro')), isTrue);
      expect(_scrollOffset(tester), 0);
      for (final key in _sectionOrder.skip(1)) {
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(
          focusedIn(ValueKey(key)),
          isTrue,
          reason: '$key: ${focusDescription()}',
        );
        expect(onScreen(tester, find.byKey(ValueKey(key))), isTrue);
      }
      // The page scrolled along.
      expect(_scrollOffset(tester), greaterThan(0));
      // OK on a link without an action does nothing.
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(HelpScreen), findsOneWidget);

      for (final key in _sectionOrder.reversed.skip(1)) {
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(focusedIn(ValueKey(key)), isTrue, reason: key);
      }
      expect(_scrollOffset(tester), 0);

      // Back returns to Settings.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(HelpScreen), findsNothing);
      expect(focusedIn(const ValueKey('settings-help')), isTrue);
      await h.dispose(tester);
    });

    testWidgets('$lang phone: Help from More', (tester) async {
      final h = await pumpSettingsApp(tester, tv: false, locale: locale);
      await _openHelpPhone(tester);
      _expectContent(tester, l10n);
      expect(
        Directionality.of(tester.element(find.byType(HelpScreen))),
        rtl ? TextDirection.rtl : TextDirection.ltr,
      );
      // Keys still walk the sections.
      expect(focusedIn(const ValueKey('help-intro')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('help-player')), isTrue);
      // Touch scrolling reaches the end.
      await tester.scrollUntilVisible(
        find.text(kLatestApkUrl),
        300,
        scrollable: find
            .descendant(
              of: find.byType(HelpScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(onScreen(tester, find.text(kLatestApkUrl)), isTrue);
      await h.dispose(tester);
    });
  }

  testWidgets('TV: "Add as source" opens the editor with the link', (
    tester,
  ) async {
    final h = await pumpSettingsApp(tester, prefill: true);
    await _openHelpTv(tester);
    expect(find.text(en.help_addAsSource), findsNWidgets(2));
    // The download link is not a playlist.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('help-url-apk')),
        matching: find.text(en.help_addAsSource),
      ),
      findsNothing,
    );

    await moveTo(tester, const ValueKey('help-url-sa'));
    await press(tester, LogicalKeyboardKey.select);
    expect(h.prefillCalls, hasLength(1));
    expect(h.prefillCalls.single.url, kIptvOrgSaudiUrl);
    expect(h.prefillCalls.single.name, contains(en.help_iptvOrgSaudi));

    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.select);
    expect(h.prefillCalls.last.url, kIptvOrgArabicUrl);

    await moveTo(tester, const ValueKey('help-url-apk'));
    await press(tester, LogicalKeyboardKey.select);
    expect(h.prefillCalls, hasLength(2));
    await h.dispose(tester);
  });

  testWidgets('ar phone: tapping "Add as source" passes the link', (
    tester,
  ) async {
    final h = await pumpSettingsApp(
      tester,
      tv: false,
      locale: const Locale('ar'),
      prefill: true,
    );
    await _openHelpPhone(tester);
    final row = find.byKey(const ValueKey('help-url-ara'));
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find
          .descendant(
            of: find.byType(HelpScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    // The action sits on the end side (left in Arabic).
    final action = find.descendant(
      of: row,
      matching: find.text(ar.help_addAsSource),
    );
    expect(
      tester.getCenter(action).dx,
      lessThan(tester.getCenter(find.text(kIptvOrgArabicUrl)).dx),
    );
    await tester.tap(action);
    await settle(tester);
    expect(h.prefillCalls.single.url, kIptvOrgArabicUrl);
    expect(h.prefillCalls.single.name, contains(ar.help_iptvOrgArabic));
    await h.dispose(tester);
  });
}
