import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/features/help/licenses.dart';
import 'package:iptv_player/features/help/licenses_page.dart';
import 'package:iptv_player/features/settings/settings_screen.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';

import '../settings/settings_harness.dart';

class _TextBundle extends CachingAssetBundle {
  _TextBundle(this.text);

  final String text;

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
}

const _fontEnd = 'END OF THE FONT LICENCE';

String _fontLicence() => [
  'Copyright 2026 The Tajawal Project Authors.',
  for (var i = 1; i <= 80; i++) 'Paragraph $i of the font licence.',
  _fontEnd,
].join('\n\n');

/// The bundled font (a long text) plus two packages sharing a licence.
void _registerSamples() {
  registerFontLicenses(bundle: _TextBundle(_fontLicence()));
  LicenseRegistry.addLicense(
    () => Stream.fromIterable([
      const LicenseEntryWithLineBreaks(['alpha_pkg'], 'Alpha licence text.'),
      const LicenseEntryWithLineBreaks([
        'zeta_pkg',
        'alpha_pkg',
      ], 'Shared licence text.'),
    ]),
  );
}

void _reset() {
  LicenseRegistry.reset();
  resetFontLicensesForTest();
}

Key _package(String name) => ValueKey('license-package-$name');
const _text = ValueKey('licenses-text');

double _textOffset(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: find.byKey(_text), matching: find.byType(Scrollable)),
    )
    .position
    .pixels;

Future<void> _openLicences(WidgetTester tester) async {
  await moveTo(tester, const ValueKey('settings-licenses'));
  await press(tester, LogicalKeyboardKey.select);
}

void main() {
  setUp(_reset);
  tearDown(_reset);

  test('the catalog groups licences by package, sorted', () async {
    _registerSamples();
    final catalog = await LicenseCatalog.load();
    expect(catalog.packages, ['alpha_pkg', 'Tajawal', 'zeta_pkg']);
    expect(catalog.entries['alpha_pkg'], hasLength(2));
    expect(catalog.entries['zeta_pkg'], hasLength(1));
    expect(catalog.entries['Tajawal'], hasLength(1));
  });

  for (final rtl in [false, true]) {
    final lang = rtl ? 'ar' : 'en';

    testWidgets('$lang TV: the licence text scrolls with the remote', (
      tester,
    ) async {
      _registerSamples();
      final h = await pumpSettingsApp(tester, locale: Locale(lang));
      await openSettingsTv(tester);
      await _openLicences(tester);
      expect(find.byType(TvLicensePage), findsOneWidget);
      expect(find.byType(LicensePage), findsNothing);

      // The first package has focus and its licences are shown.
      expect(
        focusedIn(_package('alpha_pkg')),
        isTrue,
        reason: focusDescription(),
      );
      expect(find.text('Alpha licence text.'), findsOneWidget);
      expect(find.text('Shared licence text.'), findsOneWidget);

      // The text follows the focused package.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(_package('Tajawal')), isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      expect(find.text('Alpha licence text.'), findsNothing);
      expect(find.text('Paragraph 1 of the font licence.'), findsOneWidget);

      // OK enters the text; Up and Down scroll it and keep focus.
      await press(tester, LogicalKeyboardKey.select);
      expect(focusedIn(_text), isTrue, reason: focusDescription());
      expect(_textOffset(tester), 0);
      for (var i = 0; i < 6; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      final scrolled = _textOffset(tester);
      expect(scrolled, greaterThan(300));
      expect(focusedIn(_text), isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(_textOffset(tester), lessThan(scrolled));
      expect(focusedIn(_text), isTrue);

      // Page Down reaches the end of the text.
      for (var i = 0; i < 30; i++) {
        await press(tester, LogicalKeyboardKey.pageDown);
      }
      expect(find.text(_fontEnd), findsOneWidget);
      expect(onScreen(tester, find.text(_fontEnd)), isTrue);
      expect(focusedIn(_text), isTrue);

      // The text stays left to right; the arrow toward the start goes back
      // to the package (mirrored in Arabic).
      expect(
        Directionality.of(tester.element(find.text(_fontEnd))),
        TextDirection.ltr,
      );
      final listX = tester.getCenter(find.byKey(_package('Tajawal'))).dx;
      final textX = tester.getCenter(find.byKey(_text)).dx;
      expect(rtl ? textX < listX : textX > listX, isTrue);
      await press(tester, toStart(rtl));
      expect(
        focusedIn(_package('Tajawal')),
        isTrue,
        reason: focusDescription(),
      );
      await press(tester, toEnd(rtl));
      expect(focusedIn(_text), isTrue);

      // Back in the text returns to the list; Back again closes the page.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(TvLicensePage), findsOneWidget);
      expect(focusedIn(_package('Tajawal')), isTrue);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(TvLicensePage), findsNothing);
      expect(focusedIn(const ValueKey('settings-licenses')), isTrue);
      await h.dispose(tester);
    });
  }

  testWidgets('TV: the arrow toward the end enters the text at once', (
    tester,
  ) async {
    _registerSamples();
    final h = await pumpSettingsApp(tester);
    await openSettingsTv(tester);
    await _openLicences(tester);
    // No pause after Down: the text catches up when it gets focus.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(tester);
    expect(focusedIn(_text), isTrue);
    expect(find.text('Paragraph 1 of the font licence.'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('TV: with no licences the page says so', (tester) async {
    final h = await pumpSettingsApp(tester);
    await openSettingsTv(tester);
    await _openLicences(tester);
    expect(find.byType(TvLicensePage), findsOneWidget);
    expect(find.text(en.commonEmpty), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(focusedIn(const ValueKey('settings-licenses')), isTrue);
    await h.dispose(tester);
  });

  testWidgets('phone: the licences open in the platform page', (tester) async {
    _registerSamples();
    final h = await pumpSettingsApp(tester, tv: false);
    await openSettingsPhone(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-licenses')),
      200,
      scrollable: find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('settings-licenses')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('settings-licenses')));
    await settle(tester);
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.byType(TvLicensePage), findsNothing);
    await tester.binding.handlePopRoute();
    await settle(tester);
    await h.dispose(tester);
  });

  testWidgets('a failed load shows Retry, which loads again', (tester) async {
    final log = RingLog();
    var loads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [ringLogProvider.overrideWithValue(log)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TvLicensePage(
            applicationName: 'IPTV Player',
            applicationVersion: '1.0.0',
            licenses: () => ++loads == 1
                ? Stream.error(StateError('broken registry'))
                : Stream.value(
                    const LicenseEntryWithLineBreaks(['pkg'], 'Pkg text.'),
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(en.commonErrorGeneric), findsOneWidget);
    expect(find.text('IPTV Player · 1.0.0'), findsOneWidget);
    expect(
      log.lines.any((l) => l.contains('Loading the licences failed')),
      isTrue,
    );
    await tester.tap(find.text(en.commonRetry));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.text('Pkg text.'), findsOneWidget);
    expect(find.text(en.commonErrorGeneric), findsNothing);
  });
}
