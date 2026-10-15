import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
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
    final spy = SpyCatalogDao(db);
    await pumpVodApp(
      tester,
      db: db,
      overrides: [catalogDaoProvider.overrideWithValue(spy)],
    );
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

    // Far rows are not loaded until scrolled to: only the first page of
    // Action was read.
    expect(spy.movieOffsets('action'), [0]);
    final scrollable = tester.state<ScrollableState>(
      find
          .ancestor(of: find.byKey(_grid(0)), matching: find.byType(Scrollable))
          .first,
    );
    scrollable.position.jumpTo(38 * (size.height + 12));
    await settle(tester);
    // The second page was read and arrived (built cards past index 200
    // have their titles); the third was never asked for.
    expect(spy.movieOffsets('action'), [0, 200]);
    final second = [
      for (final e in find.byType(PosterCard).evaluate())
        if (_index(e.widget) >= 200) e.widget as PosterCard,
    ];
    expect(second, isNotEmpty);
    for (final c in second) {
      expect(c.title, 'Movie ${_index(c).toString().padLeft(3, '0')}');
    }
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

  for (final rtl in [false, true]) {
    testWidgets('${rtl ? 'ar' : 'en'} TV: a sync that moves the shown '
        'category keeps it for Back', (tester) async {
      final db = openVodDb(clock);
      final id = await addM3uSource(db);
      const action = CategoryData(
        kind: ContentKind.movie,
        key: 'action',
        name: 'Action',
      );
      const drama = CategoryData(
        kind: ContentKind.movie,
        key: 'drama',
        name: 'Drama',
        sortIndex: 2,
      );
      await seedCatalog(
        db,
        id,
        categories: const [action, drama],
        movies: [
          ...movies(10),
          ...movies(3, category: 'drama', prefix: 'd', name: 'Drama'),
        ],
      );
      await pumpVodApp(tester, db: db, rtl: rtl);
      await openTabFromRail(tester, 2, rtl: rtl);
      await pressN(tester, LogicalKeyboardKey.arrowDown, 2);
      expect(focusedIn(_drama), isTrue, reason: describeFocus());
      await press(tester, LogicalKeyboardKey.select);
      final browser = tester.state<VodBrowserState>(find.byType(VodBrowser));
      expect(browser.selected, VodBrowserState.categoryId('drama'));
      expect(focusedIn(_grid(0)), isTrue);

      // A background sync adds a category above Drama.
      await seedCatalog(
        db,
        id,
        categories: const [
          action,
          CategoryData(
            kind: ContentKind.movie,
            key: 'new',
            name: 'New',
            sortIndex: 1,
          ),
          drama,
        ],
        movies: [
          ...movies(10),
          ...movies(2, category: 'new', prefix: 'n', name: 'New'),
          ...movies(3, category: 'drama', prefix: 'd', name: 'Drama'),
        ],
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('vod-cat-c:new')), findsOneWidget);
      expect(focusedIn(_grid(0)), isTrue, reason: describeFocus());

      // Back lands on Drama, and Drama stays shown.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(focusedIn(_drama), isTrue, reason: describeFocus());
      await settle(tester);
      expect(browser.selected, VodBrowserState.categoryId('drama'));
      expect(find.text('Drama 000'), findsWidgets);

      await disposeVodApp(tester, db);
    });
  }

  testWidgets('TV: Back reaches the shown category after it scrolled away', (
    tester,
  ) async {
    final db = openVodDb(clock);
    final id = await addM3uSource(db);
    List<CategoryData> categories(int count) => [
      for (var i = 0; i < count; i++)
        CategoryData(
          kind: ContentKind.movie,
          key: 'k$i',
          name: 'Genre $i',
          sortIndex: i,
        ),
    ];
    List<MovieData> catalog(int count) => [
      for (var i = 0; i < count; i++)
        ...movies(2, category: 'k$i', prefix: 'k${i}_', name: 'Genre $i'),
    ];
    await seedCatalog(db, id, categories: categories(30), movies: catalog(30));
    await pumpVodApp(tester, db: db);
    await openTabFromRail(tester, 2, rtl: false);
    // Far down the category pane: All is scrolled out of the list.
    await pressN(tester, LogicalKeyboardKey.arrowDown, 25);
    expect(focusedIn(const ValueKey('vod-cat-c:k24')), isTrue);
    expect(find.byKey(_all), findsNothing);
    await press(tester, LogicalKeyboardKey.select);
    expect(focusedIn(_grid(0)), isTrue, reason: describeFocus());

    // A sync drops that category: the grid falls back to All, and Back
    // brings the pane back to the All entry.
    await seedCatalog(db, id, categories: categories(20), movies: catalog(20));
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(focusedIn(_all), isTrue, reason: describeFocus());

    await disposeVodApp(tester, db);
  });

  testWidgets('a page that fails to read is retried after a pause, with a '
      'note', (tester) async {
    final (db, _) = await seed();
    final spy = SpyCatalogDao(db)..failMovies = (offset) => offset == 200;
    await pumpVodApp(
      tester,
      db: db,
      overrides: [catalogDaoProvider.overrideWithValue(spy)],
    );
    await openTabFromRail(tester, 2, rtl: false);
    await pressN(tester, LogicalKeyboardKey.arrowDown, 2);
    await press(tester, LogicalKeyboardKey.select);
    expect(focusedIn(_grid(0)), isTrue);
    final size = tester.getSize(find.byKey(_grid(0)));
    final scrollable = tester.state<ScrollableState>(
      find
          .ancestor(of: find.byKey(_grid(0)), matching: find.byType(Scrollable))
          .first,
    );
    scrollable.position.jumpTo(38 * (size.height + 12));
    await settle(tester);
    expect(spy.movieOffsets('action'), [0, 200]);
    expect(find.byKey(const ValueKey('vod-page-error')), findsOneWidget);
    expect(find.text(enL10n.vod_pageLoadFailed), findsOneWidget);

    // The failed page is not read again on every rebuild...
    await settle(tester, frames: 20);
    expect(spy.movieOffsets('action'), [0, 200]);
    // ...but once the pause is over, while it is on screen.
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);
    expect(spy.movieOffsets('action'), [0, 200, 200]);
    expect(find.byKey(const ValueKey('vod-page-error')), findsOneWidget);

    // The next try succeeds: titles appear and the note goes away.
    spy.failMovies = null;
    await tester.pump(const Duration(seconds: 4));
    await settle(tester);
    expect(spy.movieOffsets('action'), [0, 200, 200, 200]);
    expect(find.byKey(const ValueKey('vod-page-error')), findsNothing);
    final titled = [
      for (final e in find.byType(PosterCard).evaluate())
        if (_index(e.widget) >= 200) e.widget as PosterCard,
    ];
    expect(titled, isNotEmpty);
    expect(titled.every((c) => c.title.startsWith('Movie')), isTrue);

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
