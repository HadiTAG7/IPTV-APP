import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/sources/m3u/m3u_episode_store.dart';
import 'package:iptv_player/sources/models.dart';

String describe(EpisodeData e) => [
  e.seriesKey,
  e.key,
  e.season,
  e.number,
  e.title,
  e.ext,
  e.url,
  e.headers,
  e.durationSec,
  e.plot,
  e.still,
].join(' | ');

EpisodeData ep(
  int n, {
  String series = 'series:show',
  String? key,
  int season = 1,
  String? still = 'http://img.example.com/show.jpg',
  Map<String, String> headers = const {},
  int? duration,
}) {
  final url = 'http://127.0.0.1/series/u/p/$n.mkv';
  return EpisodeData(
    seriesKey: series,
    key: key ?? url,
    season: season,
    number: n,
    title: 'Show S${season}E$n',
    ext: 'mkv',
    url: url,
    headers: headers,
    durationSec: duration,
    still: still,
  );
}

void main() {
  test('round-trips every field', () {
    final input = [
      ep(1, duration: 2700),
      ep(2, key: 'http://127.0.0.1/series/u/p/2.mkv#2', still: null),
      const EpisodeData(
        seriesKey: 'series:show',
        key: 'id.one|Épisode حلقة',
        season: -3,
        number: 1 << 40,
        title: 'مسلسل S01E01 — \u{1F3AC}',
        headers: {'User-Agent': 'UA/1', 'Referer': 'http://r.example.com/'},
        plot: 'Plot, with "quotes"',
        still: '',
      ),
      const EpisodeData(
        seriesKey: 'series:show',
        key: 'k',
        season: 0,
        number: -1 << 62,
        durationSec: 0,
      ),
    ];
    final store = M3uEpisodeStore();
    input.forEach(store.add);
    expect(store.length, 4);
    expect(store.seriesCount, 1);
    expect(store.episodesOf('series:show')!.map(describe), input.map(describe));
  });

  test('unknown series is null; series stay separate', () {
    final store = M3uEpisodeStore()
      ..add(ep(1, series: 'series:a'))
      ..add(ep(1, series: 'series:b', season: 2))
      ..add(ep(2, series: 'series:a'));
    expect(store.episodesOf('series:missing'), isNull);
    expect(store.containsSeries('series:a'), isTrue);
    expect(store.episodesOf('series:a')!.map((e) => e.number), [1, 2]);
    expect(store.episodesOf('series:b')!.single.season, 2);
  });

  test('repeated stills and headers are restored per episode', () {
    const h1 = {'User-Agent': 'A'};
    const h2 = {'User-Agent': 'B', 'X-T': '1'};
    final input = [
      ep(1, still: 's1', headers: h1),
      ep(2, still: 's1', headers: {...h1}),
      ep(3, still: 's2', headers: h2),
      ep(4, still: null),
      ep(5, still: null),
      ep(6, still: 's1', headers: h1),
      ep(7, series: 'series:other', still: 's2', headers: h2),
      ep(8, still: 's1', headers: h1),
    ];
    final store = M3uEpisodeStore();
    input.forEach(store.add);
    final out = [
      ...store.episodesOf('series:show')!,
      ...store.episodesOf('series:other')!,
    ]..sort((a, b) => a.number.compareTo(b.number));
    expect(out.map(describe), input.map(describe));
  });

  test('shared prefixes, keys derived from the URL, surrogate pairs', () {
    EpisodeData e(String url, String key, String title, String? still) =>
        EpisodeData(
          seriesKey: 'series:x',
          key: key,
          season: 1,
          number: 1,
          title: title,
          url: url,
          still: still,
        );
    final input = [
      e(
        'http://h/s/1.mkv?t=1',
        'http://h/s/1.mkv',
        'Show S01E01',
        'http://i/1',
      ),
      e('http://h/s/1.mkv?t=2', 'http://h/s/1.mkv#2', 'Show S01E01', null),
      e('http://h/s/10.mkv', 'http://h/s/10.mkv', 'Show', 'http://i/1'),
      e(
        'http://h/s/1.mkv',
        'id|\u{1F3AC}',
        '\u{1F3AC}\u{1F3AD}',
        'http://i/12',
      ),
      e('http://h/s/1.mkv', 'id|\u{1F3AD}', '\u{1F3AC}\u{1F3AC}', ''),
      e('', '', '', 'http://i'),
      e('http://h/other', 'http://h/other', 'Different', 'http://i/12'),
    ];
    final store = M3uEpisodeStore();
    input.forEach(store.add);
    expect(store.episodesOf('series:x')!.map(describe), input.map(describe));
  });

  test('records spill over 64 KB pages and oversized records fit', () {
    final store = M3uEpisodeStore();
    final big = 'x' * (100 * 1024);
    final input = [
      for (var i = 0; i < 3000; i++) ep(i, season: i % 7),
      ep(3000, headers: {'Cookie': big}),
      ep(3001),
    ];
    input.forEach(store.add);
    expect(store.pageBytes, greaterThan(100 * 1024));
    expect(store.episodesOf('series:show')!.map(describe), input.map(describe));
  });

  test('stays compact: roughly the URL and title bytes per episode', () {
    final store = M3uEpisodeStore();
    const count = 20000;
    for (var i = 0; i < count; i++) {
      store.add(ep(i, series: 'series:s${i ~/ 50}', duration: 1500));
    }
    // Episodes of one series share URL, title and still prefixes, so only
    // a few bytes per episode remain.
    expect(store.pageBytes, lessThan(count * 32));
    expect(store.episodesOf('series:s3')!.first.number, 150);
  });

  test('clear drops everything', () {
    final store = M3uEpisodeStore()..add(ep(1));
    store.clear();
    expect(store.length, 0);
    expect(store.pageBytes, 0);
    expect(store.episodesOf('series:show'), isNull);
    store.add(ep(2));
    expect(store.episodesOf('series:show')!.single.number, 2);
  });
}
