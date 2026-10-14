import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/epg/epg_models.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/sources/models.dart';

import 'db_test_utils.dart';

void main() {
  late AppDatabase db;
  late CatalogDao catalog;
  late int src;

  setUp(() async {
    db = openTestDb();
    catalog = db.catalogDao;
    src = await addSource(db);
  });

  tearDown(() => db.close());

  Future<List<String>> keysIn(String categoryKey) async => [
    for (final c in await catalog.channelsPage(src, categoryKey, 0, 1000))
      c.key,
  ];

  group('first sync', () {
    test('nothing is visible before the commit', () async {
      expect(await catalog.committedGeneration(src), 0);
      final gen = await catalog.beginGeneration(src);
      expect(gen, 1);
      await catalog.upsertCategories(src, gen, [
        category(ContentKind.live, 'news'),
      ]);
      await catalog.upsertChannels(src, gen, [channel('a'), channel('b')]);

      expect(await catalog.categories(src, ContentKind.live), isEmpty);
      expect(await keysIn('news'), isEmpty);
      expect(await catalog.allChannelsPage(src, 0, 10), isEmpty);
      expect((await catalog.search(src, 'channel')).channels, isEmpty);
      expect(await catalog.totalCount(src, ContentKind.live), 0);

      await catalog.commitGeneration(src, gen);

      expect(await catalog.committedGeneration(src), 1);
      expect((await db.sourcesDao.byId(src))!.generation, 1);
      final cats = await catalog.categories(src, ContentKind.live);
      expect(cats.single.key, 'news');
      expect(cats.single.itemCount, 2);
      expect(await keysIn('news'), ['a', 'b']);
      expect((await catalog.search(src, 'channel')).channels, hasLength(2));
    });

    test('unknown source is rejected', () async {
      expect(() => catalog.beginGeneration(9999), throwsStateError);
    });
  });

  group('refresh', () {
    test('keeps favourites, progress, prefs, recent and EPG links', () async {
      await syncCatalog(
        db,
        src,
        categories: [category(ContentKind.live, 'news')],
        channels: [channel('a'), channel('b')],
        movies: [movie('m1')],
        seriesList: [series('s1')],
      );
      await db.favoritesDao.setFavorite(src, ContentKind.live, 'a', true);
      await db.favoritesDao.setFavorite(src, ContentKind.movie, 'm1', true);
      await db.progressDao.saveProgress(
        src,
        PlayableKind.movie,
        'm1',
        60000,
        3600000,
      );
      await db.prefsDao.setEngine(src, 'a', EngineKind.mpv);
      await db.recentDao.markRecent(src, 'a');
      final epg = await db.epgDao.addEpgSource(
        src,
        'http://127.0.0.1:8080/guide.xml',
        EpgOrigin.manual,
      );
      await db.epgDao.replaceChannelMap(src, {
        'a': (epgSourceId: epg, xmltvId: 'a.example', kind: EpgMatchKind.tvgId),
      });

      // Second sync: channel a is gone, b and the movie remain.
      await syncCatalog(
        db,
        src,
        categories: [category(ContentKind.live, 'news')],
        channels: [channel('b'), channel('c')],
        movies: [movie('m1')],
        seriesList: [series('s1')],
      );

      expect(await catalog.channelByKey(src, 'a'), isNull);
      expect(
        await db.favoritesDao.isFavorite(src, ContentKind.live, 'a'),
        isTrue,
      );
      final favs = await db.favoritesDao.favoriteChannelsPage(src);
      expect(favs.single.key, 'a');
      expect(favs.single.available, isFalse);
      final movieFavs = await db.favoritesDao.favoriteMoviesPage(src);
      expect(movieFavs.single.item?.name, 'Movie m1');
      final progress = await db.progressDao.progressFor(
        src,
        PlayableKind.movie,
        'm1',
      );
      expect(progress?.position, const Duration(minutes: 1));
      expect((await db.prefsDao.prefsFor(src, 'a')).engine, EngineKind.mpv);
      expect(await db.recentDao.recentChannelKeys(src), ['a']);
      expect(await db.recentDao.recentChannels(src), isEmpty);
      expect((await db.epgDao.linkFor(src, 'a'))?.xmltvId, 'a.example');
      expect(await db.progressDao.continueWatching(src), hasLength(1));
    });

    test('old rows disappear only on commit', () async {
      await syncCatalog(
        db,
        src,
        categories: [category(ContentKind.live, 'news')],
        channels: [channel('a'), channel('b')],
      );
      final gen = await catalog.beginGeneration(src);
      expect(gen, 2);
      await catalog.upsertCategories(src, gen, [
        category(ContentKind.live, 'news'),
        category(ContentKind.live, 'sports'),
      ]);
      await catalog.upsertChannels(src, gen, [
        channel('b', name: 'Bravo Renamed'),
        channel('c', categories: ['sports']),
      ]);

      // Readers still see generation 1 membership.
      expect(await keysIn('news'), ['a', 'b']);
      expect(await catalog.channelByKey(src, 'a'), isNotNull);
      expect(
        [
          for (final c in await catalog.categories(src, ContentKind.live))
            c.key,
        ],
        ['news'],
      );
      // "Bravo Renamed" sorts before "Channel a"; c is not committed yet.
      expect(
        [for (final c in await catalog.allChannelsPage(src, 0, 10)) c.key],
        ['b', 'a'],
      );
      expect(await keysIn('sports'), isEmpty);
      // Existing rows refresh in place.
      expect((await catalog.channelByKey(src, 'b'))!.name, 'Bravo Renamed');

      await catalog.commitGeneration(src, gen);

      expect(await catalog.channelByKey(src, 'a'), isNull);
      expect(await keysIn('news'), ['b']);
      expect(await keysIn('sports'), ['c']);
      expect(await countRows(db, 'channels'), 2);
      final items = await membership(db, src, ContentKind.live, 'news');
      expect(items.map((i) => i.generation).toSet(), {2});
      final cats = {
        for (final c in await catalog.categories(src, ContentKind.live))
          c.key: c.itemCount,
      };
      expect(cats, {'news': 1, 'sports': 1});
    });

    test('hidden categories stay hidden across syncs', () async {
      await syncCatalog(
        db,
        src,
        categories: [
          category(ContentKind.live, 'news'),
          category(ContentKind.live, 'adult'),
        ],
        channels: [channel('a')],
      );
      await catalog.setCategoryHidden(src, ContentKind.live, 'adult', true);
      await syncCatalog(
        db,
        src,
        categories: [
          category(ContentKind.live, 'news'),
          category(ContentKind.live, 'adult', name: 'Adult renamed'),
        ],
        channels: [channel('a')],
      );
      final visible = await catalog.categories(src, ContentKind.live);
      expect(visible.map((c) => c.key), ['news']);
      final all = await catalog.categories(
        src,
        ContentKind.live,
        includeHidden: true,
      );
      final adult = all.firstWhere((c) => c.key == 'adult');
      expect(adult.hidden, isTrue);
      expect(adult.name, 'Adult renamed');
    });

    test('categories follow provider sort order', () async {
      await syncCatalog(
        db,
        src,
        categories: [
          category(ContentKind.live, 'z', sortIndex: 0),
          category(ContentKind.live, 'a', sortIndex: 2),
          category(ContentKind.live, 'm', sortIndex: 1),
          category(ContentKind.movie, 'films'),
        ],
      );
      expect(
        [
          for (final c in await catalog.categories(src, ContentKind.live))
            c.key,
        ],
        ['z', 'm', 'a'],
      );
      expect(
        [
          for (final c in await catalog.categories(src, ContentKind.movie))
            c.key,
        ],
        ['films'],
      );
    });
  });

  group('abort', () {
    test('leaves the committed generation intact', () async {
      await syncCatalog(
        db,
        src,
        categories: [category(ContentKind.live, 'news')],
        channels: [channel('a'), channel('b')],
        movies: [movie('m1')],
      );
      final gen = await catalog.beginGeneration(src);
      await catalog.upsertCategories(src, gen, [
        category(ContentKind.live, 'news'),
        category(ContentKind.live, 'sports'),
      ]);
      await catalog.upsertChannels(src, gen, [
        channel('b', name: 'Bravo New'),
        channel('c', categories: ['sports']),
      ]);
      await catalog.upsertMovies(src, gen, [movie('m2')]);
      await catalog.abortGeneration(src, gen);

      expect(await catalog.committedGeneration(src), 1);
      expect(await keysIn('news'), ['a', 'b']);
      expect(await catalog.channelByKey(src, 'a'), isNotNull);
      expect(await catalog.channelByKey(src, 'b'), isNotNull);
      expect(await catalog.channelByKey(src, 'c'), isNull);
      expect(await catalog.movieByKey(src, 'm1'), isNotNull);
      expect(await catalog.movieByKey(src, 'm2'), isNull);
      final cats = await catalog.categories(
        src,
        ContentKind.live,
        includeHidden: true,
      );
      expect(cats.map((c) => c.key), ['news']);
      expect(await countRows(db, 'categories'), 1);
      final items = await membership(db, src, ContentKind.live, 'news');
      expect(items.map((i) => (i.generation, i.position, i.itemKey)), [
        (1, 0, 'a'),
        (1, 1, 'b'),
      ]);
      // Every remaining row is back on the committed generation.
      final gens = await db
          .customSelect('SELECT DISTINCT generation FROM channels')
          .get();
      expect(gens.map((r) => r.read<int>('generation')), [1]);

      // The next sync reuses the generation number and works normally.
      final next = await catalog.beginGeneration(src);
      expect(next, 2);
      await catalog.upsertChannels(src, next, [channel('b')]);
      await catalog.commitGeneration(src, next);
      expect(await keysIn('news'), ['b']);
    });

    test('is a no-op for a committed generation', () async {
      final gen = await syncCatalog(db, src, channels: [channel('a')]);
      await catalog.abortGeneration(src, gen);
      expect(await keysIn('news'), ['a']);
      expect(await catalog.committedGeneration(src), 1);
    });

    test('begin discards leftovers of an interrupted sync', () async {
      await syncCatalog(db, src, channels: [channel('a')]);
      final gen = await catalog.beginGeneration(src);
      await catalog.upsertChannels(src, gen, [channel('zombie')]);

      // A fresh DAO (e.g. after an app restart) starts over.
      final restarted = CatalogDao(db);
      final again = await restarted.beginGeneration(src);
      expect(again, gen);
      expect(await catalog.channelByKey(src, 'zombie'), isNull);
      expect(await membership(db, src, ContentKind.live, 'news'), hasLength(1));
    });
  });

  group('guards', () {
    test('writes and commits require the open generation', () async {
      final gen = await syncCatalog(db, src, channels: [channel('a')]);
      expect(
        () => catalog.upsertChannels(src, gen, [channel('b')]),
        throwsStateError,
      );
      expect(() => catalog.commitGeneration(src, gen), throwsStateError);
      expect(() => catalog.commitGeneration(src, gen + 2), throwsStateError);
      expect(await catalog.channelByKey(src, 'b'), isNull);
    });

    test('empty batches are accepted', () async {
      final gen = await catalog.beginGeneration(src);
      await catalog.upsertChannels(src, gen, const []);
      await catalog.upsertCategories(src, gen, const []);
      await catalog.commitGeneration(src, gen);
      expect(await catalog.committedGeneration(src), 1);
    });
  });

  group('positions', () {
    test('multi-category items get dense positions across batches', () async {
      final gen = await catalog.beginGeneration(src);
      await catalog.upsertChannels(src, gen, [
        channel('a', categories: ['news', 'sports']),
        channel('b', categories: ['news']),
        channel('c', categories: ['sports', 'sports', 'kids']),
      ]);
      await catalog.upsertChannels(src, gen, [
        channel('d', categories: ['kids', 'news']),
        channel('e', categories: const []),
      ]);
      await catalog.commitGeneration(src, gen);

      Future<List<(int, String)>> positions(String cat) async => [
        for (final i in await membership(db, src, ContentKind.live, cat))
          (i.position, i.itemKey),
      ];
      expect(await positions('news'), [(0, 'a'), (1, 'b'), (2, 'd')]);
      expect(await positions('sports'), [(0, 'a'), (1, 'c')]);
      expect(await positions('kids'), [(0, 'c'), (1, 'd')]);
      // Channels without categories are still listed under "All".
      expect(await catalog.totalCount(src, ContentKind.live), 5);
      expect(await catalog.itemCount(src, ContentKind.live, 'news'), 3);
      expect(await catalog.itemCount(src, ContentKind.live, 'missing'), 0);
    });

    test('kinds have independent position spaces', () async {
      final gen = await catalog.beginGeneration(src);
      await catalog.upsertChannels(src, gen, [
        channel('a', categories: ['mixed']),
      ]);
      await catalog.upsertMovies(src, gen, [
        movie('m', categories: ['mixed']),
      ]);
      await catalog.commitGeneration(src, gen);
      expect(
        (await membership(db, src, ContentKind.movie, 'mixed')).single.position,
        0,
      );
    });

    test('a failed batch does not leave gaps', () async {
      final gen = await catalog.beginGeneration(src);
      await catalog.upsertChannels(src, gen, [channel('a')]);
      await db.customStatement(
        'CREATE TEMP TRIGGER fail_boom BEFORE INSERT ON channels '
        "WHEN NEW.\"key\" = 'boom' BEGIN SELECT RAISE(ABORT, 'boom'); END",
      );
      await expectLater(
        catalog.upsertChannels(src, gen, [channel('b'), channel('boom')]),
        throwsA(anything),
      );
      await catalog.upsertChannels(src, gen, [channel('c')]);
      await catalog.commitGeneration(src, gen);
      expect(await keysIn('news'), ['a', 'c']);
      expect(
        [
          for (final i in await membership(db, src, ContentKind.live, 'news'))
            i.position,
        ],
        [0, 1],
      );
    });

    test('a second DAO continues an open generation densely', () async {
      final gen = await catalog.beginGeneration(src);
      await catalog.upsertChannels(src, gen, [channel('a'), channel('b')]);
      final other = CatalogDao(db);
      await other.upsertChannels(src, gen, [channel('c')]);
      await other.commitGeneration(src, gen);
      expect(await keysIn('news'), ['a', 'b', 'c']);
    });
  });

  group('partial sync', () {
    test('kinds not refreshed keep their committed rows', () async {
      await syncCatalog(
        db,
        src,
        categories: [
          category(ContentKind.live, 'news'),
          category(ContentKind.movie, 'films'),
          category(ContentKind.series, 'shows'),
        ],
        channels: [channel('a')],
        movies: [movie('m1'), movie('m2')],
        seriesList: [series('s1')],
        episodes: [episode('s1', 'e1')],
      );
      final gen = await catalog.beginGeneration(src);
      await catalog.upsertCategories(src, gen, [
        category(ContentKind.live, 'news'),
      ]);
      await catalog.upsertChannels(src, gen, [channel('b')]);
      await catalog.commitGeneration(src, gen, kinds: {ContentKind.live});

      expect(await keysIn('news'), ['b']);
      expect(
        [for (final m in await catalog.moviesPage(src, 'films', 0, 10)) m.key],
        ['m1', 'm2'],
      );
      expect(
        [for (final s in await catalog.seriesPage(src, 'shows', 0, 10)) s.key],
        ['s1'],
      );
      expect(await catalog.episodesForSeries(src, 's1'), hasLength(1));
      final films = await catalog.categories(src, ContentKind.movie);
      expect(films.single.itemCount, 2);
    });
  });

  group('episodes', () {
    test('playlist episodes follow the swap', () async {
      await syncCatalog(
        db,
        src,
        seriesList: [series('s1')],
        episodes: [episode('s1', 'e1'), episode('s1', 'e2', number: 2)],
      );
      await syncCatalog(
        db,
        src,
        seriesList: [series('s1')],
        episodes: [episode('s1', 'e2', number: 2)],
      );
      expect(
        [for (final e in await catalog.episodesForSeries(src, 's1')) e.key],
        ['e2'],
      );
    });

    test('fetched episodes survive syncs until their series is gone', () async {
      final xt = await addSource(
        db,
        kind: SourceKind.xtream,
        url: 'http://127.0.0.1:8080',
      );
      await syncCatalog(db, xt, seriesList: [series('s1'), series('s2')]);
      await catalog.saveFetchedEpisodes(xt, 's1', [
        episode('s1', '101', season: 2, number: 1),
        episode('s1', '102', season: 1, number: 2),
        episode('s1', '103', season: 1, number: 1),
      ]);
      await catalog.saveFetchedEpisodes(xt, 's2', [episode('s2', '201')]);
      expect(
        [for (final e in await catalog.episodesForSeries(xt, 's1')) e.key],
        ['103', '102', '101'],
      );

      // Refetching replaces the previous set.
      await catalog.saveFetchedEpisodes(xt, 's1', [
        episode('s1', '103'),
        episode('s1', '104', number: 2),
      ]);
      expect(
        [for (final e in await catalog.episodesForSeries(xt, 's1')) e.key],
        ['103', '104'],
      );

      await syncCatalog(db, xt, seriesList: [series('s1')]);
      expect(await catalog.episodesForSeries(xt, 's1'), hasLength(2));
      expect(await catalog.episodesForSeries(xt, 's2'), isEmpty);
    });
  });

  test('deleting a source removes its catalog and user data', () async {
    await syncCatalog(
      db,
      src,
      categories: [category(ContentKind.live, 'news')],
      channels: [channel('a')],
    );
    await db.favoritesDao.setFavorite(src, ContentKind.live, 'a', true);
    await db.sourcesDao.deleteSource(src);
    for (final table in [
      'categories',
      'category_items',
      'channels',
      'favorites',
    ]) {
      expect(await countRows(db, table), 0, reason: table);
    }
  });

  test('the write session wraps the same protocol', () async {
    final session = await catalog.openGeneration(src);
    expect(session.generation, 1);
    await session.categories([category(ContentKind.live, 'news')]);
    await session.channels([channel('a')]);
    await session.movies([movie('m')]);
    await session.series([series('s')]);
    await session.episodes([episode('s', 'e')]);
    await session.commit();
    expect(await keysIn('news'), ['a']);

    final second = await catalog.openGeneration(src);
    await second.channels([channel('b')]);
    await second.abort();
    expect(await keysIn('news'), ['a']);
  });

  test('programmes are untouched by catalog syncs', () async {
    final epg = await db.epgDao.addEpgSource(
      src,
      'http://127.0.0.1:8080/guide.xml',
      EpgOrigin.manual,
    );
    await db.epgDao.insertProgrammes(epg, [
      EpgProgramme(
        channelId: 'x',
        start: testEpoch,
        stop: testEpoch.add(const Duration(hours: 1)),
        title: 'Show',
      ),
    ]);
    await syncCatalog(db, src, channels: [channel('a')]);
    expect(await db.epgDao.programmeCount(epg), 1);
  });
}
