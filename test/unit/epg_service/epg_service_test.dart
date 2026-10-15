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
import 'package:iptv_player/epg/xmltv_parser.dart';
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

/// Hourly programmes from now-20h (plus [shift]) for 5 days on each guide
/// channel; [extra] adds guide channels (id -> name).
List<String> _standardGuide({
  Map<String, String> extra = const {},
  Duration shift = Duration.zero,
}) {
  final from = _now.subtract(const Duration(hours: 20)).add(shift);
  final names = {
    'alpha.tv': 'Alpha',
    'beta.id': 'Beta HD',
    'gamma.id': 'Gamma Plus',
    'other.tv': 'Other',
    ...extra,
  };
  return [
    for (final MapEntry(:key, :value) in names.entries)
      channelXml(key, [value]),
    for (final id in names.keys) ...hourly(id, from, 5 * 24),
  ];
}

/// Records the id filter of every parse.
class _SpyParser extends XmltvParser {
  _SpyParser();

  final filters = <Set<String>?>[];

  @override
  Stream<XmltvBatch> parse(
    Stream<List<int>> bytes, {
    Set<String>? wantedChannelIds,
    DateTime? windowStart,
    DateTime? windowEnd,
    int batchSize = 5000,
    int Function(String channelId)? shiftMinutesFor,
    int offsetMinutes = 0,
    List<String> preferredLangs = const ['ar', 'en'],
  }) {
    filters.add(wantedChannelIds);
    return super.parse(
      bytes,
      wantedChannelIds: wantedChannelIds,
      windowStart: windowStart,
      windowEnd: windowEnd,
      batchSize: batchSize,
      shiftMinutesFor: shiftMinutesFor,
      offsetMinutes: offsetMinutes,
      preferredLangs: preferredLangs,
    );
  }
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
      final checkedAt = _now.add(const Duration(hours: 13));
      expect(
        EpgSourceStatus.parse(row.status),
        EpgSourceStatus(EpgStatusKind.notModified, null, checkedAt),
      );
      expect(row.lastFetchAt, _now);
      expect(row.programmeCount, after.length);

      // The 304 counts as a check: not due, and a refresh skips the guide,
      // until the stored window gets too short (a day after the import).
      clock.advance(const Duration(hours: 1));
      expect(await service.needsRefresh(source), isFalse);
      final skipped = await runRefresh(service, source);
      expect(skipped.whereType<EpgGuideSkipped>().single.matched, 3);
      expect((skipped.last as EpgRefreshDone).skipped, 1);
      expect(server.requests, hasLength(2));
      clock.advance(const Duration(hours: 9, minutes: 59));
      expect(await service.needsRefresh(source), isFalse);
      clock.advance(const Duration(minutes: 1));
      expect(await service.needsRefresh(source), isTrue);
      await runRefresh(service, source);
      expect(server.requests.last.isConditional, isFalse);
    });

    test('Last-Modified is sent back as If-Modified-Since', () async {
      server.lastModified = 'Sat, 10 Jan 2026 09:00:00 GMT';
      await runRefresh(service, source);
      clock.advance(const Duration(hours: 12));

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

      // Unchanged since: skipped while current, then conditional again.
      final skipped = await runRefresh(service, source);
      expect(skipped.whereType<EpgGuideSkipped>(), hasLength(1));
      expect(server.requests, hasLength(4));
      clock.advance(const Duration(hours: 12));
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

      await runRefresh(service, source);
      expect(server.requests, hasLength(2));
      expect(server.requests.last.isConditional, isFalse);
      final link = await db.epgDao.linkFor(source, 'd');
      expect(link?.kind, EpgMatchKind.manual);
      expect(await storedIds(db, guide), contains('other.tv'));

      // Linking to an id that already has programmes needs no download.
      await service.setManualMapping(source, 'b', guide, 'alpha.tv');
      var events = await runRefresh(service, source);
      expect(events.whereType<EpgGuideSkipped>(), hasLength(1));
      expect(server.requests, hasLength(2));
      clock.advance(const Duration(hours: 12));
      events = await runRefresh(service, source);
      expect(server.requests.last.ifNoneMatch, '"v1"');
      expect(events.whereType<EpgGuideNotModified>(), hasLength(1));
      expect((await db.epgDao.linkFor(source, 'b'))?.xmltvId, 'alpha.tv');
      final nowNext = await db.epgDao.nowNext(source, ['b', 'd'], clock.now());
      expect(nowNext['b']?.now?.channelId, 'alpha.tv');
      expect(nowNext['d']?.now?.channelId, 'other.tv');
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
      expect(
        EpgSourceStatus.parse(row.status),
        EpgSourceStatus(EpgStatusKind.cancelled, null, _now),
      );
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
      // A Lite request is covered by a full-window run.
      final second = runRefresh(service, source, lite: true);
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
      final third = await runRefresh(service, source, force: true);
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
        EpgSourceStatus.parse((await guideRow(db, guide)).status)?.kind,
        EpgStatusKind.cancelled,
      );
    });
  });

  group('kept ids', () {
    test('a guide failing after a sync does not link new channels to ids '
        'it never stored', () async {
      server.etag = '"v1"';
      await runRefresh(service, source);
      clock.advance(const Duration(hours: 1));
      // The new channel matches the stored guide channel "Other".
      await syncChannels(db, source, [
        ..._playlist,
        const ChannelData(key: 'o', name: 'Other', categoryKeys: ['all']),
      ]);

      server.status = 500;
      final failed = await runRefresh(service, source);

      expect(failed.last, isA<EpgRefreshFailed>());
      expect(server.requests.last.isConditional, isFalse);
      expect(await db.epgDao.linkFor(source, 'o'), isNull);
      expect(
        (await db.epgDao.linksFor(source)).keys,
        unorderedEquals(['a', 'b', 'c']),
      );

      // Back up half an hour later: the guide is downloaded in full.
      server.status = 200;
      clock.advance(const Duration(minutes: 30));
      final events = await runRefresh(service, source);
      expect(server.requests.last.isConditional, isFalse);
      expect(events.whereType<EpgGuideFinished>(), hasLength(1));
      final nowNext = await db.epgDao.nowNext(source, ['o'], clock.now());
      expect(nowNext['o']?.now?.channelId, 'other.tv');
    });

    test('a manual link set while a refresh runs is fetched by the next '
        'refresh', () async {
      server.etag = '"v1"';
      await runRefresh(service, source);
      clock.advance(const Duration(minutes: 10));
      server.stallAfterBytes = 10;
      final run = runRefresh(service, source, force: true);
      await _until(() => server.requests.length == 2);

      await service.setManualMapping(source, 'd', guide, 'other.tv');
      server.release();

      expect((await run).last, isA<EpgRefreshDone>());
      // That run did not know the link and stored the validators again.
      expect((await guideRow(db, guide)).etag, '"v1"');
      expect(await storedIds(db, guide), isNot(contains('other.tv')));

      clock.advance(const Duration(minutes: 10));
      server.stallAfterBytes = null;
      final events = await runRefresh(service, source);
      expect(server.requests, hasLength(3));
      expect(server.requests.last.isConditional, isFalse);
      expect(events.whereType<EpgGuideFinished>(), hasLength(1));
      final nowNext = await db.epgDao.nowNext(source, ['d'], clock.now());
      expect(nowNext['d']?.now?.channelId, 'other.tv');
    });
  });

  group('scheduling', () {
    test('a dead guide neither keeps needsRefresh true nor makes refresh '
        'download the current guide again', () async {
      final dead = await db.epgDao.addEpgSource(
        source,
        'http://127.0.0.1:1/dead.xml',
        EpgOrigin.manual,
      );
      final first = await runRefresh(service, source);
      expect((first.last as EpgRefreshDone).failed, 1);
      expect(server.requests, hasLength(1));

      clock.advance(const Duration(minutes: 5));
      expect(await service.needsRefresh(source), isFalse);

      // An explicit refresh retries the dead guide only.
      final second = await runRefresh(service, source);
      expect(
        [for (final e in second.whereType<EpgGuideSkipped>()) e.epgSourceId],
        [guide],
      );
      expect(
        [for (final e in second.whereType<EpgGuideFailed>()) e.epgSourceId],
        [dead],
      );
      final done = second.last as EpgRefreshDone;
      expect((done.imported, done.skipped, done.failed), (0, 1, 1));
      expect(done.matched, 3);
      expect(server.requests, hasLength(1));
      final status = EpgSourceStatus.parse((await guideRow(db, dead)).status)!;
      expect(status.kind, EpgStatusKind.error);
      expect(status.at, _now.add(const Duration(minutes: 5)));
      // Links and data of the skipped guide are kept.
      expect((await db.epgDao.linksFor(source)).keys, hasLength(3));
      expect(await storedProgrammes(db, guide), hasLength(3 * _perChannel));

      // The failed guide is due again an hour after its last attempt.
      clock.advance(const Duration(minutes: 59));
      expect(await service.needsRefresh(source), isFalse);
      clock.advance(const Duration(minutes: 1));
      expect(await service.needsRefresh(source), isTrue);
    });

    test('needsRefresh is false while the device clock is unset', () async {
      clock.current = DateTime.utc(2000, 1, 1);
      expect(await service.needsRefresh(source), isFalse);
    });

    test('a forced refresh during a running one runs after it', () async {
      server.etag = '"v1"';
      await runRefresh(service, source);
      clock.advance(const Duration(hours: 13));

      final first = runRefresh(service, source);
      final forced = runRefresh(service, source, force: true);
      final joined = runRefresh(service, source);
      expect(service.isRefreshing(source), isTrue);

      final a = await first;
      final b = await forced;
      final c = await joined;
      expect(server.requests, hasLength(3));
      expect(server.requests[1].isConditional, isTrue);
      expect(server.requests[2].isConditional, isFalse);
      expect((a.last as EpgRefreshDone).notModified, 1);
      expect(c, a);
      expect(b.first, isA<EpgGuideStarted>());
      expect((b.last as EpgRefreshDone).imported, 1);
      expect(service.isRefreshing(source), isFalse);
      expect(
        (await guideRow(db, guide)).lastFetchAt,
        _now.add(const Duration(hours: 13)),
      );
    });

    test('cancel also drops a queued follow-up', () async {
      server.stallAfterBytes = 10;
      final first = runRefresh(service, source);
      final forced = runRefresh(service, source, force: true);
      await _until(() => server.requests.isNotEmpty);

      await service.cancel(source);

      expect((await first).last, isA<EpgRefreshCancelled>());
      expect(await forced, [isA<EpgRefreshCancelled>()]);
      expect(service.isRefreshing(source), isFalse);
      expect(server.requests, hasLength(1));
    });
  });

  group('writes', () {
    test('the guide stays readable during an import and after a dropped '
        'download', () async {
      server.etag = '"v1"';
      service = newService(batchSize: 4);
      await runRefresh(service, source);
      final before = await storedProgrammes(db, guide);
      expect(before, hasLength(3 * _perChannel));

      // Stall the next download after some alpha.tv programmes.
      server.stallAfterBytes = 3000;
      final stored = Completer<void>();
      final run = service.refresh(source, force: true).toList();
      final watch = service.refresh(source, force: true).listen((e) {
        if (e is EpgProgrammesStored && !stored.isCompleted) stored.complete();
      });
      await stored.future;
      await watch.cancel();

      final during = await db.epgDao.nowNext(source, ['a', 'b', 'c'], _now);
      expect(during.keys, unorderedEquals(['a', 'b', 'c']));
      expect(await storedProgrammes(db, guide), hasLength(before.length));
      server.release();
      expect((await run).last, isA<EpgRefreshDone>());

      // The connection breaks after the channels and some programmes.
      server
        ..stallAfterBytes = null
        ..dropAfterBytes = 3000;
      final dropped = await runRefresh(service, source, force: true);

      expect(dropped.whereType<EpgProgrammesStored>(), isNotEmpty);
      expect(dropped.last, isA<EpgRefreshFailed>());
      final after = await storedProgrammes(db, guide);
      expect(
        [for (final p in after) '${p.xmltvId}@${p.startUtc}'],
        [for (final p in before) '${p.xmltvId}@${p.startUtc}'],
      );
      final nowNext = await db.epgDao.nowNext(source, ['a', 'b', 'c'], _now);
      expect(nowNext.keys, unorderedEquals(['a', 'b', 'c']));
      // Part of a new version is stored: no validators, no import time.
      final row = await guideRow(db, guide);
      expect(EpgSourceStatus.parse(row.status)?.kind, EpgStatusKind.error);
      expect(row.etag, isNull);
      expect(row.lastFetchAt, isNull);
      // Retried an hour after the failure.
      expect(await service.needsRefresh(source), isFalse);
      clock.advance(const Duration(hours: 1));
      expect(await service.needsRefresh(source), isTrue);
    });

    test('a changed schedule replaces the old slots', () async {
      await runRefresh(service, source);
      server.body = xmltvDoc(
        _standardGuide(shift: const Duration(minutes: 30)),
      );

      await runRefresh(service, source, force: true);

      final stored = await storedProgrammes(db, guide);
      expect(stored, hasLength(3 * (_perChannel + 1)));
      expect({for (final p in stored) fromSec(p.startUtc).minute}, {30});
    });
  });

  group('parser filter', () {
    test('after the first import the parser only decodes wanted channels; '
        'a newly linked guide channel restarts the download', () async {
      final parser = _SpyParser();
      service = EpgService(
        db: db,
        dioFactory: createDio,
        clock: clock,
        parser: parser,
      );
      await runRefresh(service, source);
      expect(parser.filters, [null]);

      await runRefresh(service, source, force: true);
      const known = {'alpha.tv', 'beta.id', 'gamma.id'};
      expect(parser.filters, [null, known]);
      expect(server.requests, hasLength(2));
      expect(await storedProgrammes(db, guide), hasLength(3 * _perChannel));

      // The guide now declares a channel that matches "Delta" by name.
      server.body = xmltvDoc(_standardGuide(extra: {'delta.tv': 'Delta'}));
      final events = await runRefresh(service, source, force: true);

      expect(events.last, isA<EpgRefreshDone>());
      expect(parser.filters.sublist(2), [known, null]);
      expect(server.requests, hasLength(4));
      expect((await db.epgDao.linkFor(source, 'd'))?.xmltvId, 'delta.tv');
      expect(await storedIds(db, guide), {...known, 'delta.tv'});
      expect(await storedProgrammes(db, guide), hasLength(4 * _perChannel));

      // The stored channels now predict it: one filtered download.
      await runRefresh(service, source, force: true);
      expect(server.requests, hasLength(5));
      expect(parser.filters.last, {...known, 'delta.tv'});
    });
  });

  group('background isolate', () {
    test(
      'runs the import in an isolate and forwards events and cancel',
      () async {
        service = EpgService(
          db: db,
          dioFactory: createDio,
          clock: clock,
          runInIsolate: true,
        );

        final events = await runRefresh(service, source);

        expect(events.first, isA<EpgGuideStarted>());
        expect(events.whereType<EpgGuideFinished>(), hasLength(1));
        expect((events.last as EpgRefreshDone).matched, 3);
        expect(await storedIds(db, guide), {'alpha.tv', 'beta.id', 'gamma.id'});
        expect(
          (await db.epgDao.linksFor(source)).keys,
          unorderedEquals(['a', 'b', 'c']),
        );
        expect(server.requests.single.userAgent, _agent);

        // One run per source: a second call joins; cancel reaches the isolate.
        server.stallAfterBytes = 10;
        final run = runRefresh(service, source, force: true);
        final joined = runRefresh(service, source, force: true);
        await _until(() => server.requests.length == 2);
        expect(service.isRefreshing(source), isTrue);

        await service.cancel(source);

        expect((await run).last, isA<EpgRefreshCancelled>());
        expect((await joined).last, isA<EpgRefreshCancelled>());
        expect(service.isRefreshing(source), isFalse);
        expect(server.requests, hasLength(2));
        expect(
          EpgSourceStatus.parse((await guideRow(db, guide)).status)?.kind,
          EpgStatusKind.cancelled,
        );
        expect(await storedIds(db, guide), {'alpha.tv', 'beta.id', 'gamma.id'});
      },
    );
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
      final at = DateTime.utc(2026, 1, 10, 12);
      for (final s in [
        EpgSourceStatus.ok,
        EpgSourceStatus.notModified,
        EpgSourceStatus.cancelled,
        const EpgSourceStatus(EpgStatusKind.error, 'HTTP 500 from x'),
        EpgSourceStatus(EpgStatusKind.ok, null, at),
        EpgSourceStatus(EpgStatusKind.notModified, null, at),
        EpgSourceStatus(EpgStatusKind.error, 'HTTP 500: x@y', at),
        EpgSourceStatus(EpgStatusKind.error, null, at),
      ]) {
        expect(EpgSourceStatus.parse(s.encode()), s);
      }
      expect(
        EpgSourceStatus(EpgStatusKind.error, 'HTTP 500', at).encode(),
        'error@1768046400: HTTP 500',
      );
      expect(
        EpgSourceStatus.parse('error: HTTP 500'),
        const EpgSourceStatus(EpgStatusKind.error, 'HTTP 500'),
      );
      expect(
        EpgSourceStatus.parse('ok: odd'),
        const EpgSourceStatus(EpgStatusKind.error, 'ok: odd'),
      );
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
