// Query plans of hot paths: paged lists must walk an index instead of
// sorting the whole table, and guide deletes must not scan the EPG map.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/sources/models.dart';

import 'db_test_utils.dart';

/// Remembers the last SELECT reaching SQLite.
class _LastSelect extends QueryInterceptor {
  String? sql;
  List<Object?> args = const [];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    sql = statement;
    this.args = args;
    return super.runSelect(executor, statement, args);
  }
}

void main() {
  late _LastSelect last;
  late AppDatabase db;
  late int src;

  setUp(() async {
    last = _LastSelect();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(
      NativeDatabase.memory().interceptWith(last),
      clock: FakeClock(testEpoch),
    );
    src = await addSource(db);
    await syncCatalog(
      db,
      src,
      channels: [for (var i = 0; i < 20; i++) channel('c$i', num: i)],
      movies: [for (var i = 0; i < 20; i++) movie('m$i')],
      seriesList: [for (var i = 0; i < 20; i++) series('s$i')],
    );
  });

  tearDown(() => db.close());

  Future<String> plan(String sql, List<Object?> args) async {
    final rows = await db
        .customSelect(
          'EXPLAIN QUERY PLAN $sql',
          variables: [
            for (final a in args)
              switch (a) {
                final int i => Variable.withInt(i),
                final String s => Variable.withString(s),
                _ => const Variable<Object>(null),
              },
          ],
        )
        .get();
    return [for (final r in rows) r.read<String>('detail')].join('\n');
  }

  Future<String> planOfLastSelect() => plan(last.sql!, last.args);

  test('list pages read in index order', () async {
    await db.catalogDao.allChannelsPage(src, 10, 5);
    final channels = await planOfLastSelect();
    expect(channels, contains('channels_num'));
    expect(channels, isNot(contains('TEMP B-TREE')));

    await db.catalogDao.allMoviesPage(src, 10, 5);
    final movies = await planOfLastSelect();
    expect(movies, contains('movies_name'));
    expect(movies, isNot(contains('TEMP B-TREE')));

    await db.catalogDao.allSeriesPage(src, 10, 5);
    final series = await planOfLastSelect();
    expect(series, contains('series_name'));
    expect(series, isNot(contains('TEMP B-TREE')));

    await db.catalogDao.channelsPage(src, 'news', 10, 5);
    expect(await planOfLastSelect(), isNot(contains('SCAN')));
  });

  test('guide map lookups by guide source use an index', () async {
    final guide = await db.epgDao.addEpgSource(
      src,
      'http://127.0.0.1:8080/guide.xml',
      EpgOrigin.manual,
    );
    await db.epgDao.linkedXmltvIds(guide);
    expect(await planOfLastSelect(), contains('channel_epg_map_guide'));
    // What the FK cascade runs when a guide source is deleted.
    final cascade = await plan(
      'DELETE FROM channel_epg_map WHERE epg_source_id = ?',
      [guide],
    );
    expect(cascade, contains('channel_epg_map_guide'));
    expect(cascade, isNot(contains('SCAN channel_epg_map')));
  });
}
