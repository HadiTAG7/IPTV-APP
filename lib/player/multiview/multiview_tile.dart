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
/// [PlaybackController] (made on the first channel, disposed when the
/// channel is removed).
///
/// * [play] loads the source (kept while the channel stays on it), reads
///   the channel's catalog row, resolves the live stream like the player
///   ([PlayerSource.resolveLive]) and plays it with the source's
///   connection limit. A newer [play], [clear] or [dispose] drops one
///   still on its way.
/// * [holdsConnection] says whether the tile counts against its source's
///   connections: from [play] until it failed, is cleared or disposed.
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
  final RingLog _log;

  MultiViewChannel? _channel;
  PlaybackController? _controller;
  PlayerSource? _source;
  Object? _error;
  int _seq = 0;
  String? _playedKey;
  bool _disposed = false;

  bool _audible = false;
  bool _lite = false;

  /// The user muted this tile (M); it stays silent when active.
  bool userMuted = false;

  MultiViewChannel? get channel => _channel;
  PlaybackController? get controller => _controller;

  /// The source of the channel (once loaded).
  PlayerSource? get source => _source;

  /// The source could not be loaded or the channel resolved.
  Object? get error => _error;

  bool get isEmpty => _channel == null;

  MultiViewTileStatus get status {
    if (_channel == null) return MultiViewTileStatus.empty;
    if (_error != null) return MultiViewTileStatus.failed;
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
  /// time: the old one is closed before the new one opens).
  Future<void> play(MultiViewChannel channel) async {
    if (_disposed) return;
    final seq = ++_seq;
    _channel = channel;
    _error = null;
    _playedKey = null;
    notifyListeners();
    PlayerSource? source = _source;
    if (source == null || source.row.id != channel.sourceId) {
      // The tile now counts on the new source: the old one's stream goes
      // at once.
      final c = _controller;
      if (c != null) unawaited(c.stop());
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

  /// Plays the channel again after a failure.
  Future<void> retry() async {
    final channel = _channel;
    if (channel == null || _disposed) return;
    final controller = _controller;
    if (_error != null || _source == null || controller == null) {
      await play(channel);
      return;
    }
    _seq++;
    _playedKey = null;
    await controller.retry();
  }

  /// The channel cannot play: nothing plays in the tile (it holds no
  /// connection now).
  void _fail(Object error) {
    _error = error;
    final c = _controller;
    if (c != null) unawaited(c.stop());
    notifyListeners();
  }

  /// The controller changed: a channel that started playing goes to the
  /// Recent list (once; not the one still playing while a new one loads).
  void _onController() {
    if (_disposed) return;
    final c = _controller;
    final channel = _channel;
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
  /// when this completes, and the controller and source are released.
  Future<void> clear() async {
    _seq++;
    final controller = _controller;
    final source = _source;
    _controller = null;
    _source = null;
    _channel = null;
    _error = null;
    _playedKey = null;
    userMuted = false;
    if (!_disposed) notifyListeners();
    source?.close();
    if (controller == null) return;
    controller.removeListener(_onController);
    try {
      await controller.stop();
    } finally {
      controller.dispose();
    }
  }

  /// Stops the stream (the connection closes) and leaves the tile as it
  /// is on screen; [dispose] follows.
  Future<void> stop() async {
    _seq++;
    await _controller?.stop();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _seq++;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller
        ..removeListener(_onController)
        ..dispose();
    }
    _source?.close();
    _source = null;
    super.dispose();
  }
}
