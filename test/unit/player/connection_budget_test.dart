// The per-source connection budget (fullscreen player + detached windows).
// Synthetic data only.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/player/connection_budget.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
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
}
