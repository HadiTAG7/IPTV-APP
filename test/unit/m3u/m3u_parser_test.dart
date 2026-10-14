import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/sources/m3u/byte_source.dart';
import 'package:iptv_player/sources/m3u/m3u_parser.dart';

List<M3uEntry> entriesOf(String text) =>
    parseM3uString(text).whereType<M3uEntry>().toList();

String fixture(String name) =>
    File('test/fixtures/m3u/$name').readAsStringSync();

void main() {
  group('parseExtInf', () {
    test('reads duration, quoted/bare attributes and title', () {
      final inf = parseExtInf(
        '-1 tvg-id="a.b" tvg-name=\'Single\' tvg-logo=http://x/y.png,Title',
      );
      expect(inf.duration, -1);
      expect(inf.attrs, {
        'tvg-id': 'a.b',
        'tvg-name': 'Single',
        'tvg-logo': 'http://x/y.png',
      });
      expect(inf.title, 'Title');
    });

    test('title keeps commas after the first comma outside quotes', () {
      final inf = parseExtInf(
        '-1 group-title="News, World",Breaking, live, now',
      );
      expect(inf.attrs['group-title'], 'News, World');
      expect(inf.title, 'Breaking, live, now');
    });

    test('lower-cases keys', () {
      final inf = parseExtInf('-1 TVG-ID="X" Group-Title="G",T');
      expect(inf.attrs, {'tvg-id': 'X', 'group-title': 'G'});
    });

    test('quotes inside the title are kept verbatim', () {
      final inf = parseExtInf('-1 tvg-id="a",He said "hi", ok');
      expect(inf.title, 'He said "hi", ok');
    });

    test('apostrophes inside double-quoted values', () {
      final inf = parseExtInf('-1 tvg-name="Bob\'s Channel",Bob');
      expect(inf.attrs['tvg-name'], "Bob's Channel");
      expect(inf.title, 'Bob');
    });

    test('missing duration and fractional duration', () {
      expect(parseExtInf('tvg-id="a",T').duration, isNull);
      expect(parseExtInf('tvg-id="a",T').attrs['tvg-id'], 'a');
      expect(parseExtInf('123.5,T').duration, 123.5);
      expect(parseExtInf('0,T').title, 'T');
    });

    test('spaces around = and bare flags', () {
      final inf = parseExtInf('-1 tvg-id = "spaced" catchup ,Name');
      expect(inf.attrs['tvg-id'], 'spaced');
      expect(inf.attrs['catchup'], '');
      expect(inf.title, 'Name');
    });

    test('empty title', () {
      expect(parseExtInf('-1 tvg-id="a",').title, '');
      expect(parseExtInf('-1 tvg-id="a"').title, '');
    });

    test('unterminated quote recovers at the next comma', () {
      final inf = parseExtInf('-1 tvg-name="Broken,Title Here');
      expect(inf.attrs['tvg-name'], 'Broken');
      expect(inf.title, 'Title Here');
    });

    test('stray quote does not swallow the title', () {
      final inf = parseExtInf("-1 tvg-name='O'Brien' tvg-id=\"x\",Title");
      expect(inf.attrs['tvg-name'], "O'Brien");
      expect(inf.attrs['tvg-id'], 'x');
      expect(inf.title, 'Title');
    });

    test('apostrophes inside single-quoted values', () {
      final inf = parseExtInf(
        "-1 tvg-name='Bob's Show' group-title=\"Kids\",Bob's Show",
      );
      expect(inf.attrs, {'tvg-name': "Bob's Show", 'group-title': 'Kids'});
      expect(inf.title, "Bob's Show");
      expect(
        parseExtInf("-1 tvg-name='Rock'n'Roll' group-title='Music',T").attrs,
        {'tvg-name': "Rock'n'Roll", 'group-title': 'Music'},
      );
    });

    test('unterminated single quote with an apostrophe keeps the title', () {
      final inf = parseExtInf("-1 tvg-name='Bob's Show,Bob's Show");
      expect(inf.attrs['tvg-name'], "Bob's Show");
      expect(inf.title, "Bob's Show");
    });

    test('inch mark after a double-quoted value keeps later attributes', () {
      final inf = parseExtInf(
        '-1 tvg-name="Kids 12" Screen" group-title="Kids",Kids 12in',
      );
      expect(inf.attrs['tvg-name'], 'Kids 12');
      expect(inf.attrs['group-title'], 'Kids');
      expect(inf.title, 'Kids 12in');
    });

    test('stray apostrophe in a bare word does not jump into the title', () {
      final inf = parseExtInf('-1 Bob\'s group-title="K",Bob\'s Show');
      expect(inf.attrs['group-title'], 'K');
      expect(inf.title, "Bob's Show");
    });

    test('stray quote before the comma keeps the title', () {
      final inf = parseExtInf('-1 tvg-id="a" " group-title="G",Title');
      expect(inf.attrs['tvg-id'], 'a');
      expect(inf.attrs['group-title'], 'G');
      expect(inf.title, 'Title');
    });

    test('attributes without separating spaces', () {
      final inf = parseExtInf('-1 tvg-id="a"group-title="B",T');
      expect(inf.attrs, {'tvg-id': 'a', 'group-title': 'B'});
      expect(inf.title, 'T');
    });

    test('non-finite or overflowing durations are dropped', () {
      expect(parseExtInf('${'9' * 400},T').duration, isNull);
      expect(parseExtInf('-1,T').duration, -1);
    });
  });

  test('parseM3uAttributes keeps commas in bare header values', () {
    expect(
      parseM3uAttributes('url-tvg=http://a/1.xml,http://a/2.xml m3uautoload=1'),
      {'url-tvg': 'http://a/1.xml,http://a/2.xml', 'm3uautoload': '1'},
    );
  });

  group('lines and encodings', () {
    const body =
        '#EXTM3U\n'
        '#EXTINF:-1 group-title="G",One\n'
        'http://example.com/1.ts\n'
        '#EXTINF:-1 group-title="G",Two\n'
        'http://example.com/2.ts\n';

    Future<List<M3uEntry>> streamed(List<int> bytes, {int chunk = 7}) async {
      final records = await parseM3uStream(
        MemoryByteSource(bytes, chunkSize: chunk).open(),
      ).toList();
      return records.whereType<M3uEntry>().toList();
    }

    test('BOM is stripped', () async {
      final entries = await streamed([0xEF, 0xBB, 0xBF, ...utf8.encode(body)]);
      expect(entries.map((e) => e.name), ['One', 'Two']);
      final fromString = entriesOf('\uFEFF$body');
      expect(fromString.map((e) => e.name), ['One', 'Two']);
    });

    test('CRLF line endings', () async {
      final entries = await streamed(
        utf8.encode(body.replaceAll('\n', '\r\n')),
      );
      expect(entries.map((e) => e.url), [
        'http://example.com/1.ts',
        'http://example.com/2.ts',
      ]);
    });

    test('CR-only line endings', () async {
      final entries = await streamed(utf8.encode(body.replaceAll('\n', '\r')));
      expect(entries.map((e) => e.name), ['One', 'Two']);
    });

    test('last line without a newline, CRLF split across chunks', () async {
      for (final chunk in [1, 2, 5, 1024]) {
        final entries = await streamed(
          utf8.encode('#EXTINF:-1,A\r\nhttp://example.com/a.ts'),
          chunk: chunk,
        );
        expect(entries.single.url, 'http://example.com/a.ts', reason: '$chunk');
      }
    });

    test('parseM3uChunks groups records per input chunk', () async {
      final chunks = await parseM3uChunks(
        MemoryByteSource(utf8.encode(body), chunkSize: 1 << 20).open(),
      ).toList();
      expect(chunks, hasLength(1));
      expect(chunks.single.whereType<M3uEntry>(), hasLength(2));
      expect(chunks.single.first, isA<M3uHeader>());
    });

    test('missing #EXTM3U header', () {
      final entries = entriesOf(body.replaceFirst('#EXTM3U\n', ''));
      expect(entries, hasLength(2));
    });

    test('multi-byte characters split across chunks', () async {
      const arabic =
          '#EXTM3U\n#EXTINF:-1 group-title="أخبار",قناة الأخبار\n'
          'http://example.com/ar.ts\n';
      final entries = await streamed(utf8.encode(arabic), chunk: 3);
      expect(entries.single.name, 'قناة الأخبار');
      expect(entries.single.groups, ['أخبار']);
    });

    test('malformed UTF-8 does not throw', () async {
      final bytes = [
        ...utf8.encode('#EXTINF:-1,Bad '),
        0xFF,
        0xFE,
        ...utf8.encode('\nhttp://example.com/x.ts\n'),
      ];
      final entries = await streamed(bytes);
      expect(entries.single.name, startsWith('Bad '));
    });

    test('lower-case directives and blank/whitespace lines', () {
      final entries = entriesOf(
        '#extm3u\n\n   \n#extinf:-1 group-title="g",Lower\n'
        '  http://example.com/l.ts  \n',
      );
      expect(entries.single.name, 'Lower');
      expect(entries.single.url, 'http://example.com/l.ts');
    });

    test('an #EXTINF without URL is replaced by the next one', () {
      final entries = entriesOf(
        '#EXTINF:-1,Lost\n#EXTINF:-1,Kept\nhttp://example.com/k.ts\n',
      );
      expect(entries.single.name, 'Kept');
    });

    test('comments and unknown directives are ignored', () {
      final entries = entriesOf(
        '#EXTM3U\n# just a comment\n#PLAYLIST:Mine\n'
        '#EXTINF:-1,One\n#EXT-X-UNKNOWN:1\nhttp://example.com/1.ts\n',
      );
      expect(entries.single.name, 'One');
    });
  });

  group('header', () {
    test('guide URLs from all keys, comma lists, deduplicated', () {
      final header = parseM3uString(
        '#EXTM3U x-tvg-url="http://e.example.com/a.xml, http://e.example.com/b.xml" '
        'url-tvg="http://e.example.com/b.xml" tvg-url="http://e.example.com/c.xml"\n',
      ).whereType<M3uHeader>().single;
      expect(header.epgUrls, [
        'http://e.example.com/a.xml',
        'http://e.example.com/b.xml',
        'http://e.example.com/c.xml',
      ]);
    });

    test('repeated #EXTM3U lines merge', () {
      final parser = M3uParser()
        ..addLine('#EXTM3U url-tvg="http://e.example.com/a.xml"')
        ..addLine('#EXTM3U url-tvg="http://e.example.com/b.xml" tvg-shift=2');
      expect(parser.header.epgUrls, [
        'http://e.example.com/a.xml',
        'http://e.example.com/b.xml',
      ]);
      expect(parser.header.tvgShiftMin, 120);
    });

    test('defaults apply to entries without their own values', () {
      final entries = entriesOf(
        '#EXTM3U tvg-shift="1.5" catchup="shift" catchup-days="2" '
        'catchup-source="?utc={utc}"\n'
        '#EXTINF:-1,A\nhttp://example.com/a.ts\n'
        '#EXTINF:-1 tvg-shift="-1" catchup="append" tvg-rec="5" '
        'catchup-source="?x",B\nhttp://example.com/b.ts\n',
      );
      expect(entries[0].tvgShiftMin, 90);
      expect(entries[0].catchup, 'shift');
      expect(entries[0].catchupDays, 2);
      expect(entries[0].catchupSource, '?utc={utc}');
      expect(entries[1].tvgShiftMin, -60);
      expect(entries[1].catchup, 'append');
      expect(entries[1].catchupDays, 5);
      expect(entries[1].catchupSource, '?x');
    });
  });

  group('logos', () {
    test('relative logos resolve against url-logo', () {
      final entries = entriesOf(
        '#EXTM3U url-logo="http://img.example.com/logos"\n'
        '#EXTINF:-1 tvg-logo="a.png",A\nhttp://example.com/a.ts\n'
        '#EXTINF:-1 tvg-logo="/b.png",B\nhttp://example.com/b.ts\n'
        '#EXTINF:-1 tvg-logo="https://cdn.example.com/c.png",C\n'
        'http://example.com/c.ts\n'
        '#EXTINF:-1 tvg-logo="//cdn.example.com/d.png",D\n'
        'http://example.com/d.ts\n'
        '#EXTINF:-1 tvg-logo="",E\nhttp://example.com/e.ts\n',
      );
      expect(entries.map((e) => e.logo), [
        'http://img.example.com/logos/a.png',
        'http://img.example.com/logos/b.png',
        'https://cdn.example.com/c.png',
        '//cdn.example.com/d.png',
        null,
      ]);
    });

    test('relative logo without url-logo stays as-is', () {
      expect(
        entriesOf('#EXTINF:-1 tvg-logo="a.png",A\nhttp://example.com/a\n')
            .single
            .logo,
        'a.png',
      );
    });
  });

  group('groups', () {
    test('";" separated groups are split, trimmed and deduplicated', () {
      final e = entriesOf(
        '#EXTINF:-1 group-title="News; Sports ;News;;",A\nhttp://example.com/a\n',
      ).single;
      expect(e.groups, ['News', 'Sports']);
    });

    test('fallback to Uncategorized', () {
      expect(entriesOf('#EXTINF:-1,A\nhttp://example.com/a\n').single.groups, [
        kUncategorizedGroup,
      ]);
    });

    test('#EXTGRP is sticky until changed and loses to group-title', () {
      final entries = entriesOf(
        '#EXTGRP:First\n#EXTINF:-1,A\nhttp://example.com/a\n'
        '#EXTINF:-1,B\nhttp://example.com/b\n'
        '#EXTINF:-1 group-title="Own",C\nhttp://example.com/c\n'
        '#EXTGRP:Second\n#EXTINF:-1,D\nhttp://example.com/d\n',
      );
      expect(entries.map((e) => e.groups.single), [
        'First',
        'First',
        'Own',
        'Second',
      ]);
    });
  });

  group('names', () {
    test('title, then tvg-name, then last path segment', () {
      final entries = entriesOf(
        '#EXTINF:-1 tvg-name="Tvg",Title\nhttp://example.com/a/one.ts\n'
        '#EXTINF:-1 tvg-name="Tvg Name",\nhttp://example.com/a/two.ts\n'
        '#EXTINF:-1,\nhttp://example.com/a/My%20Show.ts?x=1\n'
        'http://example.com/plain/last/\n',
      );
      expect(entries.map((e) => e.name), [
        'Title',
        'Tvg Name',
        'My Show.ts',
        'last',
      ]);
    });

    test('URL without path falls back to the URL', () {
      expect(entriesOf('udp://@239.0.0.1:1234\n').single.name, isNotEmpty);
      expect(
        entriesOf('http://example.com\n').single.name,
        'http://example.com',
      );
    });
  });

  group('headers', () {
    test('pipe suffix with ! prefix, any case and URL-encoding', () {
      final e = entriesOf(
        '#EXTINF:-1,A\n'
        'http://example.com/a.m3u8|!user-agent=Agent%2F1.0&REFERER=http%3A%2F%2Fr.example.com%2F\n',
      ).single;
      expect(e.url, 'http://example.com/a.m3u8');
      expect(e.headers, {
        'User-Agent': 'Agent/1.0',
        'Referer': 'http://r.example.com/',
      });
    });

    test('#EXTINF attribute forms', () {
      final e = entriesOf(
        '#EXTINF:-1 user-agent="UA" http-referrer="http://r.example.com/",A\n'
        'http://example.com/a\n'
        '#EXTINF:-1 http-user-agent="UA2" http-referer="http://r2.example.com/",B\n'
        'http://example.com/b\n',
      );
      expect(e[0].headers, {
        'User-Agent': 'UA',
        'Referer': 'http://r.example.com/',
      });
      expect(e[1].headers, {
        'User-Agent': 'UA2',
        'Referer': 'http://r2.example.com/',
      });
    });

    test('options apply to one entry only', () {
      final entries = entriesOf(
        '#EXTINF:-1,A\n#EXTVLCOPT:http-user-agent=VLC\n'
        '#EXTHTTP:{"Referer":"http://r.example.com/"}\n'
        '#KODIPROP:inputstream.adaptive.manifest_type=hls\n'
        'http://example.com/a\n'
        '#EXTINF:-1,B\nhttp://example.com/b\n',
      );
      expect(entries[0].headers, {
        'User-Agent': 'VLC',
        'Referer': 'http://r.example.com/',
      });
      expect(entries[0].kodiProps, ['inputstream.adaptive.manifest_type=hls']);
      expect(entries[1].headers, isEmpty);
      expect(entries[1].kodiProps, isEmpty);
    });

    test('blank values never override earlier ones', () {
      final e = entriesOf(
        '#EXTINF:-1 http-user-agent="AttrUA",A\n'
        '#EXTVLCOPT:http-referrer=http://r.example.com/\n'
        '#EXTHTTP:{"User-Agent":"","Referer":" "}\n'
        'http://example.com/a|User-Agent=&Referer=\n',
      ).single;
      expect(e.headers, {
        'User-Agent': 'AttrUA',
        'Referer': 'http://r.example.com/',
      });
      final blank = entriesOf(
        '#EXTINF:-1,A\n#EXTHTTP:{"User-Agent":""}\n'
        '#KODIPROP:inputstream.adaptive.stream_headers=User-Agent=\n'
        'http://example.com/a|User-Agent=\n',
      ).single;
      expect(blank.headers, isEmpty);
    });

    test('malformed #EXTHTTP JSON is ignored', () {
      final e = entriesOf(
        '#EXTINF:-1,A\n#EXTHTTP:{not json\nhttp://example.com/a\n',
      ).single;
      expect(e.headers, isEmpty);
    });
  });

  group('item keys', () {
    test('non-finite and overflowing numbers become null or defaults', () {
      final records = parseM3uString(
        '#EXTM3U catchup-days="NaN" tvg-shift="1e308"\n'
        '#EXTINF:-1 tvg-chno="NaN" catchup-days="Infinity",A\nhttp://h/a\n'
        '#EXTINF:-1 tvg-chno="1e999" tvg-shift="Infinity",B\nhttp://h/b\n'
        '#EXTINF:-1 tvg-chno="-Infinity" tvg-rec="1e400",C\nhttp://h/c\n'
        '#EXTINF:-1 tvg-chno="99999999999999999999999",D\nhttp://h/d\n'
        '#EXTINF:-1 tvg-chno="4294967296" catchup-days="3.6",E\nhttp://h/e\n'
        '#EXTINF:-1 tvg-chno="1e3" tvg-shift="-1e300",F\nhttp://h/f\n'
        '#EXTINF:-1 tvg-chno="-9223372036854775808",G\nhttp://h/g\n',
      ).toList();
      final header = records.whereType<M3uHeader>().single;
      expect(header.catchupDays, 0);
      expect(header.tvgShiftMin, 0);
      final e = records.whereType<M3uEntry>().toList();
      expect(e.map((x) => x.chno), [null, null, null, null, null, 1000, null]);
      expect(e.map((x) => x.catchupDays), [0, 0, 0, 0, 4, 0, 0]);
      expect(e.map((x) => x.tvgShiftMin).toSet(), {0});
    });

    test('chno, radio, ids', () {
      final entries = entriesOf(
        '#EXTINF:-1 tvg-id="id1" tvg-chno="5" radio="true",A\nhttp://example.com/a\n'
        '#EXTINF:-1 ch-number="9" radio="false",B\nhttp://example.com/b\n'
        '#EXTINF:-1 tvg-chno="x",C\nhttp://example.com/c\n',
      );
      expect(entries[0].tvgId, 'id1');
      expect(entries[0].chno, 5);
      expect(entries[0].isRadio, isTrue);
      expect(entries[1].chno, 9);
      expect(entries[1].isRadio, isFalse);
      expect(entries[2].chno, isNull);
      expect(entries[2].tvgId, isNull);
    });
  });

  test('quirks fixture end to end', () {
    final records = parseM3uString(fixture('quirks.m3u')).toList();
    final header = records.whereType<M3uHeader>().single;
    expect(header.epgUrls, [
      'http://epg.example.com/a.xml',
      'http://epg.example.com/b.xml',
    ]);
    final e = records.whereType<M3uEntry>().toList();
    expect(e, hasLength(8));

    expect(e[0].tvgId, 'Quoted.One');
    expect(e[0].tvgName, 'Single Quoted');
    expect(e[0].logo, 'http://img.example.com/q1.png');
    expect(e[0].groups, ['A, B and C']);
    expect(e[0].name, 'Title, with, commas');
    expect(e[0].catchup, 'default');
    expect(e[0].catchupDays, 3);

    expect(e[1].url, 'http://127.0.0.1:8080/live/hdr1.m3u8');
    expect(e[1].headers, {
      'User-Agent': 'PipeUA/4.0',
      'Referer': 'http://vlc.example.com/',
      'Cookie': 'session=synthetic',
      'X-Custom': 'yes',
    });
    expect(e[1].kodiProps, hasLength(1));

    expect(e[2].groups, ['Sticky Group']);
    expect(e[2].headers, isEmpty);
    expect(e[3].groups, ['Sticky Group']);
    expect(e[4].groups, ['Own']);
    expect(e[5].groups, ['Sticky Group']);
    expect(e[5].tvgShiftMin, -150);
    expect(e[5].catchupDays, 7);
    expect(e[5].chno, 7);
    expect(e[6].name, 'Named By Tvg');
    expect(e[6].chno, 12);
    expect(e[6].groups, ['Next Group']);
    expect(e[7].name, 'Bare Url Channel.ts');
    expect(e[7].groups, ['Next Group']);
  });

  test('header precedence: kodi < attribute < vlcopt < exthttp < pipe', () {
    String ua(String lines) => entriesOf(lines).single.headers['User-Agent']!;
    const kodi = '#KODIPROP:inputstream.adaptive.stream_headers=User-Agent=K\n';
    expect(ua('$kodi#EXTINF:-1,A\nhttp://example.com/a\n'), 'K');
    expect(
      ua('$kodi#EXTINF:-1 http-user-agent="A",A\nhttp://example.com/a\n'),
      'A',
    );
    expect(
      ua(
        '$kodi#EXTINF:-1 http-user-agent="A",A\n'
        '#EXTVLCOPT:http-user-agent=V\nhttp://example.com/a\n',
      ),
      'V',
    );
    expect(
      ua(
        '#EXTINF:-1 http-user-agent="A",A\n#EXTVLCOPT:http-user-agent=V\n'
        '#EXTHTTP:{"user-agent":"H"}\nhttp://example.com/a\n',
      ),
      'H',
    );
    expect(
      ua(
        '#EXTINF:-1,A\n#EXTHTTP:{"User-Agent":"H"}\n'
        'http://example.com/a|User-Agent=P\n',
      ),
      'P',
    );
  });

  group('sawMarker', () {
    bool marker(String text) {
      final parser = M3uParser();
      for (final line in const LineSplitter().convert(text)) {
        parser.addLine(line);
      }
      return parser.sawMarker;
    }

    test('set by #EXTM3U or #EXTINF', () {
      expect(marker('#EXTM3U\n'), isTrue);
      expect(marker('\uFEFF#extm3u'), isTrue);
      expect(marker('http://h/a\n#EXTINF:-1,A\nhttp://h/b\n'), isTrue);
    });

    test('not set by HTML, JSON, plain URLs or other tags', () {
      expect(marker(''), isFalse);
      expect(
        marker('<!DOCTYPE html>\n<html><body>Expired</body></html>'),
        isFalse,
      );
      expect(marker('{"user_info":{"auth":0}}'), isFalse);
      expect(marker('http://h/a.ts\n#EXTVLCOPT:x=1\n#EXTINFO\n'), isFalse);
    });

    test('parseM3uChunks reports it through the given parser', () async {
      final parser = M3uParser();
      await parseM3uChunks(
        Stream.value(utf8.encode('#EXTINF:-1,A\nhttp://h/a\n')),
        parser: parser,
      ).drain<void>();
      expect(parser.sawMarker, isTrue);
    });
  });

  group('looksLikeM3u', () {
    test('accepts header or EXTINF', () {
      expect(looksLikeM3u('#EXTM3U\n'), isTrue);
      expect(looksLikeM3u('\uFEFF  \n#extm3u x-tvg-url=""'), isTrue);
      expect(looksLikeM3u('# comment\n#EXTINF:-1,A\nhttp://x\n'), isTrue);
    });

    test('rejects HTML, JSON and empty input', () {
      expect(looksLikeM3u('<!DOCTYPE html><html></html>'), isFalse);
      expect(looksLikeM3u('{"user_info":{}}'), isFalse);
      expect(looksLikeM3u(''), isFalse);
      expect(looksLikeM3u('http://example.com/a.ts\n'), isFalse);
    });
  });
}
