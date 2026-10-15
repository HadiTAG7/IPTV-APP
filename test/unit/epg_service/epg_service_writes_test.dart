// EpgService database writes stay short: the UI reads through the same
// connection, so an import must not hold it with large transactions or
// statements that scan the whole programme table. All guide data is
// synthetic.
@Timeout(Duration(seconds: 60))
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/net/http.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/epg/epg_models.dart';
import 'package:iptv_player/epg/epg_progress.dart';
import 'package:iptv_player/epg/epg_service.dart';
import 'package:iptv_player/sources/models.dart';

import '../../support/real_http.dart';
import 'support/epg_test_utils.dart';
import 'support/guide_server.dart';

final _now = DateTime.utc(2026, 1, 10, 12);

/// Guide channels linked by tvg-id: more than [EpgDao.idChunk].
const _channels = 250;

/// Hourly programmes per channel, all inside the kept window: more than
/// [EpgService.writeBatchSize] in one parser batch.
const _perChannel = 6;

String _id(int i) => 'ch${i.toString().padLeft(3, '0')}';

/// Every write the database runs, with its arguments.
class _Recorder extends QueryInterceptor {
  final batches = <BatchedStatements>[];
  final writes = <(String, List<Object?>)>[];

  @override
  Future<void> runBatched(QueryExecutor executor, BatchedStatements s) {
    batches.add(s);
    return super.runBatched(executor, s);
  }

  @override
  Future<int> runUpdate(QueryExecutor e, String sql, List<Object?> args) {
    writes.add((sql, args));
    return super.runUpdate(e, sql, args);
  }

  @override
  Future<int> runDelete(QueryExecutor e, String sql, List<Object?> args) {
    writes.add((sql, args));
    return super.runDelete(e, sql, args);
  }

  @override
  Future<void> runCustom(QueryExecutor e, String sql, List<Object?> args) {
    writes.add((sql, args));
    return super.runCustom(e, sql, args);
  }

  void clear() {
    batches.clear();
    writes.clear();
  }
}

void main() {
  useRealHttp();

  test('an import writes in short statements and never scans the programme '
      'table', () async {
    final recorder = _Recorder();
    final clock = FakeClock(_now);
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(
      NativeDatabase.memory().interceptWith(recorder),
      clock: clock,
    );
    final server = await GuideServer.start();
    final service = EpgService(db: db, dioFactory: createDio, clock: clock);
    addTearDown(() async {
      await service.dispose();
      await server.close();
      await db.close();
    });

    String guideDoc({required int channels, required Duration shift}) {
      final from = _now.subtract(const Duration(hours: 2)).add(shift);
      return xmltvDoc([
        for (var i = 0; i < channels; i++) channelXml(_id(i), ['Name $i']),
        for (var i = 0; i < channels; i++) ...hourly(_id(i), from, _perChannel),
      ]);
    }

    final source = await db.sourcesDao.create(
      SourceConfig(
        kind: SourceKind.m3uUrl,
        url: '${server.baseUrl}/list.m3u',
        name: 'Writes test',
      ),
    );
    final guide = await db.epgDao.addEpgSource(
      source,
      '${server.baseUrl}/epg.xml',
      EpgOrigin.m3uHeader,
    );
    // A disabled guide with programmes that ended before now - 12h.
    final old = await db.epgDao.addEpgSource(
      source,
      '${server.baseUrl}/old.xml',
      EpgOrigin.manual,
      enabled: false,
    );
    await db.epgDao.insertProgrammes(old, [
      for (var i = 0; i < _channels; i++)
        for (final hours in [14, 13, 11])
          EpgProgramme(
            channelId: _id(i),
            start: _now.subtract(Duration(hours: hours + 1)),
            stop: _now.subtract(Duration(hours: hours)),
            title: 'Old',
          ),
    ]);
    await syncChannels(db, source, [
      for (var i = 0; i < _channels; i++)
        ChannelData(
          key: 'k$i',
          name: 'Playlist $i',
          tvgId: _id(i),
          categoryKeys: const ['all'],
        ),
    ]);
    server.body = guideDoc(channels: _channels, shift: Duration.zero);
    expect((await runRefresh(service, source)).last, isA<EpgRefreshDone>());

    // New schedule: every slot moves, and the last 10 channels are gone.
    server.body = guideDoc(
      channels: _channels - 10,
      shift: const Duration(minutes: 30),
    );
    recorder.clear();
    final events = await runRefresh(service, source, force: true);
    expect(events.last, isA<EpgRefreshDone>());

    // Programme writes of at most writeBatchSize rows each.
    final inserts = [
      for (final b in recorder.batches)
        for (final a in b.arguments)
          if (b.statements[a.statementIndex].contains('"programmes"')) a,
    ];
    expect(inserts, hasLength((_channels - 10) * _perChannel));
    for (final b in recorder.batches) {
      expect(b.arguments.length, lessThanOrEqualTo(EpgService.writeBatchSize));
    }

    // Deletes find their rows through the primary key, a few ids at a time.
    final deletes = [
      for (final (sql, args) in recorder.writes)
        if (sql.contains('DELETE') && sql.contains('programmes')) (sql, args),
    ];
    expect(deletes, isNotEmpty);
    for (final (sql, args) in deletes) {
      final plan = await db
          .customSelect(
            'EXPLAIN QUERY PLAN $sql',
            variables: [for (final a in args) Variable<Object>(a!)],
          )
          .get();
      final details = [for (final r in plan) r.read<String>('detail')];
      expect(
        details,
        contains(
          startsWith(
            'SEARCH programmes USING PRIMARY KEY '
            '(epg_source_id=? AND xmltv_id=?',
          ),
        ),
        reason: sql,
      );
      expect(details, isNot(contains(startsWith('SCAN programmes'))));
      for (final a in args.whereType<String>()) {
        final ids = switch (jsonDecode(a)) {
          final Map<String, Object?> m => m.length,
          final List<Object?> l => l.length,
          _ => 0,
        };
        expect(ids, lessThanOrEqualTo(EpgDao.idChunk), reason: sql);
      }
    }

    // The result is the new guide, and old data is pruned.
    final stored = await storedProgrammes(db, guide);
    expect(stored, hasLength((_channels - 10) * _perChannel));
    expect(stored.map((p) => fromSec(p.startUtc).minute).toSet(), {30});
    expect(await storedIds(db, guide), hasLength(_channels - 10));
    expect(await guideChannelCount(db, guide), _channels - 10);
    final left = await storedProgrammes(db, old);
    expect(left, hasLength(_channels));
    expect(left.map((p) => fromSec(p.stopUtc)).toSet(), {
      _now.subtract(const Duration(hours: 11)),
    });
  });
}
