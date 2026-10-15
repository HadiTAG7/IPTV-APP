import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/isolate.dart' show ComputeWithDriftIsolate, DriftIsolate;
import 'package:xml/xml.dart' show XmlException;

import '../core/db/app_db.dart';
import '../core/db/daos/query_utils.dart';
import '../core/net/http.dart' show mapDioError;
import '../core/net/redact.dart';
import '../core/text/normalize.dart';
import '../core/time/clock.dart';
import '../sources/models.dart';
import 'epg_matcher.dart';
import 'epg_models.dart';
import 'epg_progress.dart';
import 'short_epg_cache.dart';
import 'xmltv_parser.dart';

/// Builds the HTTP client for one refresh run (`createDio` fits).
typedef EpgDioFactory = Dio Function({String? userAgent, String? referer});

/// Loads a source's configuration (User-Agent, Referer, guide offset and the
/// credentials used to redact messages).
typedef SourceConfigLoader = Future<SourceConfig?> Function(int sourceId);

/// Copy of [p] moved by [minutes] (start and stop alike).
EpgProgramme shiftProgramme(EpgProgramme p, int minutes) => minutes == 0
    ? p
    : EpgProgramme(
        channelId: p.channelId,
        start: p.start.add(Duration(minutes: minutes)),
        stop: p.stop.add(Duration(minutes: minutes)),
        title: p.title,
        subTitle: p.subTitle,
        desc: p.desc,
        category: p.category,
        icon: p.icon,
      );

/// [programmes] moved by [minutes], for display.
///
/// Stored programmes already include the source's guide offset
/// (`sources.epgOffsetMin`), and `EpgDao.nowNext` / `programmesForChannels`
/// add the channel's `tvg-shift` when reading, so their results must not be
/// shifted again. Use this for listings that bypass the database, such as
/// short EPG (see [EpgService.shortEpg]).
List<EpgProgramme> shiftProgrammes(
  Iterable<EpgProgramme> programmes,
  int minutes,
) => [for (final p in programmes) shiftProgramme(p, minutes)];

/// Guide pipeline for one app database: downloads each source's XMLTV
/// guides, links playlist channels to guide channels and keeps the
/// programmes of linked channels inside a time window.
///
/// Build one instance per database and keep it for the app's lifetime: it
/// is the coordinator that allows one refresh per source and cancels runs.
/// With [runInIsolate], each run's download, parsing and writes happen in a
/// short-lived background isolate on the same database while the
/// coordination stays here. Do not build services per call (for example
/// inside `computeWithDatabase`): separate instances do not see each other's
/// runs.
///
/// **Kept ids**: a guide's last full import kept the programmes of the guide
/// channels some playlist channel linked to. They are known from the
/// guide's automatic links (only ever written for kept ids) plus the ids
/// that have stored programmes. A guide is *covered* when every guide
/// channel the source's channels would now link to (automatic matches
/// against its stored guide channels, plus manual links) is kept; it is not
/// after a sync added channels that match new ids, or after a manual link
/// to an id without programmes.
///
/// **Refresh** ([refresh]): the enabled `epg_sources` of a source are
/// processed in order (origin xtream, then M3U header, then manual; then
/// `priority`, then id). For each guide:
/// 1. A covered guide whose last full import, or a 304 answer, is younger
///    than `refreshHours` is skipped ([EpgGuideSkipped]) unless `force` is
///    set.
/// 2. The download uses the source's User-Agent and Referer.
///    `If-None-Match` and `If-Modified-Since` are sent from the stored
///    validators only for a covered guide whose last full import is younger
///    than [notModifiedMaxAge] (a 304 keeps the window stored at that
///    import), and not with `force`. A 304 keeps the stored guide.
/// 3. gzip is detected from the bytes, then [XmltvParser] streams the
///    document with the source's `epgOffsetMin` applied and only programmes
///    overlapping the window (now - [back] .. now + [window], [liteWindow] in
///    Lite mode, widened for negative `tvg-shift`s) are kept. Once a guide
///    that declares its channels has been imported, the parser also gets the
///    ids the import is expected to want (links through the stored guide
///    channels, manual ids and the channels' tvg-ids), so it skips decoding
///    other channels' programmes. When the downloaded channel list links an
///    id outside that set, or the filtered parse finds nothing, the download
///    starts over without the filter (the channel list comes first, so
///    little is lost).
/// 4. Matching: XMLTV lists `<channel>` elements before `<programme>`s, so
///    the guide channels seen up to the first programme batch are matched
///    with [matchChannels] against the source's channels that no earlier
///    guide claimed and no manual link covers. Programmes are then kept when
///    their channel is linked, plus (tentatively) when their channel has not
///    been declared yet. Non-standard files are handled at the cost of some
///    extra writes: late `<channel>` elements trigger a re-match, ids that
///    are never declared become guide channels without names (matched by
///    tvg-id at the end), and programmes of ids that end up unlinked are
///    deleted at the end. With a parser filter, undeclared ids outside the
///    filter are not seen at all.
/// 5. Writes: batches are upserted over the stored programmes, so readers
///    keep seeing a complete guide during the import. At the end, one
///    transaction deletes the guide's rows this import did not write (old
///    slots, unlinked channels) and stores all guide channels
///    (`epg_channels`, for matching and [searchGuideChannels]). A failure or
///    cancellation keeps the old rows next to those already written; once
///    anything was written, the guide's validators and `lastFetchAt` are
///    cleared so the next refresh downloads it in full. A failure before
///    that keeps the guide as it was.
///
/// A playlist channel links to the first guide (in the order above) that
/// matches it. Manual links always win; only the letter case of their id
/// follows the guide (reads join on the exact id). A guide that failed or
/// was skipped keeps the links to the ids it kept. After all guides, the
/// automatic links of the source are replaced, programmes that ended before
/// now - [back] are pruned, and `epg_sources` get their status
/// ([EpgSourceStatus], with the attempt time), validators, `lastFetchAt`
/// (time of the last full import; a 304, a skip or a failure does not change
/// it) and `programmeCount`. `sources.lastEpgAt` is set when at least one
/// guide was imported or confirmed by a 304.
///
/// **Offsets**: programmes are stored with the source's `epgOffsetMin`
/// applied and without any channel `tvg-shift`; the DAO adds the shift when
/// reading, so several playlist channels can share a guide id with
/// different shifts. After changing `epgOffsetMin`, call
/// `refresh(sourceId, force: true)` (a skip or a 304 would keep the old
/// offset).
///
/// **Concurrency**: at most one refresh runs per source. A [refresh] call
/// while one runs joins it when that run does at least as much, otherwise
/// it queues one follow-up run. A run ends only on completion or [cancel];
/// cancelling a progress subscription just stops listening.
class EpgService {
  EpgService({
    required AppDatabase db,
    required this._dioFactory,
    SourceConfigLoader? configLoader,
    Clock clock = const SystemClock(),
    this.window = const Duration(days: 3),
    this.liteWindow = const Duration(days: 2),
    this.back = const Duration(hours: 12),
    this.batchSize = 5000,
    this.notModifiedMaxAge = const Duration(hours: 24),
    this.retryAfter = const Duration(hours: 1),
    this.runInIsolate = false,
    ShortEpgCache? shortEpgCache,
    this._parser = const XmltvParser(),
  }) : assert(batchSize > 0, 'batchSize must be positive'),
       _db = db,
       _configLoader = configLoader ?? db.sourcesDao.configFor,
       _clock = clock,
       shortEpgCache = shortEpgCache ?? ShortEpgCache(clock: clock);

  /// Times before this mean the device clock is not set yet (boxes without
  /// a clock battery boot in the past); a refresh then would drop the whole
  /// guide as out of window, so it is refused.
  static final earliestPlausibleNow = DateTime.utc(2025);

  /// How far ahead programmes are kept.
  final Duration window;

  /// [window] in Lite mode.
  final Duration liteWindow;

  /// How long programmes are kept after they end.
  final Duration back;

  /// Programmes per database write.
  final int batchSize;

  /// Conditional requests are only sent while the last full import is
  /// younger than this: a 304 keeps the window stored at that import.
  final Duration notModifiedMaxAge;

  /// How long [needsRefresh] waits before a failed guide is due again.
  final Duration retryAfter;

  /// Whether runs execute in a background isolate (see [EpgService]). The
  /// configuration loader then runs here, while the dio factory, clock and
  /// parser are sent to the isolate, so they must be sendable (`createDio`,
  /// [SystemClock] and [XmltvParser] are).
  final bool runInIsolate;

  /// Cache behind [shortEpg].
  final ShortEpgCache shortEpgCache;

  final AppDatabase _db;
  final EpgDioFactory _dioFactory;
  final SourceConfigLoader _configLoader;
  final Clock _clock;
  final XmltvParser _parser;

  /// Running refresh per source.
  final _jobs = <int, _RefreshJob>{};

  /// Follow-up run per source, started when the running one ends.
  final _queued = <int, _RefreshJob>{};
  bool _disposed = false;

  EpgDao get _epg => _db.epgDao;

  // -------------------------------------------------------------------------
  // Refresh.

  /// Refreshes the guides of [sourceId] and reports progress.
  ///
  /// Without [force], guides that are current (see [EpgService]: last
  /// import or 304 younger than [refreshHours], nothing new to keep) are
  /// skipped and the others are fetched with a conditional request when
  /// possible; [force] downloads every guide in full. Pass the same
  /// [refreshHours] as to [needsRefresh]. [lite] uses [liteWindow].
  ///
  /// The run starts at once, whether or not the stream is listened to, and
  /// the stream replays every event since this call. When a refresh of this
  /// source is already running and does at least as much (forced if [force],
  /// not Lite unless [lite], an interval no longer than [refreshHours]), the
  /// call joins it and the stream starts with that run's latest event.
  /// Otherwise one follow-up run is queued with the combined flags; it starts
  /// when the current run ends, and the stream follows it. Use [cancel] to
  /// stop runs.
  Stream<EpgProgress> refresh(
    int sourceId, {
    bool force = false,
    bool lite = false,
    int refreshHours = 12,
  }) {
    if (_disposed) throw StateError('EpgService is disposed');
    final request = _RunFlags(
      force: force,
      lite: lite,
      refreshHours: refreshHours,
    );
    final running = _jobs[sourceId];
    if (running == null) {
      final job = _jobs[sourceId] = _RefreshJob(sourceId, request);
      final events = job.watch();
      unawaited(_run(job));
      return events;
    }
    if (!running.cancelled && running.flags.covers(request)) {
      return running.watch();
    }
    final queued = _queued[sourceId];
    if (queued == null) {
      return (_queued[sourceId] = _RefreshJob(sourceId, request)).watch();
    }
    queued.flags = queued.flags.merge(request);
    return queued.watch();
  }

  /// Whether a refresh of [sourceId] is running or queued.
  bool isRefreshing(int sourceId) =>
      _jobs.containsKey(sourceId) || _queued.containsKey(sourceId);

  /// Cancels the refresh of [sourceId] and its queued follow-up, if any, and
  /// completes once they have stopped (their streams then end with
  /// [EpgRefreshCancelled]).
  Future<void> cancel(int sourceId) async {
    _queued.remove(sourceId)?.finish(EpgRefreshCancelled(sourceId));
    final job = _jobs[sourceId];
    if (job == null) return;
    job.cancel();
    await job.done;
  }

  /// Cancels every refresh and clears the short EPG cache.
  Future<void> dispose() async {
    _disposed = true;
    for (final id in _queued.keys.toList()) {
      _queued.remove(id)!.finish(EpgRefreshCancelled(id));
    }
    final jobs = _jobs.values.toList();
    for (final job in jobs) {
      job.cancel();
    }
    await Future.wait([for (final job in jobs) job.done]);
    shortEpgCache.clear();
  }

  /// Whether a guide fetched at [lastFetchAt] is older than [refreshHours].
  /// Never fetched (null) is stale, and so is a stamp in the future (the
  /// clock went back since).
  bool isStale(DateTime? lastFetchAt, int refreshHours) =>
      _olderThan(lastFetchAt, _clock.now(), Duration(hours: refreshHours));

  /// Whether a [refresh] of [sourceId] would fetch something: an enabled
  /// guide that was never imported, or whose last full import is older than
  /// [refreshHours]. A guide a 304 confirmed within [refreshHours] (while
  /// its import is younger than [notModifiedMaxAge]) is not due, and a
  /// guide that failed is due again only [retryAfter] after the attempt, so
  /// a dead guide URL does not make every check refresh. Channels added by a
  /// sync are not considered: refresh after a sync.
  Future<bool> needsRefresh(int sourceId, {int refreshHours = 12}) async {
    final now = _clock.now();
    if (now.isBefore(earliestPlausibleNow)) return false;
    final guides = await _epg.epgSources(sourceId, enabledOnly: true);
    return guides.any((g) => _isDue(g, now, refreshHours, backoff: true));
  }

  /// The programme window of a refresh started at [now].
  ({DateTime start, DateTime end}) windowAt(
    DateTime now, {
    bool lite = false,
  }) => (start: now.subtract(back), end: now.add(lite ? liteWindow : window));

  /// Whether [t] is null, more than 5 minutes in the future (the clock went
  /// back since), or at least [age] before [now].
  static bool _olderThan(DateTime? t, DateTime now, Duration age) {
    if (t == null) return true;
    if (t.isAfter(now.add(const Duration(minutes: 5)))) return true;
    return !now.isBefore(t.add(age));
  }

  /// Whether [guide] is due for a download or a 304 check at [now]; with
  /// [backoff], a failure within [retryAfter] counts as not due.
  bool _isDue(
    EpgSourceRow guide,
    DateTime now,
    int refreshHours, {
    required bool backoff,
  }) {
    final interval = Duration(hours: refreshHours);
    final imported = guide.lastFetchAt;
    if (!_olderThan(imported, now, interval)) return false;
    final status = EpgSourceStatus.parse(guide.status);
    final at = status?.at;
    if (status == null || at == null) return true;
    return switch (status.kind) {
      // Confirmed unchanged lately, while the stored window still lasts.
      EpgStatusKind.notModified =>
        _olderThan(at, now, interval) ||
            _olderThan(imported, now, notModifiedMaxAge),
      EpgStatusKind.error when backoff => _olderThan(at, now, retryAfter),
      _ => true,
    };
  }

  Future<void> _run(_RefreshJob job) async {
    EpgProgress terminal;
    try {
      terminal = runInIsolate
          ? await _runInIsolate(job)
          : await _refreshSource(job);
    } on Object catch (e) {
      terminal = job.cancelled || e is _Cancelled
          ? EpgRefreshCancelled(job.sourceId)
          : EpgRefreshFailed(job.sourceId, message: _describe(e, job.secrets));
    }
    // Hand over first: a listener that reacts to the terminal event by
    // calling refresh again must not join this finished run.
    final sourceId = job.sourceId;
    if (identical(_jobs[sourceId], job)) _jobs.remove(sourceId);
    final next = _queued.remove(sourceId);
    if (next != null) {
      _jobs[sourceId] = next;
      unawaited(_run(next));
    }
    job.finish(terminal);
  }

  /// Runs [job] in a background isolate on this database and forwards its
  /// events; [cancel] reaches it through a control port.
  Future<EpgProgress> _runInIsolate(_RefreshJob job) async {
    job.checkCancelled();
    final sourceId = job.sourceId;
    final config = await _configLoader(sourceId);
    if (config == null) {
      return EpgRefreshFailed(sourceId, message: 'Unknown source $sourceId');
    }
    job
      ..secrets = [?config.password]
      ..checkCancelled();
    final events = ReceivePort('EpgService events');
    events.listen((message) {
      switch (message) {
        case final SendPort control:
          job.attachControl(control);
        case final EpgProgress event:
          job.emit(event);
      }
    });
    try {
      return await _spawnWorker(
        _WorkerArgs(
          connection: await _db.serializableConnection(),
          events: events.sendPort,
          sourceId: sourceId,
          flags: job.flags,
          config: config,
          dioFactory: _dioFactory,
          clock: _clock,
          window: window,
          liteWindow: liteWindow,
          back: back,
          batchSize: batchSize,
          notModifiedMaxAge: notModifiedMaxAge,
          retryAfter: retryAfter,
          parser: _parser,
        ),
      );
    } finally {
      events.close();
    }
  }

  /// Static, so the isolate closure captures nothing but [args].
  static Future<EpgProgress> _spawnWorker(_WorkerArgs args) =>
      Isolate.run(() => _workerMain(args), debugName: 'EpgService refresh');

  Future<EpgProgress> _refreshSource(_RefreshJob job) async {
    job.checkCancelled();
    final sourceId = job.sourceId;
    final flags = job.flags;
    final now = _clock.now();
    if (now.isBefore(earliestPlausibleNow)) {
      return EpgRefreshFailed(
        sourceId,
        message: 'The device clock is not set; guide refresh skipped',
      );
    }
    final config = await _configLoader(sourceId);
    if (config == null) {
      return EpgRefreshFailed(sourceId, message: 'Unknown source $sourceId');
    }
    job.secrets = [?config.password];
    final guides = _ordered(await _epg.epgSources(sourceId, enabledOnly: true));
    final identities = await _db.catalogDao.channelIdentities(sourceId);
    if (guides.isEmpty || identities.isEmpty) return EpgRefreshDone(sourceId);
    job.checkCancelled();

    final links = await _epg.linksFor(sourceId);
    final manual = {
      for (final MapEntry(:key, :value) in links.entries)
        if (value.kind == EpgMatchKind.manual) key: value,
    };
    // Automatic links are only written for kept ids (see [EpgService]).
    final autoLinked = <int, Set<String>>{};
    for (final link in links.values) {
      if (link.kind != EpgMatchKind.manual) {
        (autoLinked[link.epgSourceId] ??= {}).add(link.xmltvId.toLowerCase());
      }
    }
    final candidates = [
      for (final c in identities)
        MatchCandidate(
          key: c.key,
          name: c.name,
          tvgId: c.tvgId,
          tvgName: c.tvgName,
        ),
    ];
    final range = windowAt(now, lite: flags.lite);
    // Stored times plus a channel's shift must still cover the window end.
    final end = range.end.add(
      Duration(minutes: -math.min(0, await _minShiftMinutes(sourceId))),
    );
    final plan = _GuidePlan(
      now: now,
      windowStart: range.start,
      windowEnd: end,
      offsetMinutes: config.epgOffsetMin,
      total: guides.length,
    );

    final claimed = <String>{...manual.keys};
    final autoLinks = <String, EpgLink>{};
    var imported = 0;
    var notModified = 0;
    var skipped = 0;
    var failed = 0;
    String? firstError;
    final dio = _dioFactory(
      userAgent: config.userAgent,
      referer: config.referer,
    );
    try {
      for (final (index, guide) in guides.indexed) {
        job.checkCancelled();
        final result = await _refreshGuide(
          job,
          dio,
          plan,
          guide,
          index,
          remaining: [
            for (final c in candidates)
              if (!claimed.contains(c.key)) c,
          ],
          manualIds: {
            for (final link in manual.values)
              if (link.epgSourceId == guide.id && link.xmltvId.isNotEmpty)
                link.xmltvId,
          },
          autoLinked: autoLinked[guide.id] ?? const {},
        );
        switch (result.outcome) {
          case _Outcome.imported:
            imported++;
          case _Outcome.notModified:
            notModified++;
          case _Outcome.skipped:
            skipped++;
          case _Outcome.failed:
            failed++;
            firstError ??= result.message;
        }
        // Programmes are stored under the guide's spelling of an id, and
        // reads join on it exactly.
        for (final MapEntry(:key, value: link) in manual.entries) {
          final spelling = result.respelled[link.xmltvId];
          if (link.epgSourceId == guide.id && spelling != null) {
            await _epg.setManualLink(sourceId, key, guide.id, spelling);
          }
        }
        for (final MapEntry(:key, value: match) in result.matches.entries) {
          autoLinks[key] = (
            epgSourceId: guide.id,
            xmltvId: match.xmltvId,
            kind: _dbKind(match.kind),
          );
          claimed.add(key);
        }
      }
    } finally {
      dio.close(force: true);
    }

    await _epg.replaceChannelMap(sourceId, autoLinks);
    await _epg.pruneProgrammes(range.start);
    var programmes = 0;
    for (final guide in guides) {
      final count = await _epg.programmeCount(guide.id);
      programmes += count;
      await _writeGuide(
        guide.id,
        EpgSourcesCompanion(programmeCount: Value(count)),
      );
    }
    if (imported + notModified + skipped == 0) {
      return EpgRefreshFailed(
        sourceId,
        message: firstError ?? 'No guide could be loaded',
      );
    }
    if (imported + notModified > 0) {
      await _db.sourcesDao.markEpgFetched(sourceId, now);
    }
    final keys = {for (final c in identities) c.key};
    return EpgRefreshDone(
      sourceId,
      guides: guides.length,
      imported: imported,
      notModified: notModified,
      skipped: skipped,
      failed: failed,
      matched:
          autoLinks.length +
          manual.entries
              .where((e) => e.value.xmltvId.isNotEmpty && keys.contains(e.key))
              .length,
      programmes: programmes,
    );
  }

  Future<_GuideResult> _refreshGuide(
    _RefreshJob job,
    Dio dio,
    _GuidePlan plan,
    EpgSourceRow guide,
    int index, {
    required List<MatchCandidate> remaining,
    required Set<String> manualIds,
    required Set<String> autoLinked,
  }) async {
    final sourceId = job.sourceId;
    final flags = job.flags;
    final storedChannels = await _storedGuideChannels(guide.id);
    final storedMatches = matchChannels(remaining, storedChannels);
    final matched = storedMatches.length + manualIds.length;

    Set<String>? storedIds;
    Future<bool> isKept(Iterable<String> ids) async {
      final missing = {for (final id in ids) id.toLowerCase()}
        ..removeAll(autoLinked);
      if (missing.isEmpty) return true;
      storedIds ??= await _storedProgrammeIds(guide.id);
      return storedIds!.containsAll(missing);
    }

    // Links of a guide that brings nothing new: only to ids it kept.
    Future<Map<String, EpgMatch>> keptMatches() async => {
      for (final MapEntry(:key, :value) in storedMatches.entries)
        if (await isKept([value.xmltvId])) key: value,
    };

    final covered = await isKept([
      for (final m in storedMatches.values) m.xmltvId,
      ...manualIds,
    ]);
    if (!flags.force &&
        covered &&
        !_isDue(guide, plan.now, flags.refreshHours, backoff: false)) {
      job.emit(
        EpgGuideSkipped(sourceId, epgSourceId: guide.id, matched: matched),
      );
      return _GuideResult(_Outcome.skipped, storedMatches);
    }

    job.emit(
      EpgGuideStarted(
        sourceId,
        epgSourceId: guide.id,
        url: redact(guide.url, secrets: job.secrets),
        origin: guide.origin,
        index: index,
        total: plan.total,
      ),
    );
    final lastImport = guide.lastFetchAt;
    var conditional =
        !flags.force &&
        covered &&
        (guide.etag != null || guide.lastModified != null) &&
        lastImport != null &&
        !plan.now.isBefore(lastImport) &&
        plan.now.difference(lastImport) < notModifiedMaxAge;
    // Ids this import is expected to want, for a guide that declares its
    // channels (undeclared ids have no names).
    var prefilter = storedChannels.any((c) => c.displayNames.isNotEmpty)
        ? {
            for (final m in storedMatches.values) m.xmltvId.toLowerCase(),
            for (final id in manualIds) id.toLowerCase(),
            for (final c in remaining)
              if (c.tvgId?.trim() case final id? when id.isNotEmpty)
                id.toLowerCase(),
          }
        : null;

    var wrote = false;
    _GuideImport? import;
    try {
      final url = await _epg.epgSourceUrl(guide.id) ?? guide.url;
      final uri = Uri.tryParse(url.trim());
      if (uri == null ||
          !(uri.isScheme('http') || uri.isScheme('https')) ||
          uri.host.isEmpty) {
        throw const ParseFailure('Unsupported guide address');
      }
      while (true) {
        final response = await dio.getUri<ResponseBody>(
          uri,
          cancelToken: job.cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            receiveDataWhenStatusError: false,
            validateStatus: (s) =>
                s == 304 || (s != null && s >= 200 && s < 300),
            headers: {
              if (conditional && guide.etag != null)
                'If-None-Match': guide.etag,
              if (conditional && guide.lastModified != null)
                'If-Modified-Since': guide.lastModified,
            },
          ),
        );
        final body = response.data;
        if (body == null) throw const ParseFailure('Empty guide response');
        if (response.statusCode == 304) {
          await body.stream.listen(null).cancel();
          final matches = conditional ? storedMatches : await keptMatches();
          await _writeGuide(
            guide.id,
            EpgSourcesCompanion(
              status: Value(
                EpgSourceStatus(
                  EpgStatusKind.notModified,
                  null,
                  plan.now,
                ).encode(),
              ),
            ),
          );
          job.emit(
            EpgGuideNotModified(
              sourceId,
              epgSourceId: guide.id,
              matched: matches.length + manualIds.length,
            ),
          );
          return _GuideResult(_Outcome.notModified, matches);
        }

        final current = import = _GuideImport(
          service: this,
          job: job,
          plan: plan,
          guideId: guide.id,
          remaining: remaining,
          manualIds: manualIds,
          prefilter: prefilter,
        );
        final Map<String, EpgMatch> matches;
        try {
          matches = await current.run(body.stream);
        } on _Restart {
          // Leaving the parse closed the download; fetch it again in full.
          wrote = wrote || current.wrote;
          prefilter = null;
          conditional = false;
          continue;
        }
        String? header(String name) => response.headers.map[name]?.firstOrNull;
        await _writeGuide(
          guide.id,
          EpgSourcesCompanion(
            status: Value(
              EpgSourceStatus(EpgStatusKind.ok, null, plan.now).encode(),
            ),
            etag: Value(header('etag')),
            lastModified: Value(header('last-modified')),
            lastFetchAt: Value(toEpochSec(plan.now)),
          ),
        );
        job.emit(
          EpgGuideFinished(
            sourceId,
            epgSourceId: guide.id,
            channels: current.channelCount,
            matched: matches.length + manualIds.length,
            programmes: await _epg.programmeCount(guide.id),
          ),
        );
        return _GuideResult(
          _Outcome.imported,
          matches,
          respelled: current.respelledManualIds(),
        );
      }
    } on Object catch (e) {
      wrote = wrote || (import?.wrote ?? false);
      final cancelled =
          job.cancelled ||
          e is _Cancelled ||
          (e is DioException && e.type == DioExceptionType.cancel);
      final message = cancelled ? null : _describe(e, job.secrets);
      await _writeGuide(
        guide.id,
        EpgSourcesCompanion(
          status: Value(
            EpgSourceStatus(
              cancelled ? EpgStatusKind.cancelled : EpgStatusKind.error,
              message,
              plan.now,
            ).encode(),
          ),
          // Part of a new version is stored: download in full next time.
          etag: wrote ? const Value(null) : const Value.absent(),
          lastModified: wrote ? const Value(null) : const Value.absent(),
          lastFetchAt: wrote ? const Value(null) : const Value.absent(),
        ),
      );
      if (cancelled) throw const _Cancelled();
      job.emit(
        EpgGuideFailed(sourceId, epgSourceId: guide.id, message: message!),
      );
      return _GuideResult(
        _Outcome.failed,
        await keptMatches(),
        message: message,
      );
    }
  }

  /// Most negative `tvg-shift` among the source's channels (0 if none),
  /// bounded to the playlist limit of 48 hours.
  Future<int> _minShiftMinutes(int sourceId) async {
    final c = _db.channels;
    final min = c.tvgShiftMin.min();
    final row =
        await (_db.selectOnly(c)
              ..addColumns([min])
              ..where(c.sourceId.equals(sourceId)))
            .getSingle();
    return math.max(row.read(min) ?? 0, -48 * 60);
  }

  /// Stored guide channels of [epgSourceId] in matching order.
  Future<List<EpgChannel>> _storedGuideChannels(int epgSourceId) async {
    final rows = await _epg.epgChannels(epgSourceId);
    return _sortedById([
      for (final r in rows)
        EpgChannel(
          id: r.xmltvId,
          displayNames: [?r.displayName, ...r.displayNamesNorm],
          icon: r.icon,
        ),
    ]);
  }

  /// Lower-cased ids with stored programmes in guide [epgSourceId].
  Future<Set<String>> _storedProgrammeIds(int epgSourceId) async {
    final id = _db.programmes.xmltvId;
    final query = _db.selectOnly(_db.programmes, distinct: true)
      ..addColumns([id])
      ..where(_db.programmes.epgSourceId.equals(epgSourceId));
    return {
      for (final value in await query.map((r) => r.read(id)!).get())
        value.toLowerCase(),
    };
  }

  /// Ends an import in one transaction: keeps only the programmes in [keep]
  /// (stored id -> start seconds) and replaces the guide channels.
  Future<void> _finishImport(
    int epgSourceId,
    Map<String, List<int>> keep,
    List<EpgChannel> channels,
  ) => _db.transaction(() async {
    await _db.customUpdate(
      'DELETE FROM programmes WHERE epg_source_id = ?1 '
      'AND (xmltv_id, start_utc) NOT IN '
      '(SELECT k.key, s.value FROM json_each(?2) k, json_each(k.value) s)',
      variables: [
        Variable.withInt(epgSourceId),
        Variable.withString(jsonEncode(keep)),
      ],
      updates: {_db.programmes},
      updateKind: UpdateKind.delete,
    );
    await (_db.delete(
      _db.epgChannels,
    )..where((c) => c.epgSourceId.equals(epgSourceId))).go();
    for (final part in chunked(channels, batchSize)) {
      await _epg.upsertEpgChannels(epgSourceId, part);
    }
  });

  Future<void> _writeGuide(int epgSourceId, EpgSourcesCompanion values) =>
      (_db.update(
        _db.epgSources,
      )..where((e) => e.id.equals(epgSourceId))).write(values);

  // -------------------------------------------------------------------------
  // Short EPG.

  /// Short guide of [channelKey] for channels without XMLTV data (Xtream
  /// `get_short_epg` through [loader]), cached by [shortEpgCache] for 15
  /// minutes.
  ///
  /// Results are display-ready: the source's `epgOffsetMin` and the
  /// channel's `tvg-shift` are applied, as `EpgDao.nowNext` does for stored
  /// programmes. Programmes that have ended are left out. A failing [loader]
  /// yields an empty list (retried after a minute).
  Future<List<EpgProgramme>> shortEpg(
    int sourceId,
    String channelKey,
    Future<List<EpgProgramme>> Function() loader,
  ) => shortEpgCache.get(sourceId, channelKey, () async {
    final programmes = await loader();
    if (programmes.isEmpty) return programmes;
    final source = await _db.sourcesDao.byId(sourceId);
    final channel = await _db.catalogDao.channelByKey(sourceId, channelKey);
    return shiftProgrammes(
      programmes,
      (source?.epgOffsetMin ?? 0) + (channel?.tvgShiftMin ?? 0),
    );
  });

  // -------------------------------------------------------------------------
  // Manual links ("Assign guide channel").

  /// Links [channelKey] to guide channel [xmltvId] of guide [epgSourceId] by
  /// hand; automatic matching never overrides it. An empty [xmltvId] means
  /// "no guide" and turns automatic matching off for the channel.
  ///
  /// Call [refresh] afterwards: when the guide has no stored programmes for
  /// [xmltvId] (it was not wanted at the last import), the guide is no
  /// longer covered, so the refresh downloads it in full, also when a run
  /// that started earlier is still going.
  Future<void> setManualMapping(
    int sourceId,
    String channelKey,
    int epgSourceId,
    String xmltvId,
  ) async {
    final guide = await _epg.epgSourceById(epgSourceId);
    if (guide == null || guide.sourceId != sourceId) {
      throw ArgumentError.value(
        epgSourceId,
        'epgSourceId',
        'not a guide of source $sourceId',
      );
    }
    await _epg.setManualLink(sourceId, channelKey, epgSourceId, xmltvId.trim());
  }

  /// Removes the manual link of [channelKey], if any; the next [refresh]
  /// links it automatically again. Automatic links are left alone.
  Future<void> clearManualMapping(int sourceId, String channelKey) async {
    final link = await _epg.linkFor(sourceId, channelKey);
    if (link?.kind == EpgMatchKind.manual) {
      await _epg.clearLink(sourceId, channelKey);
    }
  }

  /// Guide channels of the source's enabled guides whose display names
  /// (folded with [normalizeForEpg]) or id contain [query], best first: an
  /// earlier hit in the names, then by name. An empty query lists channels
  /// by name. Feeds the "Assign guide channel" picker; pass the row's
  /// `epgSourceId` and `xmltvId` to [setManualMapping].
  Future<List<EpgChannelRow>> searchGuideChannels(
    int sourceId,
    String query, {
    int limit = 50,
  }) async {
    final epgNorm = normalizeForEpg(query);
    final norm = epgNorm.isNotEmpty ? epgNorm : normalizeForSearch(query);
    final idQuery = query.trim().toLowerCase();
    final rows = await _db
        .customSelect(
          'SELECT g.* FROM epg_channels g '
          'JOIN epg_sources s ON s.id = g.epg_source_id '
          'WHERE s.source_id = ?1 AND s.enabled = 1 '
          r"AND (g.display_names_norm LIKE ?2 ESCAPE '\' "
          r"OR lower(g.xmltv_id) LIKE ?3 ESCAPE '\') "
          'ORDER BY CASE WHEN instr(g.display_names_norm, ?4) > 0 '
          'THEN instr(g.display_names_norm, ?4) ELSE 1000000 END, '
          'g.display_name IS NULL, g.display_name COLLATE NOCASE, '
          's.priority, g.epg_source_id, g.xmltv_id '
          'LIMIT ?5',
          variables: [
            Variable.withInt(sourceId),
            Variable.withString('%${escapeLike(norm)}%'),
            Variable.withString('%${escapeLike(idQuery)}%'),
            Variable.withString(norm),
            Variable.withInt(limit),
          ],
          readsFrom: {_db.epgChannels, _db.epgSources},
        )
        .get();
    return [for (final r in rows) _db.epgChannels.map(r.data).toRow()];
  }
}

// ---------------------------------------------------------------------------
// Internals.

/// Guides in refresh order: origin (xtream, M3U header, manual), then
/// priority, then id.
List<EpgSourceRow> _ordered(List<EpgSourceRow> guides) =>
    guides.toList()..sort((a, b) {
      final byOrigin = a.origin.index.compareTo(b.origin.index);
      if (byOrigin != 0) return byOrigin;
      final byPriority = a.priority.compareTo(b.priority);
      return byPriority != 0 ? byPriority : a.id.compareTo(b.id);
    });

/// Guide channels sorted by id. The matcher prefers the first of several
/// candidates; sorting makes an import and a later run on the stored
/// channels (whose document order is lost) pick the same one.
List<EpgChannel> _sortedById(List<EpgChannel> channels) =>
    channels.toList()..sort((a, b) => a.id.compareTo(b.id));

EpgMatchKind _dbKind(MatchKind kind) => switch (kind) {
  MatchKind.manual => EpgMatchKind.manual,
  MatchKind.tvgId => EpgMatchKind.tvgId,
  MatchKind.tvgName => EpgMatchKind.tvgName,
  MatchKind.name => EpgMatchKind.name,
};

/// Credential-free text for a failure.
String _describe(Object error, List<String> secrets) {
  final failure = switch (error) {
    SourceFailure() => error,
    DioException() => mapDioError(error, secrets: secrets),
    FormatException(:final message) => ParseFailure(
      'Invalid guide data: $message',
    ),
    XmlException(:final message) => ParseFailure('Invalid guide: $message'),
    _ => NetworkFailure('$error'),
  };
  return redact(failure.message, secrets: secrets);
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// The filtered parse cannot serve the import; download again without it.
class _Restart implements Exception {
  const _Restart();
}

enum _Outcome { imported, notModified, skipped, failed }

class _GuideResult {
  const _GuideResult(
    this.outcome,
    this.matches, {
    this.message,
    this.respelled = const {},
  });

  final _Outcome outcome;

  /// Playlist channel key -> guide channel, automatic matches only.
  final Map<String, EpgMatch> matches;
  final String? message;

  /// Manual link ids the guide now spells differently: old -> new.
  final Map<String, String> respelled;
}

/// Settings shared by the guides of one run.
class _GuidePlan {
  const _GuidePlan({
    required this.now,
    required this.windowStart,
    required this.windowEnd,
    required this.offsetMinutes,
    required this.total,
  });

  final DateTime now;
  final DateTime windowStart;
  final DateTime windowEnd;
  final int offsetMinutes;
  final int total;
}

/// What a refresh call asks for.
class _RunFlags {
  const _RunFlags({
    required this.force,
    required this.lite,
    required this.refreshHours,
  });

  final bool force;
  final bool lite;
  final int refreshHours;

  /// Whether a run with these flags does everything [other] asks for.
  bool covers(_RunFlags other) =>
      (force || !other.force) &&
      (!lite || other.lite) &&
      refreshHours <= other.refreshHours;

  _RunFlags merge(_RunFlags other) => _RunFlags(
    force: force || other.force,
    lite: lite && other.lite,
    refreshHours: math.min(refreshHours, other.refreshHours),
  );
}

/// One refresh run and its listeners.
class _RefreshJob {
  _RefreshJob(this.sourceId, this.flags);

  final int sourceId;

  /// Fixed once the run starts; a queued run takes over later requests.
  _RunFlags flags;
  final cancelToken = CancelToken();

  /// Values to mask in messages besides URL credentials (the password).
  List<String> secrets = const [];
  bool cancelled = false;

  /// Cancels the run in a background isolate ([EpgService.runInIsolate]).
  SendPort? _control;

  final _done = Completer<void>();
  final _watchers = <StreamController<EpgProgress>>{};
  EpgProgress? _last;
  bool _finished = false;

  Future<void> get done => _done.future;

  /// A stream of this job's events from now on, starting with the latest
  /// one. Cancelling it does not stop the job.
  Stream<EpgProgress> watch() {
    late final StreamController<EpgProgress> controller;
    controller = StreamController<EpgProgress>(
      onCancel: () => _watchers.remove(controller),
    );
    if (_last case final last?) controller.add(last);
    if (_finished) {
      unawaited(controller.close());
    } else {
      _watchers.add(controller);
    }
    return controller.stream;
  }

  void emit(EpgProgress event) {
    if (_finished) return;
    _last = event;
    for (final c in _watchers.toList()) {
      c.add(event);
    }
  }

  void finish(EpgProgress terminal) {
    if (_finished) return;
    emit(terminal);
    _finished = true;
    final watchers = _watchers.toList();
    _watchers.clear();
    for (final c in watchers) {
      unawaited(c.close());
    }
    _done.complete();
  }

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    cancelToken.cancel('Guide refresh cancelled');
    _control?.send(null);
  }

  void attachControl(SendPort control) {
    _control = control;
    if (cancelled) control.send(null);
  }

  void checkCancelled() {
    if (cancelled) throw const _Cancelled();
  }
}

/// Everything a background run needs; all of it can be sent to an isolate.
class _WorkerArgs {
  const _WorkerArgs({
    required this.connection,
    required this.events,
    required this.sourceId,
    required this.flags,
    required this.config,
    required this.dioFactory,
    required this.clock,
    required this.window,
    required this.liteWindow,
    required this.back,
    required this.batchSize,
    required this.notModifiedMaxAge,
    required this.retryAfter,
    required this.parser,
  });

  final DriftIsolate connection;

  /// Receives the control [SendPort] first, then the progress events.
  final SendPort events;
  final int sourceId;
  final _RunFlags flags;
  final SourceConfig config;
  final EpgDioFactory dioFactory;
  final Clock clock;
  final Duration window;
  final Duration liteWindow;
  final Duration back;
  final int batchSize;
  final Duration notModifiedMaxAge;
  final Duration retryAfter;
  final XmltvParser parser;
}

/// Background isolate body: one refresh on its own connection to the
/// database; returns the terminal event.
Future<EpgProgress> _workerMain(_WorkerArgs args) async {
  final db = AppDatabase(await args.connection.connect(), clock: args.clock);
  final service = EpgService(
    db: db,
    dioFactory: args.dioFactory,
    configLoader: (_) async => args.config,
    clock: args.clock,
    window: args.window,
    liteWindow: args.liteWindow,
    back: args.back,
    batchSize: args.batchSize,
    notModifiedMaxAge: args.notModifiedMaxAge,
    retryAfter: args.retryAfter,
    parser: args.parser,
  );
  final control = ReceivePort('EpgService control');
  final cancels = control.listen(
    (_) => unawaited(service.cancel(args.sourceId)),
  );
  args.events.send(control.sendPort);
  try {
    EpgProgress? terminal;
    final flags = args.flags;
    await for (final event in service.refresh(
      args.sourceId,
      force: flags.force,
      lite: flags.lite,
      refreshHours: flags.refreshHours,
    )) {
      if (event.isTerminal) {
        terminal = event;
      } else {
        args.events.send(event);
      }
    }
    return terminal ??
        EpgRefreshFailed(args.sourceId, message: 'Guide refresh ended early');
  } finally {
    await cancels.cancel();
    control.close();
    await service.dispose();
    await db.close();
  }
}

/// Streaming import of one downloaded guide; see [EpgService].
class _GuideImport {
  _GuideImport({
    required this.service,
    required this.job,
    required this.plan,
    required this.guideId,
    required this.remaining,
    required this.manualIds,
    required this.prefilter,
  });

  final EpgService service;
  final _RefreshJob job;
  final _GuidePlan plan;
  final int guideId;
  final List<MatchCandidate> remaining;
  final Set<String> manualIds;

  /// Lower-cased ids passed to the parser, or null for all.
  final Set<String>? prefilter;

  /// Declared guide channels by id, duplicates merged, in document order.
  final _channels = <String, EpgChannel>{};

  /// Lower-cased ids of declared channels.
  final _known = <String>{};

  /// Programme channel ids not declared (yet): lower-cased -> spelling.
  final _undeclared = <String, String>{};

  /// Start seconds of the programmes written, by id as stored.
  final _starts = <String, List<int>>{};

  var _matches = const <String, EpgMatch>{};

  /// Lower-cased ids whose programmes are kept.
  var _wanted = const <String>{};
  bool _matched = false;
  int _reportedMatches = -1;
  int _written = 0;

  /// Whether programmes were written (the guide is then a mix of versions
  /// until [run] completes).
  bool wrote = false;

  /// Guide spelling of every id, by lower-cased id (after [run]).
  var _spellings = const <String, String>{};

  /// Manual link ids this guide spells differently (case only): old -> new.
  Map<String, String> respelledManualIds() => {
    for (final id in manualIds)
      if (_spellings[id.toLowerCase()] case final spelling? when spelling != id)
        id: spelling,
  };

  int get channelCount => _channels.length + _undeclared.length;

  EpgDao get _epg => service._db.epgDao;

  /// Parses [bytes], writes the guide and returns the automatic matches.
  /// Throws [_Restart] when [prefilter] turns out too narrow.
  Future<Map<String, EpgMatch>> run(Stream<List<int>> bytes) async {
    var sawProgrammes = false;
    final batches = service._parser.parse(
      bytes,
      wantedChannelIds: prefilter,
      windowStart: plan.windowStart,
      windowEnd: plan.windowEnd,
      batchSize: service.batchSize,
      offsetMinutes: plan.offsetMinutes,
    );
    await for (final batch in batches) {
      job.checkCancelled();
      if (batch.channels.isNotEmpty) {
        _addChannels(batch.channels);
        job.emit(
          EpgChannelsParsed(
            job.sourceId,
            epgSourceId: guideId,
            channels: _channels.length,
          ),
        );
        // Channels after programmes (not DTD order): match again.
        if (_matched) _match(_channels.values);
      }
      if (batch.programmes.isEmpty) continue;
      sawProgrammes = true;
      if (!_matched) _match(_channels.values);
      final keep = <EpgProgramme>[];
      for (final p in batch.programmes) {
        final id = p.channelId.toLowerCase();
        final known = _known.contains(id);
        // Its <channel> may still come; if it does not, the id is stored as
        // a guide channel without names (for tvg-id matching and manual
        // links). Unknown ids are kept until the end decides.
        if (!known) _undeclared.putIfAbsent(id, () => p.channelId);
        if (!known || _wanted.contains(id)) keep.add(p);
      }
      if (keep.isEmpty) continue;
      wrote = true;
      await _epg.insertProgrammes(guideId, keep);
      for (final p in keep) {
        (_starts[p.channelId] ??= []).add(toEpochSec(p.start));
      }
      _written += keep.length;
      job
        ..checkCancelled()
        ..emit(
          EpgProgrammesStored(
            job.sourceId,
            epgSourceId: guideId,
            programmes: _written,
          ),
        );
    }
    if (_channels.isEmpty && !sawProgrammes) {
      // The filter may have dropped everything of a guide that changed.
      if (prefilter != null) throw const _Restart();
      throw const ParseFailure('No guide channels or programmes found');
    }

    // Ids that never got a <channel> element can still match by tvg-id.
    final all = [
      ..._channels.values,
      for (final id in _undeclared.values) EpgChannel(id: id),
    ];
    _match(all);
    _spellings = {for (final c in all) c.id.toLowerCase(): c.id};
    await service._finishImport(guideId, {
      for (final MapEntry(:key, :value) in _starts.entries)
        if (_wanted.contains(key.toLowerCase())) key: value,
    }, all);
    return _matches;
  }

  void _addChannels(List<EpgChannel> channels) {
    for (final c in channels) {
      final id = c.id.toLowerCase();
      _known.add(id);
      _undeclared.remove(id);
      final previous = _channels[c.id];
      _channels[c.id] = previous == null
          ? c
          : EpgChannel(
              id: c.id,
              displayNames: {
                ...previous.displayNames,
                ...c.displayNames,
              }.toList(),
              icon: previous.icon ?? c.icon,
            );
    }
  }

  void _match(Iterable<EpgChannel> channels) {
    _matched = true;
    _matches = matchChannels(remaining, _sortedById(channels.toList()));
    _wanted = {
      for (final m in _matches.values) m.xmltvId.toLowerCase(),
      for (final id in manualIds) id.toLowerCase(),
    };
    // The parser dropped programmes of ids outside the filter.
    if (prefilter case final ids? when !ids.containsAll(_wanted)) {
      throw const _Restart();
    }
    final matched = _matches.length + manualIds.length;
    if (matched != _reportedMatches) {
      _reportedMatches = matched;
      job.emit(
        EpgChannelsMatched(
          job.sourceId,
          epgSourceId: guideId,
          matched: matched,
        ),
      );
    }
  }
}
