// End-to-end guide refresh against the in-process fake Xtream panel.
@Timeout(Duration(seconds: 60))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/net/http.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/epg/epg_models.dart';
import 'package:iptv_player/epg/epg_progress.dart';
import 'package:iptv_player/epg/epg_service.dart';
import 'package:iptv_player/sources/models.dart';

import '../../support/fake_panel.dart';
import '../../support/real_http.dart';
import '../db/db_test_utils.dart';
import 'support/epg_test_utils.dart';

const _user = 'guide-tester';
const _password = 'Zq8pw-secret';
const _agent = 'GuideTest/1.0';

/// Channels 1..40 of the panel are in the playlist; 41..50 only in the guide.
const _inPlaylist = 40;

ChannelData _channel(FakeChannel c) => ChannelData(
  key: '${c.id}',
  name: c.name,
  tvgId: c.epgId,
  categoryKeys: const ['all'],
);

void main() {
  useRealHttp();

  late FakeClock clock;
  late AppDatabase db;
  late FakePanel panel;
  late EpgService service;
  late int source;
  late List<FakeChannel> playlist;

  final now = DateTime.utc(2026, 1, 10, 12, 10);

  setUp(() async {
    clock = FakeClock(now);
    db = openTestDb(clock: clock);
    panel = await FakePanel.start(
      username: _user,
      password: _password,
      mediaDir: null,
      epgSpan: const Duration(days: 5),
      now: clock.now,
    );
    source = await db.sourcesDao.create(
      SourceConfig(
        kind: SourceKind.xtream,
        url: panel.baseUrl,
        name: 'Panel',
        username: _user,
        password: _password,
        userAgent: _agent,
      ),
    );
    playlist = panel.catalog.live.take(_inPlaylist).toList();
    await syncChannels(db, source, [for (final c in playlist) _channel(c)]);
    service = EpgService(db: db, dioFactory: createDio, clock: clock);
  });

  tearDown(() async {
    await service.dispose();
    await panel.close();
    await db.close();
  });

  /// Panel programmes of [c] overlapping now-12h .. now+3d.
  List<FakeProgramme> expectedFor(FakeChannel c) => [
    for (final p in panel.programmes(c))
      if (p.stop.isAfter(now.subtract(const Duration(hours: 12))) &&
          p.start.isBefore(now.add(const Duration(days: 3))))
        p,
  ];

  Future<void> expectLinkedByTvgIdAndName() async {
    final links = await db.epgDao.linksFor(source);
    expect(links, hasLength(_inPlaylist));
    for (final c in playlist) {
      final link = links['${c.id}']!;
      if (c.hasEpgId) {
        expect(link.kind, EpgMatchKind.tvgId, reason: c.name);
        expect(link.xmltvId, c.epgId);
      } else {
        // No epg_channel_id: found through the display name.
        expect(link.kind, EpgMatchKind.name, reason: c.name);
        expect(link.xmltvId, 'noid${c.index}.example');
      }
    }
  }

  test('gzip xmltv.php: links by tvg-id and by name, keeps only linked '
      'channels inside the window', () async {
    final guide = await db.epgDao.addEpgSource(
      source,
      panel.xmltvUrl,
      EpgOrigin.xtream,
    );

    final events = await runRefresh(service, source);

    final done = events.last as EpgRefreshDone;
    expect(done.guides, 1);
    expect(done.imported, 1);
    expect(done.failed, 0);
    expect(done.matched, _inPlaylist);
    await expectLinkedByTvgIdAndName();

    // Programmes only for linked guide ids, exactly the panel's listings
    // inside the window, each once.
    final links = await db.epgDao.linksFor(source);
    final programmes = await storedProgrammes(db, guide);
    expect(await storedIds(db, guide), {
      for (final l in links.values) l.xmltvId,
    });
    for (final c in playlist) {
      final id = links['${c.id}']!.xmltvId;
      final stored = [
        for (final p in programmes)
          if (p.xmltvId == id) p,
      ];
      final expected = expectedFor(c);
      expect(
        [for (final p in stored) fromSec(p.startUtc)],
        [for (final p in expected) p.start],
        reason: c.name,
      );
      expect(stored.first.title, expected.first.title);
    }
    final starts = [for (final p in programmes) fromSec(p.startUtc)];
    expect(
      starts.every((s) => s.isBefore(now.add(const Duration(days: 3)))),
      isTrue,
    );
    // The guide lists 5 days; the window keeps 3.
    expect(
      starts.any((s) => s.isAfter(now.add(const Duration(days: 2, hours: 22)))),
      isTrue,
    );

    // Every guide channel is stored for matching and manual assignment.
    expect(await guideChannelCount(db, guide), panel.catalog.live.length);

    final row = await guideRow(db, guide);
    expect(EpgSourceStatus.parse(row.status), EpgSourceStatus.ok);
    expect(row.lastFetchAt, now);
    expect(row.programmeCount, programmes.length);
    expect((await db.sourcesDao.byId(source))!.lastEpgAt, now);

    // The source's User-Agent was sent.
    expect(panel.stats.userAgents['/xmltv.php'], _agent);

    // Progress: started (credentials masked), parsed, matched, stored.
    final started = events.whereType<EpgGuideStarted>().single;
    expect(started.url, isNot(contains(_password)));
    expect(started.url, contains('password=***'));
    expect(started.origin, EpgOrigin.xtream);
    expect(lastOf<EpgChannelsParsed>(events).channels, 50);
    expect(lastOf<EpgChannelsMatched>(events).matched, _inPlaylist);
    expect(lastOf<EpgProgrammesStored>(events).programmes, programmes.length);
    final finished = events.whereType<EpgGuideFinished>().single;
    expect(finished.programmes, programmes.length);
    expect(finished.matched, _inPlaylist);
    expect(events.where((e) => e.isTerminal), hasLength(1));
  });

  test('plain XML guide from the playlist header', () async {
    final guide = await db.epgDao.addEpgSource(
      source,
      panel.plainEpgUrl,
      EpgOrigin.m3uHeader,
    );

    final events = await runRefresh(service, source);

    expect(events.last, isA<EpgRefreshDone>());
    await expectLinkedByTvgIdAndName();
    final links = await db.epgDao.linksFor(source);
    expect(await storedIds(db, guide), {
      for (final l in links.values) l.xmltvId,
    });
  });

  test('a second run replaces the guide without duplicates', () async {
    final guide = await db.epgDao.addEpgSource(
      source,
      panel.xmltvUrl,
      EpgOrigin.xtream,
    );
    await runRefresh(service, source);
    final first = await storedProgrammes(db, guide);
    final firstLinks = await db.epgDao.linksFor(source);

    final events = await runRefresh(service, source);

    expect(events.last, isA<EpgRefreshDone>());
    final second = await storedProgrammes(db, guide);
    expect(second, hasLength(first.length));
    expect(
      [for (final p in second) '${p.xmltvId}@${p.startUtc}'],
      [for (final p in first) '${p.xmltvId}@${p.startUtc}'],
    );
    expect(await db.epgDao.linksFor(source), firstLinks);
    expect(panel.stats.requestsByPath['/xmltv.php'], 2);
  });

  test('manual mapping survives refreshes and brings its programmes', () async {
    final guide = await db.epgDao.addEpgSource(
      source,
      panel.xmltvUrl,
      EpgOrigin.xtream,
    );
    final first = playlist.first; // tvg-id test1.example.
    final outside = panel.catalog.live[44]; // Not in the playlist.
    expect(outside.xmltvId, 'test45.example');

    await service.setManualMapping(
      source,
      '${first.id}',
      guide,
      outside.xmltvId,
    );
    await runRefresh(service, source);
    await runRefresh(service, source);

    final link = await db.epgDao.linkFor(source, '${first.id}');
    expect(link?.kind, EpgMatchKind.manual);
    expect(link?.xmltvId, 'test45.example');
    final ids = await storedIds(db, guide);
    expect(ids, contains('test45.example'));
    // The automatic match of that channel is not kept.
    expect(ids, isNot(contains('test1.example')));

    final nowNext = await db.epgDao.nowNext(source, ['${first.id}'], now);
    expect(nowNext['${first.id}']?.now?.channelId, 'test45.example');
  });

  test('assign-guide search folds Arabic and strips quality tags', () async {
    final guide = await db.epgDao.addEpgSource(
      source,
      panel.xmltvUrl,
      EpgOrigin.xtream,
    );
    await runRefresh(service, source);

    final news = await service.searchGuideChannels(source, 'test news 4 FHD');
    expect(news.first.xmltvId, 'test4.example');
    expect(news.first.epgSourceId, guide);
    expect(news.first.displayName, 'Test News 4 HD');
    expect([
      for (final r in news) r.xmltvId,
    ], containsAll(['test4.example', 'test42.example', 'test44.example']));

    // ة/ه folding: the query spells it differently from the guide.
    final arabic = await service.searchGuideChannels(source, 'قناه اختبار 3');
    expect(arabic.first.xmltvId, 'test3.example');
    expect([
      for (final r in arabic) r.xmltvId,
    ], containsAll(['test31.example', 'test33.example']));

    final byId = await service.searchGuideChannels(source, 'NOID20');
    expect([for (final r in byId) r.xmltvId], ['noid20.example']);

    expect(
      await service.searchGuideChannels(source, 'nothing like it'),
      isEmpty,
    );
    expect(
      await service.searchGuideChannels(source, '', limit: 5),
      hasLength(5),
    );
  });

  test('prunes programmes that ended more than 12 hours ago', () async {
    await db.epgDao.addEpgSource(source, panel.xmltvUrl, EpgOrigin.xtream);
    // A second, disabled guide holds old data the refresh does not replace.
    final other = await db.epgDao.addEpgSource(
      source,
      '${panel.baseUrl}/other.xml',
      EpgOrigin.manual,
      enabled: false,
    );
    final tooOld = now.subtract(const Duration(hours: 13));
    final recent = now.subtract(const Duration(hours: 11));
    await db.epgDao.insertProgrammes(other, [
      for (final stop in [tooOld, recent])
        EpgProgramme(
          channelId: 'old.tv',
          start: stop.subtract(const Duration(hours: 1)),
          stop: stop,
          title: 'Old',
        ),
    ]);

    await runRefresh(service, source);

    final left = await storedProgrammes(db, other);
    expect([for (final p in left) fromSec(p.stopUtc)], [recent]);
  });

  test('an xtream guide wins over a manual guide listing the same '
      'channels', () async {
    // Added first, so it has the lower id and the same priority.
    final manual = await db.epgDao.addEpgSource(
      source,
      panel.plainEpgUrl,
      EpgOrigin.manual,
    );
    final xtream = await db.epgDao.addEpgSource(
      source,
      panel.xmltvUrl,
      EpgOrigin.xtream,
    );

    final events = await runRefresh(service, source);

    expect(
      [for (final e in events.whereType<EpgGuideStarted>()) e.epgSourceId],
      [xtream, manual],
    );
    final done = events.last as EpgRefreshDone;
    expect(done.imported, 2);
    final links = await db.epgDao.linksFor(source);
    expect(links.values.every((l) => l.epgSourceId == xtream), isTrue);
    // Nothing left for the manual guide to link, but its channels are kept
    // for manual assignment.
    expect(await storedProgrammes(db, manual), isEmpty);
    expect(await guideChannelCount(db, manual), panel.catalog.live.length);
    expect((await guideRow(db, manual)).programmeCount, 0);
  });

  test('a blocked account fails the guide with a redacted message', () async {
    final guide = await db.epgDao.addEpgSource(
      source,
      panel.xmltvUrl,
      EpgOrigin.xtream,
    );
    panel.auth = FakeAuthMode.banned;

    final events = await runRefresh(service, source);

    final failed = events.whereType<EpgGuideFailed>().single;
    expect(failed.message, contains('403'));
    expect(failed.message, isNot(contains(_password)));
    final terminal = events.last as EpgRefreshFailed;
    expect(terminal.message, failed.message);
    final status = EpgSourceStatus.parse((await guideRow(db, guide)).status);
    expect(status?.kind, EpgStatusKind.error);
    expect(status?.message, failed.message);
  });

  test('needsRefresh follows the age of the last import', () async {
    await db.epgDao.addEpgSource(source, panel.xmltvUrl, EpgOrigin.xtream);
    expect(await service.needsRefresh(source), isTrue);

    await runRefresh(service, source);
    expect(await service.needsRefresh(source), isFalse);

    clock.advance(const Duration(hours: 11, minutes: 59));
    expect(await service.needsRefresh(source), isFalse);
    clock.advance(const Duration(minutes: 1));
    expect(await service.needsRefresh(source), isTrue);
    expect(await service.needsRefresh(source, refreshHours: 24), isFalse);
  });
}
