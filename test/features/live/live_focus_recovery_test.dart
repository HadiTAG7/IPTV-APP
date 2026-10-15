// Focus must survive lists that empty or vanish under the remote: the info
// pane never becomes a dead end, and a category removed by a sync falls
// back to All channels (not to the often empty Favorites).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/features/live/live_models.dart';
import 'package:iptv_player/features/live/live_screen.dart';
import 'package:iptv_player/features/live/providers.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/sources/models.dart';

import 'support/live_test_utils.dart';

LiveViewState liveState(WidgetTester tester) =>
    tester.state<LiveViewState>(find.byType(LiveView));

/// The next catalog: Kids is gone; its channels stay, listed under News.
Future<void> syncWithoutKids(AppDatabase db, int id) => seedCatalog(
  db,
  id,
  categories: [
    liveCategory('news', 'News', 0),
    liveCategory('sports', 'Sports', 1),
  ],
  channels: [
    for (var n = 1; n <= 30; n++)
      testChannel(n, categories: [n > 10 && n <= 20 ? 'sports' : 'news']),
  ],
);

void main() {
  for (final rtl in [false, true]) {
    final locale = Locale(rtl ? 'ar' : 'en');
    final l10n = lookupAppLocalizations(locale);

    testWidgets('${locale.languageCode}: removing the last favourite from '
        'the info pane moves focus to the categories', (tester) async {
      final db = openAppTestDb();
      final id = await seedThreeCategories(db);
      await db.favoritesDao.setFavorite(id, ContentKind.live, 'k2', true);
      await db.settingsDao.setString(liveLastListKey(id), 'fav');
      await pumpLiveApp(tester, db, locale: locale);
      expect(liveState(tester).selected, const LiveList.favorites());

      await press(tester, toEnd(rtl));
      expectFocusOn('Channel 2');
      await press(tester, toEnd(rtl));
      expectFocusOn(l10n.vodPlay);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn(l10n.liveRemoveFavorite);
      await press(tester, LogicalKeyboardKey.select);
      await settle(tester);
      expect(await db.favoritesDao.favoriteKeys(id, ContentKind.live), isEmpty);

      // The list is empty: focus is on its category, the info pane is gone.
      expect(find.text(l10n.favoritesEmpty), findsOneWidget);
      expect(focusedIn(const ValueKey('live-category-fav')), isTrue);
      expect(find.byKey(const ValueKey('live-info-k2')), findsNothing);
      expect(liveState(tester).selected, const LiveList.favorites());

      // And the rail is one step away.
      await press(tester, toStart(rtl));
      expect(focusedIn(const ValueKey('rail-live')), isTrue);
      await disposeApp(tester, db);
    });
  }

  testWidgets('a favourite removed elsewhere while the info pane has focus '
      'moves focus to the categories', (tester) async {
    final db = openAppTestDb();
    final id = await seedThreeCategories(db);
    await db.favoritesDao.setFavorite(id, ContentKind.live, 'k2', true);
    await db.settingsDao.setString(liveLastListKey(id), 'fav');
    final en = lookupAppLocalizations(const Locale('en'));
    await pumpLiveApp(tester, db);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expectFocusOn(en.vodPlay);

    // The favourite goes away elsewhere (the player, another screen) while
    // the info pane keeps focus.
    await db.favoritesDao.setFavorite(id, ContentKind.live, 'k2', false);
    await settle(tester);
    await settle(tester);
    expect(focusedIn(const ValueKey('live-category-fav')), isTrue);
    expect(find.byKey(const ValueKey('live-info-k2')), findsNothing);

    // Back from the categories goes on to the rail.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(focusedIn(const ValueKey('rail-live')), isTrue);
    await disposeApp(tester, db);
  });

  group('a sync removes the selected category', () {
    testWidgets('with focus in the channels: All channels opens on the same '
        'channel and is saved', (tester) async {
      final db = openAppTestDb();
      final id = await seedThreeCategories(db);
      await db.settingsDao.setString(liveLastListKey(id), 'cat:kids');
      await pumpLiveApp(tester, db);
      expect(liveState(tester).selected, const LiveList.category('kids'));
      await press(tester, LogicalKeyboardKey.arrowRight);
      expectFocusOn('Channel 21');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Channel 22');

      await syncWithoutKids(db, id);
      await settle(tester);
      await wait(tester, LiveView.selectDelay * 2);
      expect(find.text('Kids'), findsNothing);
      expect(liveState(tester).selected, const LiveList.all());
      expectFocusOn('Channel 22');
      expect(await db.settingsDao.getString(liveLastListKey(id)), 'all');
      await disposeApp(tester, db);
    });

    for (final rtl in [false, true]) {
      final locale = Locale(rtl ? 'ar' : 'en');
      final l10n = lookupAppLocalizations(locale);

      testWidgets('${locale.languageCode}: with focus in the info pane: focus '
          'follows into All channels on the same channel', (tester) async {
        final db = openAppTestDb();
        final id = await seedThreeCategories(db);
        await db.settingsDao.setString(liveLastListKey(id), 'cat:kids');
        await pumpLiveApp(tester, db, locale: locale);
        await press(tester, toEnd(rtl));
        await press(tester, LogicalKeyboardKey.arrowDown);
        expectFocusOn('Channel 22');
        await press(tester, toEnd(rtl));
        expectFocusOn(l10n.vodPlay);

        await syncWithoutKids(db, id);
        await settle(tester);
        await wait(tester, LiveView.selectDelay * 2);
        expect(liveState(tester).selected, const LiveList.all());
        expectFocusOn('Channel 22');
        expect(await db.settingsDao.getString(liveLastListKey(id)), 'all');

        // Nothing is stranded: Left reaches the categories, then the rail.
        await press(tester, toStart(rtl));
        expect(focusedIn(const ValueKey('live-category-all')), isTrue);
        await press(tester, toStart(rtl));
        expect(focusedIn(const ValueKey('rail-live')), isTrue);
        await disposeApp(tester, db);
      });
    }

    testWidgets('a sync that empties the category while the info pane has '
        'focus moves focus into All channels', (tester) async {
      final db = openAppTestDb();
      final id = await seedThreeCategories(db);
      final en = lookupAppLocalizations(const Locale('en'));
      await db.settingsDao.setString(liveLastListKey(id), 'cat:kids');
      await pumpLiveApp(tester, db);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expectFocusOn('Channel 21');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expectFocusOn(en.vodPlay);

      // Kids stays listed, without channels.
      await seedCatalog(
        db,
        id,
        categories: [
          liveCategory('news', 'News', 0),
          liveCategory('sports', 'Sports', 1),
          liveCategory('kids', 'Kids', 2),
        ],
        channels: [
          for (var n = 1; n <= 30; n++)
            testChannel(n, categories: [n > 10 && n <= 20 ? 'sports' : 'news']),
        ],
      );
      await settle(tester);
      await wait(tester, LiveView.selectDelay * 2);
      expect(find.text('Kids'), findsOneWidget);
      expect(liveState(tester).selected, const LiveList.all());
      expectFocusOn('Channel 21');
      expect(await db.settingsDao.getString(liveLastListKey(id)), 'all');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusedIn(const ValueKey('live-category-all')), isTrue);
      await disposeApp(tester, db);
    });

    testWidgets('with focus on its category: All channels gets focus and '
        'stays selected', (tester) async {
      final db = openAppTestDb();
      final id = await seedThreeCategories(db);
      final en = lookupAppLocalizations(const Locale('en'));
      await db.settingsDao.setString(liveLastListKey(id), 'cat:kids');
      await pumpLiveApp(tester, db);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expectFocusOn('Kids');

      await syncWithoutKids(db, id);
      await settle(tester);
      await wait(tester, LiveView.selectDelay * 2);
      expect(focusedIn(const ValueKey('live-category-all')), isTrue);
      expectFocusOn(en.liveAllChannels);
      expect(liveState(tester).selected, const LiveList.all());
      expect(await db.settingsDao.getString(liveLastListKey(id)), 'all');
      await disposeApp(tester, db);
    });

    testWidgets('with focus on the rail: All channels is shown and focus '
        'stays put', (tester) async {
      final db = openAppTestDb();
      final id = await seedThreeCategories(db);
      await db.settingsDao.setString(liveLastListKey(id), 'cat:kids');
      await pumpLiveApp(tester, db);
      expect(focusedIn(const ValueKey('rail-live')), isTrue);

      await syncWithoutKids(db, id);
      await settle(tester);
      await wait(tester, LiveView.selectDelay * 2);
      expect(liveState(tester).selected, const LiveList.all());
      expect(focusedIn(const ValueKey('rail-live')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expectFocusOn('Channel 1');
      await disposeApp(tester, db);
    });
  });
}
