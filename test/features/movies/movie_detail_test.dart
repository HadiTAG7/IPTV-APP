import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/features/movies/movie_detail_screen.dart';
import 'package:iptv_player/sources/models.dart';

import 'vod_harness.dart';

const _play = ValueKey('vod-play');
const _startOver = ValueKey('vod-start-over');
const _favorite = ValueKey('vod-favorite');

void main() {
  late FakeClock clock;

  setUp(() => clock = FakeClock(testEpoch));

  Future<(AppDatabase, int)> seed({bool xtream = false}) async {
    final db = openVodDb(clock);
    final id = xtream ? await addXtreamSource(db) : await addM3uSource(db);
    await seedCatalog(
      db,
      id,
      categories: const [
        CategoryData(kind: ContentKind.movie, key: 'action', name: 'Action'),
      ],
      movies: [
        const MovieData(
          key: 'm1',
          name: 'The Long Road',
          year: 2019,
          rating: 7.25,
          ext: 'mkv',
          url: 'http://127.0.0.1:9/movie/m1.mkv',
          headers: {'Referer': 'http://127.0.0.1:9/'},
          categoryKeys: ['action'],
        ),
        const MovieData(
          key: 'm2',
          name: 'طريق طويل',
          ext: 'mp4',
          categoryKeys: ['action'],
        ),
      ],
    );
    return (db, id);
  }

  /// Opens Movies on TV and OK on poster [index] of All.
  Future<void> openFromGrid(
    WidgetTester tester, {
    required bool rtl,
    int index = 0,
  }) async {
    await openTabFromRail(tester, 2, rtl: rtl);
    await press(tester, toEnd(rtl));
    for (var i = 0; i < index; i++) {
      await press(tester, toEnd(rtl));
    }
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byType(MovieDetailScreen), findsOneWidget);
  }

  for (final rtl in [false, true]) {
    final lang = rtl ? 'ar' : 'en';

    testWidgets('$lang TV: resume and start over from saved progress', (
      tester,
    ) async {
      final (db, id) = await seed();
      await db.progressDao.saveProgress(
        id,
        PlayableKind.movie,
        'm1',
        (42 * 60 + 10) * 1000,
        120 * 60 * 1000,
      );
      final player = PlayRecorder();
      await pumpVodApp(tester, db: db, rtl: rtl, player: player);
      final l10n = rtl ? arL10n : enL10n;

      // The continue row comes first in All; its first card is m1.
      await openFromGrid(tester, rtl: rtl);
      expect(find.text('The Long Road'), findsWidgets);
      expect(find.text('2019'), findsOneWidget);
      expect(find.text('7.3'), findsOneWidget);

      // Resume is the focused primary button; Start over sits next to it.
      expect(focusedIn(_play), isTrue, reason: describeFocus());
      expect(find.text(l10n.vodResumeFrom('42:10')), findsOneWidget);
      expect(find.text(l10n.vodStartOver), findsOneWidget);
      final playX = tester.getCenter(find.byKey(_play)).dx;
      final overX = tester.getCenter(find.byKey(_startOver)).dx;
      expect(rtl ? playX > overX : playX < overX, isTrue);

      await press(tester, LogicalKeyboardKey.select);
      expect(player.requests, hasLength(1));
      final resume = player.last;
      expect(resume.sourceId, id);
      expect(resume.item.kind, PlayableKind.movie);
      expect(resume.item.key, 'm1');
      expect(resume.item.ext, 'mkv');
      expect(resume.item.url, 'http://127.0.0.1:9/movie/m1.mkv');
      expect(resume.item.headers, {'Referer': 'http://127.0.0.1:9/'});
      expect(resume.startAt, const Duration(minutes: 42, seconds: 10));

      await press(tester, toEnd(rtl));
      expect(focusedIn(_startOver), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(player.last.startAt, Duration.zero);

      // The favourite toggle keeps focus and flips its label.
      await press(tester, toEnd(rtl));
      expect(focusedIn(_favorite), isTrue);
      expect(find.text(l10n.vodAddFavorite), findsOneWidget);
      await press(tester, LogicalKeyboardKey.select);
      expect(
        await db.favoritesDao.isFavorite(id, ContentKind.movie, 'm1'),
        isTrue,
      );
      expect(find.text(l10n.vodRemoveFavorite), findsOneWidget);
      expect(focusedIn(_favorite), isTrue);

      // Back closes the page and focus returns to the poster.
      await tester.binding.handlePopRoute();
      await settle(tester, frames: 16);
      expect(find.byType(MovieDetailScreen), findsNothing);
      expect(
        focusedIn(const ValueKey('vod-cw-movie-m1')),
        isTrue,
        reason: describeFocus(),
      );

      await disposeVodApp(tester, db);
    });

    testWidgets('$lang TV: no progress offers Play only', (tester) async {
      final (db, id) = await seed();
      // Under 30 s and finished titles are not resumable.
      await db.progressDao.saveProgress(
        id,
        PlayableKind.movie,
        'm1',
        119 * 60 * 1000,
        120 * 60 * 1000,
      );
      final player = PlayRecorder();
      await pumpVodApp(tester, db: db, rtl: rtl, player: player);
      final l10n = rtl ? arL10n : enL10n;

      await openFromGrid(tester, rtl: rtl);
      expect(find.text('The Long Road'), findsWidgets);
      expect(focusedIn(_play), isTrue);
      expect(find.text(l10n.vodPlay), findsOneWidget);
      expect(find.byKey(_startOver), findsNothing);
      await press(tester, LogicalKeyboardKey.select);
      expect(player.last.item.key, 'm1');
      expect(player.last.startAt, isNull);

      await disposeVodApp(tester, db);
    });
  }

  testWidgets('details load lazily, are cached, and a cache hit skips the '
      'network', (tester) async {
    final (db, id) = await seed(xtream: true);
    final pending = Completer<MovieDetail?>();
    final adapter = FakeVodAdapter(onMovie: (_) => pending.future);
    await pumpVodApp(tester, db: db, adapter: adapter);

    await openFromGrid(tester, rtl: false, index: 0);
    // What the catalog has shows while the details load.
    expect(find.text('The Long Road'), findsWidgets);
    expect(find.byKey(const ValueKey('vod-plot')), findsNothing);
    expect(adapter.movieCalls, ['m1']);
    expect(focusedIn(_play), isTrue);

    pending.complete(
      const MovieDetail(
        key: 'm1',
        plot: 'A slow trip across the desert.',
        genre: 'Drama',
        durationSec: 95 * 60,
        director: 'A. Person',
        cast: 'B. Actor, C. Actor',
        rating: 8.1,
      ),
    );
    await settle(tester);
    expect(find.text('A slow trip across the desert.'), findsOneWidget);
    expect(find.text('Drama'), findsOneWidget);
    expect(find.text(enL10n.vodMinutes(95)), findsOneWidget);
    expect(find.text('8.1'), findsOneWidget);
    expect(find.text(enL10n.vod_director('A. Person')), findsOneWidget);
    expect(adapter.closed, 1);
    expect(await db.detailCacheDao.movieDetail(id, 'm1'), isNotNull);

    // Close and open again: answered from the cache.
    await tester.binding.handlePopRoute();
    await settle(tester, frames: 16);
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byType(MovieDetailScreen), findsOneWidget);
    expect(find.text('A slow trip across the desert.'), findsOneWidget);
    expect(adapter.movieCalls, ['m1']);

    // After 24 h the cache is stale and the details are fetched again.
    await tester.binding.handlePopRoute();
    await settle(tester, frames: 16);
    clock.advance(const Duration(hours: 25));
    adapter.onMovie = (key) async => MovieDetail(key: key, plot: 'Updated.');
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text('Updated.'), findsOneWidget);
    expect(adapter.movieCalls, ['m1', 'm1']);

    await disposeVodApp(tester, db);
  });

  testWidgets('a failed fetch is not fatal; stale details are used', (
    tester,
  ) async {
    final (db, id) = await seed(xtream: true);
    final adapter = FakeVodAdapter(
      onMovie: (_) => Future.error(const NetworkFailure('HTTP 500')),
    );
    await pumpVodApp(tester, db: db, adapter: adapter);

    await openFromGrid(tester, rtl: false);
    expect(find.text('The Long Road'), findsWidgets);
    expect(find.byKey(const ValueKey('vod-details-failed')), findsOneWidget);
    expect(focusedIn(_play), isTrue);

    // With an old cache entry, that one shows instead of the note.
    await tester.binding.handlePopRoute();
    await settle(tester, frames: 16);
    await db.detailCacheDao.putMovieDetail(
      id,
      const MovieDetail(key: 'm1', plot: 'Cached plot.'),
    );
    clock.advance(const Duration(days: 3));
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text('Cached plot.'), findsOneWidget);
    expect(find.byKey(const ValueKey('vod-details-failed')), findsNothing);
    expect(adapter.movieCalls, hasLength(2));

    await disposeVodApp(tester, db);
  });

  testWidgets('M3U movies never ask the adapter', (tester) async {
    final (db, _) = await seed();
    // No adapter: building one would throw.
    await pumpVodApp(tester, db: db);
    await openFromGrid(tester, rtl: false);
    expect(find.text('The Long Road'), findsWidgets);
    expect(find.byKey(const ValueKey('vod-details-failed')), findsNothing);
    await disposeVodApp(tester, db);
  });

  for (final rtl in [false, true]) {
    testWidgets('${rtl ? 'ar' : 'en'} phone: detail layout and play', (
      tester,
    ) async {
      final (db, id) = await seed();
      await db.progressDao.saveProgress(
        id,
        PlayableKind.movie,
        'm2',
        5 * 60 * 1000,
        100 * 60 * 1000,
      );
      final player = PlayRecorder();
      await pumpVodApp(tester, db: db, tv: false, rtl: rtl, player: player);
      final l10n = rtl ? arL10n : enL10n;
      await tester.tap(find.byKey(const ValueKey('nav-movies')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('vod-cw-movie-m2')));
      await settle(tester);

      expect(find.byType(MovieDetailScreen), findsOneWidget);
      expect(find.text('طريق طويل'), findsWidgets);
      expect(find.text(l10n.vodResumeFrom('5:00')), findsOneWidget);
      await tester.tap(find.byKey(_startOver));
      await settle(tester);
      expect(player.last.item.key, 'm2');
      expect(player.last.startAt, Duration.zero);
      await tester.tap(find.byKey(_play));
      await settle(tester);
      expect(player.last.startAt, const Duration(minutes: 5));

      await disposeVodApp(tester, db);
    });
  }
}
