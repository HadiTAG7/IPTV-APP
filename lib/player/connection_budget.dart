// How many stream connections each source has in use, against its limit.
//
// An Xtream account allows `max_connections` streams at a time (often 1);
// the fullscreen player (from the moment it is asked for), every
// split-screen tile ([multiViewTilesProvider]) and every detached window
// ([detachedWindowsProvider]) hold one each while they play, and a stream
// given up still holds one until it has stopped
// ([connectionDrainsProvider]). M3U sources and accounts that never said
// have no known limit: those are never limited.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../sources/source_repository.dart' show SourceView;
import 'detach/detached_windows.dart';
import 'session/connection_guard.dart';

/// What holds a connection.
enum ConnectionHolder {
  /// The fullscreen player of the app's window (also while it is on its
  /// way: [MainPlayerSource.hold]).
  player,

  /// A tile of the split screen (in the app's window).
  tile,

  /// A detached window ([DetachedWindows]).
  viewer,

  /// A stream given up that has not stopped yet ([ConnectionDrains]).
  stopping,
}

/// One connection in use.
@immutable
class ConnectionUse {
  const ConnectionUse({
    required this.sourceId,
    required this.holder,
    this.viewerId,
    this.tileId,
  });

  final int sourceId;
  final ConnectionHolder holder;

  /// The detached window, for [ConnectionHolder.viewer].
  final int? viewerId;

  /// The split-screen tile, for [ConnectionHolder.tile].
  final int? tileId;

  @override
  bool operator ==(Object other) =>
      other is ConnectionUse &&
      other.sourceId == sourceId &&
      other.holder == holder &&
      other.viewerId == viewerId &&
      other.tileId == tileId;

  @override
  int get hashCode => Object.hash(sourceId, holder, viewerId, tileId);

  @override
  String toString() =>
      'ConnectionUse(source $sourceId, ${holder.name}'
      '${viewerId == null ? '' : ' $viewerId'}'
      '${tileId == null ? '' : ' $tileId'})';
}

/// The connections in use and each source's limit. Pure.
@immutable
class ConnectionBudget {
  const ConnectionBudget({this.limits = const {}, this.uses = const []});

  /// `maxConnections` per source; a missing or null entry is unknown.
  final Map<int, int?> limits;
  final List<ConnectionUse> uses;

  /// The source's limit; null when unknown (no limit is applied).
  int? limitOf(int sourceId) {
    final limit = limits[sourceId];
    // 0 is what some panels report for "unlimited".
    return limit == null || limit <= 0 ? null : limit;
  }

  /// Connections in use on [sourceId], optionally by [holder] only.
  int usedOn(int sourceId, {ConnectionHolder? holder}) => uses
      .where(
        (u) => u.sourceId == sourceId && (holder == null || u.holder == holder),
      )
      .length;

  /// Connections still free on [sourceId]; null when the limit is unknown.
  int? freeOn(int sourceId) {
    final limit = limitOf(sourceId);
    if (limit == null) return null;
    final free = limit - usedOn(sourceId);
    return free < 0 ? 0 : free;
  }

  /// Whether [count] more connections fit on [sourceId]. Always true when
  /// the limit is unknown.
  bool fits(int sourceId, {int count = 1}) {
    final free = freeOn(sourceId);
    return free == null || free >= count;
  }

  /// This budget without the connection of the detached window [viewerId]
  /// or of the split-screen tile [tileId], without the fullscreen player's
  /// when [player], and without the streams still stopping when
  /// [stopping].
  ConnectionBudget without({
    int? viewerId,
    int? tileId,
    bool player = false,
    bool stopping = false,
  }) => ConnectionBudget(
    limits: limits,
    uses: [
      for (final u in uses)
        if ((viewerId == null || u.viewerId != viewerId) &&
            (tileId == null || u.tileId != tileId) &&
            !(player && u.holder == ConnectionHolder.player) &&
            !(stopping && u.holder == ConnectionHolder.stopping))
          u,
    ],
  );

  /// Whether [sourceId] is full only because of streams still stopping
  /// ([ConnectionHolder.stopping]): one more fits once they have stopped
  /// ([ConnectionDrains.settled]).
  bool waitsForStops(int sourceId) =>
      !fits(sourceId) && without(stopping: true).fits(sourceId);

  /// Ids of the detached windows playing from [sourceId], oldest first.
  List<int> viewersOn(int sourceId) => [
    for (final u in uses)
      if (u.sourceId == sourceId && u.holder == ConnectionHolder.viewer)
        ?u.viewerId,
  ];

  /// Ids of the split-screen tiles playing from [sourceId].
  List<int> tilesOn(int sourceId) => [
    for (final u in uses)
      if (u.sourceId == sourceId && u.holder == ConnectionHolder.tile)
        ?u.tileId,
  ];

  @override
  String toString() => 'ConnectionBudget($limits, $uses)';
}

/// The source the fullscreen player plays from while it is open, or is
/// about to open on: held by the player screen, and by [openPlayer] from
/// the request on (while it waits or asks) until the screen holds it.
final mainPlayerSourceProvider = NotifierProvider<MainPlayerSource, int?>(
  MainPlayerSource.new,
  name: 'mainPlayerSourceProvider',
);

class MainPlayerSource extends Notifier<int?> {
  /// Who holds it now ([hold]); null when [set].
  Object? _holder;

  @override
  int? build() => null;

  /// The player opened on [sourceId], or closed (null). Ignored once the
  /// app is shutting down.
  void set(int? sourceId) {
    if (!ref.mounted) return;
    _holder = null;
    state = sourceId;
  }

  /// [holder] (a player screen, or [openPlayer] for the player it is about
  /// to open) plays from [sourceId], instead of any earlier holder.
  /// Ignored once the app is shutting down.
  void hold(Object holder, int sourceId) {
    if (!ref.mounted) return;
    _holder = holder;
    state = sourceId;
  }

  /// [holder] no longer plays: the player is closed, unless another holder
  /// took over since (then this does nothing).
  void release(Object holder) {
    if (!ref.mounted || !identical(_holder, holder)) return;
    _holder = null;
    state = null;
  }
}

/// The split-screen tiles that hold (or are about to open) a connection:
/// tile id -> source id. Set by the split screen while it is open.
final multiViewTilesProvider = NotifierProvider<MultiViewTiles, Map<int, int>>(
  MultiViewTiles.new,
  name: 'multiViewTilesProvider',
);

class MultiViewTiles extends Notifier<Map<int, int>> {
  @override
  Map<int, int> build() => const {};

  /// The tiles holding a connection now (empty once the split screen is
  /// closed). Ignored once the app is shutting down.
  void set(Map<int, int> tiles) {
    if (!ref.mounted || mapEquals(tiles, state)) return;
    state = Map.unmodifiable(tiles);
  }
}

/// A stream given up that has not stopped yet ([ConnectionDrains]).
@immutable
class ConnectionDrain {
  const ConnectionDrain(this.id, this.sourceId);

  final int id;
  final int sourceId;

  @override
  String toString() => 'ConnectionDrain($id, source $sourceId)';
}

/// The streams given up that are still stopping ([ConnectionDrains]).
final connectionDrainsProvider =
    NotifierProvider<ConnectionDrains, List<ConnectionDrain>>(
      ConnectionDrains.new,
      name: 'connectionDrainsProvider',
    );

/// Streams given up that have not stopped yet: a split-screen tile's old
/// stream, whose stop waits for an open still running (up to the guard's
/// step timeout on a slow server), or a channel on its way to a separate
/// window. Each still holds its source's connection
/// ([ConnectionHolder.stopping]) until it has stopped, at most [timeout].
/// They are the app's, not the split screen's: they outlive it, and a
/// player opened after it closed waits for them ([settled]).
class ConnectionDrains extends Notifier<List<ConnectionDrain>> {
  /// The longest a stream counts as stopping: a little over the longest a
  /// stop can take ([ConnectionGuard.longestStop]: it waits for an open
  /// still running, then stops, each step bounded), so a stop that never
  /// finishes cannot hold its source forever while one the guard still
  /// allows is never cut short.
  static final timeout =
      ConnectionGuard.longestStop + const Duration(seconds: 2);

  final _timers = <int, Timer>{};
  final _waiters = <_DrainWaiter>{};
  int _nextId = 1;

  @override
  List<ConnectionDrain> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
      for (final waiter in [..._waiters]) {
        _settle(waiter, false);
      }
    });
    return const [];
  }

  /// A stream of [sourceId] was given up: it counts until [stopped]
  /// completes (either way), at most [timeout]. Ignored once the app is
  /// shutting down.
  void add(int sourceId, Future<void> stopped) {
    if (!ref.mounted) {
      stopped.ignore();
      return;
    }
    final id = _nextId++;
    state = [...state, ConnectionDrain(id, sourceId)];
    _timers[id] = Timer(timeout, () {
      _timers.remove(id);
      if (!ref.mounted) return;
      ref
          .read(ringLogProvider)
          .warn('Connections: a stream of source $sourceId did not stop');
      _remove(id);
    });
    unawaited(
      stopped.then<void>(
        (_) => _remove(id),
        onError: (Object _) => _remove(id),
      ),
    );
  }

  void _remove(int id) {
    _timers.remove(id)?.cancel();
    if (!ref.mounted || !state.any((d) => d.id == id)) return;
    state = [
      for (final d in state)
        if (d.id != id) d,
    ];
    for (final waiter in [..._waiters]) {
      if (!state.any((d) => d.sourceId == waiter.sourceId)) {
        _settle(waiter, true);
      }
    }
  }

  /// Completes with true once no stream of [sourceId] is stopping (at once
  /// when none is), or with false after [wait] (default [timeout]) or when
  /// the app is shutting down.
  Future<bool> settled(int sourceId, {Duration? wait}) {
    if (!ref.mounted) return Future.value(false);
    if (!state.any((d) => d.sourceId == sourceId)) return Future.value(true);
    final waiter = _DrainWaiter(sourceId);
    waiter.timer = Timer(wait ?? timeout, () => _settle(waiter, false));
    _waiters.add(waiter);
    return waiter.done.future;
  }

  void _settle(_DrainWaiter waiter, bool settled) {
    if (!_waiters.remove(waiter)) return;
    waiter.timer?.cancel();
    waiter.done.complete(settled);
  }
}

/// A caller of [ConnectionDrains.settled].
class _DrainWaiter {
  _DrainWaiter(this.sourceId);

  final int sourceId;
  final done = Completer<bool>();
  Timer? timer;
}

/// The current [ConnectionBudget] ([connectionBudgetOf]).
final connectionBudgetProvider = Provider<ConnectionBudget>(
  (ref) => connectionBudgetOf(
    sources: ref.watch(sourcesProvider).value ?? const [],
    viewers: ref.watch(detachedWindowsProvider),
    player: ref.watch(mainPlayerSourceProvider),
    tiles: ref.watch(multiViewTilesProvider),
    stopping: [for (final d in ref.watch(connectionDrainsProvider)) d.sourceId],
  ),
  name: 'connectionBudgetProvider',
);

/// The budget of the saved [sources]' limits (a detached window remembers
/// its source's limit too), the fullscreen [player]'s source, the
/// split-screen [tiles] (tile id -> source id), the detached [viewers]
/// that hold a connection and the sources of the streams still [stopping]
/// ([ConnectionDrains]).
ConnectionBudget connectionBudgetOf({
  required List<SourceView> sources,
  required List<DetachedViewer> viewers,
  int? player,
  Map<int, int> tiles = const {},
  List<int> stopping = const [],
}) => ConnectionBudget(
  limits: {
    for (final v in viewers) v.sourceId: v.maxConnections,
    for (final s in sources) s.id: s.maxConnections,
  },
  uses: [
    if (player != null)
      ConnectionUse(sourceId: player, holder: ConnectionHolder.player),
    for (final MapEntry(key: tile, value: source) in tiles.entries)
      ConnectionUse(
        sourceId: source,
        holder: ConnectionHolder.tile,
        tileId: tile,
      ),
    for (final v in viewers)
      if (v.holdsConnection)
        ConnectionUse(
          sourceId: v.sourceId,
          holder: ConnectionHolder.viewer,
          viewerId: v.id,
        ),
    for (final source in stopping)
      ConnectionUse(sourceId: source, holder: ConnectionHolder.stopping),
  ],
);

/// Sources whose unknown limit was already logged.
final _unknownLimitLogged = Provider<Set<int>>((ref) => <int>{});

/// Whether one more connection on [sourceId] fits the [budget] (default
/// [connectionBudgetProvider]'s). An unknown limit fits; it is logged once
/// per source and run.
bool connectionFits(
  ProviderContainer container,
  int sourceId, {
  ConnectionBudget? budget,
}) {
  final checked =
      budget ?? container.read<ConnectionBudget>(connectionBudgetProvider);
  if (checked.limitOf(sourceId) == null) {
    if (container.read(_unknownLimitLogged).add(sourceId)) {
      container
          .read(ringLogProvider)
          .warn(
            'Connections: source $sourceId has no known limit; '
            'detached windows are not limited',
          );
    }
    return true;
  }
  return checked.fits(sourceId);
}
