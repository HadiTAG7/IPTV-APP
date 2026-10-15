@Timeout(Duration(seconds: 90))
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/core/secure/secret_store.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/sources/source_adapter.dart';
import 'package:iptv_player/sources/source_repository.dart';
import 'package:iptv_player/sources/sync/sync_service.dart';

import '../../support/fake_panel.dart';
import '../../support/real_http.dart';
import '../db/db_test_utils.dart';

const _user = 'syncUser';
const _pass = 'Sync-Pw-4410';

void main() {
  useRealHttp();

  late FakePanel panel;
  late AppDatabase db;
  late FakeClock clock;
  late SourceRepository repo;
  late RingLog log;
  final services = <SyncService>[];

  setUp(() async {
    panel = await FakePanel.start(
      username: _user,
      password: _pass,
      mediaDir: null,
      liveCount: 40,
      vodCount: 12,
      seriesCount: 5,
    );
    clock = FakeClock(DateTime.utc(2026, 10, 15, 9));
    db = openTestDb(clock: clock);
    log = RingLog();
    repo = SourceRepository(db, DbSecretStore(db), clock: clock, log: log);
  });

  tearDown(() async {
    for (final s in services) {
      s.dispose();
    }
    services.clear();
    await panel.close();
    await db.close();
  });

  SyncService service({
    SourceAdapter Function(SourceConfig config)? adapters,
    SyncRunner? runner,
    void Function(int sourceId)? onSynced,
  }) {
    final s = SyncService(
      db,
      repo,
      clock: clock,
      runner: runner ?? InlineSyncRunner(adapters ?? repo.adapterFor),
      onSynced: onSynced,
      log: log,
    );
    services.add(s);
    return s;
  }

  Future<int> addXtream() => repo.add(
    SourceConfig(
      kind: SourceKind.xtream,
      url: panel.baseUrl,
      name: 'Panel',
      username: _user,
      password: _pass,
    ),
  );

  Future<int> count(int id, ContentKind kind) =>
      db.catalogDao.totalCount(id, kind);

  group('Xtream', () {
    test('a full sync matches the panel catalog', () async {
      final id = await addXtream();
      final synced = <int>[];
      final sync = service(onSynced: synced.add);
      final notified = sync.syncedSources.first;
      final events = <SyncProgress>[];
      final done = await sync.sync(id).map((p) {
        events.add(p);
        return p;
      }).last;

      final catalog = panel.catalog;
      expect(done.phase, SyncPhase.done, reason: '${done.error}');
      expect(done.channels, catalog.live.length);
      expect(done.movies, catalog.movies.length);
      expect(done.series, catalog.series.length);
      expect(done.episodes, 0); // Xtream episodes load per series.
      expect(await count(id, ContentKind.live), catalog.live.length);
      expect(await count(id, ContentKind.movie), catalog.movies.length);
      expect(await count(id, ContentKind.series), catalog.series.length);
      expect(
        (await db.catalogDao.categories(id, ContentKind.live)).length,
        catalog.liveCategories.length,
      );
      expect(events.first.phase, SyncPhase.verifying);
      expect(events.map((e) => e.phase), contains(SyncPhase.live));
      expect(events.map((e) => e.phase), contains(SyncPhase.saving));

      final row = (await db.sourcesDao.byId(id))!;
      expect(row.accountStatus, AccountStatus.active);
      expect(row.maxConnections, 1);
      expect(row.allowedFormats, containsAll(['ts', 'm3u8']));
      expect(row.expiresAt, isNotNull);
      expect(row.lastSyncAt, clock.now());
      expect(row.generation, greaterThan(0));
      expect(await db.catalogDao.openGenerationOf(id), isNull);

      // The guide URL is stored masked, the full one as a secret.
      final epg = await db.epgDao.epgSources(id);
      expect(epg, hasLength(1));
      expect(epg.single.origin, EpgOrigin.xtream);
      expect(epg.single.url, isNot(contains(_pass)));
      expect(await db.epgDao.epgSourceUrl(epg.single.id), panel.xmltvUrl);

      expect(synced, [id]);
      expect(await notified, id);
      expect(sync.statusOf(id), isA<SyncDone>());
      expect(sync.isRunning(id), isFalse);
      expect(log.dump(), isNot(contains(_pass)));
    });

    test('favourites, progress and prefs survive a second sync', () async {
      final id = await addXtream();
      final sync = service();
      expect((await sync.syncAndWait(id)).isDone, isTrue);
      final first = (await db.sourcesDao.byId(id))!.generation;
      final ch = '${panel.catalog.live.first.id}';
      final mv = '${panel.catalog.movies.first.id}';
      final sr = '${panel.catalog.series.first.id}';
      await db.favoritesDao.toggleFavorite(id, ContentKind.live, ch);
      await db.favoritesDao.toggleFavorite(id, ContentKind.movie, mv);
      await db.favoritesDao.toggleFavorite(id, ContentKind.series, sr);
      await db.progressDao.saveProgress(
        id,
        PlayableKind.movie,
        mv,
        5000,
        900000,
      );
      await db.prefsDao.setEngine(id, ch, EngineKind.mpv);
      await db.recentDao.markRecent(id, ch);

      clock.advance(const Duration(hours: 25));
      expect((await sync.syncAndWait(id)).isDone, isTrue);
      final row = (await db.sourcesDao.byId(id))!;
      expect(row.generation, greaterThan(first));
      expect(row.lastSyncAt, clock.now());
      expect(await db.favoritesDao.favoriteKeys(id, ContentKind.live), [ch]);
      final favs = await db.favoritesDao.favoriteChannelsPage(id);
      expect(favs.single.available, isTrue);
      expect(
        await db.favoritesDao.isFavorite(id, ContentKind.movie, mv),
        isTrue,
      );
      expect(
        await db.favoritesDao.isFavorite(id, ContentKind.series, sr),
        isTrue,
      );
      expect(
        (await db.progressDao.progressFor(
          id,
          PlayableKind.movie,
          mv,
        ))?.position,
        const Duration(seconds: 5),
      );
      expect((await db.prefsDao.prefsFor(id, ch)).engine, EngineKind.mpv);
      expect(await db.recentDao.recentChannelKeys(id), [ch]);
      expect(await count(id, ContentKind.live), panel.catalog.live.length);
    });

    test('a failure mid-stream keeps the previous generation', () async {
      final id = await addXtream();
      expect((await service().syncAndWait(id)).isDone, isTrue);
      final before = (await db.sourcesDao.byId(id))!;
      final channels = await db.catalogDao.allChannelsPage(id, 0, 100);

      // Channels are downloaded, then the connection drops before the live
      // family is complete.
      final flaky = service(
        adapters: (c) => _FlakyAdapter(
          repo.adapterFor(c),
          failOn: (b) => b is PhaseDoneBatch && b.kind == ContentKind.live,
        ),
      );
      final result = await flaky.syncAndWait(id);
      expect(result.phase, SyncPhase.failed);
      expect(result.error!.reason, VerifyErrorReason.unreachable);
      expect(result.channels, greaterThan(0));
      expect(flaky.statusOf(id), isA<SyncFailed>());

      final after = (await db.sourcesDao.byId(id))!;
      expect(after.generation, before.generation);
      expect(after.lastSyncAt, before.lastSyncAt);
      expect(await db.catalogDao.openGenerationOf(id), isNull);
      expect(
        (await db.catalogDao.allChannelsPage(id, 0, 100)).map((c) => c.key),
        channels.map((c) => c.key),
      );
      expect(await count(id, ContentKind.movie), panel.catalog.movies.length);
    });

    test('live is committed first; a later failure keeps it', () async {
      final id = await addXtream();
      final seen = <ContentKind, int>{};
      final result = await service(
        adapters: (c) => _FlakyAdapter(
          repo.adapterFor(c),
          before: (b) async {
            if (b is MoviesBatch && seen.isEmpty) {
              seen[ContentKind.live] = await count(id, ContentKind.live);
              seen[ContentKind.movie] = await count(id, ContentKind.movie);
            }
          },
          failOn: (b) => b is SeriesBatch,
        ),
      ).syncAndWait(id);
      final catalog = panel.catalog;
      // Channels were visible while movies were still downloading.
      expect(seen, {
        ContentKind.live: catalog.live.length,
        ContentKind.movie: 0,
      });
      expect(result.phase, SyncPhase.failed);
      expect(result.error!.reason, VerifyErrorReason.unreachable);
      // The first sync failed in the series family: live and movies stay.
      expect(await count(id, ContentKind.live), catalog.live.length);
      expect(await count(id, ContentKind.movie), catalog.movies.length);
      expect(await count(id, ContentKind.series), 0);
      expect(
        (await db.catalogDao.categories(id, ContentKind.live)).length,
        catalog.liveCategories.length,
      );
      expect((await db.sourcesDao.byId(id))!.lastSyncAt, isNull);
      expect(await db.catalogDao.openGenerationOf(id), isNull);

      // A full sync completes it; a series failure on a re-sync keeps the
      // previous series and the refreshed live and movie families.
      expect((await service().syncAndWait(id)).isDone, isTrue);
      expect(await count(id, ContentKind.series), catalog.series.length);
      await db.favoritesDao.toggleFavorite(
        id,
        ContentKind.series,
        '${catalog.series.first.id}',
      );
      final again = await service(
        adapters: (c) =>
            _FlakyAdapter(repo.adapterFor(c), failOn: (b) => b is SeriesBatch),
      ).syncAndWait(id);
      expect(again.phase, SyncPhase.failed);
      expect(await count(id, ContentKind.live), catalog.live.length);
      expect(await count(id, ContentKind.movie), catalog.movies.length);
      expect(await count(id, ContentKind.series), catalog.series.length);
      expect(await db.favoritesDao.favoriteKeys(id, ContentKind.series), [
        '${catalog.series.first.id}',
      ]);
      expect(await db.catalogDao.openGenerationOf(id), isNull);
    });

    test('a live-only panel needs one swap', () async {
      final id = await addXtream();
      bool vod(SyncBatch b) =>
          b is MoviesBatch ||
          b is SeriesBatch ||
          (b is CategoriesBatch &&
              b.items.every((c) => c.kind != ContentKind.live));
      final result = await service(
        adapters: (c) => _FlakyAdapter(repo.adapterFor(c), drop: vod),
      ).syncAndWait(id);
      expect(result.phase, SyncPhase.done, reason: '${result.error}');
      expect(await count(id, ContentKind.live), panel.catalog.live.length);
      expect(await count(id, ContentKind.movie), 0);
      final row = (await db.sourcesDao.byId(id))!;
      expect(row.generation, 1);
      expect(row.lastSyncAt, clock.now());
    });

    test('a family that comes back empty is dropped with the others', () async {
      final id = await addXtream();
      expect((await service().syncAndWait(id)).isDone, isTrue);
      final result = await service(
        adapters: (c) =>
            _FlakyAdapter(repo.adapterFor(c), drop: (b) => b is MoviesBatch),
      ).syncAndWait(id);
      expect(result.phase, SyncPhase.done, reason: '${result.error}');
      expect(await count(id, ContentKind.movie), 0);
      expect(await count(id, ContentKind.live), panel.catalog.live.length);
      expect(await count(id, ContentKind.series), panel.catalog.series.length);
      expect(await db.catalogDao.openGenerationOf(id), isNull);
    });

    test('an expired account stops before touching the catalog', () async {
      final id = await addXtream();
      expect((await service().syncAndWait(id)).isDone, isTrue);
      panel.auth = FakeAuthMode.expired;
      final result = await service().syncAndWait(id);
      expect(result.phase, SyncPhase.failed);
      expect(result.error!.reason, VerifyErrorReason.expired);
      expect(result.error!.expiresAt, isNotNull);
      final row = (await db.sourcesDao.byId(id))!;
      expect(row.accountStatus, AccountStatus.expired);
      expect(await count(id, ContentKind.live), panel.catalog.live.length);
    });

    test('an empty answer never wipes a catalog', () async {
      final id = await addXtream();
      expect((await service().syncAndWait(id)).isDone, isTrue);
      final result = await service(
        adapters: (c) => _EmptyAdapter(repo.adapterFor(c)),
      ).syncAndWait(id);
      expect(result.phase, SyncPhase.failed);
      expect(await count(id, ContentKind.live), panel.catalog.live.length);
    });

    test('cancel stops the run and keeps the catalog', () async {
      final id = await addXtream();
      final sync = service();
      expect((await sync.syncAndWait(id)).isDone, isTrue);
      final generation = (await db.sourcesDao.byId(id))!.generation;

      panel.fullListDelay = const Duration(seconds: 5);
      final started = Completer<void>();
      final run = sync.sync(id).map((p) {
        if (p.categories > 0 && !started.isCompleted) started.complete();
        return p;
      }).last;
      await started.future;
      expect(sync.isRunning(id), isTrue);
      final stopwatch = Stopwatch()..start();
      await sync.cancelAndWait(id);
      final result = await run;
      expect(result.phase, SyncPhase.cancelled);
      expect(result.error, isNull);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 4)));
      expect((sync.statusOf(id) as SyncFailed).cancelled, isTrue);
      expect((await db.sourcesDao.byId(id))!.generation, generation);
      expect(await db.catalogDao.openGenerationOf(id), isNull);
      expect(await count(id, ContentKind.live), panel.catalog.live.length);
    });

    test('one sync per source: a second call joins the first', () async {
      final id = await addXtream();
      final sync = service();
      final statuses = <SyncStatus>[];
      final sub = sync.watchStatus(id).listen(statuses.add);
      final a = sync.sync(id).last;
      final b = sync.sync(id).last;
      expect(sync.isRunning(id), isTrue);
      final results = await Future.wait([a, b]);
      expect(results[0], results[1]);
      expect(results[0].isDone, isTrue);
      expect(panel.stats.requestsByAction['login'], 1);
      expect(panel.stats.requestsByAction['get_live_streams'], 1);
      await pumpEventQueue();
      await sub.cancel();
      expect(statuses.first, const SyncIdle());
      expect(statuses.whereType<SyncRunning>(), isNotEmpty);
      expect(statuses.last, isA<SyncDone>());

      // A finished run can be joined: it replays the final snapshot.
      expect(sync.isRunning(id), isFalse);
      final again = await sync.sync(id).last;
      expect(again.isDone, isTrue);
      expect(panel.stats.requestsByAction['login'], 2);
    });

    test('a background isolate does the same work', () async {
      final id = await addXtream();
      final sync = service(runner: const IsolateSyncRunner());
      final rows = db.sourcesDao.watchAll();
      final seenSynced = rows.firstWhere((r) => r.single.lastSyncAt != null);
      final progress = <SyncProgress>[];
      final result = await sync.sync(id).map((p) {
        progress.add(p);
        return p;
      }).last;
      expect(result.phase, SyncPhase.done, reason: '${result.error}');
      expect(result.channels, panel.catalog.live.length);
      expect(progress.where((p) => !p.isTerminal), isNotEmpty);
      expect(await count(id, ContentKind.live), panel.catalog.live.length);
      expect(await count(id, ContentKind.movie), panel.catalog.movies.length);
      expect(await count(id, ContentKind.series), panel.catalog.series.length);
      // Writes from the isolate reach stream queries here.
      final seen = await seenSynced.timeout(const Duration(seconds: 10));
      expect(seen.single.lastSyncAt, clock.now());
    });

    test('a background run can be cancelled', () async {
      final id = await addXtream();
      final sync = service(runner: const IsolateSyncRunner());
      panel.fullListDelay = const Duration(seconds: 5);
      final started = Completer<void>();
      final run = sync.sync(id).map((p) {
        if (p.categories > 0 && !started.isCompleted) started.complete();
        return p;
      }).last;
      await started.future;
      sync.cancel(id);
      final result = await run;
      expect(result.phase, SyncPhase.cancelled);
      expect((await db.sourcesDao.byId(id))!.generation, 0);
      expect(await db.catalogDao.openGenerationOf(id), isNull);
      expect(await count(id, ContentKind.live), 0);
    });
  });

  group('M3U', () {
    test('the panel get.php playlist imports every item', () async {
      final id = await repo.add(
        SourceConfig(kind: SourceKind.m3uUrl, url: panel.m3uUrl()),
      );
      final result = await service().syncAndWait(id);
      final catalog = panel.catalog;
      expect(result.phase, SyncPhase.done, reason: '${result.error}');
      expect(result.channels, catalog.live.length);
      expect(result.movies, catalog.movies.length);
      expect(result.series, catalog.series.length);
      expect(result.episodes, catalog.episodes.length);
      expect(await count(id, ContentKind.live), catalog.live.length);
      expect(await count(id, ContentKind.movie), catalog.movies.length);
      expect(await count(id, ContentKind.series), catalog.series.length);
      final keys = await db.catalogDao.allChannelKeys(id);
      final episodes = await db.catalogDao.episodesForSeries(
        id,
        (await db.catalogDao.allSeriesPage(id, 0, 1)).single.key,
      );
      expect(keys, hasLength(catalog.live.length));
      expect(episodes, isNotEmpty);

      // url-tvg from the playlist header, masked; manual entries are kept
      // and stale automatic ones removed on the next sync.
      final epg = await db.epgDao.epgSources(id);
      expect(epg.single.origin, EpgOrigin.m3uHeader);
      expect(epg.single.url, isNot(contains(_pass)));
      expect(await db.epgDao.epgSourceUrl(epg.single.id), panel.xmltvUrl);

      final manual = await db.epgDao.addEpgSource(
        id,
        'http://127.0.0.1:9/manual.xml',
        EpgOrigin.manual,
      );
      final stale = await db.epgDao.addEpgSource(
        id,
        'http://127.0.0.1:9/old.xml',
        EpgOrigin.m3uHeader,
      );
      await db.favoritesDao.toggleFavorite(id, ContentKind.live, keys.first);
      expect((await service().syncAndWait(id)).isDone, isTrue);
      final ids = [for (final e in await db.epgDao.epgSources(id)) e.id];
      expect(ids, containsAll([epg.single.id, manual]));
      expect(ids, isNot(contains(stale)));
      expect(await db.favoritesDao.favoriteKeys(id, ContentKind.live), [
        keys.first,
      ]);
      expect(log.dump(), isNot(contains(_pass)));
    });

    test(
      'a playlist that turned into an error page keeps the catalog',
      () async {
        final id = await repo.add(
          SourceConfig(kind: SourceKind.m3uUrl, url: panel.m3uUrl()),
        );
        expect((await service().syncAndWait(id)).isDone, isTrue);
        panel.auth = FakeAuthMode.banned; // get.php answers 403
        final result = await service().syncAndWait(id);
        expect(result.phase, SyncPhase.failed);
        expect(result.error!.reason, VerifyErrorReason.authFailed);
        expect(await count(id, ContentKind.live), panel.catalog.live.length);
      },
    );
  });

  test('a deleted source fails cleanly', () async {
    final result = await service().syncAndWait(424242);
    expect(result.phase, SyncPhase.failed);
  });
}

/// Passes batches through and throws a network error after [failAfter]
/// item batches, or (when given) at the first batch matching [failOn].
/// [before] runs before each batch is handed on; batches matching [drop]
/// are left out.
class _FlakyAdapter implements SourceAdapter {
  _FlakyAdapter(
    this.inner, {
    this.failAfter = 1 << 30,
    this.failOn,
    this.before,
    this.drop,
  });

  final SourceAdapter inner;
  final int failAfter;
  final bool Function(SyncBatch batch)? failOn;
  final Future<void> Function(SyncBatch batch)? before;
  final bool Function(SyncBatch batch)? drop;

  @override
  SourceCapabilities get caps => inner.caps;

  @override
  Future<AccountInfo> verify() => inner.verify();

  @override
  Stream<SyncBatch> fetchCatalog([SyncScope scope = SyncScope.all]) async* {
    var items = 0;
    await for (final batch in inner.fetchCatalog(scope)) {
      if (failOn?.call(batch) ?? false) {
        throw const NetworkFailure('connection reset');
      }
      if (batch is ChannelsBatch || batch is MoviesBatch) {
        if (items++ >= failAfter) {
          throw const NetworkFailure('connection reset');
        }
      }
      if (drop?.call(batch) ?? false) continue;
      await before?.call(batch);
      yield batch;
    }
  }

  @override
  Future<SeriesDetail> seriesDetail(String seriesKey) =>
      inner.seriesDetail(seriesKey);

  @override
  Future<MovieDetail?> movieDetail(String movieKey) =>
      inner.movieDetail(movieKey);

  @override
  StreamRequest resolve(PlayableRef ref, {Duration? startAt}) =>
      inner.resolve(ref, startAt: startAt);

  @override
  List<EpgSourceSpec> epgSpecs() => inner.epgSpecs();

  @override
  void close() => inner.close();
}

/// Logs in fine but returns no items at all.
class _EmptyAdapter extends _FlakyAdapter {
  _EmptyAdapter(super.inner) : super(failAfter: 0);

  @override
  Stream<SyncBatch> fetchCatalog([SyncScope scope = SyncScope.all]) =>
      Stream.fromIterable(const [
        PhaseDoneBatch(ContentKind.live),
        PhaseDoneBatch(ContentKind.movie),
        PhaseDoneBatch(ContentKind.series),
      ]);
}
