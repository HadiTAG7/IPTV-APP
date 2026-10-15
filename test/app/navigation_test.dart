// Every destination is reachable with the real pages: Sources, Diagnostics
// and Help from Settings (TV and phone), and Search, Favorites, Sources,
// Settings and Help from the phone's More page. Back returns where the
// user came from.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/app/shell_phone.dart';
import 'package:iptv_player/app/shell_tv.dart';
import 'package:iptv_player/features/diagnostics/diagnostics_screen.dart';
import 'package:iptv_player/features/favorites/favorites_screen.dart';
import 'package:iptv_player/features/help/help_screen.dart';
import 'package:iptv_player/features/search/search_screen.dart';
import 'package:iptv_player/features/settings/settings_screen.dart';
import 'package:iptv_player/features/sources/sources_screen.dart';

import '../features/sources/support.dart';

/// The type of the page pushed on top of the home route, if any.
Type? _topPage(WidgetTester tester) {
  for (final type in [
    SourcesScreen,
    DiagnosticsScreen,
    HelpScreen,
    SearchScreen,
    FavoritesScreen,
    SettingsScreen,
  ]) {
    final found = find.byType(type);
    if (found.evaluate().isEmpty) continue;
    for (final element in found.evaluate()) {
      final route = ModalRoute.of(element);
      // A pushed page (the home route holds the tabs).
      if (route != null && route.isCurrent && !route.isFirst) return type;
    }
  }
  return null;
}

void main() {
  for (final rtl in [false, true]) {
    final lang = rtl ? 'ar' : 'en';
    testWidgets('TV $lang: Sources, Diagnostics and Help open from Settings; '
        'Back returns to the row', (tester) async {
      final db = openAppTestDb();
      await addTestSource(db, lastSyncAt: DateTime.now());
      await pumpApp(
        tester,
        db: db,
        caps: tvCaps,
        settings: AppSettings(
          locale: rtl ? AppLocaleSetting.ar : AppLocaleSetting.en,
        ),
      );
      expectFocus('rail-live');
      for (var i = 0; i < HomeTab.tvTabs.indexOf(HomeTab.settings); i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expectFocus('rail-settings');
      expect(
        tester.state<TvShellState>(find.byType(TvShell)).current,
        HomeTab.settings,
      );
      await press(
        tester,
        rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight,
      );
      expectFocus('settings-sources');

      for (final (row, page) in [
        ('settings-sources', SourcesScreen),
        ('settings-diagnostics', DiagnosticsScreen),
        ('settings-help', HelpScreen),
      ]) {
        for (var i = 0; i < 40 && !focusedIn(ValueKey(row)); i++) {
          await press(tester, LogicalKeyboardKey.arrowDown);
        }
        expectFocus(row);
        await press(tester, LogicalKeyboardKey.select);
        await settleRoute(tester);
        expect(_topPage(tester), page, reason: row);
        await back(tester);
        expect(_topPage(tester), isNull, reason: 'back from $row');
        expectFocus(row);
      }

      // Back from the page goes to the rail, not out of the app.
      await back(tester);
      expectFocus('rail-settings');
      await drainNetworkTimers(tester);
      await disposeApp(tester, db);
    });
  }

  testWidgets('phone: More and Settings reach every page; Back returns', (
    tester,
  ) async {
    final db = openAppTestDb();
    await addTestSource(db, lastSyncAt: DateTime.now());
    await pumpApp(tester, db: db);
    await tester.tap(find.byKey(const ValueKey('nav-more')));
    await settle(tester);
    expect(find.byType(MorePage), findsOneWidget);

    for (final (item, page) in [
      ('more-search', SearchScreen),
      ('more-favorites', FavoritesScreen),
      ('more-sources', SourcesScreen),
      ('more-help', HelpScreen),
    ]) {
      await tapKey(tester, item);
      await settleRoute(tester);
      expect(_topPage(tester), page, reason: item);
      await back(tester);
      expect(_topPage(tester), isNull, reason: 'back from $item');
      expect(find.byType(MorePage), findsOneWidget);
    }

    await tapKey(tester, 'more-settings');
    await settleRoute(tester);
    expect(_topPage(tester), SettingsScreen);
    for (final (row, page) in [
      ('settings-sources', SourcesScreen),
      ('settings-diagnostics', DiagnosticsScreen),
      ('settings-help', HelpScreen),
    ]) {
      // The list builds its rows lazily.
      await tester.scrollUntilVisible(
        find.byKey(ValueKey(row)),
        200,
        scrollable: find
            .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tapKey(tester, row);
      await settleRoute(tester);
      expect(_topPage(tester), page, reason: row);
      await back(tester);
      expect(_topPage(tester), SettingsScreen, reason: 'back from $row');
    }
    await back(tester);
    expect(_topPage(tester), isNull);
    expect(
      tester.state<PhoneShellState>(find.byType(PhoneShell)).current,
      HomeTab.more,
    );
    await drainNetworkTimers(tester);
    await disposeApp(tester, db);
  });
}
