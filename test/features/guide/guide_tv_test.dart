// The guide grid on a 1920x1080 TV, driven with the remote in English
// (LTR) and Arabic (RTL).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/epg/epg_progress.dart';
import 'package:iptv_player/features/guide/guide_grid.dart';
import 'package:iptv_player/features/guide/guide_model.dart';
import 'package:iptv_player/features/guide/guide_screen.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/tv/dpad_shortcuts.dart';
import 'package:iptv_player/widgets/bidi_text.dart';

import 'support/guide_fixtures.dart';

const _railGuide = ValueKey('rail-guide');
const _title = ValueKey('guide-info-title');

String? _infoTitle(WidgetTester tester) =>
    tester.widget<BidiText>(find.byKey(_title)).text;

bool get _gridFocused =>
    FocusManager.instance.primaryFocus?.debugLabel == 'guide-grid';

GuideGridState _grid(WidgetTester tester) =>
    tester.state<GuideGridState>(find.byType(GuideGrid));

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  for (final rtl in [false, true]) {
    final name = rtl ? 'ar (RTL)' : 'en';
    final l10n = rtl ? ar : en;
    // Toward the content / later in time, and the reverse.
    final forward = rtl
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight;
    final back = rtl
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;

    Future<void> openGuide(WidgetTester tester) async {
      await press(tester, LogicalKeyboardKey.arrowDown); // rail: Guide
      expect(focusedIn(_railGuide), isTrue);
      expect(find.byType(GuideScreen), findsOneWidget);
      await press(tester, forward); // into the page
    }

    testWidgets('$name: rows, programmes, window and the rail', (tester) async {
      final db = openGuideDb();
      await seedGuide(db);
      final player = PlayerLog();
      await pumpGuideApp(tester, db: db, player: player, rtl: rtl);
      await openGuide(tester);

      // Entering the page focuses the grid at now on the first channel.
      expect(_gridFocused, isTrue);
      expect(_infoTitle(tester), progTitle(1, 0));
      // Channel (isolated, keeps its own direction), times, minutes left.
      final head = tester
          .widget<Text>(find.byKey(const ValueKey('guide-info-head')))
          .data!;
      expect(head, startsWith('\u2068101  Channel 1\u2069'));
      expect(head, endsWith(l10n.guideMinutesLeft(13)));
      expect(find.text(l10n.navGuide), findsNWidgets(2)); // rail + title
      // Last update, with Western digits in Arabic too.
      final updated = tester
          .widget<Text>(find.byKey(const ValueKey('guide-updated')))
          .data!;
      expect(updated, contains('2026'));
      expect(updated, contains('15'));
      expect(find.text(l10n.guideToday), findsOneWidget);

      // The channel column is on the start side.
      final channelX = tester.getCenter(find.text('Channel 1')).dx;
      final headerX = tester
          .getCenter(find.byKey(const ValueKey('guide-header')))
          .dx;
      expect(rtl ? channelX > headerX : channelX < headerX, isTrue);

      // Down keeps the time: channel 2's half-hour slot at 18:47.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(_infoTitle(tester), progTitle(2, 0));
      expect(_grid(tester).position.row, 1);

      // Forward in time (Right in LTR, Left in RTL): the next programme.
      await press(tester, forward);
      expect(_infoTitle(tester), progTitle(2, 1));
      final anchor = _grid(tester).position.anchor;
      expect(anchor, guideViewStart.add(const Duration(minutes: 30)));

      // Up keeps the anchor (19:00): channel 1's 19:00 programme.
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(_infoTitle(tester), progTitle(1, 1));

      // Back in time to the programme on air (window unchanged), then the
      // one before it (17:30-18:00 after the hour of browsable past): the
      // window scrolls back just enough to show it.
      await press(tester, back);
      expect(_infoTitle(tester), progTitle(1, 0));
      expect(_grid(tester).position.viewStart, guideViewStart);
      await press(tester, back);
      expect(_infoTitle(tester), progTitle(1, -1));
      expect(
        _grid(tester).position.viewStart,
        guideViewStart.subtract(GuideTimes.past),
      );

      // Nothing earlier: a fresh press leaves for the rail (mirrored).
      await press(tester, back);
      expect(focusedIn(_railGuide), isTrue);

      // Coming back lands on the same programme.
      await press(tester, forward);
      expect(_gridFocused, isTrue);
      expect(_infoTitle(tester), progTitle(1, -1));

      // Back returns to now first, then the shell takes focus to the rail.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(_gridFocused, isTrue);
      expect(_infoTitle(tester), progTitle(1, 0));
      expect(_grid(tester).position.viewStart, guideViewStart);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(focusedIn(_railGuide), isTrue);
      expect(player.requests, isEmpty);
      await disposeApp(tester, db);
    });

    testWidgets('$name: OK plays the programme on air, else shows it', (
      tester,
    ) async {
      final db = openGuideDb();
      final seeded = await seedGuide(db);
      final player = PlayerLog();
      await pumpGuideApp(tester, db: db, player: player, rtl: rtl);
      await openGuide(tester);

      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      final request = player.requests.single;
      expect(request.sourceId, seeded.sourceId);
      expect(request.item.key, 'c2');
      expect(request.isLive, isTrue);
      expect(request.title, 'Channel 2');
      // All channels: the player zaps through the whole source.
      expect(request.categoryKey, isNull);
      expect(request.zapKeys, isNull);

      // A later programme shows its details; Close is focused.
      await press(tester, forward);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byKey(const ValueKey('guide-info')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('guide-info')),
          matching: find.text('About ${progTitle(2, 1)}'),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.guideWatchChannel), findsOneWidget);
      expect(focusedIn(const ValueKey('guide-info-close')), isTrue);
      expect(player.requests, hasLength(1));
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byKey(const ValueKey('guide-info')), findsNothing);
      expect(_gridFocused, isTrue);

      // "Watch channel" in the details plays the channel.
      await press(tester, menuKey);
      expect(find.byKey(const ValueKey('guide-info')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('guide-info-watch')));
      await settle(tester);
      expect(player.requests, hasLength(2));
      expect(player.requests.last.item.key, 'c2');
      await disposeApp(tester, db);
    });
  }

  testWidgets('a held OK shows the programme on air instead of playing it', (
    tester,
  ) async {
    // Remotes without a Menu or Info key reach the details this way.
    final db = openGuideDb();
    await seedGuide(db);
    final player = PlayerLog();
    await pumpGuideApp(tester, db: db, player: player, rtl: false);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(_gridFocused, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    for (var i = 0; i < 10; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await settle(tester);
    expect(find.byKey(const ValueKey('guide-info')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('guide-info')),
        matching: find.text('About ${progTitle(1, 0)}'),
      ),
      findsOneWidget,
    );
    expect(player.requests, isEmpty);
    await press(tester, LogicalKeyboardKey.select); // Close
    expect(find.byKey(const ValueKey('guide-info')), findsNothing);

    // A short press still plays it.
    await press(tester, LogicalKeyboardKey.select);
    expect(player.requests.single.item.key, 'c1');
    await disposeApp(tester, db);
  });

  testWidgets('a channel without guide data plays on OK', (tester) async {
    final db = openGuideDb();
    await seedGuide(db, withGuide: 1);
    final player = PlayerLog();
    await pumpGuideApp(tester, db: db, player: player);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(_infoTitle(tester), en.liveNoProgrammeInfo);
    await press(tester, LogicalKeyboardKey.select);
    expect(player.requests.single.item.key, 'c2');
    await disposeApp(tester, db);
  });

  testWidgets('Up from the first row reaches the header; a category filter', (
    tester,
  ) async {
    final db = openGuideDb();
    await seedGuide(db);
    final player = PlayerLog();
    await pumpGuideApp(tester, db: db, player: player);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(_gridFocused, isTrue);

    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(
      focusedIn(const ValueKey('guide-filter')) ||
          focusedIn(const ValueKey('guide-refresh')),
      isTrue,
    );
    if (!focusedIn(const ValueKey('guide-filter'))) {
      await press(tester, LogicalKeyboardKey.arrowLeft);
    }
    expect(focusedIn(const ValueKey('guide-filter')), isTrue);
    expect(find.text(en.liveAllChannels), findsOneWidget);

    // The picker opens on the current choice; pick Sports.
    await press(tester, LogicalKeyboardKey.select);
    expect(focusedIn(const ValueKey('guide-filter-0')), isTrue);
    expect(find.text('News'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedIn(const ValueKey('guide-filter-2')), isTrue);
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text('Sports'), findsOneWidget); // the filter button
    expect(focusedIn(const ValueKey('guide-filter')), isTrue);

    // Back down into the grid: Sports starts with channel 11.
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(_gridFocused, isTrue);
    expect(_infoTitle(tester), progTitle(11, 0));
    await press(tester, LogicalKeyboardKey.select);
    expect(player.requests.single.item.key, 'c11');
    expect(player.requests.single.categoryKey, 'sports');
    await disposeApp(tester, db);
  });

  testWidgets('favourites come first and are the zap list', (tester) async {
    final db = openGuideDb();
    await seedGuide(db, favorites: ['c3', 'c1']);
    final player = PlayerLog();
    await pumpGuideApp(tester, db: db, player: player);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('guide-filter')),
        matching: find.text(en.liveFavorites),
      ),
      findsOneWidget,
    );
    expect(_infoTitle(tester), progTitle(3, 0));
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(_infoTitle(tester), progTitle(1, 0));
    await press(tester, LogicalKeyboardKey.select);
    expect(player.requests.single.item.key, 'c1');
    expect(player.requests.single.zapKeys, ['c3', 'c1']);

    // A favourite added elsewhere (e.g. from the player) joins the list in
    // place: the grid keeps focus and its position.
    final source = (await db.sourcesDao.all()).single.id;
    await db.favoritesDao.setFavorite(source, ContentKind.live, 'c5', true);
    await settle(tester);
    expect(_gridFocused, isTrue);
    expect(_infoTitle(tester), progTitle(1, 0));
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(_infoTitle(tester), progTitle(5, 0));
    await press(tester, LogicalKeyboardKey.select);
    expect(player.requests.last.zapKeys, ['c3', 'c1', 'c5']);
    await disposeApp(tester, db);
  });

  testWidgets('a catalog sync reloads the rows and keeps focus', (
    tester,
  ) async {
    final db = openGuideDb();
    final seeded = await seedGuide(db, channels: 5);
    await pumpGuideApp(tester, db: db, player: PlayerLog());
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(_infoTitle(tester), progTitle(2, 0));
    expect(_grid(tester).position.row, 1);

    // The sync drops channel 1: the same row now holds channel 3.
    await resyncChannels(db, seeded.sourceId, [
      for (var i = 2; i <= 6; i++) channelData(i),
    ]);
    await settle(tester);
    expect(_gridFocused, isTrue);
    expect(_grid(tester).position.row, 1);
    expect(_infoTitle(tester), progTitle(3, 0));
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(_grid(tester).position.row, 4); // five rows: 2..6
    expect(find.text('Channel 6'), findsOneWidget);
    await disposeApp(tester, db);
  });

  testWidgets('the default list stays when the first favourite is added', (
    tester,
  ) async {
    final db = openGuideDb();
    final seeded = await seedGuide(db);
    await pumpGuideApp(tester, db: db, player: PlayerLog());
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(_infoTitle(tester), progTitle(2, 0));
    await db.favoritesDao.setFavorite(
      seeded.sourceId,
      ContentKind.live,
      'c9',
      true,
    );
    await settle(tester);
    expect(_gridFocused, isTrue);
    expect(_infoTitle(tester), progTitle(2, 0)); // still All channels
    await disposeApp(tester, db);
  });

  testWidgets('no guide data: explains Settings and refreshes on OK', (
    tester,
  ) async {
    final db = openGuideDb();
    final seeded = await seedGuide(db, guide: false);
    final epg = FakeEpgService();
    await pumpGuideApp(tester, db: db, player: PlayerLog(), epg: epg);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.text(en.guideEmpty), findsOneWidget);
    expect(find.byType(GuideGrid), findsNothing);

    // Entering the page focuses Refresh.
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedIn(const ValueKey('guide-empty-refresh')), isTrue);
    await press(tester, LogicalKeyboardKey.select);
    expect(epg.calls.single.sourceId, seeded.sourceId);
    expect(epg.calls.single.force, isTrue);
    expect(find.text(en.guideUpdating), findsNWidgets(2)); // header + button
    expect(focusedIn(const ValueKey('guide-empty-refresh')), isTrue);

    // Nothing to download: the hint comes back as a snack bar.
    await epg.finish(seeded.sourceId, EpgRefreshDone(seeded.sourceId));
    await settle(tester);
    expect(find.text(en.guideUpdating), findsNothing);
    expect(find.text(en.guideEmpty), findsNWidgets(2)); // page + snack bar

    // A failed run says so.
    expect(focusedIn(const ValueKey('guide-empty-refresh')), isTrue);
    await press(tester, LogicalKeyboardKey.select);
    expect(epg.calls, hasLength(2));
    await epg.finish(
      seeded.sourceId,
      EpgRefreshFailed(seeded.sourceId, message: 'HTTP 500'),
    );
    await settle(tester);
    await tester.pump(const Duration(seconds: 1)); // the old one hides
    expect(find.text(en.guideRefreshFailed), findsOneWidget);
    await disposeApp(tester, db);
  });
}
