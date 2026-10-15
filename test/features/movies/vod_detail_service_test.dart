import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/db/queries/vod_queries.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/features/vod_common/vod_detail_service.dart';
import 'package:iptv_player/sources/models.dart';

import 'vod_harness.dart';

void main() {
  late FakeClock clock;
  late AppDatabase db;
  late FakeVodAdapter adapter;
  late RingLog log;
  late VodDetailService service;
  late int xtream;
  late int m3u;
  var loads = 0;

  setUp(() async {
    clock = FakeClock(testEpoch);
    db = openVodDb(clock);
    adapter = FakeVodAdapter();
    log = RingLog();
    loads = 0;
    service = VodDetailService(
      db: db,
      log: log,
      adapters: (sourceId) async {
        loads++;
        return adapter;
      },
    );
    xtream = await addXtreamSource(db);
    m3u = await addM3uSource(db);
    await seedCatalog(
      db,
      xtream,
      series: const [SeriesData(key: 's1', name: 'Show')],
    );
  });

  tearDown(() => db.close());

  EpisodeData ep(String key, int season, int number) => EpisodeData(
    seriesKey: 'ignored',
    key: key,
    season: season,
    number: number,
  );

  group('movies', () {
    test('a fresh cache entry answers without the network', () async {
      adapter.onMovie = (key) async => MovieDetail(key: key, plot: 'Plot');
      final first = await service.movieDetail(xtream, 'm1');
      expect(first.value?.plot, 'Plot');
      expect(first.failed, isFalse);
      expect(adapter.movieCalls, ['m1']);
      expect(adapter.closed, 1);

      final second = await service.movieDetail(xtream, 'm1');
      expect(second.value?.plot, 'Plot');
      expect(adapter.movieCalls, ['m1']);
      expect(loads, 1);

      clock.advance(const Duration(hours: 25));
      await service.movieDetail(xtream, 'm1');
      expect(adapter.movieCalls, ['m1', 'm1']);
    });

    test('an empty answer is cached too', () async {
      final result = await service.movieDetail(xtream, 'm2');
      expect(result.value?.key, 'm2');
      expect(result.value?.plot, isNull);
      await service.movieDetail(xtream, 'm2');
      expect(adapter.movieCalls, ['m2']);
    });

    test('M3U sources never build an adapter', () async {
      final result = await service.movieDetail(m3u, 'http://x/1.mkv');
      expect(result.value, isNull);
      expect(result.failed, isFalse);
      expect(loads, 0);
    });

    test('failures fall back to stale details and are logged '
        'without credentials', () async {
      adapter.onMovie = (_) => Future.error(
        const NetworkFailure(
          'GET http://127.0.0.1:9/player_api.php?username=tester&password=secret-pass failed',
        ),
      );
      final none = await service.movieDetail(xtream, 'm1');
      expect(none.value, isNull);
      expect(none.failed, isTrue);
      expect(adapter.closed, 1);
      final logged = log.lines.join('\n');
      expect(logged, contains('Movie details failed'));
      expect(logged, isNot(contains('secret-pass')));

      await db.detailCacheDao.putMovieDetail(
        xtream,
        const MovieDetail(key: 'm1', plot: 'Old'),
      );
      clock.advance(const Duration(days: 2));
      final stale = await service.movieDetail(xtream, 'm1');
      expect(stale.value?.plot, 'Old');
      expect(stale.failed, isFalse);
    });

    test('an adapter that cannot be built is a failure, not a crash', () async {
      final broken = VodDetailService(
        db: db,
        log: log,
        adapters: (_) async => throw StateError('Unknown source'),
      );
      final result = await broken.movieDetail(xtream, 'm1');
      expect(result.failed, isTrue);
    });
  });

  group('series', () {
    test('fetched episodes are stored and the header cached', () async {
      adapter.onSeries = (key) async => SeriesDetail(
        key: key,
        plot: 'Plot',
        seasons: const [SeasonInfo(number: 1, name: 'One')],
        episodes: [ep('e1', 1, 1), ep('e2', 1, 2)],
      );
      final result = await service.seriesDetail(xtream, 's1');
      expect(result.value?.plot, 'Plot');
      expect(result.value?.episodes, hasLength(2));
      final stored = await db.catalogDao.episodesForSeries(xtream, 's1');
      expect(stored.map((e) => (e.key, e.seriesKey)), [
        ('e1', 's1'),
        ('e2', 's1'),
      ]);
      final cached = await db.detailCacheDao.seriesDetail(xtream, 's1');
      expect(cached?.seasons.single.name, 'One');
      expect(cached?.episodes, isEmpty);

      // Cache hit: no second call.
      final again = await service.seriesDetail(xtream, 's1');
      expect(again.value?.plot, 'Plot');
      expect(adapter.seriesCalls, ['s1']);

      // Without stored episodes the cache is not enough.
      await db.catalogDao.saveFetchedEpisodes(xtream, 's1', const []);
      await service.seriesDetail(xtream, 's1');
      expect(adapter.seriesCalls, ['s1', 's1']);
    });

    test('an empty answer keeps the episodes stored before', () async {
      await db.catalogDao.saveFetchedEpisodes(xtream, 's1', [ep('e1', 1, 1)]);
      adapter.onSeries = (key) async => SeriesDetail(key: key);
      final result = await service.seriesDetail(xtream, 's1');
      expect(result.failed, isFalse);
      expect(await db.catalogDao.episodesForSeries(xtream, 's1'), hasLength(1));
    });

    test('a failure is reported and keeps stored episodes', () async {
      await db.catalogDao.saveFetchedEpisodes(xtream, 's1', [ep('e1', 1, 1)]);
      adapter.onSeries = (_) => Future.error(const TimeoutFailure('slow'));
      final result = await service.seriesDetail(xtream, 's1');
      expect(result.failed, isTrue);
      expect(await db.catalogDao.episodesForSeries(xtream, 's1'), hasLength(1));
      expect(adapter.closed, 1);
    });

    test('M3U series come from the playlist import', () async {
      final result = await service.seriesDetail(m3u, 's1');
      expect(result.value, isNull);
      expect(result.failed, isFalse);
      expect(loads, 0);
    });
  });

  group('queries', () {
    test(
      'series progress includes entries saved without a series key',
      () async {
        await db.catalogDao.saveFetchedEpisodes(xtream, 's1', [
          ep('e1', 1, 1),
          ep('e2', 1, 2),
        ]);
        final progress = db.progressDao;
        await progress.saveProgress(xtream, PlayableKind.episode, 'e1', 1, 10);
        // Saved before its episode row existed: no series key.
        await progress.saveProgress(xtream, PlayableKind.episode, 'x9', 5, 10);
        await db.catalogDao.saveFetchedEpisodes(xtream, 's1', [
          ep('e1', 1, 1),
          ep('e2', 1, 2),
          ep('x9', 2, 1),
        ]);
        await progress.saveProgress(
          xtream,
          PlayableKind.episode,
          'other',
          5,
          10,
          seriesKey: 's2',
        );
        final map = await progress.watchProgressForSeries(xtream, 's1').first;
        expect(map.keys.toSet(), {'e1', 'x9'});
        expect(map['x9']!.position, const Duration(milliseconds: 5));
      },
    );

    test('episodes stream in season and number order', () async {
      await db.catalogDao.saveFetchedEpisodes(xtream, 's1', [
        ep('b', 2, 1),
        ep('a', 1, 2),
        ep('c', 1, 1),
      ]);
      final rows = await db.catalogDao
          .watchEpisodesForSeries(xtream, 's1')
          .first;
      expect(rows.map((e) => e.key), ['c', 'a', 'b']);
    });
  });
}
