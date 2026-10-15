import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/live/category_chips.dart';
import 'package:iptv_player/features/live/category_pane.dart';
import 'package:iptv_player/features/live/live_models.dart';
import 'package:iptv_player/features/live/live_screen.dart';
import 'package:iptv_player/features/live/providers.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/widgets/channel_tile.dart';

import 'support/live_test_utils.dart';

/// The phone Live layout's chip row.
final chipRow = find.descendant(
  of: find.byType(LiveCategoryChips),
  matching: find.byType(Scrollable),
);

void main() {
  for (final rtl in [false, true]) {
    final locale = Locale(rtl ? 'ar' : 'en');
    final l10n = lookupAppLocalizations(locale);

    testWidgets('${locale.languageCode}: phone chips switch the list; tap '
        'plays, long press opens options', (tester) async {
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
      // Phone layout: chips, no category pane.
      expect(find.byType(LiveCategoryPane), findsNothing);
      expect(find.byType(LiveCategoryChips), findsOneWidget);
      // Chips run from the start side.
      final favX = tester
          .getCenter(
            find.byKey(const ValueKey('live-chip-fav'), skipOffstage: false),
          )
          .dx;
      final allX = tester
          .getCenter(find.byKey(const ValueKey('live-chip-all')))
          .dx;
      expect(rtl ? favX > allX : favX < allX, isTrue);
      expect(find.text('Channel 1'), findsOneWidget);

      // The row is lazy: chips further along are built as it scrolls.
      final chip = find.byKey(const ValueKey('live-chip-cat:sports'));
      await tester.scrollUntilVisible(chip, 200, scrollable: chipRow);
      await settle(tester);
      await tester.tap(chip);
      await settle(tester);
      final live = tester.state<LiveViewState>(find.byType(LiveView));
      expect(live.selected, const LiveList.category('sports'));
      expect(find.text('Channel 1'), findsNothing);
      expect(find.text('Channel 11'), findsOneWidget);

      await tester.tap(find.text('Channel 12'));
      await settle(tester);
      expect(player.requests.single.item.key, 'k12');
      expect(player.requests.single.categoryKey, 'sports');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Channel 12'), findsOneWidget);
      final tile = tester.widget<ChannelTile>(
        find.ancestor(
          of: find.text('Channel 12'),
          matching: find.byType(ChannelTile),
        ),
      );
      expect(tile.selected, isTrue);

      await tester.longPress(find.text('Channel 13'));
      await settle(tester);
      await tester.tap(find.text(l10n.liveAddFavorite));
      await settle(tester);
      expect(await db.favoritesDao.favoriteKeys(id, ContentKind.live), ['k13']);

      // Favourites zap within the favourites.
      final fav = find.byKey(const ValueKey('live-chip-fav'));
      await tester.scrollUntilVisible(fav, -200, scrollable: chipRow);
      await settle(tester);
      await tester.tap(fav);
      await settle(tester);
      expect(find.text('Channel 13'), findsOneWidget);
      await tester.tap(find.text('Channel 13'));
      await settle(tester);
      expect(player.requests.last.zapKeys, ['k13']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Long press on a chip hides its category.
      final kids = find.byKey(const ValueKey('live-chip-cat:kids'));
      await tester.scrollUntilVisible(kids, 200, scrollable: chipRow);
      await settle(tester);
      await tester.longPress(kids);
      await settle(tester);
      await tester.tap(find.text(l10n.liveHideCategory));
      await settle(tester);
      expect(find.byKey(const ValueKey('live-chip-cat:kids')), findsNothing);
      await disposeApp(tester, db);
    });
  }

  for (final rtl in [false, true]) {
    testWidgets('${rtl ? 'ar' : 'en'}: thousands of categories build only the '
        'chips on screen; a far selected one is revealed', (tester) async {
      final db = openAppTestDb();
      final id = await addTestSource(db, lastSyncAt: DateTime.now());
      await seedCatalog(
        db,
        id,
        categories: [
          for (var i = 0; i < 2000; i++) liveCategory('c$i', 'Category $i', i),
        ],
        channels: [
          testChannel(1, categories: ['c0']),
          testChannel(2, categories: ['c1500']),
        ],
      );
      await db.settingsDao.setString(liveLastListKey(id), 'cat:c1500');
      await pumpLiveApp(
        tester,
        db,
        tv: false,
        locale: Locale(rtl ? 'ar' : 'en'),
      );
      // Built chips, on screen or in the row's cache extent.
      final chips = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('live-chip-'),
        skipOffstage: false,
      );
      expect(chips.evaluate().length, lessThan(40));
      final selected = find.byKey(const ValueKey('live-chip-cat:c1500'));
      expect(selected, findsOneWidget);
      final rect = tester.getRect(selected);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(phoneSize.width));
      expect(find.text('Channel 2'), findsOneWidget);

      // Rebuilds (a played channel, a favourite) stay as small.
      await db.recentDao.markRecent(id, 'k2');
      await settle(tester);
      expect(chips.evaluate().length, lessThan(40));
      await disposeApp(tester, db);
    });
  }

  testWidgets('a wide landscape phone uses the three panes', (tester) async {
    final db = openAppTestDb();
    await seedThreeCategories(db);
    tester.view.physicalSize = const Size(2000, 1000);
    await pumpLiveApp(tester, db, tv: false);
    tester.view.physicalSize = const Size(2000, 1000);
    await settle(tester);
    expect(find.byType(LiveCategoryPane), findsOneWidget);
    await disposeApp(tester, db);
  });
}
