// The TV guide when data is slow or changes underneath it: focus while the
// page loads and when its body is replaced, the favourites list and zap
// list, the programme block around the window, and the details dialog
// outliving the grid. English and Arabic where focus moves sideways.
import 'dart:async';

import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/daos/epg_dao.dart';
import 'package:iptv_player/epg/epg_models.dart';
import 'package:iptv_player/features/guide/guide_grid.dart';
import 'package:iptv_player/features/guide/guide_model.dart';
import 'package:iptv_player/features/guide/providers.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/tv/dpad_shortcuts.dart';
import 'package:iptv_player/widgets/bidi_text.dart';
import 'package:iptv_player/widgets/states.dart';

import 'support/guide_fixtures.dart';

const _filter = ValueKey('guide-filter');
const _refresh = ValueKey('guide-refresh');
const _emptyRefresh = ValueKey('guide-empty-refresh');

String? get _focusLabel => FocusManager.instance.primaryFocus?.debugLabel;

bool get _gridFocused => _focusLabel == 'guide-grid';

bool get _headerFocused => focusedIn(_filter) || focusedIn(_refresh);

bool get _inErrorView {
  var found = false;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
    found = e.widget is ErrorView;
    return !found;
  });
  return found;
}

String? _infoTitle(WidgetTester tester) => tester
    .widget<BidiText>(find.byKey(const ValueKey('guide-info-title')))
    .text;

GuideGridState _grid(WidgetTester tester) =>
    tester.state<GuideGridState>(find.byType(GuideGrid));

/// The label of the header's filter button.
String _filterLabel(WidgetTester tester) => tester
    .widget<BidiText>(
      find.descendant(of: find.byKey(_filter), matching: find.byType(BidiText)),
    )
    .text;

/// Programme reads that fail, as on a damaged database.
class _FailingEpgDao extends EpgDao {
  _FailingEpgDao(super.attachedDatabase);

  int calls = 0;

  @override
  Future<Map<String, List<EpgProgramme>>> programmesForChannels(
    int sourceId,
    List<String> channelKeys,
    DateTime from,
    DateTime to,
  ) async {
    calls++;
    throw StateError('disk I/O error');
  }
}

/// Channel counts fail while [fail] is set, as on a damaged database.
class _FailingCounts extends QueryInterceptor {
  bool fail = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (fail && statement.startsWith('SELECT COUNT(*) AS n FROM channels')) {
      throw StateError('disk I/O error');
    }
    return executor.runSelect(statement, args);
  }
}

/// Rail -> Guide, then into the page ([rtl]: the page is on the left).
Future<void> _enter(WidgetTester tester, {bool rtl = false}) async {
  await press(tester, LogicalKeyboardKey.arrowDown);
  await press(
    tester,
    rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight,
  );
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  for (final rtl in [false, true]) {
    final name = rtl ? 'ar (RTL)' : 'en';

    testWidgets('$name: entering while the page loads ends in the grid', (
      tester,
    ) async {
      final db = openGuideDb();
      await seedGuide(db);
      // "Is there guide data?" answers only when the test says so.
      final ready = Completer<bool>();
      await pumpGuideApp(
        tester,
        db: db,
        player: PlayerLog(),
        rtl: rtl,
        overrides: [
          guideHasDataProvider.overrideWith(
            (ref, id) => Stream.fromFuture(ready.future),
          ),
        ],
      );
      await _enter(tester, rtl: rtl);
      expect(find.byType(LoadingView), findsOneWidget);
      expect(_focusLabel, 'guide-loading');

      // The header is reachable meanwhile, and the page remembers it.
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(_headerFocused, isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focusLabel, 'guide-loading');

      ready.complete(true);
      await settle(tester);
      expect(find.byType(GuideGrid), findsOneWidget);
      expect(_gridFocused, isTrue);
      expect(_infoTitle(tester), progTitle(1, 0));
      await disposeApp(tester, db);
    });
  }

  testWidgets('walking the rail past a Guide that failed to load stays on '
      'the rail', (tester) async {
    final db = openGuideDb();
    await seedGuide(db);
    await pumpGuideApp(
      tester,
      db: db,
      player: PlayerLog(),
      overrides: [
        guideHasDataProvider.overrideWith(
          (ref, id) => Stream<bool>.error(StateError('disk I/O error')),
        ),
      ],
    );
    expect(focusedIn(const ValueKey('rail-live')), isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.byType(ErrorView), findsOneWidget);
    expect(focusedIn(const ValueKey('rail-guide')), isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedIn(const ValueKey('rail-movies')), isTrue);
    // Entering the page lands on the header; Retry is right below.
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(_headerFocused, isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(_inErrorView, isTrue);
    await disposeApp(tester, db);
  });

  testWidgets('a channel list that fails to load does not pull focus off '
      'the rail', (tester) async {
    final counts = _FailingCounts();
    final db = openGuideDb(interceptor: counts);
    await seedGuide(db);
    await pumpGuideApp(tester, db: db, player: PlayerLog());
    expect(focusedIn(const ValueKey('rail-live')), isTrue);
    counts.fail = true;
    await press(tester, LogicalKeyboardKey.arrowDown);
    await settle(tester);
    expect(find.byType(ErrorView), findsOneWidget);
    expect(focusedIn(const ValueKey('rail-guide')), isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedIn(const ValueKey('rail-movies')), isTrue);
    counts.fail = false;
    await disposeApp(tester, db);
  });

  testWidgets('a slow box: focus stays in the body until the rows arrive', (
    tester,
  ) async {
    final slow = SlowReads();
    final db = openGuideDb(interceptor: slow);
    await seedGuide(db);
    await pumpGuideApp(tester, db: db, player: PlayerLog());
    slow.delay = const Duration(milliseconds: 300);
    await _enter(tester);

    var sawGridLoading = false;
    for (
      var i = 0;
      i < 60 &&
          find.byKey(const ValueKey('guide-info-title')).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(_focusLabel, anyOf('guide-loading', 'guide-grid'));
      if (find.byType(GuideGrid).evaluate().isNotEmpty &&
          find.byType(LoadingView).evaluate().isNotEmpty) {
        // The grid counts its channels: its focus is already there.
        sawGridLoading = true;
        expect(_gridFocused, isTrue);
      }
    }
    expect(sawGridLoading, isTrue);
    expect(_gridFocused, isTrue);
    slow.delay = Duration.zero;
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(_infoTitle(tester), progTitle(1, 0));
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(_infoTitle(tester), progTitle(2, 0));
    await disposeApp(tester, db);
  });

  testWidgets('guide data arriving moves focus from Refresh to the grid', (
    tester,
  ) async {
    final db = openGuideDb();
    final seeded = await seedGuide(db, guide: false);
    final epg = FakeEpgService();
    await pumpGuideApp(tester, db: db, player: PlayerLog(), epg: epg);
    await _enter(tester);
    expect(focusedIn(_emptyRefresh), isTrue);

    // Visit the header (the page remembers it), then come back.
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(_headerFocused, isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    if (!focusedIn(_emptyRefresh)) {
      await press(tester, LogicalKeyboardKey.arrowLeft);
    }
    expect(focusedIn(_emptyRefresh), isTrue);

    await press(tester, LogicalKeyboardKey.select);
    expect(epg.calls.single.force, isTrue);
    await addGuide(db, seeded.sourceId);
    await epg.finish(seeded.sourceId);
    await settle(tester);
    expect(find.byType(GuideGrid), findsOneWidget);
    expect(_gridFocused, isTrue);
    expect(_infoTitle(tester), progTitle(1, 0));
    await disposeApp(tester, db);
  });

  group('favourites', () {
    testWidgets('removing the last one falls back to all channels', (
      tester,
    ) async {
      final db = openGuideDb();
      final seeded = await seedGuide(db, favorites: ['c3']);
      await pumpGuideApp(tester, db: db, player: PlayerLog());
      await _enter(tester);
      expect(_gridFocused, isTrue);
      expect(_filterLabel(tester), en.liveFavorites);
      expect(_infoTitle(tester), progTitle(3, 0));

      // Removed elsewhere (Live, the player).
      await db.favoritesDao.setFavorite(
        seeded.sourceId,
        ContentKind.live,
        'c3',
        false,
      );
      await settle(tester);
      expect(find.text(en.favoritesEmpty), findsNothing);
      expect(_filterLabel(tester), en.liveAllChannels);
      expect(_gridFocused, isTrue);
      expect(_infoTitle(tester), progTitle(1, 0));
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(_infoTitle(tester), progTitle(2, 0));
      await disposeApp(tester, db);
    });

    testWidgets('favourites no longer in the playlist are left out', (
      tester,
    ) async {
      final db = openGuideDb();
      await seedGuide(db, favorites: ['gone']);
      final player = PlayerLog();
      await pumpGuideApp(tester, db: db, player: player);
      await _enter(tester);
      expect(_filterLabel(tester), en.liveAllChannels);
      expect(_gridFocused, isTrue);
      expect(_infoTitle(tester), progTitle(1, 0));
      await press(tester, LogicalKeyboardKey.select);
      expect(player.requests.single.zapKeys, isNull); // all channels
      await disposeApp(tester, db);
    });

    testWidgets('the zap list holds every favourite, not just loaded rows', (
      tester,
    ) async {
      final db = openGuideDb();
      // More than one page of rows (200), with a vanished channel inside.
      final favorites = ['c250', 'gone', for (var i = 1; i < 250; i++) 'c$i'];
      await seedGuide(db, channels: 250, favorites: favorites);
      final player = PlayerLog();
      await pumpGuideApp(tester, db: db, player: player);
      await _enter(tester);
      expect(_grid(tester).position.row, 0);
      await press(tester, LogicalKeyboardKey.select);
      final request = player.requests.single;
      expect(request.item.key, 'c250');
      expect(request.zapKeys, ['c250', for (var i = 1; i < 250; i++) 'c$i']);
      await disposeApp(tester, db);
    });
  });

  testWidgets('Watch channel in the details works after the grid is gone', (
    tester,
  ) async {
    final db = openGuideDb();
    final seeded = await seedGuide(db, favorites: ['c3']);
    final player = PlayerLog();
    await pumpGuideApp(tester, db: db, player: player);
    await _enter(tester);
    await press(tester, menuKey);
    expect(find.byKey(const ValueKey('guide-info')), findsOneWidget);
    final grid = _grid(tester);

    // The list changes under the dialog: the grid is replaced.
    await db.favoritesDao.setFavorite(
      seeded.sourceId,
      ContentKind.live,
      'c3',
      false,
    );
    await settle(tester);
    expect(grid.mounted, isFalse);

    await tester.tap(find.byKey(const ValueKey('guide-info-watch')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('guide-info')), findsNothing);
    final request = player.requests.single;
    expect(request.item.key, 'c3');
    expect(request.zapKeys, ['c3']);
    await disposeApp(tester, db);
  });

  testWidgets('programmes are loaded around the window, not from now', (
    tester,
  ) async {
    final db = openGuideDb();
    await seedGuide(db);
    await pumpGuideApp(tester, db: db, player: PlayerLog());
    await _enter(tester);
    var grid = _grid(tester);
    expect(grid.loadedRange!.from, grid.window.minTime);

    // Channel 1 ahead to its last programme (06:00 tomorrow), then into the
    // time after it: the block follows the window.
    for (var k = 1; k <= 12; k++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(_infoTitle(tester), progTitle(1, k));
    }
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(_infoTitle(tester), en.liveNoProgrammeInfo);
    grid = _grid(tester);
    final pos = grid.position;
    final range = grid.loadedRange!;
    expect(range.from, pos.viewStart.subtract(GuideTimes.loadBehind));
    expect(range.to, pos.viewEnd.add(GuideTimes.loadAhead));
    expect(range.from.isAfter(grid.window.minTime), isTrue);
    expect(range.to.difference(range.from), lessThan(const Duration(days: 1)));

    // Past the loaded block the window keeps moving while more loads.
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(
      _grid(tester).position.viewStart,
      pos.viewStart.add(GuideTimes.slot),
    );

    // Back to now: what is on air shows again (loaded for that window).
    await tester.binding.handlePopRoute();
    await settle(tester);
    grid = _grid(tester);
    expect(_gridFocused, isTrue);
    expect(grid.position.viewStart, guideViewStart);
    expect(_infoTitle(tester), progTitle(1, 0));
    expect(grid.loadedRange!.from, grid.window.minTime);

    // Browsing back from there finds the earlier programmes as before.
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_infoTitle(tester), progTitle(1, -1));
    await disposeApp(tester, db);
  });

  testWidgets('failing programme reads are retried, not every frame', (
    tester,
  ) async {
    final db = openGuideDb();
    await seedGuide(db);
    final dao = _FailingEpgDao(db);
    await pumpGuideApp(
      tester,
      db: db,
      player: PlayerLog(),
      overrides: [epgDaoProvider.overrideWithValue(dao)],
    );
    await _enter(tester);
    expect(_gridFocused, isTrue);
    final before = dao.calls;
    expect(before, greaterThan(0));
    // One second of frames: retries follow the debounce (150 ms).
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(dao.calls - before, inInclusiveRange(1, 8));
    // The grid stays usable meanwhile.
    expect(_gridFocused, isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(_grid(tester).position.row, 1);
    await disposeApp(tester, db);
  });
}
