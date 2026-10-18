// The user's own channel lists on the Live screen: "Add to list…" from the
// channel options (a new list, an existing one, removing again), and each
// list as a category after Favorites that plays and zaps within itself.
// All names and URLs are synthetic.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/features/live/category_chips.dart';
import 'package:iptv_player/features/live/live_models.dart';
import 'package:iptv_player/features/live/live_screen.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/widgets/states.dart';

import '../../support/text_entry.dart';
import 'support/live_test_utils.dart';

LiveViewState liveState(WidgetTester tester) =>
    tester.state<LiveViewState>(find.byType(LiveView));

/// The phone Live layout's chip row.
final chipRow = find.descendant(
  of: find.byType(LiveCategoryChips),
  matching: find.byType(Scrollable),
);

const nameField = ValueKey('channel-list-name-field');

/// Opens "Add to list…" from the focused channel's options sheet.
Future<void> openAddToList(WidgetTester tester, AppLocalizations l10n) async {
  await press(tester, LogicalKeyboardKey.contextMenu);
  expectFocusOn(l10n.liveAddFavorite);
  await press(tester, LogicalKeyboardKey.arrowDown);
  expectFocusOn(l10n.liveAddToList);
  await press(tester, LogicalKeyboardKey.select);
  expect(find.text(l10n.liveAddToListTitle), findsOneWidget);
}

void main() {
  for (final rtl in [false, true]) {
    final locale = Locale(rtl ? 'ar' : 'en');
    final l10n = lookupAppLocalizations(locale);
    final name = rtl ? 'الرياضة' : 'Sports';

    testWidgets('${locale.languageCode}: TV adds channels to a new list and '
        'an existing one; the list is a category that zaps within '
        'itself', (tester) async {
      final db = openAppTestDb();
      final id = await seedThreeCategories(db);
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
      await press(tester, toEnd(rtl));
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Channel 2');

      // No list yet: "New list…" asks for a name.
      await openAddToList(tester, l10n);
      expectFocusOn(l10n.liveNewList);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text(l10n.liveNewListTitle), findsOneWidget);
      // An empty name is refused in place.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('channel-list-name-save')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text(l10n.liveListNameEmpty), findsOneWidget);
      await typeText(tester, find.byKey(nameField), '  $name ');
      await settle(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text(l10n.liveNewListTitle), findsNothing);
      expect(find.text(l10n.liveListAdded(name)), findsOneWidget);
      expectFocusOn('Channel 2');
      final lists = await db.channelListsDao.lists(id);
      expect(lists.single.name, name);
      final listId = lists.single.id;
      expect(await db.channelListsDao.channelKeys(listId), ['k2']);

      // The list is a category right after Favorites, with its count.
      final entry = find.byKey(ValueKey('live-category-list:$listId'));
      expect(entry, findsOneWidget);
      expect(
        find.descendant(of: entry, matching: find.text('1')),
        findsOneWidget,
      );
      double y(String id) =>
          tester.getCenter(find.byKey(ValueKey('live-category-$id'))).dy;
      expect(y('fav'), lessThan(y('list:$listId')));
      expect(y('list:$listId'), lessThan(y('recent')));

      // Channel 4 joins the existing list (focused first in the dialog).
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Channel 4');
      await openAddToList(tester, l10n);
      expectFocusOn(name);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text(l10n.liveListAdded(name)), findsOneWidget);
      expect(await db.channelListsDao.channelKeys(listId), ['k2', 'k4']);
      expectFocusOn('Channel 4');

      // Open the list from the categories: Favorites, the list, Recent,
      // All channels.
      await press(tester, toStart(rtl));
      expectFocusOn(l10n.liveAllChannels);
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expectFocusOn(name);
      await press(tester, LogicalKeyboardKey.select);
      expect(liveState(tester).selected, LiveList.channelList(listId));
      expectFocusOn('Channel 2');
      expect(find.text('Channel 1'), findsNothing);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Channel 4');
      await press(tester, LogicalKeyboardKey.select);
      final request = player.requests.single;
      expect(request.item.key, 'k4');
      expect(request.zapKeys, ['k2', 'k4']);
      expect(request.categoryKey, isNull);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expectFocusOn('Channel 4');

      // The dialog shows the list checked; picking it removes the channel
      // and the list keeps focus on its next row.
      await openAddToList(tester, l10n);
      expect(
        find.descendant(
          of: find.byKey(ValueKey('add-to-list-$listId')),
          matching: find.byIcon(Icons.check_box_rounded),
        ),
        findsOneWidget,
      );
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text(l10n.liveListRemoved(name)), findsOneWidget);
      expect(await db.channelListsDao.channelKeys(listId), ['k2']);
      expectFocusOn('Channel 2');
      // The info pane follows the focused row after its pause.
      await wait(tester, LiveView.infoDelay);
      expect(find.text('Channel 4'), findsNothing);

      // Removing the last one leaves the friendly empty state, focus on the
      // list's category.
      await openAddToList(tester, l10n);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text(l10n.liveListEmpty), findsOneWidget);
      expectFocusOn(name);
      await disposeApp(tester, db);
    });

    testWidgets('${locale.languageCode}: phone long press adds to a new '
        'list; its chip plays within the list', (tester) async {
      final db = openAppTestDb();
      final id = await seedThreeCategories(db);
      final player = FakePlayer();
      await pumpLiveApp(
        tester,
        db,
        tv: false,
        locale: locale,
        overrides: [player.override],
      );
      await tester.longPress(find.text('Channel 3'));
      await settle(tester);
      await tester.tap(find.text(l10n.liveAddToList));
      await settle(tester);
      await tester.tap(find.text(l10n.liveNewList));
      await settle(tester);
      await typeText(tester, find.byKey(nameField), name);
      await tester.tap(find.byKey(const ValueKey('channel-list-name-save')));
      await settle(tester);
      expect(find.text(l10n.liveListAdded(name)), findsOneWidget);
      final listId = (await db.channelListsDao.lists(id)).single.id;

      // A taken name is refused.
      await tester.longPress(find.text('Channel 5'));
      await settle(tester);
      await tester.tap(find.text(l10n.liveAddToList));
      await settle(tester);
      await tester.tap(find.text(l10n.liveNewList));
      await settle(tester);
      await typeText(tester, find.byKey(nameField), name.toUpperCase());
      await tester.tap(find.byKey(const ValueKey('channel-list-name-save')));
      await settle(tester);
      expect(find.text(l10n.liveListNameTaken), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('channel-list-name-cancel')));
      await settle(tester);
      expect(await db.channelListsDao.lists(id), hasLength(1));

      // Its chip comes right after Favorites.
      final chip = find.byKey(ValueKey('live-chip-list:$listId'));
      await tester.scrollUntilVisible(chip, -200, scrollable: chipRow);
      await settle(tester);
      final favX = tester
          .getCenter(
            find.byKey(const ValueKey('live-chip-fav'), skipOffstage: false),
          )
          .dx;
      final recentX = tester
          .getCenter(
            find.byKey(const ValueKey('live-chip-recent'), skipOffstage: false),
          )
          .dx;
      final chipX = tester.getCenter(chip).dx;
      expect(rtl ? chipX < favX : chipX > favX, isTrue);
      expect(rtl ? chipX > recentX : chipX < recentX, isTrue);
      await tester.tap(chip);
      await settle(tester);
      expect(liveState(tester).selected, LiveList.channelList(listId));
      expect(find.text('Channel 1'), findsNothing);
      await tester.tap(find.text('Channel 3'));
      await settle(tester);
      expect(player.requests.single.item.key, 'k3');
      expect(player.requests.single.zapKeys, ['k3']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(chipRow, findsOneWidget);
      await disposeApp(tester, db);
    });
  }

  testWidgets('a saved list opens again; a deleted one falls back to All '
      'channels', (tester) async {
    final db = openAppTestDb();
    final id = await seedThreeCategories(db);
    final listId = await db.channelListsDao.createList(
      id,
      'Evening',
      channels: ['k12', 'k3'],
    );
    await db.settingsDao.setString('live.lastList.$id', 'list:$listId');
    await pumpLiveApp(tester, db);
    expect(liveState(tester).selected, LiveList.channelList(listId));
    expect(find.text('Channel 12'), findsOneWidget);
    expect(find.text('Channel 3'), findsOneWidget);
    expect(find.text('Channel 1'), findsNothing);

    // Deleted elsewhere: All channels shows.
    await db.channelListsDao.deleteList(listId);
    await settle(tester);
    expect(liveState(tester).selected, const LiveList.all());
    expect(find.text('Evening'), findsNothing);
    await disposeApp(tester, db);
  });
}
