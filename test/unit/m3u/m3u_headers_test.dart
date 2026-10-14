import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/sources/m3u/m3u_headers.dart';

void main() {
  test('canonicalHeaderName', () {
    expect(canonicalHeaderName('user-agent'), 'User-Agent');
    expect(canonicalHeaderName('USER-AGENT'), 'User-Agent');
    expect(canonicalHeaderName('referrer'), 'Referer');
    expect(canonicalHeaderName(' Referer '), 'Referer');
    expect(canonicalHeaderName('x-forwarded-for'), 'X-Forwarded-For');
    expect(canonicalHeaderName('cookie'), 'Cookie');
  });

  test('mergeHeaders lets later values win regardless of case', () {
    final h = {'User-Agent': 'A'};
    mergeHeaders(h, {'user-agent': 'B', 'origin': 'http://o.example.com'});
    expect(h, {'User-Agent': 'B', 'Origin': 'http://o.example.com'});
  });

  test('mergeHeaders ignores blank values', () {
    final h = {'User-Agent': 'A', 'Referer': 'http://r/'};
    mergeHeaders(h, {'user-agent': '', 'Referer': '  ', 'X-Token': 't'});
    expect(h, {'User-Agent': 'A', 'Referer': 'http://r/', 'X-Token': 't'});
  });

  group('splitPipeHeaders', () {
    test('no suffix', () {
      final r = splitPipeHeaders('http://h/a.ts');
      expect(r.url, 'http://h/a.ts');
      expect(r.headers, isEmpty);
    });

    test('Kodi style', () {
      final r = splitPipeHeaders(
        'http://h/a.ts?x=1|User-Agent=Agent%2F1&!Referer=http://r/&bad&=x',
      );
      expect(r.url, 'http://h/a.ts?x=1');
      expect(r.headers, {'User-Agent': 'Agent/1', 'Referer': 'http://r/'});
    });

    test('pipe-separated pairs and broken percent-encoding', () {
      final r = splitPipeHeaders('http://h/a|user-agent=A%ZZ|referrer=R');
      expect(r.headers, {'User-Agent': 'A%ZZ', 'Referer': 'R'});
    });

    test('blank values are dropped', () {
      final r = splitPipeHeaders(
        'http://h/a.ts|User-Agent=&Referer=%20&X-Token=t',
      );
      expect(r.url, 'http://h/a.ts');
      expect(r.headers, {'X-Token': 't'});
      expect(parseHeaderPairs('User-Agent=  |Referer='), isEmpty);
    });
  });

  test('parseVlcOpt', () {
    expect(parseVlcOpt('http-user-agent=UA/1')?.key, 'User-Agent');
    expect(parseVlcOpt('http-user-agent="UA/1"')?.value, 'UA/1');
    expect(parseVlcOpt('http-referrer=http://r/')?.key, 'Referer');
    expect(parseVlcOpt('http-referer=http://r/')?.key, 'Referer');
    expect(parseVlcOpt('http-origin=http://o/')?.key, 'Origin');
    expect(parseVlcOpt('network-caching=1000'), isNull);
    expect(parseVlcOpt('http-user-agent='), isNull);
    expect(parseVlcOpt('http-user-agent=" "'), isNull);
    expect(parseVlcOpt('garbage'), isNull);
  });

  test('parseExtHttp', () {
    expect(parseExtHttp('{"user-agent":"A","X-Num":5,"nested":{}}'), {
      'User-Agent': 'A',
      'X-Num': '5',
    });
    expect(parseExtHttp('[1,2]'), isEmpty);
    expect(parseExtHttp('{"User-Agent":"","Referer":"  ","X-A":"a"}'), {
      'X-A': 'a',
    });
    expect(parseExtHttp('{oops'), isEmpty);
  });

  test('parseKodiPropHeaders', () {
    expect(
      parseKodiPropHeaders(
        'inputstream.adaptive.stream_headers=User-Agent=A%2F1&Referer=http%3A%2F%2Fr%2F',
      ),
      {'User-Agent': 'A/1', 'Referer': 'http://r/'},
    );
    expect(
      parseKodiPropHeaders('inputstream.adaptive.manifest_headers=Cookie=c=1'),
      {'Cookie': 'c=1'},
    );
    expect(parseKodiPropHeaders('inputstream.adaptive.manifest_type=hls'), {});
    expect(parseKodiPropHeaders('noequals'), isEmpty);
    expect(
      parseKodiPropHeaders(
        'inputstream.adaptive.stream_headers=User-Agent=&Referer=',
      ),
      isEmpty,
    );
  });

  test('splitUrlList', () {
    expect(splitUrlList(null), isEmpty);
    expect(splitUrlList(' a , ,b,'), ['a', 'b']);
  });

  test('parseShiftMinutes', () {
    expect(parseShiftMinutes('+2'), 120);
    expect(parseShiftMinutes('-3.5'), -210);
    expect(parseShiftMinutes('5,5'), 330);
    expect(parseShiftMinutes('0.25'), 15);
    expect(parseShiftMinutes('x'), isNull);
    expect(parseShiftMinutes(null), isNull);
  });

  test('parseShiftMinutes rejects non-finite and absurd values', () {
    expect(parseShiftMinutes('48'), 2880);
    expect(parseShiftMinutes('-48'), -2880);
    for (final v in ['NaN', 'Infinity', '-Infinity', '1e308', '1e999', '49']) {
      expect(parseShiftMinutes(v), isNull, reason: v);
    }
  });
}
