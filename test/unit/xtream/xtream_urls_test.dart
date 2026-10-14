import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/sources/xtream/xtream_urls.dart';

void main() {
  group('normalizeBase', () {
    test('adds http:// when no scheme and keeps the port', () {
      expect(
        XtreamUrls.normalizeBase('example.com:8080'),
        'http://example.com:8080',
      );
      expect(
        XtreamUrls.normalizeBase('127.0.0.1:25461/'),
        'http://127.0.0.1:25461',
      );
    });

    test('trims whitespace and trailing slashes', () {
      expect(
        XtreamUrls.normalizeBase('  http://example.com:8080///  '),
        'http://example.com:8080',
      );
    });

    test('keeps https and lower-cases the scheme only', () {
      expect(
        XtreamUrls.normalizeBase('HTTPS://Panel.Example.com:8443/'),
        'https://Panel.Example.com:8443',
      );
    });

    test('strips a pasted endpoint and its query', () {
      expect(
        XtreamUrls.normalizeBase(
          'http://example.com:8080/player_api.php?username=a&password=b',
        ),
        'http://example.com:8080',
      );
      expect(
        XtreamUrls.normalizeBase(
          'http://example.com/get.php?username=a&password=b&type=m3u_plus',
        ),
        'http://example.com',
      );
      expect(
        XtreamUrls.normalizeBase('http://example.com:80/xmltv.php'),
        'http://example.com:80',
      );
    });

    test('keeps a path prefix', () {
      expect(
        XtreamUrls.normalizeBase('http://example.com/panel/'),
        'http://example.com/panel',
      );
    });
  });

  group('with special characters in credentials', () {
    final urls = XtreamUrls('example.com:8080/', 'user name', 'p@ss/w rd');
    const u = 'user%20name';
    const p = 'p%40ss%2Fw%20rd';

    test('player_api without action', () {
      final uri = urls.playerApi();
      expect(
        uri.toString(),
        'http://example.com:8080/player_api.php?username=$u&password=$p',
      );
      expect(uri.queryParameters, {
        'username': 'user name',
        'password': 'p@ss/w rd',
      });
    });

    test('player_api with action and params', () {
      final uri = urls.playerApi(
        action: 'get_live_streams',
        params: {'category_id': '1&2'},
      );
      expect(
        uri.toString(),
        'http://example.com:8080/player_api.php?username=$u&password=$p'
        '&action=get_live_streams&category_id=1%262',
      );
      expect(uri.queryParameters['category_id'], '1&2');
      expect(uri.queryParameters['action'], 'get_live_streams');
    });

    test('xmltv and get.php', () {
      expect(
        urls.xmltv(),
        'http://example.com:8080/xmltv.php?username=$u&password=$p',
      );
      expect(
        urls.getPhp(),
        'http://example.com:8080/get.php?username=$u&password=$p'
        '&type=m3u_plus&output=ts',
      );
      expect(
        urls.getPhp(type: 'm3u', output: 'm3u8'),
        endsWith('&type=m3u&output=m3u8'),
      );
    });

    test('stream URLs encode credentials as path segments', () {
      final live = urls.live('101', 'ts');
      expect(live, 'http://example.com:8080/live/$u/$p/101.ts');
      expect(Uri.parse(live).pathSegments, [
        'live',
        'user name',
        'p@ss/w rd',
        '101.ts',
      ]);
      expect(
        urls.movie('1001', 'mkv'),
        'http://example.com:8080/movie/$u/$p/1001.mkv',
      );
      expect(
        urls.episode('90001', '.mp4'),
        'http://example.com:8080/series/$u/$p/90001.mp4',
      );
      expect(urls.live('7', 'm3u8'), endsWith('/7.m3u8'));
    });

    test('timeshift', () {
      expect(
        urls.timeshift('101', 60, DateTime(2024, 3, 5, 7, 9)),
        'http://example.com:8080/timeshift/$u/$p/60/2024-03-05:07-09/101.ts',
      );
    });
  });

  test('plain credentials stay readable', () {
    final urls = XtreamUrls('http://example.com', 'demo', 'pass123');
    expect(urls.live('1', 'ts'), 'http://example.com/live/demo/pass123/1.ts');
  });
}
