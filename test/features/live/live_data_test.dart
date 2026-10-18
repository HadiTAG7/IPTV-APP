// Unit tests for the Live data layer: list sources, the pager, the now/next
// store and the extra queries.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/db/queries/live_queries.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/epg/epg_models.dart';
import 'package:iptv_player/features/live/channel_pager.dart';
import 'package:iptv_player/features/live/channel_source.dart';
import 'package:iptv_player/features/live/live_models.dart';
import 'package:iptv_player/features/live/now_next_store.dart';
import 'package:iptv_player/player/ui/play_request.dart';
import 'package:iptv_player/sources/models.dart';

import 'support/live_test_utils.dart';

/// A source of [length] synthetic rows that counts page reads.
class _CountingSource extends ChannelListSource {
  _CountingSource(AppDatabase db, this.length) : super(db, 1);

  final int length;
  final reads = <int>[];
  String prefix = 'c';

  @override
  LiveList get list => const LiveList.all();

  @override
  Future<int> count() async => length;

  @override
  Future<List<LiveEntry>> page(int offset, int limit) async {
    reads.add(offset);
    final end = offset + limit > length ? length : offset + limit;
    return [
      for (var i = offset; i < end; i++)
        LiveEntry('$prefix$i', ChannelRow(key: '$prefix$i', name: 'Row $i')),
    ];
  }

  @override
  Future<int?> indexOfKey(String key) async => int.tryParse(key.substring(1));

  @override
  Future<PlayRequest> requestFor(ChannelRow channel) async =>
      PlayRequest(sourceId: 1, item: channel.toPlayable());
}

void main() {
  group('LiveList', () {
    test('ids round-trip', () {
      for (final list in [
        const LiveList.favorites(),
        const LiveList.recent(),
        const LiveList.all(),
        const LiveList.category('cat:with:colons'),
        const LiveList.channelList(7),
      ]) {
        expect(LiveList.fromId(list.id), list);
      }
      expect(const LiveList.channelList(7).id, 'list:7');
      expect(const LiveList.channelList(7).isChannelList, isTrue);
      expect(const LiveList.channelList(7).isCategory, isFalse);
      expect(
        const LiveList.channelList(7),
        isNot(const LiveList.channelList(8)),
      );
      expect(LiveList.fromId(null), isNull);
      expect(LiveList.fromId('cat:'), isNull);
      expect(LiveList.fromId('list:'), isNull);
      expect(LiveList.fromId('list:x'), isNull);
      expect(LiveList.fromId('nope'), isNull);
    });
  });

  group('queries', () {
    late AppDatabase db;
    late int id;

    setUp(() async {
      db = openAppTestDb();
      id = await addTestSource(db);
      await seedCatalog(
        db,
        id,
        categories: [liveCategory('c', 'C', 0)],
        channels: [
          testChannel(5, name: 'Echo', categories: ['c']),
          testChannel(1, name: 'Bravo', categories: ['c']),
          const ChannelData(
            key: 'dup-b',
            name: 'Beta',
            num: 1,
            categoryKeys: ['c'],
          ),
          testChannel(9, name: 'Zulu', numbered: false, categories: ['c']),
          testChannel(8, name: 'Alpha', numbered: false, categories: ['c']),
          testChannel(3, name: 'قناة', categories: ['c']),
        ],
      );
    });

    tearDown(() => db.close());

    test('allChannelsIndexOf follows the all-channels order', () async {
      final page = await db.catalogDao.allChannelsPage(id, 0, 100);
      for (final (i, row) in page.indexed) {
        expect(await db.allChannelsIndexOf(id, row.key), i, reason: row.key);
      }
      expect(await db.allChannelsIndexOf(id, 'missing'), isNull);
    });

    test('liveKeysWithNumber lists every channel with that number', () async {
      expect(await db.liveKeysWithNumber(id, 1), ['dup-b', 'k1']);
      expect(await db.liveKeysWithNumber(id, 42), isEmpty);
    });

    test('sources find numbers and keys', () async {
      final all = channelSourceFor(db, id, const LiveList.all());
      expect(await all.count(), 6);
      expect(await all.indexOfNumber(1), 0);
      expect(await all.indexOfNumber(3), 2);
      expect(await all.indexOfNumber(7), isNull);
      final cat = channelSourceFor(db, id, const LiveList.category('c'));
      expect(await cat.count(), 6);
      expect(await cat.indexOfNumber(5), 0);
      expect((await cat.page(0, 2)).map((e) => e.key), ['k5', 'k1']);
      final req = await cat.requestFor((await cat.page(1, 1)).single.row!);
      expect(req.categoryKey, 'c');
      expect(req.zapKeys, isNull);
    });

    test('favourites zap through the channels that still exist', () async {
      await db.favoritesDao.setFavorite(id, ContentKind.live, 'k3', true);
      await db.favoritesDao.setFavorite(id, ContentKind.live, 'gone', true);
      await db.favoritesDao.setFavorite(id, ContentKind.live, 'k1', true);
      final fav = channelSourceFor(db, id, const LiveList.favorites());
      expect(await fav.count(), 3);
      final entries = await fav.page(0, 10);
      expect([for (final e in entries) e.available], [true, false, true]);
      expect(await fav.indexOfKey('k1'), 2);
      final req = await fav.requestFor(entries.first.row!);
      expect(req.zapKeys, ['k3', 'k1']);
    });

    test('a channel list pages in list order and zaps through the channels '
        'that still exist', () async {
      final dao = db.channelListsDao;
      final listId = await dao.createList(
        id,
        'Sports',
        channels: ['k5', 'gone', 'k3', 'k1'],
      );
      final source = channelSourceFor(db, id, LiveList.channelList(listId));
      expect(source, isA<ListChannelsSource>());
      expect(source.list, LiveList.channelList(listId));
      expect(await source.count(), 4);
      final entries = await source.page(0, 10);
      expect([for (final e in entries) e.key], ['k5', 'gone', 'k3', 'k1']);
      expect([for (final e in entries) e.available], [true, false, true, true]);
      expect((await source.page(2, 1)).single.row?.name, 'قناة');
      expect(await source.indexOfKey('k3'), 2);
      expect(await source.indexOfKey('k9'), isNull);
      expect(await source.indexOfNumber(1), 3);
      final req = await source.requestFor(entries[2].row!);
      expect(req.item.key, 'k3');
      expect(req.categoryKey, isNull);
      expect(req.zapKeys, ['k5', 'k3', 'k1']);
    });
  });

  group('ChannelPager', () {
    late AppDatabase db;

    setUp(() => db = openAppTestDb());
    tearDown(() => db.close());

    test('loads the first page at once and later pages after a pause', () {
      fakeAsync((async) {
        final source = _CountingSource(db, 5000);
        final pager = ChannelPager(source, 5000);
        expect(pager.entryAt(0), isNull);
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        expect(pager.entryAt(0)?.key, 'c0');
        expect(source.reads, [0]);

        // A fling asks for many pages; only the ones still wanted after
        // the pause, near the window, are read.
        RowWindow window = (first: 0, last: 9);
        final flung = ChannelPager(source, 5000, window: () => window);
        flung.entryAt(0);
        async.elapse(Duration.zero);
        source.reads.clear();
        for (var i = 200; i < 4000; i += 200) {
          flung.entryAt(i);
          async.elapse(const Duration(milliseconds: 20));
        }
        window = (first: 3800, last: 3809);
        async.elapse(const Duration(milliseconds: 200));
        // The page holding the window plus a 20-row margin above it.
        expect(source.reads, [3600, 3800]);
        expect(flung.loadedPages, {0, 18, 19});
        pager.dispose();
        flung.dispose();
      });
    });

    test('reads only pages near the window and keeps at most maxPages', () {
      fakeAsync((async) {
        final source = _CountingSource(db, 5000);
        const window = (first: 0, last: 9);
        final pager = ChannelPager(source, 5000, window: () => window);
        pager.entryAt(0);
        async.elapse(Duration.zero);
        for (final p in [5, 6, 7, 8]) {
          pager.entryAt(p * 200);
        }
        async.elapse(const Duration(seconds: 1));
        expect(pager.loadedPages, {0});

        final lru = ChannelPager(source, 5000, maxPages: 3);
        for (final p in [0, 1, 2, 3, 4]) {
          lru.entryAt(p * 200);
          async.elapse(const Duration(seconds: 1));
        }
        expect(lru.loadedPages, {2, 3, 4});
        // Reading a page makes it the most recently used.
        lru.entryAt(2 * 200);
        lru.entryAt(5 * 200);
        async.elapse(const Duration(seconds: 1));
        expect(lru.loadedPages, {2, 4, 5});
        pager.dispose();
        lru.dispose();
      });
    });

    test('reset keeps old rows until the page reloads', () {
      fakeAsync((async) {
        final source = _CountingSource(db, 300);
        final pager = ChannelPager(source, 300);
        pager.entryAt(0);
        async.elapse(Duration.zero);
        expect(pager.entryAt(5)?.key, 'c5');
        source.prefix = 'n';
        pager.reset(250);
        expect(pager.length, 250);
        expect(pager.entryAt(5)?.key, 'c5', reason: 'stale until reloaded');
        async.elapse(const Duration(seconds: 1));
        expect(pager.entryAt(5)?.key, 'n5');
        pager.dispose();
      });
    });
  });

  group('NowNextStore', () {
    EpgProgramme p(String title, DateTime start, int minutes) => EpgProgramme(
      channelId: 'x',
      start: start,
      stop: start.add(Duration(minutes: minutes)),
      title: title,
    );

    test('one query once the rows have been still for 150 ms', () {
      fakeAsync((async) {
        final calls = <List<String>>[];
        final clock = FakeClock(testNow);
        final store = NowNextStore(
          clock: clock,
          load: (keys, now) async {
            calls.add(keys);
            return {
              for (final k in keys)
                if (k != 'none') k: (now: p('Now $k', now, 30), next: null),
            };
          },
        );
        var notified = 0;
        store.addListener(() => notified++);
        store.showing(['a', 'b']);
        async.elapse(const Duration(milliseconds: 100));
        store.showing(['b', 'c', 'none']);
        async.elapse(const Duration(milliseconds: 149));
        expect(calls, isEmpty);
        async.elapse(const Duration(milliseconds: 2));
        expect(calls, [
          ['b', 'c', 'none'],
        ]);
        expect(store['b']?.now?.title, 'Now b');
        expect(store['none'], isNull);
        expect(store.has('none'), isTrue);
        expect(notified, 1);

        // Known rows are not queried again; new ones are.
        store.showing(['b', 'd']);
        async.elapse(const Duration(milliseconds: 200));
        expect(calls.last, ['d']);

        // Once the current programme is over it counts as missing.
        clock.advance(const Duration(minutes: 31));
        store.showing(['b', 'd']);
        async.elapse(const Duration(milliseconds: 200));
        expect(calls.last, ['b', 'd']);

        // The minute refresh re-reads the rows on screen and pinned keys.
        store.pin('z');
        async.flushMicrotasks();
        expect(calls.last, ['z']);
        final before = calls.length;
        async.elapse(const Duration(minutes: 1));
        expect(calls.length, before + 1);
        expect(calls.last.toSet(), {'b', 'd', 'z'});
        store.dispose();
        async.elapse(const Duration(minutes: 5));
        expect(calls.length, before + 1);
      });
    });

    test('reload re-reads the rows on screen and pinned, drops the rest, '
        'and keeps the shown values until the new ones arrive', () {
      fakeAsync((async) {
        var title = 'Old';
        final calls = <List<String>>[];
        final store = NowNextStore(
          clock: FakeClock(testNow),
          load: (keys, now) async {
            calls.add(keys);
            return {
              for (final k in keys)
                k: (now: p('$title $k', now, 30), next: null),
            };
          },
        );
        store.showing(['a', 'b']);
        async.elapse(const Duration(milliseconds: 200));
        store.showing(['c']);
        async.elapse(const Duration(milliseconds: 200));
        store.pin('a');
        expect(store['b']?.now?.title, 'Old b');

        // A guide refresh imported new programmes.
        title = 'New';
        unawaited(store.reload());
        expect(store['a']?.now?.title, 'Old a', reason: 'until read again');
        expect(store.has('b'), isFalse, reason: 'neither visible nor pinned');
        async.flushMicrotasks();
        expect(calls.last.toSet(), {'a', 'c'});
        expect(store['a']?.now?.title, 'New a');
        expect(store['c']?.now?.title, 'New c');
        store.dispose();
      });
    });

    test('programmeProgress', () {
      final start = DateTime.utc(2026, 1, 1, 10);
      final show = p('x', start, 60);
      expect(programmeProgress(null, start), isNull);
      expect(programmeProgress(show, start), 0);
      expect(
        programmeProgress(show, start.add(const Duration(minutes: 15))),
        0.25,
      );
      expect(programmeProgress(show, start.add(const Duration(hours: 2))), 1);
    });
  });
}
