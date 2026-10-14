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

  test('leaves ordinary URLs alone', () {
    const url = 'https://iptv-org.github.io/iptv/countries/sa.m3u';
    expect(redact(url), url);
  });
}
