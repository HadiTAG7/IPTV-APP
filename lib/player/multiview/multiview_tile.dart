// One tile of the split screen ([MultiViewScreen]): the live channel it
// plays through a [PlaybackController] of its own.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/db/app_db.dart';
import '../../core/log/ring_log.dart';
import '../../features/live/live_models.dart';
import '../../sources/models.dart';
import '../player_providers.dart';
import '../session/playback_controller.dart';
import '../ui/player_format.dart';

/// A live channel a split-screen tile plays.
@immutable
class MultiViewChannel {
  const MultiViewChannel({
    required this.sourceId,
    required this.item,
    this.name,
    this.logo,
    this.list,
  });

  /// The catalog [row] of [sourceId], picked in [list].
  MultiViewChannel.of(int sourceId, ChannelRow row, {LiveList? list})
    : this(
        sourceId: sourceId,
        item: row.toPlayable(),
        name: row.name,
        logo: row.logo,
        list: list,
      );

  final int sourceId;

  /// The channel ([PlayableKind.live]).
  final PlayableRef item;
  final String? name;
  final String? logo;

  /// The Live list it was picked from: the picker opens there again.
  final LiveList? list;

  String get key => item.key;

  MultiViewChannel _withRow(ChannelRow row) => MultiViewChannel(
    sourceId: sourceId,
    item: row.toPlayable(),
    name: row.name,
    logo: row.logo ?? logo,
    list: list,
  );

  @override
  String toString() => 'MultiViewChannel(source $sourceId)';
}

/// What a tile shows.
enum MultiViewTileStatus {
  /// No channel: the big "Add channel" button.
  empty,

  /// Loading the source or opening the stream (or reconnecting).
  opening,
  playing,

  /// The source, the channel or the stream failed: Retry.
  failed,
}

/// One tile: the channel it plays, its source and its own
/// [PlaybackController] (made for the first stream it opens, and again for
/// the next stream once it gave one up).
///
/// * [play] loads the source (kept while the channel stays on it), reads
///   the channel's catalog row, resolves the live stream like the player
///   ([PlayerSource.resolveLive]) and plays it with the source's
///   connection limit. A newer [play], [clear] or [dispose] drops one
///   still on its way. Given a `when`, it waits for it first (showing the
///   channel opening).
/// * [holdsConnection] says whether the tile counts against its source's
///   connections: from [play] until it failed, is cleared or disposed.
/// * A stream it gives up (emptied, another source, waiting, failed,
///   stopped or disposed) goes with its controller, which is stopped and
///   then disposed: nothing else uses that controller, so no later play can
///   cancel its stop. The stream still counts until it has stopped, since
///   its stop waits for an open still running: [onStopping] hears of each.
/// * [configure] sets the sound (only the active tile is heard) and the
///   cache size (the Lite one when it is not heard) for this controller and
///   the later ones.
///
/// The split screen checks the connection budget before [play] and
/// [retry]; this class never does.
class MultiViewTile extends ChangeNotifier {
  MultiViewTile({
    required this.id,
    required this.createController,
    required this.loadSource,
    required this.db,
    this.onChannelPlayed,
    this.onStopping,
    RingLog? log,
  }) : _log = log ?? RingLog.instance;

  /// Stable for the tile's life (its place in the grid may change).
  final int id;

  /// Makes this tile's controller (the screen sets lifecycle and network
  /// state on it).
  final PlaybackController Function() createController;
  final PlayerSourceLoader loadSource;
  final AppDatabase db;

  /// The channel started playing (the Recent list).
  final ChannelPlayedCallback? onChannelPlayed;

  /// The tile gave up its stream of [sourceId], which has stopped (its
  /// connection is closed) once [stopped] completes.
  final void Function(int sourceId, Future<void> stopped)? onStopping;
  final RingLog _log;

  MultiViewChannel? _channel;
  PlaybackController? _controller;
  PlayerSource? _source;
  Object? _error;
  int _seq = 0;
  String? _playedKey;
  bool _disposed = false;

  /// The source of the stream the controller has (or opens); null once the
  /// tile gave it up ([_giveUp]).
  int? _streamSource;

  /// [play] or [retry] waits before the stream opens.
  bool _waiting = false;

  bool _audible = false;
  bool _lite = false;

  /// The user muted this tile (M); it stays silent when active.
  bool userMuted = false;

  MultiViewChannel? get channel => _channel;
  PlaybackController? get controller => _controller;

  /// The source of the channel (once loaded).
  PlayerSource? get source => _source;

  /// The source could not be loaded, the channel resolved, or its stream
  /// failed.
  Object? get error => _error;

  bool get isEmpty => _channel == null;

  MultiViewTileStatus get status {
    if (_channel == null) return MultiViewTileStatus.empty;
    if (_error != null) return MultiViewTileStatus.failed;
    if (_waiting) return MultiViewTileStatus.opening;
    return switch (_controller?.phase) {
      PlaybackPhase.failed => MultiViewTileStatus.failed,
      PlaybackPhase.playing => MultiViewTileStatus.playing,
      _ => MultiViewTileStatus.opening,
    };
  }

  /// Whether the tile holds (or is about to open) a connection of its
  /// channel's source.
  bool get holdsConnection =>
      _channel != null && status != MultiViewTileStatus.failed;

  /// Whether the channel waits before its stream opens ([play]'s `when`).
  bool get waiting => _waiting;

  /// Whether the tile is heard ([configure]).
  bool get audible => _audible;

  /// Whether it uses the Lite cache ([configure]).
  bool get lite => _lite;

  /// Sound and cache size for the controller now and the ones after it.
  void configure({required bool audible, required bool lite}) {
    _audible = audible;
    _lite = lite;
    final c = _controller;
    if (c == null) return;
    _apply(c);
  }

  void _apply(PlaybackController c) {
    if (c.muted != !_audible) unawaited(c.setMuted(!_audible));
    if (c.lite != _lite) unawaited(c.setLite(_lite));
  }

  /// Plays [channel] instead of what the tile played (one stream at a
  /// time: the old one is closed before the new one opens). With [when],
  /// the stream opens only once it completes with true (the split screen
  /// waits there for streams of the channel's source still stopping):
  /// meanwhile the tile shows the channel opening and holds its connection,
  /// and the stream it had stops at once. False fails the tile.
  Future<void> play(MultiViewChannel channel, {Future<bool>? when}) async {
    if (_disposed) return;
    final seq = ++_seq;
    _channel = channel;
    _error = null;
    _playedKey = null;
    _waiting = false;
    if (when != null && !await _wait(seq, when)) return;
    notifyListeners();
    PlayerSource? source = _source;
    if (source == null || source.row.id != channel.sourceId) {
      // The tile now counts on the new source: the old one's stream goes
      // at once, with its controller (it counts until it has stopped).
      unawaited(_giveUp());
      _source = null;
      source?.close();
      try {
        source = await loadSource(channel.sourceId);
      } on Object catch (e) {
        if (seq != _seq || _disposed) return;
        _log.warn('Split screen: source ${channel.sourceId} unavailable: $e');
        _fail(e);
        return;
      }
      if (seq != _seq || _disposed) {
        source.close();
        return;
      }
      _source = source;
    }
    await _open(source, channel, seq);
  }

  Future<void> _open(
    PlayerSource source,
    MultiViewChannel channel,
    int seq,
  ) async {
    // The catalog's row: its current URL and name.
    ChannelRow? row;
    try {
      row = await db.catalogDao.channelByKey(channel.sourceId, channel.key);
    } on Object catch (e) {
      _log.warn('Split screen: channel read failed: $e');
    }
    if (seq != _seq || _disposed) return;
    final current = row == null ? channel : channel._withRow(row);
    _channel = current;
    final StreamRequest stream;
    try {
      stream = source.resolveLive(current.item);
    } on Object catch (e) {
      _log.warn(
        'Split screen: cannot resolve channel: ${source.redactText('$e')}',
      );
      _fail(e);
      return;
    }
    final controller = _controller ??= _newController();
    notifyListeners();
    _log.info(
      'Split screen: tile $id live '
      '"${hideUrlPaths(source.redactText(current.name ?? ''))}"',
    );
    _streamSource = current.sourceId;
    await controller.play(
      stream,
      itemKey: _itemKey(current),
      maxConnections: source.maxConnections,
    );
  }

  /// [channel]'s [PlaybackController.itemKey].
  static String _itemKey(MultiViewChannel channel) =>
      PlayerItemKey(channel.sourceId, PlayableKind.live, channel.key).encode();

  /// Whether the controller plays (or opens) the tile's channel, not one it
  /// is about to replace.
  bool get playsChannel {
    final channel = _channel;
    return channel != null && _controller?.itemKey == _itemKey(channel);
  }

  PlaybackController _newController() {
    final c = createController();
    _apply(c);
    c.addListener(_onController);
    return c;
  }

  /// Plays the channel again after a failure; with [when], once it
  /// completes with true (as for [play]). A failed tile has no controller
  /// left ([_fail]): a new one plays it.
  Future<void> retry({Future<bool>? when}) async {
    final channel = _channel;
    if (channel == null || _disposed) return;
    await play(channel, when: when);
  }

  /// Waits for [when] before the stream of call [seq] opens: the tile shows
  /// its channel opening, and the stream it had stops at once (with its
  /// controller). False when a newer call took over, or when [when] said no
  /// (the tile failed then).
  Future<bool> _wait(int seq, Future<bool> when) async {
    _waiting = true;
    unawaited(_giveUp());
    notifyListeners();
    final go = await when.catchError((Object _) => false);
    if (seq != _seq || _disposed) return false;
    _waiting = false;
    if (!go) {
      _fail(const _NoConnection());
      return false;
    }
    return true;
  }

  /// The channel cannot play: nothing plays in the tile (it holds no
  /// connection now).
  void _fail(Object error) {
    _error = error;
    unawaited(_giveUp());
    notifyListeners();
  }

  /// The tile gives up its stream, which goes with its controller: the
  /// controller is stopped, then disposed, and the tile never uses it again
  /// (its next stream gets a new one). A stop that a later play or retry
  /// on the same controller superseded would complete without stopping
  /// anything. The stream counts against its source until it has stopped
  /// ([onStopping]), then until [handedOver] completes, when given (a
  /// separate window takes it over); told after this frame's work when
  /// [later] (providers cannot change while the widget tree is being
  /// finalized). Completes once it has stopped.
  Future<void> _giveUp({Future<void>? handedOver, bool later = false}) {
    final controller = _controller;
    final sourceId = _streamSource;
    _controller = null;
    _streamSource = null;
    if (controller == null) return Future<void>.value();
    controller.removeListener(_onController);
    final stopped = _stopAndDispose(controller);
    final onStopping = this.onStopping;
    if (sourceId != null && onStopping != null) {
      final drained = handedOver == null
          ? stopped
          : stopped.whenComplete(() => handedOver);
      if (later) {
        scheduleMicrotask(() => onStopping(sourceId, drained));
      } else {
        onStopping(sourceId, drained);
      }
    }
    return stopped;
  }

  /// The controller changed: a channel that started playing goes to the
  /// Recent list (once; not the one still playing while a new one loads).
  void _onController() {
    if (_disposed) return;
    final c = _controller;
    final channel = _channel;
    if (c != null && c.phase == PlaybackPhase.failed) {
      // The stream failed by itself (it would not open, or the watchdog
      // gave up): it goes with its controller like any failure, so its
      // stop still running counts ([onStopping]).
      _fail(const _StreamFailed());
      return;
    }
    if (c != null &&
        channel != null &&
        c.phase == PlaybackPhase.playing &&
        _playedKey != channel.key &&
        c.itemKey == _itemKey(channel)) {
      _playedKey = channel.key;
      final callback = onChannelPlayed;
      if (callback != null) {
        unawaited(
          callback(channel.sourceId, channel.key).catchError(
            (Object e) => _log.warn('Split screen: recent failed: $e'),
          ),
        );
      }
    }
    notifyListeners();
  }

  /// Removes the channel: its stream is stopped (the connection closed)
  /// when this completes, and the controller and source are released. The
  /// stream counts until then ([onStopping]), and after that until
  /// [handedOver] completes, when given (a separate window takes it over).
  Future<void> clear({Future<void>? handedOver}) async {
    _seq++;
    final source = _source;
    _source = null;
    _channel = null;
    _error = null;
    _playedKey = null;
    _waiting = false;
    userMuted = false;
    final stopped = _giveUp(handedOver: handedOver);
    if (!_disposed) notifyListeners();
    source?.close();
    await stopped;
  }

  static Future<void> _stopAndDispose(PlaybackController controller) async {
    try {
      await controller.stop();
    } finally {
      controller.dispose();
    }
  }

  /// Stops the stream (the connection closes once this completes) and
  /// leaves the channel on screen; [dispose] follows.
  Future<void> stop() async {
    _seq++;
    _waiting = false;
    final stopped = _giveUp();
    if (!_disposed) notifyListeners();
    await stopped;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _seq++;
    // Not stopped before (the screen went away without its Back): the
    // stream stops once an open still running is done, then its controller
    // goes.
    unawaited(_giveUp(later: true));
    _source?.close();
    _source = null;
    super.dispose();
  }
}

/// Why a tile that waited for its source's connection does not play.
class _NoConnection implements Exception {
  const _NoConnection();

  @override
  String toString() => 'No connection free';
}

/// Why a tile whose controller failed does not play (the controller logged
/// the reason).
class _StreamFailed implements Exception {
  const _StreamFailed();

  @override
  String toString() => 'Stream failed';
}
