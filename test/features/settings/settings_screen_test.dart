import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/account/account_controller.dart';
import 'package:iptv_player/app/form_factor.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/platform/device_caps.dart';
import 'package:iptv_player/features/help/help_screen.dart';
import 'package:iptv_player/features/help/licenses_page.dart';
import 'package:iptv_player/features/settings/settings_dialogs.dart';
import 'package:iptv_player/features/settings/settings_screen.dart';
import 'package:iptv_player/player/engine/player_engine.dart';

import 'settings_harness.dart';

const _rowOrder = [
  'settings-sources',
  'settings-account',
  'settings-language',
  'settings-deviceMode',
  'settings-lite',
  'settings-liveEngine',
  'settings-vodEngine',
  'settings-exoView',
  'settings-hwdec',
  'settings-audioLang',
  'settings-subLang',
  'settings-aspect',
  'settings-epgAdd',
  'settings-epgOffset',
  'settings-epgRefresh',
  'settings-epgInterval',
  'settings-diagnostics',
  'settings-help',
  'settings-about',
  'settings-licenses',
];

Finder _row(String key) => find.byKey(ValueKey(key));

/// Text [text] inside the row [key].
Finder _inRow(String key, String text) =>
    find.descendant(of: _row(key), matching: find.text(text));

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await settle(tester);
}

void main() {
  for (final rtl in [false, true]) {
    final lang = rtl ? 'ar' : 'en';
    final l10n = rtl ? ar : en;
    final locale = Locale(lang);

    testWidgets('$lang TV: every row is reachable with the remote', (
      tester,
    ) async {
      final h = await pumpSettingsApp(tester, locale: locale);
      await openSettingsTv(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
      // The tab shows its own title next to the rail label.
      expect(find.text(l10n.navSettings), findsNWidgets(2));
      expect(focusedIn(const ValueKey('settings-sources')), isTrue);

      for (final key in _rowOrder.skip(1)) {
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(
          focusedIn(ValueKey(key)),
          isTrue,
          reason: '$key: ${focusDescription()}',
        );
        expect(onScreen(tester, _row(key)), isTrue, reason: '$key visible');
      }
      // The last row is a dead end downwards.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('settings-licenses')), isTrue);

      // Back up a few rows.
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedIn(const ValueKey('settings-help')), isTrue);

      // Toward the reading start leaves for the rail (mirrored in Arabic);
      // toward the end comes back to the same row.
      await press(tester, toEnd(rtl));
      expect(focusedIn(const ValueKey('settings-help')), isTrue);
      await press(tester, toStart(rtl));
      expect(focusedIn(settingsRail), isTrue);
      await press(tester, toEnd(rtl));
      expect(focusedIn(const ValueKey('settings-help')), isTrue);

      // Back from the page goes to the rail too.
      await _back(tester);
      expect(focusedIn(settingsRail), isTrue);
      await h.dispose(tester);
    });

    testWidgets('$lang TV: the account row asks to sign in again after the '
        'sign-in expired', (tester) async {
      for (final (account, value) in [
        (const AccountView(error: 'SESSION_EXPIRED'), l10n.accountSignInAgain),
        // A saved sign-in the secure storage could not read.
        (
          const AccountView(error: 'SESSION_STORAGE', linked: true),
          l10n.accountSignInAgain,
        ),
        (
          const AccountView(email: 'viewer@example.test', linked: true),
          'viewer@example.test',
        ),
      ]) {
        final h = await pumpSettingsApp(
          tester,
          locale: locale,
          overrides: [
            accountViewProvider.overrideWith((ref) => Stream.value(account)),
          ],
        );
        await openSettingsTv(tester);
        expect(_inRow('settings-account', value), findsOneWidget);
        await h.dispose(tester);
      }
    });

    testWidgets('$lang TV: the account row says when sync stopped, but not '
        'while the connection is down', (tester) async {
      for (final (error, stopped) in [
        ('PLAYLIST_FILE_TOO_LARGE', true),
        ('RECORD_TOO_LARGE', true),
        ('SYNC_ERROR', true),
        ('NETWORK_ERROR', false),
        (null, false),
      ]) {
        final h = await pumpSettingsApp(
          tester,
          locale: locale,
          overrides: [
            accountViewProvider.overrideWith(
              (ref) => Stream.value(
                AccountView(
                  email: 'viewer@example.test',
                  linked: true,
                  error: error,
                ),
              ),
            ),
          ],
        );
        await openSettingsTv(tester);
        expect(
          _inRow('settings-account', l10n.accountSyncStopped),
          stopped ? findsOneWidget : findsNothing,
          reason: error,
        );
        expect(
          _inRow('settings-account', 'viewer@example.test'),
          findsOneWidget,
        );
        await h.dispose(tester);
      }
    });

    testWidgets('$lang TV: Page Down and Page Up move focus a screen at a '
        'time and keep it on screen', (tester) async {
      final h = await pumpSettingsApp(tester, locale: locale);
      await openSettingsTv(tester);
      expect(focusedIn(const ValueKey('settings-sources')), isTrue);

      int focusedRow() => _rowOrder.indexWhere((k) => focusedIn(ValueKey(k)));
      await press(tester, LogicalKeyboardKey.pageDown);
      final down = focusedRow();
      expect(down, greaterThan(2), reason: focusDescription());
      expect(onScreen(tester, _row(_rowOrder[down])), isTrue);
      await press(tester, LogicalKeyboardKey.pageDown);
      final further = focusedRow();
      expect(further, greaterThan(down));
      expect(onScreen(tester, _row(_rowOrder[further])), isTrue);

      await press(tester, LogicalKeyboardKey.pageUp);
      final up = focusedRow();
      expect(up, inInclusiveRange(1, further - 3));
      expect(onScreen(tester, _row(_rowOrder[up])), isTrue);
      // Never past the top: the rail stays where it is.
      await press(tester, LogicalKeyboardKey.pageUp);
      await press(tester, LogicalKeyboardKey.pageUp);
      expect(focusedRow(), 0);
      expect(onScreen(tester, _row(_rowOrder.first)), isTrue);
      await h.dispose(tester);
    });

    testWidgets('$lang TV: values sit on the end side of their rows', (
      tester,
    ) async {
      final h = await pumpSettingsApp(tester, locale: locale);
      await openSettingsTv(tester);
      final title = _inRow('settings-liveEngine', l10n.settingsLiveEngine);
      final value = _inRow('settings-liveEngine', l10n.engineAuto);
      expect(title, findsOneWidget);
      expect(value, findsOneWidget);
      final titleX = tester.getCenter(title).dx;
      final valueX = tester.getCenter(value).dx;
      expect(rtl ? valueX < titleX : valueX > titleX, isTrue);
      // Directionality follows the language.
      expect(
        Directionality.of(tester.element(find.byType(SettingsScreen))),
        rtl ? TextDirection.rtl : TextDirection.ltr,
      );
      await h.dispose(tester);
    });

    testWidgets('$lang phone: a standard list driven by keys', (tester) async {
      final h = await pumpSettingsApp(tester, tv: false, locale: locale);
      await openSettingsPhone(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
      // Pushed page: the app bar has the title, the page has none.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(l10n.navSettings),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.navSettings), findsOneWidget);
      expect(
        find.descendant(
          of: _row('settings-language'),
          matching: find.byType(ListTile),
        ),
        findsOneWidget,
      );
      // The first row has focus; arrows walk the list.
      expect(focusedIn(const ValueKey('settings-sources')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('settings-account')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('settings-language')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('settings-deviceMode')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedIn(const ValueKey('settings-language')), isTrue);

      // OK opens the picker on the current value.
      await press(tester, LogicalKeyboardKey.select);
      final current = rtl ? AppLocaleSetting.ar : AppLocaleSetting.en;
      expect(focusedIn(choiceKey(current)), isTrue);
      await tester.tap(find.byKey(choiceKey(AppLocaleSetting.auto)));
      await settle(tester);
      expect(
        h.container(tester).read(settingsProvider).locale,
        AppLocaleSetting.auto,
      );
      expect((await h.savedSettings(tester))['locale'], 'auto');

      // Taps work too: the aspect ratio picker.
      await tester.scrollUntilVisible(
        _row('settings-aspect'),
        200,
        scrollable: find.descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(_row('settings-aspect'));
      await settle(tester);
      await tester.tap(_row('settings-aspect'));
      await settle(tester);
      await tester.tap(find.byKey(choiceKey(AspectMode.stretch)));
      await settle(tester);
      expect(
        h.container(tester).read(settingsProvider).defaultAspect,
        AspectMode.stretch,
      );
      expect((await h.savedSettings(tester))['defaultAspect'], 'stretch');
      await h.dispose(tester);
    });
  }

  testWidgets('TV: language applies at once and is saved', (tester) async {
    final h = await pumpSettingsApp(tester);
    await openSettingsTv(tester);
    await moveTo(tester, const ValueKey('settings-language'));
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byType(ChoiceDialog<AppLocaleSetting>), findsOneWidget);
    // The dialog opens on the current value.
    expect(focusedIn(choiceKey(AppLocaleSetting.en)), isTrue);
    await moveTo(
      tester,
      choiceKey(AppLocaleSetting.ar),
      arrow: LogicalKeyboardKey.arrowUp,
    );
    await press(tester, LogicalKeyboardKey.select);

    expect(find.byType(ChoiceDialog<AppLocaleSetting>), findsNothing);
    expect(
      h.container(tester).read(settingsProvider).locale,
      AppLocaleSetting.ar,
    );
    expect((await h.savedSettings(tester))['locale'], 'ar');
    // The whole app is Arabic now, and focus stayed on the row.
    expect(find.text(ar.settingsLanguage), findsOneWidget);
    expect(find.text(ar.navLive), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(SettingsScreen))),
      TextDirection.rtl,
    );
    expect(focusedIn(const ValueKey('settings-language')), isTrue);
    await h.dispose(tester);
  });

  testWidgets('TV: every picker opens on the current value and persists', (
    tester,
  ) async {
    final h = await pumpSettingsApp(tester);
    await openSettingsTv(tester);
    final container = h.container(tester);
    AppSettings now() => container.read(settingsProvider);

    Future<void> pick(String row, Object current, Object target) async {
      await moveTo(tester, ValueKey(row));
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(AlertDialog), findsOneWidget, reason: row);
      expect(focusedIn(choiceKey(current)), isTrue, reason: '$row current');
      for (final arrow in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
      ]) {
        for (var i = 0; i < 8 && !focusedIn(choiceKey(target)); i++) {
          await press(tester, arrow);
        }
      }
      expect(focusedIn(choiceKey(target)), isTrue, reason: '$row -> $target');
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(AlertDialog), findsNothing, reason: row);
      // Focus returns to the row that opened the dialog.
      expect(focusedIn(ValueKey(row)), isTrue, reason: '$row refocused');
    }

    await pick(
      'settings-deviceMode',
      FormFactorOverride.auto,
      FormFactorOverride.tv,
    );
    expect(now().formFactor, FormFactorOverride.tv);
    await pick('settings-lite', LiteSetting.auto, LiteSetting.on);
    expect(now().lite, LiteSetting.on);
    await pick('settings-liveEngine', EngineSetting.auto, EngineSetting.mpv);
    expect(now().liveEngine, EngineSetting.mpv);
    await pick('settings-vodEngine', EngineSetting.auto, EngineSetting.exo);
    expect(now().vodEngine, EngineSetting.exo);
    await pick('settings-exoView', ExoViewType.texture, ExoViewType.platform);
    expect(now().exoView, ExoViewType.platform);
    await pick('settings-audioLang', 'ar', 'en');
    expect(now().preferredAudioLang, 'en');
    await pick('settings-subLang', 'ar', 'fr');
    expect(now().preferredSubLang, 'fr');
    await pick('settings-aspect', AspectMode.fit, AspectMode.ratio16x9);
    expect(now().defaultAspect, AspectMode.ratio16x9);
    await pick('settings-epgInterval', 12, 24);
    expect(now().epgRefreshHours, 24);

    // Hardware decoding toggles with OK, no dialog.
    await moveTo(
      tester,
      const ValueKey('settings-hwdec'),
      arrow: LogicalKeyboardKey.arrowUp,
    );
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byType(AlertDialog), findsNothing);
    expect(now().hwdec, isFalse);
    expect(_inRow('settings-hwdec', en.commonOff), findsOneWidget);
    expect(focusedIn(const ValueKey('settings-hwdec')), isTrue);

    // The rows show the new values.
    expect(_inRow('settings-lite', en.commonOn), findsOneWidget);
    expect(_inRow('settings-liveEngine', en.engineMpv), findsOneWidget);
    expect(_inRow('settings-aspect', en.aspect16x9), findsOneWidget);
    expect(_inRow('settings-subLang', en.settings_langFrench), findsOneWidget);
    expect(
      _inRow('settings-epgInterval', en.settings_everyHours(24)),
      findsOneWidget,
    );

    final saved = await h.savedSettings(tester);
    expect(saved, containsPair('formFactor', 'tv'));
    expect(saved, containsPair('lite', 'on'));
    expect(saved, containsPair('liveEngine', 'mpv'));
    expect(saved, containsPair('vodEngine', 'exo'));
    expect(saved, containsPair('exoView', 'platform'));
    expect(saved, containsPair('hwdec', false));
    expect(saved, containsPair('preferredAudioLang', 'en'));
    expect(saved, containsPair('preferredSubLang', 'fr'));
    expect(saved, containsPair('defaultAspect', 'ratio16x9'));
    expect(saved, containsPair('epgRefreshHours', 24));
    // The changes reach the player options.
    final options = container.read(engineOptionsProvider);
    expect(options.hardwareDecoding, isFalse);
    expect(options.lite, isTrue);
    await h.dispose(tester);
  });

  testWidgets('TV: Back in a picker keeps the old value', (tester) async {
    final h = await pumpSettingsApp(tester);
    await openSettingsTv(tester);
    await moveTo(tester, const ValueKey('settings-aspect'));
    await press(tester, LogicalKeyboardKey.select);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await _back(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      h.container(tester).read(settingsProvider).defaultAspect,
      AspectMode.fit,
    );
    expect(focusedIn(const ValueKey('settings-aspect')), isTrue);
    await h.dispose(tester);
  });

  testWidgets('Android offers ExoPlayer; desktop only mpv', (tester) async {
    var h = await pumpSettingsApp(tester);
    await openSettingsTv(tester);
    expect(_row('settings-exoView'), findsOneWidget);
    await moveTo(tester, const ValueKey('settings-liveEngine'));
    await press(tester, LogicalKeyboardKey.select);
    for (final v in EngineSetting.values) {
      expect(find.byKey(choiceKey(v)), findsOneWidget, reason: v.name);
    }
    await _back(tester);
    await h.dispose(tester);

    h = await pumpSettingsApp(
      tester,
      platform: TargetPlatform.windows,
      caps: const DeviceCaps.desktop(),
    );
    await openSettingsTv(tester);
    expect(_row('settings-exoView'), findsNothing);
    for (final row in ['settings-liveEngine', 'settings-vodEngine']) {
      await moveTo(tester, ValueKey(row));
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byKey(choiceKey(EngineSetting.auto)), findsOneWidget);
      expect(find.byKey(choiceKey(EngineSetting.mpv)), findsOneWidget);
      expect(find.byKey(choiceKey(EngineSetting.exo)), findsNothing);
      expect(find.text(en.engineExo), findsNothing);
      await _back(tester);
    }
    await h.dispose(tester);
  });

  testWidgets('desktop offers no Phone device mode unless it is saved', (
    tester,
  ) async {
    Future<void> openDeviceMode() async {
      await openSettingsTv(tester);
      await moveTo(tester, const ValueKey('settings-deviceMode'));
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(ChoiceDialog<FormFactorOverride>), findsOneWidget);
    }

    var h = await pumpSettingsApp(
      tester,
      platform: TargetPlatform.windows,
      caps: const DeviceCaps.desktop(),
    );
    await openDeviceMode();
    expect(find.byKey(choiceKey(FormFactorOverride.auto)), findsOneWidget);
    expect(find.byKey(choiceKey(FormFactorOverride.tv)), findsOneWidget);
    expect(find.byKey(choiceKey(FormFactorOverride.phone)), findsNothing);
    await _back(tester);
    await h.dispose(tester);

    // A Phone saved earlier is still shown as the current value.
    h = await pumpSettingsApp(
      tester,
      platform: TargetPlatform.windows,
      caps: const DeviceCaps.desktop(),
      settings: const AppSettings(formFactor: FormFactorOverride.phone),
    );
    await openDeviceMode();
    expect(_inRow('settings-deviceMode', en.deviceModePhone), findsOneWidget);
    expect(find.byKey(choiceKey(FormFactorOverride.phone)), findsOneWidget);
    expect(focusedIn(choiceKey(FormFactorOverride.phone)), isTrue);
    await moveTo(
      tester,
      choiceKey(FormFactorOverride.auto),
      arrow: LogicalKeyboardKey.arrowUp,
    );
    await press(tester, LogicalKeyboardKey.select);
    expect(
      h.container(tester).read(settingsProvider).formFactor,
      FormFactorOverride.auto,
    );
    await h.dispose(tester);

    // Android keeps all three.
    h = await pumpSettingsApp(tester);
    await openDeviceMode();
    for (final v in FormFactorOverride.values) {
      expect(find.byKey(choiceKey(v)), findsOneWidget, reason: v.name);
    }
    await _back(tester);
    await h.dispose(tester);
  });

  testWidgets('Lite mode Auto shows the value detected on the device', (
    tester,
  ) async {
    var h = await pumpSettingsApp(
      tester,
      caps: const DeviceCaps(uiModeTv: true, touch: false, totalRamMb: 1536),
    );
    await openSettingsTv(tester);
    expect(
      _inRow('settings-lite', en.settings_liteAuto(en.commonOn)),
      findsOneWidget,
    );
    await h.dispose(tester);

    h = await pumpSettingsApp(
      tester,
      caps: const DeviceCaps(uiModeTv: true, touch: false, totalRamMb: 4096),
    );
    await openSettingsTv(tester);
    expect(
      _inRow('settings-lite', en.settings_liteAuto(en.commonOff)),
      findsOneWidget,
    );
    expect(h.container(tester).read(liteModeProvider), isFalse);
    // Forcing it on wins over the device.
    await moveTo(tester, const ValueKey('settings-lite'));
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text(en.settings_liteAuto(en.commonOff)), findsNWidgets(2));
    await moveTo(tester, choiceKey(LiteSetting.on));
    await press(tester, LogicalKeyboardKey.select);
    expect(h.container(tester).read(liteModeProvider), isTrue);
    await h.dispose(tester);
  });

  testWidgets('TV: Sources, Help and Diagnostics open as pages', (
    tester,
  ) async {
    final h = await pumpSettingsApp(tester);
    await openSettingsTv(tester);
    // The active source is the Sources row's value.
    expect(_inRow('settings-sources', 'Home'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.select);
    expect(find.text(stubPageText(HomeTab.sources)), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(en.navSources),
      ),
      findsOneWidget,
    );
    await _back(tester);
    expect(find.text(stubPageText(HomeTab.sources)), findsNothing);
    expect(focusedIn(const ValueKey('settings-sources')), isTrue);

    await moveTo(tester, const ValueKey('settings-diagnostics'));
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text(stubPageText(HomeTab.diagnostics)), findsOneWidget);
    await _back(tester);
    expect(focusedIn(const ValueKey('settings-diagnostics')), isTrue);

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedIn(const ValueKey('settings-help')), isTrue);
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byType(HelpScreen), findsOneWidget);
    // The pushed Help page starts on its first section.
    expect(
      focusedIn(const ValueKey('help-intro')),
      isTrue,
      reason: focusDescription(),
    );
    await _back(tester);
    expect(find.byType(HelpScreen), findsNothing);
    expect(focusedIn(const ValueKey('settings-help')), isTrue);
    await h.dispose(tester);
  });

  testWidgets('About shows the version; OK opens the licences', (tester) async {
    final h = await pumpSettingsApp(tester);
    await openSettingsTv(tester);
    expect(
      _inRow('settings-about', en.settingsVersion('1.2.3 (45)')),
      findsOneWidget,
    );
    await moveTo(tester, const ValueKey('settings-licenses'));
    await press(tester, LogicalKeyboardKey.select);
    // On TV the licences open in a page a remote can scroll.
    expect(find.byType(TvLicensePage), findsOneWidget);
    await _back(tester);
    expect(find.byType(TvLicensePage), findsNothing);
    expect(focusedIn(const ValueKey('settings-licenses')), isTrue);
    await h.dispose(tester);
  });

  testWidgets('no version: About shows no value', (tester) async {
    final h = await pumpSettingsApp(tester, version: null);
    await openSettingsTv(tester);
    expect(_row('settings-about'), findsOneWidget);
    expect(find.textContaining('1.2.3'), findsNothing);
    await h.dispose(tester);
  });
}
