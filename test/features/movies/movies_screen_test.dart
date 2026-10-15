import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/features/movies/movie_detail_screen.dart';
import 'package:iptv_player/features/vod_common/vod_browser.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/widgets/poster_card.dart';

import 'vod_harness.dart';

const _all = ValueKey('vod-cat-all');
const _cw = ValueKey('vod-cat-cw');
const _action = ValueKey('vod-cat-c:action');
const _drama = ValueKey('vod-cat-c:drama');
const _railMovies = ValueKey('rail-movies');

Key _grid(int i) => ValueKey('vod-grid-$i');
Key _cwCard(String key) => ValueKey('vod-cw-movie-$key');

/// The index of a grid poster from its key.
int _index(Widget card) =>
    int.parse((card.key! as ValueKey<String>).value.substring(9));

void main() {
  late FakeClock clock;

  setUp(() => clock = FakeClock(testEpoch));

  /// A source with 450 action movies, 3 dramas and two started movies
  /// (m001 first, then d001).
  Future<(AppDatabase, int)> seed() async {
    final db = openVodDb(clock);
    final id = await addM3uSource(db);
    await seedCatalog(
      db,
      id,
      categories: const [
        CategoryData(kind: ContentKind.movie, key: 'action', name: 'Action'),
        CategoryData(
          kind: ContentKind.movie,
          key: 'drama',
          name: 'دراما',
          sortIndex: 1,
        ),
      ],
      movies: [
        ...movies(450),
        ...movies(3, category: 'drama', prefix: 'd', name: 'Drama'),
      ],
    );
    final progress = db.progressDao;
    await progress.saveProgress(
      id,
      PlayableKind.movie,
      'm001',
      10 * 60 * 1000,
      100 * 60 * 1000,
    );
    clock.advance(const Duration(minutes: 5));
    await progress.saveProgress(
      id,
      PlayableKind.movie,
      'd001',
      20 * 60 * 1000,
      90 * 60 * 1000,
    );
    return (db, id);
  }

  for (final rtl in [false, true]) {
    final lang = rtl ? 'ar' : 'en';

    testWidgets('$lang TV: rail, categories, continue row and grid cross', (
      tester,
    ) async {
      final (db, _) = await seed();
      await pumpVodApp(tester, db: db, rtl: rtl);
      final l10n = rtl ? arL10n : enL10n;

      await openTabFromRail(tester, 2, rtl: rtl);
      expect(focusedIn(_all), isTrue, reason: describeFocus());
      expect(find.text(l10n.vod_allMovies), findsWidgets);
      expect(find.text(l10n.vodContinueWatching), findsWidgets);

      // The category pane is on the start side, the grid on the end side.
      final catX = tester.getCenter(find.byKey(_all)).dx;
      final cardX = tester.getCenter(find.byKey(_cwCard('d001'))).dx;
      expect(rtl ? catX > cardX : catX < cardX, isTrue);

      // Continue watching: newest first, in reading order.
      final first = tester.getCenter(find.byKey(_cwCard('d001'))).dx;
      final second = tester.getCenter(find.byKey(_cwCard('m001'))).dx;
      expect(rtl ? first > second : first < second, isTrue);

      // Into the grid pane: the first continue card.
      await press(tester, toEnd(rtl));
      expect(focusedIn(_cwCard('d001')), isTrue, reason: describeFocus());
      await press(tester, toEnd(rtl));
      expect(focusedIn(_cwCard('m001')), isTrue);
      // Down reaches the poster grid.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(_grid(0)) || focusedIn(_grid(1)), isTrue);

      // Toward the start: back to the selected category, then the rail.
      await pressN(tester, toStart(rtl), 2);
      expect(focusedIn(_all), isTrue, reason: describeFocus());
      await press(tester, toStart(rtl));
      expect(focusedIn(_railMovies), isTrue, reason: describeFocus());

      // Back into the page lands on the remembered category.
      await press(tester, toEnd(rtl));
      expect(focusedIn(_all), isTrue);

      // Focusing a category shows it after a short delay.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(_cw), isTrue);
      await settle(tester);
      final browser = tester.state<VodBrowserState>(find.byType(VodBrowser));
      expect(browser.selected, VodBrowserState.continueId);
      expect(find.byKey(const ValueKey('vod-cwg-movie-d001')), findsOneWidget);

      // OK on a category shows it at once and enters its grid.
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(_drama), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(browser.selected, VodBrowserState.categoryId('drama'));
      expect(focusedIn(_grid(0)), isTrue, reason: describeFocus());
      expect(find.text('Drama 000'), findsWidgets);
      expect(find.text('Movie 000'), findsNothing);

      // Back from the grid returns to the categories.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(focusedIn(_drama), isTrue, reason: describeFocus());

      await disposeVodApp(tester, db);
    });
  }

  testWidgets('TV grid: 6 columns, pages read on demand', (tester) async {
    final (db, _) = await seed();
    await pumpVodApp(tester, db: db);
    await openTabFromRail(tester, 2, rtl: false);
    await press(tester, LogicalKeyboardKey.arrowDown); // Continue watching
    await press(tester, LogicalKeyboardKey.arrowDown); // Action
    expect(focusedIn(_action), isTrue);
    await press(tester, LogicalKeyboardKey.select);
    expect(focusedIn(_grid(0)), isTrue);
    expect(find.text('Movie 000'), findsWidgets);

    // Six posters per row, the seventh starts the next row.
    final y0 = tester.getTopLeft(find.byKey(_grid(0))).dy;
    for (var i = 1; i < 6; i++) {
      expect(tester.getTopLeft(find.byKey(_grid(i))).dy, y0);
    }
    expect(tester.getTopLeft(find.byKey(_grid(6))).dy, greaterThan(y0));
    // 2:3 posters with a fixed extent.
    final size = tester.getSize(find.byKey(_grid(0)));
    expect(size.height, closeTo(PosterCard.heightForWidth(size.width), 0.5));

    // Arrows move through the grid; right then down.
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedIn(_grid(1)), isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedIn(_grid(7)), isTrue);

    // Far rows are not loaded until scrolled to.
    expect(find.textContaining('Movie 2'), findsNothing);
    final scrollable = tester.state<ScrollableState>(
      find
          .ancestor(of: find.byKey(_grid(0)), matching: find.byType(Scrollable))
          .first,
    );
    scrollable.position.jumpTo(38 * (size.height + 12));
    await settle(tester);
    // The second page arrived (built cards past index 200 have their
    // titles); the third was never asked for.
    final second = [
      for (final e in find.byType(PosterCard).evaluate())
        if (_index(e.widget) >= 200) e.widget as PosterCard,
    ];
    expect(second, isNotEmpty);
    for (final c in second) {
      expect(c.title, 'Movie ${_index(c).toString().padLeft(3, '0')}');
    }
    expect(find.textContaining('Movie 4'), findsNothing);
    // The focused poster scrolled away: focus moved to a built one.
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused, isNotNull);
    final card = find.ancestor(
      of: find.byWidget(focused!.widget),
      matching: find.byType(PosterCard),
    );
    expect(card, findsOneWidget);
    final title = tester.widget<PosterCard>(card).title;
    expect(title, startsWith('Movie 2'));

    // OK opens its detail page.
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byType(MovieDetailScreen), findsOneWidget);
    expect(find.text(title), findsWidgets);

    await disposeVodApp(tester, db);
  });

  for (final rtl in [false, true]) {
    testWidgets('${rtl ? 'ar' : 'en'} phone: chips, 3 columns, tap opens', (
      tester,
    ) async {
      final (db, _) = await seed();
      await pumpVodApp(tester, db: db, tv: false, rtl: rtl);
      final l10n = rtl ? arL10n : enL10n;
      await tester.tap(find.byKey(const ValueKey('nav-movies')));
      await settle(tester);

      expect(find.byKey(_all), findsOneWidget);
      expect(find.text(l10n.vodContinueWatching), findsWidgets);

      await tester.tap(find.byKey(_action));
      await settle(tester);
      final y0 = tester.getTopLeft(find.byKey(_grid(0))).dy;
      expect(tester.getTopLeft(find.byKey(_grid(2))).dy, y0);
      expect(tester.getTopLeft(find.byKey(_grid(3))).dy, greaterThan(y0));
      // Reading order follows the layout direction.
      final x0 = tester.getCenter(find.byKey(_grid(0))).dx;
      final x1 = tester.getCenter(find.byKey(_grid(1))).dx;
      expect(rtl ? x0 > x1 : x0 < x1, isTrue);

      await tester.tap(find.byKey(_grid(1)));
      await settle(tester);
      expect(find.byType(MovieDetailScreen), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await settle(tester, frames: 16);
      expect(find.byType(MovieDetailScreen), findsNothing);

      await disposeVodApp(tester, db);
    });
  }

  testWidgets('a sync refreshes the grid in place and keeps focus', (
    tester,
  ) async {
    final (db, id) = await seed();
    await pumpVodApp(tester, db: db);
    await openTabFromRail(tester, 2, rtl: false);
    await pressN(tester, LogicalKeyboardKey.arrowDown, 3);
    expect(focusedIn(_drama), isTrue);
    await press(tester, LogicalKeyboardKey.select);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedIn(_grid(1)), isTrue);

    // Same number of dramas, one renamed: the grid stays and updates.
    Future<void> resync(List<MovieData> dramas) async {
      await seedCatalog(
        db,
        id,
        categories: const [
          CategoryData(kind: ContentKind.movie, key: 'action', name: 'Action'),
          CategoryData(
            kind: ContentKind.movie,
            key: 'drama',
            name: 'دراما',
            sortIndex: 1,
          ),
        ],
        movies: [...movies(450), ...dramas],
      );
      await settle(tester);
    }

    final dramas = movies(3, category: 'drama', prefix: 'd', name: 'Drama');
    await resync([
      dramas[0],
      const MovieData(key: 'd001', name: 'Renamed', categoryKeys: ['drama']),
      dramas[2],
    ]);
    expect(find.text('Renamed'), findsWidgets);
    expect(focusedIn(_grid(1)), isTrue, reason: describeFocus());

    // A different count rebuilds the grid; focus stays in the grid pane.
    await resync([...dramas, ...movies(2, category: 'drama', prefix: 'x')]);
    expect(find.byKey(_grid(4)), findsOneWidget);
    expect(focusedIn(_grid(0)), isTrue, reason: describeFocus());

    await disposeVodApp(tester, db);
  });

  testWidgets('an empty source shows the empty state', (tester) async {
    final db = openVodDb(clock);
    await addM3uSource(db);
    await pumpVodApp(tester, db: db, tv: false);
    await tester.tap(find.byKey(const ValueKey('nav-movies')));
    await settle(tester);
    expect(find.text(enL10n.vod_noMovies), findsOneWidget);
    await disposeVodApp(tester, db);
  });
}
