// The live player's channel panel: browsing the Live screen's lists and
// switching channel without leaving the player (remote, mouse and touch).
// All data is synthetic (127.0.0.1 URLs, made-up names).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/live/channel_list.dart';
import 'package:iptv_player/features/live/live_models.dart';
import 'package:iptv_player/player/ui/channel_panel.dart';
import 'package:iptv_player/player/ui/play_request.dart';
import 'package:iptv_player/player/ui/player_screen.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/widgets/channel_tile.dart';

import 'support/player_harness.dart';

const _panel = ValueKey('channel-panel');
const _osd = ValueKey('player-osd');

String _url(String key) => 'http://127.0.0.1:9/live/$key.ts';

/// An M3U source with channels `ch1..chN` ("Channel N", numbers 101...) in
/// category News and `sp1..spM` ("Sport N", numbers 201...) in Sports.
Future<int> _seed(PlayerRig rig, {int news = 5, int sports = 3}) async {
  final db = rig.db;
  final id = await db.sourcesDao.create(
    const SourceConfig(
      kind: SourceKind.m3uUrl,
      url: 'http://127.0.0.1:9/list.m3u',
      name: 'Home',
    ),
  );
  final gen = await db.catalogDao.beginGeneration(id);
  await db.catalogDao.upsertCategories(id, gen, const [
    CategoryData(kind: ContentKind.live, key: 'news', name: 'News'),
    CategoryData(kind: ContentKind.live, key: 'sports', name: 'Sports'),
  ]);
  await db.catalogDao.upsertChannels(id, gen, [
    for (var i = 1; i <= news; i++)
      ChannelData(
        key: 'ch$i',
        name: 'Channel $i',
        num: 100 + i,
        url: _url('ch$i'),
        categoryKeys: const ['news'],
      ),
    for (var i = 1; i <= sports; i++)
      ChannelData(
        key: 'sp$i',
        name: 'Sport $i',
        num: 200 + i,
        url: _url('sp$i'),
        categoryKeys: const ['sports'],
      ),
  ]);
  await db.catalogDao.commitGeneration(id, gen);
  return id;
}

/// The request the Live screen builds for [key] in [category].
PlayRequest _request(int sourceId, String key, {String category = 'news'}) =>
    PlayRequest(
      sourceId: sourceId,
      item: PlayableRef(kind: PlayableKind.live, key: key, url: _url(key)),
      categoryKey: category,
      list: LiveList.category(category),
    );

Finder _inPanel(String text) =>
    find.descendant(of: find.byKey(_panel), matching: find.text(text));

Finder _inBanner(String text) => find.descendant(
  of: find.byKey(const ValueKey('player-banner')),
  matching: find.text(text),
);

bool _rowFocused(int index) => focusedIn(ValueKey('channel-row-$index'));

bool _categoryFocused(String id) => focusedIn(ValueKey('live-category-$id'));

ChannelTile _tile(WidgetTester tester, int index) =>
    tester.widget<ChannelTile>(find.byKey(ValueKey('channel-row-$index')));

ChannelPanelState _panelState(WidgetTester tester) =>
    tester.state<ChannelPanelState>(find.byType(ChannelPanel));

/// Zaps with [key] and waits for the debounce.
Future<void> _zap(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump(const Duration(milliseconds: 400));
  await settle(tester);
}

/// Presses OK on the focused channel and waits for it to open.
Future<void> _pick(WidgetTester tester) async {
  await press(tester, LogicalKeyboardKey.select);
  await tester.pump(const Duration(milliseconds: 400));
  await settle(tester);
}

Future<void> _wheel(WidgetTester tester, Offset at, double dy) async {
  final mouse = TestPointer(9, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(mouse.hover(at));
  await tester.sendEventToBinding(mouse.scroll(Offset(0, dy)));
  await settle(tester);
}

double _scrollOf(WidgetTester tester, Finder list) => tester
    .state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    )
    .position
    .pixels;

void main() {
  group('remote', () {
    forLocales((locale) {
      final rtl = locale == ar;
      // Towards the categories (the reading start) and back.
      final toStart = rtl
          ? LogicalKeyboardKey.arrowRight
          : LogicalKeyboardKey.arrowLeft;
      final toEnd = rtl
          ? LogicalKeyboardKey.arrowLeft
          : LogicalKeyboardKey.arrowRight;

      testWidgets('OK opens the panel on the playing channel; a channel of '
          'another category plays and zapping follows that category '
          '(${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await _seed(rig);
        await pumpPlayerApp(tester, rig, locale: locale);
        await openPlayerFor(tester, _request(id, 'ch2'));
        await tester.pump(const Duration(seconds: 5));

        await press(tester, LogicalKeyboardKey.select);
        expect(find.byKey(_panel), findsOneWidget);
        expect(find.byKey(_osd), findsNothing);
        // At the start edge: left in English, right in Arabic; on TV a
        // wider share of the 960 dp canvas plus the overscan margin.
        final rect = tester.getRect(find.byKey(_panel));
        expect(rtl ? rect.right : rect.left, rtl ? 960 : 0);
        expect(rect.width, 960 * ChannelPanel.tvWidthFraction + 48);
        // News, on the channel playing (highlighted).
        expect(_panelState(tester).selected, const LiveList.category('news'));
        expect(_rowFocused(1), isTrue);
        expect(_tile(tester, 1).selected, isTrue);
        expect(_inPanel('Channel 2'), findsOneWidget);
        expect(_inPanel('Sports'), findsOneWidget);

        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(_rowFocused(2), isTrue);
        await press(tester, LogicalKeyboardKey.arrowUp);
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(_rowFocused(0), isTrue);
        // Nothing was tuned while moving.
        expect(rig.openedUrls, [_url('ch2')]);

        // To the categories and back (mirrored in Arabic).
        await press(tester, toStart);
        expect(_categoryFocused('cat:news'), isTrue);
        await press(tester, toEnd);
        expect(_rowFocused(0), isTrue);
        await press(tester, toStart);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(_categoryFocused('cat:sports'), isTrue);

        // OK shows Sports and moves to its channels.
        await press(tester, LogicalKeyboardKey.select);
        expect(_panelState(tester).selected, const LiveList.category('sports'));
        expect(_inPanel('Sport 1'), findsOneWidget);
        expect(_rowFocused(0), isTrue);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(_rowFocused(1), isTrue);
        await _pick(tester);

        expect(find.byKey(_panel), findsNothing);
        expect(focusLabel, 'player');
        expect(rig.openedUrls, [_url('ch2'), _url('sp2')]);
        expect(rig.played.map((p) => p.$2), ['ch2', 'sp2']);
        expect(_inBanner('Sport 2'), findsOneWidget);
        expect(_inBanner('202'), findsOneWidget);

        // Zapping walks Sports now (wrapping around), never News.
        await _zap(tester, LogicalKeyboardKey.arrowUp);
        expect(rig.openedUrls.last, _url('sp3'));
        await _zap(tester, LogicalKeyboardKey.arrowUp);
        expect(rig.openedUrls.last, _url('sp1'));
        await _zap(tester, LogicalKeyboardKey.arrowDown);
        expect(rig.openedUrls.last, _url('sp3'));
        // Numbers too; a lone 0 returns to the channel before.
        await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
        await press(tester, LogicalKeyboardKey.select);
        expect(rig.openedUrls.last, _url('sp1'));

        // Reopened, the panel shows Sports on the channel playing.
        await press(tester, LogicalKeyboardKey.select);
        expect(_panelState(tester).selected, const LiveList.category('sports'));
        expect(_rowFocused(0), isTrue);
        expect(_tile(tester, 0).selected, isTrue);

        // One engine: every switch stopped the stream before the next.
        expect(rig.engines.created, hasLength(1));
        expect(rig.engine.count('stop'), rig.openedUrls.length - 1);
        await disposeRig(tester, rig);
      });

      testWidgets('Back closes the panel without tuning; it closes by '
          'itself after 15 s without a key (${locale.languageCode})', (
        tester,
      ) async {
        final rig = PlayerRig()..autoPlay();
        final id = await _seed(rig);
        await pumpPlayerApp(tester, rig, locale: locale);
        await openPlayerFor(tester, _request(id, 'ch1'));

        await press(tester, LogicalKeyboardKey.select);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(_rowFocused(1), isTrue);
        // Focusing a category shows its channels after a pause, without
        // moving focus or tuning.
        await press(tester, toStart);
        await press(tester, LogicalKeyboardKey.arrowDown);
        await tester.pump(ChannelPanel.selectDelay);
        await settle(tester);
        expect(_inPanel('Sport 1'), findsOneWidget);
        expect(_categoryFocused('cat:sports'), isTrue);

        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(find.byKey(_panel), findsNothing);
        expect(find.byType(PlayerScreen), findsOneWidget);
        expect(focusLabel, 'player');
        await tester.pump(const Duration(seconds: 1));
        expect(rig.openedUrls, [_url('ch1')]);
        // Zapping still walks News.
        await _zap(tester, LogicalKeyboardKey.arrowUp);
        expect(rig.openedUrls.last, _url('ch2'));

        // Any key, also one the panel handles itself, restarts its timer.
        await press(tester, LogicalKeyboardKey.select);
        expect(find.byKey(_panel), findsOneWidget);
        await tester.pump(const Duration(seconds: 14));
        expect(find.byKey(_panel), findsOneWidget);
        await press(tester, LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(seconds: 14));
        expect(find.byKey(_panel), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        await settle(tester);
        expect(find.byKey(_panel), findsNothing);
        expect(focusLabel, 'player');
        expect(rig.openedUrls.last, _url('ch2'));

        // Back closes the player once the panel is gone.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(PlayerScreen), findsNothing);
        await disposeRig(tester, rig);
      });
    });

    testWidgets('keys the panel does not use never zap or type numbers', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await _seed(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, _request(id, 'ch1'));
      await press(tester, LogicalKeyboardKey.select);
      // In the categories: CH+/CH-, digits, Info and Menu do nothing.
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(_categoryFocused('cat:news'), isTrue);
      for (final key in [
        LogicalKeyboardKey.channelUp,
        LogicalKeyboardKey.channelDown,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.info,
        LogicalKeyboardKey.contextMenu,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('player-number-badge')), findsNothing);
      expect(_categoryFocused('cat:news'), isTrue);
      // In the channels: digits jump to that number in the list.
      await press(tester, LogicalKeyboardKey.arrowRight);
      for (final key in [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit0,
        LogicalKeyboardKey.digit4,
      ]) {
        await tester.sendKeyEvent(key);
      }
      await tester.pump(ChannelList.digitDelay);
      await settle(tester);
      expect(_rowFocused(3), isTrue);
      expect(find.byKey(_panel), findsOneWidget);
      expect(rig.openedUrls, [_url('ch1')]);
      await disposeRig(tester, rig);
    });

    testWidgets('a lone 0 after a pick returns to the channel before it', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await _seed(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, _request(id, 'ch2'));
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await _pick(tester);
      expect(rig.openedUrls.last, _url('sp2'));
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await press(tester, LogicalKeyboardKey.select);
      expect(rig.openedUrls.last, _url('ch2'));
      expect(_inBanner('Channel 2'), findsOneWidget);
      // Back again: zapping still walks Sports, from its first channel.
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await press(tester, LogicalKeyboardKey.select);
      expect(rig.openedUrls.last, _url('sp2'));
      await _zap(tester, LogicalKeyboardKey.arrowUp);
      expect(rig.openedUrls.last, _url('sp3'));
      expect(rig.engine.count('stop'), rig.openedUrls.length - 1);
      await disposeRig(tester, rig);
    });

    testWidgets('the Channels option of the Menu key opens the panel', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await _seed(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, _request(id, 'ch3'));
      await press(tester, LogicalKeyboardKey.contextMenu);
      expect(find.text('Options'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('player-choice-0')),
          matching: find.text('Channels'),
        ),
        findsOneWidget,
      );
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byKey(_panel), findsOneWidget);
      expect(_rowFocused(2), isTrue);
      await disposeRig(tester, rig);
    });

    testWidgets('movies keep OK for the OSD and have no Channels', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay(duration: const Duration(minutes: 90));
      final id = await seedVod(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, movieRequest(id));
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byKey(_osd), findsOneWidget);
      expect(find.byKey(_panel), findsNothing);
      expect(find.byKey(const ValueKey('player-osd-channels')), findsNothing);
      await disposeRig(tester, rig);
    });
  });

  group('lists', () {
    testWidgets('Favorites and the user\'s lists are in the panel; zapping '
        'follows the list a channel was picked from', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await _seed(rig);
      final favorites = rig.db.favoritesDao;
      await favorites.setFavorite(id, ContentKind.live, 'ch4', true);
      await favorites.setFavorite(id, ContentKind.live, 'sp1', true);
      await rig.db.channelListsDao.createList(
        id,
        'Evening',
        channels: ['ch5', 'gone', 'ch1'],
      );
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, _request(id, 'ch1'));

      await press(tester, LogicalKeyboardKey.select);
      // Favourites carry their star in every list.
      expect(_tile(tester, 3).isFavorite, isTrue);
      expect(_tile(tester, 2).isFavorite, isFalse);
      // Favorites, Evening, Recent, All channels, News, Sports.
      await press(tester, LogicalKeyboardKey.arrowLeft);
      for (var i = 0; i < 4; i++) {
        await press(tester, LogicalKeyboardKey.arrowUp);
      }
      expect(_categoryFocused('fav'), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(_panelState(tester).selected, const LiveList.favorites());
      expect(_inPanel('Channel 4'), findsOneWidget);
      expect(_inPanel('Sport 1'), findsOneWidget);
      expect(_rowFocused(0), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await _pick(tester);
      expect(rig.openedUrls, [_url('ch1'), _url('sp1')]);
      // Zapping walks the favourites only.
      await _zap(tester, LogicalKeyboardKey.arrowUp);
      expect(rig.openedUrls.last, _url('ch4'));
      await _zap(tester, LogicalKeyboardKey.arrowUp);
      expect(rig.openedUrls.last, _url('sp1'));

      // The panel reopens on Favorites, on the channel playing.
      await press(tester, LogicalKeyboardKey.select);
      expect(_panelState(tester).selected, const LiveList.favorites());
      expect(_rowFocused(1), isTrue);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(_categoryFocused('fav'), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(_categoryFocused('list:1'), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      // The list's gone channel shows as unavailable and plays nothing.
      expect(_inPanel('Unavailable'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await _pick(tester);
      expect(find.byKey(_panel), findsOneWidget);
      expect(rig.openedUrls.last, _url('sp1'));
      await press(tester, LogicalKeyboardKey.arrowDown);
      await _pick(tester);
      expect(find.byKey(_panel), findsNothing);
      expect(rig.openedUrls.last, _url('ch1'));
      // Zapping walks the list's available channels.
      await _zap(tester, LogicalKeyboardKey.arrowUp);
      expect(rig.openedUrls.last, _url('ch5'));
      await _zap(tester, LogicalKeyboardKey.arrowUp);
      expect(rig.openedUrls.last, _url('ch1'));
      expect(rig.engine.count('stop'), rig.openedUrls.length - 1);
      await disposeRig(tester, rig);
    });

    testWidgets('Menu on a channel adds it to the favourites', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await _seed(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, _request(id, 'ch1'));
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.contextMenu);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Channel 3'),
        ),
        findsOneWidget,
      );
      expect(focusedIn(const ValueKey('player-choice-0')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(
        await rig.db.favoritesDao.isFavorite(id, ContentKind.live, 'ch3'),
        isTrue,
      );
      expect(find.text('Added to favorites'), findsOneWidget);
      // Back in the panel, on the same channel, now starred.
      expect(find.byKey(_panel), findsOneWidget);
      expect(_rowFocused(2), isTrue);
      expect(_tile(tester, 2).isFavorite, isTrue);
      expect(rig.openedUrls, [_url('ch1')]);
      await disposeRig(tester, rig);
    });

    testWidgets('a large category stays paged in the panel', (tester) async {
      final queries = QueryCounter();
      final rig = PlayerRig(queries: queries)..autoPlay();
      final id = await seedLive(rig, count: 5000);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id, key: 'ch2500'));
      await settle(tester);
      queries.reset();

      await press(tester, LogicalKeyboardKey.select);
      await settle(tester);
      expect(_rowFocused(2499), isTrue);
      final pager = _panelState(tester).channelList!.pager!;
      expect(pager.length, 5000);
      expect(pager.loadedPages.length, lessThanOrEqualTo(2));
      for (var i = 0; i < 5; i++) {
        await press(tester, LogicalKeyboardKey.pageDown);
      }
      expect(pager.loadedPages.length, lessThanOrEqualTo(3));

      // All channels (5000 too), on the channel playing.
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(_categoryFocused('all'), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      await settle(tester);
      expect(_rowFocused(2499), isTrue);
      // Picking the channel playing keeps the stream; zapping now walks
      // All channels.
      await _pick(tester);
      expect(find.byKey(_panel), findsNothing);
      expect(rig.openedUrls, [_url('ch2500')]);
      await _zap(tester, LogicalKeyboardKey.arrowUp);
      expect(rig.openedUrls.last, _url('ch2501'));
      // No read returned more than one page of the 5000 channels.
      expect(queries.maxRows, lessThanOrEqualTo(ChannelList.pageSize));
      await disposeRig(tester, rig);
    });

    testWidgets('quick moves through the categories show only the last one', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await _seed(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, _request(id, 'ch1'));
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      // News -> All channels -> Recent -> All channels -> News -> Sports,
      // faster than the pause.
      for (final key in [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(_panelState(tester).selected, const LiveList.category('news'));
      await tester.pump(ChannelPanel.selectDelay);
      await settle(tester);
      expect(_panelState(tester).selected, const LiveList.category('sports'));
      expect(_inPanel('Sport 3'), findsOneWidget);
      expect(_categoryFocused('cat:sports'), isTrue);
      await disposeRig(tester, rig);
    });
  });

  testWidgets('a player removed with the panel open leaves no timer behind', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final id = await _seed(rig);
    await seedGuide(rig, id);
    await pumpPlayerApp(
      tester,
      rig,
      tv: false,
      platform: TargetPlatform.windows,
    );
    await openPlayerFor(tester, _request(id, 'ch1'));
    await press(tester, LogicalKeyboardKey.select);
    // A category pending its pause and a row's now/next being read.
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.byKey(_panel), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await rig.db.close();
    // The test framework fails here if a timer is still pending.
  });

  group('one connection', () {
    testWidgets('a channel picked on a single-connection panel opens only '
        'after the one playing stopped', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedXtream(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, xtreamRequest(id, '501'));
      await tester.pump(const Duration(seconds: 1));
      await press(tester, LogicalKeyboardKey.select);
      expect(_rowFocused(0), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      // A zap right away (no frame for the new list yet) opens nothing
      // more than one stream at a time.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      final urls = rig.openedUrls;
      expect(urls.first, endsWith('/501.ts'));
      expect(urls[1], endsWith('/502.ts'));
      expect(rig.engines.maxAlive, 1);
      final calls = [
        for (final c in rig.engine.calls)
          if (c == 'open' || c == 'stop') c,
      ];
      // Every open after the first comes right after a stop.
      for (var i = 1; i < calls.length; i++) {
        if (calls[i] == 'open') expect(calls[i - 1], 'stop');
      }
      expect(rig.engine.count('stop'), urls.length - 1);
      await disposeRig(tester, rig);
    });
  });

  group('mouse and touch', () {
    testWidgets('desktop: the OSD button opens it; the wheel scrolls; '
        'clicks pick a category and a channel; a click beside it closes it', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await _seed(rig, news: 40);
      await pumpPlayerApp(
        tester,
        rig,
        tv: false,
        platform: TargetPlatform.windows,
      );
      await openPlayerFor(tester, _request(id, 'ch1'));
      await tester.pump(const Duration(seconds: 1));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(640, 360));
      await mouse.moveTo(const Offset(650, 360));
      await settle(tester);
      expect(find.byKey(_osd), findsOneWidget);
      expect(focusLabel, 'player');

      Future<void> openFromOsd() async {
        if (find.byKey(_osd).evaluate().isEmpty) {
          await mouse.moveTo(const Offset(660, 360));
          await settle(tester);
        }
        await tester.tap(
          find.byKey(const ValueKey('player-osd-channels')),
          kind: PointerDeviceKind.mouse,
        );
        await settle(tester);
        // Clicks right after opening are ignored (a double click).
        await tester.pump(ChannelPanel.openGuard);
        await tester.pump();
        expect(find.byKey(_panel), findsOneWidget);
      }

      await openFromOsd();
      expect(find.byKey(_osd), findsNothing);
      expect(tester.getSize(find.byKey(_panel)).width, ChannelPanel.maxWidth);
      // The keyboard moved into the panel too.
      expect(_rowFocused(0), isTrue);
      // Moving the mouse never brings the OSD back over the panel.
      await mouse.moveTo(const Offset(900, 300));
      await settle(tester);
      expect(find.byKey(_osd), findsNothing);

      // The wheel scrolls the channels.
      final list = find.descendant(
        of: find.byKey(_panel),
        matching: find.byType(ListView),
      );
      final channels = list.last;
      expect(_scrollOf(tester, channels), 0);
      await _wheel(tester, tester.getCenter(channels), 400);
      expect(_scrollOf(tester, channels), greaterThan(0));
      expect(find.byKey(_panel), findsOneWidget);

      // A click on a channel plays it.
      await tester.tap(
        find.byKey(const ValueKey('channel-row-10')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(find.byKey(_panel), findsNothing);
      expect(rig.openedUrls, [_url('ch1'), _url('ch11')]);

      // A click on a category shows its channels; zapping follows it.
      await openFromOsd();
      await tester.tap(
        find.byKey(const ValueKey('live-category-cat:sports')),
        kind: PointerDeviceKind.mouse,
      );
      await settle(tester);
      expect(_inPanel('Sport 2'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('channel-row-1')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(rig.openedUrls, [_url('ch1'), _url('ch11'), _url('sp2')]);
      await _zap(tester, LogicalKeyboardKey.arrowUp);
      expect(rig.openedUrls.last, _url('sp3'));

      // Moving the mouse keeps the panel up; a click beside it closes it,
      // playing nothing.
      await openFromOsd();
      await tester.pump(const Duration(seconds: 14));
      await mouse.moveTo(const Offset(1000, 300));
      await tester.pump(const Duration(seconds: 14));
      expect(find.byKey(_panel), findsOneWidget);
      await tester.tapAt(
        const Offset(1000, 360),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(find.byKey(_panel), findsNothing);
      expect(find.byKey(_osd), findsNothing);
      expect(rig.openedUrls.last, _url('sp3'));
      final played = rig.openedUrls.length;

      // Escape closes the panel before it leaves window fullscreen; the
      // close button closes it too.
      expect(rig.window, ['enter']);
      await openFromOsd();
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byKey(_panel), findsNothing);
      expect(rig.window, ['enter']);
      expect(find.byType(PlayerScreen), findsOneWidget);
      await openFromOsd();
      await tester.tap(
        find.byKey(const ValueKey('channel-panel-close')),
        kind: PointerDeviceKind.mouse,
      );
      await settle(tester);
      expect(find.byKey(_panel), findsNothing);
      expect(focusLabel, 'player');
      expect(rig.openedUrls, hasLength(played));
      expect(rig.engine.count('stop'), played - 1);
      await disposeRig(tester, rig);
    });

    testWidgets('phone: the panel covers the screen; a tap plays, the close '
        'button closes', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await _seed(rig);
      await pumpPlayerApp(tester, rig, tv: false);
      await openPlayerFor(tester, _request(id, 'ch1'));

      Future<void> openFromOsd() async {
        await tester.tapAt(const Offset(195, 400));
        await tester.pump(const Duration(milliseconds: 400));
        await settle(tester);
        expect(find.byKey(_osd), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('player-osd-channels')));
        await settle(tester);
        await tester.pump(ChannelPanel.openGuard);
        await tester.pump();
        expect(find.byKey(_panel), findsOneWidget);
      }

      await openFromOsd();
      expect(tester.getSize(find.byKey(_panel)), const Size(390, 800));
      await tester.tap(find.byKey(const ValueKey('channel-row-3')));
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(find.byKey(_panel), findsNothing);
      expect(rig.openedUrls, [_url('ch1'), _url('ch4')]);

      await openFromOsd();
      await tester.tap(find.byKey(const ValueKey('channel-panel-close')));
      await settle(tester);
      expect(find.byKey(_panel), findsNothing);
      expect(rig.openedUrls, [_url('ch1'), _url('ch4')]);
      await disposeRig(tester, rig);
    });
  });
}
