import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/time/clock.dart';

import 'db_test_utils.dart';

Matcher _nameError(ChannelListNameError error) =>
    isA<ChannelListNameException>().having((e) => e.error, 'error', error);

void main() {
  late FakeClock clock;
  late AppDatabase db;
  late ChannelListsDao dao;
  late int src;

  setUp(() async {
    clock = FakeClock(testEpoch);
    db = openTestDb(clock: clock);
    dao = db.channelListsDao;
    src = await addSource(db);
    await syncCatalog(
      db,
      src,
      channels: [channel('a'), channel('b'), channel('c'), channel('d')],
    );
  });

  tearDown(() => db.close());

  Future<List<(String, int)>> listsOf(int sourceId) async => [
    for (final l in await dao.lists(sourceId)) (l.name, l.count),
  ];

  /// Raw (key, position) rows of a list, by position.
  Future<List<(String, int)>> positions(int listId) async {
    final rows = await db
        .customSelect(
          'SELECT "key" AS k, position AS p FROM channel_list_items '
          'WHERE list_id = ?1 ORDER BY position',
          variables: [Variable.withInt(listId)],
        )
        .get();
    return [for (final r in rows) (r.read<String>('k'), r.read<int>('p'))];
  }

  group('lists', () {
    test('create trims, appends and refuses empty or taken names', () async {
      final sports = await dao.createList(src, '  Sports ');
      final news = await dao.createList(src, 'الأخبار');
      expect(await listsOf(src), [('Sports', 0), ('الأخبار', 0)]);
      final rows = await dao.lists(src);
      expect(rows.map((l) => (l.id, l.position)), [(sports, 0), (news, 1)]);
      expect(rows.first.sourceId, src);
      expect((await dao.listById(sports))?.createdAt, toEpochSec(testEpoch));

      await expectLater(
        dao.createList(src, '   '),
        throwsA(_nameError(ChannelListNameError.empty)),
      );
      await expectLater(
        dao.createList(src, 'sPORTS'),
        throwsA(_nameError(ChannelListNameError.taken)),
      );
      await expectLater(
        dao.createList(src, ' الأخبار'),
        throwsA(_nameError(ChannelListNameError.taken)),
      );
      expect(await dao.lists(src), hasLength(2));

      // Names are per source.
      final other = await addSource(db, name: 'Other');
      await dao.createList(other, 'Sports');
      expect(await listsOf(other), [('Sports', 0)]);
    });

    test('create can start with channels, in order', () async {
      final id = await dao.createList(src, 'Mix', channels: ['c', 'a', 'c']);
      expect(await dao.channelKeys(id), ['c', 'a']);
      expect(await positions(id), [('c', 0), ('a', 1)]);
      expect(await listsOf(src), [('Mix', 2)]);
    });

    test('rename trims and refuses empty or taken names', () async {
      final sports = await dao.createList(src, 'Sports');
      await dao.createList(src, 'News');
      await dao.renameList(sports, ' Football  ');
      expect(await listsOf(src), [('Football', 0), ('News', 0)]);
      // Its own name, in another case, is fine.
      await dao.renameList(sports, 'FOOTBALL');
      expect((await dao.listById(sports))?.name, 'FOOTBALL');
      await expectLater(
        dao.renameList(sports, 'news'),
        throwsA(_nameError(ChannelListNameError.taken)),
      );
      await expectLater(
        dao.renameList(sports, ''),
        throwsA(_nameError(ChannelListNameError.empty)),
      );
      expect((await dao.listById(sports))?.name, 'FOOTBALL');
      // A missing list is ignored.
      await dao.renameList(9999, 'Ghost');
      expect(await dao.lists(src), hasLength(2));
    });

    test('delete removes the list and its channels only', () async {
      final sports = await dao.createList(src, 'Sports', channels: ['a', 'b']);
      final news = await dao.createList(src, 'News', channels: ['a']);
      await dao.deleteList(sports);
      expect(await listsOf(src), [('News', 1)]);
      expect(await dao.listById(sports), isNull);
      expect(await dao.channelKeys(sports), isEmpty);
      expect(await countRows(db, 'channel_list_items'), 1);
      expect(await dao.channelKeys(news), ['a']);
      // The channels themselves stay in the catalog and in the favourites.
      expect(await db.catalogDao.channelByKey(src, 'a'), isNotNull);
    });

    test('reorder rewrites positions, only for the source', () async {
      final a = await dao.createList(src, 'A');
      final b = await dao.createList(src, 'B');
      final c = await dao.createList(src, 'C');
      final other = await addSource(db, name: 'Other');
      final x = await dao.createList(other, 'X');
      await dao.reorderLists(src, [c, a, b, x]);
      expect((await dao.lists(src)).map((l) => l.name), ['C', 'A', 'B']);
      expect((await dao.listById(x))?.position, 0);
      // New lists still go last.
      await dao.createList(src, 'D');
      expect((await dao.lists(src)).map((l) => l.name), ['C', 'A', 'B', 'D']);
    });

    test('watchLists emits names and counts after every change', () async {
      final seen = <List<(String, int)>>[];
      final sub = dao
          .watchLists(src)
          .listen(
            (rows) => seen.add([for (final l in rows) (l.name, l.count)]),
          );
      await pumpEventQueue();
      final sports = await dao.createList(src, 'Sports');
      await pumpEventQueue();
      await dao.setChannel(sports, 'a', true);
      await pumpEventQueue();
      await dao.renameList(sports, 'Football');
      await pumpEventQueue();
      await dao.deleteList(sports);
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [
        <(String, int)>[],
        [('Sports', 0)],
        [('Sports', 1)],
        [('Football', 1)],
        <(String, int)>[],
      ]);
    });
  });

  group('channels', () {
    late int list;

    setUp(() async => list = await dao.createList(src, 'Sports'));

    test('adding appends; adding twice keeps the first position', () async {
      for (final k in ['c', 'a', 'b']) {
        await dao.setChannel(list, k, true);
        clock.advance(const Duration(seconds: 1));
      }
      await dao.setChannel(list, 'c', true);
      expect(await dao.channelKeys(list), ['c', 'a', 'b']);
      expect(await positions(list), [('c', 0), ('a', 1), ('b', 2)]);
      final page = await dao.channelsPage(list);
      expect(page.first.addedAt, testEpoch);
      expect(page.last.addedAt, testEpoch.add(const Duration(seconds: 2)));
      // Adding to a list that does not exist does nothing.
      await dao.setChannel(9999, 'a', true);
      expect(await countRows(db, 'channel_list_items'), 3);
    });

    test('removing closes the gap; new channels still go last', () async {
      for (final k in ['a', 'b', 'c', 'd']) {
        await dao.setChannel(list, k, true);
      }
      await dao.setChannel(list, 'b', false);
      expect(await positions(list), [('a', 0), ('c', 1), ('d', 2)]);
      await dao.setChannel(list, 'a', false);
      await dao.setChannel(list, 'missing', false);
      expect(await positions(list), [('c', 0), ('d', 1)]);
      await dao.setChannel(list, 'b', true);
      expect(await positions(list), [('c', 0), ('d', 1), ('b', 2)]);
    });

    test('toggle flips and reports the new state', () async {
      expect(await dao.toggleChannel(list, 'a'), isTrue);
      expect(await dao.contains(list, 'a'), isTrue);
      expect(await dao.toggleChannel(list, 'b'), isTrue);
      expect(await dao.toggleChannel(list, 'a'), isFalse);
      expect(await dao.contains(list, 'a'), isFalse);
      expect(await positions(list), [('b', 0)]);
    });

    test('move swaps with a neighbour within the bounds', () async {
      for (final k in ['a', 'b', 'c']) {
        await dao.setChannel(list, k, true);
      }
      expect(await dao.moveChannel(list, 'c', -1), isTrue);
      expect(await dao.channelKeys(list), ['a', 'c', 'b']);
      expect(await dao.moveChannel(list, 'a', 1), isTrue);
      expect(await dao.channelKeys(list), ['c', 'a', 'b']);
      expect(await dao.moveChannel(list, 'c', -1), isFalse);
      expect(await dao.moveChannel(list, 'b', 1), isFalse);
      expect(await dao.moveChannel(list, 'missing', 1), isFalse);
      expect(await positions(list), [('c', 0), ('a', 1), ('b', 2)]);
      await dao.reorderChannels(list, ['b', 'c', 'a']);
      expect(await dao.channelKeys(list), ['b', 'c', 'a']);
    });

    test('membership lists the source lists holding a channel', () async {
      final news = await dao.createList(src, 'News');
      final other = await addSource(db, name: 'Other');
      final foreign = await dao.createList(other, 'Foreign');
      await dao.setChannel(list, 'a', true);
      await dao.setChannel(news, 'a', true);
      await dao.setChannel(foreign, 'a', true);
      expect(await dao.listsWithChannel(src, 'a'), {list, news});
      expect(await dao.listsWithChannel(src, 'b'), isEmpty);
      expect(await dao.listsWithChannel(other, 'a'), {foreign});

      final seen = <Set<int>>[];
      final sub = dao.watchListsWithChannel(src, 'b').listen(seen.add);
      await pumpEventQueue();
      await dao.setChannel(news, 'b', true);
      await pumpEventQueue();
      await dao.deleteList(news);
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [
        <int>{},
        {news},
        <int>{},
      ]);
    });

    test('watchChannelKeys emits the order after every change', () async {
      final seen = <List<String>>[];
      final sub = dao.watchChannelKeys(list).listen(seen.add);
      await pumpEventQueue();
      await dao.setChannel(list, 'a', true);
      await pumpEventQueue();
      await dao.setChannel(list, 'b', true);
      await pumpEventQueue();
      await dao.moveChannel(list, 'b', -1);
      await pumpEventQueue();
      await dao.deleteList(list);
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [
        <String>[],
        ['a'],
        ['a', 'b'],
        ['b', 'a'],
        <String>[],
      ]);
    });

    test('pages join the catalog of the list source; gone channels are '
        'unavailable', () async {
      final other = await addSource(db, name: 'Other');
      await syncCatalog(db, other, channels: [channel('x', name: 'Other x')]);
      for (final k in ['b', 'gone', 'x', 'a']) {
        await dao.setChannel(list, k, true);
      }
      final page = await dao.channelsPage(list);
      expect(page.map((i) => (i.key, i.available)), [
        ('b', true),
        ('gone', false),
        // Another source's channel is not this source's.
        ('x', false),
        ('a', true),
      ]);
      expect(page.first.item?.name, 'Channel b');
      expect(
        (await dao.channelsPage(list, offset: 1, limit: 2)).map((i) => i.key),
        ['gone', 'x'],
      );
      expect(await dao.channelsPage(list, limit: 0), isEmpty);
      expect(
        (await dao.channelsPage(list, offset: -3, limit: 1)).single.key,
        'b',
      );
    });

    test('a catalog refresh keeps the lists; channels come and go', () async {
      for (final k in ['a', 'b', 'c']) {
        await dao.setChannel(list, k, true);
      }
      // The next sync drops b and renames a.
      await syncCatalog(
        db,
        src,
        channels: [
          channel('a', name: 'Renamed a'),
          channel('c'),
          channel('d'),
        ],
      );
      expect(await dao.channelKeys(list), ['a', 'b', 'c']);
      var page = await dao.channelsPage(list);
      expect(page.map((i) => (i.key, i.item?.name)), [
        ('a', 'Renamed a'),
        ('b', null),
        ('c', 'Channel c'),
      ]);
      // b comes back in a later sync.
      await syncCatalog(db, src, channels: [channel('a'), channel('b')]);
      page = await dao.channelsPage(list);
      expect(page.map((i) => i.available), [true, true, false]);
      expect(await listsOf(src), [('Sports', 3)]);
    });

    test('deleting the source deletes its lists and their channels', () async {
      final other = await addSource(db, name: 'Other');
      final kept = await dao.createList(other, 'Kept', channels: ['x']);
      await dao.setChannel(list, 'a', true);
      await db.sourcesDao.deleteSource(src);
      expect(await dao.lists(src), isEmpty);
      expect(await dao.listById(list), isNull);
      expect(await dao.channelKeys(list), isEmpty);
      expect(await dao.channelKeys(kept), ['x']);
      expect(await countRows(db, 'channel_lists'), 1);
      expect(await countRows(db, 'channel_list_items'), 1);
    });
  });
}
