import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/net/http.dart';
import 'package:iptv_player/sources/m3u/byte_source.dart';
import 'package:iptv_player/sources/m3u/m3u_adapter.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/sources/source_adapter.dart';

const _config = SourceConfig(
  kind: SourceKind.m3uUrl,
  url: 'http://127.0.0.1/list.m3u',
);

M3uAdapter adapterFor(
  String text, {
  SourceConfig config = _config,
  int chunkSize = 64 * 1024,
}) => M3uAdapter(
  config,
  dio: Dio(),
  byteSource: MemoryByteSource(utf8.encode(text), chunkSize: chunkSize),
);

String fixture(String name) =>
    File('test/fixtures/m3u/$name').readAsStringSync();

/// Byte source driven by a caller-supplied stream factory.
class FakeByteSource implements ByteSource {
  FakeByteSource(this.factory);

  final Stream<List<int>> Function() factory;
  int opens = 0;
  int cancels = 0;

  @override
  Stream<List<int>> open() {
    opens++;
    return factory();
  }

  @override
  void cancel() => cancels++;
}

String playlist(Iterable<String> entries, {String header = '#EXTM3U'}) =>
    '$header\n${entries.join('\n')}\n';

String live(int i, {String group = 'G'}) =>
    '#EXTINF:-1 tvg-id="ch$i" group-title="$group",Channel $i\n'
    'http://127.0.0.1/live/$i.ts';

String movie(int i, {String group = 'M'}) =>
    '#EXTINF:-1 group-title="$group",Movie $i\nhttp://127.0.0.1/movie/$i.mkv';

String episode(int s, int e, {String show = 'Show', String group = 'S'}) =>
    '#EXTINF:-1 group-title="$group",$show S${s}E$e\n'
    'http://127.0.0.1/series/$show-$s-$e.mp4';

/// Asserts every item references categories announced earlier.
void expectCategoriesFirst(List<SyncBatch> batches) {
  final seen = <ContentKind, Set<String>>{
    for (final k in ContentKind.values) k: {},
  };
  void check(ContentKind kind, List<String> keys) {
    for (final k in keys) {
      expect(seen[kind], contains(k), reason: 'category $kind/$k not sent');
    }
  }

  for (final b in batches) {
    switch (b) {
      case CategoriesBatch(:final items):
        for (final c in items) {
          expect(seen[c.kind]!.add(c.key), isTrue, reason: 'dup ${c.key}');
        }
      case ChannelsBatch(:final items):
        for (final c in items) {
          check(ContentKind.live, c.categoryKeys);
        }
      case MoviesBatch(:final items):
        for (final m in items) {
          check(ContentKind.movie, m.categoryKeys);
        }
      case SeriesBatch(:final items):
        for (final s in items) {
          check(ContentKind.series, s.categoryKeys);
        }
      default:
        break;
    }
  }
}

void main() {
  test('caps', () {
    final caps = adapterFor('').caps;
    expect(caps.live, isTrue);
    expect(caps.movies, isTrue);
    expect(caps.series, isTrue);
  });

  group('fetchCatalog on the mixed fixture', () {
    late M3uAdapter adapter;
    late List<SyncBatch> batches;

    setUp(() async {
      adapter = adapterFor(fixture('mixed.m3u'), chunkSize: 97);
      batches = await adapter.fetchCatalog().toList();
    });

    T single<T extends SyncBatch>() => batches.whereType<T>().single;

    test('batch order', () {
      expect(batches.map((b) => b.runtimeType), [
        EpgHintBatch,
        CategoriesBatch,
        ChannelsBatch,
        CategoriesBatch,
        MoviesBatch,
        CategoriesBatch,
        SeriesBatch,
        EpisodesBatch,
        PhaseDoneBatch,
        PhaseDoneBatch,
        PhaseDoneBatch,
      ]);
      expect(
        batches.whereType<PhaseDoneBatch>().map((b) => b.kind),
        ContentKind.values,
      );
      expectCategoriesFirst(batches);
    });

    test('guide hints and epgSpecs', () {
      expect(single<EpgHintBatch>().urls, [
        'http://epg.example.com/guide.xml.gz',
        'http://epg.example.com/backup.xml',
      ]);
      final specs = adapter.epgSpecs();
      expect(specs.map((s) => s.url), [
        'http://epg.example.com/guide.xml.gz',
        'http://epg.example.com/backup.xml',
      ]);
      expect(specs.map((s) => s.origin).toSet(), {EpgOrigin.m3uHeader});
    });

    test('categories per kind with first-appearance order', () {
      final cats = batches
          .whereType<CategoriesBatch>()
          .expand((b) => b.items)
          .toList();
      String describe(CategoryData c) =>
          '${c.kind.name}:${c.key}:${c.name}:${c.sortIndex}';
      expect(cats.map(describe), [
        'live:News:News:0',
        'live:Sports:Sports:1',
        'live:Radio:Radio:2',
        'movie:Movies Action:Movies Action:0',
        'movie:Movies Drama:Movies Drama:1',
        'movie:Series B:Series B:2',
        'series:Series A:Series A:0',
        'series:Series B:Series B:1',
      ]);
    });

    test('channels', () {
      final ch = single<ChannelsBatch>().items;
      expect(ch, hasLength(3));
      expect(ch[0].key, 'http://stream.example.com/live/news1.m3u8');
      expect(ch[0].name, 'News One HD');
      expect(ch[0].tvgId, 'news.one');
      expect(ch[0].tvgName, 'News One');
      expect(ch[0].num, 101);
      expect(ch[0].logo, 'http://img.example.com/logos/news1.png');
      expect(ch[0].tvgShiftMin, 60);
      expect(ch[0].categoryKeys, ['News']);
      expect(ch[1].key, 'http://stream.example.com/live/sport1.ts');
      expect(ch[1].url, 'http://stream.example.com/live/sport1.ts?token=abc');
      expect(ch[1].logo, 'http://cdn.example.com/sport1.png');
      expect(ch[1].categoryKeys, ['Sports', 'News']);
      expect(ch[2].isRadio, isTrue);
    });

    test('movies, including /series/ items without SxxEyy', () {
      final mv = single<MoviesBatch>().items;
      expect(mv.map((m) => m.name), [
        'Fake Movie (2021)',
        'Another Film',
        'Special Without Marker',
      ]);
      expect(mv[0].year, 2021);
      expect(mv[0].ext, 'mkv');
      expect(mv[0].key, 'http://vod.example.com/movie/1001.mkv');
      expect(mv[1].ext, 'mp4');
      expect(mv[2].categoryKeys, ['Series B']);
    });

    test('series and episodes', () {
      final series = single<SeriesBatch>().items;
      expect(series.map((s) => s.key), [
        'series:example show',
        'series:other show',
      ]);
      expect(series[0].name, 'Example Show');
      expect(series[0].poster, 'http://img.example.com/logos/show.png');
      expect(series[0].categoryKeys, ['Series A']);
      final eps = single<EpisodesBatch>().items;
      expect(eps.map((e) => '${e.seriesKey} ${e.season}x${e.number}'), [
        'series:example show 1x1',
        'series:example show 1x2',
        'series:example show 2x1',
        'series:other show 1x5',
      ]);
      expect(eps[0].key, 'http://vod.example.com/series/2001.mkv');
      expect(eps[0].ext, 'mkv');
      expect(eps[0].url, 'http://vod.example.com/series/2001.mkv');
    });

    test('seriesDetail returns the collected episodes', () async {
      final detail = await adapter.seriesDetail('series:example show');
      expect(detail.key, 'series:example show');
      expect(detail.seasons.map((s) => s.number), [1, 2]);
      expect(detail.episodes.map((e) => e.number), [1, 2, 1]);
      await expectLater(
        adapter.seriesDetail('series:missing'),
        throwsA(isA<ParseFailure>()),
      );
    });

    test('movieDetail is null', () async {
      expect(await adapter.movieDetail('anything'), isNull);
    });
  });

  test('seriesDetail before any fetch throws ParseFailure', () async {
    await expectLater(
      adapterFor('').seriesDetail('series:x'),
      throwsA(isA<ParseFailure>()),
    );
  });

  test('episode details are sorted by season and number', () async {
    final adapter = adapterFor(
      playlist([episode(2, 1), episode(1, 3), episode(1, 1)]),
    );
    await adapter.fetchCatalog().drain<void>();
    final detail = await adapter.seriesDetail('series:show');
    expect(detail.episodes.map((e) => '${e.season}x${e.number}'), [
      '1x1',
      '1x3',
      '2x1',
    ]);
  });

  test('playlist without header still parses and has no guide hints', () async {
    final adapter = adapterFor('${live(1)}\n${live(2)}\n');
    final batches = await adapter.fetchCatalog().toList();
    expect(batches.whereType<EpgHintBatch>(), isEmpty);
    expect(batches.whereType<ChannelsBatch>().single.items, hasLength(2));
    expect(adapter.epgSpecs(), isEmpty);
  });

  test('stable keys: query removed, collisions get #n', () async {
    final adapter = adapterFor(
      playlist([
        '#EXTINF:-1,A\nhttp://127.0.0.1/a.ts?token=1',
        '#EXTINF:-1,A again\nhttp://127.0.0.1/a.ts?token=2',
        '#EXTINF:-1,A third\nhttp://127.0.0.1/a.ts',
        '#EXTINF:-1 tvg-id="ID.One",Same\n?only=query',
        '#EXTINF:-1 tvg-id="id.one",Same\n?other=query',
        '#EXTINF:-1,Fragment\nhttp://127.0.0.1/a.ts#2',
      ]),
    );
    final batches = await adapter.fetchCatalog().toList();
    final keys = batches
        .whereType<ChannelsBatch>()
        .expand((b) => b.items)
        .map((c) => c.key)
        .toList();
    expect(keys, [
      'http://127.0.0.1/a.ts',
      'http://127.0.0.1/a.ts#2',
      'http://127.0.0.1/a.ts#3',
      'id.one|Same',
      'id.one|Same#2',
      'http://127.0.0.1/a.ts#4',
    ]);
  });

  test('batches hold at most 2000 items', () async {
    final adapter = adapterFor(
      playlist([
        for (var i = 0; i < 4500; i++) live(i, group: 'G${i % 3}'),
        for (var i = 0; i < 2500; i++) movie(i),
        for (var i = 0; i < 2100; i++) episode(1 + i ~/ 100, i % 100),
      ]),
      chunkSize: 4096,
    );
    final batches = await adapter.fetchCatalog().toList();
    List<int> sizes<T extends SyncBatch>(int Function(T) count) =>
        batches.whereType<T>().map(count).toList();

    expect(sizes<ChannelsBatch>((b) => b.items.length), [2000, 2000, 500]);
    expect(sizes<MoviesBatch>((b) => b.items.length), [2000, 500]);
    expect(sizes<EpisodesBatch>((b) => b.items.length), [2000, 100]);
    expect(sizes<SeriesBatch>((b) => b.items.length), [1]);
    expect(
      batches.whereType<CategoriesBatch>().expand((b) => b.items).length,
      5,
    );
    expectCategoriesFirst(batches);

    // The first live batch is emitted before the movies are parsed.
    final firstChannels = batches.indexWhere((b) => b is ChannelsBatch);
    final firstMovies = batches.indexWhere((b) => b is MoviesBatch);
    expect(firstChannels, lessThan(firstMovies));

    final tail = batches.sublist(batches.length - 3);
    expect(tail.map((b) => (b as PhaseDoneBatch).kind), ContentKind.values);
    expect(batches.whereType<PhaseDoneBatch>(), hasLength(3));
  });

  group('SyncScope', () {
    Future<List<SyncBatch>> fetch(SyncScope scope) =>
        adapterFor(fixture('mixed.m3u')).fetchCatalog(scope).toList();

    test('live only', () async {
      final batches = await fetch(
        const SyncScope(movies: false, series: false),
      );
      expect(batches.whereType<MoviesBatch>(), isEmpty);
      expect(batches.whereType<SeriesBatch>(), isEmpty);
      expect(batches.whereType<EpisodesBatch>(), isEmpty);
      expect(batches.whereType<ChannelsBatch>().single.items, hasLength(3));
      expect(
        batches
            .whereType<CategoriesBatch>()
            .expand((b) => b.items)
            .map((c) => c.kind)
            .toSet(),
        {ContentKind.live},
      );
      expect(batches.whereType<PhaseDoneBatch>().map((b) => b.kind), [
        ContentKind.live,
      ]);
    });

    test('series only', () async {
      final batches = await fetch(const SyncScope(live: false, movies: false));
      expect(batches.whereType<ChannelsBatch>(), isEmpty);
      expect(batches.whereType<MoviesBatch>(), isEmpty);
      expect(batches.whereType<SeriesBatch>().single.items, hasLength(2));
      expect(batches.whereType<EpisodesBatch>().single.items, hasLength(4));
      expect(batches.whereType<PhaseDoneBatch>().map((b) => b.kind), [
        ContentKind.series,
      ]);
    });

    test('movies only keeps /series/ items without a marker', () async {
      final batches = await fetch(const SyncScope(live: false, series: false));
      expect(batches.whereType<MoviesBatch>().single.items, hasLength(3));
      expect(batches.whereType<EpisodesBatch>(), isEmpty);
      expect(batches.whereType<PhaseDoneBatch>().map((b) => b.kind), [
        ContentKind.movie,
      ]);
    });
  });

  group('verify', () {
    test('accepts an M3U playlist', () async {
      final info = await adapterFor(fixture('mixed.m3u')).verify();
      expect(info.status, AccountStatus.active);
    });

    test('accepts EXTINF without header', () async {
      final info = await adapterFor(live(1)).verify();
      expect(info.status, AccountStatus.active);
    });

    for (final (label, body) in [
      ('HTML', '<!DOCTYPE html><html><body>Login</body></html>'),
      ('JSON', '{"user_info":{"auth":0}}'),
      ('empty', ''),
      ('plain URLs', 'http://127.0.0.1/a.ts\n'),
    ]) {
      test('rejects $label', () async {
        await expectLater(
          adapterFor(body).verify(),
          throwsA(
            isA<ParseFailure>().having(
              (f) => f.message,
              'message',
              'not an M3U playlist',
            ),
          ),
        );
      });
    }

    test('reads only the first 64 KB and releases the source', () async {
      var chunks = 0;
      var released = false;
      Stream<List<int>> endless() async* {
        try {
          yield utf8.encode('#EXTM3U\n');
          while (true) {
            chunks++;
            yield List.filled(16 * 1024, 0x23);
          }
        } finally {
          released = true;
        }
      }

      final adapter = M3uAdapter(
        _config,
        dio: Dio(),
        byteSource: FakeByteSource(endless),
      );
      final info = await adapter.verify();
      expect(info.status, AccountStatus.active);
      expect(released, isTrue);
      expect(chunks, lessThanOrEqualTo(5));
    });

    test('a 64 KB prefix without markers is rejected', () async {
      final body = '${'#' * (70 * 1024)}\n#EXTINF:-1,Late\nhttp://x/a.ts\n';
      await expectLater(
        adapterFor(body).verify(),
        throwsA(isA<ParseFailure>()),
      );
    });

    test('byte source failures pass through', () async {
      final adapter = M3uAdapter(
        _config,
        dio: Dio(),
        byteSource: FakeByteSource(
          () => Stream.error(const NetworkFailure('down', statusCode: 503)),
        ),
      );
      await expectLater(
        adapter.verify(),
        throwsA(isA<NetworkFailure>().having((f) => f.statusCode, 'code', 503)),
      );
    });
  });

  group('errors', () {
    test('unexpected errors become redacted ParseFailures', () async {
      final adapter = M3uAdapter(
        const SourceConfig(
          kind: SourceKind.m3uUrl,
          url: 'http://127.0.0.1/get.php',
          password: 'hunter22',
        ),
        dio: Dio(),
        byteSource: FakeByteSource(() async* {
          yield utf8.encode('#EXTM3U\n${live(1)}\n');
          throw StateError(
            'boom http://127.0.0.1/get.php?username=bob&password=s3cret '
            'and hunter22',
          );
        }),
      );
      final error = await adapter.fetchCatalog().drain<void>().then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      expect(error, isA<ParseFailure>());
      final message = (error! as SourceFailure).message;
      expect(message, isNot(contains('s3cret')));
      expect(message, isNot(contains('hunter22')));
      expect(message, contains('password=***'));
    });

    test('SourceFailures from the byte source pass through', () async {
      final adapter = M3uAdapter(
        _config,
        dio: Dio(),
        byteSource: FakeByteSource(
          () => Stream.error(const TimeoutFailure('slow')),
        ),
      );
      await expectLater(
        adapter.fetchCatalog().toList(),
        throwsA(isA<TimeoutFailure>()),
      );
    });

    test('dio errors are mapped', () async {
      final adapter = M3uAdapter(
        _config,
        dio: Dio(),
        byteSource: FakeByteSource(
          () => Stream.error(
            DioException.connectionTimeout(
              timeout: const Duration(seconds: 1),
              requestOptions: RequestOptions(path: 'http://127.0.0.1/x'),
            ),
          ),
        ),
      );
      await expectLater(
        adapter.fetchCatalog().toList(),
        throwsA(isA<TimeoutFailure>()),
      );
    });
  });

  test('close() cancels a running fetch', () async {
    final adapter = adapterFor(
      playlist([for (var i = 0; i < 6000; i++) live(i)]),
      chunkSize: 1024,
    );
    final got = <SyncBatch>[];
    Object? error;
    final done = Completer<void>();
    adapter.fetchCatalog().listen(
      (b) {
        got.add(b);
        if (b is ChannelsBatch) adapter.close();
      },
      onError: (Object e) => error = e,
      onDone: done.complete,
    );
    await done.future;
    expect(got.whereType<ChannelsBatch>(), hasLength(1));
    expect(error, isA<CancelledFailure>());
  });

  test('close() cancels the byte source', () {
    final source = FakeByteSource(() => const Stream.empty());
    M3uAdapter(_config, dio: Dio(), byteSource: source).close();
    expect(source.cancels, 1);
  });

  test('a file source reads the local copy', () async {
    final adapter = M3uAdapter(
      const SourceConfig(
        kind: SourceKind.m3uFile,
        url: 'test/fixtures/m3u/mixed.m3u',
      ),
      dio: Dio(),
    );
    expect((await adapter.verify()).status, AccountStatus.active);
    final batches = await adapter.fetchCatalog().toList();
    expect(batches.whereType<ChannelsBatch>().single.items, hasLength(3));
  });

  group('resolve', () {
    const ref = PlayableRef(
      kind: PlayableKind.live,
      key: 'k',
      url: 'http://127.0.0.1/live/1.ts',
      title: 'One',
    );

    test('falls back to the app User-Agent', () {
      final r = adapterFor('').resolve(ref);
      expect(r.url, 'http://127.0.0.1/live/1.ts');
      expect(r.headers, {'User-Agent': kDefaultUserAgent});
      expect(r.kind, PlayableKind.live);
      expect(r.isLive, isTrue);
      expect(r.isHls, isFalse);
      expect(r.title, 'One');
    });

    test('source User-Agent and Referer beat the default', () {
      final adapter = adapterFor(
        '',
        config: _config.copyWith(
          userAgent: 'SourceUA',
          referer: 'http://ref.example.com/',
        ),
      );
      expect(adapter.resolve(ref).headers, {
        'User-Agent': 'SourceUA',
        'Referer': 'http://ref.example.com/',
      });
    });

    test('entry headers beat the source', () {
      final adapter = adapterFor(
        '',
        config: _config.copyWith(
          userAgent: 'SourceUA',
          referer: 'http://ref.example.com/',
        ),
      );
      final r = adapter.resolve(
        const PlayableRef(
          kind: PlayableKind.movie,
          key: 'k',
          url: 'http://127.0.0.1/movie/1.mkv',
          headers: {'user-agent': 'EntryUA', 'X-Token': 't'},
        ),
        startAt: const Duration(seconds: 42),
      );
      expect(r.headers, {
        'User-Agent': 'EntryUA',
        'Referer': 'http://ref.example.com/',
        'X-Token': 't',
      });
      expect(r.kind, PlayableKind.movie);
      expect(r.startAt, const Duration(seconds: 42));
    });

    test('blank source values are ignored', () {
      final adapter = adapterFor(
        '',
        config: _config.copyWith(userAgent: '  ', referer: ''),
      );
      expect(adapter.resolve(ref).headers, {'User-Agent': kDefaultUserAgent});
    });

    test('a pipe suffix on the stored URL is honoured', () {
      final r = adapterFor('').resolve(
        const PlayableRef(
          kind: PlayableKind.live,
          key: 'k',
          url: 'http://127.0.0.1/a.m3u8|User-Agent=PipeUA',
          headers: {'Referer': 'http://entry.example.com/'},
        ),
      );
      expect(r.url, 'http://127.0.0.1/a.m3u8');
      expect(r.headers, {
        'User-Agent': 'PipeUA',
        'Referer': 'http://entry.example.com/',
      });
      expect(r.isHls, isTrue);
    });

    test('HLS detection', () {
      final adapter = adapterFor('');
      bool hls(String url) => adapter
          .resolve(PlayableRef(kind: PlayableKind.live, key: 'k', url: url))
          .isHls;
      expect(hls('http://127.0.0.1/a/index.m3u8?token=x'), isTrue);
      expect(hls('http://127.0.0.1/play.php?id=1&type=m3u8'), isTrue);
      expect(hls('http://127.0.0.1/live/1.ts'), isFalse);
    });

    test('missing URL is a ParseFailure', () {
      expect(
        () =>
            adapterFor('')
                .resolve(const PlayableRef(kind: PlayableKind.live, key: 'k')),
        throwsA(isA<ParseFailure>()),
      );
    });
  });

  test('implements SourceAdapter', () {
    expect(adapterFor(''), isA<SourceAdapter>());
  });
}
