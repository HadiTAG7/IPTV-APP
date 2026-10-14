import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/sources/models.dart';

import 'db_test_utils.dart';

void main() {
  late FakeClock clock;
  late AppDatabase db;
  late int src;

  setUp(() async {
    clock = FakeClock(testEpoch);
    db = openTestDb(clock: clock);
    src = await addSource(db);
  });

  tearDown(() => db.close());

  group('favorites', () {
    late FavoritesDao favs;

    setUp(() async {
      favs = db.favoritesDao;
      await syncCatalog(
        db,
        src,
        channels: [channel('a'), channel('b'), channel('c')],
        movies: [movie('m')],
        seriesList: [series('s')],
      );
    });

    test('toggle flips and reports the new state', () async {
      expect(await favs.toggleFavorite(src, ContentKind.live, 'a'), isTrue);
      expect(await favs.isFavorite(src, ContentKind.live, 'a'), isTrue);
      expect(await favs.isFavorite(src, ContentKind.movie, 'a'), isFalse);
      expect(await favs.toggleFavorite(src, ContentKind.live, 'a'), isFalse);
      expect(await favs.isFavorite(src, ContentKind.live, 'a'), isFalse);
    });

    test('keeps insertion order, ignores duplicates, can reorder', () async {
      for (final k in ['c', 'a', 'b']) {
        await favs.setFavorite(src, ContentKind.live, k, true);
        clock.advance(const Duration(seconds: 1));
      }
      await favs.setFavorite(src, ContentKind.live, 'c', true);
      expect(await favs.favoriteKeys(src, ContentKind.live), ['c', 'a', 'b']);
      await favs.reorder(src, ContentKind.live, ['b', 'c', 'a']);
      expect(await favs.favoriteKeys(src, ContentKind.live), ['b', 'c', 'a']);
      final page = await favs.favoriteChannelsPage(src, offset: 1, limit: 1);
      expect(page.single.key, 'c');
      expect(page.single.item?.name, 'Channel c');
      expect(page.single.addedAt, testEpoch);
    });

    test('pages per kind and marks vanished items', () async {
      await favs.setFavorite(src, ContentKind.live, 'a', true);
      await favs.setFavorite(src, ContentKind.live, 'gone', true);
      await favs.setFavorite(src, ContentKind.movie, 'm', true);
      await favs.setFavorite(src, ContentKind.series, 's', true);
      final live = await favs.favoriteChannelsPage(src);
      expect(live.map((f) => (f.key, f.available)), [
        ('a', true),
        ('gone', false),
      ]);
      expect((await favs.favoriteMoviesPage(src)).single.item?.key, 'm');
      expect((await favs.favoriteSeriesPage(src)).single.item?.key, 's');
      expect(await favs.favoriteChannelsPage(src, limit: 0), isEmpty);
    });

    test('watchFavorites emits on change', () async {
      final seen = <Set<String>>[];
      final sub = favs.watchFavorites(src, ContentKind.live).listen(seen.add);
      await pumpEventQueue();
      await favs.toggleFavorite(src, ContentKind.live, 'b');
      await pumpEventQueue();
      await favs.toggleFavorite(src, ContentKind.live, 'a');
      await pumpEventQueue();
      await sub.cancel();
      expect(seen.first, isEmpty);
      expect(seen.last, {'b', 'a'});
      expect(seen.last.toList(), ['b', 'a']);
    });
  });

  group('watch progress', () {
    late ProgressDao progress;

    setUp(() => progress = db.progressDao);

    test('finished rule', () {
      const min = 60000;
      expect(ProgressDao.isFinished(95 * min, 100 * min), isTrue);
      expect(ProgressDao.isFinished(94 * min, 100 * min), isFalse);
      // Under 2 minutes left wins below 95 % (short videos).
      expect(ProgressDao.isFinished(28 * min + 1000, 30 * min), isTrue);
      expect(ProgressDao.isFinished(28 * min, 30 * min), isFalse);
      expect(ProgressDao.isFinished(28 * min - 1000, 30 * min), isFalse);
      expect(ProgressDao.isFinished(90000, 3 * min), isTrue);
      expect(ProgressDao.isFinished(10, 3 * min), isFalse);
      expect(ProgressDao.isFinished(50 * min, 0), isFalse);
      expect(ProgressDao.isFinished(50 * min, -1), isFalse);
    });

    test('saves, updates and keeps the series key', () async {
      await progress.saveProgress(
        src,
        PlayableKind.episode,
        'e1',
        1000,
        3600000,
        seriesKey: 's',
      );
      clock.advance(const Duration(minutes: 5));
      await progress.saveProgress(
        src,
        PlayableKind.episode,
        'e1',
        3590000,
        3600000,
      );
      final p = (await progress.progressFor(src, PlayableKind.episode, 'e1'))!;
      expect(p.seriesKey, 's');
      expect(p.position, const Duration(milliseconds: 3590000));
      expect(p.finished, isTrue);
      expect(p.updatedAt, testEpoch.add(const Duration(minutes: 5)));
      expect(p.fraction, closeTo(0.997, 0.001));
      expect(await progress.progressFor(src, PlayableKind.movie, 'e1'), isNull);

      await progress.saveProgress(src, PlayableKind.live, 'ch', 10, 0);
      expect(await countRows(db, 'watch_progress'), 1);

      await progress.clearProgress(src, PlayableKind.episode, 'e1');
      expect(
        await progress.progressFor(src, PlayableKind.episode, 'e1'),
        isNull,
      );
    });

    test(
      'continue watching: newest first, unfinished, one per series',
      () async {
        await syncCatalog(
          db,
          src,
          movies: [
            movie('m1', name: 'First'),
            movie('m2'),
            movie('m3'),
          ],
          seriesList: [
            const SeriesData(key: 's1', name: 'Show One', poster: 'p1.png'),
            series('s2'),
          ],
          episodes: [
            episode('s1', 'e1', number: 1, title: 'Pilot'),
            episode('s1', 'e2', number: 2, title: 'Second'),
            episode('s2', 'x1'),
          ],
        );
        Future<void> save(
          PlayableKind kind,
          String key,
          int pos, {
          String? seriesKey,
        }) async {
          await progress.saveProgress(
            src,
            kind,
            key,
            pos,
            3600000,
            seriesKey: seriesKey,
          );
          clock.advance(const Duration(minutes: 1));
        }

        await save(PlayableKind.movie, 'm1', 600000);
        await save(PlayableKind.episode, 'e1', 900000, seriesKey: 's1');
        await save(PlayableKind.movie, 'm2', 3500000); // finished
        await save(PlayableKind.movie, 'm3', 0); // not started
        await save(PlayableKind.episode, 'e2', 1200000, seriesKey: 's1');
        await save(PlayableKind.episode, 'x1', 3550000, seriesKey: 's2');
        await save(PlayableKind.movie, 'gone', 5000); // not in catalog

        final items = await progress.continueWatching(src);
        expect(items.map((i) => i.key), ['e2', 'm1']);
        final ep = items.first;
        expect(ep.kind, PlayableKind.episode);
        expect(ep.title, 'Second');
        expect(ep.seriesName, 'Show One');
        expect(ep.poster, 'p1.png');
        expect(ep.season, 1);
        expect(ep.episodeNumber, 2);
        expect(items.last.title, 'First');
        expect(await progress.continueWatching(src, limit: 1), hasLength(1));

        // Re-watching e1 makes it the series entry again.
        await save(PlayableKind.episode, 'e1', 950000, seriesKey: 's1');
        expect((await progress.continueWatching(src)).map((i) => i.key), [
          'e1',
          'm1',
        ]);

        final bySeries = await progress.progressForSeries(src, 's1');
        expect(bySeries.keys, unorderedEquals(['e1', 'e2']));
        expect((await progress.lastWatchedEpisode(src, 's1'))?.key, 'e1');
        expect((await progress.lastWatchedEpisode(src, 's2'))?.key, 'x1');
      },
    );

    test(
      'episodes without a fetched row still show via their series',
      () async {
        await syncCatalog(db, src, seriesList: [series('s9', name: 'Lazy')]);
        await progress.saveProgress(
          src,
          PlayableKind.episode,
          '9001',
          60000,
          3600000,
          seriesKey: 's9',
        );
        final item = (await progress.continueWatching(src)).single;
        expect(item.title, isNull);
        expect(item.seriesName, 'Lazy');
      },
    );

    test('watchContinueWatching emits updates', () async {
      await syncCatalog(db, src, movies: [movie('m1')]);
      final seen = <int>[];
      final sub = progress
          .watchContinueWatching(src)
          .listen((items) => seen.add(items.length));
      await pumpEventQueue();
      await progress.saveProgress(src, PlayableKind.movie, 'm1', 1000, 600000);
      await pumpEventQueue();
      await sub.cancel();
      expect(seen.first, 0);
      expect(seen.last, 1);
    });
  });

  group('recent channels', () {
    test('newest first, re-marking moves to the top', () async {
      await syncCatalog(db, src, channels: [channel('a'), channel('b')]);
      final recent = db.recentDao;
      // Same second: ordering still follows the call order.
      await recent.markRecent(src, 'a');
      await recent.markRecent(src, 'b');
      await recent.markRecent(src, 'gone');
      expect(await recent.recentChannelKeys(src), ['gone', 'b', 'a']);
      await recent.markRecent(src, 'a');
      expect(await recent.recentChannelKeys(src), ['a', 'gone', 'b']);
      expect((await recent.recentChannels(src)).map((c) => c.key), ['a', 'b']);
      expect(await recent.recentChannelKeys(src, limit: 1), ['a']);
    });

    test('keeps the last 50 per source', () async {
      final other = await addSource(db, name: 'Other');
      await db.recentDao.markRecent(other, 'keep');
      for (var i = 0; i < 60; i++) {
        await db.recentDao.markRecent(src, 'c$i');
        if (i.isEven) clock.advance(const Duration(seconds: 1));
      }
      final keys = await db.recentDao.recentChannelKeys(src, limit: 100);
      expect(keys, hasLength(RecentDao.maxEntries));
      expect(keys.first, 'c59');
      expect(keys.last, 'c10');
      expect(await db.recentDao.recentChannelKeys(other), ['keep']);
      await db.recentDao.clear(src);
      expect(await db.recentDao.recentChannelKeys(src), isEmpty);
      expect(await db.recentDao.recentChannelKeys(other), ['keep']);
    });

    test('watchRecentChannelKeys emits', () async {
      final seen = <List<String>>[];
      final sub = db.recentDao.watchRecentChannelKeys(src).listen(seen.add);
      await pumpEventQueue();
      await db.recentDao.markRecent(src, 'x');
      await pumpEventQueue();
      await sub.cancel();
      expect(seen.last, ['x']);
    });
  });

  group('channel prefs', () {
    test('partial updates keep other fields', () async {
      final prefs = db.prefsDao;
      expect((await prefs.prefsFor(src, 'a')).isEmpty, isTrue);
      await prefs.setEngine(src, 'a', EngineKind.mpv);
      await prefs.setAspect(src, 'a', AspectMode.ratio16x9);
      await prefs.setAudioLang(src, 'a', 'ara');
      var p = await prefs.prefsFor(src, 'a');
      expect(p.engine, EngineKind.mpv);
      expect(p.aspect, AspectMode.ratio16x9);
      expect(p.audioLang, 'ara');
      await prefs.setEngine(src, 'a', null);
      p = await prefs.prefsFor(src, 'a');
      expect(p.engine, isNull);
      expect(p.aspect, AspectMode.ratio16x9);
      expect((await prefs.prefsFor(src, 'b')).isEmpty, isTrue);
      await prefs.clearPrefs(src, 'a');
      expect((await prefs.prefsFor(src, 'a')).isEmpty, isTrue);
    });
  });

  group('detail cache', () {
    test('respects the 24 h TTL', () async {
      final cache = db.detailCacheDao;
      await cache.putJson(src, ContentKind.movie, 'm', '{"a":1}');
      clock.advance(const Duration(hours: 23));
      expect(await cache.getJson(src, ContentKind.movie, 'm'), '{"a":1}');
      expect(await cache.getJson(src, ContentKind.series, 'm'), isNull);
      clock.advance(const Duration(hours: 2));
      expect(await cache.getJson(src, ContentKind.movie, 'm'), isNull);
      expect(
        await cache.getJson(src, ContentKind.movie, 'm', allowStale: true),
        '{"a":1}',
      );
      await cache.putJson(src, ContentKind.movie, 'fresh', '{}');
      expect(await cache.purgeExpired(), 1);
      expect(await cache.getJson(src, ContentKind.movie, 'fresh'), '{}');
      await cache.invalidate(src, ContentKind.movie, 'fresh');
      expect(await cache.getJson(src, ContentKind.movie, 'fresh'), isNull);
    });

    test('typed details round-trip', () async {
      final cache = db.detailCacheDao;
      await cache.putMovieDetail(
        src,
        const MovieDetail(
          key: 'm',
          plot: 'A synthetic plot',
          durationSec: 5400,
          rating: 7.5,
          ext: 'mp4',
        ),
      );
      final m = (await cache.movieDetail(src, 'm'))!;
      expect(m.plot, 'A synthetic plot');
      expect(m.durationSec, 5400);
      expect(m.rating, 7.5);
      expect(m.ext, 'mp4');

      await cache.putSeriesDetail(
        src,
        const SeriesDetail(
          key: 's',
          plot: 'Series plot',
          seasons: [SeasonInfo(number: 1, name: 'Season 1', cover: 'c.png')],
          episodes: [
            EpisodeData(
              seriesKey: 's',
              key: '11',
              season: 1,
              number: 1,
              title: 'One',
              headers: {'Referer': 'http://example.com/'},
              durationSec: 1500,
            ),
          ],
        ),
      );
      final s = (await cache.seriesDetail(src, 's'))!;
      expect(s.plot, 'Series plot');
      expect(s.seasons.single.name, 'Season 1');
      expect(s.episodes.single.title, 'One');
      expect(s.episodes.single.headers, {'Referer': 'http://example.com/'});
      expect(s.episodes.single.durationSec, 1500);
      expect(await cache.seriesDetail(src, 'missing'), isNull);
    });

    test('unreadable entries are treated as missing', () async {
      final cache = db.detailCacheDao;
      await cache.putJson(src, ContentKind.movie, 'bad', 'not json');
      await cache.putJson(src, ContentKind.series, 'list', '[1, 2]');
      await cache.putJson(src, ContentKind.movie, 'typed', '{"plot": 3}');
      expect(await cache.movieDetail(src, 'bad'), isNull);
      expect(await cache.seriesDetail(src, 'list'), isNull);
      expect(await cache.movieDetail(src, 'typed'), isNull);
    });
  });
}
