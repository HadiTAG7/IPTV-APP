import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/sources/xtream_link.dart';

void main() {
  test('get.php with type and output', () {
    final link = parseXtreamLink(
      'http://panel.example.com:8080/get.php?username=demo&password=pa55&type=m3u_plus&output=ts',
    )!;
    expect(link.base, 'http://panel.example.com:8080');
    expect(link.username, 'demo');
    expect(link.password, 'pa55');
    expect(link.output, 'ts');
    expect(link.liveFormat, LiveFormat.ts);
  });

  test('player_api.php over https without port', () {
    final link = parseXtreamLink(
      'https://panel.example.com/player_api.php?username=u1&password=p1',
    )!;
    expect(link.base, 'https://panel.example.com');
    expect(link.output, isNull);
  });

  test('values are URL-decoded and names match case-insensitively', () {
    final link = parseXtreamLink(
      'http://127.0.0.1:25461/GET.PHP?Username=my%20user&PASSWORD=p%26ss%2Bw0rd&output=m3u8',
    )!;
    expect(link.base, 'http://127.0.0.1:25461');
    expect(link.username, 'my user');
    expect(link.password, 'p&ss+w0rd');
    expect(link.liveFormat, LiveFormat.m3u8);
  });

  test('default port is dropped, path prefix kept', () {
    expect(
      parseXtreamLink(
        'http://panel.example.com:80/get.php?username=a&password=b',
      )?.base,
      'http://panel.example.com',
    );
    expect(
      parseXtreamLink(
        'http://panel.example.com/sub/dir/get.php?username=a&password=b',
      )?.base,
      'http://panel.example.com/sub/dir',
    );
  });

  test('IPv6 hosts keep their brackets', () {
    expect(
      parseXtreamLink('http://[::1]:8080/get.php?username=a&password=b')?.base,
      'http://[::1]:8080',
    );
  });

  test('toSourceConfig', () {
    final config = parseXtreamLink(
      'http://panel.example.com:8080/get.php?username=demo&password=pa55&output=hls',
    )!.toSourceConfig(name: 'Mine');
    expect(config.kind, SourceKind.xtream);
    expect(config.url, 'http://panel.example.com:8080');
    expect(config.username, 'demo');
    expect(config.password, 'pa55');
    expect(config.name, 'Mine');
    expect(config.liveFormat, LiveFormat.m3u8);
  });

  test('toString hides credentials', () {
    final link = parseXtreamLink(
      'http://panel.example.com/get.php?username=demo&password=pa55',
    )!;
    expect(link.toString(), isNot(contains('pa55')));
    expect(link.toString(), isNot(contains('demo')));
  });

  test('rejects other URLs', () {
    for (final url in [
      '',
      'not a url',
      'http://panel.example.com/playlist.m3u',
      'http://panel.example.com/get.php',
      'http://panel.example.com/get.php?username=a',
      'http://panel.example.com/get.php?username=&password=b',
      'http://panel.example.com/xget.php?username=a&password=b',
      'http://panel.example.com/get.php/extra?username=a&password=b',
      'ftp://panel.example.com/get.php?username=a&password=b',
      '/get.php?username=a&password=b',
    ]) {
      expect(parseXtreamLink(url), isNull, reason: url);
    }
  });
}
