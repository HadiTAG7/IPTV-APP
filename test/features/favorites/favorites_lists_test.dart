// Managing the user's channel lists in the Favorites screen: list tabs
// after the live favourites, moving and removing channels, renaming and
// deleting lists (focus never lost on TV), "New list…". All names and URLs
// are synthetic.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/features/favorites/favorites_screen.dart';
import 'package:iptv_player/features/live/channel_list.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/sources/models.dart';

import '../../support/text_entry.dart';
import '../live/support/live_test_utils.dart';

FavoritesViewState favoritesState(WidgetTester tester) =>
    tester.state<FavoritesViewState>(find.byType(FavoritesView));

ValueKey<String> listTab(int listId) => ValueKey('favorites-tab-list-$listId');

/// [text] on a row of the channel list (not, say, a closing sheet's title).
Finder inList(String text) =>
    find.descendant(of: find.byType(ChannelList), matching: find.text(text));

const nameField = ValueKey('channel-list-name-field');

/// Ten channels; channel 2 is a favourite; lists [first] (channels 3, 5
/// and 7) and [second] (channel 1).
Future<({int source, int first, int second})> seedLists(
  AppDatabase db, {
  required String first,
  required String second,
}) async {
  final id = await addTestSource(db, lastSyncAt: DateTime.now());
  await seedCatalog(
    db,
    id,
    categories: [liveCategory('news', 'News', 0)],
    channels: [for (var n = 1; n <= 10; n++) testChannel(n)],
  );
  await db.favoritesDao.setFavorite(id, ContentKind.live, 'k2', true);
  final dao = db.channelListsDao;
  final a = await dao.createList(id, first, channels: ['k3', 'k5', 'k7']);
  final b = await dao.createList(id, second, channels: ['k1']);
  return (source: id, first: a, second: b);
}

Future<void> openFavoritesTab(WidgetTester tester, bool rtl) async {
  final steps = HomeTab.tvTabs.indexOf(HomeTab.favorites);
  for (var i = 0; i < steps; i++) {
    await press(tester, LogicalKeyboardKey.arrowDown);
  }
  expect(focusedIn(const ValueKey('rail-favorites')), isTrue);
  await press(tester, toEnd(rtl));
}

void main() {
  for (final rtl in [false, true]) {
    final locale = Locale(rtl ? 'ar' : 'en');
    final l10n = lookupAppLocalizations(locale);
    final sports = rtl ? 'الرياضة' : 'Sports';
    final news = rtl ? 'الأخبار' : 'News';
    final football = rtl ? 'كرة القدم' : 'Football';
    final kids = rtl ? 'الأطفال' : 'Kids';

    testWidgets('${locale.languageCode}: TV list tabs; move, remove, play, '
        'rename and delete with the remote', (tester) async {
      final db = openAppTestDb();
      final seeded = await seedLists(db, first: sports, second: news);
      final dao = db.channelListsDao;
      final player = FakePlayer();
      await pumpLiveApp(
        tester,
        db,
        locale: locale,
        overrides: [
          player.override,
          targetPlatformProvider.overrideWithValue(TargetPlatform.linux),
        ],
      );
      await openFavoritesTab(tester, rtl);
      expect(focusedIn(const ValueKey('favorites-tab-live')), isTrue);

      // The lists follow the live favourites; focusing a tab shows it.
      await press(tester, toEnd(rtl));
      expect(focusedIn(listTab(seeded.first)), isTrue);
      expect(favoritesState(tester).listId, seeded.first);
      expect(find.text('Channel 2'), findsNothing);
      expect(find.text('Channel 3'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Channel 3');

      // Move down: the channel moves and keeps focus.
      await press(tester, LogicalKeyboardKey.contextMenu);
      expect(find.text(l10n.liveMoveUp), findsNothing);
      expectFocusOn(l10n.liveMoveDown);
      await press(tester, LogicalKeyboardKey.select);
      expect(await dao.channelKeys(seeded.first), ['k5', 'k3', 'k7']);
      expectFocusOn('Channel 3');
      expect(
        tester.state<ChannelListState>(find.byType(ChannelList)).currentIndex,
        1,
      );

      // Move up, back to the top.
      await press(tester, LogicalKeyboardKey.contextMenu);
      expectFocusOn(l10n.liveMoveUp);
      await press(tester, LogicalKeyboardKey.select);
      expect(await dao.channelKeys(seeded.first), ['k3', 'k5', 'k7']);
      expectFocusOn('Channel 3');

      // Remove channel 5: focus stays on its row, now channel 7.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Channel 5');
      await press(tester, LogicalKeyboardKey.contextMenu);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn(l10n.liveRemoveFromList(sports));
      await press(tester, LogicalKeyboardKey.select);
      expect(await dao.channelKeys(seeded.first), ['k3', 'k7']);
      expect(inList('Channel 5'), findsNothing);
      expectFocusOn('Channel 7');

      // Playing zaps within the list.
      await press(tester, LogicalKeyboardKey.select);
      expect(player.requests.single.item.key, 'k7');
      expect(player.requests.single.zapKeys, ['k3', 'k7']);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expectFocusOn('Channel 7');

      // Rename from the button above the channels.
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedIn(const ValueKey('favorites-list-rename')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text(l10n.liveRenameList), findsWidgets);
      await typeText(tester, find.byKey(nameField), news);
      await settle(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      // Taken: the dialog stays with the error.
      expect(find.text(l10n.liveListNameTaken), findsOneWidget);
      await typeText(tester, find.byKey(nameField), football);
      await settle(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byKey(nameField), findsNothing);
      expect((await dao.listById(seeded.first))?.name, football);
      expect(
        find.descendant(
          of: find.byKey(listTab(seeded.first)),
          matching: find.text(football),
        ),
        findsOneWidget,
      );
      expect(focusedIn(const ValueKey('favorites-list-rename')), isTrue);

      // Delete from the button: Cancel has focus and keeps it.
      await press(tester, toEnd(rtl));
      expect(focusedIn(const ValueKey('favorites-list-delete')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(focusedIn(const ValueKey('delete-list-cancel')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(await dao.listById(seeded.first), isNotNull);
      expect(focusedIn(const ValueKey('favorites-list-delete')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, toEnd(rtl));
      expect(focusedIn(const ValueKey('delete-list-confirm')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      // The first list: focus and the selection go to the live favourites.
      expect(await dao.listById(seeded.first), isNull);
      expect(find.byKey(listTab(seeded.first)), findsNothing);
      expect(focusedIn(const ValueKey('favorites-tab-live')), isTrue);
      expect(favoritesState(tester).listId, isNull);
      expect(find.text('Channel 2'), findsOneWidget);

      // Delete the other list from its tab's options.
      await press(tester, toEnd(rtl));
      expect(focusedIn(listTab(seeded.second)), isTrue);
      await press(tester, LogicalKeyboardKey.contextMenu);
      expectFocusOn(l10n.liveRenameList);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn(l10n.liveDeleteList);
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, toEnd(rtl));
      await press(tester, LogicalKeyboardKey.select);
      expect(await dao.lists(seeded.source), isEmpty);
      expect(focusedIn(const ValueKey('favorites-tab-live')), isTrue);

      // "New list…" ends the row; the new list's tab gets focus.
      await press(tester, toEnd(rtl));
      await press(tester, toEnd(rtl));
      await press(tester, toEnd(rtl));
      expect(focusedIn(const ValueKey('favorites-tab-new-list')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      await typeText(tester, find.byKey(nameField), kids);
      await settle(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      final created = (await dao.lists(seeded.source)).single;
      expect(created.name, kids);
      await settle(tester);
      expect(focusedIn(listTab(created.id)), isTrue);
      expect(favoritesState(tester).listId, created.id);
      expect(find.text(l10n.liveListEmpty), findsOneWidget);
      // An empty list still has its buttons to enter.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('favorites-list-rename')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedIn(listTab(created.id)), isTrue);
      await disposeApp(tester, db);
    });

    testWidgets('${locale.languageCode}: TV removing the last channel moves '
        'focus to the list buttons; a list deleted elsewhere hands focus to '
        'the live favourites', (tester) async {
      final db = openAppTestDb();
      final seeded = await seedLists(db, first: sports, second: news);
      final dao = db.channelListsDao;
      await pumpLiveApp(
        tester,
        db,
        locale: locale,
        overrides: [
          targetPlatformProvider.overrideWithValue(TargetPlatform.linux),
        ],
      );
      await openFavoritesTab(tester, rtl);
      await press(tester, toEnd(rtl));
      await press(tester, toEnd(rtl));
      expect(focusedIn(listTab(seeded.second)), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Channel 1');
      await press(tester, LogicalKeyboardKey.contextMenu);
      expectFocusOn(l10n.liveRemoveFromList(news));
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text(l10n.liveListEmpty), findsOneWidget);
      expect(focusedIn(const ValueKey('favorites-list-rename')), isTrue);

      // Deleted while its buttons have focus (another screen): back to the
      // live favourites, focus on their tab.
      await dao.deleteList(seeded.second);
      await settle(tester);
      expect(favoritesState(tester).listId, isNull);
      expect(focusedIn(const ValueKey('favorites-tab-live')), isTrue);
      expect(find.text('Channel 2'), findsOneWidget);
      await disposeApp(tester, db);
    });

    testWidgets('${locale.languageCode}: phone list tabs with touch', (
      tester,
    ) async {
      final db = openAppTestDb();
      final seeded = await seedLists(db, first: sports, second: news);
      final dao = db.channelListsDao;
      await pumpLiveApp(tester, db, tv: false, locale: locale);
      await tester.tap(find.byKey(const ValueKey('nav-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('more-favorites')));
      await tester.pumpAndSettle();
      expect(find.byType(FavoritesView), findsOneWidget);

      // List tabs run from the start side, after the live favourites.
      final liveX = tester
          .getCenter(find.byKey(const ValueKey('favorites-tab-live')))
          .dx;
      final listX = tester.getCenter(find.byKey(listTab(seeded.first))).dx;
      expect(rtl ? listX < liveX : listX > liveX, isTrue);
      await tester.tap(find.byKey(listTab(seeded.first)));
      await settle(tester);
      expect(favoritesState(tester).listId, seeded.first);

      // Long press: move channel 5 up.
      await tester.longPress(find.text('Channel 5'));
      await settle(tester);
      await tester.tap(find.text(l10n.liveMoveUp));
      await settle(tester);
      expect(await dao.channelKeys(seeded.first), ['k5', 'k3', 'k7']);

      // Remove channel 7.
      await tester.longPress(find.text('Channel 7'));
      await settle(tester);
      expect(find.text(l10n.liveMoveDown), findsNothing);
      await tester.tap(find.text(l10n.liveRemoveFromList(sports)));
      await settle(tester);
      expect(await dao.channelKeys(seeded.first), ['k5', 'k3']);
      expect(inList('Channel 7'), findsNothing);

      // Rename with the button.
      await tester.tap(find.byKey(const ValueKey('favorites-list-rename')));
      await settle(tester);
      await typeText(tester, find.byKey(nameField), football);
      await tester.tap(find.byKey(const ValueKey('channel-list-name-save')));
      await settle(tester);
      expect((await dao.listById(seeded.first))?.name, football);
      expect(find.text(football), findsOneWidget);

      // Delete with the button, confirmed.
      await tester.tap(find.byKey(const ValueKey('favorites-list-delete')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('delete-list-confirm')));
      await settle(tester);
      expect(await dao.listById(seeded.first), isNull);
      expect(find.byKey(listTab(seeded.first)), findsNothing);
      expect(favoritesState(tester).listId, isNull);
      expect(find.text('Channel 2'), findsOneWidget);
      await disposeApp(tester, db);
    });
  }
}
