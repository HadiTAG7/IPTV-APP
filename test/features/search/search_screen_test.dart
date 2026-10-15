import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/features/favorites/vod_navigation.dart';
import 'package:iptv_player/features/search/search_screen.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/sources/models.dart';

import '../live/support/live_test_utils.dart';

/// Channels, movies and series with "News" in their names, plus Arabic
/// names that differ only in hamza and taa marbuta spelling.
Future<int> seedSearchCatalog(AppDatabase db) async {
  final id = await addTestSource(db, lastSyncAt: DateTime.now());
  await seedCatalog(
    db,
    id,
    categories: [liveCategory('all', 'All', 0)],
    channels: [
      testChannel(1, name: 'News One', categories: ['all']),
      testChannel(2, name: 'News Two', categories: ['all']),
      testChannel(3, name: 'Sports', categories: ['all']),
      testChannel(4, name: 'قناة الأخبار', categories: ['all']),
    ],
    movies: [
      const MovieData(key: 'm1', name: 'News Movie', categoryKeys: ['films']),
      const MovieData(key: 'm2', name: 'Comedy', categoryKeys: ['films']),
    ],
    series: [
      const SeriesData(key: 's1', name: 'News Series', categoryKeys: ['tv']),
      const SeriesData(key: 's2', name: 'مسلسل الإختبار', categoryKeys: ['tv']),
    ],
  );
  return id;
}

/// Records what Favorites and Search ask to open.
class VodRecorder {
  final targets = <VodTarget>[];

  Future<void> open(BuildContext context, _, VodTarget target) async =>
      targets.add(target);
}

/// Whether the search field has focus.
bool fieldHasFocus() =>
    FocusManager.instance.primaryFocus?.debugLabel == 'search-field';

SearchViewState searchState(WidgetTester tester) =>
    tester.state<SearchViewState>(find.byType(SearchView));

/// From the rail's Live item down to [tab] and into its page.
Future<void> openTab(
  WidgetTester tester,
  HomeTab tab, {
  bool rtl = false,
}) async {
  final steps = HomeTab.tvTabs.indexOf(tab);
  for (var i = 0; i < steps; i++) {
    await press(tester, LogicalKeyboardKey.arrowDown);
  }
  expect(focusedIn(ValueKey('rail-${tab.name}')), isTrue);
  await press(tester, toEnd(rtl));
}

void main() {
  for (final rtl in [false, true]) {
    final locale = Locale(rtl ? 'ar' : 'en');
    final l10n = lookupAppLocalizations(locale);

    testWidgets('${locale.languageCode}: TV search debounces, groups and '
        'moves from the field into the results', (tester) async {
      final db = openAppTestDb();
      await seedSearchCatalog(db);
      final player = FakePlayer();
      final vod = VodRecorder();
      await pumpLiveApp(
        tester,
        db,
        locale: locale,
        overrides: [
          player.override,
          vodDetailNavigatorProvider.overrideWithValue(vod.open),
        ],
      );
      await openTab(tester, HomeTab.search, rtl: rtl);
      final field = find.byKey(const ValueKey('search-field'));
      expect(fieldHasFocus(), isTrue);
      expect(find.text(l10n.commonSearchHint), findsWidgets);

      // Typing restarts the 300 ms wait; one query runs after the pause.
      await tester.enterText(
        find.descendant(of: field, matching: find.byType(TextField)),
        'Ne',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(
        find.descendant(of: field, matching: find.byType(TextField)),
        'News',
      );
      await tester.pump(const Duration(milliseconds: 299));
      expect(searchState(tester).searches, 0);
      await tester.pump(const Duration(milliseconds: 2));
      await settle(tester);
      expect(searchState(tester).searches, 1);

      // Grouped results.
      final results = searchState(tester).results;
      expect([for (final c in results.channels) c.key], ['k1', 'k2']);
      expect([for (final m in results.movies) m.key], ['m1']);
      expect([for (final s in results.series) s.key], ['s1']);
      Finder inResults(Finder f) =>
          find.descendant(of: find.byType(SearchView), matching: f);
      expect(inResults(find.text(l10n.searchChannels)), findsOneWidget);
      expect(inResults(find.text(l10n.searchMovies)), findsOneWidget);
      expect(find.text('News One'), findsOneWidget);
      expect(find.text('News Two'), findsOneWidget);
      expect(find.text('Sports'), findsNothing);

      // Down leaves the field for the first result; up comes back.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('News One');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('News Two');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(
        focusedIn(const ValueKey('search-movie-m1')),
        isTrue,
        reason: 'the movie row is below the channels',
      );
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('search-series-s1')), isTrue);
      expect(inResults(find.text(l10n.searchSeries)), findsOneWidget);
      await press(tester, LogicalKeyboardKey.select);
      expect(vod.targets.single.kind, ContentKind.series);
      expect(vod.targets.single.key, 's1');
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.select);
      expect(vod.targets.last.kind, ContentKind.movie);
      expect(vod.targets.last.movie?.name, 'News Movie');
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expectFocusOn('News One');

      // Channels play, zapping within the results.
      await press(tester, LogicalKeyboardKey.select);
      expect(player.requests.single.item.key, 'k1');
      expect(player.requests.single.zapKeys, ['k1', 'k2']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expectFocusOn('News One');

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(fieldHasFocus(), isTrue);

      // Back from the results returns to the field, then to the rail.
      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(fieldHasFocus(), isTrue);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(focusedIn(const ValueKey('rail-search')), isTrue);

      // No match.
      await tester.enterText(
        find.descendant(of: field, matching: find.byType(TextField)),
        'zzz',
      );
      await wait(tester, SearchView.debounce);
      expect(find.text(l10n.searchNoResults('zzz')), findsOneWidget);
      await disposeApp(tester, db);
    });
  }

  testWidgets('phone: Arabic folding finds hamza and taa marbuta '
      'variants', (tester) async {
    final db = openAppTestDb();
    await seedSearchCatalog(db);
    await pumpLiveApp(tester, db, tv: false, locale: const Locale('ar'));
    await tester.tap(find.byKey(const ValueKey('nav-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('more-search')));
    await tester.pumpAndSettle();
    // A pushed page focuses its field itself.
    expect(fieldHasFocus(), isTrue);

    final text = find.byType(TextField);
    await tester.enterText(text, 'الاخبار');
    await wait(tester, SearchView.debounce);
    expect(find.text('قناة الأخبار'), findsOneWidget);
    expect(searchState(tester).results.channels.single.key, 'k4');

    await tester.enterText(text, 'قناه');
    await wait(tester, SearchView.debounce);
    expect(find.text('قناة الأخبار'), findsOneWidget);

    await tester.enterText(text, 'اختبار');
    await wait(tester, SearchView.debounce);
    expect(searchState(tester).results.series.single.key, 's2');
    expect(searchState(tester).results.channels, isEmpty);
    await disposeApp(tester, db);
  });
}
