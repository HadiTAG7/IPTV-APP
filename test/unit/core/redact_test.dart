import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/net/redact.dart';

void main() {
  test('redacts Xtream query credentials', () {
    expect(
      redact(
        'http://h:8080/player_api.php?username=bob&password=s3cret&action=x',
      ),
      'http://h:8080/player_api.php?username=***&password=***&action=x',
    );
  });

  test('redacts Xtream path credentials', () {
    expect(
      redact('http://h/live/bob/s3cret/123.ts'),
      'http://h/live/***/***/123.ts',
    );
    expect(
      redact('http://h/movie/bob/s3cret/9.mkv'),
      'http://h/movie/***/***/9.mkv',
    );
    expect(
      redact('http://h/series/a/b/9.mp4'),
      'http://h/series/***/***/9.mp4',
    );
  });

  test('redacts user info and explicit secrets', () {
    expect(redact('https://u:p@host/list.m3u'), 'https://***@host/list.m3u');
    expect(redact('error for s3cret!', secrets: ['s3cret']), 'error for ***!');
  });

  test('redacts common token parameter names', () {
    expect(
      redact('https://cdn.example.net/list.m3u?access_token=SECRETTOKEN123'),
      'https://cdn.example.net/list.m3u?access_token=***',
    );
    expect(
      redact('https://h/epg.xml?api_key=K1&apikey=K2&X-Amz-Signature=S&a=1'),
      'https://h/epg.xml?api_key=***&apikey=***&X-Amz-Signature=***&a=1',
    );
    expect(
      redact('http://h/get.php?u=alice&p=SECRETPW&type=m3u_plus'),
      'http://h/get.php?u=***&p=***&type=m3u_plus',
    );
    expect(
      redact('fetch http://h/x?passwd=a1&client_secret=b2 failed'),
      'fetch http://h/x?passwd=***&client_secret=*** failed',
    );
  });

  test('a password with an unencoded @ is masked whole', () {
    expect(
      redact('http://user:p@ss@host.example/list.m3u'),
      'http://***@host.example/list.m3u',
    );
    expect(
      redact('see http://u:a@b@host.example and http://other/x'),
      'see http://***@host.example and http://other/x',
    );
  });

  test('credential parameter names', () {
    for (final name in [
      'u',
      'p',
      'user',
      'Username',
      'password',
      'passwd',
      'pwd',
      'token',
      'access_token',
      'api_key',
      'apikey',
      'auth',
      'client_secret',
      'sig',
    ]) {
      expect(isCredentialParam(name), isTrue, reason: name);
    }
    for (final name in [
      'page',
      'id',
      'type',
      'output',
      'action',
      'keyword',
      'stream_id',
      'category_id',
    ]) {
      expect(isCredentialParam(name), isFalse, reason: name);
    }
  });

  test('leaves ordinary URLs alone', () {
    const url = 'https://iptv-org.github.io/iptv/countries/sa.m3u';
    expect(redact(url), url);
    const query = 'http://h/player_api.php?action=get_live&category_id=3&p2=1';
    expect(redact(query), query);
    const email = 'https://h/list.m3u?contact=a@b.example';
    expect(redact(email), email);
  });
}
