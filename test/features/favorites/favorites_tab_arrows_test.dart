// After "New list…" creates a list (or a list is deleted from its tab
// options), the first arrow back toward the start moves to the neighbouring
// tab, not along stale traversal history.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/features/favorites/favorites_screen.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/sources/models.dart';

import '../../support/text_entry.dart';
import '../live/support/live_test_utils.dart';

FavoritesViewState favoritesState(WidgetTester tester) =>
    tester.state<FavoritesViewState>(find.byType(FavoritesView));

ValueKey<String> listTab(int listId) => ValueKey('favorites-tab-list-$listId');

const nameField = ValueKey('channel-list-name-field');

Future<void> openFavoritesTab(WidgetTester tester, bool rtl) async {
  final steps = HomeTab.tvTabs.indexOf(HomeTab.favorites);
  for (var i = 0; i < steps; i++) {
    await press(tester, LogicalKeyboardKey.arrowDown);
  }
  expect(focusedIn(const ValueKey('rail-favorites')), isTrue);
  await press(tester, toEnd(rtl));
}

Future<int> seedSource(AppDatabase db) async {
  final id = await addTestSource(db, lastSyncAt: DateTime.now());
  await seedCatalog(
    db,
    id,
    categories: [liveCategory('news', 'News', 0)],
    channels: [for (var n = 1; n <= 10; n++) testChannel(n)],
  );
  await db.favoritesDao.setFavorite(id, ContentKind.live, 'k2', true);
  return id;
}

void main() {
  for (final rtl in [false, true]) {
    final locale = Locale(rtl ? 'ar' : 'en');
    final l10n = lookupAppLocalizations(locale);
    final sports = rtl ? 'الرياضة' : 'Sports';

    testWidgets('${locale.languageCode}: after creating a list, the arrow '
        'toward the start goes to Live', (tester) async {
      final db = openAppTestDb();
      final source = await seedSource(db);
      await pumpLiveApp(
        tester,
        db,
        locale: locale,
        overrides: [
          targetPlatformProvider.overrideWithValue(TargetPlatform.linux),
        ],
      );
      await openFavoritesTab(tester, rtl);
      expect(focusedIn(const ValueKey('favorites-tab-live')), isTrue);
      await press(tester, toEnd(rtl));
      await press(tester, toEnd(rtl));
      await press(tester, toEnd(rtl));
      expect(focusedIn(const ValueKey('favorites-tab-new-list')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      await typeText(tester, find.byKey(nameField), sports);
      await settle(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      final created = (await db.channelListsDao.lists(source)).single;
      await settle(tester);
      expect(focusedIn(listTab(created.id)), isTrue);

      // The new tab sits right after Live: toward the start is Live.
      await press(tester, toStart(rtl));
      expect(
        focusedIn(const ValueKey('favorites-tab-live')),
        isTrue,
        reason:
            'series focused: ${focusedIn(const ValueKey('favorites-tab-series'))}, '
            'segment: ${favoritesState(tester).segment}, '
            'list: ${favoritesState(tester).listId}',
      );
      await disposeApp(tester, db);
    });

    testWidgets('${locale.languageCode}: after deleting the last list tab '
        'from its options, the arrow toward the start moves', (tester) async {
      final db = openAppTestDb();
      final source = await seedSource(db);
      final dao = db.channelListsDao;
      final a = await dao.createList(source, 'Alpha', channels: ['k1']);
      final b = await dao.createList(source, 'Beta', channels: ['k3']);
      final c = await dao.createList(source, 'Gamma', channels: ['k4']);
      await pumpLiveApp(
        tester,
        db,
        locale: locale,
        overrides: [
          targetPlatformProvider.overrideWithValue(TargetPlatform.linux),
        ],
      );
      await openFavoritesTab(tester, rtl);
      expect(focusedIn(const ValueKey('favorites-tab-live')), isTrue);
      await press(tester, toEnd(rtl));
      await press(tester, toEnd(rtl));
      await press(tester, toEnd(rtl));
      expect(focusedIn(listTab(c)), isTrue);
      await press(tester, LogicalKeyboardKey.contextMenu);
      expectFocusOn(l10n.liveRenameList);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn(l10n.liveDeleteList);
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, toEnd(rtl));
      expect(focusedIn(const ValueKey('delete-list-confirm')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(await dao.listById(c), isNull);
      expect(focusedIn(listTab(b)), isTrue);
      expect(favoritesState(tester).listId, b);

      // Toward the start from Beta is Alpha.
      await press(tester, toStart(rtl));
      expect(
        focusedIn(listTab(a)),
        isTrue,
        reason: 'still on Beta: ${focusedIn(listTab(b))}',
      );
      await disposeApp(tester, db);
    });
  }
}
