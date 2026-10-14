/// In-process fake IPTV panel (Xtream API, M3U, XMLTV, live TS/HLS, VOD).
///
/// Pure `dart:io`, so it runs inside `flutter test`, integration tests and
/// `dart run tool/fake_panel.dart`. Everything it serves is synthetic: made-up
/// names, generated test media from `tool/gen_media.sh`, or null packets.
///
/// Inside `testWidgets`, start and use the panel within `tester.runAsync`,
/// because sockets and timers need real time.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Login behaviour of `player_api.php`.
///
/// [auth0WithHttp200] and [emptyArray] only change `player_api.php`. The
/// blocked states ([expired], [banned], [disabled]) also make `get.php`,
/// `xmltv.php` and stream endpoints answer 403.
enum FakeAuthMode {
  /// `auth: 1`, `status: Active`.
  good,

  /// `auth: 1`, `status: Expired` and an `exp_date` in the past.
  expired,

  /// `auth: 1`, `status: Banned`.
  banned,

  /// `auth: 1`, `status: Disabled`.
  disabled,

  /// `{"user_info":{"auth":0}}` with HTTP 200.
  auth0WithHttp200,

  /// `[]` with HTTP 200.
  emptyArray,
}

/// Fault injected into stream endpoints, see [FakePanel.setChaos].
enum FakeChaosMode {
  /// No fault.
  off('off'),

  /// Destroys open stream sockets once, after a delay.
  drop('drop'),

  /// New stream requests get 403.
  forbidden('403'),

  /// Open and new streams stop sending bytes.
  stall('stall');

  const FakeChaosMode(this.wireName);

  /// Name used by `/__chaos?mode=`.
  final String wireName;

  static FakeChaosMode? parse(String? name) {
    for (final m in values) {
      if (m.wireName == name || m.name == name) return m;
    }
    return null;
  }
}

class FakeCategory {
  const FakeCategory(this.id, this.name);

  final String id;
  final String name;
}

class FakeChannel {
  const FakeChannel({
    required this.index,
    required this.id,
    required this.name,
    required this.categoryIds,
    this.epgId,
  });

  /// 1-based position in the catalog.
  final int index;

  /// Xtream `stream_id`.
  final int id;
  final String name;

  /// Primary category first; some channels sit in two categories.
  final List<String> categoryIds;

  /// `epg_channel_id` as served: null or empty for some channels.
  final String? epgId;

  String get categoryId => categoryIds.first;
  bool get isArabic => index.isOdd;

  /// Channel id in the XMLTV guide; channels without [epgId] get a synthetic
  /// id whose display name equals [name], so only name matching finds them.
  String get xmltvId => hasEpgId ? epgId! : 'noid$index.example';

  /// Whether `get_short_epg` returns listings for this channel.
  bool get hasEpgId => epgId != null && epgId!.isNotEmpty;
}

class FakeMovie {
  const FakeMovie({
    required this.index,
    required this.id,
    required this.name,
    required this.categoryId,
    required this.ext,
  });

  final int index;
  final int id;
  final String name;
  final String categoryId;

  /// `container_extension`.
  final String ext;
  bool get isArabic => index.isOdd;
}

class FakeEpisode {
  const FakeEpisode({
    required this.id,
    required this.seriesId,
    required this.season,
    required this.number,
    required this.title,
    required this.ext,
  });

  final int id;
  final int seriesId;
  final int season;
  final int number;
  final String title;
  final String ext;
}

class FakeSeries {
  const FakeSeries({
    required this.index,
    required this.id,
    required this.name,
    required this.categoryId,
    required this.seasonCount,
    required this.episodes,
    required this.episodesAsMap,
    required this.emptyInfo,
  });

  final int index;
  final int id;
  final String name;
  final String categoryId;
  final int seasonCount;
  final List<FakeEpisode> episodes;

  /// `get_series_info` episodes keyed by season (`{"1":[...]}`) when true,
  /// a flat list otherwise.
  final bool episodesAsMap;

  /// `get_series_info` returns `info: []` and `seasons: []`.
  final bool emptyInfo;
  bool get isArabic => index.isOdd;
}

class FakeProgramme {
  const FakeProgramme({
    required this.channelId,
    required this.start,
    required this.stop,
    required this.title,
    required this.description,
    required this.lang,
  });

  /// XMLTV channel id.
  final String channelId;

  /// UTC.
  final DateTime start;

  /// UTC.
  final DateTime stop;
  final String title;
  final String description;
  final String lang;
}

/// Deterministic synthetic catalog.
///
/// Ids: live `1000 + i`, movies `2000 + i`, series `3000 + i`, episodes
/// `seriesId * 100 + season * 10 + number`. Odd items have Arabic names.
class FakeCatalog {
  FakeCatalog._({
    required this.live,
    required this.movies,
    required this.series,
  }) : _liveById = {for (final c in live) c.id: c},
       _movieById = {for (final m in movies) m.id: m},
       _seriesById = {for (final s in series) s.id: s},
       _episodeById = {
         for (final s in series)
           for (final e in s.episodes) e.id: e,
       };

  factory FakeCatalog.generate({
    int liveCount = 50,
    int vodCount = 30,
    int seriesCount = 10,
  }) {
    final live = <FakeChannel>[];
    for (var i = 1; i <= liveCount; i++) {
      final primary = '${(i - 1) % 4 + 1}';
      final name = i.isOdd
          ? 'قناة اختبار $i'
          : (i % 4 == 0 ? 'Test News $i HD' : 'Test News $i');
      live.add(
        FakeChannel(
          index: i,
          id: 1000 + i,
          name: name,
          categoryIds: [primary, if (i % 7 == 0 && primary != '1') '1'],
          epgId: i % 20 == 0 ? null : (i % 10 == 0 ? '' : 'test$i.example'),
        ),
      );
    }
    final movies = <FakeMovie>[
      for (var i = 1; i <= vodCount; i++)
        FakeMovie(
          index: i,
          id: 2000 + i,
          name: i.isOdd ? 'فيلم اختبار $i' : 'Test Movie $i',
          categoryId: i.isOdd ? '10' : (i % 4 == 0 ? '12' : '11'),
          ext: i % 3 == 0 ? 'mp4' : 'mkv',
        ),
    ];
    final series = <FakeSeries>[];
    for (var i = 1; i <= seriesCount; i++) {
      final id = 3000 + i;
      final name = i.isOdd ? 'مسلسل اختبار $i' : 'Test Series $i';
      final seasons = i % 3 + 1;
      series.add(
        FakeSeries(
          index: i,
          id: id,
          name: name,
          categoryId: i.isOdd ? '20' : '21',
          seasonCount: seasons,
          episodesAsMap: i.isOdd,
          emptyInfo: i == seriesCount,
          episodes: [
            for (var s = 1; s <= seasons; s++)
              for (var e = 1; e <= 3; e++)
                FakeEpisode(
                  id: id * 100 + s * 10 + e,
                  seriesId: id,
                  season: s,
                  number: e,
                  title: '$name S${_two(s)}E${_two(e)}',
                  ext: e.isEven ? 'mkv' : 'mp4',
                ),
          ],
        ),
      );
    }
    return FakeCatalog._(live: live, movies: movies, series: series);
  }

  final List<FakeCategory> liveCategories = const [
    FakeCategory('1', 'أخبار'),
    FakeCategory('2', 'رياضة'),
    FakeCategory('3', 'Kids'),
    FakeCategory('4', 'Documentary'),
    FakeCategory('5', 'فارغة Empty'),
  ];
  final List<FakeCategory> vodCategories = const [
    FakeCategory('10', 'أفلام عربية'),
    FakeCategory('11', 'English Movies'),
    FakeCategory('12', 'Kids Movies'),
  ];
  final List<FakeCategory> seriesCategories = const [
    FakeCategory('20', 'مسلسلات عربية'),
    FakeCategory('21', 'English Series'),
  ];

  final List<FakeChannel> live;
  final List<FakeMovie> movies;
  final List<FakeSeries> series;
  final Map<int, FakeChannel> _liveById;
  final Map<int, FakeMovie> _movieById;
  final Map<int, FakeSeries> _seriesById;
  final Map<int, FakeEpisode> _episodeById;

  Iterable<FakeEpisode> get episodes => series.expand((s) => s.episodes);

  FakeChannel? channelById(int? id) => _liveById[id];
  FakeMovie? movieById(int? id) => _movieById[id];
  FakeSeries? seriesById(int? id) => _seriesById[id];
  FakeEpisode? episodeById(int? id) => _episodeById[id];

  /// Live channels listed by `get_live_streams&category_id=[categoryId]`.
  List<FakeChannel> liveInCategory(String categoryId) =>
      live.where((c) => c.categoryIds.contains(categoryId)).toList();

  String categoryName(String id) => [
    ...liveCategories,
    ...vodCategories,
    ...seriesCategories,
  ].firstWhere((c) => c.id == id, orElse: () => FakeCategory(id, '')).name;

  /// Guide for [channel] from the slot containing [now] to `now + span`.
  ///
  /// Even channels use 30-minute slots, odd channels 60-minute slots, aligned
  /// to UTC. Titles are Arabic on Arabic channels.
  List<FakeProgramme> programmesFor(
    FakeChannel channel,
    DateTime now, {
    Duration span = const Duration(hours: 24),
  }) {
    final slot = channel.index.isEven ? 1800 : 3600;
    final nowSec = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    final end = nowSec + span.inSeconds;
    final out = <FakeProgramme>[];
    for (var t = nowSec - nowSec % slot; t < end; t += slot) {
      final start = DateTime.fromMillisecondsSinceEpoch(t * 1000, isUtc: true);
      final hhmm = '${_two(start.hour)}:${_two(start.minute)}';
      out.add(
        FakeProgramme(
          channelId: channel.xmltvId,
          start: start,
          stop: start.add(Duration(seconds: slot)),
          title: channel.isArabic ? 'برنامج $hhmm' : 'Test Show $hhmm',
          description: channel.isArabic
              ? 'وصف تجريبي لبرنامج $hhmm على ${channel.name}'
              : 'News & weather <live> at $hhmm on ${channel.name}',
          lang: channel.isArabic ? 'ar' : 'en',
        ),
      );
    }
    return out;
  }
}

/// Snapshot of the panel's instrumentation, also served at `/__stats`.
class FakePanelStats {
  const FakePanelStats({
    required this.activeConnections,
    required this.maxConcurrentSeen,
    required this.maxConcurrentAttempted,
    required this.openStreams,
    required this.maxOpenStreamsSeen,
    required this.acceptedStreams,
    required this.rejectedStreams,
    required this.requestsByPath,
    required this.requestsByAction,
    required this.userAgents,
    required this.referers,
    required this.chaos,
  });

  factory FakePanelStats.fromJson(Map<String, Object?> json) {
    int i(String k) => (json[k] as num?)?.toInt() ?? 0;
    Map<String, T> m<T>(String k) => {
      for (final e in ((json[k] as Map<String, Object?>?) ?? const {}).entries)
        e.key: e.value as T,
    };
    return FakePanelStats(
      activeConnections: i('activeConnections'),
      maxConcurrentSeen: i('maxConcurrentSeen'),
      maxConcurrentAttempted: i('maxConcurrentAttempted'),
      openStreams: i('openStreams'),
      maxOpenStreamsSeen: i('maxOpenStreamsSeen'),
      acceptedStreams: i('acceptedStreams'),
      rejectedStreams: i('rejectedStreams'),
      requestsByPath: m<int>('requestsByPath'),
      requestsByAction: m<int>('requestsByAction'),
      userAgents: m<String>('userAgents'),
      referers: m<String>('referers'),
      chaos: json['chaos'] as String? ?? 'off',
    );
  }

  /// Connections as the panel counts them: concurrent requests for the same
  /// stream from the same client address count once, and an HLS viewer
  /// holds its connection until `hlsSessionTimeout` after its last request.
  final int activeConnections;

  /// Peak of [activeConnections]; never above `maxConnections`, because
  /// refused requests are not admitted.
  final int maxConcurrentSeen;

  /// Peak number of connections a client tried to hold at once, counting
  /// refused (403) requests. Use this, not [maxConcurrentSeen], to catch a
  /// client that opens a stream before releasing the previous one.
  final int maxConcurrentAttempted;

  /// Raw open stream responses (sockets), without grouping.
  final int openStreams;
  final int maxOpenStreamsSeen;

  /// Stream requests admitted / refused with 403 (limit or chaos).
  final int acceptedStreams;
  final int rejectedStreams;

  /// Request count per exact path (query excluded).
  final Map<String, int> requestsByPath;

  /// `player_api.php` count per `action` (`login` when absent).
  final Map<String, int> requestsByAction;

  /// Last User-Agent / Referer per first path segment, e.g. `/live`.
  final Map<String, String> userAgents;
  final Map<String, String> referers;

  /// Current [FakeChaosMode.wireName].
  final String chaos;

  /// Sum of [requestsByPath] for paths starting with [prefix].
  int requestsWithPrefix(String prefix) => requestsByPath.entries
      .where((e) => e.key.startsWith(prefix))
      .fold(0, (sum, e) => sum + e.value);

  Map<String, Object?> toJson() => {
    'activeConnections': activeConnections,
    'maxConcurrentSeen': maxConcurrentSeen,
    'maxConcurrentAttempted': maxConcurrentAttempted,
    'openStreams': openStreams,
    'maxOpenStreamsSeen': maxOpenStreamsSeen,
    'acceptedStreams': acceptedStreams,
    'rejectedStreams': rejectedStreams,
    'requestsByPath': requestsByPath,
    'requestsByAction': requestsByAction,
    'userAgents': userAgents,
    'referers': referers,
    'chaos': chaos,
  };
}

/// Fake Xtream Codes panel on a local [HttpServer].
///
/// Endpoints: `player_api.php`, `get.php`, `xmltv.php` (gzip),
/// `epg_plain.xml`, `/live/u/p/id.ts|m3u8`, `/hls/id/seq.ts`,
/// `/movie/u/p/id.ext`, `/series/u/p/id.ext`, `/logo/*.png`, and the
/// instrumentation endpoints `/__stats`, `/__chaos` and `/__config`.
class FakePanel {
  FakePanel._({
    required this._server,
    required this.username,
    required this.password,
    required this.catalog,
    required this.maxConnections,
    required this.auth,
    required this.allowedOutputFormats,
    required this.fullListDelay,
    required this.liveBytesPerSecond,
    required this.liveBurst,
    required this.hlsSegmentDuration,
    required this.hlsWindowSize,
    required this.hlsSessionTimeout,
    required this.epgSpan,
    required this.mediaDir,
    required this.liveMediaFile,
    required this.liveMediaOverrides,
    required this.vodMediaFile,
    required this.syntheticVodBytes,
    required DateTime Function() now,
  }) : _now = now,
       _startedAt = now();

  /// Media per stream id, relative to `mediaDir`; see `tool/gen_media.sh`.
  static const defaultLiveMediaOverrides = <int, String>{
    1002: 'h264_mp2.ts',
    1003: 'h264_ac3.ts',
    1004: 'hevc_aac.ts',
  };

  /// Starts a panel on [port] (0 picks a free one).
  ///
  /// Binds to loopback, or to all IPv4 interfaces when [anyIPv4] is true
  /// (an Android emulator reaches the host as `10.0.2.2`). Generated URLs use
  /// the request's `Host` header, so they work from either side.
  ///
  /// Media comes from [mediaDir] ([liveMediaFile], [liveMediaOverrides] by
  /// stream id, [vodMediaFile]); missing files fall back to synthetic null
  /// TS packets and a [syntheticVodBytes]-long payload whose byte at offset
  /// `i` is [syntheticVodByte]. A null [mediaDir] forces synthetic media; a
  /// relative one resolves against the current directory (the package root
  /// under `flutter test`).
  ///
  /// [maxConnections] of 0 or less means unlimited. [liveBytesPerSecond]
  /// defaults to the media file's own bitrate (128 KiB/s when synthetic).
  /// An HLS viewer keeps its connection until [hlsSessionTimeout] (default
  /// twice [hlsSegmentDuration]) after its last playlist or segment request.
  /// [epgSpan] is how far ahead `xmltv.php` lists programmes.
  static Future<FakePanel> start({
    String username = 'user',
    String password = 'pass',
    int maxConnections = 1,
    FakeAuthMode auth = FakeAuthMode.good,
    int liveCount = 50,
    int vodCount = 30,
    int seriesCount = 10,
    int port = 0,
    bool anyIPv4 = false,
    List<String> allowedOutputFormats = const ['m3u8', 'ts', 'rtmp'],
    Duration fullListDelay = Duration.zero,
    int? liveBytesPerSecond,
    Duration liveBurst = const Duration(seconds: 1),
    Duration hlsSegmentDuration = const Duration(seconds: 2),
    int hlsWindowSize = 4,
    Duration? hlsSessionTimeout,
    Duration epgSpan = const Duration(hours: 24),
    String? mediaDir = 'test/media',
    String liveMediaFile = 'h264_aac.ts',
    Map<int, String> liveMediaOverrides = defaultLiveMediaOverrides,
    String vodMediaFile = 'vod_2audio_ara_eng_srt.mkv',
    int syntheticVodBytes = 2 * 1024 * 1024,
    DateTime Function()? now,
  }) async {
    final server = await HttpServer.bind(
      anyIPv4 ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4,
      port,
    );
    server.defaultResponseHeaders.clear();
    server.serverHeader = 'nginx';
    final panel = FakePanel._(
      server: server,
      username: username,
      password: password,
      catalog: FakeCatalog.generate(
        liveCount: liveCount,
        vodCount: vodCount,
        seriesCount: seriesCount,
      ),
      maxConnections: maxConnections,
      auth: auth,
      allowedOutputFormats: allowedOutputFormats,
      fullListDelay: fullListDelay,
      liveBytesPerSecond: liveBytesPerSecond,
      liveBurst: liveBurst,
      hlsSegmentDuration: hlsSegmentDuration,
      hlsWindowSize: math.max(1, hlsWindowSize),
      hlsSessionTimeout: hlsSessionTimeout ?? hlsSegmentDuration * 2,
      epgSpan: epgSpan,
      mediaDir: mediaDir,
      liveMediaFile: liveMediaFile,
      liveMediaOverrides: liveMediaOverrides,
      vodMediaFile: vodMediaFile,
      syntheticVodBytes: syntheticVodBytes,
      now: now ?? DateTime.now,
    );
    server.listen(
      (req) => unawaited(panel._handle(req)),
      onError: (Object _) {}, // Malformed requests; nothing to answer.
    );
    return panel;
  }

  /// Byte at [offset] of the synthetic VOD payload.
  static int syntheticVodByte(int offset) => offset % 251;

  final HttpServer _server;
  final DateTime Function() _now;
  final DateTime _startedAt;

  final String username;
  final String password;
  final FakeCatalog catalog;
  final List<String> allowedOutputFormats;
  final Duration liveBurst;
  final Duration hlsSegmentDuration;
  final int hlsWindowSize;
  final String? mediaDir;
  final String liveMediaFile;
  final Map<int, String> liveMediaOverrides;
  final String vodMediaFile;
  final int syntheticVodBytes;

  /// Runtime-adjustable behaviour (also via `/__config`).
  FakeAuthMode auth;
  int maxConnections;
  Duration fullListDelay;
  int? liveBytesPerSecond;

  /// Idle time after which an HLS viewer's connection is released; zero
  /// counts HLS requests only while they are in flight.
  Duration hlsSessionTimeout;
  Duration epgSpan;

  final _leases = <_Lease>{};

  /// Expiry timers of HLS viewers by connection key.
  final _hlsSessions = <String, Timer>{};
  final _tsCache = <String, TsLoop>{};
  _VodBody? _vodBody;
  bool _closed = false;

  FakeChaosMode _chaos = FakeChaosMode.off;
  Timer? _chaosTimer;

  int _maxConcurrent = 0;
  int _maxAttempted = 0;
  int _maxOpen = 0;
  int _accepted = 0;
  int _rejected = 0;
  final _byPath = <String, int>{};
  final _byAction = <String, int>{};
  final _userAgents = <String, String>{};
  final _referers = <String, String>{};

  int get port => _server.port;

  /// Address the server is bound to (loopback, or `0.0.0.0` with anyIPv4).
  InternetAddress get address => _server.address;

  /// Loopback URL of the panel, e.g. `http://127.0.0.1:41234`.
  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  FakeChaosMode get chaosMode => _chaos;

  String get _u => Uri.encodeComponent(username);
  String get _p => Uri.encodeComponent(password);
  String get _creds =>
      'username=${Uri.encodeQueryComponent(username)}'
      '&password=${Uri.encodeQueryComponent(password)}';

  /// `player_api.php` URL with the panel's credentials.
  String playerApiUrl({String? action, Map<String, String> params = const {}}) {
    final extra = {'action': ?action, ...params}.entries
        .map(
          (e) =>
              '&${Uri.encodeQueryComponent(e.key)}='
              '${Uri.encodeQueryComponent(e.value)}',
        )
        .join();
    return '$baseUrl/player_api.php?$_creds$extra';
  }

  String m3uUrl({String type = 'm3u_plus', String output = 'ts'}) =>
      '$baseUrl/get.php?$_creds&type=$type&output=$output';
  String get xmltvUrl => '$baseUrl/xmltv.php?$_creds';
  String get plainEpgUrl => '$baseUrl/epg_plain.xml';
  String get statsUrl => '$baseUrl/__stats';
  String liveUrl(int streamId, {String ext = 'ts'}) =>
      '$baseUrl/live/$_u/$_p/$streamId.$ext';
  String movieUrl(int streamId, {String? ext}) =>
      '$baseUrl/movie/$_u/$_p/$streamId.'
      '${ext ?? catalog.movieById(streamId)?.ext ?? 'mp4'}';
  String episodeUrl(int episodeId, {String? ext}) =>
      '$baseUrl/series/$_u/$_p/$episodeId.'
      '${ext ?? catalog.episodeById(episodeId)?.ext ?? 'mp4'}';

  /// Guide for [channel] relative to the panel clock, [epgSpan] by default.
  List<FakeProgramme> programmes(FakeChannel channel, {Duration? span}) =>
      catalog.programmesFor(channel, _now(), span: span ?? epgSpan);

  /// Whether live stream [streamId] is backed by a real media file.
  bool liveUsesMediaFile(int streamId) => !_liveSource(streamId).isSynthetic;

  /// Whether VOD is backed by a real media file.
  bool get vodUsesMediaFile => _vod() is _FileBody;

  FakePanelStats get stats => FakePanelStats(
    activeConnections: _activeKeys.length,
    maxConcurrentSeen: _maxConcurrent,
    maxConcurrentAttempted: _maxAttempted,
    openStreams: _leases.where((l) => l.isStream).length,
    maxOpenStreamsSeen: _maxOpen,
    acceptedStreams: _accepted,
    rejectedStreams: _rejected,
    requestsByPath: Map.of(_byPath),
    requestsByAction: Map.of(_byAction),
    userAgents: Map.of(_userAgents),
    referers: Map.of(_referers),
    chaos: _chaos.wireName,
  );

  /// Clears counters; open connections stay counted as active.
  void resetStats() {
    _maxConcurrent = _activeKeys.length;
    _maxAttempted = _maxConcurrent;
    _maxOpen = _leases.where((l) => l.isStream).length;
    _accepted = 0;
    _rejected = 0;
    _byPath.clear();
    _byAction.clear();
    _userAgents.clear();
    _referers.clear();
  }

  /// Polls [stats] until [test] passes; throws [TimeoutException] otherwise.
  Future<FakePanelStats> waitForStats(
    bool Function(FakePanelStats s) test, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final sw = Stopwatch()..start();
    while (true) {
      final s = stats;
      if (test(s)) return s;
      if (sw.elapsed > timeout) {
        throw TimeoutException('Stats condition not met: ${s.toJson()}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// Injects a stream fault, replacing any previous one.
  ///
  /// - [FakeChaosMode.drop]: after [after], destroys every open stream socket
  ///   and forgets HLS viewers once, then returns to [FakeChaosMode.off].
  /// - [FakeChaosMode.forbidden]: new stream requests get 403.
  /// - [FakeChaosMode.stall]: streams send no bytes (sockets stay open).
  ///
  /// [duration] ends forbidden/stall automatically; null means until changed.
  void setChaos(
    FakeChaosMode mode, {
    Duration after = Duration.zero,
    Duration? duration,
  }) {
    _chaosTimer?.cancel();
    _chaosTimer = null;
    _chaos = mode;
    switch (mode) {
      case FakeChaosMode.off:
        break;
      case FakeChaosMode.drop:
        void fire() {
          _chaosTimer = null;
          _chaos = FakeChaosMode.off;
          _endHlsSessions();
          for (final l in _leases.where((l) => l.isStream).toList()) {
            l.close();
          }
        }
        if (after <= Duration.zero) {
          fire();
        } else {
          _chaosTimer = Timer(after, fire);
        }
      case FakeChaosMode.forbidden:
      case FakeChaosMode.stall:
        if (duration != null) {
          _chaosTimer = Timer(duration, () {
            _chaosTimer = null;
            _chaos = FakeChaosMode.off;
          });
        }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _chaosTimer?.cancel();
    _endHlsSessions();
    for (final l in _leases.toList()) {
      l.close();
    }
    await _server.close(force: true);
  }

  // ---------------------------------------------------------------- routing

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      final segs = req.uri.pathSegments;
      if (!path.startsWith('/__')) _record(req, segs);
      switch (path) {
        case '/player_api.php':
          return await _playerApi(req);
        case '/get.php':
          return await _getPhp(req);
        case '/xmltv.php':
          return await _xmltv(req, gzipped: true);
        case '/epg_plain.xml':
          return await _xmltv(req, gzipped: false);
        case '/__stats':
          final snapshot = stats.toJson();
          if (req.uri.queryParameters['reset'] == '1') resetStats();
          return await _json(req, snapshot);
        case '/__chaos':
          return await _chaosEndpoint(req);
        case '/__config':
          return await _configEndpoint(req);
      }
      if (segs.length == 4 && segs[0] == 'live') return await _live(req, segs);
      if (segs.length == 4 && (segs[0] == 'movie' || segs[0] == 'series')) {
        return await _vodStream(req, segs);
      }
      if (segs.length == 3 && segs[0] == 'hls') return await _hlsSegment(req);
      if (segs.length == 2 && segs[0] == 'logo') return await _logo(req);
      await _text(req, 404, 'Not found');
    } catch (_) {
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (_) {
        // The response was already started or the client went away.
      }
    }
  }

  void _record(HttpRequest req, List<String> segs) {
    final path = req.uri.path;
    _byPath[path] = (_byPath[path] ?? 0) + 1;
    final prefix = segs.isEmpty ? '/' : '/${segs.first}';
    final ua = req.headers.value(HttpHeaders.userAgentHeader);
    if (ua != null) _userAgents[prefix] = ua;
    final ref = req.headers.value(HttpHeaders.refererHeader);
    if (ref != null) _referers[prefix] = ref;
    if (path == '/player_api.php') {
      final action = req.uri.queryParameters['action'];
      final key = (action == null || action.isEmpty) ? 'login' : action;
      _byAction[key] = (_byAction[key] ?? 0) + 1;
    }
  }

  String _origin(HttpRequest req) =>
      'http://${req.headers.value(HttpHeaders.hostHeader) ?? '127.0.0.1:$port'}';

  bool _credsOk(String? u, String? p) => u == username && p == password;

  bool get _blocked =>
      auth == FakeAuthMode.expired ||
      auth == FakeAuthMode.banned ||
      auth == FakeAuthMode.disabled;

  /// 401 for wrong credentials, 403 for a blocked account, else null.
  int? _accessError(String? u, String? p) {
    if (!_credsOk(u, p)) return HttpStatus.unauthorized;
    if (_blocked) return HttpStatus.forbidden;
    return null;
  }

  // ------------------------------------------------------------ player_api

  Future<void> _playerApi(HttpRequest req) async {
    final q = req.uri.queryParameters;
    if (!_credsOk(q['username'], q['password'])) {
      return _json(req, {
        'user_info': {'auth': 0},
      });
    }
    switch (auth) {
      case FakeAuthMode.emptyArray:
        return _json(req, const <Object?>[]);
      case FakeAuthMode.auth0WithHttp200:
        return _json(req, {
          'user_info': {'auth': 0},
        });
      case FakeAuthMode.good:
      case FakeAuthMode.expired:
      case FakeAuthMode.banned:
      case FakeAuthMode.disabled:
        break;
    }
    final action = q['action'];
    if (action == null || action.isEmpty || auth != FakeAuthMode.good) {
      return _json(req, _loginBody(req));
    }
    final origin = _origin(req);
    final cat = q['category_id'];
    Future<void> fullListDelayIfNeeded() async {
      if (cat == null && fullListDelay > Duration.zero) {
        await Future<void>.delayed(fullListDelay);
      }
    }

    switch (action) {
      case 'get_live_categories':
        return _json(req, [
          for (final c in catalog.liveCategories)
            {
              'category_id': c.id == '3' ? 3 : c.id,
              'category_name': c.name,
              'parent_id': 0,
            },
        ]);
      case 'get_vod_categories':
        return _json(req, _categoriesJson(catalog.vodCategories));
      case 'get_series_categories':
        return _json(req, _categoriesJson(catalog.seriesCategories));
      case 'get_live_streams':
        await fullListDelayIfNeeded();
        return _json(req, [
          for (final c in catalog.live)
            if (cat == null || c.categoryIds.contains(cat))
              _liveJson(c, origin),
        ]);
      case 'get_vod_streams':
        await fullListDelayIfNeeded();
        return _json(req, [
          for (final m in catalog.movies)
            if (cat == null || m.categoryId == cat) _movieJson(m, origin),
        ]);
      case 'get_series':
        await fullListDelayIfNeeded();
        return _json(req, [
          for (final s in catalog.series)
            if (cat == null || s.categoryId == cat) _seriesJson(s, origin),
        ]);
      case 'get_vod_info':
        final m = catalog.movieById(int.tryParse(q['vod_id'] ?? ''));
        return _json(req, m == null ? const <Object?>[] : _vodInfo(m, origin));
      case 'get_series_info':
        final s = catalog.seriesById(int.tryParse(q['series_id'] ?? ''));
        return _json(
          req,
          s == null ? const <Object?>[] : _seriesInfo(s, origin),
        );
      case 'get_short_epg':
        return _json(req, _shortEpg(q));
      default:
        return _json(req, const <Object?>[]);
    }
  }

  Map<String, Object?> _loginBody(HttpRequest req) {
    final now = _now().toUtc();
    final epoch = now.millisecondsSinceEpoch ~/ 1000;
    return {
      'user_info': {
        'username': username,
        'password': password,
        'message': 'Fake panel (synthetic data)',
        'auth': 1,
        'status': switch (auth) {
          FakeAuthMode.expired => 'Expired',
          FakeAuthMode.banned => 'Banned',
          FakeAuthMode.disabled => 'Disabled',
          _ => 'Active',
        },
        'exp_date': switch (auth) {
          FakeAuthMode.expired => '${epoch - 2 * 86400}',
          FakeAuthMode.banned || FakeAuthMode.disabled => null,
          _ => '${epoch + 30 * 86400}',
        },
        'is_trial': '0',
        'active_cons': '${_activeKeys.length}',
        'created_at': '${epoch - 90 * 86400}',
        'max_connections': '$maxConnections',
        'allowed_output_formats': allowedOutputFormats,
      },
      'server_info': {
        // Both follow the Host header, like every generated URL.
        'url': req.headers.host ?? '127.0.0.1',
        'port': '${req.headers.port ?? port}',
        'https_port': '',
        'server_protocol': 'http',
        'rtmp_port': '',
        'timezone': 'Asia/Riyadh',
        'timestamp_now': epoch,
        'time_now': _riyadhTime(now),
        'process': true,
      },
    };
  }

  List<Map<String, Object?>> _categoriesJson(List<FakeCategory> cats) => [
    for (final c in cats)
      {'category_id': c.id, 'category_name': c.name, 'parent_id': 0},
  ];

  Map<String, Object?> _liveJson(FakeChannel c, String origin) => {
    'num': c.index % 3 == 0 ? '${c.index}' : c.index,
    'name': c.name,
    'stream_type': 'live',
    'stream_id': c.index.isEven ? '${c.id}' : c.id,
    'stream_icon': c.index % 5 == 0 ? '' : '$origin/logo/live${c.id}.png',
    'epg_channel_id': c.epgId,
    'added': '1700000000',
    'is_adult': c.index.isEven ? '0' : 0,
    'category_id': c.categoryId,
    'category_ids': [for (final id in c.categoryIds) int.parse(id)],
    'custom_sid': c.index % 4 == 0 ? null : '',
    'tv_archive': c.index % 9 == 0 ? '1' : 0,
    'direct_source': '',
    'tv_archive_duration': c.index % 9 == 0 ? '3' : 0,
    'thumbnail': '',
  };

  Map<String, Object?> _movieJson(FakeMovie m, String origin) => {
    'num': m.index,
    'name': m.name,
    'title': m.name,
    'year': m.index.isEven ? '${2000 + m.index % 25}' : '',
    'stream_type': 'movie',
    'stream_id': m.index % 3 == 0 ? '${m.id}' : m.id,
    'stream_icon': m.index % 4 == 0 ? '' : '$origin/logo/movie${m.id}.png',
    'rating': m.index % 4 == 0 ? '' : (m.index.isEven ? '7.5' : 6.5),
    'rating_5based': m.index % 4 == 0 ? 0 : 3.5,
    'added': '${1700000000 + m.index * 3600}',
    'is_adult': '0',
    'category_id': m.categoryId,
    'category_ids': [int.parse(m.categoryId)],
    'container_extension': m.ext,
    'custom_sid': '',
    'direct_source': '',
  };

  Map<String, Object?> _seriesJson(FakeSeries s, String origin) => {
    'num': s.index,
    'name': s.name,
    'title': s.name,
    'year': '2021',
    'series_id': s.index.isEven ? '${s.id}' : s.id,
    'cover': s.index % 3 == 0 ? '' : '$origin/logo/series${s.id}.png',
    'plot': s.isArabic ? 'قصة تجريبية للمسلسل ${s.index}' : 'Synthetic plot',
    'cast': '',
    'director': '',
    'genre': 'Drama',
    'releaseDate': '2021-01-01',
    'release_date': '2021-01-01',
    'last_modified': '${1700000000 + s.index * 60}',
    'rating': s.index.isOdd ? '8.1' : '',
    'rating_5based': s.index.isOdd ? 4.05 : '0',
    'backdrop_path': s.index.isOdd
        ? const <String>[]
        : ['$origin/logo/backdrop${s.id}.png'],
    'youtube_trailer': '',
    'episode_run_time': s.index.isOdd ? '45' : '',
    'category_id': s.categoryId,
    'category_ids': [int.parse(s.categoryId)],
  };

  Map<String, Object?> _vodInfo(FakeMovie m, String origin) => {
    'info': {
      'tmdb_id': '',
      'name': m.name,
      'o_name': m.name,
      'movie_image': '$origin/logo/movie${m.id}.png',
      'cover_big': '',
      'releasedate': '2020-05-01',
      'youtube_trailer': '',
      'director': 'Director ${m.index}',
      'actors': 'Actor A, ممثل ب',
      'cast': 'Actor A, ممثل ب',
      'description': m.isArabic ? 'قصة فيلم تجريبي' : 'Synthetic movie plot',
      'plot': m.isArabic ? 'قصة فيلم تجريبي' : 'Synthetic movie plot',
      'genre': 'Drama',
      'backdrop_path': m.index.isEven ? const <String>[] : [''],
      'duration_secs': m.index.isEven ? 5400 : '5400',
      'duration': '01:30:00',
      'bitrate': 0,
      'rating': m.index % 4 == 0 ? '' : '7.5',
    },
    'movie_data': {
      'stream_id': m.id,
      'name': m.name,
      'added': '${1700000000 + m.index * 3600}',
      'category_id': m.categoryId,
      'category_ids': [int.parse(m.categoryId)],
      'container_extension': m.ext,
      'custom_sid': '',
      'direct_source': '',
    },
  };

  Map<String, Object?> _seriesInfo(FakeSeries s, String origin) {
    Map<String, Object?> episode(FakeEpisode e, bool first) => {
      'id': '${e.id}',
      'episode_num': e.number.isOdd ? e.number : '${e.number}',
      'title': e.title,
      'container_extension': e.ext,
      'info': (first && !s.episodesAsMap)
          ? const <Object?>[]
          : {
              'duration_secs': 1200,
              'duration': '00:20:00',
              'plot': s.isArabic ? 'حلقة تجريبية' : 'Synthetic episode',
              'movie_image': '',
              'rating': '',
            },
      'custom_sid': '',
      'added': '1700000000',
      'season': e.season.isEven ? '${e.season}' : e.season,
      'direct_source': '',
    };

    final episodes = [
      for (final (i, e) in s.episodes.indexed) episode(e, i == 0),
    ];
    return {
      'seasons': s.emptyInfo
          ? const <Object?>[]
          : [
              for (var n = 1; n <= s.seasonCount; n++)
                {
                  'air_date': '2021-01-01',
                  'episode_count': s.episodes
                      .where((e) => e.season == n)
                      .length,
                  'id': s.id * 10 + n,
                  'name': s.isArabic ? 'الموسم $n' : 'Season $n',
                  'overview': '',
                  'season_number': n,
                  'cover': '',
                  'cover_big': '',
                },
            ],
      'info': s.emptyInfo
          ? const <Object?>[]
          : {
              'name': s.name,
              'cover': '$origin/logo/series${s.id}.png',
              'plot': s.isArabic ? 'قصة تجريبية' : 'Synthetic plot',
              'cast': '',
              'director': '',
              'genre': 'Drama',
              'releaseDate': '2021-01-01',
              'last_modified': '1700000000',
              'rating': '8',
              'rating_5based': 4,
              'backdrop_path': [''],
              'youtube_trailer': '',
              'episode_run_time': '20',
              'category_id': s.categoryId,
            },
      'episodes': s.episodesAsMap
          ? {
              for (var n = 1; n <= s.seasonCount; n++)
                '$n': [
                  for (final (i, e) in s.episodes.indexed)
                    if (e.season == n) episodes[i],
                ],
            }
          : episodes,
    };
  }

  Map<String, Object?> _shortEpg(Map<String, String> q) {
    final ch = catalog.channelById(int.tryParse(q['stream_id'] ?? ''));
    if (ch == null || !ch.hasEpgId) return {'epg_listings': const <Object?>[]};
    final limit = int.tryParse(q['limit'] ?? '') ?? 4;
    String b64(String s) => base64.encode(utf8.encode(s));
    int sec(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
    return {
      'epg_listings': [
        for (final (i, p) in programmes(ch).take(limit).indexed)
          {
            'id': '${ch.id}${sec(p.start)}',
            'epg_id': '${ch.index}',
            'title': b64(p.title),
            'lang': p.lang,
            'start': _riyadhTime(p.start),
            'end': _riyadhTime(p.stop),
            'description': b64(p.description),
            'channel_id': ch.xmltvId,
            'start_timestamp': '${sec(p.start)}',
            'stop_timestamp': '${sec(p.stop)}',
            'now_playing': i == 0 ? 1 : 0,
            'has_archive': 0,
          },
      ],
    };
  }

  // ------------------------------------------------------------ M3U, XMLTV

  Future<void> _getPhp(HttpRequest req) async {
    final q = req.uri.queryParameters;
    final err = _accessError(q['username'], q['password']);
    if (err != null) return _text(req, err, 'Access denied');
    final origin = _origin(req);
    final plus = q['type'] == 'm3u_plus';
    final output = q['output'] ?? 'ts';
    final liveExt = (output == 'm3u8' || output == 'hls') ? 'm3u8' : 'ts';
    final epg = '$origin/xmltv.php?$_creds';
    // Header values must be ASCII; percent-encode non-ASCII usernames.
    final file =
        'tv_channels_${Uri.encodeComponent(username)}_'
        '${plus ? 'plus' : 'm3u'}.m3u';
    final res = req.response
      ..headers.contentType = ContentType('application', 'octet-stream')
      ..headers.set('content-disposition', 'attachment; filename="$file"');
    final w = _SliceWriter(res)
      ..writeln(plus ? '#EXTM3U url-tvg="$epg" x-tvg-url="$epg"' : '#EXTM3U');
    Future<void> entry(
      String name,
      String url, {
      String id = '',
      String logo = '',
      String group = '',
    }) async {
      w
        ..writeln(
          plus
              ? '#EXTINF:-1 tvg-id="$id" tvg-name="$name" tvg-logo="$logo" '
                    'group-title="$group",$name'
              : '#EXTINF:-1,$name',
        )
        ..writeln(url);
      if (w.isFull) await w.flush();
    }

    for (final c in catalog.live) {
      await entry(
        c.name,
        '$origin/live/$_u/$_p/${c.id}.$liveExt',
        id: c.epgId ?? '',
        logo: c.index % 5 == 0 ? '' : '$origin/logo/live${c.id}.png',
        group: catalog.categoryName(c.categoryId),
      );
    }
    for (final m in catalog.movies) {
      await entry(
        m.name,
        '$origin/movie/$_u/$_p/${m.id}.${m.ext}',
        group: catalog.categoryName(m.categoryId),
      );
    }
    for (final s in catalog.series) {
      for (final e in s.episodes) {
        await entry(
          '${s.name} S${_two(e.season)} E${_two(e.number)}',
          '$origin/series/$_u/$_p/${e.id}.${e.ext}',
          group: catalog.categoryName(s.categoryId),
        );
      }
    }
    await w.close();
  }

  /// Streams the guide in slices, so a large catalog neither blocks other
  /// requests nor builds the whole document in memory.
  Future<void> _xmltv(HttpRequest req, {required bool gzipped}) async {
    if (gzipped) {
      final q = req.uri.queryParameters;
      final err = _accessError(q['username'], q['password']);
      if (err != null) return _text(req, err, 'Access denied');
    }
    final origin = _origin(req);
    final now = _now();
    final res = req.response
      ..headers.contentType = gzipped
          ? ContentType('application', 'gzip')
          : ContentType('application', 'xml', charset: 'utf-8');
    final w = _SliceWriter(res, gzipped: gzipped)
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<!DOCTYPE tv SYSTEM "xmltv.dtd">')
      ..writeln(
        '<tv generator-info-name="fake_panel" '
        'generator-info-url="${_xml(origin)}">',
      );
    for (final c in catalog.live) {
      w.writeln(
        '  <channel id="${_xml(c.xmltvId)}">'
        '<display-name>${_xml(c.name)}</display-name>'
        '<icon src="${_xml('$origin/logo/live${c.id}.png')}"/></channel>',
      );
      if (w.isFull) await w.flush();
    }
    for (final c in catalog.live) {
      // Every third channel uses a +0300 local offset for the same instants.
      final offset = c.index % 3 == 0 ? 180 : 0;
      for (final p in catalog.programmesFor(c, now, span: epgSpan)) {
        w.writeln(
          '  <programme start="${_xmltvTime(p.start, offset)}" '
          'stop="${_xmltvTime(p.stop, offset)}" channel="${_xml(c.xmltvId)}">'
          '<title lang="${p.lang}">${_xml(p.title)}</title>'
          '<desc lang="${p.lang}">${_xml(p.description)}</desc>'
          '<category lang="en">${c.isArabic ? 'News' : 'Entertainment'}'
          '</category></programme>',
        );
      }
      if (w.isFull) await w.flush();
    }
    w.writeln('</tv>');
    await w.close();
  }

  // ---------------------------------------------------------------- streams

  Set<String> get _activeKeys => {
    for (final l in _leases) l.key,
    ..._hlsSessions.keys,
  };

  /// Admits a stream request or returns null after answering 403.
  Future<_Lease?> _acquire(HttpRequest req, String stream) async {
    final key = '${req.connectionInfo?.remoteAddress.address ?? '?'}|$stream';
    final active = _activeKeys;
    final held = active.contains(key);
    final overLimit =
        maxConnections > 0 && !held && active.length >= maxConnections;
    if (!_closed) {
      _maxAttempted = math.max(_maxAttempted, active.length + (held ? 0 : 1));
    }
    if (_chaos == FakeChaosMode.forbidden || overLimit || _closed) {
      _rejected++;
      await _text(
        req,
        HttpStatus.forbidden,
        overLimit ? 'Max connections reached' : 'Forbidden',
      );
      return null;
    }
    final lease = _Lease(key, _leases.remove);
    _leases.add(lease);
    _accepted++;
    _maxConcurrent = math.max(_maxConcurrent, _activeKeys.length);
    return lease;
  }

  /// Writes headers, detaches the socket and tracks it on [lease].
  Future<Socket?> _detach(HttpResponse res, _Lease lease) async {
    try {
      res.persistentConnection = false;
      res.headers.chunkedTransferEncoding = false;
      final socket = await res.detachSocket();
      lease.attach(socket);
      _maxOpen = math.max(_maxOpen, _leases.where((l) => l.isStream).length);
      return lease.closed ? null : socket;
    } catch (_) {
      lease.close();
      return null;
    }
  }

  bool get _stalled => _chaos == FakeChaosMode.stall;

  static (int?, String) _idExt(String file) {
    final dot = file.lastIndexOf('.');
    return dot < 0
        ? (int.tryParse(file), '')
        : (int.tryParse(file.substring(0, dot)), file.substring(dot + 1));
  }

  Future<void> _live(HttpRequest req, List<String> segs) async {
    final err = _accessError(segs[1], segs[2]);
    if (err != null) return _text(req, err, 'Access denied');
    final (id, ext) = _idExt(segs[3]);
    final ch = catalog.channelById(id);
    if (ch == null || (ext != 'ts' && ext != 'm3u8' && ext != '')) {
      return _text(req, 404, 'Not found');
    }
    if (ext == 'm3u8') return _hlsPlaylist(req, ch);
    final src = _liveSource(ch.id);
    final res = req.response;
    if (req.method == 'HEAD') {
      res.headers.contentType = ContentType('video', 'mp2t');
      return res.close();
    }
    final lease = await _acquire(req, 'live:${ch.id}');
    if (lease == null) return;
    res.headers.contentType = ContentType('video', 'mp2t');
    final socket = await _detach(res, lease);
    if (socket == null) return;
    final rate = _liveRate(src);
    // Join at the live edge (keyframe-aligned), like a real panel: a
    // reconnect continues forward in time instead of restarting.
    final origin = src.hasKeyframeIndex
        ? src
              .segment(_hlsFirstSequence(src), hlsSegmentDuration, rate)
              .firstPacket
        : 0;
    final perSecond = math.max(1, rate ~/ TsLoop.packetSize);
    final maxChunk = math.max(1, perSecond ~/ 4);
    var base = math.max(1, perSecond * liveBurst.inMilliseconds ~/ 1000);
    var sent = 0;
    final clock = Stopwatch()..start();
    while (!lease.closed) {
      if (_stalled) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        base = sent;
        clock.reset();
        continue;
      }
      final due = base + clock.elapsedMicroseconds * perSecond ~/ 1000000;
      if (due <= sent) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        continue;
      }
      final n = math.min(due - sent, maxChunk);
      if (!await lease.write(src.read(origin + sent, n))) break;
      sent += n;
    }
  }

  int _liveRate(TsLoop src) =>
      liveBytesPerSecond ?? src.nominalBytesPerSecond ?? 131072;

  /// Sequence number of the oldest segment in the live window.
  int _hlsFirstSequence(TsLoop src) =>
      src.segmentAt(_now().difference(_startedAt), hlsSegmentDuration);

  /// Starts or extends the HLS viewer session [key]. With [create] false,
  /// only a session that still exists is extended (a chaos drop ends it).
  void _touchHls(String key, {bool create = true}) {
    final old = _hlsSessions.remove(key);
    old?.cancel();
    if (_closed || hlsSessionTimeout <= Duration.zero) return;
    if (old == null && !create) return;
    _hlsSessions[key] = Timer(hlsSessionTimeout, () {
      _hlsSessions.remove(key);
    });
  }

  void _endHlsSessions() {
    for (final t in _hlsSessions.values) {
      t.cancel();
    }
    _hlsSessions.clear();
  }

  Future<void> _hlsPlaylist(HttpRequest req, FakeChannel ch) async {
    final lease = await _acquire(req, 'hls:${ch.id}');
    if (lease == null) return;
    _touchHls(lease.key);
    try {
      final src = _liveSource(ch.id);
      final rate = _liveRate(src);
      final first = _hlsFirstSequence(src);
      final segments = [
        for (var s = first; s < first + hlsWindowSize; s++)
          src.segment(s, hlsSegmentDuration, rate),
      ];
      final b = StringBuffer()
        ..writeln('#EXTM3U')
        ..writeln('#EXT-X-VERSION:3')
        ..writeln(
          '#EXT-X-TARGETDURATION:'
          '${src.targetDurationSeconds(hlsSegmentDuration)}',
        )
        ..writeln('#EXT-X-MEDIA-SEQUENCE:$first');
      for (final (i, seg) in segments.indexed) {
        final secs = seg.duration.inMicroseconds / 1e6;
        b
          ..writeln('#EXTINF:${secs.toStringAsFixed(3)},')
          ..writeln('/hls/${ch.id}/${first + i}.ts');
      }
      final res = req.response
        ..headers.contentType = ContentType('application', 'vnd.apple.mpegurl')
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      res.add(utf8.encode(b.toString()));
      await res.close();
    } finally {
      lease.close();
      _touchHls(lease.key, create: false);
    }
  }

  Future<void> _hlsSegment(HttpRequest req) async {
    if (_blocked) return _text(req, HttpStatus.forbidden, 'Access denied');
    final segs = req.uri.pathSegments;
    final ch = catalog.channelById(int.tryParse(segs[1]));
    final (seq, ext) = _idExt(segs[2]);
    if (ch == null || seq == null || ext != 'ts') {
      return _text(req, 404, 'Not found');
    }
    final src = _liveSource(ch.id);
    final first = _hlsFirstSequence(src);
    // Keep one window of old segments; refuse ones not yet in a playlist.
    if (seq < first - hlsWindowSize || seq >= first + hlsWindowSize) {
      return _text(req, 404, 'Not found');
    }
    final seg = src.segment(seq, hlsSegmentDuration, _liveRate(src));
    void setHeaders(HttpResponse res) => res.headers
      ..contentType = ContentType('video', 'mp2t')
      ..contentLength = seg.packetCount * TsLoop.packetSize;
    if (req.method == 'HEAD') {
      setHeaders(req.response);
      return req.response.close();
    }
    final lease = await _acquire(req, 'hls:${ch.id}');
    if (lease == null) return;
    _touchHls(lease.key);
    try {
      setHeaders(req.response);
      final socket = await _detach(req.response, lease);
      if (socket == null) return;
      const chunk = 256;
      for (var i = 0; i < seg.packetCount && !lease.closed;) {
        if (_stalled) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          continue;
        }
        final n = math.min(chunk, seg.packetCount - i);
        if (!await lease.write(src.read(seg.firstPacket + i, n))) break;
        i += n;
      }
      await lease.finish();
    } finally {
      _touchHls(lease.key, create: false);
    }
  }

  Future<void> _vodStream(HttpRequest req, List<String> segs) async {
    final err = _accessError(segs[1], segs[2]);
    if (err != null) return _text(req, err, 'Access denied');
    final (id, ext) = _idExt(segs[3]);
    final exists = segs[0] == 'movie'
        ? catalog.movieById(id) != null
        : catalog.episodeById(id) != null;
    if (!exists) return _text(req, 404, 'Not found');
    final body = _vod();
    final size = body.length;
    final range = _parseRange(req.headers.value(HttpHeaders.rangeHeader), size);
    if (range == null) {
      final res = req.response
        ..statusCode = HttpStatus.requestedRangeNotSatisfiable
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
      return res.close();
    }
    final (start, end, partial) = range;
    void setHeaders(HttpResponse res) {
      res.headers
        ..contentType = _vodContentType(ext)
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentLength = end - start + 1;
      if (partial) {
        res
          ..statusCode = HttpStatus.partialContent
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/$size',
          );
      }
    }

    if (req.method == 'HEAD') {
      setHeaders(req.response);
      return req.response.close();
    }
    // Admit first: a 403 must not carry the media's headers.
    final lease = await _acquire(req, '${segs[0]}:$id');
    if (lease == null) return;
    setHeaders(req.response);
    final socket = await _detach(req.response, lease);
    if (socket == null) return;
    await for (final bytes in body.range(start, end, 64 * 1024)) {
      while (_stalled && !lease.closed) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      if (!await lease.write(bytes)) break;
    }
    await lease.finish();
  }

  /// `(start, end, partial)`; null when unsatisfiable (416). Malformed or
  /// multi-range headers are ignored and the whole body is served.
  static (int, int, bool)? _parseRange(String? header, int size) {
    final full = (0, size - 1, false);
    if (header == null) return full;
    final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (m == null) return full;
    final a = int.tryParse(m[1]!);
    final b = int.tryParse(m[2]!);
    if (a == null) {
      if (b == null) return full;
      if (b == 0 || size == 0) return null;
      return (math.max(0, size - b), size - 1, true);
    }
    if (a >= size) return null;
    if (b != null && b < a) return full;
    return (a, math.min(b ?? size - 1, size - 1), true);
  }

  static ContentType _vodContentType(String ext) => switch (ext) {
    'mkv' => ContentType('video', 'x-matroska'),
    'mp4' || 'm4v' => ContentType('video', 'mp4'),
    'avi' => ContentType('video', 'x-msvideo'),
    'ts' => ContentType('video', 'mp2t'),
    _ => ContentType('application', 'octet-stream'),
  };

  TsLoop _liveSource(int streamId) {
    final names = [?liveMediaOverrides[streamId], liveMediaFile];
    for (final name in names) {
      final loop = _tsCache.putIfAbsent(name, () {
        final file = _mediaFile(name);
        if (file == null) return TsLoop.synthetic();
        return TsLoop.tryParse(file.readAsBytesSync()) ?? TsLoop.synthetic();
      });
      if (!loop.isSynthetic) return loop;
    }
    return _tsCache.putIfAbsent('', TsLoop.synthetic);
  }

  _VodBody _vod() => _vodBody ??= () {
    final file = _mediaFile(vodMediaFile);
    if (file != null) return _FileBody(file, file.lengthSync());
    return _SyntheticBody(syntheticVodBytes);
  }();

  File? _mediaFile(String name) {
    final dir = mediaDir;
    if (dir == null) return null;
    final file = File(File(name).isAbsolute ? name : '$dir/$name');
    return file.existsSync() ? file : null;
  }

  Future<void> _logo(HttpRequest req) async {
    final res = req.response..headers.contentType = ContentType('image', 'png');
    res.add(_png1x1);
    await res.close();
  }

  // ---------------------------------------------------------- instruments

  Future<void> _chaosEndpoint(HttpRequest req) async {
    final q = req.uri.queryParameters;
    final mode = FakeChaosMode.parse(q['mode']);
    if (mode == null) {
      return _text(req, 400, 'mode must be one of: drop, 403, stall, off');
    }
    Duration? secs(String? v) {
      final d = double.tryParse(v ?? '');
      return d == null ? null : Duration(microseconds: (d * 1e6).round());
    }

    setChaos(
      mode,
      after: secs(q['after']) ?? Duration.zero,
      duration: secs(q['for']),
    );
    return _json(req, {'chaos': mode.wireName});
  }

  Future<void> _configEndpoint(HttpRequest req) async {
    final q = req.uri.queryParameters;
    if (q['auth'] case final a?) {
      final mode = FakeAuthMode.values.where((m) => m.name == a).firstOrNull;
      if (mode == null) return _text(req, 400, 'Unknown auth mode');
      auth = mode;
    }
    if (int.tryParse(q['maxConnections'] ?? '') case final n?) {
      maxConnections = n;
    }
    if (int.tryParse(q['fullListDelayMs'] ?? '') case final n?) {
      fullListDelay = Duration(milliseconds: n);
    }
    if (int.tryParse(q['liveBytesPerSecond'] ?? '') case final n?) {
      liveBytesPerSecond = n > 0 ? n : null;
    }
    if (int.tryParse(q['hlsSessionTimeoutMs'] ?? '') case final n?) {
      hlsSessionTimeout = Duration(milliseconds: n);
    }
    if (int.tryParse(q['epgHours'] ?? '') case final n?) {
      epgSpan = Duration(hours: n);
    }
    return _json(req, {
      'auth': auth.name,
      'maxConnections': maxConnections,
      'fullListDelayMs': fullListDelay.inMilliseconds,
      'liveBytesPerSecond': liveBytesPerSecond,
      'hlsSessionTimeoutMs': hlsSessionTimeout.inMilliseconds,
      'epgHours': epgSpan.inHours,
    });
  }

  // ---------------------------------------------------------------- helpers

  Future<void> _json(HttpRequest req, Object? body, {int status = 200}) async {
    final res = req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json;
    res.add(utf8.encode(jsonEncode(body)));
    await res.close();
  }

  Future<void> _text(HttpRequest req, int status, String body) async {
    final res = req.response
      ..statusCode = status
      ..headers.contentType = ContentType.text;
    res.write(body);
    await res.close();
  }

  /// `yyyy-MM-dd HH:mm:ss` in the panel's advertised zone (UTC+3).
  static String _riyadhTime(DateTime utc) {
    final t = utc.toUtc().add(const Duration(hours: 3));
    return '${t.year}-${_two(t.month)}-${_two(t.day)} '
        '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
  }

  /// XMLTV `yyyyMMddHHmmss ±HHMM` for [utc] shown at [offsetMin].
  static String _xmltvTime(DateTime utc, int offsetMin) {
    final t = utc.toUtc().add(Duration(minutes: offsetMin));
    final sign = offsetMin < 0 ? '-' : '+';
    final off = offsetMin.abs();
    return '${t.year}${_two(t.month)}${_two(t.day)}'
        '${_two(t.hour)}${_two(t.minute)}${_two(t.second)} '
        '$sign${_two(off ~/ 60)}${_two(off % 60)}';
  }

  static String _xml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

String _two(int n) => n.toString().padLeft(2, '0');

/// One admitted stream request; [key] groups requests into connections.
class _Lease {
  _Lease(this.key, this._onClose);

  final String key;
  final void Function(_Lease) _onClose;
  Socket? _socket;
  bool closed = false;

  bool get isStream => _socket != null;

  void attach(Socket socket) {
    _socket = socket;
    socket.listen(
      (_) {},
      onError: (Object _) => close(),
      onDone: close,
      cancelOnError: true,
    );
    unawaited(socket.done.then<void>((_) {}, onError: (Object _) {}));
  }

  /// Writes [bytes] and waits for the socket to accept them.
  Future<bool> write(Uint8List bytes) async {
    final s = _socket;
    if (closed || s == null) return false;
    try {
      s.add(bytes);
      await s.flush();
      return !closed;
    } catch (_) {
      close();
      return false;
    }
  }

  /// Ends a response that has a known length.
  Future<void> finish() async {
    final s = _socket;
    if (!closed && s != null) {
      try {
        await s.flush();
        await s.close();
      } catch (_) {
        // Client already gone.
      }
    }
    close();
  }

  void close() {
    if (closed) return;
    closed = true;
    _socket?.destroy();
    _onClose(this);
  }
}

sealed class _VodBody {
  int get length;

  /// Bytes `start..end` (inclusive) in chunks of at most [chunk] bytes.
  Stream<Uint8List> range(int start, int end, int chunk);
}

/// A media file read from disk chunk by chunk, so large files cost neither
/// memory nor a blocked event loop.
class _FileBody extends _VodBody {
  _FileBody(this._file, this.length);

  final File _file;

  @override
  final int length;

  @override
  Stream<Uint8List> range(int start, int end, int chunk) async* {
    final raf = await _file.open();
    try {
      await raf.setPosition(start);
      for (var pos = start; pos <= end;) {
        final bytes = await raf.read(math.min(chunk, end - pos + 1));
        if (bytes.isEmpty) break; // The file shrank.
        yield bytes;
        pos += bytes.length;
      }
    } finally {
      await raf.close();
    }
  }
}

class _SyntheticBody extends _VodBody {
  _SyntheticBody(this.length);

  @override
  final int length;

  @override
  Stream<Uint8List> range(int start, int end, int chunk) async* {
    for (var pos = start; pos <= end; pos += chunk) {
      final out = Uint8List(math.min(chunk, end - pos + 1));
      for (var i = 0; i < out.length; i++) {
        out[i] = FakePanel.syntheticVodByte(pos + i);
      }
      yield out;
    }
  }
}

/// Writes a large text body in slices, optionally gzipped, yielding to the
/// event loop between slices.
class _SliceWriter {
  _SliceWriter(this._res, {bool gzipped = false})
    : _gzip = gzipped
          ? gzip.encoder.startChunkedConversion(_AddSink(_res))
          : null;

  static const _sliceChars = 64 * 1024;

  final HttpResponse _res;
  final ByteConversionSink? _gzip;
  final _buf = StringBuffer();

  /// Whether enough text is buffered for [flush].
  bool get isFull => _buf.length >= _sliceChars;

  void writeln(String line) => _buf.writeln(line);

  /// Sends the buffer, waits for the socket, then lets other events run.
  Future<void> flush() async {
    _send();
    await _res.flush();
    // A drained flush completes as a microtask; yield to timers and I/O too.
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> close() async {
    _send();
    _gzip?.close();
    await _res.close();
  }

  void _send() {
    if (_buf.isEmpty) return;
    final bytes = utf8.encode(_buf.toString());
    _buf.clear();
    final gz = _gzip;
    if (gz != null) {
      gz.add(bytes);
    } else {
      _res.add(bytes);
    }
  }
}

class _AddSink implements Sink<List<int>> {
  _AddSink(this._target);

  final IOSink _target;

  @override
  void add(List<int> data) => _target.add(data);

  @override
  void close() {}
}

/// One HLS segment of a [TsLoop]: packets in the endless stream.
class TsSegment {
  const TsSegment(this.firstPacket, this.packetCount, this.duration);

  final int firstPacket;
  final int packetCount;
  final Duration duration;
}

/// Endless MPEG-TS packet source.
///
/// Loops a TS file while shifting PCR, PTS, DTS and continuity counters, so
/// each pass continues the previous one like a real live stream. Without a
/// file it emits null packets (sync `0x47`, PID `0x1FFF`).
class TsLoop {
  TsLoop._(
    this._data,
    this.packetCount,
    this.loopTicks,
    this._ccStep,
    this._cuts,
  );

  /// Null packets only.
  factory TsLoop.synthetic() => TsLoop._(null, 1, 0, null, const []);

  static const packetSize = 188;
  static const _mask33 = 0x1FFFFFFFF;

  /// Returns null unless [bytes] is 188-byte aligned MPEG-TS.
  static TsLoop? tryParse(Uint8List bytes) {
    final n = bytes.length ~/ packetSize;
    if (n < 2) return null;
    for (var i = 0; i < n; i++) {
      if (bytes[i * packetSize] != 0x47) return null;
    }
    final payloadCount = Int32List(8192);
    final ptsCount = <int, int>{};
    final ptsMin = <int, int>{};
    final ptsMax = <int, int>{};
    final psiPids = {0x00, 0x11};
    final keyframes = <(int, int)>[];
    for (var i = 0; i < n; i++) {
      final o = i * packetSize;
      final pid = _pid(bytes, o);
      if (pid == 0x1FFF) continue;
      if ((bytes[o + 3] & 0x10) != 0) payloadCount[pid]++;
      if (pid == 0) psiPids.addAll(_patPmtPids(bytes, o));
      final ts = _ptsAt(bytes, o);
      if (ts == null) continue;
      final pts = _readTs(bytes, ts.$1);
      ptsCount[pid] = (ptsCount[pid] ?? 0) + 1;
      ptsMin[pid] = math.min(ptsMin[pid] ?? pts, pts);
      ptsMax[pid] = math.max(ptsMax[pid] ?? pts, pts);
      // Video PES flagged random_access_indicator: an IDR frame.
      final streamId = bytes[ts.$1 - 6];
      if (streamId >= 0xE0 &&
          streamId <= 0xEF &&
          (bytes[o + 3] & 0x20) != 0 &&
          bytes[o + 4] > 0 &&
          (bytes[o + 5] & 0x40) != 0) {
        keyframes.add((i, pts));
      }
    }
    // A pass spans from the earliest start to the latest end of any PID, so
    // the next pass never overlaps (at worst a frame-sized gap) and A/V sync
    // holds. With one frame per PES, `span * n / (n - 1)` includes the last
    // frame's duration exactly.
    double? start, end;
    for (final MapEntry(key: pid, value: count) in ptsCount.entries) {
      if (count < 2) continue;
      final first = ptsMin[pid]!;
      final last = first + (ptsMax[pid]! - first) * count / (count - 1);
      start = math.min(start ?? first.toDouble(), first.toDouble());
      end = math.max(end ?? last, last);
    }
    final ticks = (start == null || end == null) ? 0 : (end - start).ceil();
    // Segment cut points: each keyframe plus the PAT/PMT written before it.
    final cuts = <(int, int)>[(0, 0)];
    if (start != null) {
      for (final (packet, pts) in keyframes) {
        var at = packet;
        while (at > 0 && psiPids.contains(_pid(bytes, (at - 1) * packetSize))) {
          at--;
        }
        final t = pts - start.round();
        if (at > cuts.last.$1 && t > cuts.last.$2 && t < ticks) {
          cuts.add((at, t));
        }
      }
    }
    final step = Uint8List(8192);
    for (var pid = 0; pid < 8192; pid++) {
      step[pid] = payloadCount[pid] & 0x0F;
    }
    return TsLoop._(
      Uint8List.sublistView(bytes, 0, n * packetSize),
      n,
      ticks,
      step,
      cuts.length > 1 ? cuts : const [],
    );
  }

  final Uint8List? _data;
  final Uint8List? _ccStep;

  /// Keyframe cut points within a pass: (packet index, ticks from start).
  final List<(int, int)> _cuts;
  final _plans = <Duration, List<TsSegment>>{};

  /// Packets per pass.
  final int packetCount;

  /// Pass length in 90 kHz ticks (0 when unknown).
  final int loopTicks;

  bool get isSynthetic => _data == null;

  /// Whether HLS segments are cut at keyframes (see [segment]).
  bool get hasKeyframeIndex => _cuts.isNotEmpty;

  /// File bitrate in bytes per second, when timestamps allow computing it.
  int? get nominalBytesPerSecond => loopTicks > 0
      ? (packetCount * packetSize * 90000 / loopTicks).round()
      : null;

  /// Packets `first .. first + count - 1` of the endless stream.
  Uint8List read(int first, int count) {
    final out = Uint8List(count * packetSize);
    final data = _data;
    if (data == null) {
      for (var i = 0; i < count; i++) {
        final o = i * packetSize;
        out
          ..fillRange(o, o + packetSize, 0xFF)
          ..[o] = 0x47
          ..[o + 1] = 0x1F
          ..[o + 2] = 0xFF
          ..[o + 3] = 0x10;
      }
      return out;
    }
    for (var i = 0; i < count; i++) {
      final k = first + i;
      final pass = k ~/ packetCount;
      final j = k - pass * packetCount;
      final o = i * packetSize;
      out.setRange(o, o + packetSize, data, j * packetSize);
      if (pass > 0) _shift(out, o, pass);
    }
    return out;
  }

  /// HLS segment [seq] for a [target] duration.
  ///
  /// Media with keyframe markers is cut at keyframes, so every segment
  /// starts with PAT/PMT and an IDR frame; otherwise the stream is sliced
  /// into equal parts at [bytesPerSecond].
  TsSegment segment(int seq, Duration target, int bytesPerSecond) {
    final plan = _plan(target);
    if (plan == null) {
      final n = math.max(
        1,
        (bytesPerSecond * target.inMicroseconds / 1e6 / packetSize).round(),
      );
      return TsSegment(seq * n, n, target);
    }
    final pass = seq ~/ plan.length;
    final s = plan[seq - pass * plan.length];
    return TsSegment(
      pass * packetCount + s.firstPacket,
      s.packetCount,
      s.duration,
    );
  }

  /// Sequence number of the segment playing [elapsed] after the start.
  int segmentAt(Duration elapsed, Duration target) {
    final us = math.max(0, elapsed.inMicroseconds);
    final plan = _plan(target);
    if (plan == null) return us ~/ math.max(1, target.inMicroseconds);
    final passUs = plan.fold(0, (sum, s) => sum + s.duration.inMicroseconds);
    final pass = us ~/ passUs;
    var acc = pass * passUs;
    for (var i = 0; i < plan.length; i++) {
      acc += plan[i].duration.inMicroseconds;
      if (us < acc) return pass * plan.length + i;
    }
    return pass * plan.length + plan.length - 1;
  }

  /// `EXT-X-TARGETDURATION` for [target]: the longest segment, rounded.
  int targetDurationSeconds(Duration target) {
    final plan = _plan(target);
    final longest = plan == null
        ? target
        : plan.map((s) => s.duration).reduce((a, b) => a > b ? a : b);
    return math.max(1, (longest.inMicroseconds / 1e6).round());
  }

  List<TsSegment>? _plan(Duration target) {
    if (_cuts.isEmpty || loopTicks <= 0) return null;
    return _plans.putIfAbsent(target, () {
      // Group whole GOPs until a segment reaches 90% of the target.
      final minTicks = target.inMicroseconds * 81 ~/ 1000;
      Duration toDuration(int ticks) =>
          Duration(microseconds: ticks * 100 ~/ 9);
      final out = <TsSegment>[];
      for (var i = 0; i < _cuts.length;) {
        var j = i + 1;
        while (j < _cuts.length && _cuts[j].$2 - _cuts[i].$2 < minTicks) {
          j++;
        }
        final (endPacket, endTicks) = j < _cuts.length
            ? _cuts[j]
            : (packetCount, loopTicks);
        out.add(
          TsSegment(
            _cuts[i].$1,
            endPacket - _cuts[i].$1,
            toDuration(endTicks - _cuts[i].$2),
          ),
        );
        i = j;
      }
      if (out.length > 1 && out.last.duration < target * 0.5) {
        final tail = out.removeLast();
        final prev = out.removeLast();
        out.add(
          TsSegment(
            prev.firstPacket,
            prev.packetCount + tail.packetCount,
            prev.duration + tail.duration,
          ),
        );
      }
      return out;
    });
  }

  void _shift(Uint8List b, int o, int pass) {
    final pid = _pid(b, o);
    if (pid == 0x1FFF) return;
    final step = _ccStep![pid];
    if (step != 0) {
      b[o + 3] = (b[o + 3] & 0xF0) | ((b[o + 3] + pass * step) & 0x0F);
    }
    if (loopTicks == 0) return;
    final delta = (pass * loopTicks) & _mask33;
    // PCR in the adaptation field.
    if ((b[o + 3] & 0x20) != 0 && b[o + 4] >= 7 && (b[o + 5] & 0x10) != 0) {
      final p = o + 6;
      final base =
          ((b[p] << 25) |
              (b[p + 1] << 17) |
              (b[p + 2] << 9) |
              (b[p + 3] << 1) |
              (b[p + 4] >> 7)) +
          delta;
      b[p] = (base >> 25) & 0xFF;
      b[p + 1] = (base >> 17) & 0xFF;
      b[p + 2] = (base >> 9) & 0xFF;
      b[p + 3] = (base >> 1) & 0xFF;
      b[p + 4] = ((base & 1) << 7) | (b[p + 4] & 0x7F);
    }
    final ts = _ptsAt(b, o);
    if (ts == null) return;
    _writeTs(b, ts.$1, (_readTs(b, ts.$1) + delta) & _mask33);
    if (ts.$2) {
      _writeTs(b, ts.$1 + 5, (_readTs(b, ts.$1 + 5) + delta) & _mask33);
    }
  }

  static int _pid(Uint8List b, int o) => ((b[o + 1] & 0x1F) << 8) | b[o + 2];

  /// Start of the payload of packet [o], or null without payload.
  static int? _payload(Uint8List b, int o) {
    final afc = (b[o + 3] >> 4) & 0x03;
    if ((afc & 0x01) == 0) return null;
    final p = (afc & 0x02) != 0 ? o + 5 + b[o + 4] : o + 4;
    return p < o + packetSize ? p : null;
  }

  /// PMT PIDs listed by a PAT section starting in packet [o].
  static Iterable<int> _patPmtPids(Uint8List b, int o) sync* {
    if ((b[o + 1] & 0x40) == 0) return;
    var p = _payload(b, o);
    if (p == null) return;
    p += 1 + b[p]; // pointer_field
    final limit = o + packetSize;
    if (p + 8 > limit || b[p] != 0x00) return;
    final length = ((b[p + 1] & 0x0F) << 8) | b[p + 2];
    final end = math.min(p + 3 + length - 4, limit);
    for (var q = p + 8; q + 4 <= end; q += 4) {
      if (((b[q] << 8) | b[q + 1]) != 0) {
        yield ((b[q + 2] & 0x1F) << 8) | b[q + 3];
      }
    }
  }

  /// Offset of the PTS in a PES header starting in packet [o], and whether a
  /// DTS follows it.
  static (int, bool)? _ptsAt(Uint8List b, int o) {
    if ((b[o + 1] & 0x40) == 0) return null; // payload_unit_start_indicator
    final p = _payload(b, o);
    if (p == null || p + 14 > o + packetSize) return null;
    if (b[p] != 0 || b[p + 1] != 0 || b[p + 2] != 1) return null;
    const noHeader = {0xBC, 0xBE, 0xBF, 0xF0, 0xF1, 0xF2, 0xF8, 0xFF};
    if (noHeader.contains(b[p + 3]) || (b[p + 6] & 0xC0) != 0x80) return null;
    final flags = b[p + 7] >> 6;
    if (flags < 2) return null;
    final dts = flags == 3 && p + 19 <= o + packetSize;
    return (p + 9, dts);
  }

  static int _readTs(Uint8List b, int p) =>
      (((b[p] >> 1) & 0x07) << 30) |
      (b[p + 1] << 22) |
      ((b[p + 2] >> 1) << 15) |
      (b[p + 3] << 7) |
      (b[p + 4] >> 1);

  static void _writeTs(Uint8List b, int p, int v) {
    b[p] = (b[p] & 0xF1) | (((v >> 30) & 0x07) << 1);
    b[p + 1] = (v >> 22) & 0xFF;
    b[p + 2] = (((v >> 15) & 0x7F) << 1) | 1;
    b[p + 3] = (v >> 7) & 0xFF;
    b[p + 4] = ((v & 0x7F) << 1) | 1;
  }
}

/// 1x1 transparent PNG served for every logo/poster URL.
final _png1x1 = base64.decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);
