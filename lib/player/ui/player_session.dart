import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/settings.dart';
import '../../core/db/app_db.dart';
import '../../core/db/queries/player_ui_queries.dart';
import '../../core/log/ring_log.dart';
import '../../core/net/redact.dart';
import '../../core/time/clock.dart';
import '../../sources/models.dart';
import '../engine/player_engine.dart';
import '../player_providers.dart';
import '../session/playback_controller.dart';
import '../session/progress_saver.dart';
import '../session/reconnect_watchdog.dart';
import '../session/zap_controller.dart';
import 'play_request.dart';

/// What the player screen plays and everything around it that is not the
/// engine itself: resolving items through the source adapter, per-item
/// prefs (aspect, engine), live zapping and its banner data, now/next,
/// favourites, the VOD resume offer, the next-episode countdown, "try other
/// format" and the redacted report.
///
/// Drives one [PlaybackController] (owned by the provider, not by this
/// object).
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

  /// How often the live now/next is re-read.
  final Duration epgRefresh;

  final RingLog _log;
  final PlayRequest _initial;
  PlayRequest _request;
  PlayerSource? _source;
  Object? _error;
  bool _disposed = false;
  bool _started = false;

  // Live.
  ZapController<ZapEntry>? _zap;
  List<ZapEntry> _zapEntries = const [];
  bool _hasNumbers = false;
  ChannelRow? _channel;
  final _channels = <String, ChannelRow>{};
  final _guide = <String, NowNext>{};
  final _guideLoading = <String>{};
  final _channelLoading = <String>{};
  String? _liveExt;
  bool _favorite = false;
  String? _playedKey;
  int _tuneSeq = 0;
  Timer? _epgTimer;

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
  NowNext? get nowNext => _guide[_request.item.key];
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
  ValueListenable<ZapPreview<ZapEntry>>? get zapPreview => _zap?.preview;

  /// "Try other format" switches Xtream live between `.ts` and `.m3u8`.
  bool get canTryOtherFormat => isLive && (_source?.isXtream ?? false);

  PlayerItemKey get itemKey =>
      PlayerItemKey(sourceId, _request.kind, _request.item.key);

  /// Title for the OSD.
  String? get title => _request.displayTitle ?? _channel?.name;

  /// Loads the source and starts the request (or asks about resuming).
  Future<void> start() async {
    if (_started) return;
    _started = true;
    controller.addListener(_onController);
    controller.state.addListener(_onPlaybackState);
    await _load();
  }

  Future<void> _load() async {
    _error = null;
    try {
      _source ??= await loadSource(sourceId);
    } on Object catch (e) {
      if (_disposed) return;
      _log.warn('Player: source $sourceId unavailable: $e');
      _setError(e);
      return;
    }
    if (_disposed) return;
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
    final seq = ++_tuneSeq;
    final row =
        _channels[ref.key] ??
        await db.catalogDao.channelByKey(sourceId, ref.key);
    if (seq != _tuneSeq || _disposed) return;
    if (row != null) _remember(row);
    await _playLive(row?.toPlayable() ?? ref, row, seq);
  }

  Future<void> _playLive(PlayableRef ref, ChannelRow? row, int seq) async {
    final source = _source;
    if (source == null) return;
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
    if (seq != _tuneSeq || _disposed) return;
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
    if (seq != _tuneSeq || _disposed) return;
    unawaited(_refreshGuide(ref.key));
    _scheduleEpgRefresh();
  }

  Future<void> _loadZapList() async {
    final List<ZapEntry> entries;
    try {
      final keys = _initial.zapKeys;
      final category = _initial.categoryKey;
      entries = keys != null
          ? await db.zapEntriesForKeys(sourceId, keys)
          : category != null
          ? await db.zapEntriesInCategory(sourceId, category)
          : await db.zapEntriesAll(sourceId);
    } on Object catch (e) {
      _log.warn('Player: zap list unavailable: $e');
      return;
    }
    if (_disposed) return;
    final key = _request.item.key;
    final index = entries.indexWhere((e) => e.key == key);
    final hasNumbers = entries.any((e) => e.num != null);
    _hasNumbers = hasNumbers;
    final zap = ZapController<ZapEntry>(
      onTune: (e) => unawaited(_tuneKey(e.key)),
      items: entries,
      initialIndex: index,
      numberOf: hasNumbers ? (e) => e.num : null,
    );
    if (index < 0) zap.markTuned((key: key, num: _channel?.num));
    _zap = zap;
    _zapEntries = entries;
    zap.preview.addListener(_onPreview);
    unawaited(_prefetchAround(index));
    _notify();
  }

  Future<void> _tuneKey(String key) async {
    final seq = ++_tuneSeq;
    final row =
        _channels[key] ?? await db.catalogDao.channelByKey(sourceId, key);
    if (seq != _tuneSeq || _disposed || row == null) return;
    _remember(row);
    await _playLive(row.toPlayable(), row, seq);
    unawaited(_prefetchAround(_zap?.currentIndex ?? -1));
  }

  void _onPreview() {
    final item = _zap?.preview.value.item;
    if (item != null) {
      channelFor(item.key);
      nowNextFor(item.key);
    }
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
  int? positionNumber(int index) =>
      _zap == null || _hasNumbers || index < 0 ? null : index + 1;

  /// Whether the typed number of [p] found a channel in the zap list.
  bool numberMatches(ZapPreview<ZapEntry> p) {
    final n = int.tryParse(p.digits);
    if (n == null || n <= 0 || p.item == null) return false;
    return _hasNumbers ? p.item!.num == n : p.index == n - 1;
  }

  /// Whether a channel number is being typed.
  bool get enteringNumber => (_zap?.preview.value.digits ?? '').isNotEmpty;

  /// Tunes the typed number now (OK). False when no number was typed.
  bool commitNumber() {
    if (!enteringNumber) return false;
    _zap?.commit();
    return true;
  }

  /// Drops a half-typed number. False when none was typed.
  bool cancelNumber() {
    if (!enteringNumber) return false;
    _zap?.cancelNumber();
    return true;
  }

  /// A channel row from the cache; loads it (and notifies) when missing.
  ChannelRow? channelFor(String key) {
    final row = _channels[key];
    if (row != null || _channelLoading.contains(key)) return row;
    _channelLoading.add(key);
    unawaited(
      db.catalogDao
          .channelByKey(sourceId, key)
          .then((r) {
            _channelLoading.remove(key);
            if (r == null || _disposed) return;
            _remember(r);
            _notify();
          })
          .catchError((Object _) {
            _channelLoading.remove(key);
          }),
    );
    return null;
  }

  /// Now/next of [key] from the cache; loads it when missing.
  NowNext? nowNextFor(String key) {
    final cached = _guide[key];
    if (cached == null && !_guideLoading.contains(key)) {
      unawaited(_refreshGuide(key));
    }
    return cached;
  }

  Future<void> _refreshGuide(String key) async {
    if (!_guideLoading.add(key)) return;
    try {
      final result = await db.epgDao.nowNext(sourceId, [key], clock.now());
      if (_disposed) return;
      final value = result[key];
      if (value == null) {
        _guide.remove(key);
      } else {
        _guide[key] = value;
      }
      _notify();
    } on Object catch (e) {
      _log.warn('Player: guide read failed: $e');
    } finally {
      _guideLoading.remove(key);
    }
  }

  void _scheduleEpgRefresh() {
    _epgTimer?.cancel();
    _epgTimer = Timer.periodic(epgRefresh, (_) {
      if (isLive) unawaited(_refreshGuide(_request.item.key));
    });
  }

  Future<void> _prefetchAround(int index) async {
    final items = _zapEntries;
    if (index < 0) return;
    final n = items.length;
    if (n == 0) return;
    final keys = {
      for (var d = -10; d <= 10; d++) items[((index + d) % n + n) % n].key,
    }.where((k) => !_channels.containsKey(k)).toList();
    if (keys.isEmpty) return;
    try {
      final rows = await db.catalogDao.channelsByKeys(sourceId, keys);
      if (_disposed) return;
      rows.forEach(_remember);
    } on Object catch (_) {
      // Prefetching is best-effort.
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
      if (_disposed || key != _request.item.key) return;
      _favorite = now;
      _notify();
    } on Object catch (e) {
      _log.warn('Player: favourite failed: $e');
    }
  }

  /// Plays the current Xtream channel in the other container (`.ts` <->
  /// `.m3u8`); later channels of this session keep that choice.
  Future<void> tryOtherFormat() async {
    if (!canTryOtherFormat) return;
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
      if (_disposed) return;
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
    if (offer == null) return;
    _resumeOffer = null;
    _notify();
    await _playVod(resume ? offer.position : null);
  }

  Future<void> _playVod(Duration? startAt) async {
    final source = _source;
    if (source == null) return;
    final seq = ++_tuneSeq;
    _error = null;
    _resetNextEpisode();
    final key = itemKey;
    final prefs = await db.prefsDao.prefsFor(sourceId, key.prefsKey);
    if (seq != _tuneSeq || _disposed) return;
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
    if (seq != _tuneSeq || _disposed) return;
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
      if (seq != _tuneSeq || _disposed) return;
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
    if (_nextEpisode == null ||
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
    if (next == null) return;
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
  Future<void> switchEngine() => controller.switchEngine();

  /// After a failure: reloads what failed (source, item) or replays.
  Future<void> retry() async {
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
    if (_disposed) return;
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
    if (!_disposed) notifyListeners();
  }

  /// A plain-text report for support, with every URL credential and source
  /// secret masked.
  Future<String> buildReport({String? appVersion}) async {
    final source = _source;
    String safe(String s) => source?.redactText(s) ?? redact(s);
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

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _tuneSeq++;
    _epgTimer?.cancel();
    _countdownTimer?.cancel();
    if (_started) {
      controller.removeListener(_onController);
      controller.state.removeListener(_onPlaybackState);
    }
    final zap = _zap;
    if (zap != null) {
      zap.preview.removeListener(_onPreview);
      zap.dispose();
    }
    _source?.close();
    super.dispose();
  }
}
