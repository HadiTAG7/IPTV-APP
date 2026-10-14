import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/sources/m3u/m3u_classify.dart';

void main() {
  group('classifyM3uUrl', () {
    test('path markers', () {
      expect(
        classifyM3uUrl('http://h.example.com/movie/u/p/1.mkv'),
        M3uItemKind.movie,
      );
      expect(
        classifyM3uUrl('http://h.example.com/series/u/p/2.mp4'),
        M3uItemKind.episode,
      );
      expect(
        classifyM3uUrl('http://h.example.com/live/u/p/3.ts'),
        M3uItemKind.live,
      );
      expect(
        classifyM3uUrl('http://h.example.com/MOVIE/1.mkv'),
        M3uItemKind.movie,
      );
    });

    test('file extensions', () {
      for (final ext in ['mp4', 'mkv', 'avi', 'mov', 'm4v', 'MKV']) {
        expect(
          classifyM3uUrl('http://h.example.com/vod/file.$ext?token=1'),
          M3uItemKind.movie,
          reason: ext,
        );
      }
      expect(
        classifyM3uUrl('http://h.example.com/live/channel.mp4'),
        M3uItemKind.live,
      );
      expect(
        classifyM3uUrl('http://h.example.com/a/stream.m3u8'),
        M3uItemKind.live,
      );
      expect(classifyM3uUrl('http://h.example.com/123'), M3uItemKind.live);
      expect(classifyM3uUrl('udp://@239.0.0.1:1234'), M3uItemKind.live);
    });

    test('query and host do not affect classification', () {
      expect(
        classifyM3uUrl('http://h.example.com/play?file=/movie/x.mkv'),
        M3uItemKind.live,
      );
      expect(classifyM3uUrl('http://movie.mkv'), M3uItemKind.live);
    });

    test('radio is always live', () {
      expect(
        classifyM3uUrl('http://h.example.com/movie/x.mp4', isRadio: true),
        M3uItemKind.live,
      );
    });
  });

  group('matchEpisode', () {
    test('common forms', () {
      expect(matchEpisode('Example Show S01E02'), (
        series: 'Example Show',
        season: 1,
        episode: 2,
      ));
      expect(matchEpisode('Example Show - S2 E10'), (
        series: 'Example Show',
        season: 2,
        episode: 10,
      ));
      expect(matchEpisode('Example.Show.s03e104.1080p'), (
        series: 'Example Show',
        season: 3,
        episode: 104,
      ));
      expect(matchEpisode('Example_Show_S01_E01'), (
        series: 'Example Show',
        season: 1,
        episode: 1,
      ));
      expect(matchEpisode('Mrs Example S01E05 Pilot'), (
        series: 'Mrs Example',
        season: 1,
        episode: 5,
      ));
    });

    test('keeps dots when the name has spaces', () {
      expect(matchEpisode('Mr. Example S01E01')?.series, 'Mr. Example');
    });

    test('Arabic names', () {
      expect(matchEpisode('مسلسل تجريبي S01E03')?.series, 'مسلسل تجريبي');
    });

    test('no marker or no name', () {
      expect(matchEpisode('Some Film 2020'), isNull);
      expect(matchEpisode('Season Finale'), isNull);
      expect(matchEpisode('S01E01'), isNull);
    });
  });

  test('seriesKeyFor normalises the name', () {
    expect(seriesKeyFor('Example  SHOW'), 'series:example show');
    expect(seriesKeyFor('أحمد'), seriesKeyFor('احمد'));
  });

  group('url helpers', () {
    test('stripQuery', () {
      expect(stripQuery('http://a/b.ts?x=1#f'), 'http://a/b.ts');
      expect(stripQuery('http://a/b.ts#f?x'), 'http://a/b.ts');
      expect(stripQuery('http://a/b.ts'), 'http://a/b.ts');
      expect(stripQuery('?only=query'), '');
    });

    test('urlPath and urlExtension', () {
      expect(urlPath('http://h:80/a/b.mkv?x'), '/a/b.mkv');
      expect(urlPath('http://h'), '');
      expect(urlPath('/local/file.m3u'), '/local/file.m3u');
      expect(urlExtension('http://h/a/b.MKV?x=1.mp4'), 'mkv');
      expect(urlExtension('http://h/a.dir/b'), isNull);
      expect(urlExtension('http://h.example.com'), isNull);
      expect(urlExtension('http://h/a/b.'), isNull);
      expect(urlExtension('http://h/a/b.toolongext'), isNull);
    });

    test('lastPathSegment', () {
      expect(lastPathSegment('http://h/a/My%20File.ts?x'), 'My File.ts');
      expect(lastPathSegment('http://h/a/b/'), 'b');
      expect(lastPathSegment('http://h/a/100%'), '100%');
      expect(lastPathSegment('http://h'), '');
    });

    test('looksLikeHls', () {
      expect(looksLikeHls('http://h/a/index.m3u8'), isTrue);
      expect(looksLikeHls('http://h/a/INDEX.M3U8?token=1'), isTrue);
      expect(looksLikeHls('http://h/play?type=m3u8'), isTrue);
      expect(looksLikeHls('http://h/live/1.ts'), isFalse);
    });
  });

  test('baseStableKey', () {
    expect(baseStableKey('http://h/a.ts?token=1', name: 'A'), 'http://h/a.ts');
    expect(
      baseStableKey('?token=1', tvgId: 'News.One', name: 'N'),
      'news.one|N',
    );
    expect(baseStableKey('', name: 'N'), '|N');
  });

  test('extractYear', () {
    expect(extractYear('Film (2021)'), 2021);
    expect(extractYear('Film (1080) (1999)'), 1999);
    expect(extractYear('Film 2021'), isNull);
    expect(extractYear('Film (3000)'), isNull);
  });
}
