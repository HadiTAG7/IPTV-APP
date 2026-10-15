import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/db/daos/query_utils.dart';
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

  group('paging', () {
    setUp(() async {
      await syncCatalog(
        db,
        src,
        categories: [category(ContentKind.live, 'news')],
        channels: [
          for (var i = 0; i < 25; i++)
            channel(
              'k$i',
              num: 100 - i,
              name: 'Name ${i.toString().padLeft(2, '0')}',
            ),
        ],
      );
    });

    test('category pages follow playlist positions', () async {
      final first = await catalog.channelsPage(src, 'news', 0, 10);
      final second = await catalog.channelsPage(src, 'news', 10, 10);
      final last = await catalog.channelsPage(src, 'news', 20, 10);
      expect(first.map((c) => c.key), [for (var i = 0; i < 10; i++) 'k$i']);
      expect(second.map((c) => c.key), [for (var i = 10; i < 20; i++) 'k$i']);
      expect(last.map((c) => c.key), [for (var i = 20; i < 25; i++) 'k$i']);
      expect(await catalog.channelsPage(src, 'news', 25, 10), isEmpty);
      expect(await catalog.channelsPage(src, 'news', 0, 0), isEmpty);
      expect(
        (await catalog.channelsPage(src, 'news', -5, 2)).map((c) => c.key),
        ['k0', 'k1'],
      );
      expect(await catalog.channelsPage(src, 'missing', 0, 10), isEmpty);
    });

    test('rows carry what the player needs', () async {
      final row = (await catalog.channelsPage(src, 'news', 3, 1)).single;
      expect(row.num, 97);
      expect(row.url, 'http://127.0.0.1:8080/live/k3.ts');
      final ref = row.toPlayable();
      expect(ref.kind, PlayableKind.live);
      expect(ref.key, 'k3');
    });

    test('zapping keys match page order', () async {
      final keys = await catalog.channelKeysInCategory(src, 'news');
      final paged = [
        for (var o = 0; o < 25; o += 7)
          ...(await catalog.channelsPage(src, 'news', o, 7)).map((c) => c.key),
      ];
      expect(keys, paged);
      expect(
        await catalog.positionInCategory(src, ContentKind.live, 'news', 'k12'),
        12,
      );
      expect(
        await catalog.positionInCategory(src, ContentKind.live, 'news', 'nope'),
        isNull,
      );
    });

    test('all channels: by number, unnumbered last, stable pages', () async {
      final gen = await catalog.beginGeneration(src);
      await catalog.upsertChannels(src, gen, [
        for (var i = 0; i < 25; i++)
          channel(
            'k$i',
            num: 100 - i,
            name: 'Name ${i.toString().padLeft(2, '0')}',
          ),
        channel('x', name: 'Bravo'),
        channel('y', name: 'alpha'),
        channel('z', num: 76, name: 'Same number'),
      ]);
      await catalog.commitGeneration(src, gen);

      final keys = await catalog.allChannelKeys(src);
      expect(keys.first, 'k24'); // num 76, "Name 24" < "Same number"
      expect(keys[1], 'z');
      expect(keys.sublist(keys.length - 2), ['y', 'x']); // nulls last, by name
      final paged = <String>[];
      for (var o = 0; o < 40; o += 6) {
        paged.addAll(
          (await catalog.allChannelsPage(src, o, 6)).map((c) => c.key),
        );
      }
      expect(paged, keys);
      expect(await catalog.totalCount(src, ContentKind.live), 28);
    });

    test('lookups by key, number and key list', () async {
      expect((await catalog.channelByKey(src, 'k5'))?.name, 'Name 05');
      expect(await catalog.channelByKey(src, 'missing'), isNull);
      expect((await catalog.channelByNumber(src, 90))?.key, 'k10');
      expect(await catalog.channelByNumber(src, 5000), isNull);
      final rows = await catalog.channelsByKeys(src, ['k7', 'missing', 'k2']);
      expect(rows.map((c) => c.key), ['k7', 'k2']);
      final many = [for (var i = 0; i < 2000; i++) 'k${i % 25}'];
      expect(await catalog.channelsByKeys(src, many), hasLength(2000));
    });

    test('pages are scoped to the source', () async {
      final other = await addSource(db, name: 'Other');
      await syncCatalog(db, other, channels: [channel('k0', name: 'Other k0')]);
      expect(await catalog.channelsPage(src, 'news', 0, 100), hasLength(25));
      expect((await catalog.channelByKey(other, 'k0'))?.name, 'Other k0');
      expect(await catalog.totalCount(other, ContentKind.live), 1);
    });
  });

  test('movies and series pages', () async {
    await syncCatalog(
      db,
      src,
      categories: [
        category(ContentKind.movie, 'films'),
        category(ContentKind.series, 'shows'),
      ],
      movies: [
        movie('m3', name: 'Charlie'),
        movie('m1', name: 'alpha'),
        movie('m2', name: 'Bravo', categories: ['films', 'kids']),
      ],
      seriesList: [
        series('s2', name: 'Zulu'),
        series('s1', name: 'Echo'),
      ],
    );
    expect((await catalog.moviesPage(src, 'films', 0, 10)).map((m) => m.key), [
      'm3',
      'm1',
      'm2',
    ]);
    expect((await catalog.moviesPage(src, 'kids', 0, 10)).map((m) => m.key), [
      'm2',
    ]);
    expect((await catalog.allMoviesPage(src, 0, 10)).map((m) => m.name), [
      'alpha',
      'Bravo',
      'Charlie',
    ]);
    expect((await catalog.allMoviesPage(src, 1, 1)).map((m) => m.name), [
      'Bravo',
    ]);
    expect((await catalog.seriesPage(src, 'shows', 0, 10)).map((s) => s.key), [
      's2',
      's1',
    ]);
    expect((await catalog.allSeriesPage(src, 0, 10)).map((s) => s.key), [
      's1',
      's2',
    ]);
    final m = await catalog.movieByKey(src, 'm2');
    expect(m?.ext, 'mkv');
    expect(m?.toPlayable().kind, PlayableKind.movie);
    expect((await catalog.seriesByKey(src, 's1'))?.name, 'Echo');
  });

  test('All movies: newest added first, then natural name order', () async {
    final day = DateTime.utc(2026, 3);
    MovieData m(String key, String name, [int? addedDay]) => MovieData(
      key: key,
      name: name,
      categoryKeys: const ['films'],
      addedAt: addedDay == null ? null : day.add(Duration(days: addedDay)),
    );
    await syncCatalog(
      db,
      src,
      categories: [
        category(ContentKind.movie, 'films'),
        category(ContentKind.series, 'shows'),
      ],
      movies: [
        m('a', 'Movie 10'),
        m('b', 'Movie 2'),
        m('c', 'movie 1'),
        m('d', 'Movie'),
        m('e', '21 Jump Street'),
        m('f', '2012'),
        m('g', 'Zulu', 1),
        m('h', 'Alpha 10', 5),
        m('i', 'Alpha 9', 5),
        m('j', 'فيلم ٣'),
        m('k', 'فيلم 12'),
      ],
      seriesList: [
        series('s1', name: 'Show 10'),
        series('s2', name: 'Show 9'),
        series('s3', name: 'Show'),
        series('s4', name: 'Another 1'),
      ],
    );
    final movies = await catalog.allMoviesPage(src, 0, 20);
    expect(movies.map((m) => m.name), [
      // Newest first; a tie by natural name.
      'Alpha 9',
      'Alpha 10',
      'Zulu',
      // No added time: natural name order (digits before letters, the
      // number compared as a number, Arabic-Indic digits folded).
      '21 Jump Street',
      '2012',
      'Movie',
      'movie 1',
      'Movie 2',
      'Movie 10',
      'فيلم ٣',
      'فيلم 12',
    ]);
    // Pages follow the same order.
    expect((await catalog.allMoviesPage(src, 4, 3)).map((m) => m.key), [
      'f',
      'd',
      'c',
    ]);
    expect((await catalog.allSeriesPage(src, 0, 10)).map((s) => s.name), [
      'Another 1',
      'Show',
      'Show 9',
      'Show 10',
    ]);
  });

  test('episodes are ordered by season and number', () async {
    await syncCatalog(
      db,
      src,
      seriesList: [series('s')],
      episodes: [
        episode('s', 'e5', season: 2, number: 1),
        episode('s', 'e2', season: 1, number: 10),
        episode('s', 'e1', season: 1, number: 2),
        episode('s', 'e9', season: 0, number: 1),
      ],
    );
    final eps = await catalog.episodesForSeries(src, 's');
    expect(eps.map((e) => e.key), ['e9', 'e1', 'e2', 'e5']);
    expect((await catalog.episodeByKey(src, 'e5'))?.season, 2);
    expect(eps.first.toPlayable().kind, PlayableKind.episode);
  });

  test('headers round-trip through storage', () async {
    final gen = await catalog.beginGeneration(src);
    await catalog.upsertChannels(src, gen, [
      const ChannelData(
        key: 'h',
        name: 'Headers',
        headers: {
          'User-Agent': 'TestAgent/1.0',
          'Referer': 'http://example.com/',
        },
        isRadio: true,
        tvgShiftMin: 60,
        catchupDays: 3,
      ),
    ]);
    await catalog.commitGeneration(src, gen);
    final row = (await catalog.channelByKey(src, 'h'))!;
    expect(row.headers, {
      'User-Agent': 'TestAgent/1.0',
      'Referer': 'http://example.com/',
    });
    expect(row.isRadio, isTrue);
    expect(row.tvgShiftMin, 60);
    expect(row.catchupDays, 3);
  });

  test('watchCategories emits after a commit', () async {
    final seen = <List<String>>[];
    final sub = catalog
        .watchCategories(src, ContentKind.live)
        .listen((cats) => seen.add([for (final c in cats) c.key]));
    await pumpEventQueue();
    await syncCatalog(
      db,
      src,
      categories: [category(ContentKind.live, 'news')],
      channels: [channel('a')],
    );
    await pumpEventQueue();
    await sub.cancel();
    expect(seen.first, isEmpty);
    expect(seen.last, ['news']);
  });

  group('search', () {
    setUp(() async {
      await syncCatalog(
        db,
        src,
        channels: [
          channel('jz', name: 'قناة الجَزِيرَة'),
          channel('ar', name: 'العربية HD'),
          channel('ak', name: 'أخبار المساء'),
          channel('mbc', name: 'MBC ٢'),
          channel('pct', name: '100% Hits'),
          channel('und', name: 'A_B Music'),
          channel('aab', name: 'AAB Music'),
          channel('bsl', name: r'Back\slash TV'),
          channel('wn', name: 'World News'),
          channel('nw', name: 'News 24'),
        ],
        movies: [movie('m', name: 'News Movie')],
        seriesList: [series('s', name: 'The News Hour')],
      );
    });

    Future<List<String>> channelKeys(String q, {int limit = 50}) async => [
      for (final c in (await catalog.search(
        src,
        q,
        limitPerKind: limit,
      )).channels)
        c.key,
    ];

    test('folds Arabic letters and diacritics', () async {
      expect(await channelKeys('الجزيره'), ['jz']);
      expect(await channelKeys('الجَزيرة'), ['jz']);
      expect(await channelKeys('اخبار'), ['ak']);
      expect(await channelKeys('العربيه'), ['ar']);
      expect(await channelKeys('mbc 2'), ['mbc']);
      expect(await channelKeys('MBC ٢'), ['mbc']);
    });

    test('is case-insensitive and ranks earlier matches first', () async {
      expect(await channelKeys('NEWS'), ['nw', 'wn']);
      expect(await channelKeys('news', limit: 1), ['nw']);
    });

    test('treats LIKE wildcards literally', () async {
      expect(await channelKeys('%'), ['pct']);
      expect(await channelKeys('0%'), ['pct']);
      expect(await channelKeys('_'), ['und']);
      expect(await channelKeys('a_b'), ['und']);
      expect(await channelKeys(r'\'), ['bsl']);
      expect(await channelKeys(r'k\s'), ['bsl']);
    });

    test('groups results by kind', () async {
      final r = await catalog.search(src, 'news');
      expect(r.channels.map((c) => c.key), ['nw', 'wn']);
      expect(r.movies.map((m) => m.key), ['m']);
      expect(r.series.map((s) => s.key), ['s']);
      final moviesOnly = await catalog.search(
        src,
        'news',
        kinds: {ContentKind.movie},
      );
      expect(moviesOnly.channels, isEmpty);
      expect(moviesOnly.series, isEmpty);
      expect(moviesOnly.movies, hasLength(1));
    });

    test('empty queries return nothing', () async {
      expect((await catalog.search(src, '')).isEmpty, isTrue);
      expect((await catalog.search(src, '   ')).isEmpty, isTrue);
      expect((await catalog.search(src, 'zzz')).isEmpty, isTrue);
      expect(
        (await catalog.search(src, 'news', limitPerKind: 0)).isEmpty,
        isTrue,
      );
    });

    test('does not leak across sources', () async {
      final other = await addSource(db, name: 'Other');
      expect((await catalog.search(other, 'news')).isEmpty, isTrue);
    });
  });

  test('channel identities for EPG matching', () async {
    await syncCatalog(
      db,
      src,
      channels: [
        channel('a', name: 'Alpha', tvgId: 'alpha.example'),
        channel('b', name: 'Bravo'),
      ],
    );
    final ids = await catalog.channelIdentities(src);
    expect(ids, hasLength(2));
    final alpha = ids.firstWhere((c) => c.key == 'a');
    expect(alpha.tvgId, 'alpha.example');
    expect(alpha.name, 'Alpha');
    expect(escapeLike(r'a%b_c\d'), r'a\%b\_c\\d');
  });
}
