import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/settings.dart';
import '../../core/db/app_db.dart';
import '../../core/db/queries/player_ui_queries.dart';
import '../../core/log/ring_log.dart';
import '../../core/net/redact.dart';
import '../../core/time/clock.dart';
import '../../epg/epg_models.dart';
import '../../sources/models.dart';
import '../engine/player_engine.dart';
import '../player_providers.dart';
import '../session/playback_controller.dart';
import '../session/progress_saver.dart';
import '../session/reconnect_watchdog.dart';
import 'paged_zapper.dart';
import 'play_request.dart';
import 'player_format.dart';

/// What the player screen plays and everything around it that is not the
/// engine itself: resolving items through the source adapter, per-item
/// prefs (aspect, engine), live zapping and its banner data, now/next,
/// favourites, the VOD resume offer, the next-episode countdown, "try other
/// format" and the redacted report.
///
/// Drives one [PlaybackController] (owned by the provider, not by this
/// object). The controller is shared with the next player screen, so once
/// the screen exits [close] makes this session inert: nothing it started
/// (a debounced zap, a typed number, a source or catalog read) reaches the
/// controller after that.
class PlayerSession extends ChangeNotifier {
  PlayerSession({
    required PlayRequest request,
    required this.controller,
    required this.db,
    required this.loadSource,
    required this.settings,
    this.clock = const SystemClock(),
    this.onChannelPlayed,
    RingLog? log,
    this.nextEpisodeLead = const Duration(seconds: 15),
    this.nextEpisodeCountdown = 10,
    this.epgRefresh = const Duration(minutes: 1),
    this.guideSettle = const Duration(milliseconds: 150),
  }) : _initial = request,
       _request = request,
       _log = log ?? RingLog.instance;

  final PlaybackController controller;
  final AppDatabase db;
  final PlayerSourceLoader loadSource;

  /// Current Settings (default aspect ratio).
  final AppSettings Function() settings;
  final Clock clock;
  final ChannelPlayedCallback? onChannelPlayed;

  /// The countdown starts this long before an episode ends.
  final Duration nextEpisodeLead;

  /// Seconds of the next-episode countdown.
  final int nextEpisodeCountdown;

  /// How often the live now/next is re-read; also how long a channel
  /// without guide data is remembered as such.
  final Duration epgRefresh;

  /// The zap banner's now/next is read once it rests this long on a
  /// channel.
  final Duration guideSettle;

  final RingLog _log;
  final PlayRequest _initial;
  PlayRequest _request;
  PlayerSource? _source;
  Object? _error;
  bool _disposed = false;
  bool _closed = false;
  bool _started = false;

  // Live.
  PagedZapper? _zap;
  ChannelRow? _channel;
  final _channels = <String, ChannelRow>{};

  /// Keys read from the catalog and not found (never re-read).
  final _missingChannels = <String>{};
  final _channelLoading = <String>{};
  final _guide = <String, _GuideEntry>{};
  final _guideLoading = <String>{};
  String? _liveExt;
  bool _favorite = false;
  String? _playedKey;
  int _tuneSeq = 0;
  Timer? _epgTimer;
  Timer? _guideTimer;

  // Item prefs.
  AspectMode? _aspect;

  // VOD.
  ProgressRow? _resumeOffer;
  EpisodeRow? _episode;
  EpisodeRow? _nextEpisode;
  String? _seriesKey;
  bool _nextCancelled = false;
  int? _countdown;
  Timer? _countdownTimer;

  static const _channelCacheSize = 200;
  static const _guideCacheSize = 300;

  /// The item playing now (changes with zapping and the next episode).
  PlayRequest get request => _request;
  int get sourceId => _request.sourceId;
  bool get isLive => _request.isLive;
  PlayerSource? get source => _source;

  /// The source could not be loaded or the item has no playable URL.
  Object? get error => _error;

  /// The current live channel's catalog row (null until loaded).
  ChannelRow? get channel => _channel;

  /// Now/next of the current channel (null without guide data).
  NowNext? get nowNext => _guide[_request.item.key]?.value;
  bool get favorite => _favorite;

  /// Aspect ratio of the current item (its saved choice, else Settings).
  AspectMode get aspect => _aspect ?? settings().defaultAspect;

  /// Saved progress the user is asked about before a title starts.
  ProgressRow? get resumeOffer => _resumeOffer;

  /// The episode playing now, when the item is an episode.
  EpisodeRow? get episode => _episode;
  EpisodeRow? get nextEpisode => _nextEpisode;

  /// Seconds left before the next episode starts, while counting down.
  int? get countdown => _countdown;

  /// The zap banner (null until the zap list is loaded).
  ValueListenable<ZapView>? get zapPreview => _zap?.preview;

  /// The screen exited ([close]) or the session was disposed.
  bool get isClosed => _closed || _disposed;

  /// "Try other format" switches Xtream live between `.ts` and `.m3u8`.
  bool get canTryOtherFormat => isLive && (_source?.isXtream ?? false);

  PlayerItemKey get itemKey =>
      PlayerItemKey(sourceId, _request.kind, _request.item.key);

  /// Title for the OSD.
  String? get title => _request.displayTitle ?? _channel?.name;

  /// Loads the source and starts the request (or asks about resuming).
  Future<void> start() async {
    if (_started || isClosed) return;
    _started = true;
    controller.addListener(_onController);
    controller.state.addListener(_onPlaybackState);
    await _load();
  }

  Future<void> _load() async {
    _error = null;
    try {
      final source = _source ?? await loadSource(sourceId);
      if (isClosed) {
        if (!identical(source, _source)) source.close();
        return;
      }
      _source = source;
    } on Object catch (e) {
      if (isClosed) return;
      _log.warn('Player: source $sourceId unavailable: $e');
      _setError(e);
      return;
    }
    if (isLive) {
      unawaited(_loadZapList());
      await _startLive(_request.item);
    } else {
      await _startVod(askResume: true);
    }
  }

  // ---------------------------------------------------------------------
  // Live.

  Future<void> _startLive(PlayableRef ref) async {
    if (isClosed) return;
    final seq = ++_tuneSeq;
    final row =
        _channels[ref.key] ??
        await db.catalogDao.channelByKey(sourceId, ref.key);
    if (seq != _tuneSeq || isClosed) return;
    if (row != null) _remember(row);
    await _playLive(row?.toPlayable() ?? ref, row, seq);
  }

  Future<void> _playLive(PlayableRef ref, ChannelRow? row, int seq) async {
    final source = _source;
    if (source == null || seq != _tuneSeq || isClosed) return;
    _channel = row;
    _request = PlayRequest(
      sourceId: sourceId,
      item: ref,
      categoryKey: _initial.categoryKey,
      zapKeys: _initial.zapKeys,
      title: row?.name ?? ref.title,
    );
    _playedKey = null;
    _error = null;
    final key = itemKey;
    final prefs = await db.prefsDao.prefsFor(sourceId, key.prefsKey);
    final favorite = await db.favoritesDao.isFavorite(
      sourceId,
      ContentKind.live,
      ref.key,
    );
    if (seq != _tuneSeq || isClosed) return;
    _aspect = prefs.aspect;
    _favorite = favorite;
    _notify();
    final StreamRequest stream;
    try {
      stream = source.adapter.resolve(
        PlayableRef(
          kind: ref.kind,
          key: ref.key,
          url: ref.url,
          ext: _liveExt ?? ref.ext,
          headers: ref.headers,
          title: ref.title,
        ),
      );
    } on Object catch (e) {
      _log.warn('Player: cannot resolve channel: ${source.redactText('$e')}');
      _setError(e);
      return;
    }
    _log.info('Player: live "${source.redactText(title ?? '')}"');
    await controller.play(
      stream,
      itemKey: key.encode(),
      maxConnections: source.maxConnections,
      channelPref: prefs.engine,
    );
    if (seq != _tuneSeq || isClosed) return;
    unawaited(_loadGuide([ref.key]));
    _scheduleEpgRefresh();
  }

  Future<void> _loadZapList() async {
    final keys = _initial.zapKeys;
    final category = _initial.categoryKey;
    final key = _request.item.key;
    PagedZapper? zap;
    try {
      final ZapList list = keys != null
          ? MemoryZapList(await db.zapEntriesForKeys(sourceId, keys))
          : category != null
          ? CategoryZapList(db, sourceId, category)
          : AllChannelsZapList(db, sourceId);
      if (isClosed) return;
      zap = PagedZapper(
        list: list,
        onTune: (e) => unawaited(_tuneKey(e.key)),
        onError: (e) => _log.warn('Player: zap list read failed: $e'),
      );
      await zap.init((key: key, num: _channel?.num));
    } on Object catch (e) {
      _log.warn('Player: zap list unavailable: $e');
      zap?.dispose();
      return;
    }
    if (isClosed) {
      zap.dispose();
      return;
    }
    _zap = zap;
    zap.preview.addListener(_onPreview);
    unawaited(_prefetchAround(zap.currentIndex));
    _notify();
  }

  Future<void> _tuneKey(String key) async {
    if (isClosed) return;
    final seq = ++_tuneSeq;
    final row =
        _channels[key] ?? await db.catalogDao.channelByKey(sourceId, key);
    if (seq != _tuneSeq || isClosed || row == null) return;
    _remember(row);
    await _playLive(row.toPlayable(), row, seq);
    if (seq != _tuneSeq || isClosed) return;
    unawaited(_prefetchAround(_zap?.currentIndex ?? -1));
  }

  /// The banner moved: its channel row is read at once (with its
  /// neighbours), its now/next once the banner rests on it.
  void _onPreview() {
    final p = _zap?.preview.value;
    final item = p?.item;
    if (p == null || item == null || isClosed) return;
    if (!_channels.containsKey(item.key)) {
      unawaited(_prefetchAround(p.index, also: item.key, guide: false));
    }
    _guideTimer?.cancel();
    _guideTimer = null;
    if (!_guideFresh(item.key)) {
      _guideTimer = Timer(guideSettle, () {
        _guideTimer = null;
        unawaited(_loadGuide([item.key]));
      });
    }
  }

  /// New guide data was imported (a guide refresh of this source ended):
  /// forgets every cached now/next and reads the current channel's again,
  /// and the zap banner's channel when it points elsewhere.
  void reloadGuide() {
    if (isClosed || !isLive) return;
    final banner = _zap?.preview.value.item?.key;
    final keys = {_request.item.key, ?banner};
    // The shown ones stay until their new value is read.
    _guide.removeWhere((key, _) => !keys.contains(key));
    unawaited(_loadGuide(keys.toList(), force: true));
  }

  /// Zaps forward (CH+); the banner moves at once, the stream after the
  /// debounce.
  void zapNext() => _zap?.next();

  /// Zaps backward (CH-).
  void zapPrevious() => _zap?.previous();

  /// Adds a typed digit (tunes after a pause or [commitNumber]).
  void digit(int d) => _zap?.digit(d);

  /// The number shown for the zap list entry at [index] when the playlist
  /// has no channel numbers (its 1-based position), else null.
  int? positionNumber(int index) {
    final zap = _zap;
    return zap == null || zap.hasNumbers || index < 0 ? null : index + 1;
  }

  /// Whether the typed number of [p] found a channel in the zap list.
  bool numberMatches(ZapView p) => p.matched && p.item != null;

  /// Whether a channel number is being typed.
  bool get enteringNumber => (_zap?.preview.value.digits ?? '').isNotEmpty;

  /// Tunes the typed number now (OK). False when no number was typed.
  bool commitNumber() {
    if (!enteringNumber) return false;
    _zap?.commit();
    return true;
  }

  /// Drops a half-typed number. False when none was typed.
  bool cancelNumber() => _zap?.cancelNumber() ?? false;

  /// A channel row from the cache (rows are read when the banner moves).
  ChannelRow? channelFor(String key) => _channels[key];

  /// Now/next of [key] from the cache (read when the banner rests on a
  /// channel); null without guide data or before it was read.
  NowNext? nowNextFor(String key) => _guide[key]?.value;

  /// Whether [key]'s cached now/next is still valid: read less than
  /// [epgRefresh] ago, and its current programme has not ended (nor its
  /// next one started).
  bool _guideFresh(String key) {
    final entry = _guide[key];
    if (entry == null) return false;
    final now = clock.now();
    if (now.difference(entry.readAt) >= epgRefresh) return false;
    final current = entry.value?.now;
    if (current != null && !now.isBefore(current.stop)) return false;
    final next = entry.value?.next;
    return next == null || now.isBefore(next.start);
  }

  /// Reads now/next of [keys] (those not fresh, or all with [force]) in one
  /// query. Misses are cached too; listeners hear only of changed values.
  Future<void> _loadGuide(List<String> keys, {bool force = false}) async {
    final wanted = [
      for (final k in keys.toSet())
        if (!_guideLoading.contains(k) && (force || !_guideFresh(k))) k,
    ];
    if (wanted.isEmpty || isClosed) return;
    _guideLoading.addAll(wanted);
    try {
      final now = clock.now();
      final result = await db.epgDao.nowNext(sourceId, wanted, now);
      if (isClosed) return;
      var changed = false;
      for (final k in wanted) {
        final value = result[k];
        final old = _guide.remove(k);
        if (!_sameNowNext(old?.value, value)) changed = true;
        _guide[k] = _GuideEntry(value, now);
      }
      while (_guide.length > _guideCacheSize) {
        _guide.remove(_guide.keys.first);
      }
      if (changed) _notify();
    } on Object catch (e) {
      _log.warn('Player: guide read failed: $e');
    } finally {
      _guideLoading.removeAll(wanted);
    }
  }

  void _scheduleEpgRefresh() {
    _epgTimer?.cancel();
    _epgTimer = Timer.periodic(epgRefresh, (_) {
      if (isLive && !isClosed) {
        unawaited(_loadGuide([_request.item.key], force: true));
      }
    });
  }

  /// Reads the channel rows (and, with [guide], now/next) of the zap list
  /// entries around [index] that are in memory, plus [also].
  Future<void> _prefetchAround(
    int index, {
    String? also,
    bool guide = true,
  }) async {
    final zap = _zap;
    final keys = <String>{?also};
    final n = zap?.length ?? 0;
    if (zap != null && index >= 0 && n > 0) {
      for (var d = -10; d <= 10; d++) {
        final entry = zap.entryAt(((index + d) % n + n) % n);
        if (entry != null) keys.add(entry.key);
      }
    }
    if (keys.isEmpty || isClosed) return;
    final missing = [
      for (final k in keys)
        if (!_channels.containsKey(k) &&
            !_missingChannels.contains(k) &&
            !_channelLoading.contains(k))
          k,
    ];
    if (guide) unawaited(_loadGuide(keys.toList()));
    if (missing.isEmpty) return;
    _channelLoading.addAll(missing);
    try {
      final rows = await db.catalogDao.channelsByKeys(sourceId, missing);
      if (isClosed) return;
      rows.forEach(_remember);
      final found = {for (final r in rows) r.key};
      _missingChannels.addAll(missing.where((k) => !found.contains(k)));
      final shown = _zap?.preview.value.item?.key;
      if (shown != null && found.contains(shown)) _notify();
    } on Object catch (e) {
      _log.warn('Player: channel read failed: $e');
    } finally {
      _channelLoading.removeAll(missing);
    }
  }

  void _remember(ChannelRow row) {
    _channels
      ..remove(row.key)
      ..[row.key] = row;
    while (_channels.length > _channelCacheSize) {
      _channels.remove(_channels.keys.first);
    }
  }

  /// Adds or removes the current channel from the favourites.
  Future<void> toggleFavorite() async {
    if (!isLive) return;
    final key = _request.item.key;
    try {
      final now = await db.favoritesDao.toggleFavorite(
        sourceId,
        ContentKind.live,
        key,
      );
      if (isClosed || key != _request.item.key) return;
      _favorite = now;
      _notify();
    } on Object catch (e) {
      _log.warn('Player: favourite failed: $e');
    }
  }

  /// Plays the current Xtream channel in the other container (`.ts` <->
  /// `.m3u8`); later channels of this session keep that choice.
  Future<void> tryOtherFormat() async {
    if (!canTryOtherFormat || isClosed) return;
    final url = (controller.request?.url ?? '').toLowerCase();
    final hls =
        (controller.request?.isHls ?? false) ||
        url.contains('.m3u8') ||
        (controller.request == null && _liveExt == 'm3u8');
    _liveExt = hls ? 'ts' : 'm3u8';
    _log.info('Player: trying .$_liveExt');
    final seq = ++_tuneSeq;
    await _playLive(_request.item, _channel, seq);
  }

  // ---------------------------------------------------------------------
  // VOD.

  Future<void> _startVod({required bool askResume, Duration? startAt}) async {
    final item = _request.item;
    var start = startAt ?? _request.startAt;
    if (start == null) {
      ProgressRow? saved;
      try {
        saved = await db.progressDao.progressFor(sourceId, item.kind, item.key);
      } on Object catch (e) {
        _log.warn('Player: progress read failed: $e');
      }
      if (isClosed) return;
      if (saved != null &&
          ProgressSaver.shouldOfferResume(saved.position, saved.duration)) {
        if (askResume) {
          _resumeOffer = saved;
          _notify();
          return;
        }
        start = saved.position;
      }
    }
    await _playVod(start);
  }

  /// Answers the resume offer: from the saved position or from the start.
  Future<void> chooseResume({required bool resume}) async {
    final offer = _resumeOffer;
    if (offer == null || isClosed) return;
    _resumeOffer = null;
    _notify();
    await _playVod(resume ? offer.position : null);
  }

  Future<void> _playVod(Duration? startAt) async {
    final source = _source;
    if (source == null || isClosed) return;
    final seq = ++_tuneSeq;
    _error = null;
    _resetNextEpisode();
    final key = itemKey;
    final prefs = await db.prefsDao.prefsFor(sourceId, key.prefsKey);
    if (seq != _tuneSeq || isClosed) return;
    _aspect = prefs.aspect;
    _notify();
    final StreamRequest stream;
    try {
      stream = source.adapter.resolve(_request.item, startAt: startAt);
    } on Object catch (e) {
      _log.warn('Player: cannot resolve title: ${source.redactText('$e')}');
      _setError(e);
      return;
    }
    _log.info(
      'Player: ${_request.kind.name} "${source.redactText(title ?? '')}"'
      '${startAt == null ? '' : ' from ${startAt.inSeconds} s'}',
    );
    await controller.play(
      stream,
      itemKey: key.encode(),
      maxConnections: source.maxConnections,
      channelPref: prefs.engine,
    );
    if (seq != _tuneSeq || isClosed) return;
    if (_request.kind == PlayableKind.episode) unawaited(_loadEpisodes(seq));
  }

  Future<void> _loadEpisodes(int seq) async {
    try {
      final key = _request.item.key;
      final current = await db.catalogDao.episodeByKey(sourceId, key);
      final seriesKey = _request.seriesKey ?? current?.seriesKey;
      if (seriesKey == null) return;
      final episodes = await db.catalogDao.episodesForSeries(
        sourceId,
        seriesKey,
      );
      if (seq != _tuneSeq || isClosed) return;
      final index = episodes.indexWhere((e) => e.key == key);
      _seriesKey = seriesKey;
      _episode = index >= 0 ? episodes[index] : current;
      _nextEpisode = index >= 0 && index + 1 < episodes.length
          ? episodes[index + 1]
          : null;
      _notify();
      _onPlaybackState();
    } on Object catch (e) {
      _log.warn('Player: episodes unavailable: $e');
    }
  }

  void _resetNextEpisode() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdown = null;
    _nextEpisode = null;
    _nextCancelled = false;
  }

  void _onPlaybackState() {
    if (isClosed ||
        _nextEpisode == null ||
        _nextCancelled ||
        _countdownTimer != null ||
        controller.itemKey != itemKey.encode()) {
      return;
    }
    final st = controller.state.value;
    final ended = controller.phase == PlaybackPhase.ended;
    final nearEnd =
        st.duration > Duration.zero &&
        st.position > Duration.zero &&
        st.duration - st.position <= nextEpisodeLead;
    if (ended || nearEnd) _startCountdown();
  }

  void _startCountdown() {
    _countdown = nextEpisodeCountdown;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = (_countdown ?? 1) - 1;
      _countdown = left;
      _notify();
      if (left <= 0) unawaited(playNextEpisode());
    });
    _notify();
  }

  /// Stops the countdown; it does not come back for this episode.
  void cancelNextEpisode() {
    if (_countdownTimer == null && _countdown == null) return;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdown = null;
    _nextCancelled = true;
    _notify();
  }

  /// Plays the next episode now (resuming it if it was started before).
  Future<void> playNextEpisode() async {
    final next = _nextEpisode;
    if (next == null || isClosed) return;
    _resetNextEpisode();
    _episode = next;
    _request = PlayRequest(
      sourceId: sourceId,
      item: next.toPlayable(),
      seriesKey: _seriesKey ?? next.seriesKey,
      title: next.title,
    );
    _notify();
    await _startVod(askResume: false);
  }

  // ---------------------------------------------------------------------
  // Shared.

  /// Saves and applies the aspect ratio of the current item.
  Future<void> setAspect(AspectMode mode) async {
    _aspect = mode;
    _notify();
    try {
      await db.prefsDao.setAspect(sourceId, itemKey.prefsKey, mode);
    } on Object catch (e) {
      _log.warn('Player: saving aspect failed: $e');
    }
  }

  /// Plays the current item with the other engine (remembered per item).
  Future<void> switchEngine() async {
    if (!isClosed) await controller.switchEngine();
  }

  /// After a failure: reloads what failed (source, item) or replays.
  Future<void> retry() async {
    if (isClosed) return;
    if (_error != null || _source == null) {
      final live = isLive;
      _error = null;
      _notify();
      if (_source == null) {
        await _load();
      } else if (live) {
        await _playLive(_request.item, _channel, ++_tuneSeq);
      } else {
        await _startVod(askResume: false);
      }
      return;
    }
    await controller.retry();
  }

  void _onController() {
    if (isClosed) return;
    if (isLive &&
        controller.phase == PlaybackPhase.playing &&
        controller.itemKey == itemKey.encode()) {
      final key = _request.item.key;
      if (_playedKey != key) {
        _playedKey = key;
        final callback = onChannelPlayed;
        if (callback != null) {
          unawaited(
            callback(
              sourceId,
              key,
            ).catchError((Object e) => _log.warn('Player: recent failed: $e')),
          );
        }
      }
    }
    _onPlaybackState();
  }

  void _setError(Object error) {
    _error = error;
    _notify();
  }

  void _notify() {
    if (!isClosed) notifyListeners();
  }

  /// A plain-text report for support, with every source secret masked and
  /// no URL path or query at all ([hideUrlPaths]): the stream shows as
  /// `scheme://host:port/***.ext`.
  Future<String> buildReport({String? appVersion}) async {
    final source = _source;
    String safe(String s) => hideUrlPaths(source?.redactText(s) ?? redact(s));
    final b = StringBuffer()
      ..writeln('IPTV Player playback report')
      ..writeln('Time: ${clock.now().toUtc().toIso8601String()}');
    if (appVersion != null) b.writeln('App: $appVersion');
    b
      ..writeln('Item: ${_request.kind.name} "${safe(title ?? '')}"')
      ..writeln(
        'Source: ${source?.row.kind.name ?? 'not loaded'}'
        '${source?.maxConnections == null ? '' : ', max connections ${source!.maxConnections}'}',
      )
      ..writeln('Engine: ${controller.engineKind?.name ?? '-'}')
      ..writeln('Phase: ${controller.phase.name}');
    final err = controller.errorMessage ?? _error?.toString();
    if (err != null) b.writeln('Error: ${safe(err)}');
    final request = controller.request;
    if (request != null) {
      b.writeln('Stream: ${safe(request.url)}${request.isHls ? ' (hls)' : ''}');
    }
    final reconnect = controller.reconnectStatus.value;
    if (reconnect is! ReconnectIdle) b.writeln('Reconnect: $reconnect');
    try {
      final stats = await controller.stats();
      for (final e in stats.entries) {
        b.writeln('${e.key}: ${safe(e.value)}');
      }
    } on Object catch (_) {
      // Stats are optional.
    }
    b
      ..writeln()
      ..writeln('Recent log:')
      ..writeln(safe(_log.dump(last: 40)));
    return b.toString();
  }

  /// The screen is exiting: stops everything this session would still
  /// start (debounced zaps, typed numbers, reads in flight, the countdown,
  /// guide refreshes). Its state stays readable for the closing frames.
  void close() {
    if (_closed) return;
    _closed = true;
    _tuneSeq++;
    _epgTimer?.cancel();
    _epgTimer = null;
    _guideTimer?.cancel();
    _guideTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _zap?.close();
    if (_started) {
      controller.removeListener(_onController);
      controller.state.removeListener(_onPlaybackState);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    close();
    _disposed = true;
    final zap = _zap;
    if (zap != null) {
      zap.preview.removeListener(_onPreview);
      zap.dispose();
    }
    _source?.close();
    super.dispose();
  }
}

/// A cached now/next (null: the channel has no guide data) and when it was
/// read.
class _GuideEntry {
  const _GuideEntry(this.value, this.readAt);

  final NowNext? value;
  final DateTime readAt;
}

bool _sameNowNext(NowNext? a, NowNext? b) =>
    _sameProgramme(a?.now, b?.now) && _sameProgramme(a?.next, b?.next);

bool _sameProgramme(EpgProgramme? a, EpgProgramme? b) =>
    identical(a, b) ||
    (a != null &&
        b != null &&
        a.channelId == b.channelId &&
        a.start == b.start &&
        a.stop == b.stop &&
        a.title == b.title &&
        a.subTitle == b.subTitle);
