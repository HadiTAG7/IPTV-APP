// How many stream connections each source has in use, against its limit.
//
// An Xtream account allows `max_connections` streams at a time (often 1);
// the fullscreen player, every split-screen tile ([multiViewTilesProvider])
// and every detached window ([detachedWindowsProvider]) hold one each while
// they play. M3U sources and accounts that never said have no known limit:
// those are never limited.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../sources/source_repository.dart' show SourceView;
import 'detach/detached_windows.dart';

/// What holds a connection.
enum ConnectionHolder {
  /// The fullscreen player of the app's window.
  player,

  /// A tile of the split screen (in the app's window).
  tile,

  /// A detached window ([DetachedWindows]).
  viewer,
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
  /// or of the split-screen tile [tileId].
  ConnectionBudget without({int? viewerId, int? tileId}) => ConnectionBudget(
    limits: limits,
    uses: [
      for (final u in uses)
        if ((viewerId == null || u.viewerId != viewerId) &&
            (tileId == null || u.tileId != tileId))
          u,
    ],
  );

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

/// The source the fullscreen player plays from while it is open; set by the
/// player screen.
final mainPlayerSourceProvider = NotifierProvider<MainPlayerSource, int?>(
  MainPlayerSource.new,
  name: 'mainPlayerSourceProvider',
);

class MainPlayerSource extends Notifier<int?> {
  @override
  int? build() => null;

  /// The player opened on [sourceId], or closed (null). Ignored once the
  /// app is shutting down.
  void set(int? sourceId) {
    if (ref.mounted) state = sourceId;
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

/// The current [ConnectionBudget] ([connectionBudgetOf]).
final connectionBudgetProvider = Provider<ConnectionBudget>(
  (ref) => connectionBudgetOf(
    sources: ref.watch(sourcesProvider).value ?? const [],
    viewers: ref.watch(detachedWindowsProvider),
    player: ref.watch(mainPlayerSourceProvider),
    tiles: ref.watch(multiViewTilesProvider),
  ),
  name: 'connectionBudgetProvider',
);

/// The budget of the saved [sources]' limits (a detached window remembers
/// its source's limit too), the fullscreen [player]'s source, the
/// split-screen [tiles] (tile id -> source id) and the detached [viewers]
/// that hold a connection.
ConnectionBudget connectionBudgetOf({
  required List<SourceView> sources,
  required List<DetachedViewer> viewers,
  int? player,
  Map<int, int> tiles = const {},
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
  ],
);

/// Sources whose unknown limit was already logged.
final _unknownLimitLogged = Provider<Set<int>>((ref) => <int>{});

/// Whether one more connection on [sourceId] fits the budget. An unknown
/// limit fits; it is logged once per source and run.
bool connectionFits(ProviderContainer container, int sourceId) {
  final budget = container.read(connectionBudgetProvider);
  if (budget.limitOf(sourceId) == null) {
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
  return budget.fits(sourceId);
}
