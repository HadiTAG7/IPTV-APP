import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/secure/secret_store.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/epg/epg_models.dart';
import 'package:iptv_player/sources/models.dart';

import 'db_test_utils.dart';

/// Counts SELECT statements reaching SQLite.
class _SelectCounter extends QueryInterceptor {
  int selects = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects++;
    return super.runSelect(executor, statement, args);
  }
}

DateTime at(int hour, [int minute = 0]) =>
    DateTime.utc(2026, 1, 10, hour, minute);

EpgProgramme prog(
  String id,
  DateTime start,
  DateTime stop,
  String title, {
  String? desc,
}) => EpgProgramme(
  channelId: id,
  start: start,
  stop: stop,
  title: title,
  desc: desc,
);

void main() {
  late _SelectCounter counter;
  late AppDatabase db;
  late EpgDao epg;
  late int src;
  late int guide;

  setUp(() async {
    counter = _SelectCounter();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(
      NativeDatabase.memory().interceptWith(counter),
      clock: FakeClock(testEpoch),
    );
    epg = db.epgDao;
    src = await addSource(db);
    guide = await epg.addEpgSource(
      src,
      'http://127.0.0.1:8080/xmltv.xml',
      EpgOrigin.m3uHeader,
    );
  });

  tearDown(() => db.close());

  EpgLink link(String xmltvId, [EpgMatchKind kind = EpgMatchKind.tvgId]) =>
      (epgSourceId: guide, xmltvId: xmltvId, kind: kind);

  group('guide data', () {
    setUp(() async {
      await epg.insertProgrammes(guide, [
        prog('x.a', at(10), at(11), 'Morning', desc: 'First show'),
        prog('x.a', at(11), at(12), 'Noon'),
        prog('x.a', at(13), at(14), 'Afternoon'),
        prog('x.b', at(9), at(10, 30), 'Early'),
        prog('x.c', at(9, 30), at(11, 30), 'Long'),
        prog('x.c', at(10), at(10, 30), 'Overlap'),
        prog('x.c', at(12), at(13), 'Later'),
      ]);
      await epg.replaceChannelMap(src, {
        'a': link('x.a'),
        'b': link('x.b'),
        'c': link('x.c'),
        'e': link('x.a', EpgMatchKind.name),
      });
    });

    Future<Map<String, (String?, String?)>> titles(DateTime now) async {
      final map = await epg.nowNext(src, ['a', 'b', 'c', 'd', 'e'], now);
      return map.map((k, v) => MapEntry(k, (v.now?.title, v.next?.title)));
    }

    test('now/next at a boundary', () async {
      expect(await titles(at(11)), {
        'a': ('Noon', 'Afternoon'),
        'c': ('Long', 'Later'),
        'e': ('Noon', 'Afternoon'),
      });
    });

    test('now/next in a gap, before, after and with overlaps', () async {
      expect((await titles(at(12, 30)))['a'], (null, 'Afternoon'));
      expect((await titles(at(8)))['a'], (null, 'Morning'));
      expect((await titles(at(8)))['b'], (null, 'Early'));
      expect((await titles(at(14))).containsKey('a'), isFalse);
      expect((await titles(at(13, 59)))['a'], ('Afternoon', null));
      // Overlapping entries: the most recent start is "now".
      expect((await titles(at(10, 15)))['c'], ('Overlap', 'Later'));
      // Next programmes beyond the horizon are ignored.
      expect((await titles(at(10, 15).subtract(const Duration(days: 2)))), {});
    });

    test('now/next maps rows to programmes', () async {
      final nn = (await epg.nowNext(src, ['a'], at(10, 30)))['a']!;
      expect(nn.now?.title, 'Morning');
      expect(nn.now?.desc, 'First show');
      expect(nn.now?.channelId, 'x.a');
      expect(nn.now?.start, at(10));
      expect(nn.now?.stop, at(11));
      expect(nn.now?.isOnAt(at(10, 30)), isTrue);
      expect(nn.next?.title, 'Noon');
    });

    test('now/next is one query for a screen of channels', () async {
      final keys = [
        for (var i = 0; i < 60; i++) 'k$i',
        'a',
        'b',
        'c',
        'a', // duplicates are fine
      ];
      counter.selects = 0;
      final map = await epg.nowNext(src, keys, at(11));
      expect(counter.selects, 1);
      expect(map.keys, unorderedEquals(['a', 'c']));
      expect(await epg.nowNext(src, const [], at(11)), isEmpty);
    });

    test('ignores other sources and disabled guides', () async {
      final other = await addSource(db, name: 'Other');
      final otherGuide = await epg.addEpgSource(
        other,
        'http://127.0.0.1:8080/other.xml',
        EpgOrigin.manual,
      );
      await epg.insertProgrammes(otherGuide, [
        prog('x.a', at(10), at(12), 'Other show'),
      ]);
      await epg.replaceChannelMap(other, {
        'a': (
          epgSourceId: otherGuide,
          xmltvId: 'x.a',
          kind: EpgMatchKind.tvgId,
        ),
      });
      expect((await titles(at(11)))['a'], ('Noon', 'Afternoon'));
      final otherNn = await epg.nowNext(other, ['a'], at(11));
      expect(otherNn['a']?.now?.title, 'Other show');

      await epg.setEpgSourceEnabled(guide, false);
      expect(await titles(at(11)), isEmpty);
      expect(
        await epg.programmesForChannels(src, ['a'], at(0), at(23)),
        isEmpty,
      );
    });

    test('programmes for a window, per channel, ordered', () async {
      final map = await epg.programmesForChannels(
        src,
        ['a', 'b', 'c', 'd'],
        at(10),
        at(12, 30),
      );
      List<String> t(String key) => [for (final p in map[key]!) p.title];
      expect(t('a'), ['Morning', 'Noon']);
      expect(t('b'), ['Early']);
      expect(t('c'), ['Long', 'Overlap', 'Later']);
      expect(map.containsKey('d'), isFalse);
    });

    test('a channel tvg-shift moves its programmes when read', () async {
      // Playlist channels sharing guide id x.a: the original, a "+1" and a
      // channel 30 minutes early. Guide rows are stored unshifted.
      await syncCatalog(
        db,
        src,
        channels: const [
          ChannelData(key: 'a', name: 'News'),
          ChannelData(key: 'p1', name: 'News +1', tvgShiftMin: 60),
          ChannelData(key: 'm30', name: 'News early', tvgShiftMin: -30),
        ],
      );
      await epg.replaceChannelMap(src, {
        'a': link('x.a'),
        'p1': link('x.a', EpgMatchKind.tvgName),
        'm30': link('x.a', EpgMatchKind.name),
      });

      counter.selects = 0;
      final nn = await epg.nowNext(src, ['a', 'p1', 'm30'], at(12, 30));
      expect(counter.selects, 1);
      expect(nn['a']!.now, isNull);
      expect(nn['a']!.next?.start, at(13));
      expect(nn['p1']!.now?.title, 'Noon');
      expect(nn['p1']!.now?.start, at(12));
      expect(nn['p1']!.now?.stop, at(13));
      expect(nn['p1']!.next?.title, 'Afternoon');
      expect(nn['p1']!.next?.start, at(14));
      expect(nn['m30']!.now?.title, 'Afternoon');
      expect(nn['m30']!.now?.start, at(12, 30));
      expect(nn['m30']!.now?.stop, at(13, 30));
      expect(nn['m30']!.next, isNull);
      expect(nn['m30']!.now?.isOnAt(at(12, 30)), isTrue);

      final map = await epg.programmesForChannels(
        src,
        ['a', 'p1', 'm30'],
        at(12),
        at(14),
      );
      List<(String, DateTime, DateTime)> t(String key) => [
        for (final p in map[key]!) (p.title, p.start, p.stop),
      ];
      expect(t('a'), [('Afternoon', at(13), at(14))]);
      expect(t('p1'), [('Noon', at(12), at(13))]);
      expect(t('m30'), [('Afternoon', at(12, 30), at(13, 30))]);
      // Stored rows are unchanged.
      expect(await epg.programmeCount(guide), 7);
      expect((await titles(at(11)))['a'], ('Noon', 'Afternoon'));
    });

    test('same channel and start replaces; prune drops ended rows', () async {
      await epg.insertProgrammes(guide, [
        prog('x.a', at(10), at(11), 'Morning v2'),
      ]);
      expect(await epg.programmeCount(guide), 7);
      final nn = await epg.nowNext(src, ['a'], at(10, 30));
      expect(nn['a']?.now?.title, 'Morning v2');

      expect(await epg.pruneProgrammes(at(11)), 3);
      expect(await epg.programmeCount(guide), 4);
      expect(await epg.deleteProgrammesOf(guide), 4);
      expect(await epg.programmeCount(guide), 0);
    });

    test('per-guide prune, ids and deletes by id', () async {
      final other = await epg.addEpgSource(
        src,
        'http://127.0.0.1:8080/other.xml',
        EpgOrigin.manual,
      );
      await epg.insertProgrammes(other, [prog('X.A', at(9), at(10), 'Other')]);
      expect(await epg.programmeIds(guide), ['x.a', 'x.b', 'x.c']);
      expect(await epg.programmeIds(other), ['X.A']);

      // Only this guide, only rows that ended at or before the time.
      expect(await epg.pruneGuide(guide, at(11)), 3);
      expect(await epg.programmeCount(guide), 4);
      expect(await epg.programmeCount(other), 1);
      expect(await epg.programmeIds(guide), ['x.a', 'x.c']);

      expect(await epg.deleteProgrammesOfIds(guide, ['x.c', 'X.A']), 2);
      expect(await epg.programmeIds(guide), ['x.a']);
      expect(await epg.programmeCount(other), 1);
    });
  });

  group('channel map', () {
    test('manual links win and survive replacement', () async {
      await epg.setManualLink(src, 'b', guide, 'x.manual');
      await epg.replaceChannelMap(src, {
        'a': link('x.a'),
        'b': link('x.b'),
        'c': link('x.c', EpgMatchKind.tvgName),
      });
      final links = await epg.linksFor(src);
      expect(links['a']?.xmltvId, 'x.a');
      expect(links['b']?.xmltvId, 'x.manual');
      expect(links['b']?.kind, EpgMatchKind.manual);
      expect(links['c']?.kind, EpgMatchKind.tvgName);

      await epg.replaceChannelMap(src, {'a': link('x.a2')});
      final after = await epg.linksFor(src);
      expect(after.keys, unorderedEquals(['a', 'b']));
      expect(after['a']?.xmltvId, 'x.a2');
      expect(await epg.linkedXmltvIds(guide), {'x.a2', 'x.manual'});

      await epg.clearLink(src, 'b');
      expect(await epg.linkFor(src, 'b'), isNull);
      await epg.setManualLink(src, 'a', guide, 'x.hand');
      expect((await epg.linkFor(src, 'a'))?.kind, EpgMatchKind.manual);
    });
  });

  group('guide sources', () {
    test('add is idempotent per URL and keeps settings', () async {
      await epg.setEpgSourcePriority(guide, 5);
      final again = await epg.addEpgSource(
        src,
        'http://127.0.0.1:8080/xmltv.xml',
        EpgOrigin.manual,
      );
      expect(again, guide);
      final second = await epg.addEpgSource(
        src,
        'http://127.0.0.1:8080/second.xml.gz',
        EpgOrigin.manual,
        priority: 1,
      );
      final rows = await epg.epgSources(src);
      expect(rows.map((r) => r.id), [second, guide]);
      expect(rows.last.priority, 5);
      expect(rows.last.origin, EpgOrigin.m3uHeader);

      await epg.setEpgSourceEnabled(second, false);
      expect((await epg.epgSources(src, enabledOnly: true)).map((r) => r.id), [
        guide,
      ]);
    });

    test('a guide URL with credentials is stored masked', () async {
      const xmltv =
          'http://127.0.0.1:8080/xmltv.php?username=demo&password=s3cret';
      final id = await epg.addEpgSource(src, xmltv, EpgOrigin.xtream);
      final row = (await epg.epgSourceById(id))!;
      expect(
        row.url,
        'http://127.0.0.1:8080/xmltv.php?username=***&password=***',
      );
      expect(await epg.epgSourceUrl(id), xmltv);
      expect(await epg.epgSourceUrl(guide), 'http://127.0.0.1:8080/xmltv.xml');
      expect(await epg.epgSourceUrl(999), isNull);
      final leaks = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM epg_sources WHERE url LIKE '%s3cret%'",
          )
          .getSingle();
      expect(leaks.read<int>('n'), 0);

      // A changed password updates the same entry.
      const changed =
          'http://127.0.0.1:8080/xmltv.php?username=demo&password=n3w';
      expect(await epg.addEpgSource(src, changed, EpgOrigin.xtream), id);
      expect(await epg.epgSourceUrl(id), changed);
      expect(await countRows(db, 'secrets'), 1);

      await epg.deleteEpgSource(id);
      expect(await countRows(db, 'secrets'), 0);
      expect(await epg.epgSourceUrl(id), isNull);
    });

    test('a given store receives guide credentials', () async {
      final store = InMemorySecretStore();
      const xmltv = 'http://127.0.0.1:8080/xmltv.php?username=u&password=p';
      final id = await epg.addEpgSource(
        src,
        xmltv,
        EpgOrigin.xtream,
        secrets: store,
      );
      expect(await countRows(db, 'secrets'), 0);
      expect(await store.read(src, SecretNames.epgUrl(id)), xmltv);
      expect(await epg.epgSourceUrl(id, store), xmltv);
      await epg.deleteEpgSource(id, secrets: store);
      expect(await store.read(src, SecretNames.epgUrl(id)), isNull);
    });

    test('recordFetch updates only what is given', () async {
      await epg.recordFetch(
        guide,
        etag: '"abc"',
        lastModified: 'Sat, 10 Jan 2026 10:00:00 GMT',
        status: 'ok',
        programmeCount: 10,
      );
      await epg.recordFetch(guide, at: at(15), status: 'not modified');
      final row = (await epg.epgSourceById(guide))!;
      expect(row.etag, '"abc"');
      expect(row.lastModified, 'Sat, 10 Jan 2026 10:00:00 GMT');
      expect(row.status, 'not modified');
      expect(row.programmeCount, 10);
      expect(row.lastFetchAt, at(15));
      expect(await epg.epgSourceById(999), isNull);
    });

    test('forgetGuideVersions clears validators and import time of the '
        "source's guides only", () async {
      final otherSource = await addSource(db, name: 'Other');
      final otherGuide = await epg.addEpgSource(
        otherSource,
        'http://127.0.0.1:8080/other.xml',
        EpgOrigin.manual,
      );
      for (final id in [guide, otherGuide]) {
        await epg.recordFetch(
          id,
          etag: '"v1"',
          lastModified: 'x',
          status: 'ok',
        );
      }

      await epg.forgetGuideVersions(src);

      final row = (await epg.epgSourceById(guide))!;
      expect((row.etag, row.lastModified, row.lastFetchAt), (null, null, null));
      expect(row.status, 'ok');
      final other = (await epg.epgSourceById(otherGuide))!;
      expect(other.etag, '"v1"');
      expect(other.lastFetchAt, isNotNull);
    });

    test('guide channels store normalised names', () async {
      await epg.upsertEpgChannels(guide, const [
        EpgChannel(
          id: 'alj.example',
          displayNames: ['AR: Al Jazeera HD', 'الجزيرة'],
          icon: 'http://example.com/alj.png',
        ),
        EpgChannel(id: 'empty.example'),
      ]);
      await epg.upsertEpgChannels(guide, const [
        EpgChannel(id: 'empty.example', displayNames: ['Empty One']),
      ]);
      final rows = await epg.epgChannels(guide);
      expect(rows.map((r) => r.xmltvId), ['alj.example', 'empty.example']);
      expect(rows.first.displayName, 'AR: Al Jazeera HD');
      expect(rows.first.displayNamesNorm, ['al jazeera', 'الجزيره']);
      expect(rows.first.icon, 'http://example.com/alj.png');
      expect(rows.last.displayNamesNorm, ['empty one']);
    });

    test('deleting a guide removes its data and links', () async {
      await epg.upsertEpgChannels(guide, const [EpgChannel(id: 'x.a')]);
      await epg.insertProgrammes(guide, [prog('x.a', at(10), at(11), 'Show')]);
      await epg.replaceChannelMap(src, {'a': link('x.a')});
      await epg.deleteEpgSource(guide);
      expect(await countRows(db, 'programmes'), 0);
      expect(await countRows(db, 'epg_channels'), 0);
      expect(await countRows(db, 'channel_epg_map'), 0);
      expect(await epg.epgSources(src), isEmpty);
    });

    test('watchEpgSources emits', () async {
      final seen = <int>[];
      final sub = epg.watchEpgSources(src).listen((l) => seen.add(l.length));
      await pumpEventQueue();
      await epg.addEpgSource(src, 'http://127.0.0.1/x.xml', EpgOrigin.manual);
      await pumpEventQueue();
      await sub.cancel();
      expect(seen.first, 1);
      expect(seen.last, 2);
    });
  });
}
