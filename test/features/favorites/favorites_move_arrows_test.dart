// After Move down / Move up in a user list, the next Up press goes to the
// row directly above the moved channel.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/features/live/channel_list.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';

import '../live/support/live_test_utils.dart';

ValueKey<String> listTab(int listId) => ValueKey('favorites-tab-list-$listId');

Future<void> openFavoritesTab(WidgetTester tester, bool rtl) async {
  final steps = HomeTab.tvTabs.indexOf(HomeTab.favorites);
  for (var i = 0; i < steps; i++) {
    await press(tester, LogicalKeyboardKey.arrowDown);
  }
  expect(focusedIn(const ValueKey('rail-favorites')), isTrue);
  await press(tester, toEnd(rtl));
}

Future<({int source, int list})> seed(AppDatabase db) async {
  final id = await addTestSource(db, lastSyncAt: DateTime.now());
  await seedCatalog(
    db,
    id,
    categories: [liveCategory('news', 'News', 0)],
    channels: [for (var n = 1; n <= 10; n++) testChannel(n)],
  );
  final list = await db.channelListsDao.createList(
    id,
    'Mine',
    channels: ['k1', 'k2', 'k3', 'k4', 'k5', 'k6'],
  );
  return (source: id, list: list);
}

int currentIndex(WidgetTester tester) =>
    tester.state<ChannelListState>(find.byType(ChannelList)).currentIndex;

void main() {
  for (final rtl in [false, true]) {
    final locale = Locale(rtl ? 'ar' : 'en');
    final l10n = lookupAppLocalizations(locale);

    Future<void> enterList(WidgetTester tester, AppDatabase db) async {
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
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Channel 1');
    }

    Future<void> moveVia(WidgetTester tester, String label) async {
      await press(tester, LogicalKeyboardKey.contextMenu);
      // Walk the sheet down to [label].
      for (var i = 0; i < 4 && !focusedShows(label); i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expectFocusOn(label);
      await press(tester, LogicalKeyboardKey.select);
    }

    testWidgets('${locale.languageCode}: Up right after Move down goes to '
        'the row above', (tester) async {
      final db = openAppTestDb();
      final seeded = await seed(db);
      await enterList(tester, db);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Channel 3');
      await moveVia(tester, l10n.liveMoveDown);
      await moveVia(tester, l10n.liveMoveDown);
      expect(await db.channelListsDao.channelKeys(seeded.list), [
        'k1',
        'k2',
        'k4',
        'k5',
        'k3',
        'k6',
      ]);
      expectFocusOn('Channel 3');
      expect(currentIndex(tester), 4);

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(
        focusedShows('Channel 5'),
        isTrue,
        reason: 'focused: ${focusedTexts()} index ${currentIndex(tester)}',
      );
      await disposeApp(tester, db);
    });

    testWidgets('${locale.languageCode}: Up right after Move up moves', (
      tester,
    ) async {
      final db = openAppTestDb();
      final seeded = await seed(db);
      await enterList(tester, db);
      for (var i = 0; i < 4; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expectFocusOn('Channel 5');
      await moveVia(tester, l10n.liveMoveUp);
      expect(await db.channelListsDao.channelKeys(seeded.list), [
        'k1',
        'k2',
        'k3',
        'k5',
        'k4',
        'k6',
      ]);
      expectFocusOn('Channel 5');
      expect(currentIndex(tester), 3);

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(
        focusedShows('Channel 3'),
        isTrue,
        reason: 'focused: ${focusedTexts()} index ${currentIndex(tester)}',
      );
      await disposeApp(tester, db);
    });

    testWidgets('${locale.languageCode}: Up right after removing the bottom '
        'channel moves', (tester) async {
      final db = openAppTestDb();
      final seeded = await seed(db);
      await enterList(tester, db);
      for (var i = 0; i < 5; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expectFocusOn('Channel 6');
      await moveVia(tester, l10n.liveRemoveFromList('Mine'));
      expect(await db.channelListsDao.channelKeys(seeded.list), [
        'k1',
        'k2',
        'k3',
        'k4',
        'k5',
      ]);
      expectFocusOn('Channel 5');
      expect(currentIndex(tester), 4);

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(
        focusedShows('Channel 4'),
        isTrue,
        reason: 'focused: ${focusedTexts()} index ${currentIndex(tester)}',
      );
      await disposeApp(tester, db);
    });
  }
}
