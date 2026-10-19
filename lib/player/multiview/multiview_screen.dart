// The split screen (Windows and Linux): two or four live channels at once
// in tiles of the app's window, each through its own PlaybackController.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/platform/window_fullscreen.dart';
import '../../epg/epg_providers.dart';
import '../../features/live/channel_source.dart';
import '../../features/live/live_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../sources/source_repository.dart' show SourceView;
import '../../theme/tokens.dart';
import '../../tv/dpad_shortcuts.dart';
import '../../tv/focus_watchdog.dart';
import '../../tv/key_repeat.dart';
import '../../tv/tv_focusable.dart';
import '../../widgets/bidi_text.dart';
import '../connection_budget.dart';
import '../detach/detached_windows.dart';
import '../engine/player_engine.dart';
import '../player_providers.dart';
import '../session/playback_controller.dart';
import '../ui/channel_panel.dart';
import '../ui/player_route.dart';
import 'multiview_tile.dart';
import 'multiview_tile_view.dart';

/// Route name of the split screen.
const kMultiViewRouteName = '/multiview';

/// The split screen's layouts.
enum MultiViewLayout {
  /// Two tiles side by side.
  two(2),

  /// Four tiles, two by two.
  four(4);

  const MultiViewLayout(this.count);

  /// Tiles shown.
  final int count;

  /// Tiles per row (both layouts).
  static const columns = 2;

  int get rows => count ~/ columns;
}

/// Opens the split screen on [navigator] with [first] in its first tile
/// (the player hands its channel over), the window fullscreen when
/// [fullscreen]. [handedOver] is completed once that tile holds the
/// connection ([MultiViewScreen.handedOver]). Completes when it is closed.
Future<void> openMultiView(
  NavigatorState navigator, {
  MultiViewChannel? first,
  bool fullscreen = false,
  Completer<void>? handedOver,
}) => navigator.push<void>(
  PageRouteBuilder<void>(
    settings: const RouteSettings(name: kMultiViewRouteName),
    fullscreenDialog: true,
    transitionDuration: kPlayerFadeIn,
    reverseTransitionDuration: kPlayerFadeOut,
    pageBuilder: (_, _, _) => MultiViewScreen(
      first: first,
      fullscreen: fullscreen,
      handedOver: handedOver,
    ),
    transitionsBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  ),
);

/// Split screen: 2 (side by side) or 4 (two by two) live channels at once
/// in the app's window (desktop only; the player's Split screen action, S).
///
/// * Every tile ([MultiViewTile]) plays through a [PlaybackController] of
///   its own. Exactly one tile is active: it has the gold border, it is
///   the only one heard (M mutes it too) and the keys act on it. Tiles
///   without sound use the Lite cache.
/// * An empty tile shows a big "Add channel" button. Adding or changing a
///   channel opens a picker ([ChannelPanel]) with the user's sources on
///   top, so a tile can play from another source than the others; the
///   tile becomes the active one once its channel is picked.
/// * Before a tile opens a stream, its source must have a connection free
///   ([connectionBudgetProvider]: tiles and separate windows count);
///   otherwise a message says which tiles (or separate windows) use it.
///   Unknown limits (M3U) are never limited. Tiles hold their connection
///   ([multiViewTilesProvider]) from opening until they fail, are emptied
///   or the screen closes. A stream a tile gives up (emptied, another
///   channel, dropped by the layout, the screen closed) still counts until
///   it has stopped, and one sent to a separate window until the window has
///   it ([ConnectionDrains], also after the screen closed). A source full
///   only because of those makes the tile wait for them, showing its
///   channel opening.
/// * Mouse: a click makes a tile active, a double click maximizes it (the
///   others keep playing, hidden) and restores it. Hovering a tile shows
///   Change channel, Separate window (not on a failed tile) and Remove, and
///   on a maximized one Show all tiles; moving the mouse shows the bar
///   (Back, layout, fullscreen). The second click of a double click on
///   something that goes away never reaches the tile under it.
/// * Keys: arrows move the active tile (mirrored in Arabic), Enter
///   maximizes and restores (adds a channel to an empty tile, retries a
///   failed one), C changes the channel, M mutes, Delete removes the
///   channel, D detaches it into a separate window ([DetachedWindows]), L
///   switches the layout (from a maximized tile of 4 it shows all the tiles
///   first), F and F11 toggle the window's fullscreen, Escape shows all the
///   tiles again, leaves fullscreen, then the split screen. Tab never takes
///   the keyboard away; while a message is over the split screen no key
///   acts on the tiles.
/// * Like the player it owns the window's fullscreen
///   ([WindowFullscreenHold]), the app lifecycle (live stops in the
///   background and reopens on return, for every tile),
///   [fullscreenPlaybackProvider] and the keyboard. Closing it stops every
///   stream and frees every connection (each once its stream has stopped).
class MultiViewScreen extends ConsumerStatefulWidget {
  const MultiViewScreen({
    super.key,
    this.first,
    this.fullscreen = false,
    this.handedOver,
  });

  /// The first tile's channel; null opens the picker on it.
  final MultiViewChannel? first;

  /// Completed once [first]'s tile holds its connection (or was refused
  /// it, or the screen closed first): the player handing the channel over
  /// counts its stream until then ([ConnectionDrains]), so nothing takes
  /// the connection in between.
  final Completer<void>? handedOver;

  /// Makes the window fullscreen while the screen is open.
  final bool fullscreen;

  /// The bar hides after this long without the mouse moving.
  static const barTimeout = Duration(seconds: 4);

  @override
  ConsumerState<MultiViewScreen> createState() => _MultiViewScreenState();
}

class _MultiViewScreenState extends ConsumerState<MultiViewScreen> {
  /// Tiles in grid order (start to end, top to bottom); the layout shows
  /// the first [MultiViewLayout.count].
  late final List<MultiViewTile> _slots;
  MultiViewLayout _layout = MultiViewLayout.two;

  /// The active tile's place in [_slots].
  int _active = 0;

  /// The tile shown alone (the others play on, hidden).
  MultiViewTile? _maximized;

  /// The tile the channel picker is open for, and the source it shows.
  MultiViewTile? _pickerTile;
  int? _pickerSource;
  bool _pickerSlides = true;
  GlobalKey<ChannelPanelState> _pickerKey = GlobalKey();

  /// The list the picker last showed per source.
  final _lists = <int, LiveList>{};
  int? _lastSource;

  bool _barVisible = false;
  Timer? _barTimer;
  int? _hoveredTile;

  /// Mouse moves are ignored for a moment after the window changed size:
  /// Windows reports one when the window moves under a still cursor.
  bool _hoverMuted = false;
  Timer? _hoverMuteTimer;

  /// Where the click being handled was ([_onPointerUp]); null otherwise.
  Offset? _clickAt;

  /// The area whose coordinates [_clickAt] and [_guardAt] are in.
  final _clicks = GlobalKey(debugLabel: 'multiview-clicks');

  /// The spot of a click that made what was under it go away: it takes no
  /// clicks for a moment ([_guardClick]).
  Offset? _guardAt;
  Timer? _guardTimer;

  late final WindowFullscreenHold _window;
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<bool>? _onlineSub;
  bool _online = true;
  bool _background = false;
  bool _closing = false;
  int _dialogs = 0;

  final _rootNode = FocusNode(debugLabel: 'multiview');
  FocusWatchdogState? _watchdog;

  late final MultiViewTiles _connections;
  late final ConnectionDrains _drains;
  late final FullscreenPlayback _fullscreen;

  /// The app's providers, for what outlives this screen ([_detach]).
  late final ProviderContainer _container;

  /// The split screen reported as fullscreen playback and whose tiles are
  /// in the connection budget: a closing one never undoes what one opened
  /// meanwhile reported.
  static Object? _owner;

  bool get _desktop => _window.window != null;

  @override
  void initState() {
    super.initState();
    _window = WindowFullscreenHold(ref.read(playerWindowProvider));
    _connections = ref.read(multiViewTilesProvider.notifier);
    _drains = ref.read(connectionDrainsProvider.notifier);
    _fullscreen = ref.read(fullscreenPlaybackProvider.notifier);
    _container = ProviderScope.containerOf(context, listen: false);
    _owner = this;
    // Not while the route is being built.
    scheduleMicrotask(() {
      if (identical(_owner, this)) _fullscreen.set(true);
    });
    final loadSource = ref.read(playerSourceLoaderProvider);
    final db = ref.read(databaseProvider);
    final played = ref.read(onChannelPlayedProvider);
    final log = ref.read(ringLogProvider);
    _slots = [
      for (var id = 0; id < MultiViewLayout.four.count; id++)
        MultiViewTile(
          id: id,
          createController: () => _createController(id),
          loadSource: loadSource,
          db: db,
          onChannelPlayed: played,
          // Counted until stopped, also once this screen is gone.
          onStopping: _drains.add,
          log: log,
        )..addListener(_onTileChanged),
    ];
    _configureTiles();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    _onlineSub = ref.read(playerOnlineProvider)?.listen(_setOnline);
    if (widget.fullscreen) _setWindowFullscreen(true);
    final first = widget.first;
    if (first != null) {
      final list = first.list;
      if (list != null) _lists[first.sourceId] = list;
      _lastSource = first.sourceId;
    }
    // The budget is a provider: not while the route is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closing) {
        if (first == null) {
          _openPicker(_slots.first);
        } else {
          // Its tile holds the connection at once (waiting for the
          // player's stream, still counted, to be handed over), or is
          // refused it.
          unawaited(_tune(_slots.first, first));
        }
      }
      _handOver();
    });
  }

  /// The player's stream handed over is no longer counted for it
  /// ([MultiViewScreen.handedOver]).
  void _handOver() {
    final handedOver = widget.handedOver;
    if (handedOver != null && !handedOver.isCompleted) handedOver.complete();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final watchdog = FocusWatchdog.maybeOf(context);
    if (watchdog != _watchdog) {
      _watchdog?.unregister(_rootNode);
      _watchdog = watchdog?..register(_rootNode);
    }
  }

  @override
  void dispose() {
    _closing = true;
    _lifecycle.dispose();
    _barTimer?.cancel();
    _hoverMuteTimer?.cancel();
    _guardTimer?.cancel();
    unawaited(_onlineSub?.cancel());
    _watchdog?.unregister(_rootNode);
    // Disposing a tile disposes its controller (its engine stops and the
    // connection closes).
    for (final tile in _slots) {
      tile
        ..removeListener(_onTileChanged)
        ..dispose();
    }
    _rootNode.dispose();
    _release(later: true);
    _handOver();
    _window.set(false);
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Tiles.

  PlaybackController _createController(int id) {
    final tile = _slots.firstWhere((t) => t.id == id);
    final controller = createPlaybackController(
      read: ref.read,
      mounted: () => mounted,
      engines: () => ref.read(engineFactoryBuilderProvider)(
        ref.read(engineOptionsProvider).copyWith(lite: tile.lite),
      ),
    );
    if (!_online) controller.setOnline(false);
    if (_background) unawaited(controller.onBackground());
    return controller;
  }

  void _onTileChanged() {
    _syncConnections();
    _rebuild();
  }

  /// Tells the connection budget which tiles hold a connection (the
  /// streams they gave up count as [ConnectionDrains]). Once closing,
  /// [_release] has emptied it.
  void _syncConnections() {
    if (_closing || !identical(_owner, this)) return;
    _connections.set({
      for (final t in _slots)
        if (t.holdsConnection) t.id: t.channel!.sourceId,
    });
  }

  /// Only the active tile is heard (unless muted); the others use the Lite
  /// cache.
  void _configureTiles() {
    final appLite = ref.read(engineOptionsProvider).lite;
    for (final (i, tile) in _slots.indexed) {
      final active = i == _active;
      tile.configure(
        audible: active && !tile.userMuted && !_closing,
        lite: appLite || !active,
      );
    }
  }

  void _setActive(int slot) {
    if (slot == _active || slot < 0 || slot >= _layout.count) return;
    setState(() => _active = slot);
    _configureTiles();
  }

  /// Arrows: the neighbour in [direction] becomes active (Left and Right
  /// mirrored in Arabic, where the first tile is on the right). Not while a
  /// tile is maximized.
  void _moveActive(TraversalDirection direction) {
    if (_maximized != null) return;
    const columns = MultiViewLayout.columns;
    var row = _active ~/ columns;
    var column = _active % columns;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    switch (direction) {
      case TraversalDirection.left:
        column += rtl ? 1 : -1;
      case TraversalDirection.right:
        column += rtl ? -1 : 1;
      case TraversalDirection.up:
        row--;
      case TraversalDirection.down:
        row++;
    }
    if (column < 0 || column >= columns || row < 0 || row >= _layout.rows) {
      return;
    }
    _setActive(row * columns + column);
  }

  /// Double click and Enter: shows the tile alone, or the grid again.
  void _toggleMaximize(int slot) {
    final tile = _slots[slot];
    if (identical(_maximized, tile)) {
      setState(() => _maximized = null);
      return;
    }
    if (tile.isEmpty) return;
    setState(() => _maximized = tile);
    _setActive(slot);
  }

  /// A maximized tile's Show all tiles, Back and Escape: every tile shows
  /// again (the maximized one stays active).
  void _showGrid() {
    if (_maximized == null) return;
    _guardClick();
    setState(() => _maximized = null);
  }

  /// Enter on the active tile: adds a channel to an empty one, retries a
  /// failed one, else maximizes or restores it.
  void _select() {
    final tile = _slots[_active];
    switch (tile.status) {
      case MultiViewTileStatus.empty:
        _openPicker(tile);
      case MultiViewTileStatus.failed:
        unawaited(_retry(tile));
      case MultiViewTileStatus.opening || MultiViewTileStatus.playing:
        _toggleMaximize(_active);
    }
  }

  void _toggleMute(MultiViewTile tile) {
    if (tile.isEmpty || _closing) return;
    setState(() => tile.userMuted = !tile.userMuted);
    _configureTiles();
  }

  /// Plays [channel] in [tile] when its source has a connection free, or
  /// will have once streams still stopping have stopped (the tile shows the
  /// channel opening meanwhile, [_afterStops]); otherwise says what uses
  /// it. False when refused.
  Future<bool> _tune(MultiViewTile tile, MultiViewChannel channel) async {
    if (_closing) return false;
    final when = _afterStops(tile, channel);
    final refusal = when == null ? _refusal(tile, channel.sourceId) : null;
    if (refusal != null) {
      await _showInUse(refusal);
      return false;
    }
    // Holds the connection at once ([_syncConnections]).
    unawaited(tile.play(channel, when: when));
    return true;
  }

  Future<void> _retry(MultiViewTile tile) async {
    final channel = tile.channel;
    if (channel == null ||
        _closing ||
        tile.status != MultiViewTileStatus.failed) {
      return;
    }
    final when = _afterStops(tile, channel);
    final refusal = when == null ? _refusal(tile, channel.sourceId) : null;
    if (refusal != null) {
      await _showInUse(refusal);
      return;
    }
    unawaited(tile.retry(when: when));
  }

  /// Null unless [channel]'s source is full for [tile] only because of
  /// streams still stopping ([ConnectionDrains]). Else waits until they
  /// have stopped (at most [ConnectionDrains.timeout]) and checks again:
  /// true when [tile] may open the stream now; false when it may not (and
  /// says what uses the connection), when the tile went on to something
  /// else meanwhile or the split screen closed.
  Future<bool>? _afterStops(MultiViewTile tile, MultiViewChannel channel) {
    final sourceId = channel.sourceId;
    if (!_budgetFor(tile).waitsForStops(sourceId)) return null;
    ref
        .read(ringLogProvider)
        .info('Split screen: tile ${tile.id} waits for source $sourceId');
    return () async {
      await _drains.settled(sourceId);
      if (!mounted ||
          _closing ||
          !tile.waiting ||
          !identical(tile.channel, channel)) {
        return false;
      }
      final refusal = _refusal(tile, sourceId);
      if (refusal == null) return true;
      if (_dialogs == 0) unawaited(_showInUse(refusal));
      return false;
    }();
  }

  /// The connection budget as [tile] sees it (its own connection is its to
  /// reuse).
  ConnectionBudget _budgetFor(MultiViewTile tile) =>
      ref.read(connectionBudgetProvider).without(tileId: tile.id);

  /// Whether [tile] may open a stream of [sourceId] (unknown limits fit),
  /// now or once streams still stopping have stopped.
  bool _fits(MultiViewTile tile, int sourceId) =>
      _budgetFor(tile).without(stopping: true).fits(sourceId);

  /// Why [tile] may not open a stream of [sourceId] (all its connections
  /// are used by other tiles or separate windows), or null when it may.
  /// Streams still stopping are never named: only a lasting use is.
  String? _refusal(MultiViewTile tile, int sourceId) {
    final budget = _budgetFor(tile);
    final limit = budget.limitOf(sourceId);
    if (limit == null || budget.fits(sourceId)) return null;
    ref
        .read(ringLogProvider)
        .info('Split screen: source $sourceId has no connection free');
    final l10n = AppLocalizations.of(context);
    final sources = ref.read(sourcesProvider).value ?? const <SourceView>[];
    final name = sources.where((s) => s.id == sourceId).firstOrNull?.name;
    final source = name ?? '';
    if (limit == 1) {
      final tiles = budget.tilesOn(sourceId);
      final slot = tiles.isEmpty
          ? -1
          : _slots.indexWhere((t) => t.id == tiles.first);
      if (slot >= 0) return l10n.multiviewInUseTile(source, slot + 1);
      if (budget.viewersOn(sourceId).isNotEmpty) {
        return l10n.multiviewInUseWindow(source);
      }
    }
    // Named when the tiles and windows take every connection between them
    // (not with a stream still stopping among them).
    final places = budget.without(stopping: true).fits(sourceId)
        ? null
        : _placesUsing(l10n, budget, sourceId);
    if (places != null) return l10n.multiviewInUseManyAt(source, limit, places);
    return l10n.multiviewInUseMany(source, limit);
  }

  /// Where [budget]'s connections of [sourceId] are used: "tile 1, tile 2
  /// and a separate window"; null when nothing here or in a separate window
  /// uses one.
  String? _placesUsing(
    AppLocalizations l10n,
    ConnectionBudget budget,
    int sourceId,
  ) {
    final slots = [
      for (final id in budget.tilesOn(sourceId))
        _slots.indexWhere((t) => t.id == id),
    ].where((slot) => slot >= 0).toList()..sort();
    final windows = budget.viewersOn(sourceId).length;
    final places = [
      for (final slot in slots) l10n.multiviewPlaceTile(slot + 1),
      if (windows > 0) l10n.multiviewPlaceWindows(windows),
    ];
    if (places.length < 2) return places.firstOrNull;
    return l10n.multiviewPlacesAnd(
      places.sublist(0, places.length - 1).join(l10n.multiviewPlacesSeparator),
      places.last,
    );
  }

  Future<void> _showInUse(String message) async {
    final l10n = AppLocalizations.of(context);
    Offset? clickAt;
    await _dialog<void>(
      () => showDialog<void>(
        context: context,
        // The second click of a double click on the channel would close it
        // before it could be read.
        builder: (context) => _DialogGuard(
          onClick: (at) => clickAt = at,
          child: AlertDialog(
            key: const ValueKey('multiview-in-use'),
            title: Text(l10n.multiviewNoConnectionTitle),
            content: Text(message),
            actions: [
              FilledButton(
                key: const ValueKey('multiview-in-use-ok'),
                autofocus: true,
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonOk),
              ),
            ],
          ),
        ),
      ),
    );
    // Closed with a click (OK, or beside it): the second click of a double
    // click would reach the tile or the picker under it.
    final at = clickAt;
    if (at != null) _guardClick(at: at);
  }

  /// Empties [tile]: its stream stops and its connection is free.
  void _remove(MultiViewTile tile) {
    if (_closing || tile.isEmpty) return;
    _guardClick();
    if (identical(_maximized, tile)) _maximized = null;
    unawaited(tile.clear());
    // Its next channel follows the sound as it is now (no longer muted).
    _configureTiles();
    _rebuild();
  }

  /// Plays [tile]'s channel in a separate window ([DetachedWindows.detach])
  /// and empties the tile: its stream stops first, so a one-connection
  /// account never has two open. Its connection stays counted meanwhile
  /// ([ConnectionDrains]), from the moment the tile lets it go until the
  /// window is listed ([detachedWindowsProvider]) or failed to open: nothing
  /// takes it before the window has it.
  ///
  /// Leaving the split screen meanwhile does not cancel it: the user asked
  /// for the window, and it still opens. The connection stays counted
  /// throughout (the drain is the app's, not this screen's), so a player
  /// opened meanwhile on the same subscription waits for it and then asks
  /// about the window.
  Future<void> _detach(MultiViewTile tile) async {
    final channel = tile.channel;
    if (!_desktop || _closing || channel == null) return;
    _guardClick();
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final log = ref.read(ringLogProvider);
    void failed() {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.playerDetachFailed)));
    }

    final source = tile.source;
    final stream = tile.controller?.request;
    // Nothing to hand over, and no window failed: a failed tile offers
    // Retry, and a channel still being resolved (or a new one on its way)
    // shows its spinner for a moment.
    if (source == null ||
        stream == null ||
        tile.status == MultiViewTileStatus.failed ||
        !tile.playsChannel) {
      log.info('Split screen: tile ${tile.id} has no stream to detach');
      return;
    }
    final request = DetachRequest(
      sourceId: channel.sourceId,
      channelKey: channel.key,
      title: channel.name ?? '',
      logo: channel.logo,
      stream: stream,
      maxConnections: source.maxConnections,
      secrets: source.secrets,
      locale: Localizations.localeOf(context).languageCode == 'ar'
          ? 'ar'
          : 'en',
    );
    final windows = ref.read(detachedWindowsProvider.notifier);
    if (!windows.canPlay(request)) {
      failed();
      return;
    }
    log.info('Split screen: detaching tile ${tile.id}');
    if (identical(_maximized, tile)) setState(() => _maximized = null);
    final container = _container;
    final handedOver = Completer<void>();
    ProviderSubscription<List<DetachedViewer>>? listing;
    try {
      // Counted while its stream stops (which can wait for an opening one
      // to finish), then until the window is listed.
      await tile.clear(handedOver: handedOver.future);
      // Its next channel follows the sound as it is now (no longer muted).
      if (mounted) _configureTiles();
      try {
        listing = listenForWindow(container, request, handedOver);
      } on StateError {
        // The app is going away (its providers are disposed).
        return;
      }
      try {
        await windows.detach(request);
      } on ViewerLaunchException catch (e) {
        if (e.closedOnPurpose) {
          log.info('Split screen: the separate window was closed early');
          return;
        }
        log.warn('Split screen: the separate window failed: $e');
        failed();
      } on Object catch (e) {
        log.warn('Split screen: the separate window failed: $e');
        failed();
      }
    } finally {
      listing?.close();
      if (!handedOver.isCompleted) handedOver.complete();
    }
  }

  /// 2 <-> 4 tiles, all of them shown (a maximized tile too). Going back to
  /// 2 keeps the active tile and the next one with a channel (the others
  /// are emptied); an empty active tile makes way for the next two with a
  /// channel. From a maximized tile in 4 it only shows the grid: no channel
  /// stops before it was seen, the next press goes to 2.
  void _toggleLayout() {
    if (_closing) return;
    if (_layout == MultiViewLayout.two) {
      setState(() {
        _layout = MultiViewLayout.four;
        _maximized = null;
      });
      return;
    }
    if (_maximized != null) {
      _showGrid();
      return;
    }
    final count = MultiViewLayout.two.count;
    // From the active tile on, wrapping around.
    final order = [
      for (var i = 0; i < _slots.length; i++)
        _slots[(_active + i) % _slots.length],
    ];
    final kept = order.where((t) => !t.isEmpty).take(count).toList();
    for (final tile in order) {
      if (kept.length == count) break;
      if (!kept.contains(tile)) kept.add(tile);
    }
    final active = order.firstWhere(kept.contains);
    // Kept in their order on screen.
    kept.sort((a, b) => _slots.indexOf(a).compareTo(_slots.indexOf(b)));
    final dropped = [
      for (final t in _slots)
        if (!kept.contains(t)) t,
    ];
    for (final tile in dropped) {
      if (!tile.isEmpty) unawaited(tile.clear());
    }
    setState(() {
      _slots
        ..clear()
        ..addAll([...kept, ...dropped]);
      _layout = MultiViewLayout.two;
      _active = _slots.indexOf(active);
    });
    _configureTiles();
  }

  // ---------------------------------------------------------------------
  // The channel picker.

  /// Opens the channel picker for [tile]. The sound stays where it is
  /// until a channel is picked (the tile becomes the active one then).
  void _openPicker(MultiViewTile tile) {
    if (_closing || _pickerTile != null) return;
    final sources = ref.read(sourcesProvider).value ?? const <SourceView>[];
    var source = tile.channel?.sourceId ?? _lastSource;
    if (sources.isNotEmpty && !sources.any((s) => s.id == source)) {
      source = sources.first.id;
    }
    if (source == null) return;
    // A new channel: on a source it can play from, when the last one has
    // no connection free (another subscription or a free list).
    if (tile.isEmpty && !_fits(tile, source)) {
      source =
          sources.where((s) => _fits(tile, s.id)).firstOrNull?.id ?? source;
    }
    _barTimer?.cancel();
    setState(() {
      _pickerTile = tile;
      _pickerSource = source;
      _pickerSlides = true;
      _pickerKey = GlobalKey();
      _barVisible = false;
    });
  }

  void _closePicker() {
    if (_pickerTile == null) return;
    _guardClick();
    setState(() => _pickerTile = null);
    _focusAfterBuild(_rootNode);
  }

  void _switchSource(int sourceId) {
    if (_pickerTile == null || sourceId == _pickerSource) return;
    setState(() {
      _pickerSource = sourceId;
      _pickerSlides = false;
      _pickerKey = GlobalKey();
    });
  }

  /// A channel picked: it plays in the picker's tile, which becomes the
  /// active one (heard).
  /// Refused (no connection free), the picker stays open for another one.
  Future<void> _pick(ChannelListSource source, LiveEntry entry) async {
    final row = entry.row;
    final tile = _pickerTile;
    if (row == null || tile == null || _closing) return;
    // The picker goes away under a click (not after the await below).
    _guardClick();
    final channel = MultiViewChannel.of(
      source.sourceId,
      row,
      list: source.list,
    );
    _lists[source.sourceId] = source.list;
    _lastSource = source.sourceId;
    final current = tile.channel;
    if (current != null &&
        current.sourceId == channel.sourceId &&
        current.key == channel.key &&
        tile.status != MultiViewTileStatus.failed) {
      _closePicker();
      return;
    }
    if (_dialogs > 0) return;
    if (!await _tune(tile, channel) || !mounted) return;
    _setActive(_slots.indexOf(tile));
    // Also when it already was the active tile: its new stream is heard
    // unless it is muted now.
    _configureTiles();
    if (identical(_pickerTile, tile)) _closePicker();
  }

  Widget _picker(
    AppLocalizations l10n,
    MultiViewTile tile,
    int sourceId,
    List<SourceView> sources,
  ) {
    final current = tile.channel;
    return ChannelPanel(
      key: _pickerKey,
      sourceId: sourceId,
      list: _lists[sourceId] ?? const LiveList.all(),
      playingKey: current != null && current.sourceId == sourceId
          ? current.key
          : '',
      title: current == null
          ? l10n.multiviewAddChannel
          : l10n.multiviewChangeChannel,
      header: _SourceSwitcher(
        sources: sources,
        selected: sourceId,
        onSelect: _switchSource,
      ),
      slideIn: _pickerSlides,
      onTune: (source, entry) => unawaited(_pick(source, entry)),
      onClose: _closePicker,
    );
  }

  // ---------------------------------------------------------------------
  // Window, lifecycle, network.

  void _setWindowFullscreen(bool on) {
    if (!_window.set(on)) return;
    _hoverMuted = true;
    _hoverMuteTimer?.cancel();
    _hoverMuteTimer = Timer(
      const Duration(milliseconds: 600),
      () => _hoverMuted = false,
    );
  }

  /// The fullscreen button, F and F11; the choice also decides how the
  /// next player opens.
  void _toggleWindowFullscreen() {
    if (!_desktop || _closing) return;
    _setWindowFullscreen(!_window.isOn);
    ref.read(playerOpensFullscreenProvider.notifier).set(_window.isOn);
    _restartBarTimer();
    _rebuild();
  }

  /// Ends the fullscreen playback report and takes the tiles out of the
  /// connection budget, while this screen is the one that reported them;
  /// [later] when the widget tree is being finalized (providers cannot
  /// change then).
  void _release({bool later = false}) {
    if (!identical(_owner, this)) return;
    _owner = null;
    final fullscreen = _fullscreen;
    final connections = _connections;
    void release() {
      fullscreen.set(false);
      connections.set(const {});
    }

    if (later) {
      scheduleMicrotask(release);
    } else {
      release();
    }
  }

  /// The same policy as the player: live stops in the background (a
  /// minimized desktop window is "hidden") and reopens on return.
  void _onLifecycle(AppLifecycleState state) {
    if (_closing) return;
    switch (state) {
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _background = true;
        for (final tile in _slots) {
          final c = tile.controller;
          if (c != null) unawaited(c.onBackground());
        }
      case AppLifecycleState.resumed:
        _background = false;
        for (final tile in _slots) {
          final c = tile.controller;
          if (c != null) unawaited(c.onForeground());
        }
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _setOnline(bool online) {
    _online = online;
    for (final tile in _slots) {
      tile.controller?.setOnline(online);
    }
  }

  // ---------------------------------------------------------------------
  // Mouse, bar, focus.

  void _onMouseMoved() {
    if (_closing || _hoverMuted || _pickerTile != null) return;
    if (!_barVisible) setState(() => _barVisible = true);
    _restartBarTimer();
  }

  void _restartBarTimer() {
    if (!_barVisible || _closing) return;
    _barTimer?.cancel();
    _barTimer = Timer(MultiViewScreen.barTimeout, _onBarTimeout);
  }

  void _onBarTimeout() {
    if (!mounted) return;
    if (_dialogs > 0) {
      _restartBarTimer();
      return;
    }
    setState(() => _barVisible = false);
  }

  void _onTileHover(MultiViewTile tile, bool inside) {
    final id = inside
        ? tile.id
        : (_hoveredTile == tile.id ? null : _hoveredTile);
    if (id == _hoveredTile) return;
    setState(() => _hoveredTile = id);
  }

  /// A click gives the keyboard back to the split screen, should focus
  /// have gone elsewhere (the picker keeps its own).
  void _onPointerDown(PointerDownEvent _) {
    if (_closing || _pickerTile != null || _rootNode.hasPrimaryFocus) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _rootNode.requestFocus();
  }

  /// Kept for the click's handlers, which run in this same event
  /// ([_guardClick]).
  void _onPointerUp(PointerUpEvent event) {
    _clickAt = event.localPosition;
    scheduleMicrotask(() => _clickAt = null);
  }

  /// A click made what was under it go away (a channel picked, the picker
  /// closed, a tile's Remove or Separate window, the grid shown again, the
  /// "no free connection" message closed [at] its global spot): the spot
  /// takes no clicks for [kDoubleTapTimeout], or the second click of a
  /// double click would make the tile under it the active (heard) one, or
  /// press what is there now. Keys leave no spot.
  void _guardClick({Offset? at}) {
    if (!mounted) return;
    final box = _clicks.currentContext?.findRenderObject();
    final spot = at == null
        ? _clickAt
        : (box is RenderBox && box.hasSize ? box.globalToLocal(at) : null);
    if (spot == null) return;
    _guardTimer?.cancel();
    setState(() => _guardAt = spot);
    _guardTimer = Timer(kDoubleTapTimeout, () {
      if (mounted) setState(() => _guardAt = null);
    });
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _focusAfterBuild(FocusNode node) {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted || node.context == null) return;
        if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
        node.requestFocus();
      })
      ..ensureVisualUpdate();
  }

  Future<T?> _dialog<T>(Future<T?> Function() show) async {
    _dialogs++;
    try {
      return await show();
    } finally {
      _dialogs--;
      if (mounted && _pickerTile == null && !_closing) {
        _focusAfterBuild(_rootNode);
      }
    }
  }

  // ---------------------------------------------------------------------
  // Keys, Back.

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_closing) return KeyEventResult.handled;
    // A message over the split screen gets the keys once its first frame
    // took the focus; none of them acts on the tiles under it before
    // (Escape would stop them all and pop the message, not the screen).
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final down = event is KeyDownEvent;
    if (_desktop &&
        (key == LogicalKeyboardKey.f11 || key == LogicalKeyboardKey.keyF)) {
      if (down) _toggleWindowFullscreen();
      return KeyEventResult.handled;
    }
    final direction = arrowDirection(key);
    if (_pickerTile != null) {
      // Focus has not reached the picker yet (its lists are still being
      // read): the arrows and OK take it there.
      final primary = FocusManager.instance.primaryFocus;
      if (primary == _rootNode &&
          (direction != null || selectKeys.contains(key))) {
        if (down) _pickerKey.currentState?.focusIn();
        return KeyEventResult.handled;
      }
      // The picker's own keys; Escape closes it through Back.
      return KeyEventResult.ignored;
    }
    // Nothing here takes focus: Tab (and Shift+Tab) would take it off the
    // split screen, and none of its keys would work any more.
    if (key == LogicalKeyboardKey.tab) return KeyEventResult.handled;
    // Escape shows the grid and leaves window fullscreen before it closes
    // the split screen.
    if (key == LogicalKeyboardKey.escape) {
      if (down) _handleBack();
      return KeyEventResult.handled;
    }
    if (direction != null) {
      if (down) _moveActive(direction);
      return KeyEventResult.handled;
    }
    final tile = _slots[_active];
    if (selectKeys.contains(key)) {
      if (down) _select();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      if (down) _openPicker(tile);
    } else if (key == LogicalKeyboardKey.keyM) {
      if (down) _toggleMute(tile);
    } else if (key == LogicalKeyboardKey.delete) {
      if (down) _remove(tile);
    } else if (key == LogicalKeyboardKey.keyD && _desktop) {
      if (down) unawaited(_detach(tile));
    } else if (key == LogicalKeyboardKey.keyL) {
      if (down) _toggleLayout();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Back (Escape), innermost first: closes the picker, shows every tile
  /// again, leaves window fullscreen, then leaves the split screen.
  void _handleBack() {
    if (_closing) return;
    if (_pickerTile != null) {
      _closePicker();
    } else if (_maximized != null) {
      _showGrid();
    } else if (_window.isOn) {
      _setWindowFullscreen(false);
      _rebuild();
    } else {
      _exit();
    }
  }

  /// The bar's Back button: every tile again from a maximized one, else
  /// out of the split screen (in fullscreen too, like the player's).
  void _onBarBack() {
    if (_maximized != null) {
      _showGrid();
    } else {
      _exit();
    }
  }

  /// Leaves the split screen: every stream stops, and its connection is
  /// free once it has stopped ([ConnectionDrains]; the tiles are out of the
  /// budget at once); the window leaves fullscreen.
  void _exit() {
    if (_closing) return;
    setState(() {
      _closing = true;
      _pickerTile = null;
      _barVisible = false;
    });
    _barTimer?.cancel();
    unawaited(_onlineSub?.cancel());
    _onlineSub = null;
    for (final tile in _slots) {
      unawaited(tile.stop());
    }
    _release();
    _setWindowFullscreen(false);
    Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------
  // Build.

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Watched: the picker's source list and the budget's limits.
    final sources = ref.watch(sourcesProvider).value ?? const <SourceView>[];
    final aspect = ref.watch(settingsProvider.select((s) => s.defaultAspect));
    final pickerTile = _pickerTile;
    final pickerSource = _pickerSource;
    final guardAt = _guardAt;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // [_onKey] takes Escape (desktop Back); in the picker it goes
        // through the PopScope.
        body: Focus(
          focusNode: _rootNode,
          autofocus: true,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: MouseRegion(
            key: const ValueKey('multiview-mouse'),
            cursor: _barVisible || pickerTile != null || _closing
                ? MouseCursor.defer
                : SystemMouseCursors.none,
            onHover: (_) => _onMouseMoved(),
            child: Listener(
              key: _clicks,
              onPointerDown: _onPointerDown,
              onPointerUp: _onPointerUp,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _grid(aspect),
                  if (_barVisible && pickerTile == null && !_closing)
                    _bar(l10n),
                  if (pickerTile != null && pickerSource != null)
                    Positioned.fill(
                      child: _picker(l10n, pickerTile, pickerSource, sources),
                    ),
                  // Where a double click can land its second click.
                  if (guardAt != null)
                    Positioned.fromRect(
                      rect: Rect.fromCircle(
                        center: guardAt,
                        radius: kDoubleTapSlop,
                      ),
                      child: const AbsorbPointer(child: SizedBox.expand()),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _grid(AspectMode aspect) => LayoutBuilder(
    builder: (context, c) {
      const columns = MultiViewLayout.columns;
      final width = c.maxWidth / columns;
      final height = c.maxHeight / _layout.rows;
      final maximized = _maximized;
      return Stack(
        children: [
          for (var slot = 0; slot < _layout.count; slot++)
            _placed(slot, width, height, c.biggest, maximized, aspect),
        ],
      );
    },
  );

  Widget _placed(
    int slot,
    double width,
    double height,
    Size size,
    MultiViewTile? maximized,
    AspectMode aspect,
  ) {
    const columns = MultiViewLayout.columns;
    final tile = _slots[slot];
    final alone = identical(maximized, tile);
    final hidden = maximized != null && !alone;
    return PositionedDirectional(
      // Keyed by the tile: its video survives layout changes.
      key: ValueKey('multiview-tile-${tile.id}'),
      start: alone ? 0 : (slot % columns) * width,
      top: alone ? 0 : (slot ~/ columns) * height,
      width: alone ? size.width : width,
      height: alone ? size.height : height,
      child: Offstage(
        offstage: hidden,
        child: TickerMode(
          enabled: !hidden,
          child: MultiViewTileView(
            key: ValueKey('multiview-slot-$slot'),
            tile: tile,
            number: slot + 1,
            active: slot == _active && maximized == null,
            // Shown alone, it still shows whether it is heard.
            heard: slot == _active,
            hovered: _hoveredTile == tile.id && _barVisible && !_closing,
            aspect: aspect,
            onTap: () => _setActive(slot),
            onDoubleTap: () => _toggleMaximize(slot),
            onHover: (inside) => _onTileHover(tile, inside),
            onAdd: () => _openPicker(tile),
            onChange: () => _openPicker(tile),
            onRemove: () => _remove(tile),
            onRetry: () {
              _setActive(slot);
              unawaited(_retry(tile));
            },
            onDetach: _desktop ? () => unawaited(_detach(tile)) : null,
            onShowAll: alone ? _showGrid : null,
          ),
        ),
      ),
    );
  }

  /// Back, the layout and fullscreen, at the top centre while the mouse
  /// moves. On a maximized tile Back shows every tile again first.
  Widget _bar(AppLocalizations l10n) {
    final two = _layout == MultiViewLayout.two;
    final fullscreen = _window.isOn;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Container(
          key: const ValueKey('multiview-bar'),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.xs,
          ),
          decoration: const BoxDecoration(
            color: Color(0xE6151A22),
            borderRadius: BorderRadius.all(Radius.circular(Radii.pill)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MultiViewButton(
                key: const ValueKey('multiview-back'),
                icon: Icons.arrow_back,
                label: l10n.commonBack,
                size: 40,
                onPressed: _onBarBack,
              ),
              const SizedBox(width: Spacing.md),
              Text(
                l10n.playerSplitScreen,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: Spacing.md),
              MultiViewButton(
                key: const ValueKey('multiview-layout'),
                icon: two ? Icons.grid_view : Icons.vertical_split,
                label: two
                    ? l10n.multiviewFourChannels
                    : l10n.multiviewTwoChannels,
                size: 40,
                onPressed: _toggleLayout,
              ),
              if (_desktop) ...[
                const SizedBox(width: Spacing.sm),
                MultiViewButton(
                  key: const ValueKey('multiview-fullscreen'),
                  icon: fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  label: fullscreen
                      ? l10n.playerExitFullscreen
                      : l10n.playerFullscreen,
                  size: 40,
                  onPressed: _toggleWindowFullscreen,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A dialog that ignores clicks, on it and beside it (it covers the
/// barrier), for [kDoubleTapTimeout] after it opens, like
/// [ChannelPanel.openGuard]: the click that opened it may be the first of a
/// double click. Keys work at once. [onClick] gets the global spot of a
/// click on it or beside it while that click is handled (a click that
/// closes it, with OK or the barrier, has closed it by then), and null
/// after.
class _DialogGuard extends StatefulWidget {
  const _DialogGuard({required this.onClick, required this.child});

  final ValueChanged<Offset?> onClick;
  final Widget child;

  @override
  State<_DialogGuard> createState() => _DialogGuardState();
}

class _DialogGuardState extends State<_DialogGuard> {
  bool _justOpened = true;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(kDoubleTapTimeout, () {
      if (mounted) setState(() => _justOpened = false);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _onPointerUp(PointerUpEvent event) {
    final onClick = widget.onClick;
    onClick(event.position);
    // After the pop (OK) or maybePop (the barrier) this click caused.
    Timer.run(() => onClick(null));
  }

  @override
  Widget build(BuildContext context) => Listener(
    // Beside the dialog too: the barrier under it still takes the click.
    behavior: HitTestBehavior.translucent,
    onPointerUp: _onPointerUp,
    child: AbsorbPointer(absorbing: _justOpened, child: widget.child),
  );
}

/// The picker's row of sources: the channels shown come from the selected
/// one. Arrows move along it; Down goes back to the lists.
class _SourceSwitcher extends StatelessWidget {
  const _SourceSwitcher({
    required this.sources,
    required this.selected,
    required this.onSelect,
  });

  final List<SourceView> sources;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      children: [
        const SizedBox(width: Spacing.sm),
        Text(
          l10n.multiviewSource,
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final source in sources)
                  Padding(
                    padding: const EdgeInsets.all(Spacing.xs),
                    child: TvFocusable(
                      key: ValueKey('multiview-source-${source.id}'),
                      semanticLabel: source.name,
                      focusScale: 1.04,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(Radii.pill),
                      ),
                      onSelect: () => onSelect(source.id),
                      child: _chip(theme, source),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(ThemeData theme, SourceView source) {
    final on = source.id == selected;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: on ? AppColors.accent : AppColors.surfaceHigh,
        borderRadius: const BorderRadius.all(Radius.circular(Radii.pill)),
      ),
      child: BidiText(
        source.name,
        style: theme.textTheme.labelLarge?.copyWith(
          color: on ? AppColors.onAccent : AppColors.textPrimary,
        ),
      ),
    );
  }
}
