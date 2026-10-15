import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/features/favorites/favorites_screen.dart';
import 'package:iptv_player/features/favorites/vod_navigation.dart';
import 'package:iptv_player/features/movies/movie_detail_screen.dart';
import 'package:iptv_player/features/series/series_detail_screen.dart';
import 'package:iptv_player/features/vod_common/vod_providers.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/widgets/poster_card.dart';

import '../live/support/live_test_utils.dart';

/// Ten channels, two movies and a series; favourites: channels 2 and 5, a
/// channel that left the catalog, movie m1 and series s1.
Future<int> seedFavorites(AppDatabase db) async {
  final id = await addTestSource(db, lastSyncAt: DateTime.now());
  await seedCatalog(
    db,
    id,
    categories: [liveCategory('news', 'News', 0)],
    channels: [for (var n = 1; n <= 10; n++) testChannel(n)],
    movies: [
      const MovieData(key: 'm1', name: 'First Movie', categoryKeys: ['f']),
      const MovieData(key: 'm2', name: 'Second Movie', categoryKeys: ['f']),
    ],
    series: [
      const SeriesData(key: 's1', name: 'Some Series', categoryKeys: ['t']),
    ],
  );
  final favorites = db.favoritesDao;
  await favorites.setFavorite(id, ContentKind.live, 'k2', true);
  await favorites.setFavorite(id, ContentKind.live, 'gone', true);
  await favorites.setFavorite(id, ContentKind.live, 'k5', true);
  await favorites.setFavorite(id, ContentKind.movie, 'm1', true);
  await favorites.setFavorite(id, ContentKind.series, 's1', true);
  return id;
}

class VodRecorder {
  final targets = <VodTarget>[];

  Future<void> open(BuildContext context, _, VodTarget target) async =>
      targets.add(target);
}

FavoritesViewState favoritesState(WidgetTester tester) =>
    tester.state<FavoritesViewState>(find.byType(FavoritesView));

Future<void> openFavoritesTab(WidgetTester tester, bool rtl) async {
  final steps = HomeTab.tvTabs.indexOf(HomeTab.favorites);
  for (var i = 0; i < steps; i++) {
    await press(tester, LogicalKeyboardKey.arrowDown);
  }
  expect(focusedIn(const ValueKey('rail-favorites')), isTrue);
  await press(tester, toEnd(rtl));
}

void main() {
  for (final rtl in [false, true]) {
    final locale = Locale(rtl ? 'ar' : 'en');
    final l10n = lookupAppLocalizations(locale);

    testWidgets('${locale.languageCode}: TV favourites segments, playing and '
        'removing', (tester) async {
      final db = openAppTestDb();
      final id = await seedFavorites(db);
      final player = FakePlayer();
      final vod = VodRecorder();
      await pumpLiveApp(
        tester,
        db,
        locale: locale,
        overrides: [
          player.override,
          vodDetailNavigatorProvider.overrideWithValue(vod.open),
        ],
      );
      await openFavoritesTab(tester, rtl);
      expect(focusedIn(const ValueKey('favorites-tab-live')), isTrue);
      expect(favoritesState(tester).segment, FavoritesSegment.live);

      // Live favourites in favourite order; a vanished one is unavailable.
      expect(find.text('Channel 2'), findsOneWidget);
      expect(find.text('Channel 5'), findsOneWidget);
      expect(find.text(l10n.commonUnavailable), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Channel 2');
      await press(tester, LogicalKeyboardKey.select);
      expect(player.requests.single.item.key, 'k2');
      expect(player.requests.single.zapKeys, ['k2', 'k5']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expectFocusOn('Channel 2');

      // Removing a favourite keeps focus in the list.
      await press(tester, LogicalKeyboardKey.contextMenu);
      expectFocusOn(l10n.liveRemoveFavorite);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text('Channel 2'), findsNothing);
      expectFocusOn(l10n.commonUnavailable);
      expect(await db.favoritesDao.favoriteKeys(id, ContentKind.live), [
        'gone',
        'k5',
      ]);

      // Up returns to the tabs; moving along them switches segments.
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedIn(const ValueKey('favorites-tab-live')), isTrue);
      await press(tester, toEnd(rtl));
      expect(focusedIn(const ValueKey('favorites-tab-movies')), isTrue);
      expect(favoritesState(tester).segment, FavoritesSegment.movies);
      expect(find.byKey(const ValueKey('poster-m1')), findsOneWidget);
      expect(find.byKey(const ValueKey('poster-m2')), findsNothing);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('poster-m1')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(vod.targets.single.kind, ContentKind.movie);
      expect(vod.targets.single.movie?.name, 'First Movie');

      // Removing the last movie moves focus back to the tabs.
      await press(tester, LogicalKeyboardKey.contextMenu);
      expectFocusOn(l10n.vodRemoveFavorite);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text(l10n.favoritesEmptyMovies), findsOneWidget);
      expect(focusedIn(const ValueKey('favorites-tab-movies')), isTrue);

      await press(tester, toEnd(rtl));
      expect(favoritesState(tester).segment, FavoritesSegment.series);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('poster-s1')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(vod.targets.last.kind, ContentKind.series);
      expect(vod.targets.last.key, 's1');

      // Back: content -> tabs -> rail.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(focusedIn(const ValueKey('favorites-tab-series')), isTrue);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(focusedIn(const ValueKey('rail-favorites')), isTrue);
      await disposeApp(tester, db);
    });

    testWidgets('${locale.languageCode}: a key pressed while the list '
        're-reads after the player closes is kept', (tester) async {
      final db = openAppTestDb();
      final id = await seedFavorites(db);
      final player = FakePlayer();
      final recent = SlowRecentDao(db);
      await pumpLiveApp(
        tester,
        db,
        locale: locale,
        overrides: [
          player.override,
          recentDaoProvider.overrideWithValue(recent),
        ],
      );
      await openFavoritesTab(tester, rtl);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Channel 2');
      await press(tester, LogicalKeyboardKey.select);
      expect(player.requests.single.item.key, 'k2');

      // The player zapped on to channel 5; Back, then Up at once.
      await db.recentDao.markRecent(id, 'k5');
      recent.delay = const Duration(milliseconds: 300);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expectFocusOn('Channel 2');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      const tab = ValueKey('favorites-tab-live');
      expect(focusedIn(tab), isTrue);
      for (var i = 0; i < 4; i++) {
        await settle(tester);
      }
      expect(focusedIn(tab), isTrue);
      // The list still moved on to the channel played last.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Channel 5');
      await disposeApp(tester, db);
    });

    testWidgets('${locale.languageCode}: the page stays reachable from the '
        'rail after its list empties elsewhere', (tester) async {
      final db = openAppTestDb();
      final id = await addTestSource(db, lastSyncAt: DateTime.now());
      await seedCatalog(
        db,
        id,
        categories: [liveCategory('news', 'News', 0)],
        channels: [for (var n = 1; n <= 3; n++) testChannel(n)],
        movies: [
          const MovieData(key: 'm1', name: 'First Movie', categoryKeys: ['f']),
        ],
      );
      await db.favoritesDao.setFavorite(id, ContentKind.live, 'k2', true);
      await db.favoritesDao.setFavorite(id, ContentKind.movie, 'm1', true);
      await pumpLiveApp(tester, db, locale: locale);
      final railSteps = HomeTab.tvTabs.indexOf(HomeTab.favorites);

      // Leave Favorites from its list straight to the rail.
      await openFavoritesTab(tester, rtl);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Channel 2');
      await press(tester, toStart(rtl));
      expect(focusedIn(const ValueKey('rail-favorites')), isTrue);

      // On Live, remove the favourite with the Menu key.
      for (var i = 0; i < railSteps; i++) {
        await press(tester, LogicalKeyboardKey.arrowUp);
      }
      expect(focusedIn(const ValueKey('rail-live')), isTrue);
      await press(tester, toEnd(rtl));
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Channel 2');
      await press(tester, LogicalKeyboardKey.contextMenu);
      expectFocusOn(l10n.liveRemoveFavorite);
      await press(tester, LogicalKeyboardKey.select);
      expect(await db.favoritesDao.favoriteKeys(id, ContentKind.live), []);
      await press(tester, toStart(rtl));
      await press(tester, toStart(rtl));
      expect(focusedIn(const ValueKey('rail-live')), isTrue);

      // Back on Favorites: entering lands on the segment tabs.
      for (var i = 0; i < railSteps; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(focusedIn(const ValueKey('rail-favorites')), isTrue);
      expect(find.text(l10n.favoritesEmpty), findsOneWidget);
      await press(tester, toEnd(rtl));
      expect(focusedIn(const ValueKey('favorites-tab-live')), isTrue);

      // Same for the movie grid: leave it from the poster to the rail, then
      // the movie stops being a favourite.
      await press(tester, toEnd(rtl));
      expect(focusedIn(const ValueKey('favorites-tab-movies')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('poster-m1')), isTrue);
      await press(tester, toStart(rtl));
      expect(focusedIn(const ValueKey('rail-favorites')), isTrue);
      await db.favoritesDao.setFavorite(id, ContentKind.movie, 'm1', false);
      await settle(tester);
      expect(find.text(l10n.favoritesEmptyMovies), findsOneWidget);
      await press(tester, LogicalKeyboardKey.select);
      expect(focusedIn(const ValueKey('favorites-tab-movies')), isTrue);
      await disposeApp(tester, db);
    });

    testWidgets('${locale.languageCode}: phone favourites as a pushed page; '
        'a movie opens its detail page and resumes there; a series opens '
        'its detail page', (tester) async {
      final db = openAppTestDb();
      final id = await seedFavorites(db);
      await db.progressDao.saveProgress(
        id,
        PlayableKind.movie,
        'm1',
        const Duration(minutes: 12).inMilliseconds,
        const Duration(minutes: 90).inMilliseconds,
      );
      final player = FakePlayer();
      await pumpLiveApp(
        tester,
        db,
        tv: false,
        locale: locale,
        overrides: [
          player.override,
          vodPlayerLauncherProvider.overrideWithValue(player.launch),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('nav-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('more-favorites')));
      await tester.pumpAndSettle();
      expect(find.byType(FavoritesView), findsOneWidget);
      // A pushed page focuses its selected segment itself.
      expect(focusedIn(const ValueKey('favorites-tab-live')), isTrue);

      // Segments run from the start side.
      final liveX = tester
          .getCenter(find.byKey(const ValueKey('favorites-tab-live')))
          .dx;
      final moviesX = tester
          .getCenter(find.byKey(const ValueKey('favorites-tab-movies')))
          .dx;
      expect(rtl ? liveX > moviesX : liveX < moviesX, isTrue);

      await tester.tap(find.byKey(const ValueKey('favorites-tab-movies')));
      await tester.pumpAndSettle();
      // The poster shows the watch progress.
      final card = tester.widget<PosterCard>(
        find.byKey(const ValueKey('poster-m1')),
      );
      expect(card.progress, closeTo(12 / 90, 0.001));
      // The movie's detail page (the same one the Movies grid opens),
      // offering to resume.
      await tester.tap(find.byKey(const ValueKey('poster-m1')));
      await tester.pumpAndSettle();
      final detail = tester.widget<MovieDetailScreen>(
        find.byType(MovieDetailScreen),
      );
      expect((detail.sourceId, detail.movieKey), (id, 'm1'));
      expect(player.requests, isEmpty);
      await tester.tap(find.byKey(const ValueKey('vod-play')));
      await tester.pumpAndSettle();
      final request = player.requests.single;
      expect(request.item.kind, PlayableKind.movie);
      expect(request.item.key, 'm1');
      expect(request.startAt, const Duration(minutes: 12));
      // Back from the player, then from the detail page.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MovieDetailScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MovieDetailScreen), findsNothing);
      expect(find.byType(FavoritesView), findsOneWidget);

      // A series opens its detail page (seasons and episodes).
      await tester.tap(find.byKey(const ValueKey('favorites-tab-series')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('poster-s1')));
      await tester.pumpAndSettle();
      final series = tester.widget<SeriesDetailScreen>(
        find.byType(SeriesDetailScreen),
      );
      expect((series.sourceId, series.seriesKey), (id, 's1'));
      expect(player.requests, hasLength(1));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(FavoritesView), findsOneWidget);
      await disposeApp(tester, db);
    });
  }
}
