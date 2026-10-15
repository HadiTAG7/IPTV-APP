import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/db/queries/guide_queries.dart';
import 'package:iptv_player/epg/epg_models.dart';
import 'package:iptv_player/features/guide/guide_data.dart';
import 'package:iptv_player/features/guide/guide_widgets.dart';
import 'package:iptv_player/features/guide/providers.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/sources/models.dart';

import 'support/guide_fixtures.dart';

ChannelRow _row(int i) => ChannelRow(key: 'k$i', name: 'N$i');

void main() {
  group('GuideChannelPager', () {
    test('pages on demand and keeps a bounded LRU of pages', () async {
      final loads = <int>[];
      final pager = GuideChannelPager(
        count: () async => 1000,
        load: (offset, limit) async {
          loads.add(offset);
          return [for (var i = offset; i < offset + limit; i++) _row(i)];
        },
        pageSize: 100,
        maxPages: 3,
        loadDelay: Duration.zero,
      );
      addTearDown(pager.dispose);
      var notified = 0;
      pager.addListener(() => notified++);
      expect(pager.length, isNull);
      expect(pager.rowAt(0), isNull);

      await pager.init();
      expect(pager.length, 1000);
      expect(loads, [0]);
      expect(pager.rowAt(5)!.key, 'k5');
      expect(notified, greaterThan(0));

      // A row of another page loads it.
      expect(pager.rowAt(250), isNull);
      await pumpEventQueue();
      expect(pager.rowAt(250)!.key, 'k250');
      pager.ensure(300, 450);
      await pumpEventQueue();
      expect(loads, [0, 200, 300, 400]);
      // Only three pages stay: page 0 (least recently used) went first.
      expect(pager.keysIn(0, 1), isEmpty);
      expect(pager.keysIn(449, 451), ['k449', 'k450', 'k451']);
      expect(pager.rowAt(-1), isNull);
      expect(pager.rowAt(1000), isNull);
    });

    test('a scrollbar drag over 50k channels reads only the pages where '
        'it stops', () {
      fakeAsync((async) {
        final loads = <int>[];
        var visible = (first: 0, last: 10);
        final pager = GuideChannelPager(
          count: () async => 50000,
          load: (offset, limit) async {
            loads.add(offset ~/ 200);
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return [for (var i = offset; i < offset + limit; i++) _row(i)];
          },
          window: () => visible,
        );
        unawaited(pager.init());
        async.elapse(const Duration(milliseconds: 100));
        expect(loads, [0]);
        // 60 frames from the top to the bottom, ten rows built per frame.
        for (var frame = 1; frame <= 60; frame++) {
          final first = (49990 * frame / 60).floor();
          visible = (first: first, last: first + 10);
          for (var i = first; i <= first + 10; i++) {
            pager.rowAt(i);
          }
          pager.ensure(first - 20, first + 30);
          async.elapse(const Duration(milliseconds: 16));
        }
        async.elapse(const Duration(milliseconds: 500));
        // Only the destination page, not the 60 pages passed on the way.
        expect(loads, [0, 249]);
        expect(pager.rowAt(49995)!.key, 'k49995');
        expect(pager.loadCount, 2);
        pager.dispose();
      });
    });

    test('reload keeps showing the old rows until their page is read', () {
      fakeAsync((async) {
        var version = 0;
        var count = 30;
        final pager = GuideChannelPager(
          count: () async => count,
          load: (offset, limit) async => [
            for (var i = offset; i < offset + limit && i < count; i++)
              ChannelRow(key: 'k$i', name: 'v$version:$i'),
          ],
          pageSize: 10,
        );
        unawaited(pager.init());
        async.elapse(const Duration(milliseconds: 10));
        pager.rowAt(25);
        async.elapse(const Duration(milliseconds: 200));
        expect(pager.rowAt(5)!.name, 'v0:5');
        version = 1;
        count = 22;
        var notified = 0;
        pager.addListener(() => notified++);
        unawaited(pager.reload());
        async.flushMicrotasks();
        expect(notified, 1);
        expect(pager.length, 22);
        // The old rows stay until the page is read again.
        expect(pager.rowAt(5)!.name, 'v0:5');
        expect(pager.rowAt(21)!.name, 'v0:21');
        async.elapse(const Duration(milliseconds: 200));
        expect(pager.rowAt(5)!.name, 'v1:5');
        expect(pager.rowAt(21)!.name, 'v1:21');
        expect(pager.rowAt(25), isNull);
        pager.dispose();
      });
    });

    test('reload drops late answers', () async {
      var count = 10;
      final pending = <Completer<List<ChannelRow>>>[];
      final pager = GuideChannelPager(
        count: () async => count,
        load: (offset, limit) {
          final c = Completer<List<ChannelRow>>();
          pending.add(c);
          return c.future;
        },
      );
      addTearDown(pager.dispose);
      final first = pager.init();
      await pumpEventQueue();
      count = 2;
      final second = pager.reload();
      await pumpEventQueue();
      pending.first.complete([for (var i = 0; i < 10; i++) _row(i)]);
      pending.last.complete([_row(0), _row(1)]);
      await Future.wait([first, second]);
      expect(pager.length, 2);
      expect(pager.loadedKeys(), ['k0', 'k1']);
    });

    test('errors are kept for the screen', () async {
      final pager = GuideChannelPager(
        count: () async => throw StateError('db'),
        load: (offset, limit) async => const [],
      );
      addTearDown(pager.dispose);
      await pager.init();
      expect(pager.length, isNull);
      expect(pager.error, isA<StateError>());
    });

    test('filters read the catalog in guide order', () async {
      final db = openGuideDb();
      addTearDown(db.close);
      final id = (await seedGuide(db, channels: 30)).sourceId;
      Future<List<String>> keys(
        GuideFilter f, [
        List<String> favs = const [],
      ]) async {
        final pager = GuideChannelPager.forFilter(
          db,
          id,
          f,
          favoriteKeys: () => favs,
        );
        addTearDown(pager.dispose);
        await pager.init();
        pager.ensure(0, (pager.length ?? 0) - 1);
        await pumpEventQueue();
        return pager.loadedKeys();
      }

      expect(await keys(GuideFilter.all), [
        for (var i = 1; i <= 30; i++) 'c$i',
      ]);
      expect(await keys(const GuideFilter.category('news')), [
        for (var i = 1; i <= 10; i++) 'c$i',
      ]);
      expect(await keys(const GuideFilter.category('sports')), hasLength(20));
      // Favourites keep their order; a vanished channel is skipped.
      expect(await keys(GuideFilter.favorites, ['c7', 'gone', 'c2']), [
        'c7',
        'c2',
      ]);
    });
  });

  group('GuideProgrammeStore', () {
    EpgProgramme prog(String key) => EpgProgramme(
      channelId: key,
      start: guideNow,
      stop: guideNow.add(const Duration(hours: 1)),
      title: 'P $key',
    );

    test('debounces requests into one query per block', () {
      fakeAsync((async) {
        final queries = <List<String>>[];
        final store = GuideProgrammeStore((keys, from, to) async {
          queries.add(keys);
          return {
            for (final k in keys.where((k) => k != 'b')) k: [prog(k)],
          };
        });
        var notified = 0;
        store.addListener(() => notified++);
        final from = guideNow;
        final to = guideNow.add(const Duration(hours: 12));

        store.request(['a'], from, to);
        async.elapse(const Duration(milliseconds: 100));
        store.request(['a', 'b'], from, to);
        expect(store.covers(['a', 'b'], from, to), isTrue);
        expect(store.programmesOf('a'), isNull); // not delivered yet
        async.elapse(const Duration(milliseconds: 100));
        expect(queries, isEmpty);
        async.elapse(const Duration(milliseconds: 60));
        expect(queries, [
          ['a', 'b'],
        ]);
        expect(notified, 1);
        expect(store.programmesOf('a')!.single.title, 'P a');
        expect(store.programmesOf('b'), isEmpty); // loaded, no data
        expect(store.programmesOf('c'), isNull); // not in the block
        expect(store.hasRange(from, to), isTrue);
        expect(store.range, (from: from, to: to));
        expect(
          store.hasRange(from.subtract(const Duration(minutes: 1)), to),
          isFalse,
        );
        expect(store.covers(['a', 'c'], from, to), isFalse);
        expect(
          store.covers(['a'], from, to.add(const Duration(hours: 1))),
          isFalse,
        );

        // Immediate requests skip the debounce; reload repeats the block.
        store.request(['c'], from, to, immediate: true);
        async.flushMicrotasks();
        expect(queries.last, ['c']);
        store.reload();
        async.flushMicrotasks();
        expect(queries, hasLength(3));
        expect(store.version, 3);
        store.dispose();
      });
    });

    test('a late answer never replaces a newer block', () async {
      final answers = <Completer<Map<String, List<EpgProgramme>>>>[];
      final store = GuideProgrammeStore((keys, from, to) {
        final c = Completer<Map<String, List<EpgProgramme>>>();
        answers.add(c);
        return c.future;
      });
      addTearDown(store.dispose);
      store.request(['old'], guideNow, guideNow, immediate: true);
      store.request(['new'], guideNow, guideNow, immediate: true);
      answers.last.complete({
        'new': [prog('new')],
      });
      answers.first.complete({
        'old': [prog('old')],
      });
      await pumpEventQueue();
      expect(store.programmesOf('new'), hasLength(1));
      expect(store.programmesOf('old'), isNull);
    });
  });

  group('filters and play requests', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    const news = CategoryRow(
      kind: ContentKind.live,
      key: 'news',
      name: 'News',
      sortIndex: 0,
      itemCount: 3,
      hidden: false,
    );
    const empty = CategoryRow(
      kind: ContentKind.live,
      key: 'empty',
      name: 'Empty',
      sortIndex: 1,
      itemCount: 0,
      hidden: false,
    );

    test('the effective filter falls back sensibly', () {
      expect(effectiveGuideFilter(null, const [], null), GuideFilter.all);
      expect(effectiveGuideFilter(null, ['c1'], null), GuideFilter.favorites);
      const pick = GuideFilter.category('news');
      expect(effectiveGuideFilter(pick, const [], [news]), pick);
      expect(effectiveGuideFilter(pick, const [], null), pick); // loading
      expect(
        effectiveGuideFilter(pick, ['c1'], [empty]),
        GuideFilter.favorites, // the category is gone
      );
      // Favourites while there are any; after the last one, all channels.
      expect(
        effectiveGuideFilter(GuideFilter.favorites, ['c1'], null),
        GuideFilter.favorites,
      );
      expect(
        effectiveGuideFilter(GuideFilter.favorites, const [], [news]),
        GuideFilter.all,
      );
      expect(
        effectiveGuideFilter(GuideFilter.all, ['c1'], null),
        GuideFilter.all,
      );
    });

    test('labels and picker options', () {
      expect(GuideFilter.all.label(l10n, const []), l10n.liveAllChannels);
      expect(GuideFilter.favorites.label(l10n, const []), l10n.liveFavorites);
      expect(const GuideFilter.category('news').label(l10n, [news]), 'News');
      final options = guideFilterOptions(
        l10n,
        favoriteKeys: ['c1', 'c2'],
        categories: [news, empty],
      );
      expect(
        [for (final o in options) o.label],
        [l10n.liveFavorites, l10n.liveAllChannels, 'News'],
      );
      expect(options.first.count, 2);
      expect(
        guideFilterOptions(
          l10n,
          favoriteKeys: const [],
          categories: const [],
        ).single.filter,
        GuideFilter.all,
      );
    });

    test('play requests zap through the same channels', () {
      const channel = ChannelRow(key: 'c2', name: 'Channel 2');
      final fav = guidePlayRequest(
        sourceId: 1,
        channel: channel,
        filter: GuideFilter.favorites,
        favoriteKeys: ['c3', 'c2'],
      );
      expect(fav.zapKeys, ['c3', 'c2']);
      expect(fav.categoryKey, isNull);
      expect(fav.item.key, 'c2');
      expect(fav.title, 'Channel 2');
      final cat = guidePlayRequest(
        sourceId: 1,
        channel: channel,
        filter: const GuideFilter.category('news'),
      );
      expect(cat.categoryKey, 'news');
      expect(cat.zapKeys, isNull);
      final all = guidePlayRequest(
        sourceId: 1,
        channel: channel,
        filter: GuideFilter.all,
      );
      expect(all.categoryKey, isNull);
      expect(all.zapKeys, isNull);
    });
  });

  test('favourite keys leave out channels not in the catalog', () async {
    final db = openGuideDb();
    addTearDown(db.close);
    final seeded = await seedGuide(
      db,
      channels: 5,
      favorites: ['c4', 'gone', 'c2', 'c5'],
    );
    final id = seeded.sourceId;
    final updates = <List<String>>[];
    final sub = db.watchAvailableFavoriteChannelKeys(id).listen(updates.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(updates.single, ['c4', 'c2', 'c5']);

    await db.favoritesDao.setFavorite(id, ContentKind.live, 'c2', false);
    await pumpEventQueue();
    expect(updates.last, ['c4', 'c5']);

    // A sync drops c4; the favourite itself stays (it may come back).
    await resyncChannels(db, id, [
      for (var i = 1; i <= 5; i++)
        if (i != 4) channelData(i),
    ]);
    await pumpEventQueue();
    expect(updates.last, ['c5']);
    expect(await db.favoritesDao.isFavorite(id, ContentKind.live, 'c4'), true);
    // Unrelated writes do not emit the same list again.
    final count = updates.length;
    await db.sourcesDao.markEpgFetched(id, guideNow);
    await pumpEventQueue();
    expect(updates, hasLength(count));
  });

  test('hasGuideData follows imports and disabled guides', () async {
    final db = openGuideDb();
    addTearDown(db.close);
    final seeded = await seedGuide(db, guide: false);
    expect(await db.hasGuideData(seeded.sourceId), isFalse);
    final updates = <bool>[];
    final sub = db.watchHasGuideData(seeded.sourceId).listen(updates.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    final guide = await db.epgDao.addEpgSource(
      seeded.sourceId,
      'http://127.0.0.1:9/g.xml',
      EpgOrigin.manual,
    );
    await db.epgDao.insertProgrammes(guide, programmesFor(1));
    expect(await db.hasGuideData(seeded.sourceId), isFalse); // not linked
    await db.epgDao.replaceChannelMap(seeded.sourceId, {
      'c1': (epgSourceId: guide, xmltvId: 'x.c1', kind: EpgMatchKind.tvgId),
    });
    expect(await db.hasGuideData(seeded.sourceId), isTrue);
    await db.epgDao.setEpgSourceEnabled(guide, false);
    expect(await db.hasGuideData(seeded.sourceId), isFalse);
    await db.epgDao.setEpgSourceEnabled(guide, true);
    await pumpEventQueue();
    expect(updates.first, isFalse);
    expect(updates.last, isTrue);
  });
}
