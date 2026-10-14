import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/net/http.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/sources/xtream/xtream_adapter.dart';

import 'support/fake_http_adapter.dart';

const _base = 'http://panel.example.com:8080';
const _u = 'demo%20user';
const _p = 'p%40ss%2Fw%20rd';

const _config = SourceConfig(
  kind: SourceKind.xtream,
  url: 'panel.example.com:8080/',
  username: 'demo user',
  password: 'p@ss/w rd',
);

FakeHttpAdapter fullPanel() => FakeHttpAdapter({
  '': FakeReply.fixture('auth_ok.json'),
  'get_live_categories': FakeReply.fixture('live_categories.json'),
  'get_live_streams': FakeReply.fixture('live_streams.json', chunkSize: 97),
  'get_vod_categories': FakeReply.fixture('vod_categories.json'),
  'get_vod_streams': FakeReply.fixture('vod_streams.json', chunkSize: 13),
  'get_series_categories': FakeReply.fixture('series_categories.json'),
  'get_series': FakeReply.fixture('series.json'),
  'get_series_info': FakeReply.fixture('series_info_map.json'),
  'get_vod_info': FakeReply.fixture('vod_info.json'),
  'get_short_epg': FakeReply.fixture('short_epg.json'),
});

XtreamAdapter makeAdapter(
  FakeHttpAdapter http, {
  SourceConfig config = _config,
  bool lowMemory = false,
  Duration fullListTimeout = const Duration(seconds: 60),
}) => XtreamAdapter(
  config,
  dio: fakeDio(http),
  lowMemory: lowMemory,
  fullListTimeout: fullListTimeout,
);

String describe(SyncBatch b) => switch (b) {
  CategoriesBatch(:final items) =>
    'categories(${items.first.kind.name}:${items.length})',
  ChannelsBatch(:final items) => 'channels(${items.length})',
  MoviesBatch(:final items) => 'movies(${items.length})',
  SeriesBatch(:final items) => 'series(${items.length})',
  EpisodesBatch(:final items) => 'episodes(${items.length})',
  EpgHintBatch() => 'epg',
  PhaseDoneBatch(:final kind) => 'done(${kind.name})',
};

List<T> itemsOf<T>(List<SyncBatch> batches) => [
  for (final b in batches)
    ...switch (b) {
      ChannelsBatch(:final items) => items,
      MoviesBatch(:final items) => items,
      SeriesBatch(:final items) => items,
      CategoriesBatch(:final items) => items,
      _ => const <Object>[],
    }.whereType<T>(),
];

Map<String, Object?> stream(int id, {String? category, String? name}) => {
  'stream_id': id,
  'name': name ?? 'Channel $id',
  'category_id': ?category,
};

Future<SourceFailure> failureOf(Future<Object?> f) async {
  try {
    await f;
  } on SourceFailure catch (e) {
    return e;
  }
  fail('expected a SourceFailure');
}

void main() {
  test('capabilities', () {
    final caps = makeAdapter(FakeHttpAdapter()).caps;
    expect(caps.live, isTrue);
    expect(caps.movies, isTrue);
    expect(caps.series, isTrue);
    expect(caps.shortEpg, isTrue);
    expect(caps.catchup, isFalse);
  });

  test('verify authenticates and remembers allowed formats', () async {
    final http = fullPanel();
    final adapter = makeAdapter(
      http,
      config: _config.copyWith(liveFormat: LiveFormat.m3u8),
    );
    final info = await adapter.verify();
    expect(info.status, AccountStatus.active);
    expect(adapter.allowedFormats, ['m3u8', 'ts', 'rtmp']);
    expect(http.calls, ['']);
  });

  test('verify propagates AuthFailure', () async {
    final http = FakeHttpAdapter({'': FakeReply.json([])});
    expect(await failureOf(makeAdapter(http).verify()), isA<AuthFailure>());
  });

  group('fetchCatalog', () {
    test('order: live, then movies, then series', () async {
      final http = fullPanel();
      final batches = await makeAdapter(http).fetchCatalog().toList();
      expect(batches.map(describe), [
        'categories(live:3)',
        'channels(5)',
        'done(live)',
        'categories(movie:2)',
        'movies(3)',
        'done(movie)',
        'categories(series:1)',
        'series(2)',
        'done(series)',
      ]);
      expect(http.calls, [
        'get_live_categories',
        'get_live_streams',
        'get_vod_categories',
        'get_vod_streams',
        'get_series_categories',
        'get_series',
      ]);
    });

    test('categories keep panel order and string keys', () async {
      final batches = await makeAdapter(fullPanel())
          .fetchCatalog(const SyncScope(movies: false, series: false))
          .toList();
      final cats = itemsOf<CategoryData>(batches);
      expect(cats.map((c) => c.key), ['10', '20', '30']);
      expect(cats.map((c) => c.name), ['News | أخبار', 'Sports', 'Radio']);
      expect(cats.map((c) => c.sortIndex), [0, 1, 2]);
      expect(cats.every((c) => c.kind == ContentKind.live), isTrue);
    });

    test('channels are mapped tolerantly', () async {
      final batches = await makeAdapter(fullPanel())
          .fetchCatalog(const SyncScope(movies: false, series: false))
          .toList();
      final ch = {for (final c in itemsOf<ChannelData>(batches)) c.key: c};
      expect(ch.keys, ['101', '102', '201', '301', '401']);

      final news = ch['101']!;
      expect(news.num, 1);
      expect(news.name, 'Example News HD');
      expect(news.logo, 'http://127.0.0.1/logos/news.png');
      expect(news.tvgId, 'news.example');
      expect(news.isRadio, isFalse);
      expect(news.categoryKeys, ['10']);
      expect(news.catchupMode, 'xc');
      expect(news.catchupDays, 7);
      expect(news.url, isNull);
      expect(news.headers, isEmpty);

      final arabic = ch['102']!;
      expect(arabic.num, 2);
      expect(arabic.name, 'قناة الأخبار التجريبية');
      expect(arabic.logo, isNull);
      expect(arabic.tvgId, isNull);
      expect(arabic.catchupMode, isNull);
      expect(arabic.catchupDays, 0);

      final sports = ch['201']!;
      expect(sports.name, 'Example Sports 1 {"live"} [FHD]');
      expect(sports.categoryKeys, ['20', '10']);
      expect(sports.catchupMode, 'xc');
      expect(sports.catchupDays, 3);

      expect(ch['301']!.isRadio, isTrue);
      expect(ch['401']!.categoryKeys, isEmpty);
    });

    test('direct_source is dropped', () async {
      final batches = await makeAdapter(fullPanel())
          .fetchCatalog(const SyncScope(movies: false, series: false))
          .toList();
      for (final c in itemsOf<ChannelData>(batches)) {
        expect(c.url, isNull);
        expect(
          [c.name, c.logo, c.tvgId, c.tvgName, c.catchupSource].join(),
          isNot(contains('secret')),
        );
      }
    });

    test('movies are mapped tolerantly', () async {
      final batches = await makeAdapter(fullPanel())
          .fetchCatalog(const SyncScope(live: false, series: false))
          .toList();
      expect(batches.map(describe), [
        'categories(movie:2)',
        'movies(3)',
        'done(movie)',
      ]);
      final m = {for (final x in itemsOf<MovieData>(batches)) x.key: x};

      final sample = m['1001']!;
      expect(sample.name, 'The Sample Movie (2019)');
      expect(sample.year, 2019);
      expect(sample.rating, 7.4);
      expect(sample.ext, 'mkv');
      expect(sample.poster, 'http://127.0.0.1/posters/1001.jpg');
      expect(sample.addedAt, DateTime.utc(2023, 11, 14, 22, 13, 20));
      expect(sample.categoryKeys, ['100']);
      expect(sample.url, isNull);

      final arabic = m['1002']!;
      expect(arabic.year, 2021);
      expect(arabic.rating, 9.0);
      expect(arabic.ext, 'mp4');
      expect(arabic.poster, isNull);
      expect(arabic.addedAt, DateTime.utc(2023, 11, 14, 22, 21, 40));

      final cartoon = m['2001']!;
      expect(cartoon.year, 2015);
      expect(cartoon.rating, isNull);
      expect(cartoon.addedAt, isNull);
      expect(cartoon.ext, 'avi');
      expect(cartoon.categoryKeys, ['200']);
    });

    test('series are mapped tolerantly', () async {
      final batches = await makeAdapter(fullPanel())
          .fetchCatalog(const SyncScope(live: false, movies: false))
          .toList();
      final s = {for (final x in itemsOf<SeriesData>(batches)) x.key: x};
      final drama = s['5001']!;
      expect(drama.name, 'Example Drama');
      expect(drama.year, 2018);
      expect(drama.poster, 'http://127.0.0.1/covers/5001.jpg');
      expect(drama.plot, 'A synthetic plot.');
      expect(drama.rating, 8.1);
      expect(drama.categoryKeys, ['500']);

      final arabic = s['5002']!;
      expect(arabic.name, 'مسلسل تجريبي');
      expect(arabic.year, 2020);
      expect(arabic.poster, isNull);
      expect(arabic.plot, isNull);
      expect(arabic.rating, 6.0);
      expect(arabic.categoryKeys, ['500']);
    });

    test('batches hold at most 2000 items', () async {
      final http = FakeHttpAdapter({
        'get_live_categories': FakeReply.json([]),
        'get_live_streams': FakeReply.json([
          for (var i = 0; i < 4500; i++) stream(i, category: '1'),
          stream(7, name: 'duplicate id'),
        ], chunkSize: 4096),
      });
      final batches = await makeAdapter(http)
          .fetchCatalog(const SyncScope(movies: false, series: false))
          .toList();
      expect(batches.map(describe), [
        'channels(2000)',
        'channels(2000)',
        'channels(500)',
        'done(live)',
      ]);
      final keys = itemsOf<ChannelData>(batches).map((c) => c.key).toSet();
      expect(keys, hasLength(4500));
    });

    test('empty panel still reports each phase', () async {
      final http = FakeHttpAdapter({
        'get_live_categories': FakeReply.json([]),
        'get_live_streams': FakeReply.json([]),
        'get_vod_categories': FakeReply.json({}),
        'get_vod_streams': FakeReply.json({}),
        'get_series_categories': FakeReply.text(
          '',
          contentType: 'application/json',
        ),
        'get_series': FakeReply.json(null),
      });
      final batches = await makeAdapter(http).fetchCatalog().toList();
      expect(batches.map(describe), [
        'done(live)',
        'done(movie)',
        'done(series)',
      ]);
    });

    group('per-category fallback', () {
      FakeRoute byCategory(Map<String, List<Map<String, Object?>>> lists) =>
          (r) {
            final cat = r.uri.queryParameters['category_id'];
            if (cat == null) {
              // The full list: never answers in time.
              return FakeReply.json(
                lists.values.expand((l) => l).toList(),
                delay: const Duration(seconds: 10),
              );
            }
            return FakeReply.json(lists[cat] ?? const []);
          };

      final liveLists = {
        '10': [
          stream(101, category: '10'),
          stream(102, category: '10'),
          {
            'stream_id': 201,
            'name': 'Multi',
            'category_id': '20',
            'category_ids': [20, 10],
          },
        ],
        '20': [
          {
            'stream_id': 201,
            'name': 'Multi',
            'category_id': '20',
            'category_ids': [20, 10],
          },
        ],
        '30': [
          stream(301, category: '30'),
          {'stream_id': 302, 'name': 'No category field'},
        ],
      };

      test('when the full list times out', () async {
        final http = fullPanel()
          ..routes['get_live_streams'] = byCategory(liveLists);
        final sw = Stopwatch()..start();
        final batches = await makeAdapter(
          http,
          fullListTimeout: const Duration(milliseconds: 100),
        ).fetchCatalog(const SyncScope(movies: false, series: false)).toList();
        expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
        expect(http.calls, [
          'get_live_categories',
          'get_live_streams',
          'get_live_streams?category_id=10',
          'get_live_streams?category_id=20',
          'get_live_streams?category_id=30',
        ]);
        expect(batches.map(describe), [
          'categories(live:3)',
          'channels(5)',
          'done(live)',
        ]);
        final ch = {for (final c in itemsOf<ChannelData>(batches)) c.key: c};
        expect(ch.keys, ['101', '102', '201', '301', '302']);
        expect(ch['201']!.categoryKeys, ['20', '10']);
        expect(ch['302']!.categoryKeys, ['30']);
        await pumpEventQueue();
        expect(http.cancelledCount, 1);
      });

      test('when the full list stalls mid-body (no duplicates)', () async {
        final full = [
          stream(101, category: '10'),
          stream(102, category: '10'),
          stream(301, category: '30'),
        ];
        final http = fullPanel()
          ..routes['get_live_streams'] = (RequestOptions r) {
            final cat = r.uri.queryParameters['category_id'];
            if (cat == null) {
              return FakeReply.json(
                full,
                chunkSize: 100,
                chunkDelay: const Duration(seconds: 10),
              );
            }
            return FakeReply.json(liveLists[cat] ?? const []);
          };
        final batches = await makeAdapter(
          http,
          fullListTimeout: const Duration(milliseconds: 100),
        ).fetchCatalog(const SyncScope(movies: false, series: false)).toList();
        final keys = itemsOf<ChannelData>(batches).map((c) => c.key).toList();
        expect(keys.toSet(), {'101', '102', '201', '301', '302'});
        expect(keys, hasLength(5));
      });

      test('lowMemory never requests the full list', () async {
        final http = fullPanel()
          ..routes['get_live_streams'] = byCategory(liveLists)
          ..routes['get_vod_streams'] = byCategory({
            '100': [
              {'stream_id': 1001, 'name': 'M (2001)', 'category_id': '100'},
            ],
            '200': [
              {'stream_id': 2001, 'name': 'K', 'category_id': '200'},
            ],
          })
          ..routes['get_series'] = byCategory({
            '500': [
              {'series_id': 5001, 'name': 'S', 'category_id': '500'},
            ],
          });
        final batches = await makeAdapter(
          http,
          lowMemory: true,
        ).fetchCatalog().toList();
        expect(http.calls, [
          'get_live_categories',
          'get_live_streams?category_id=10',
          'get_live_streams?category_id=20',
          'get_live_streams?category_id=30',
          'get_vod_categories',
          'get_vod_streams?category_id=100',
          'get_vod_streams?category_id=200',
          'get_series_categories',
          'get_series?category_id=500',
        ]);
        expect(batches.map(describe), [
          'categories(live:3)',
          'channels(5)',
          'done(live)',
          'categories(movie:2)',
          'movies(2)',
          'done(movie)',
          'categories(series:1)',
          'series(1)',
          'done(series)',
        ]);
      });

      test('dio timeouts on the full list also fall back', () async {
        final http = fullPanel()
          ..routes['get_live_streams'] = (RequestOptions r) {
            if (r.uri.queryParameters['category_id'] == null) {
              throw DioException.receiveTimeout(
                timeout: const Duration(seconds: 120),
                requestOptions: r,
              );
            }
            return FakeReply.json(
              liveLists[r.uri.queryParameters['category_id']],
            );
          };
        final batches = await makeAdapter(http)
            .fetchCatalog(const SyncScope(movies: false, series: false))
            .toList();
        expect(itemsOf<ChannelData>(batches), hasLength(5));
      });

      test('a timeout without categories fails instead of '
          'returning an empty catalog', () async {
        final http = FakeHttpAdapter({
          'get_live_categories': FakeReply.json([]),
          'get_live_streams': (RequestOptions r) =>
              throw DioException.receiveTimeout(
                timeout: const Duration(seconds: 120),
                requestOptions: r,
              ),
        });
        final f = await failureOf(
          makeAdapter(
            http,
            fullListTimeout: const Duration(milliseconds: 50),
          ).fetchCatalog().toList(),
        );
        expect(f, isA<TimeoutFailure>());
        expect(http.calls, ['get_live_categories', 'get_live_streams']);
      });

      test('without categories the full list gets no idle timeout', () async {
        final http = FakeHttpAdapter({
          'get_live_categories': FakeReply.json([]),
          'get_live_streams': FakeReply.json([
            stream(1),
            stream(2),
          ], delay: const Duration(milliseconds: 150)),
        });
        final batches = await makeAdapter(
          http,
          fullListTimeout: const Duration(milliseconds: 20),
        ).fetchCatalog(const SyncScope(movies: false, series: false)).toList();
        expect(batches.map(describe), ['channels(2)', 'done(live)']);
      });

      test('lowMemory without categories uses the full list', () async {
        final http = FakeHttpAdapter({
          'get_live_categories': FakeReply.json([]),
          'get_live_streams': FakeReply.json([stream(1)]),
        });
        final batches = await makeAdapter(
          http,
          lowMemory: true,
        ).fetchCatalog(const SyncScope(movies: false, series: false)).toList();
        expect(http.calls, ['get_live_categories', 'get_live_streams']);
        expect(batches.map(describe), ['channels(1)', 'done(live)']);
      });

      test('non-timeout errors do not fall back', () async {
        final http = fullPanel()
          ..routes['get_live_streams'] = FakeReply.text('down', status: 503);
        final f = await failureOf(
          makeAdapter(
            http,
            fullListTimeout: const Duration(milliseconds: 100),
          ).fetchCatalog().toList(),
        );
        expect(f, isA<NetworkFailure>());
        expect(http.calls, ['get_live_categories', 'get_live_streams']);
      });

      test('errors during the fallback propagate, redacted', () async {
        final http = fullPanel()
          ..routes['get_live_streams'] = (RequestOptions r) {
            if (r.uri.queryParameters['category_id'] == null) {
              return FakeReply.json([], delay: const Duration(seconds: 10));
            }
            return FakeReply.text('gone', status: 500);
          };
        final f = await failureOf(
          makeAdapter(
            http,
            fullListTimeout: const Duration(milliseconds: 50),
          ).fetchCatalog().toList(),
        );
        expect(f, isA<NetworkFailure>());
        expect(f.message, isNot(contains('p@ss')));
        expect(f.message, isNot(contains(_p)));
        expect(f.message, isNot(contains(_u)));
      });
    });

    test('category errors surface as redacted SourceFailures', () async {
      final http = fullPanel()
        ..routes['get_live_categories'] = (RequestOptions r) =>
            throw DioException.connectionError(
              requestOptions: r,
              reason: 'refused ${r.uri}',
            );
      final f = await failureOf(makeAdapter(http).fetchCatalog().toList());
      expect(f, isA<NetworkFailure>());
      expect(f.message, contains('panel.example.com'));
      expect(f.message, isNot(contains(_p)));
      expect(f.message, isNot(contains('p@ss/w rd')));
    });

    test('close cancels an in-flight sync', () async {
      final http = fullPanel()
        ..routes['get_live_streams'] = FakeReply.json(
          [],
          delay: const Duration(seconds: 10),
        );
      final adapter = makeAdapter(http);
      final pending = failureOf(adapter.fetchCatalog().toList());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      adapter.close();
      expect(await pending, isA<CancelledFailure>());
    });
  });

  group('seriesDetail', () {
    test('episodes as a map keyed by season', () async {
      final http = fullPanel();
      final d = await makeAdapter(http).seriesDetail('5001');
      expect(http.calls, ['get_series_info?series_id=5001']);
      expect(d.key, '5001');
      expect(d.plot, 'A synthetic plot.');
      expect(d.cast, 'Actor A, Actor B');
      expect(d.genre, 'Drama');
      expect(d.backdrop, 'http://127.0.0.1/bd/5001.jpg');

      expect(d.seasons.map((s) => s.number), [1, 2]);
      expect(d.seasons.first.name, 'Season 1');
      expect(d.seasons.first.cover, 'http://127.0.0.1/covers/s1_big.jpg');
      expect(d.seasons.last.name, isNull);

      expect(d.episodes.map((e) => e.key), ['90001', '90002', '90003']);
      final e1 = d.episodes[0];
      expect(e1.seriesKey, '5001');
      expect((e1.season, e1.number), (1, 1));
      expect(e1.title, 'Example Drama - S01E01');
      expect(e1.ext, 'mkv');
      expect(e1.durationSec, 2700);
      expect(e1.plot, 'Pilot.');
      expect(e1.still, 'http://127.0.0.1/stills/90001.jpg');
      expect(e1.url, isNull);

      final e2 = d.episodes[1];
      expect((e2.season, e2.number), (1, 2));
      expect(e2.durationSec, isNull);
      expect(e2.plot, isNull);
      expect(e2.still, isNull);

      final e3 = d.episodes[2];
      expect((e3.season, e3.number), (2, 1));
      expect(e3.ext, 'mp4');
      expect(e3.durationSec, 3030);
    });

    test('flat episode list with info []', () async {
      final http = fullPanel()
        ..routes['get_series_info'] = FakeReply.fixture(
          'series_info_list.json',
        );
      final d = await makeAdapter(http).seriesDetail('5002');
      expect(d.plot, isNull);
      expect(d.cast, isNull);
      expect(d.backdrop, isNull);
      expect(d.seasons.map((s) => s.number), [1, 2]);
      expect(d.episodes.map((e) => '${e.key}:s${e.season}e${e.number}'), [
        '91001:s1e1',
        '91002:s1e2',
        '92001:s2e1',
      ]);
      expect(d.episodes[1].durationSec, 1500);
    });

    test("an episode's own season field wins over the map key", () async {
      final http = fullPanel()
        ..routes['get_series_info'] = FakeReply.json({
          'seasons': [],
          'info': {'backdrop_path': 'http://127.0.0.1/bd/x.jpg'},
          'episodes': {
            '1': [
              {'id': 'a', 'episode_num': 1, 'season': 3},
            ],
            '2': [
              {'id': 'b', 'title': 'no number'},
              {'id': 'c'},
              {'id': 'b', 'title': 'duplicate'},
              {'title': 'no id'},
            ],
            '4': {'id': 'd', 'episode_num': '5'},
          },
        });
      final d = await makeAdapter(http).seriesDetail('9');
      expect(d.backdrop, 'http://127.0.0.1/bd/x.jpg');
      expect(d.episodes.map((e) => '${e.key}:s${e.season}e${e.number}'), [
        'b:s2e1',
        'c:s2e2',
        'a:s3e1',
        'd:s4e5',
      ]);
      expect(d.episodes.first.title, 'no number');
      expect(d.seasons.map((s) => s.number), [2, 3, 4]);
    });

    test('list of season lists', () async {
      final http = fullPanel()
        ..routes['get_series_info'] = FakeReply.json({
          'episodes': [
            [
              {'id': 'x1', 'season': 1, 'episode_num': 1},
            ],
            [
              {'id': 'x2', 'season': 2, 'episode_num': 1},
            ],
          ],
        });
      final d = await makeAdapter(http).seriesDetail('9');
      expect(d.episodes.map((e) => e.key), ['x1', 'x2']);
    });

    test('seasons without episodes are kept when nothing is listed', () async {
      final http = fullPanel()
        ..routes['get_series_info'] = FakeReply.json({
          'seasons': [
            {'season_number': '2', 'name': 'S2', 'cover': 'http://127.0.0.1/c'},
            {'season_number': 1, 'name': 'S1'},
          ],
          'info': [],
          'episodes': [],
        });
      final d = await makeAdapter(http).seriesDetail('9');
      expect(d.seasons.map((s) => s.name), ['S1', 'S2']);
      expect(d.seasons.last.cover, 'http://127.0.0.1/c');
      expect(d.episodes, isEmpty);
    });

    test('[] response gives an empty detail', () async {
      final http = fullPanel()..routes['get_series_info'] = FakeReply.json([]);
      final d = await makeAdapter(http).seriesDetail('9');
      expect(d.key, '9');
      expect(d.seasons, isEmpty);
      expect(d.episodes, isEmpty);
    });
  });

  group('movieDetail', () {
    test('maps info and movie_data', () async {
      final http = fullPanel();
      final d = (await makeAdapter(http).movieDetail('1001'))!;
      expect(http.calls, ['get_vod_info?vod_id=1001']);
      expect(d.key, '1001');
      expect(d.plot, 'Synthetic plot.');
      expect(d.cast, 'Actor Y, Actor Z');
      expect(d.director, 'Director X');
      expect(d.genre, 'Drama / Test');
      expect(d.durationSec, 6300);
      expect(d.backdrop, 'http://127.0.0.1/bd/1001a.jpg');
      expect(d.rating, 7.4);
      expect(d.releaseDate, '2019-05-01');
      expect(d.ext, 'mkv');
    });

    test('fallback fields', () async {
      final http = fullPanel()
        ..routes['get_vod_info'] = FakeReply.json({
          'info': {
            'description': 'Only a description.',
            'actors': 'Someone',
            'duration': '01:30:00',
            'backdrop_path': 'http://127.0.0.1/bd/one.jpg',
            'rating_5based': '4',
            'release_date': '2001',
          },
          'movie_data': [],
        });
      final d = (await makeAdapter(http).movieDetail('5'))!;
      expect(d.plot, 'Only a description.');
      expect(d.cast, 'Someone');
      expect(d.durationSec, 5400);
      expect(d.backdrop, 'http://127.0.0.1/bd/one.jpg');
      expect(d.rating, 8.0);
      expect(d.releaseDate, '2001');
      expect(d.ext, isNull);
    });

    test('[] or empty info gives null', () async {
      final http = fullPanel()..routes['get_vod_info'] = FakeReply.json([]);
      expect(await makeAdapter(http).movieDetail('5'), isNull);
      http.routes['get_vod_info'] = FakeReply.json({
        'info': [],
        'movie_data': [],
      });
      expect(await makeAdapter(http).movieDetail('5'), isNull);
    });
  });

  group('resolve', () {
    test('live defaults to ts with the default User-Agent', () {
      final http = FakeHttpAdapter();
      final r = makeAdapter(http)
          .resolve(const PlayableRef(kind: PlayableKind.live, key: '101'));
      expect(r.url, '$_base/live/$_u/$_p/101.ts');
      expect(r.kind, PlayableKind.live);
      expect(r.isLive, isTrue);
      expect(r.isHls, isFalse);
      expect(r.headers, {'User-Agent': kDefaultUserAgent});
      expect(http.requests, isEmpty);
    });

    test('live m3u8 is HLS', () {
      final r = makeAdapter(
        FakeHttpAdapter(),
        config: _config.copyWith(liveFormat: LiveFormat.m3u8),
      ).resolve(const PlayableRef(kind: PlayableKind.live, key: '101'));
      expect(r.url, '$_base/live/$_u/$_p/101.m3u8');
      expect(r.isHls, isTrue);
    });

    test('allowed formats override the configured live format', () {
      final adapter = makeAdapter(FakeHttpAdapter());
      const ref = PlayableRef(kind: PlayableKind.live, key: '1');
      adapter.allowedFormats = ['m3u8'];
      expect(adapter.resolve(ref).url, endsWith('/1.m3u8'));
      adapter.allowedFormats = ['ts', 'rtmp'];
      expect(adapter.resolve(ref).url, endsWith('/1.ts'));
      adapter.allowedFormats = ['rtmp'];
      expect(adapter.resolve(ref).url, endsWith('/1.ts'));
      adapter.allowedFormats = [];
      expect(adapter.resolve(ref).url, endsWith('/1.ts'));

      final hls = makeAdapter(
        FakeHttpAdapter(),
        config: _config.copyWith(liveFormat: LiveFormat.m3u8),
      )..allowedFormats = ['ts'];
      expect(hls.resolve(ref).url, endsWith('/1.ts'));
      expect(hls.resolve(ref).isHls, isFalse);
    });

    test('verify feeds the live format choice', () async {
      final http = fullPanel()
        ..routes[''] = FakeReply.json({
          'user_info': {
            'auth': 1,
            'allowed_output_formats': ['m3u8'],
          },
        });
      final adapter = makeAdapter(http);
      await adapter.verify();
      final r = adapter.resolve(
        const PlayableRef(kind: PlayableKind.live, key: '1'),
      );
      expect(r.url, endsWith('/1.m3u8'));
      expect(r.isHls, isTrue);
    });

    test('ref.ext toggles the live format', () {
      final adapter = makeAdapter(FakeHttpAdapter())..allowedFormats = ['ts'];
      final r = adapter.resolve(
        const PlayableRef(kind: PlayableKind.live, key: '1', ext: 'M3U8'),
      );
      expect(r.url, endsWith('/1.m3u8'));
      expect(r.isHls, isTrue);
    });

    test('movies and episodes use their container extension', () {
      final adapter = makeAdapter(FakeHttpAdapter());
      expect(
        adapter
            .resolve(
              const PlayableRef(
                kind: PlayableKind.movie,
                key: '1001',
                ext: 'mkv',
              ),
            )
            .url,
        '$_base/movie/$_u/$_p/1001.mkv',
      );
      expect(
        adapter
            .resolve(const PlayableRef(kind: PlayableKind.movie, key: '1002'))
            .url,
        '$_base/movie/$_u/$_p/1002.mp4',
      );
      final ep = adapter.resolve(
        const PlayableRef(kind: PlayableKind.episode, key: '90001'),
      );
      expect(ep.url, '$_base/series/$_u/$_p/90001.mp4');
      expect(ep.kind, PlayableKind.episode);
      expect(ep.isLive, isFalse);
      expect(
        adapter
            .resolve(
              const PlayableRef(
                kind: PlayableKind.episode,
                key: '90003',
                ext: '.MKV',
              ),
            )
            .url,
        endsWith('/90003.mkv'),
      );
      expect(
        adapter
            .resolve(
              const PlayableRef(
                kind: PlayableKind.movie,
                key: '7',
                ext: 'm3u8',
              ),
            )
            .isHls,
        isTrue,
      );
    });

    test('source headers, ref headers, startAt and title', () {
      final adapter = makeAdapter(
        FakeHttpAdapter(),
        config: _config.copyWith(
          userAgent: 'VLC/3.0.21 LibVLC/3.0.21',
          referer: 'http://panel.example.com/',
        ),
      );
      final r = adapter.resolve(
        const PlayableRef(
          kind: PlayableKind.movie,
          key: '1',
          title: 'The Sample Movie',
          headers: {'X-Test': '1', 'Referer': 'http://127.0.0.1/'},
        ),
        startAt: const Duration(minutes: 42),
      );
      expect(r.headers, {
        'User-Agent': 'VLC/3.0.21 LibVLC/3.0.21',
        'Referer': 'http://127.0.0.1/',
        'X-Test': '1',
      });
      expect(r.startAt, const Duration(minutes: 42));
      expect(r.title, 'The Sample Movie');
    });

    test('empty source User-Agent falls back to the default', () {
      final r = makeAdapter(
        FakeHttpAdapter(),
        config: _config.copyWith(userAgent: '', referer: ''),
      ).resolve(const PlayableRef(kind: PlayableKind.live, key: '1'));
      expect(r.headers, {'User-Agent': kDefaultUserAgent});
    });
  });

  test('epgSpecs points at xmltv.php', () {
    final specs = makeAdapter(FakeHttpAdapter()).epgSpecs();
    expect(specs, hasLength(1));
    expect(specs.single.origin, EpgOrigin.xtream);
    expect(specs.single.url, '$_base/xmltv.php?username=$_u&password=$_p');
  });

  test('shortEpg', () async {
    final http = fullPanel();
    final list = await makeAdapter(http).shortEpg('101');
    expect(http.calls, ['get_short_epg?stream_id=101&limit=2']);
    expect(list.first.title, 'نشرة الأخبار');
    expect(list.first.channelId, 'news.example');
    await makeAdapter(http).shortEpg('101', limit: 5);
    expect(http.calls.last, 'get_short_epg?stream_id=101&limit=5');
  });

  group('invalid server address', () {
    for (final url in ['host:8O80', 'host:80,', 'http://host:8080:8080']) {
      test("'$url' fails every call with a redacted ParseFailure", () async {
        final http = fullPanel();
        final adapter = makeAdapter(http, config: _config.copyWith(url: url));
        final failures = [
          await failureOf(adapter.verify()),
          await failureOf(adapter.fetchCatalog().toList()),
          await failureOf(adapter.seriesDetail('5001')),
          await failureOf(adapter.movieDetail('1001')),
          await failureOf(adapter.shortEpg('101')),
        ];
        for (final f in failures) {
          expect(f, isA<ParseFailure>());
          expect(f.message, startsWith('Invalid server address'));
          for (final s in ['demo user', 'p@ss/w rd', _u, _p, 'p@ss']) {
            expect(f.toString(), isNot(contains(s)));
          }
        }
        expect(http.requests, isEmpty);
      });
    }
  });

  group('out-of-range timestamps', () {
    test('a huge added date does not abort the sync', () async {
      final http = FakeHttpAdapter({
        'get_vod_categories': FakeReply.json([]),
        'get_vod_streams': FakeReply.json([
          {'stream_id': 1, 'name': 'Fine', 'added': '1700000000'},
          {'stream_id': 2, 'name': 'Huge', 'added': '9999999999999999'},
          {'stream_id': 3, 'name': 'Huger', 'added': '1e30'},
        ]),
      });
      final batches = await makeAdapter(http)
          .fetchCatalog(const SyncScope(live: false, series: false))
          .toList();
      final movies = itemsOf<MovieData>(batches);
      expect(movies.map((m) => m.key), ['1', '2', '3']);
      expect(movies.first.addedAt, DateTime.utc(2023, 11, 14, 22, 13, 20));
      expect(movies[1].addedAt, isNull);
      expect(movies[2].addedAt, isNull);
      expect(describe(batches.last), 'done(movie)');
    });

    test('verify and shortEpg survive huge timestamps', () async {
      final http = FakeHttpAdapter({
        '': FakeReply.json({
          'user_info': {'auth': 1, 'exp_date': '9999999999999999'},
        }),
        'get_short_epg': FakeReply.json({
          'epg_listings': [
            {
              'title': 'VGVzdA==',
              'start_timestamp': '9999999999999999',
              'stop_timestamp': '99999999999999999',
            },
          ],
        }),
      });
      final adapter = makeAdapter(http);
      expect((await adapter.verify()).expiresAt, isNull);
      expect(await adapter.shortEpg('1'), isEmpty);
    });
  });

  test('missing credentials do not crash', () {
    final adapter = makeAdapter(
      FakeHttpAdapter(),
      config: const SourceConfig(
        kind: SourceKind.xtream,
        url: 'http://127.0.0.1:25461',
      ),
    );
    expect(
      adapter.resolve(const PlayableRef(kind: PlayableKind.live, key: '1')).url,
      'http://127.0.0.1:25461/live///1.ts',
    );
  });
}
