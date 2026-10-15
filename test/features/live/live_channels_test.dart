import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/features/live/channel_list.dart';
import 'package:iptv_player/features/live/info_pane.dart';
import 'package:iptv_player/features/live/live_actions.dart';
import 'package:iptv_player/features/live/live_models.dart';
import 'package:iptv_player/features/live/live_screen.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/theme/tokens.dart';
import 'package:iptv_player/tv/key_repeat.dart';
import 'package:iptv_player/widgets/channel_tile.dart';
import 'package:iptv_player/widgets/states.dart';

import 'support/live_test_utils.dart';

final en = lookupAppLocalizations(const Locale('en'));

/// A source whose only category holds [count] numbered channels.
Future<int> seedMany(AppDatabase db, int count) async {
  final id = await addTestSource(db, lastSyncAt: DateTime.now());
  await seedCatalog(
    db,
    id,
    categories: [liveCategory('big', 'Big', 0)],
    channels: [
      for (var n = 1; n <= count; n++) testChannel(n, categories: ['big']),
    ],
  );
  return id;
}

LiveViewState liveState(WidgetTester tester) =>
    tester.state<LiveViewState>(find.byType(LiveView));

ChannelListState listState(WidgetTester tester) =>
    tester.state<ChannelListState>(find.byType(ChannelList));

Future<void> enterPage(WidgetTester tester) =>
    press(tester, LogicalKeyboardKey.arrowRight);

void main() {
  group('paging', () {
    testWidgets('5k channels: only the pages on screen are read', (
      tester,
    ) async {
      final db = openAppTestDb();
      await seedMany(db, 5000);
      await pumpLiveApp(tester, db);
      final pager = listState(tester).pager!;
      expect(pager.length, 5000);
      expect(pager.loadedPages, {0});
      expect(pager.loadCount, 1);
      // Only the rows on screen (plus the cache band) are built.
      expect(find.byType(ChannelTile).evaluate().length, lessThan(30));

      await enterPage(tester);
      expectFocusOn('Channel 1');

      // Page Down moves one screen of rows.
      await press(tester, LogicalKeyboardKey.pageDown);
      final perScreen = listState(tester).currentIndex;
      expect(perScreen, greaterThanOrEqualTo(6));
      expectFocusOn('Channel ${perScreen + 1}');
      await press(tester, LogicalKeyboardKey.pageUp);
      expectFocusOn('Channel 1');

      // Digits jump to the channel number once typing pauses.
      for (final key in [
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit1,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
      }
      final badge = find.byKey(const ValueKey('channel-number-badge'));
      expect(
        find.descendant(of: badge, matching: find.text('4321')),
        findsOneWidget,
      );
      await wait(tester, ChannelList.digitDelay);
      expectFocusOn('Channel 4321');
      expect(badge, findsNothing);
      expect(pager.loadedPages, contains(4320 ~/ 200));
      expect(pager.loadedPages.length, lessThanOrEqualTo(3));
      expect(pager.loadCount, lessThanOrEqualTo(3));

      // OK commits typed digits at once.
      await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.select);
      expectFocusOn('Channel 7');

      // An unknown number says so and keeps focus.
      for (final key in [
        LogicalKeyboardKey.digit9,
        LogicalKeyboardKey.digit9,
        LogicalKeyboardKey.digit9,
        LogicalKeyboardKey.digit9,
        LogicalKeyboardKey.digit9,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
      }
      await wait(tester, ChannelList.digitDelay);
      expect(find.text(en.liveNoChannelNumber(99999)), findsOneWidget);
      expectFocusOn('Channel 7');
      await wait(tester, ChannelList.missDuration);
      expect(find.text(en.liveNoChannelNumber(99999)), findsNothing);

      // Pages far away were dropped (at most 10 kept).
      expect(pager.loadedPages.length, lessThanOrEqualTo(ChannelList.maxPages));
      await disposeApp(tester, db);
    });

    testWidgets('held arrows are throttled, then jump five rows', (
      tester,
    ) async {
      final db = openAppTestDb();
      await seedMany(db, 300);
      await pumpLiveApp(tester, db);
      await enterPage(tester);
      final clock = FakeClock(DateTime.utc(2026, 10, 15));
      KeyRepeatThrottle.instance = KeyRepeatThrottle(clock: clock);

      Future<void> repeatAfter(int ms) async {
        clock.advance(Duration(milliseconds: ms));
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
        await settle(tester);
      }

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await settle(tester);
      expectFocusOn('Channel 2');
      await repeatAfter(50); // too soon: dropped
      expectFocusOn('Channel 2');
      await repeatAfter(450);
      expectFocusOn('Channel 3');
      await repeatAfter(500); // held 1 s: jumps
      expectFocusOn('Channel 8');
      await repeatAfter(150);
      expectFocusOn('Channel 13');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await settle(tester);
      await disposeApp(tester, db);
    });

    testWidgets('opens scrolled to the last played channel', (tester) async {
      final db = openAppTestDb();
      final id = await seedMany(db, 5000);
      await db.recentDao.markRecent(id, 'k3000');
      await pumpLiveApp(tester, db);
      final pager = listState(tester).pager!;
      expect(pager.loadedPages, isNot(contains(0)));
      expect(pager.loadedPages, contains(2999 ~/ 200));
      expect(find.text('Channel 3000'), findsOneWidget);
      expect(find.text('Channel 1'), findsNothing);

      await enterPage(tester);
      expectFocusOn('Channel 3000');
      // The playing channel is marked.
      final tile = tester.widget<ChannelTile>(
        find.ancestor(
          of: find.text('Channel 3000'),
          matching: find.byType(ChannelTile),
        ),
      );
      expect(tile.selected, isTrue);
      await disposeApp(tester, db);
    });
  });

  group('data changes', () {
    testWidgets('a sync reloads the list and keeps focus on the channel', (
      tester,
    ) async {
      final db = openAppTestDb();
      final id = await seedThreeCategories(db);
      await pumpLiveApp(tester, db);
      await enterPage(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Channel 3');
      expect(listState(tester).currentIndex, 2);

      // The next catalog has a channel numbered 0, which sorts first.
      await seedCatalog(
        db,
        id,
        categories: [
          liveCategory('news', 'News', 0),
          liveCategory('sports', 'Sports', 1),
        ],
        channels: [
          testChannel(0, name: 'Channel Zero'),
          for (var n = 1; n <= 20; n++)
            testChannel(n, categories: [n <= 10 ? 'news' : 'sports']),
        ],
      );
      await settle(tester);
      await settle(tester);
      expect(find.text('Channel Zero'), findsOneWidget);
      expect(find.text('Kids'), findsNothing);
      expectFocusOn('Channel 3');
      expect(listState(tester).currentIndex, 3);
      await disposeApp(tester, db);
    });
  });

  group('now/next', () {
    for (final rtl in [false, true]) {
      final locale = Locale(rtl ? 'ar' : 'en');
      final l10n = lookupAppLocalizations(locale);

      testWidgets('${locale.languageCode}: rows and the info pane show the '
          'guide, refreshed each minute', (tester) async {
        final db = openAppTestDb();
        final id = await seedThreeCategories(db);
        final start = DateTime.utc(2026, 10, 15, 18);
        await seedGuide(db, id, {
          1: [
            programme(
              1,
              start,
              const Duration(hours: 1),
              'Morning Report',
              desc: 'Headlines and weather.',
            ),
            programme(
              1,
              start.add(const Duration(hours: 1)),
              const Duration(hours: 1),
              'Evening Talk',
            ),
          ],
          2: [programme(2, start, const Duration(minutes: 30), 'مباراة اليوم')],
        });
        final clock = FakeClock(testNow); // 18:10
        await pumpLiveApp(tester, db, clock: clock, locale: locale);
        final store = liveState(tester).nowNext;
        // One query for the rows on screen once scrolling settled.
        await wait(tester, const Duration(milliseconds: 200));
        expect(find.text('Morning Report'), findsOneWidget);
        expect(find.text('مباراة اليوم'), findsOneWidget);
        expect(store.queries, 1);
        expect(store.lastQuery, containsAll(['k1', 'k2', 'k3']));
        final rows = find.byType(ChannelTile);
        final first = tester.widget<ChannelTile>(rows.first);
        expect(first.progress, closeTo(10 / 60, 0.01));
        expect(
          tester.widget<ChannelTile>(rows.at(2)).nowTitle,
          isNull,
          reason: 'channel 3 has no guide',
        );

        // The info pane follows the focused channel after a short rest.
        await tester.sendKeyEvent(toEnd(rtl));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expectFocusOn('Channel 1');
        expect(find.byKey(const ValueKey('live-info-k1')), findsNothing);
        await wait(tester, LiveView.infoDelay);
        expect(find.byKey(const ValueKey('live-info-k1')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('live-info-now-desc')),
          findsOneWidget,
        );
        expect(find.text('Headlines and weather.'), findsOneWidget);
        expect(find.text('Evening Talk'), findsOneWidget);
        final context = tester.element(find.byType(LiveView));
        expect(
          find.text(
            l10n.liveTimeRange(
              formatClock(context, start),
              formatClock(context, start.add(const Duration(hours: 1))),
            ),
          ),
          findsOneWidget,
        );

        // An hour later the minute refresh moves the rows on.
        clock.advance(const Duration(hours: 1));
        await wait(tester, const Duration(minutes: 1));
        expect(find.text('Morning Report'), findsNothing);
        expect(find.text('مباراة اليوم'), findsNothing);
        expect(
          tester.widget<ChannelTile>(find.byType(ChannelTile).first).nowTitle,
          'Evening Talk',
        );
        await disposeApp(tester, db);
      });
    }
  });

  group('menu', () {
    for (final rtl in [false, true]) {
      final locale = Locale(rtl ? 'ar' : 'en');
      final l10n = lookupAppLocalizations(locale);

      testWidgets('${locale.languageCode}: Menu toggles a favourite and hides '
          'a category', (tester) async {
        final db = openAppTestDb();
        final id = await seedThreeCategories(db);
        await pumpLiveApp(
          tester,
          db,
          locale: locale,
          overrides: [
            targetPlatformProvider.overrideWithValue(TargetPlatform.linux),
          ],
        );
        await press(tester, toEnd(rtl));
        await press(tester, LogicalKeyboardKey.arrowDown);
        expectFocusOn('Channel 2');

        await press(tester, LogicalKeyboardKey.contextMenu);
        expectFocusOn(l10n.liveAddFavorite);
        // Desktop and tests have one engine: no "other player".
        expect(find.text(l10n.livePlayWithOtherPlayer), findsNothing);
        await press(tester, LogicalKeyboardKey.select);
        expect(find.text(l10n.liveAddFavorite), findsNothing);
        expectFocusOn('Channel 2');
        expect(await db.favoritesDao.favoriteKeys(id, ContentKind.live), [
          'k2',
        ]);
        final tile = tester.widget<ChannelTile>(
          find.ancestor(
            of: find.text('Channel 2'),
            matching: find.byType(ChannelTile),
          ),
        );
        expect(tile.isFavorite, isTrue);
        // The Favorites entry counts it.
        final favEntry = find.byKey(const ValueKey('live-category-fav'));
        expect(
          find.descendant(of: favEntry, matching: find.text('1')),
          findsOneWidget,
        );

        await press(tester, LogicalKeyboardKey.contextMenu);
        expectFocusOn(l10n.liveRemoveFavorite);
        await press(tester, LogicalKeyboardKey.select);
        expect(await db.favoritesDao.favoriteKeys(id, ContentKind.live), []);

        // Hide Sports from the category pane.
        await press(tester, toStart(rtl));
        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expectFocusOn('Sports');
        await press(tester, LogicalKeyboardKey.contextMenu);
        expectFocusOn(l10n.liveHideCategory);
        await press(tester, LogicalKeyboardKey.select);
        expect(find.text('Sports'), findsNothing);
        expectFocusOn('News');
        expect(
          liveState(tester).selected,
          isNot(const LiveList.category('sports')),
        );

        // Show it again.
        await press(tester, LogicalKeyboardKey.contextMenu);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expectFocusOn(l10n.liveShowHiddenCategories);
        await press(tester, LogicalKeyboardKey.select);
        expect(find.text('Sports'), findsOneWidget);
        await disposeApp(tester, db);
      });
    }

    testWidgets('"Play with the other player" saves the engine and plays', (
      tester,
    ) async {
      final db = openAppTestDb();
      final id = await seedThreeCategories(db);
      final player = FakePlayer();
      await pumpLiveApp(
        tester,
        db,
        overrides: [
          player.override,
          targetPlatformProvider.overrideWithValue(TargetPlatform.android),
        ],
      );
      await enterPage(tester);
      await press(tester, LogicalKeyboardKey.contextMenu);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn(en.livePlayWithOtherPlayer);
      await press(tester, LogicalKeyboardKey.select);
      expect(player.requests.single.item.key, 'k1');
      expect((await db.prefsDao.prefsFor(id, 'k1')).engine, EngineKind.mpv);
      expect(find.text('PLAYING k1'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expectFocusOn('Channel 1');
      await disposeApp(tester, db);
    });

    testWidgets('the options sheet keeps clear of the TV overscan', (
      tester,
    ) async {
      final db = openAppTestDb();
      await seedThreeCategories(db);
      await pumpLiveApp(
        tester,
        db,
        overrides: [
          targetPlatformProvider.overrideWithValue(TargetPlatform.android),
        ],
      );
      await enterPage(tester);
      await press(tester, LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      final last = find.byKey(
        ValueKey('option-${LiveChannelAction.otherPlayer}'),
      );
      expect(last, findsOneWidget);
      expect(
        tester.getRect(last).bottom,
        lessThanOrEqualTo(tvSize.height - TvLayout.overscanVertical),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expectFocusOn('Channel 1');
      await disposeApp(tester, db);
    });
  });

  group('play', () {
    testWidgets('a second OK while the player opens is ignored', (
      tester,
    ) async {
      final db = openAppTestDb();
      await seedThreeCategories(db);
      final player = FakePlayer();
      await pumpLiveApp(tester, db, overrides: [player.override]);
      await enterPage(tester);
      expectFocusOn('Channel 1');
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await settle(tester);
      expect(player.requests, hasLength(1));
      expect(find.text('PLAYING k1'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expectFocusOn('Channel 1');

      // Once the player has closed, OK plays again.
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      expect(player.requests, hasLength(2));
      expect(player.requests.last.item.key, 'k2');
      await tester.binding.handlePopRoute();
      await settle(tester);
      await disposeApp(tester, db);
    });

    testWidgets('OK plays within the category and returns to the channel '
        'played last', (tester) async {
      final db = openAppTestDb();
      final id = await seedThreeCategories(db);
      final player = FakePlayer();
      await pumpLiveApp(tester, db, overrides: [player.override]);
      // Open Sports and play its second channel.
      await enterPage(tester);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Sports');
      await press(tester, LogicalKeyboardKey.select);
      expectFocusOn('Channel 11');
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);

      final request = player.requests.single;
      expect(request.sourceId, id);
      expect(request.item.key, 'k12');
      expect(request.item.kind, PlayableKind.live);
      expect(request.categoryKey, 'sports');
      expect(request.zapKeys, isNull);
      expect(await db.recentDao.recentChannelKeys(id), ['k12']);

      // The player zapped on to channel 15, then closed.
      await db.recentDao.markRecent(id, 'k15');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expectFocusOn('Channel 15');

      // Recent lists both, newest first, and zaps within them.
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expectFocusOn('Sports');
      for (var i = 0; i < 3; i++) {
        await press(tester, LogicalKeyboardKey.arrowUp);
      }
      expectFocusOn(en.liveRecent);
      await press(tester, LogicalKeyboardKey.select);
      expectFocusOn('Channel 15');
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      expect(player.requests.last.item.key, 'k12');
      expect(player.requests.last.zapKeys, ['k15', 'k12']);
      await tester.binding.handlePopRoute();
      await settle(tester);
      // Playing moved channel 12 to the top of Recent.
      expectFocusOn('Channel 12');
      expect(listState(tester).currentIndex, 0);
      await disposeApp(tester, db);
    });

    testWidgets('an empty favourites list says how to add one', (tester) async {
      final db = openAppTestDb();
      await seedThreeCategories(db);
      await pumpLiveApp(tester, db);
      await enterPage(tester);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expectFocusOn(en.liveFavorites);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text(en.favoritesEmpty), findsOneWidget);
      // Nothing to enter: focus stays on the category.
      expectFocusOn(en.liveFavorites);
      await disposeApp(tester, db);
    });
  });
}
