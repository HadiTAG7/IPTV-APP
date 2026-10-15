// EpgService against a small local guide server: conditional requests,
// failures, non-standard XMLTV, offsets, cancellation and concurrency.
@Timeout(Duration(seconds: 60))
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/net/http.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/epg/epg_models.dart';
import 'package:iptv_player/epg/epg_progress.dart';
import 'package:iptv_player/epg/epg_service.dart';
import 'package:iptv_player/sources/models.dart';

import '../../support/real_http.dart';
import '../db/db_test_utils.dart';
import 'support/epg_test_utils.dart';
import 'support/guide_server.dart';

const _secret = 'Zx9-guide-secret';
const _agent = 'GuideTest/2.0';

final _now = DateTime.utc(2026, 1, 10, 12);

const _playlist = [
  ChannelData(
    key: 'a',
    name: 'Alpha HD',
    tvgId: 'ALPHA.tv',
    categoryKeys: ['all'],
  ),
  ChannelData(key: 'b', name: 'Beta', categoryKeys: ['all']),
  ChannelData(
    key: 'c',
    name: 'Gamma',
    tvgName: 'Gamma Plus',
    categoryKeys: ['all'],
  ),
  ChannelData(key: 'd', name: 'Delta', categoryKeys: ['all']),
];

/// Hourly programmes from now-20h for 5 days on each guide channel.
List<String> _standardGuide() {
  final from = _now.subtract(const Duration(hours: 20));
  return [
    channelXml('alpha.tv', ['Alpha']),
    channelXml('beta.id', ['Beta HD']),
    channelXml('gamma.id', ['Gamma Plus']),
    channelXml('other.tv', ['Other']),
    for (final id in ['alpha.tv', 'beta.id', 'gamma.id', 'other.tv'])
      ...hourly(id, from, 5 * 24),
  ];
}

/// Programmes per channel inside now-12h .. now+3d for [_standardGuide].
const _perChannel = 12 + 72;

void main() {
  useRealHttp();

  late FakeClock clock;
  late AppDatabase db;
  late GuideServer server;
  late EpgService service;
  late int source;
  late int guide;

  Future<void> createSource({int epgOffsetMin = 0}) async {
    source = await db.sourcesDao.create(
      SourceConfig(
        kind: SourceKind.m3uUrl,
        url: '${server.baseUrl}/list.m3u',
        name: 'Guide test',
        userAgent: _agent,
        password: _secret,
        epgOffsetMin: epgOffsetMin,
      ),
    );
    guide = await db.epgDao.addEpgSource(
      source,
      '${server.baseUrl}/epg.xml?username=alice&password=$_secret',
      EpgOrigin.m3uHeader,
    );
  }

  EpgService newService({int batchSize = 5000}) => EpgService(
    db: db,
    dioFactory: createDio,
    clock: clock,
    batchSize: batchSize,
  );

  setUp(() async {
    clock = FakeClock(_now);
    db = openTestDb(clock: clock);
    server = await GuideServer.start();
    server.body = xmltvDoc(_standardGuide());
    await createSource();
    await syncChannels(db, source, _playlist);
    service = newService();
  });

  tearDown(() async {
    await service.dispose();
    await server.close();
    await db.close();
  });

  group('import', () {
    test('links by tvg-id (any case), tvg-name and name', () async {
      final events = await runRefresh(service, source);

      expect(events.last, isA<EpgRefreshDone>());
      final links = await db.epgDao.linksFor(source);
      expect(links.keys, unorderedEquals(['a', 'b', 'c']));
      expect(links['a']!.xmltvId, 'alpha.tv');
      expect(links['a']!.kind, EpgMatchKind.tvgId);
      expect(links['b']!.xmltvId, 'beta.id');
      expect(links['b']!.kind, EpgMatchKind.name);
      expect(links['c']!.xmltvId, 'gamma.id');
      expect(links['c']!.kind, EpgMatchKind.tvgName);
      expect(await storedIds(db, guide), {'alpha.tv', 'beta.id', 'gamma.id'});
      expect(server.requests.single.userAgent, _agent);
    });

    test('keeps now-12h .. now+3d, or now+2d in Lite mode', () async {
      await runRefresh(service, source);
      var stored = await storedProgrammes(db, guide);
      expect(stored, hasLength(3 * _perChannel));
      final alpha = [
        for (final p in stored)
          if (p.xmltvId == 'alpha.tv') p,
      ];
      expect(
        fromSec(alpha.first.startUtc),
        _now.subtract(const Duration(hours: 12)),
      );
      expect(fromSec(alpha.last.stopUtc), _now.add(const Duration(days: 3)));

      await runRefresh(service, source, force: true, lite: true);
      stored = await storedProgrammes(db, guide);
      expect(stored, hasLength(3 * (12 + 48)));
    });

    test('the source offset is stored, the channel shift is applied once '
        'when reading', () async {
      await db.sourcesDao.updateConfig(
        source,
        SourceConfig(
          kind: SourceKind.m3uUrl,
          url: (await db.sourcesDao.byId(source))!.url,
          name: 'Guide test',
          userAgent: _agent,
          epgOffsetMin: 30,
        ),
      );
      await syncChannels(db, source, [
        const ChannelData(
          key: 'a',
          name: 'Alpha HD',
          tvgId: 'alpha.tv',
          tvgShiftMin: 60,
          categoryKeys: ['all'],
        ),
      ]);

      await runRefresh(service, source);

      // Published hourly on the hour; stored 30 minutes later.
      final stored = await storedProgrammes(db, guide);
      expect(stored.map((p) => fromSec(p.startUtc).minute).toSet(), {30});
      // Read back with the +60 shift: on air now is the one published at
      // 10:00 (stored 10:30, shown 11:30-12:30).
      final nowNext = await db.epgDao.nowNext(source, ['a'], _now);
      final current = nowNext['a']!.now!;
      expect(current.title, 'alpha.tv 18');
      expect(current.start, DateTime.utc(2026, 1, 10, 11, 30));
      expect(current.stop, DateTime.utc(2026, 1, 10, 12, 30));
    });

    test('a negative channel shift widens the stored window end', () async {
      await syncChannels(db, source, [
        const ChannelData(
          key: 'a',
          name: 'Alpha',
          tvgId: 'alpha.tv',
          tvgShiftMin: -120,
          categoryKeys: ['all'],
        ),
      ]);

      await runRefresh(service, source);

      expect(await storedProgrammes(db, guide), hasLength(_perChannel + 2));
    });

    test('channels after programmes, undeclared ids and duplicate channels '
        'are handled', () async {
      final from = _now.subtract(const Duration(hours: 1));
      server.body = xmltvDoc([
        channelXml('beta.id', ['Beta HD']),
        // Programmes before their <channel>, and for an id never declared.
        ...hourly('alpha.tv', from, 3),
        ...hourly('ghost.tv', from, 3),
        ...hourly('other.tv', from, 3),
        // Never declared either, linked by hand.
        ...hourly('manual.tv', from, 3),
        channelXml('ALPHA.TV', ['Alpha']),
        channelXml('other.tv', ['Other']),
        ...hourly('beta.id', from, 3),
        // Duplicate element with another name: both names match.
        channelXml('gamma.id', ['Gamma One']),
        channelXml('gamma.id', ['Gamma Plus']),
        ...hourly('gamma.id', from, 3),
        ...hourly('other.tv', from.add(const Duration(hours: 3)), 3),
      ]);
      await syncChannels(db, source, [
        ..._playlist,
        const ChannelData(
          key: 'g',
          name: 'Ghost',
          tvgId: 'ghost.tv',
          categoryKeys: ['all'],
        ),
      ]);
      await service.setManualMapping(source, 'd', guide, 'manual.tv');
      service = newService(batchSize: 2);

      final events = await runRefresh(service, source);

      expect(events.last, isA<EpgRefreshDone>());
      final links = await db.epgDao.linksFor(source);
      expect(links['a']!.xmltvId, 'alpha.tv');
      expect(links['d']!.xmltvId, 'manual.tv');
      expect(links['c']!.xmltvId, 'gamma.id');
      expect(links['g']!.xmltvId, 'ghost.tv');
      expect(links['g']!.kind, EpgMatchKind.tvgId);
      final stored = await storedProgrammes(db, guide);
      expect(
        {for (final p in stored) p.xmltvId},
        {'alpha.tv', 'beta.id', 'gamma.id', 'ghost.tv', 'manual.tv'},
      );
      expect(stored, hasLength(5 * 3));
      // Undeclared ids are kept as guide channels without names.
      final channels = await db.epgDao.epgChannels(guide);
      expect(
        [for (final c in channels) c.xmltvId],
        [
          'alpha.tv',
          'beta.id',
          'gamma.id',
          'ghost.tv',
          'manual.tv',
          'other.tv',
        ],
      );
      expect(
        [
          for (final r in await service.searchGuideChannels(source, 'manual'))
            r.xmltvId,
        ],
        ['manual.tv'],
      );
      final gamma = channels.firstWhere((c) => c.xmltvId == 'gamma.id');
      expect(gamma.displayNamesNorm, ['gamma one', 'gamma plus']);
    });

    test('a body that is not XMLTV fails and keeps the stored guide', () async {
      await runRefresh(service, source);
      final before = await storedProgrammes(db, guide);
      server.body = '<html><body>Service unavailable</body></html>';

      final events = await runRefresh(service, source, force: true);

      expect(
        events.whereType<EpgGuideFailed>().single.message,
        contains('No guide'),
      );
      expect(events.last, isA<EpgRefreshFailed>());
      expect(await storedProgrammes(db, guide), hasLength(before.length));
      expect((await db.epgDao.linksFor(source)).keys, hasLength(3));
    });

    test(
      'a guide with channels but no programmes empties the old data',
      () async {
        await runRefresh(service, source);
        server.body = xmltvDoc([
          channelXml('alpha.tv', ['Alpha']),
        ]);

        final events = await runRefresh(service, source, force: true);

        expect(events.last, isA<EpgRefreshDone>());
        expect(await storedProgrammes(db, guide), isEmpty);
        expect((await db.epgDao.linksFor(source)).keys, ['a']);
      },
    );

    test('does nothing without live channels or enabled guides', () async {
      await syncChannels(db, source, const []);
      var events = await runRefresh(service, source);
      expect(events, [isA<EpgRefreshDone>()]);
      expect((events.single as EpgRefreshDone).guides, 0);

      await syncChannels(db, source, _playlist);
      await db.epgDao.setEpgSourceEnabled(guide, false);
      events = await runRefresh(service, source);
      expect((events.single as EpgRefreshDone).guides, 0);
      expect(server.requests, isEmpty);
    });

    test('refuses to run while the device clock is unset', () async {
      clock.current = DateTime.utc(2000, 1, 1);

      final events = await runRefresh(service, source);

      expect((events.single as EpgRefreshFailed).message, contains('clock'));
      expect(server.requests, isEmpty);
    });

    test('an unknown source fails', () async {
      final events = await runRefresh(service, 999);
      expect(
        (events.single as EpgRefreshFailed).message,
        contains('Unknown source'),
      );
    });
  });

  group('conditional requests', () {
    test('304 keeps the stored guide and its age', () async {
      server.etag = '"v1"';
      await runRefresh(service, source);
      expect((await guideRow(db, guide)).etag, '"v1"');
      final before = await storedProgrammes(db, guide);
      final links = await db.epgDao.linksFor(source);
      clock.advance(const Duration(hours: 13));

      final events = await runRefresh(service, source);

      expect(server.requests.last.ifNoneMatch, '"v1"');
      expect(events.whereType<EpgGuideNotModified>().single.matched, 3);
      final done = events.last as EpgRefreshDone;
      expect(done.notModified, 1);
      expect(done.imported, 0);
      expect(done.matched, 3);
      // Programmes that ended before the new now-12h are pruned.
      final after = await storedProgrammes(db, guide);
      expect(after, hasLength(before.length - 3 * 13));
      expect(await db.epgDao.linksFor(source), links);
      final row = await guideRow(db, guide);
      expect(EpgSourceStatus.parse(row.status), EpgSourceStatus.notModified);
      expect(row.lastFetchAt, _now);
      expect(row.programmeCount, after.length);
      // The data is still from the first import: due again.
      expect(await service.needsRefresh(source), isTrue);
    });

    test('Last-Modified is sent back as If-Modified-Since', () async {
      server.lastModified = 'Sat, 10 Jan 2026 09:00:00 GMT';
      await runRefresh(service, source);

      final events = await runRefresh(service, source);

      expect(server.requests.last.ifModifiedSince, server.lastModified);
      expect(events.whereType<EpgGuideNotModified>(), hasLength(1));
    });

    test('not sent when forced, when the import is a day old, or when a '
        'new channel needs the guide', () async {
      server.etag = '"v1"';
      await runRefresh(service, source);

      await runRefresh(service, source, force: true);
      expect(server.requests.last.isConditional, isFalse);

      clock.advance(const Duration(hours: 24));
      await runRefresh(service, source);
      expect(server.requests.last.isConditional, isFalse);

      // Within a day of that import, a new channel matches "Other".
      clock.advance(const Duration(hours: 1));
      await syncChannels(db, source, [
        ..._playlist,
        const ChannelData(key: 'o', name: 'Other', categoryKeys: ['all']),
      ]);
      final events = await runRefresh(service, source);
      expect(server.requests.last.isConditional, isFalse);
      expect(events.whereType<EpgGuideFinished>(), hasLength(1));
      expect(await storedIds(db, guide), contains('other.tv'));
      expect((await db.epgDao.linkFor(source, 'o'))?.xmltvId, 'other.tv');

      // Unchanged since: conditional again.
      await runRefresh(service, source);
      expect(server.requests.last.ifNoneMatch, '"v1"');
    });
  });

  group('failures', () {
    test(
      'HTTP 500 records a redacted error and keeps data and links',
      () async {
        server.etag = '"v1"';
        await runRefresh(service, source);
        final before = await storedProgrammes(db, guide);
        final links = await db.epgDao.linksFor(source);
        server.status = 500;
        clock.advance(const Duration(minutes: 30));

        final events = await runRefresh(service, source, force: true);

        final failed = events.whereType<EpgGuideFailed>().single;
        expect(failed.message, contains('HTTP 500'));
        expect(failed.message, isNot(contains(_secret)));
        expect(failed.message, isNot(contains('alice')));
        final started = events.whereType<EpgGuideStarted>().single;
        expect(started.url, isNot(contains(_secret)));
        expect((events.last as EpgRefreshFailed).message, failed.message);

        expect(await storedProgrammes(db, guide), hasLength(before.length));
        expect(await db.epgDao.linksFor(source), links);
        final row = await guideRow(db, guide);
        final status = EpgSourceStatus.parse(row.status)!;
        expect(status.kind, EpgStatusKind.error);
        expect(status.message, failed.message);
        expect(row.status, isNot(contains(_secret)));
        // The stored guide is still the one from the first import.
        expect(row.lastFetchAt, _now);
        expect(row.etag, '"v1"');
        // A failed run does not count as a guide update.
        expect((await db.sourcesDao.byId(source))!.lastEpgAt, _now);
      },
    );

    test('one failing guide does not stop the others', () async {
      final manual = await db.epgDao.addEpgSource(
        source,
        '${server.baseUrl}/manual.xml',
        EpgOrigin.manual,
      );
      // The header guide (first) fails; the manual one links everything.
      final unreachable = await db.epgDao.addEpgSource(
        source,
        'http://127.0.0.1:1/epg.xml',
        EpgOrigin.m3uHeader,
        priority: -1,
      );

      final events = await runRefresh(service, source);

      expect(
        [for (final e in events.whereType<EpgGuideStarted>()) e.epgSourceId],
        [unreachable, guide, manual],
      );
      final done = events.last as EpgRefreshDone;
      expect(done.failed, 1);
      expect(done.imported, 2);
      expect(
        EpgSourceStatus.parse((await guideRow(db, unreachable)).status)?.kind,
        EpgStatusKind.error,
      );
      final links = await db.epgDao.linksFor(source);
      expect(links.values.every((l) => l.epgSourceId == guide), isTrue);
    });
  });

  group('manual links', () {
    test('a manual link to a guide id without programmes forces the next '
        'download', () async {
      server.etag = '"v1"';
      await runRefresh(service, source);

      await service.setManualMapping(source, 'd', guide, 'other.tv');

      expect((await guideRow(db, guide)).etag, isNull);
      await runRefresh(service, source);
      expect(server.requests.last.isConditional, isFalse);
      final link = await db.epgDao.linkFor(source, 'd');
      expect(link?.kind, EpgMatchKind.manual);
      expect(await storedIds(db, guide), contains('other.tv'));

      // Linking to an id that already has programmes keeps the validators.
      await service.setManualMapping(source, 'b', guide, 'alpha.tv');
      expect((await guideRow(db, guide)).etag, '"v1"');
      final events = await runRefresh(service, source);
      expect(events.whereType<EpgGuideNotModified>(), hasLength(1));
      expect((await db.epgDao.linkFor(source, 'b'))?.xmltvId, 'alpha.tv');
    });

    test(
      'an empty id means no guide; clearing restores automatic matching',
      () async {
        await service.setManualMapping(source, 'a', guide, '');
        await runRefresh(service, source);
        expect(await storedIds(db, guide), isNot(contains('alpha.tv')));
        expect((await db.epgDao.nowNext(source, ['a'], _now))['a'], isNull);

        await service.clearManualMapping(source, 'a');
        expect(await db.epgDao.linkFor(source, 'a'), isNull);
        await runRefresh(service, source);
        final link = await db.epgDao.linkFor(source, 'a');
        expect(link?.kind, EpgMatchKind.tvgId);
        expect(await storedIds(db, guide), contains('alpha.tv'));

        // Clearing an automatic link is a no-op.
        await service.clearManualMapping(source, 'a');
        expect(await db.epgDao.linkFor(source, 'a'), isNotNull);
      },
    );

    test('a manual id spelled in another case follows the guide', () async {
      await service.setManualMapping(source, 'd', guide, 'OTHER.TV');

      await runRefresh(service, source);

      final link = await db.epgDao.linkFor(source, 'd');
      expect(link?.kind, EpgMatchKind.manual);
      expect(link?.xmltvId, 'other.tv');
      final nowNext = await db.epgDao.nowNext(source, ['d'], _now);
      expect(nowNext['d']?.now?.title, 'other.tv 20');
    });

    test('rejects a guide of another source', () async {
      final otherSource = await addSource(db, name: 'Other');
      final otherGuide = await db.epgDao.addEpgSource(
        otherSource,
        '${server.baseUrl}/x.xml',
        EpgOrigin.manual,
      );
      await expectLater(
        service.setManualMapping(source, 'a', otherGuide, 'alpha.tv'),
        throwsArgumentError,
      );
    });
  });

  group('concurrency', () {
    test('cancel stops a running refresh and marks the guide for a full '
        'download', () async {
      server.etag = '"v1"';
      service = newService(batchSize: 4);
      await runRefresh(service, source);
      // Stall the next download after the channels and some programmes.
      server
        ..body = xmltvDoc(_standardGuide())
        ..stallAfterBytes = 3000;

      final events = <EpgProgress>[];
      final stored = Completer<void>();
      final finished = Completer<void>();
      service.refresh(source, force: true).listen((e) {
        events.add(e);
        if (e is EpgProgrammesStored && !stored.isCompleted) stored.complete();
      }, onDone: finished.complete);
      await stored.future;
      expect(service.isRefreshing(source), isTrue);

      await service.cancel(source);
      await finished.future;

      expect(events.last, isA<EpgRefreshCancelled>());
      expect(events.where((e) => e.isTerminal), hasLength(1));
      expect(service.isRefreshing(source), isFalse);
      final row = await guideRow(db, guide);
      expect(EpgSourceStatus.parse(row.status), EpgSourceStatus.cancelled);
      // Partial data: no validators, no import time.
      expect(row.etag, isNull);
      expect(row.lastFetchAt, isNull);
      expect(await service.needsRefresh(source), isTrue);

      // The next run downloads everything again.
      server
        ..stallAfterBytes = null
        ..release();
      final again = await runRefresh(service, source);
      expect(again.last, isA<EpgRefreshDone>());
      expect(server.requests.last.isConditional, isFalse);
      expect(await storedProgrammes(db, guide), hasLength(3 * _perChannel));
    });

    test('cancel while waiting for the server', () async {
      server.stallAfterBytes = 0;
      final run = runRefresh(service, source);
      await _until(() => server.requests.isNotEmpty);

      await service.cancel(source);

      expect((await run).last, isA<EpgRefreshCancelled>());
      expect(await storedProgrammes(db, guide), isEmpty);
      await service.cancel(source); // Nothing running: no-op.
    });

    test('a second refresh joins the running one', () async {
      server.stallAfterBytes = 10;
      final first = runRefresh(service, source);
      final second = runRefresh(service, source, force: true);
      await _until(() => server.requests.isNotEmpty);
      expect(service.isRefreshing(source), isTrue);
      // Joining late starts with the latest event.
      final joined = service.refresh(source).first;
      expect(await joined, isA<EpgGuideStarted>());

      server.release();
      final a = await first;
      final b = await second;

      expect(server.requests, hasLength(1));
      expect(a.last, isA<EpgRefreshDone>());
      expect(b.last, isA<EpgRefreshDone>());
      expect(service.isRefreshing(source), isFalse);

      // Finished runs are not joined.
      final third = await runRefresh(service, source);
      expect(third.first, isA<EpgGuideStarted>());
      expect(server.requests, hasLength(2));
    });

    test('a refresh starts without a listener; dispose cancels it', () async {
      server.stallAfterBytes = 10;
      service.refresh(source);
      await _until(() => server.requests.isNotEmpty);

      await service.dispose();

      expect(service.isRefreshing(source), isFalse);
      expect(() => service.refresh(source), throwsStateError);
      expect(
        EpgSourceStatus.parse((await guideRow(db, guide)).status),
        EpgSourceStatus.cancelled,
      );
    });
  });

  group('helpers', () {
    test('isStale', () {
      expect(service.isStale(null, 12), isTrue);
      expect(
        service.isStale(_now.subtract(const Duration(hours: 11)), 12),
        isFalse,
      );
      expect(
        service.isStale(_now.subtract(const Duration(hours: 12)), 12),
        isTrue,
      );
      // A stamp from the future: the clock went back since.
      expect(service.isStale(_now.add(const Duration(hours: 1)), 12), isTrue);
      expect(
        service.isStale(_now.add(const Duration(minutes: 1)), 12),
        isFalse,
      );
    });

    test('windowAt', () {
      expect(service.windowAt(_now), (
        start: _now.subtract(const Duration(hours: 12)),
        end: _now.add(const Duration(days: 3)),
      ));
      expect(
        service.windowAt(_now, lite: true).end,
        _now.add(const Duration(days: 2)),
      );
    });

    test('shiftProgramme moves start and stop and keeps the rest', () {
      final p = EpgProgramme(
        channelId: 'x',
        start: _now,
        stop: _now.add(const Duration(hours: 1)),
        title: 'T',
        subTitle: 'S',
        desc: 'D',
        category: 'C',
        icon: 'I',
      );
      final moved = shiftProgramme(p, -90);
      expect(moved.start, _now.subtract(const Duration(minutes: 90)));
      expect(moved.stop, _now.subtract(const Duration(minutes: 30)));
      expect(
        [
          moved.channelId,
          moved.title,
          moved.subTitle,
          moved.desc,
          moved.category,
          moved.icon,
        ],
        ['x', 'T', 'S', 'D', 'C', 'I'],
      );
      expect(identical(shiftProgramme(p, 0), p), isTrue);
      expect(shiftProgrammes([p, p], 15).map((e) => e.start), [
        _now.add(const Duration(minutes: 15)),
        _now.add(const Duration(minutes: 15)),
      ]);
    });

    test('shortEpg applies the source offset and the channel shift, and '
        'caches for 15 minutes', () async {
      await db.sourcesDao.updateConfig(
        source,
        SourceConfig(
          kind: SourceKind.m3uUrl,
          url: (await db.sourcesDao.byId(source))!.url,
          name: 'Guide test',
          epgOffsetMin: -30,
        ),
      );
      await syncChannels(db, source, [
        const ChannelData(
          key: 'a',
          name: 'Alpha',
          tvgShiftMin: 120,
          categoryKeys: ['all'],
        ),
      ]);
      var calls = 0;
      Future<List<EpgProgramme>> loader() async {
        calls++;
        return [
          EpgProgramme(
            channelId: 'alpha.tv',
            start: _now,
            stop: _now.add(const Duration(hours: 1)),
            title: 'Now',
          ),
        ];
      }

      final first = await service.shortEpg(source, 'a', loader);
      expect(first.single.start, _now.add(const Duration(minutes: 90)));
      await service.shortEpg(source, 'a', loader);
      expect(calls, 1);
      clock.advance(const Duration(minutes: 15));
      await service.shortEpg(source, 'a', loader);
      expect(calls, 2);

      // Failures give an empty list.
      final none = await service.shortEpg(
        source,
        'b',
        () async => throw const NetworkFailure('down'),
      );
      expect(none, isEmpty);
    });

    test('EpgSourceStatus round-trips', () {
      for (final s in [
        EpgSourceStatus.ok,
        EpgSourceStatus.notModified,
        EpgSourceStatus.cancelled,
        const EpgSourceStatus(EpgStatusKind.error, 'HTTP 500 from x'),
      ]) {
        expect(EpgSourceStatus.parse(s.encode()), s);
      }
      expect(EpgSourceStatus.parse(null), isNull);
      expect(EpgSourceStatus.parse(''), isNull);
      expect(
        EpgSourceStatus.parse('something odd'),
        const EpgSourceStatus(EpgStatusKind.error, 'something odd'),
      );
    });
  });

  test('the dio factory gets the source User-Agent and Referer', () async {
    final seen = <String?>[];
    service = EpgService(
      db: db,
      clock: clock,
      dioFactory: ({String? userAgent, String? referer}) {
        seen.addAll([userAgent, referer]);
        return createDio(userAgent: userAgent, referer: referer);
      },
    );
    await runRefresh(service, source);
    expect(seen, [_agent, null]);
    expect(server.requests.single.userAgent, _agent);
  });
}

Future<void> _until(bool Function() condition) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > const Duration(seconds: 10)) {
      throw TimeoutException('condition not met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
