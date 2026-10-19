// The per-source connection budget (fullscreen player, split-screen tiles,
// detached windows and streams still stopping). Synthetic data only.
import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/player/connection_budget.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/session/connection_guard.dart';
import 'package:iptv_player/sources/models.dart';

/// Detached windows set by the test.
class _Windows extends DetachedWindows {
  _Windows(this._initial);

  final List<DetachedViewer> _initial;

  @override
  List<DetachedViewer> build() => _initial;

  void set(List<DetachedViewer> windows) => state = windows;
}

DetachedViewer _window(
  int id,
  int sourceId, {
  ViewerStatus status = ViewerStatus.playing,
  int? maxConnections,
}) => DetachedViewer(
  id: id,
  sourceId: sourceId,
  channelKey: 'ch$id',
  title: 'Channel $id',
  status: status,
  maxConnections: maxConnections,
);

const _viewer = ConnectionHolder.viewer;
const _player = ConnectionHolder.player;
const _tile = ConnectionHolder.tile;
const _stopping = ConnectionHolder.stopping;

void main() {
  group('ConnectionBudget', () {
    test('limit 1: one connection, by the player or a window', () {
      const budget = ConnectionBudget(limits: {1: 1});
      expect(budget.fits(1), isTrue);
      expect(budget.freeOn(1), 1);
      const used = ConnectionBudget(
        limits: {1: 1},
        uses: [ConnectionUse(sourceId: 1, holder: _viewer, viewerId: 4)],
      );
      expect(used.fits(1), isFalse);
      expect(used.freeOn(1), 0);
      expect(used.viewersOn(1), [4]);
      const player = ConnectionBudget(
        limits: {1: 1},
        uses: [ConnectionUse(sourceId: 1, holder: _player)],
      );
      expect(player.fits(1), isFalse);
      expect(player.viewersOn(1), isEmpty);
    });

    test('limit 2: a window and the player', () {
      const one = ConnectionBudget(
        limits: {1: 2},
        uses: [ConnectionUse(sourceId: 1, holder: _viewer, viewerId: 1)],
      );
      expect(one.fits(1), isTrue);
      expect(one.fits(1, count: 2), isFalse);
      const two = ConnectionBudget(
        limits: {1: 2},
        uses: [
          ConnectionUse(sourceId: 1, holder: _viewer, viewerId: 1),
          ConnectionUse(sourceId: 1, holder: _viewer, viewerId: 2),
        ],
      );
      expect(two.fits(1), isFalse);
      expect(two.usedOn(1), 2);
      expect(two.usedOn(1, holder: _player), 0);
      expect(two.viewersOn(1), [1, 2]);
    });

    test('an unknown limit (M3U, null, 0) always fits', () {
      final uses = [
        for (var i = 0; i < 5; i++)
          ConnectionUse(sourceId: 1, holder: _viewer, viewerId: i),
      ];
      for (final limits in [
        <int, int?>{},
        {1: null},
        {1: 0},
      ]) {
        final budget = ConnectionBudget(limits: limits, uses: uses);
        expect(budget.limitOf(1), isNull);
        expect(budget.freeOn(1), isNull);
        expect(budget.fits(1), isTrue);
      }
    });

    test('split-screen tiles count; a budget without one of them', () {
      const budget = ConnectionBudget(
        limits: {1: 1},
        uses: [ConnectionUse(sourceId: 1, holder: _tile, tileId: 2)],
      );
      expect(budget.fits(1), isFalse);
      expect(budget.tilesOn(1), [2]);
      expect(budget.viewersOn(1), isEmpty);
      expect(budget.usedOn(1, holder: _tile), 1);
      expect(budget.without(tileId: 2).fits(1), isTrue);
      expect(budget.without(tileId: 3).fits(1), isFalse);
      // A window id never drops a tile, nor a tile id a window.
      expect(budget.without(viewerId: 2).fits(1), isFalse);
      const window = ConnectionBudget(
        limits: {1: 1},
        uses: [ConnectionUse(sourceId: 1, holder: _viewer, viewerId: 2)],
      );
      expect(window.without(tileId: 2).fits(1), isFalse);
      expect(window.without(viewerId: 2).fits(1), isTrue);
    });

    test('a stream still stopping counts, but is no tile nor window; the '
        'source waits only for it', () {
      const budget = ConnectionBudget(
        limits: {1: 1},
        uses: [ConnectionUse(sourceId: 1, holder: _stopping)],
      );
      expect(budget.fits(1), isFalse);
      expect(budget.usedOn(1), 1);
      expect(budget.tilesOn(1), isEmpty);
      expect(budget.viewersOn(1), isEmpty);
      expect(budget.waitsForStops(1), isTrue);
      expect(budget.without(stopping: true).fits(1), isTrue);
      // A tile or a window id never drops it.
      expect(budget.without(tileId: 0, viewerId: 0).fits(1), isFalse);

      // Full without it too: waiting would not help.
      const window = ConnectionBudget(
        limits: {1: 1},
        uses: [
          ConnectionUse(sourceId: 1, holder: _stopping),
          ConnectionUse(sourceId: 1, holder: _viewer, viewerId: 2),
        ],
      );
      expect(window.waitsForStops(1), isFalse);
      // Room for both: nothing to wait for.
      const two = ConnectionBudget(
        limits: {1: 2},
        uses: [ConnectionUse(sourceId: 1, holder: _stopping)],
      );
      expect(two.fits(1), isTrue);
      expect(two.waitsForStops(1), isFalse);
      // An unknown limit never waits.
      const m3u = ConnectionBudget(
        uses: [ConnectionUse(sourceId: 1, holder: _stopping)],
      );
      expect(m3u.waitsForStops(1), isFalse);
    });

    test('sources count separately', () {
      const budget = ConnectionBudget(
        limits: {1: 1, 2: 1},
        uses: [ConnectionUse(sourceId: 1, holder: _viewer, viewerId: 1)],
      );
      expect(budget.fits(1), isFalse);
      expect(budget.fits(2), isTrue);
      expect(budget.viewersOn(2), isEmpty);
    });
  });

  group('connectionBudgetProvider', () {
    late AppDatabase db;
    late RingLog log;
    late _Windows windows;
    late ProviderContainer container;
    late int xtream;
    late int m3u;

    setUp(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase(NativeDatabase.memory());
      xtream = await db.sourcesDao.create(
        const SourceConfig(
          kind: SourceKind.xtream,
          url: 'http://127.0.0.1:9',
          name: 'Panel',
          username: 'viewer7',
          password: 'Secret-Pass-9',
        ),
      );
      await db.sourcesDao.updateAccount(
        xtream,
        const AccountInfo(maxConnections: 1),
      );
      m3u = await db.sourcesDao.create(
        const SourceConfig(
          kind: SourceKind.m3uUrl,
          url: 'http://127.0.0.1:9/list.m3u',
          name: 'Home',
        ),
      );
      log = RingLog();
      windows = _Windows(const []);
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          ringLogProvider.overrideWithValue(log),
          detachedWindowsProvider.overrideWith(() => windows),
        ],
      );
      container
        ..read(detachedWindowsProvider)
        ..listen(sourcesProvider, (_, _) {});
      await container.read(sourcesProvider.future);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    ConnectionBudget budget() => container.read(connectionBudgetProvider);

    test('the saved limits; windows take, release on close and on '
        'error', () {
      expect(budget().limitOf(xtream), 1);
      expect(budget().limitOf(m3u), isNull);
      expect(connectionFits(container, xtream), isTrue);

      windows.set([_window(1, xtream)]);
      expect(connectionFits(container, xtream), isFalse);
      expect(budget().viewersOn(xtream), [1]);
      // Another source is not affected.
      expect(connectionFits(container, m3u), isTrue);

      // A failed window holds no connection.
      windows.set([_window(1, xtream, status: ViewerStatus.failed)]);
      expect(connectionFits(container, xtream), isTrue);
      expect(budget().viewersOn(xtream), isEmpty);

      // A starting one already counts.
      windows.set([_window(1, xtream, status: ViewerStatus.starting)]);
      expect(connectionFits(container, xtream), isFalse);

      // Closed or exited: gone from the list.
      windows.set(const []);
      expect(connectionFits(container, xtream), isTrue);
    });

    test('the fullscreen player counts too', () {
      container.read(mainPlayerSourceProvider.notifier).set(xtream);
      expect(budget().usedOn(xtream, holder: _player), 1);
      expect(connectionFits(container, xtream), isFalse);
      container.read(mainPlayerSourceProvider.notifier).set(null);
      expect(connectionFits(container, xtream), isTrue);
    });

    test('split-screen tiles count too, until the screen clears them', () {
      final tiles = container.read(multiViewTilesProvider.notifier)
        ..set({0: xtream, 1: m3u});
      expect(budget().tilesOn(xtream), [0]);
      expect(budget().usedOn(xtream, holder: _tile), 1);
      expect(connectionFits(container, xtream), isFalse);
      expect(connectionFits(container, m3u), isTrue);
      tiles.set(const {});
      expect(budget().tilesOn(xtream), isEmpty);
      expect(connectionFits(container, xtream), isTrue);
    });

    test('a stream given up counts until it has stopped, also with the '
        'tiles gone; settled waits for it', () async {
      final drains = container.read(connectionDrainsProvider.notifier);
      final stopped = Completer<void>();
      container.read(multiViewTilesProvider.notifier).set({0: xtream});
      drains.add(xtream, stopped.future);
      container.read(multiViewTilesProvider.notifier).set(const {});

      expect(connectionFits(container, xtream), isFalse);
      expect(budget().usedOn(xtream, holder: _stopping), 1);
      expect(budget().tilesOn(xtream), isEmpty);
      expect(budget().waitsForStops(xtream), isTrue);
      expect(connectionFits(container, m3u), isTrue);
      var settled = false;
      unawaited(drains.settled(xtream).then((v) => settled = v));
      // Another source has nothing to wait for.
      expect(await drains.settled(m3u), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);

      // A stop that fails has stopped as well.
      stopped.completeError(StateError('engine gone'));
      await Future<void>.delayed(Duration.zero);
      expect(settled, isTrue);
      expect(container.read(connectionDrainsProvider), isEmpty);
      expect(connectionFits(container, xtream), isTrue);
    });

    test('an unknown limit fits any number of windows, logged once', () {
      windows.set([for (var i = 1; i <= 3; i++) _window(i, m3u)]);
      expect(connectionFits(container, m3u), isTrue);
      expect(connectionFits(container, m3u), isTrue);
      expect(
        log.lines.where((l) => l.contains('no known limit')),
        hasLength(1),
      );
    });

    test("a window remembers its source's limit", () {
      windows.set([_window(1, 77, maxConnections: 1)]);
      expect(budget().limitOf(77), 1);
      expect(connectionFits(container, 77), isFalse);
    });
  });

  group('ConnectionDrains', () {
    /// Runs [body] on a fresh container in fake time; no timer may be left
    /// once the container is gone.
    void inFakeTime(
      void Function(FakeAsync async, ProviderContainer container, RingLog log)
      body,
    ) {
      fakeAsync((async) {
        final log = RingLog();
        final container = ProviderContainer(
          overrides: [ringLogProvider.overrideWithValue(log)],
        );
        body(async, container, log);
        container.dispose();
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    }

    List<int> sources(ProviderContainer container) => [
      for (final d in container.read(connectionDrainsProvider)) d.sourceId,
    ];

    test('a stop that never finishes is released after the safety '
        'timeout, which is longer than a stop can wait for an open', () {
      expect(
        ConnectionDrains.timeout,
        greaterThan(ConnectionGuard.defaultStepTimeout),
      );
      inFakeTime((async, container, log) {
        final drains = container.read(connectionDrainsProvider.notifier)
          ..add(1, Completer<void>().future);
        bool? settled;
        async.elapse(const Duration(seconds: 1));
        unawaited(drains.settled(1).then((v) => settled = v));

        async.elapse(ConnectionDrains.timeout - const Duration(seconds: 2));
        expect(sources(container), [1]);
        expect(settled, isNull);

        async.elapse(const Duration(seconds: 1));
        expect(sources(container), isEmpty);
        expect(settled, isTrue);
        expect(
          log.lines.where((l) => l.contains('did not stop')),
          hasLength(1),
        );
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a stop done in time leaves no timer; each source settles on its '
        'own', () {
      inFakeTime((async, container, log) {
        final a = Completer<void>();
        final b = Completer<void>();
        final drains = container.read(connectionDrainsProvider.notifier)
          ..add(1, a.future)
          ..add(1, b.future)
          ..add(2, Completer<void>().future);
        final settled = <bool>[];
        unawaited(drains.settled(1).then(settled.add));
        a.complete();
        async.flushMicrotasks();
        expect(sources(container), [1, 2]);
        expect(settled, isEmpty);

        b.complete();
        async.flushMicrotasks();
        expect(sources(container), [2]);
        expect(settled, [true]);
        // Only source 2's safety timer is left.
        expect(async.pendingTimers, hasLength(1));
        expect(log.lines.where((l) => l.contains('did not stop')), isEmpty);
      });
    });

    test('settled gives up after its wait; the app going away ends every '
        'wait and timer', () {
      inFakeTime((async, container, log) {
        final drains = container.read(connectionDrainsProvider.notifier)
          ..add(1, Completer<void>().future);
        final settled = <bool>[];
        unawaited(
          drains.settled(1, wait: const Duration(seconds: 1)).then(settled.add),
        );
        async.elapse(const Duration(seconds: 1));
        expect(settled, [false]);
        expect(sources(container), [1]);

        unawaited(drains.settled(1).then(settled.add));
        container.dispose();
        async.flushMicrotasks();
        expect(settled, [false, false]);
        expect(async.pendingTimers, isEmpty);
        // Later stops are ignored.
        drains.add(1, Completer<void>().future);
        expect(async.pendingTimers, isEmpty);
      });
    });
  });
}
