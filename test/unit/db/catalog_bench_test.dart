// Run with: flutter test --tags bench test/unit/db/catalog_bench_test.dart
@Tags(['bench'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/sources/models.dart';

import 'db_test_utils.dart';

const _total = 100000;
const _batch = 5000;
const _categories = 200;

List<ChannelData> _batchAt(int start) => [
  for (var i = start; i < start + _batch; i++)
    ChannelData(
      key: 'http://127.0.0.1:8080/live/$i.ts',
      name: i.isEven ? 'Channel $i HD' : 'قناة رقم $i',
      num: i + 1,
      url: 'http://127.0.0.1:8080/live/$i.ts',
      tvgId: 'ch$i.example',
      logo: 'http://127.0.0.1:8080/logo/$i.png',
      // Every tenth channel sits in two groups.
      categoryKeys: ['group ${i % _categories}', if (i % 10 == 0) 'featured'],
    ),
];

Future<Duration> _timed(Future<void> Function() body) async {
  final sw = Stopwatch()..start();
  await body();
  return sw.elapsed;
}

void main() {
  test('100k channels import in batches under 15 s', () async {
    final db = openTestDb();
    addTearDown(db.close);
    final src = await addSource(db);
    final catalog = db.catalogDao;

    var lastCommit = Duration.zero;
    Future<void> importAll() async {
      final gen = await catalog.beginGeneration(src);
      await catalog.upsertCategories(src, gen, [
        for (var c = 0; c < _categories; c++)
          CategoryData(
            kind: ContentKind.live,
            key: 'group $c',
            name: 'Group $c',
          ),
        const CategoryData(
          kind: ContentKind.live,
          key: 'featured',
          name: 'Featured',
        ),
      ]);
      for (var start = 0; start < _total; start += _batch) {
        await catalog.upsertChannels(src, gen, _batchAt(start));
      }
      lastCommit = await _timed(() => catalog.commitGeneration(src, gen));
    }

    final first = await _timed(importAll);
    final refresh = await _timed(importAll);
    debugPrint('first import: ${first.inMilliseconds} ms');
    debugPrint('refresh import: ${refresh.inMilliseconds} ms');
    debugPrint('refresh commit (swap): ${lastCommit.inMilliseconds} ms');
    expect(first, lessThan(const Duration(seconds: 15)));
    expect(refresh, lessThan(const Duration(seconds: 15)));
    expect(lastCommit, lessThan(const Duration(seconds: 3)));

    expect(await catalog.totalCount(src, ContentKind.live), _total);
    expect(
      await catalog.itemCount(src, ContentKind.live, 'featured'),
      _total ~/ 10,
    );
    expect(
      await catalog.itemCount(src, ContentKind.live, 'group 7'),
      _total ~/ _categories,
    );

    final reads = <String, Duration>{
      'category page (deep)': await _timed(
        () => catalog.channelsPage(src, 'featured', 9800, 200),
      ),
      'all channels page (deep)': await _timed(
        () => catalog.allChannelsPage(src, 90000, 200),
      ),
      'zapping keys (10k)': await _timed(
        () => catalog.channelKeysInCategory(src, 'featured'),
      ),
      'search latin': await _timed(() => catalog.search(src, '9999')),
      'search arabic': await _timed(() => catalog.search(src, 'قناه رقم 77')),
    };
    reads.forEach((k, v) => debugPrint('$k: ${v.inMilliseconds} ms'));
    final page = await catalog.channelsPage(src, 'featured', 9800, 200);
    expect(page, hasLength(200));
    expect(page.first.num, 98001);
    final all = await catalog.allChannelsPage(src, 90000, 5);
    expect(all.first.num, 90001);
    for (final v in reads.values) {
      expect(v, lessThan(const Duration(seconds: 2)));
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('All movies pages of 50k titles in natural order', () async {
    const count = 50000;
    final db = openTestDb();
    addTearDown(db.close);
    final src = await addSource(db);
    final catalog = db.catalogDao;
    final gen = await catalog.beginGeneration(src);
    await catalog.upsertCategories(src, gen, const [
      CategoryData(kind: ContentKind.movie, key: 'films', name: 'Films'),
    ]);
    final added = DateTime.utc(2026);
    for (var start = 0; start < count; start += _batch) {
      await catalog.upsertMovies(src, gen, [
        for (var i = start; i < start + _batch; i++)
          MovieData(
            key: '$i',
            name: i.isEven ? 'Movie $i (2020)' : 'فيلم رقم $i',
            categoryKeys: const ['films'],
            // A third without an added time (M3U style), the rest in
            // batches sharing one time.
            addedAt: i % 3 == 0 ? null : added.add(Duration(hours: i ~/ 100)),
          ),
      ]);
    }
    await catalog.commitGeneration(src, gen);

    final reads = <String, Duration>{
      'first page': await _timed(() => catalog.allMoviesPage(src, 0, 200)),
      'middle page': await _timed(
        () => catalog.allMoviesPage(src, count ~/ 2, 200),
      ),
      'last page': await _timed(
        () => catalog.allMoviesPage(src, count - 200, 200),
      ),
    };
    reads.forEach(
      (k, v) => debugPrint('all movies $k: ${v.inMilliseconds} ms'),
    );
    expect(await catalog.allMoviesPage(src, count - 200, 200), hasLength(200));
    for (final v in reads.values) {
      expect(v, lessThan(const Duration(seconds: 2)));
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
