import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/epg/epg_matcher.dart';
import 'package:iptv_player/epg/epg_models.dart';
import 'package:iptv_player/epg/xmltv_parser.dart';

typedef Parsed = ({
  List<EpgChannel> channels,
  List<EpgProgramme> programmes,
  List<XmltvBatch> batches,
});

Stream<List<int>> chunked(List<int> bytes, int size) async* {
  for (var i = 0; i < bytes.length; i += size) {
    yield bytes.sublist(i, min(i + size, bytes.length));
  }
}

Future<Parsed> parseBytes(
  List<int> bytes, {
  int chunk = 1 << 16,
  Set<String>? wanted,
  DateTime? from,
  DateTime? to,
  int batchSize = 5000,
  int Function(String channelId)? shift,
  int offset = 0,
  List<String> langs = const ['ar', 'en'],
}) async {
  final batches = await const XmltvParser()
      .parse(
        chunked(bytes, chunk),
        wantedChannelIds: wanted,
        windowStart: from,
        windowEnd: to,
        batchSize: batchSize,
        shiftMinutesFor: shift,
        offsetMinutes: offset,
        preferredLangs: langs,
      )
      .toList();
  return (
    channels: [for (final b in batches) ...b.channels],
    programmes: [for (final b in batches) ...b.programmes],
    batches: batches,
  );
}

Future<Parsed> parse(
  String xml, {
  int chunk = 1 << 16,
  Set<String>? wanted,
  DateTime? from,
  DateTime? to,
  int batchSize = 5000,
  int Function(String channelId)? shift,
  int offset = 0,
  List<String> langs = const ['ar', 'en'],
}) => parseBytes(
  utf8.encode(xml),
  chunk: chunk,
  wanted: wanted,
  from: from,
  to: to,
  batchSize: batchSize,
  shift: shift,
  offset: offset,
  langs: langs,
);

/// Wraps programme elements in a minimal document.
String tv(String body) => '<?xml version="1.0"?>\n<tv>\n$body\n</tv>\n';

/// A programme on [channel] from [start] to [stop] (XMLTV text, UTC if bare).
String prog(String channel, String start, [String? stop, String inner = '']) {
  final stopAttr = stop == null ? '' : ' stop="$stop"';
  return '<programme start="$start"$stopAttr channel="$channel">'
      '<title>$channel $start</title>$inner</programme>';
}

DateTime utc(int d, int h, [int m = 0]) => DateTime.utc(2026, 10, d, h, m);

String describe(EpgProgramme p) =>
    '${p.channelId}|${p.start.toIso8601String()}|${p.stop.toIso8601String()}|'
    '${p.title}|${p.subTitle}|${p.desc}|${p.category}|${p.icon}';

String describeChannel(EpgChannel c) =>
    '${c.id}|${c.displayNames.join(',')}|${c.icon}';

void main() {
  late List<int> fixture;

  setUpAll(() {
    fixture = File('test/fixtures/epg/guide.xml').readAsBytesSync();
  });

  group('fixture guide', () {
    test('channels with all display names and icon', () async {
      final r = await parseBytes(fixture);
      expect(r.channels.map((c) => c.id), [
        'news.example',
        'Sport.Example',
        'kids.example',
      ]);
      final news = r.channels.first;
      expect(news.displayNames, ['قناة الأخبار', 'Example News HD']);
      expect(news.icon, 'http://example.com/logos/news.png');
      expect(r.channels[1].icon, 'http://example.com/logos/sport.png');
      expect(r.channels[2].displayNames, ['Kids & Family']);
      expect(r.channels[2].icon, isNull);
    });

    test('programmes with fields, nested tags and missing stops', () async {
      final r = await parseBytes(fixture);
      expect(r.programmes.map((p) => p.title), [
        'نشرة المساء',
        'حوار <خاص> & مباشر',
        'Match Day',
        'Post-match & Analysis ا',
        '',
        'Cartoons',
      ]);

      final bulletin = r.programmes[0];
      expect(bulletin.channelId, 'news.example');
      expect(bulletin.start, utc(14, 15));
      expect(bulletin.stop, utc(14, 16));
      expect(bulletin.start.isUtc, isTrue);
      expect(bulletin.subTitle, 'Headlines');
      expect(bulletin.desc, 'أهم الأخبار والطقس.');
      expect(bulletin.category, 'أخبار');
      // The rating icon nested deeper is not the programme icon.
      expect(bulletin.icon, 'http://example.com/img/bulletin.jpg');

      final talk = r.programmes[1];
      expect(talk.desc, 'جزء أول فقط');
      expect(talk.subTitle, isNull);
      expect(talk.icon, isNull);

      final matchDay = r.programmes[2];
      // Written `sport.example`, reported with the `<channel id>` spelling.
      expect(matchDay.channelId, 'Sport.Example');
      expect(matchDay.start, utc(14, 16));
      expect(matchDay.stop, utc(14, 17, 30), reason: 'next start');

      final selfClosing = r.programmes[4];
      expect(selfClosing.channelId, 'unknown.example');
      expect(selfClosing.start, utc(14, 18, 30));
      expect(selfClosing.stop, utc(14, 19, 30));

      final cartoons = r.programmes[5];
      expect(cartoons.start, utc(14, 13));
      expect(cartoons.stop, utc(14, 14), reason: 'start + 1 h');
    });

    test('English preference picks English values', () async {
      final r = await parseBytes(fixture, langs: ['en']);
      final bulletin = r.programmes.first;
      expect(bulletin.title, 'Evening Bulletin');
      expect(bulletin.desc, 'Top stories & weather.');
      expect(bulletin.category, 'News');
    });

    test('unknown preference falls back to the first value', () async {
      final r = await parseBytes(fixture, langs: ['fr']);
      expect(r.programmes.first.title, 'Evening Bulletin');
      final none = await parseBytes(fixture, langs: const []);
      expect(none.programmes.first.title, 'Evening Bulletin');
    });

    test('any chunking gives the same result', () async {
      final whole = await parseBytes(fixture, chunk: fixture.length);
      final expected = (
        whole.channels.map(describeChannel).toList(),
        whole.programmes.map(describe).toList(),
      );
      for (final size in [1, 2, 3, 5, 13, 64, 1000]) {
        final r = await parseBytes(fixture, chunk: size);
        expect(r.channels.map(describeChannel).toList(), expected.$1);
        expect(r.programmes.map(describe).toList(), expected.$2);
      }
    });

    test('gzip input gives the same result', () async {
      final plain = await parseBytes(fixture);
      final gz = await parseBytes(gzip.encode(fixture), chunk: 1);
      expect(
        gz.programmes.map(describe).toList(),
        plain.programmes.map(describe).toList(),
      );
      expect(gz.channels, hasLength(plain.channels.length));
    });
  });

  group('language preference', () {
    String withTitles(String titles) => tv(
      '<programme start="20261014120000" stop="20261014130000" channel="c">'
      '$titles</programme>',
    );

    test('Arabic wins over English by default regardless of order', () async {
      final r = await parse(
        withTitles(
          '<title lang="en">Hello</title><title lang="ar">مرحبا</title>',
        ),
      );
      expect(r.programmes.single.title, 'مرحبا');
    });

    test('order of preferredLangs decides', () async {
      final xml = withTitles(
        '<title lang="ar">مرحبا</title><title lang="en">Hello</title>',
      );
      expect(
        (await parse(xml, langs: ['en', 'ar'])).programmes.single.title,
        'Hello',
      );
      expect(
        (await parse(xml, langs: ['ar', 'en'])).programmes.single.title,
        'مرحبا',
      );
    });

    test('region subtags and case match the primary language', () async {
      final r = await parse(
        withTitles(
          '<title lang="en-GB">Colour</title><title lang="AR_sa">لون</title>',
        ),
      );
      expect(r.programmes.single.title, 'لون');
      final en = await parse(
        withTitles(
          '<title lang="fr">Couleur</title><title lang="EN-us">Color</title>',
        ),
        langs: ['en'],
      );
      expect(en.programmes.single.title, 'Color');
    });

    test('values without lang count as unpreferred', () async {
      final r = await parse(
        withTitles('<title>Plain</title><title lang="en">English</title>'),
      );
      expect(r.programmes.single.title, 'English');
      final first = await parse(
        withTitles('<title>Plain</title><title lang="fr">Français</title>'),
      );
      expect(first.programmes.single.title, 'Plain');
    });

    test('empty preferred value does not hide a later one', () async {
      final r = await parse(
        withTitles(
          '<title lang="ar">  </title><title lang="en">English</title>'
          '<title lang="ar">عربي</title>',
        ),
      );
      expect(r.programmes.single.title, 'عربي');
    });
  });

  group('text decoding', () {
    Future<EpgProgramme> one(String inner, {int chunk = 1 << 16}) async {
      final r = await parse(
        tv(
          '<programme start="20261014120000" stop="20261014130000" '
          'channel="c">$inner</programme>',
        ),
        chunk: chunk,
      );
      return r.programmes.single;
    }

    test('entities, numeric references and CDATA', () async {
      final p = await one(
        '<title>A &amp; B &lt;C&gt; &#x41;&#66; &quot;q&quot; &apos;s</title>'
        '<desc><![CDATA[Tom & Jerry <Live> &amp;]]></desc>'
        '<sub-title>x <![CDATA[<y>]]> &amp; z</sub-title>',
      );
      expect(p.title, 'A & B <C> AB "q" \'s');
      expect(p.desc, 'Tom & Jerry <Live> &amp;');
      expect(p.subTitle, 'x <y> & z');
    });

    test('entities split across chunks', () async {
      for (final chunk in [1, 2, 3, 4]) {
        final p = await one(
          '<title>Fish &amp; Chips &#1575;&#x644;</title>',
          chunk: chunk,
        );
        expect(p.title, 'Fish & Chips ال', reason: 'chunk $chunk');
      }
    });

    test('HTML entities and stray ampersands are tolerated', () async {
      final p = await one('<title>Q&amp;A&nbsp;Live & more &unknown;</title>');
      expect(p.title, 'Q&A\u00a0Live & more &unknown;');
    });

    test('a stray < in text is kept as text', () async {
      final p = await one(
        '<title>1 < 2 and 3 <4</title><desc>a <b c</desc>'
        '<sub-title><![CDATA[x < y <z w]]></sub-title>'
        '<category>if x<y and <z> then</category>',
      );
      expect(p.title, '1 < 2 and 3 <4');
      expect(p.desc, 'a <b c');
      expect(p.subTitle, 'x < y <z w');
      // `<z>` is a well-formed (unknown) tag, so only its text remains.
      expect(p.category, 'if x<y and  then');
    });

    test(
      'whitespace is trimmed and multi-byte text survives 1-byte chunks',
      () async {
        final p = await one(
          '<title>\n   العربية   \n</title><desc>  😀 emoji  </desc>',
          chunk: 1,
        );
        expect(p.title, 'العربية');
        expect(p.desc, '😀 emoji');
      },
    );

    test('attribute entities are decoded', () async {
      final r = await parse(
        tv(
          '<channel id="a&amp;b"><display-name>A&amp;B</display-name>'
          '<icon src="http://example.com/l.png?a=1&amp;b=2"/></channel>'
          '<programme start="20261014120000" stop="20261014130000" '
          'channel="a&amp;b"><title>t</title></programme>',
        ),
      );
      expect(r.channels.single.id, 'a&b');
      expect(r.channels.single.displayNames, ['A&B']);
      expect(r.channels.single.icon, 'http://example.com/l.png?a=1&b=2');
      expect(r.programmes.single.channelId, 'a&b');
    });

    test('invalid UTF-8 is replaced, not fatal', () async {
      final head = utf8.encode(tv('<channel id="c"><display-name>X'));
      final bytes = [
        ...head.sublist(0, head.length - '\n</tv>\n'.length),
        0xff,
        0xfe,
        ...utf8.encode('Y</display-name></channel></tv>'),
      ];
      final r = await parseBytes(bytes);
      expect(r.channels.single.displayNames.single, 'X\ufffd\ufffdY');
    });
  });

  group('structure tolerance', () {
    test('comments, processing instructions and unknown elements', () async {
      final r = await parse(
        tv(
          '<?xml-stylesheet href="x.xsl"?>'
          '<!-- <programme start="20261014000000" channel="c"/> -->'
          '<extra><programme-like>no</programme-like></extra>'
          '<programme start="20261014120000" stop="20261014130000" channel="c">'
          '<title>Real</title>'
          '<video><present>yes</present><quality>HDTV</quality></video>'
          '<credits><title>Not the title</title></credits>'
          '<star-rating><value>3/5</value><icon src="http://example.com/s.png"/></star-rating>'
          '<desc>One</desc>'
          '</programme>',
        ),
      );
      final p = r.programmes.single;
      expect(p.title, 'Real');
      expect(p.desc, 'One');
      expect(p.icon, isNull);
    });

    test('an unclosed programme is finished by the next one', () async {
      final r = await parse(
        tv(
          '<programme start="20261014120000" stop="20261014130000" channel="c">'
          '<title>First</title>'
          '<programme start="20261014130000" stop="20261014140000" channel="c">'
          '<title>Second</title></programme>'
          '<programme start="20261014140000" stop="20261014150000" channel="c">'
          '<title>Third</title></programme>',
        ),
      );
      expect(r.programmes.map((p) => p.title), ['First', 'Second', 'Third']);
    });

    test('an unclosed tag inside a field does not swallow the rest', () async {
      final r = await parse(
        tv(
          '<programme start="20261014120000" stop="20261014130000" channel="c">'
          '<desc>Bold <b>text</desc><title>T1</title></programme>'
          '<programme start="20261014130000" stop="20261014140000" channel="c">'
          '<title>T2</title></programme>',
        ),
      );
      expect(r.programmes.map((p) => p.title), ['T1', 'T2']);
      expect(r.programmes.first.desc, 'Bold text');
    });

    test('stray end tags do not end a field or programme early', () async {
      final r = await parse(
        tv(
          '<channel id="c"></b><display-name>C</display-name></i></channel>'
          '<programme start="20261014120000" stop="20261014130000" channel="c">'
          '<title>T</title></foo><desc>a</i> b</desc></bar>'
          '<icon src="http://example.com/i.png"/></programme>'
          '${prog('c', '20261014130000', '20261014140000')}',
        ),
      );
      expect(r.channels.single.displayNames, ['C']);
      expect(r.programmes, hasLength(2));
      final p = r.programmes.first;
      expect(
        (p.title, p.desc, p.icon),
        ('T', 'a b', 'http://example.com/i.png'),
      );
    });

    test('same-name nested element ends the field at its own end tag', () async {
      final r = await parse(
        tv(
          '<programme start="20261014120000" stop="20261014130000" channel="c">'
          '<desc>outer <desc>inner</desc> tail</desc><title>T</title>'
          '</programme>',
        ),
      );
      final p = r.programmes.single;
      expect(p.desc, 'outer inner');
      expect(p.title, 'T');
    });

    test('channels and programmes without a root element', () async {
      final r = await parse(
        '<channel id="c"><display-name>C</display-name></channel>'
        '${prog('c', '20261014120000', '20261014130000')}',
      );
      expect(r.channels, hasLength(1));
      expect(r.programmes, hasLength(1));
    });

    test('unusable programmes are skipped', () async {
      final r = await parse(
        tv(
          '<programme start="20261014120000" stop="20261014130000"><title>no channel</title></programme>'
          '<programme start="" stop="20261014130000" channel="c"><title>empty start</title></programme>'
          '<programme stop="20261014130000" channel="c"><title>no start</title></programme>'
          '<programme start="2026-10-14 12:00" channel="c"><title>bad start</title></programme>'
          '<programme start="20261014120000" stop="20261014130000" channel="  "><title>blank</title></programme>'
          '<channel><display-name>no id</display-name></channel>'
          '<channel id=" "/>'
          '${prog('ok', '20261014120000', '20261014130000')}',
        ),
      );
      expect(r.channels, isEmpty);
      expect(r.programmes.map((p) => p.channelId), ['ok']);
    });

    test('a document cut off mid-element keeps what was complete', () async {
      final full = tv(
        '<channel id="c"><display-name>C</display-name></channel>'
        '${prog('c', '20261014120000', '20261014130000')}'
        '${prog('c', '20261014130000', '20261014140000')}',
      );
      final cut = full.substring(0, full.indexOf('20261014140000') + 4);
      final r = await parse(cut, chunk: 7);
      expect(r.channels, hasLength(1));
      expect(r.programmes, hasLength(1));
    });

    test('markup that never completes recovers after a long carry', () async {
      // An unterminated comment could still end in a later chunk, so it is
      // carried; once the carry exceeds its limit the `<` is treated as text
      // and parsing resumes, ending the programme at its own end tag.
      final body = StringBuffer(
        '<programme start="20261014000000" stop="20261014003000" channel="c">'
        '<title>a <!-- b</title></programme>',
      );
      for (var i = 0; i < 6000; i++) {
        final start = utc(14, 1).add(Duration(minutes: i));
        String ts(DateTime t) =>
            '${t.year}${_two(t.month)}${_two(t.day)}${_two(t.hour)}${_two(t.minute)}00';
        body.write(
          '<programme start="${ts(start)}" '
          'stop="${ts(start.add(const Duration(minutes: 1)))}" channel="c">'
          '<title>Show $i</title><desc>${'x' * 150}</desc></programme>\n',
        );
      }
      final bytes = utf8.encode(tv(body.toString()));
      expect(bytes.length, greaterThan(1 << 20));

      var inputDone = false;
      Stream<List<int>> input() async* {
        yield* chunked(bytes, 1 << 14);
        inputDone = true;
      }

      final programmes = <EpgProgramme>[];
      var beforeEnd = 0;
      await for (final b in const XmltvParser().parse(
        input(),
        batchSize: 500,
      )) {
        programmes.addAll(b.programmes);
        if (!inputDone) beforeEnd += b.programmes.length;
      }
      // Recovery happened mid-stream, not only when the input ended.
      expect(beforeEnd, greaterThan(5000));
      expect(programmes, hasLength(6001));
      expect(programmes.first.title, 'a <!-- b');
      expect(programmes[1].title, 'Show 0');
      expect(programmes.last.title, 'Show 5999');
    });

    test('empty input yields nothing', () async {
      expect((await parse('')).batches, isEmpty);
      expect((await parse('<tv></tv>')).batches, isEmpty);
    });

    test('invalid batchSize is rejected', () {
      expect(
        () => const XmltvParser().parse(const Stream.empty(), batchSize: 0),
        throwsArgumentError,
      );
    });
  });

  group('missing stop', () {
    test('uses the next start of the same channel, interleaved', () async {
      final r = await parse(
        tv(
          prog('a', '20261014120000') +
              prog('b', '20261014121500') +
              prog('a', '20261014124500', '20261014130000') +
              prog('b', '20261014140000'),
        ),
      );
      final byTitle = {for (final p in r.programmes) p.title: p};
      expect(byTitle['a 20261014120000']!.stop, utc(14, 12, 45));
      expect(byTitle['b 20261014121500']!.stop, utc(14, 14));
      expect(byTitle['b 20261014140000']!.stop, utc(14, 15), reason: 'last');
    });

    test('a next start that is not later falls back to one hour', () async {
      final r = await parse(
        tv(
          prog('a', '20261014120000') +
              prog('a', '20261014120000', '20261014123000') +
              prog('a', '20261014150000') +
              prog('a', '20261014100000', '20261014110000'),
        ),
      );
      expect(r.programmes.map((p) => (p.start, p.stop)), [
        (utc(14, 12), utc(14, 13)),
        (utc(14, 12), utc(14, 12, 30)),
        (utc(14, 15), utc(14, 16)),
        (utc(14, 10), utc(14, 11)),
      ]);
    });

    test('stop not after start is treated as missing', () async {
      final r = await parse(
        tv(
          prog('a', '20261014120000', '20261014110000') +
              prog('a', '20261014123000', '20261014123000') +
              prog('a', '20261014124000', 'garbage') +
              prog('a', '20261014125000', '20261014130000'),
        ),
      );
      expect(r.programmes.map((p) => p.stop), [
        utc(14, 12, 30),
        utc(14, 12, 40),
        utc(14, 12, 50),
        utc(14, 13),
      ]);
    });

    test(
      'next start from a programme outside the window still resolves',
      () async {
        final r = await parse(
          tv(
            prog('a', '20261014100000') +
                prog('a', '20261014200000', '20261014210000'),
          ),
          from: utc(14, 9),
          to: utc(14, 12),
        );
        expect(r.programmes.single.stop, utc(14, 20));
      },
    );

    test('resolved stop decides the window', () async {
      final r = await parse(
        tv(
          prog('a', '20261014060000') +
              prog('a', '20261014070000') +
              prog('a', '20261014120000', '20261014130000'),
        ),
        from: utc(14, 8),
      );
      // 06:00-07:00 ends before the window; 07:00-12:00 overlaps it.
      expect(r.programmes.map((p) => p.start), [utc(14, 7), utc(14, 12)]);
    });
  });

  group('window', () {
    final xml = tv(
      prog('c', '20261014080000', '20261014090000') + // ends at from
          prog('c', '20261014083000', '20261014093000') + // overlaps from
          prog('c', '20261014100000', '20261014110000') + // inside
          prog('c', '20261014170000', '20261014190000') + // overlaps to
          prog('c', '20261014180000', '20261014190000') + // starts at to
          prog('c', '20261020000000', '20261020010000') + // far future
          prog('c', '20261001000000', '20261001010000'), // far past
    );

    test('keeps programmes overlapping the window', () async {
      final r = await parse(xml, from: utc(14, 9), to: utc(14, 18));
      expect(r.programmes.map((p) => p.start), [
        utc(14, 8, 30),
        utc(14, 10),
        utc(14, 17),
      ]);
    });

    test('open-ended bounds', () async {
      expect((await parse(xml)).programmes, hasLength(7));
      expect((await parse(xml, from: utc(14, 9))).programmes, hasLength(5));
      expect((await parse(xml, to: utc(14, 9))).programmes, hasLength(3));
    });

    test(
      'a missing-stop programme starting after the window is dropped',
      () async {
        final r = await parse(
          tv(prog('c', '20261015000000') + prog('c', '20261014100000')),
          from: utc(14, 9),
          to: utc(14, 18),
        );
        expect(r.programmes.map((p) => p.start), [utc(14, 10)]);
      },
    );
  });

  group('wanted channel ids', () {
    test('filter programmes case-insensitively, keep all channels', () async {
      final r = await parseBytes(
        fixture,
        wanted: {'NEWS.EXAMPLE', ' Sport.Example '},
      );
      expect(r.channels, hasLength(3));
      expect(r.programmes.map((p) => p.channelId).toSet(), {
        'news.example',
        'Sport.Example',
      });
      expect(r.programmes, hasLength(4));
    });

    test('an empty set keeps no programmes', () async {
      final r = await parseBytes(fixture, wanted: {});
      expect(r.channels, hasLength(3));
      expect(r.programmes, isEmpty);
    });
  });

  group('shift and offset', () {
    final xml = tv(
      prog('a', '20261014120000 +0300', '20261014130000 +0300') +
          prog('B', '20261014120000', '20261014130000') +
          prog('c', '20261014120000') +
          prog('c', '20261014130000', '20261014140000'),
    );

    test('per-channel shift then global offset', () async {
      final calls = <String>[];
      final r = await parse(
        xml,
        shift: (id) {
          calls.add(id);
          return switch (id) {
            'a' => 60,
            'B' => -120,
            _ => 0,
          };
        },
        offset: 30,
      );
      expect(r.programmes.map((p) => (p.channelId, p.start, p.stop)), [
        ('a', utc(14, 10, 30), utc(14, 11, 30)),
        ('B', utc(14, 10, 30), utc(14, 11, 30)),
        ('c', utc(14, 12, 30), utc(14, 13, 30)),
        ('c', utc(14, 13, 30), utc(14, 14, 30)),
      ]);
      expect(calls, ['a', 'B', 'c'], reason: 'one call per channel');
    });

    test('offset alone and window after shifting', () async {
      final r = await parse(
        xml,
        offset: -60,
        from: utc(14, 12),
        to: utc(14, 13),
      );
      // Shifted to 11:00-12:00 (outside) except c 12:00-13:00.
      expect(r.programmes.map((p) => (p.channelId, p.start)), [
        ('c', utc(14, 12)),
      ]);
    });

    test('shift is not asked for unwanted channels', () async {
      final calls = <String>[];
      await parse(
        xml,
        wanted: {'b'},
        shift: (id) {
          calls.add(id);
          return 0;
        },
      );
      expect(calls, ['B']);
    });
  });

  group('channel id spelling', () {
    test('matched ids find their programmes and shifts (fixture)', () async {
      // The fixture declares `Sport.Example` but its programmes say
      // `sport.example`.
      final shifted = await parseBytes(
        fixture,
        shift: (id) => id == 'Sport.Example' ? 60 : 0,
      );
      final match = matchChannels([
        const MatchCandidate(key: 'k', name: 'x', tvgId: 'sport.example'),
      ], shifted.channels)['k']!;
      expect(match, const EpgMatch('Sport.Example', MatchKind.tvgId));

      final mine = shifted.programmes.where(
        (p) => p.channelId == match.xmltvId,
      );
      expect(mine.map((p) => (p.title, p.start, p.stop)), [
        ('Match Day', utc(14, 17), utc(14, 18, 30)),
        ('Post-match & Analysis ا', utc(14, 18, 30), utc(14, 20)),
      ]);
    });

    test('first spelling wins, also for programmes before channels', () async {
      final calls = <String>[];
      final r = await parse(
        tv(
          '${prog('NEWS', '20261014120000')}'
          '<channel id="News"><display-name>N</display-name></channel>'
          '<channel id="sport"/>'
          '${prog('news', '20261014130000', '20261014140000')}'
          '${prog('Sport', '20261014120000', '20261014130000')}'
          '${prog('SPORT', '20261014130000', '20261014140000')}',
        ),
        shift: (id) {
          calls.add(id);
          return 0;
        },
      );
      expect(r.channels.map((c) => c.id), ['NEWS', 'sport']);
      expect(r.programmes.map((p) => (p.channelId, p.start, p.stop)), [
        // The missing stop resolves across spellings.
        ('NEWS', utc(14, 12), utc(14, 13)),
        ('NEWS', utc(14, 13), utc(14, 14)),
        ('sport', utc(14, 12), utc(14, 13)),
        ('sport', utc(14, 13), utc(14, 14)),
      ]);
      expect(calls, ['NEWS', 'sport'], reason: 'one call per channel');
    });
  });

  group('malformed markup in text', () {
    /// Feeds [parts] one by one and records the programme titles emitted
    /// after each, so held-back output shows up.
    Future<List<List<String>>> titlesAfterEach(List<String> parts) async {
      final input = StreamController<List<int>>();
      final titles = <String>[];
      final done = const XmltvParser()
          .parse(input.stream, batchSize: 1)
          .forEach((b) => titles.addAll(b.programmes.map((p) => p.title)));
      final seen = <List<String>>[];
      for (final part in parts) {
        input.add(utf8.encode(part));
        await pumpEventQueue();
        seen.add([...titles]);
      }
      await input.close();
      await done;
      seen.add(titles);
      return seen;
    }

    String show(String title, String desc) =>
        '<programme start="20261014120000" stop="20261014130000" channel="c">'
        '<title>$title</title><desc>$desc</desc></programme>';

    for (final bad in [
      'Movie <A&E> tonight',
      "<Director's Cut>",
      'wow<!> and <!important>',
      'what<?> now <? x',
      'x <1st> </ desc> <a b="c" d<e>',
      'unterminated <icon src="x.png/>',
    ]) {
      test('does not hold back later output: $bad', () async {
        final seen = await titlesAfterEach([
          '<tv>${show('A', bad)}',
          show('B', 'fine'),
          '</tv>',
        ]);
        expect(seen, [
          ['A'],
          ['A', 'B'],
          ['A', 'B'],
          ['A', 'B'],
        ]);
      });
    }

    test('text is kept as written', () async {
      final r = await parse(
        tv(show('T', "Movie <A&E> tonight, <Director's Cut>, wow<!> <?> <? x")),
        chunk: 7,
      );
      expect(
        r.programmes.single.desc,
        "Movie <A&E> tonight, <Director's Cut>, wow<!> <?> <? x",
      );
    });

    test('`<?` without a target name is text however it is chunked', () async {
      final xml = tv(
        '${show('A', '<?قناة x')}${show('B', 'what <? now')}'
        '${show('C', 'ends ?> here')}',
      );
      for (final chunk in [1, 2, 3, 1 << 16]) {
        final r = await parse(xml, chunk: chunk);
        expect(r.programmes.map((p) => p.desc), [
          '<?قناة x',
          'what <? now',
          'ends ?> here',
        ], reason: 'chunk $chunk');
      }
    });

    test('random malformed text parses the same in any chunking', () async {
      const pieces = [
        // Entities, stray and valid markup, and openers without closers.
        'plain', ' ', '&amp;', '&#1575;', '<', '< ', 'a<b', '<3', '<!',
        '<?', '<?a', '<x>', '</x>', '<y/>', '<![CDATA[c<d]]>', '<!-- c -->',
        '&', '>', '"', "'", 'قناة', '😀', '<b c', '<A&E>', ']]>', '\n',
        '<!-- ', ' -->', '<![CDATA[', '<?php ', '?>', '<!x>', '</ d>',
        "<Director's Cut>", '<!DOC', '<!-', '-->',
      ];
      String describeAll(Parsed r) => [
        ...r.channels.map(describeChannel),
        ...r.programmes.map(describe),
      ].join('\n');

      for (var seed = 0; seed < 150; seed++) {
        final rnd = Random(seed);
        String text() => [
          for (var i = rnd.nextInt(6); i > 0; i--)
            pieces[rnd.nextInt(pieces.length)],
        ].join();
        final body = StringBuffer();
        for (var i = 0; i < 5; i++) {
          if (rnd.nextBool()) {
            body.write(
              '<channel id="ch$i"><display-name>${text()}</display-name>'
              '</channel>',
            );
          }
          final stop = rnd.nextBool() ? ' stop="2026101413${i}000"' : '';
          body.write(
            '<programme start="2026101412${i}000"$stop '
            'channel="${rnd.nextBool() ? 'CH' : 'ch'}${i % 3}">'
            '<title>${text()}</title><desc>${text()}</desc></programme>\n',
          );
        }
        final bytes = utf8.encode(tv(body.toString()));
        final whole = describeAll(await parseBytes(bytes, chunk: bytes.length));
        for (final chunk in [1, 2, 5, 17]) {
          expect(
            describeAll(await parseBytes(bytes, chunk: chunk)),
            whole,
            reason: 'seed $seed, chunk $chunk',
          );
        }
      }
    });

    test('markup cut at a chunk boundary is still carried', () async {
      final long = 'a <b> -- ] ]] ? > ' * 20;
      final xml = tv(
        '<!DOCTYPE tv SYSTEM "xmltv.dtd">'
        '<?xml-stylesheet href="x.xsl"?>'
        '<?pi $long?>'
        '${show('A', '<![CDATA[x <y> z]]> <!-- c --> <b>bold</b>')}'
        '<!-- $long -->'
        '${show('B', '<![CDATA[$long]]>')}'
        '${show('C', 'c')}',
      );
      for (final chunk in [1, 2, 3, 5, 8, 13, 64]) {
        final r = await parse(xml, chunk: chunk);
        expect(r.programmes.map((p) => (p.title, p.desc)), [
          ('A', 'x <y> z  bold'),
          ('B', long.trim()),
          ('C', 'c'),
        ], reason: 'chunk $chunk');
      }
    });
  });

  group('batches', () {
    final xml = tv(
      '<channel id="a"/><channel id="b"/>'
      '${prog('a', '20261014120000', '20261014130000')}'
      '${prog('a', '20261014130000', '20261014140000')}'
      '${prog('b', '20261014120000', '20261014130000')}'
      '${prog('b', '20261014130000', '20261014140000')}'
      '${prog('b', '20261014140000', '20261014150000')}',
    );

    test('are bounded by batchSize and preserve order', () async {
      for (final size in [1, 2, 3, 4, 7, 100]) {
        final r = await parse(xml, batchSize: size, chunk: 5);
        for (final b in r.batches) {
          expect(
            b.channels.length + b.programmes.length,
            inInclusiveRange(1, size),
          );
        }
        final counts = [
          for (final b in r.batches) b.channels.length + b.programmes.length,
        ];
        expect(counts.reduce((a, b) => a + b), 7);
        // Every batch but the last is full.
        expect(counts.take(counts.length - 1).every((n) => n == size), isTrue);
        expect(r.channels.map((c) => c.id), ['a', 'b']);
        expect(r.programmes.map((p) => p.channelId), ['a', 'a', 'b', 'b', 'b']);
      }
    });

    test('size 3 mixes channels and programmes', () async {
      final r = await parse(xml, batchSize: 3);
      expect(r.batches.map((b) => (b.channels.length, b.programmes.length)), [
        (2, 1),
        (0, 3),
        (0, 1),
      ]);
    });

    test('large inputs stream in many batches', () async {
      final body = StringBuffer();
      for (var i = 0; i < 12000; i++) {
        body.write(prog('c${i % 50}', '20261014120000', '20261014130000'));
      }
      final r = await parse(tv(body.toString()), batchSize: 5000);
      expect(r.batches.map((b) => b.programmes.length), [5000, 5000, 2000]);
    });
  });
}

String _two(int v) => v.toString().padLeft(2, '0');
