// The phone guide: channel list with what is on now, and a channel's day
// schedule, in English and Arabic.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/features/guide/guide_phone.dart';
import 'package:iptv_player/features/guide/guide_screen.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/widgets/channel_tile.dart';

import 'support/guide_fixtures.dart';

/// [matching] inside the schedule page.
Finder _inSchedule(Finder matching) =>
    find.descendant(of: find.byType(GuideSchedulePage), matching: matching);

/// Lets a route transition finish.
Future<void> _navigate(WidgetTester tester) async {
  await settle(tester);
  await tester.pump(const Duration(milliseconds: 500));
  await settle(tester);
}

Future<void> _openGuideTab(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav-guide')));
  await settle(tester);
  // now/next of the visible rows is read once scrolling settles.
  await tester.pump(const Duration(milliseconds: 200));
  await settle(tester);
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  for (final rtl in [false, true]) {
    final name = rtl ? 'ar (RTL)' : 'en';
    final l10n = rtl ? ar : en;

    testWidgets('$name: channels with now, then a day schedule', (
      tester,
    ) async {
      final db = openGuideDb();
      final seeded = await seedGuide(db);
      final player = PlayerLog();
      await pumpGuideApp(
        tester,
        db: db,
        player: player,
        caps: phoneCaps,
        rtl: rtl,
      );
      await _openGuideTab(tester);
      expect(find.byType(GuideScreen), findsOneWidget);
      expect(find.byType(GuidePhoneList), findsOneWidget);
      expect(find.text(l10n.guideRefresh), findsNothing); // icon button
      expect(find.byTooltip(l10n.guideRefresh), findsOneWidget);

      // Filter chips: All channels (selected), News, Sports.
      final all = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('guide-chip-0')),
      );
      expect(all.selected, isTrue);
      expect(find.text('News'), findsOneWidget);

      // Rows show what is on now.
      expect(find.byType(ChannelTile), findsWidgets);
      expect(find.text(progTitle(1, 0)), findsOneWidget);
      expect(find.text(progTitle(2, 0)), findsOneWidget);

      // Channel 1 -> its schedule for today, the programme on air marked.
      await tester.tap(find.text('Channel 1'));
      await _navigate(tester);
      expect(find.byType(GuideSchedulePage), findsOneWidget);
      expect(find.byType(GuidePhoneList), findsNothing); // covered
      expect(_inSchedule(find.text(l10n.guideToday)), findsOneWidget);
      expect(_inSchedule(find.text(progTitle(1, 0))), findsOneWidget);
      expect(_inSchedule(find.textContaining(l10n.guideNow)), findsOneWidget);
      // Today's earlier programmes are listed too (15:00 local onward).
      expect(_inSchedule(find.text(progTitle(1, -3))), findsOneWidget);

      // A later programme shows its details.
      await tester.tap(_inSchedule(find.text(progTitle(1, 2))));
      await settle(tester);
      expect(find.byKey(const ValueKey('guide-info')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('guide-info')),
          matching: find.text('About ${progTitle(1, 2)}'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('guide-info-close')));
      await settle(tester);
      expect(find.byKey(const ValueKey('guide-info')), findsNothing);
      expect(player.requests, isEmpty);

      // The one on air plays the channel, zapping through all channels.
      await tester.tap(_inSchedule(find.text(progTitle(1, 0))));
      await settle(tester);
      final request = player.requests.single;
      expect(request.sourceId, seeded.sourceId);
      expect(request.item.key, 'c1');
      expect(request.categoryKey, isNull);

      // Tomorrow: programmes after local midnight.
      await tester.tap(_inSchedule(find.text(l10n.guideTomorrow)));
      await settle(tester);
      expect(_inSchedule(find.text(progTitle(1, 0))), findsNothing);
      expect(_inSchedule(find.text(progTitle(1, 6))), findsOneWidget);

      // Back closes the schedule.
      await tester.binding.handlePopRoute();
      await _navigate(tester);
      expect(find.byType(GuideSchedulePage), findsNothing);
      expect(find.byType(GuidePhoneList), findsOneWidget);
      await disposeApp(tester, db);
    });
  }

  testWidgets('the schedule follows the clock', (tester) async {
    final db = openGuideDb();
    await seedGuide(db);
    final clock = FakeClock(guideNow); // 18:47
    final player = PlayerLog();
    await pumpGuideApp(
      tester,
      db: db,
      player: player,
      caps: phoneCaps,
      clock: clock,
    );
    await _openGuideTab(tester);
    // Channel 2 has half-hour programmes: 18:30-19:00 is on air.
    await tester.tap(find.text('Channel 2'));
    await _navigate(tester);
    expect(_inSchedule(find.textContaining(en.guideMinutesLeft(13))), findsOne);

    // 19:07: the next one is on air. A tap decides by the time of the tap.
    clock.advance(const Duration(minutes: 20));
    await tester.tap(_inSchedule(find.text(progTitle(2, 1))));
    await settle(tester);
    expect(find.byKey(const ValueKey('guide-info')), findsNothing);
    expect(player.requests.single.item.key, 'c2');

    // The highlight moves with the clock.
    await tester.pump(const Duration(seconds: 30));
    await settle(tester);
    expect(_inSchedule(find.textContaining(en.guideMinutesLeft(23))), findsOne);
    expect(
      _inSchedule(find.textContaining(en.guideMinutesLeft(13))),
      findsNothing,
    );
    await tester.tap(_inSchedule(find.text(progTitle(2, 0))));
    await settle(tester);
    expect(find.byKey(const ValueKey('guide-info')), findsOneWidget);
    expect(player.requests, hasLength(1));
    await disposeApp(tester, db);
  });

  testWidgets('favourites: the whole list is the zap list', (tester) async {
    final db = openGuideDb();
    await seedGuide(db, favorites: ['c3', 'gone', 'c1']);
    final player = PlayerLog();
    await pumpGuideApp(tester, db: db, player: player, caps: phoneCaps);
    await _openGuideTab(tester);
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('guide-chip-0')),
    );
    expect(chip.selected, isTrue);
    expect(find.text(en.liveFavorites), findsOneWidget);
    await tester.tap(find.text('Channel 1'));
    await _navigate(tester);
    await tester.tap(find.byKey(const ValueKey('guide-schedule-play')));
    await settle(tester);
    expect(player.requests.single.item.key, 'c1');
    expect(player.requests.single.zapKeys, ['c3', 'c1']);
    await disposeApp(tester, db);
  });

  testWidgets('a category chip narrows the list; its zap list', (tester) async {
    final db = openGuideDb();
    await seedGuide(db);
    final player = PlayerLog();
    await pumpGuideApp(tester, db: db, player: player, caps: phoneCaps);
    await _openGuideTab(tester);
    await tester.tap(find.text('Sports'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 200));
    await settle(tester);
    expect(find.text('Channel 1'), findsNothing);
    expect(find.text('Channel 11'), findsOneWidget);
    expect(find.text(progTitle(11, 0)), findsOneWidget);
    await tester.tap(find.text('Channel 11'));
    await _navigate(tester);
    await tester.tap(find.byKey(const ValueKey('guide-schedule-play')));
    await settle(tester);
    expect(player.requests.single.item.key, 'c11');
    expect(player.requests.single.categoryKey, 'sports');
    await disposeApp(tester, db);
  });

  testWidgets('no guide data on the phone', (tester) async {
    final db = openGuideDb();
    await seedGuide(db, guide: false);
    final epg = FakeEpgService();
    await pumpGuideApp(
      tester,
      db: db,
      player: PlayerLog(),
      caps: phoneCaps,
      epg: epg,
    );
    await _openGuideTab(tester);
    expect(find.text(en.guideEmpty), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guide-empty-refresh')));
    await settle(tester);
    expect(epg.calls.single.force, isTrue);
    expect(find.text(en.guideUpdating), findsOneWidget);
    await disposeApp(tester, db);
  });

  testWidgets('a channel without programmes offers to watch it', (
    tester,
  ) async {
    final db = openGuideDb();
    await seedGuide(db, withGuide: 1);
    final player = PlayerLog();
    await pumpGuideApp(tester, db: db, player: player, caps: phoneCaps);
    await _openGuideTab(tester);
    expect(find.text(en.liveNoProgrammeInfo), findsWidgets); // channel 2..
    await tester.tap(find.text('Channel 2'));
    await _navigate(tester);
    expect(_inSchedule(find.text(en.liveNoProgrammeInfo)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guide-schedule-watch')));
    await settle(tester);
    expect(player.requests.single.item.key, 'c2');
    await disposeApp(tester, db);
  });
}
