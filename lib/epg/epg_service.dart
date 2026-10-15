import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
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
/// **Refresh** ([refresh]): the enabled `epg_sources` of a source are
/// processed in order (origin xtream, then M3U header, then manual; then
/// `priority`, then id). For each guide:
/// 1. The download uses the source's User-Agent and Referer. `If-None-Match`
///    and `If-Modified-Since` are sent from the stored validators unless
///    `force` is set, the last import is older than [notModifiedMaxAge] (the
///    stored window would be too short), or a playlist channel would now
///    link to a guide channel whose programmes were not kept last time (new
///    channels after a sync, a cleared manual link). A 304 keeps the stored
///    guide.
/// 2. gzip is detected from the bytes, then [XmltvParser] streams the
///    document with the source's `epgOffsetMin` applied and only programmes
///    overlapping the window (now - [back] .. now + [window], [liteWindow] in
///    Lite mode, widened for negative `tvg-shift`s) are kept.
/// 3. Matching: XMLTV lists `<channel>` elements before `<programme>`s, so
///    the guide channels seen up to the first programme batch are matched
///    with [matchChannels] against the source's channels that no earlier
///    guide claimed and no manual link covers. Programmes are then kept when
///    their channel is linked, plus (tentatively) when their channel has not
///    been declared yet. Non-standard files are handled at the cost of some
///    extra writes: late `<channel>` elements trigger a re-match, ids that
///    are never declared become guide channels without names (matched by
///    tvg-id at the end), and programmes of ids that end up unlinked are
///    deleted after the parse.
/// 4. The guide's old programmes are deleted right before its first new
///    batch is written, so re-runs never duplicate and a failure before any
///    data arrives (HTTP error, timeout, not XMLTV) keeps the old guide. A
///    failure or cancellation after that leaves a partial guide: its
///    validators and `lastFetchAt` are cleared so the next refresh downloads
///    it in full.
/// 5. All guide channels are stored (`epg_channels`) for 304 runs and for
///    manual assignment ([searchGuideChannels]).
///
/// A playlist channel links to the first guide (in the order above) that
/// matches it. Manual links always win; only the letter case of their id
/// follows the guide (reads join on the exact id). After all
/// guides, the automatic links of the source are replaced, programmes that
/// ended before now - [back] are pruned, `epg_sources` get their status
/// ([EpgSourceStatus]), validators, `lastFetchAt` (time of the last full
/// import, not changed by a 304 or a failure) and `programmeCount`, and
/// `sources.lastEpgAt` is set when at least one guide is current.
///
/// **Offsets**: programmes are stored with the source's `epgOffsetMin`
/// applied and without any channel `tvg-shift`; the DAO adds the shift when
/// reading, so several playlist channels can share a guide id with
/// different shifts. After changing `epgOffsetMin`, call
/// `refresh(sourceId, force: true)` (a 304 would keep the old offset).
///
/// **Concurrency**: at most one refresh runs per source. A second
/// [refresh] call while one runs joins it. A run ends only on completion or
/// [cancel]; cancelling a progress subscription just stops listening.
///
/// The class holds no isolate-bound state besides its jobs and the short EPG
/// cache, so it can also be built inside a background isolate on that
/// isolate's database connection; [EpgProgress] events are plain values.
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

  /// Cache behind [shortEpg].
  final ShortEpgCache shortEpgCache;

  final AppDatabase _db;
  final EpgDioFactory _dioFactory;
  final SourceConfigLoader _configLoader;
  final Clock _clock;
  final XmltvParser _parser;

  final _jobs = <int, _RefreshJob>{};
  bool _disposed = false;

  EpgDao get _epg => _db.epgDao;

  // -------------------------------------------------------------------------
  // Refresh.

  /// Refreshes the guides of [sourceId] and reports progress.
  ///
  /// The run starts at once, whether or not the stream is listened to, and
  /// the stream replays every event since this call. When a refresh of this
  /// source is already running, the call joins it instead (its own `force`
  /// and `lite` are then ignored) and the stream starts with that run's
  /// latest event. Use [cancel] to stop a run.
  Stream<EpgProgress> refresh(
    int sourceId, {
    bool force = false,
    bool lite = false,
  }) {
    if (_disposed) throw StateError('EpgService is disposed');
    final running = _jobs[sourceId];
    if (running != null) return running.watch();
    final job = _jobs[sourceId] = _RefreshJob(
      sourceId,
      force: force,
      lite: lite,
    );
    final events = job.watch();
    unawaited(_run(job));
    return events;
  }

  /// Whether a refresh of [sourceId] is running.
  bool isRefreshing(int sourceId) => _jobs.containsKey(sourceId);

  /// Cancels the refresh of [sourceId], if any, and completes once it has
  /// stopped (its stream then ends with [EpgRefreshCancelled]).
  Future<void> cancel(int sourceId) async {
    final job = _jobs[sourceId];
    if (job == null) return;
    job.cancel();
    await job.done;
  }

  /// Cancels every refresh and clears the short EPG cache.
  Future<void> dispose() async {
    _disposed = true;
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
  bool isStale(DateTime? lastFetchAt, int refreshHours) {
    if (lastFetchAt == null) return true;
    final now = _clock.now();
    if (lastFetchAt.isAfter(now.add(const Duration(minutes: 5)))) return true;
    return !now.isBefore(lastFetchAt.add(Duration(hours: refreshHours)));
  }

  /// Whether any enabled guide of [sourceId] [isStale]: never imported, or
  /// its last full import is older than [refreshHours]. A 304 or a failure
  /// does not reset the age, so such guides are retried (cheaply) on the
  /// next check.
  Future<bool> needsRefresh(int sourceId, {int refreshHours = 12}) async {
    final guides = await _epg.epgSources(sourceId, enabledOnly: true);
    return guides.any((g) => isStale(g.lastFetchAt, refreshHours));
  }

  /// The programme window of a refresh started at [now].
  ({DateTime start, DateTime end}) windowAt(
    DateTime now, {
    bool lite = false,
  }) => (start: now.subtract(back), end: now.add(lite ? liteWindow : window));

  Future<void> _run(_RefreshJob job) async {
    EpgProgress terminal;
    try {
      terminal = await _refreshSource(job);
    } on Object catch (e) {
      terminal = job.cancelled || e is _Cancelled
          ? EpgRefreshCancelled(job.sourceId)
          : EpgRefreshFailed(job.sourceId, message: _describe(e, job.secrets));
    }
    // Remove first: a listener that reacts to the terminal event by calling
    // refresh again must start a new run, not join this one.
    if (identical(_jobs[job.sourceId], job)) _jobs.remove(job.sourceId);
    job.finish(terminal);
  }

  Future<EpgProgress> _refreshSource(_RefreshJob job) async {
    final sourceId = job.sourceId;
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
    final candidates = [
      for (final c in identities)
        MatchCandidate(
          key: c.key,
          name: c.name,
          tvgId: c.tvgId,
          tvgName: c.tvgName,
        ),
    ];
    final range = windowAt(now, lite: job.lite);
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
        );
        switch (result.outcome) {
          case _Outcome.imported:
            imported++;
          case _Outcome.notModified:
            notModified++;
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
    if (imported + notModified == 0) {
      return EpgRefreshFailed(
        sourceId,
        message: firstError ?? 'No guide could be loaded',
      );
    }
    await _db.sourcesDao.markEpgFetched(sourceId, now);
    final keys = {for (final c in identities) c.key};
    return EpgRefreshDone(
      sourceId,
      guides: guides.length,
      imported: imported,
      notModified: notModified,
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
  }) async {
    final sourceId = job.sourceId;
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

    List<EpgChannel>? stored;
    Future<Map<String, EpgMatch>> storedMatches() async => matchChannels(
      remaining,
      stored ??= await _storedGuideChannels(guide.id),
    );

    Map<String, EpgMatch>? unchangedMatches;
    final lastImport = guide.lastFetchAt;
    if (!job.force &&
        (guide.etag != null || guide.lastModified != null) &&
        lastImport != null &&
        !plan.now.isBefore(lastImport) &&
        plan.now.difference(lastImport) < notModifiedMaxAge) {
      final matches = await storedMatches();
      final wanted = {
        for (final m in matches.values) m.xmltvId.toLowerCase(),
        for (final id in manualIds) id.toLowerCase(),
      };
      final kept = {
        for (final id in await _epg.linkedXmltvIds(guide.id)) id.toLowerCase(),
      };
      if (kept.containsAll(wanted)) unchangedMatches = matches;
    }

    final import = _GuideImport(
      service: this,
      job: job,
      plan: plan,
      guideId: guide.id,
      remaining: remaining,
      manualIds: manualIds,
    );
    try {
      final url = await _epg.epgSourceUrl(guide.id) ?? guide.url;
      final uri = Uri.tryParse(url.trim());
      if (uri == null ||
          !(uri.isScheme('http') || uri.isScheme('https')) ||
          uri.host.isEmpty) {
        throw const ParseFailure('Unsupported guide address');
      }
      final response = await dio.getUri<ResponseBody>(
        uri,
        cancelToken: job.cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          receiveDataWhenStatusError: false,
          validateStatus: (s) => s == 304 || (s != null && s >= 200 && s < 300),
          headers: {
            if (unchangedMatches != null && guide.etag != null)
              'If-None-Match': guide.etag,
            if (unchangedMatches != null && guide.lastModified != null)
              'If-Modified-Since': guide.lastModified,
          },
        ),
      );
      final body = response.data;
      if (body == null) throw const ParseFailure('Empty guide response');
      if (response.statusCode == 304) {
        await body.stream.listen(null).cancel();
        final matches = unchangedMatches ?? await storedMatches();
        await _writeGuide(
          guide.id,
          EpgSourcesCompanion(
            status: Value(EpgSourceStatus.notModified.encode()),
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

      final matches = await import.run(body.stream);
      String? header(String name) => response.headers.map[name]?.firstOrNull;
      await _writeGuide(
        guide.id,
        EpgSourcesCompanion(
          status: Value(EpgSourceStatus.ok.encode()),
          etag: Value(header('etag')),
          lastModified: Value(header('last-modified')),
          lastFetchAt: Value(toEpochSec(plan.now)),
        ),
      );
      job.emit(
        EpgGuideFinished(
          sourceId,
          epgSourceId: guide.id,
          channels: import.channelCount,
          matched: matches.length + manualIds.length,
          programmes: await _epg.programmeCount(guide.id),
        ),
      );
      return _GuideResult(
        _Outcome.imported,
        matches,
        respelled: import.respelledManualIds(),
      );
    } on Object catch (e) {
      final cancelled =
          job.cancelled ||
          e is _Cancelled ||
          (e is DioException && e.type == DioExceptionType.cancel);
      final message = cancelled ? null : _describe(e, job.secrets);
      await _writeGuide(
        guide.id,
        EpgSourcesCompanion(
          status: Value(
            cancelled
                ? EpgSourceStatus.cancelled.encode()
                : EpgSourceStatus(EpgStatusKind.error, message).encode(),
          ),
          // The old programmes are gone: download in full next time.
          etag: import.replacedOld ? const Value(null) : const Value.absent(),
          lastModified: import.replacedOld
              ? const Value(null)
              : const Value.absent(),
          lastFetchAt: import.replacedOld
              ? const Value(null)
              : const Value.absent(),
        ),
      );
      if (cancelled) throw const _Cancelled();
      job.emit(
        EpgGuideFailed(sourceId, epgSourceId: guide.id, message: message!),
      );
      // Keep linking to what an earlier import stored.
      return _GuideResult(
        _Outcome.failed,
        await storedMatches(),
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

  /// Replaces the stored guide channels of [epgSourceId].
  Future<void> _replaceGuideChannels(
    int epgSourceId,
    List<EpgChannel> channels,
  ) => _db.transaction(() async {
    await (_db.delete(
      _db.epgChannels,
    )..where((c) => c.epgSourceId.equals(epgSourceId))).go();
    for (final part in chunked(channels, batchSize)) {
      await _epg.upsertEpgChannels(epgSourceId, part);
    }
  });

  Future<void> _deleteProgrammesFor(int epgSourceId, List<String> ids) async {
    for (final part in chunked(ids)) {
      await (_db.delete(_db.programmes)..where(
            (p) => p.epgSourceId.equals(epgSourceId) & p.xmltvId.isIn(part),
          ))
          .go();
    }
  }

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
  /// When the guide has no stored programmes for [xmltvId] (it was not
  /// wanted at the last import), its validators are cleared so the next
  /// [refresh] downloads it in full; call [refresh] to fetch them.
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
    final id = xmltvId.trim();
    await _epg.setManualLink(sourceId, channelKey, epgSourceId, id);
    if (id.isNotEmpty && !await _hasProgrammes(epgSourceId, id)) {
      await _writeGuide(
        epgSourceId,
        const EpgSourcesCompanion(etag: Value(null), lastModified: Value(null)),
      );
    }
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

  Future<bool> _hasProgrammes(int epgSourceId, String xmltvId) async {
    final row =
        await (_db.selectOnly(_db.programmes)
              ..addColumns([_db.programmes.startUtc])
              ..where(
                _db.programmes.epgSourceId.equals(epgSourceId) &
                    _db.programmes.xmltvId.equals(xmltvId),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
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

enum _Outcome { imported, notModified, failed }

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

/// One running refresh and its listeners.
class _RefreshJob {
  _RefreshJob(this.sourceId, {required this.force, required this.lite});

  final int sourceId;
  final bool force;
  final bool lite;
  final cancelToken = CancelToken();

  /// Values to mask in messages besides URL credentials (the password).
  List<String> secrets = const [];
  bool cancelled = false;

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
    _last = event;
    for (final c in _watchers.toList()) {
      c.add(event);
    }
  }

  void finish(EpgProgress terminal) {
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
  }

  void checkCancelled() {
    if (cancelled) throw const _Cancelled();
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
  });

  final EpgService service;
  final _RefreshJob job;
  final _GuidePlan plan;
  final int guideId;
  final List<MatchCandidate> remaining;
  final Set<String> manualIds;

  /// Declared guide channels by id, duplicates merged, in document order.
  final _channels = <String, EpgChannel>{};

  /// Lower-cased ids of declared channels.
  final _known = <String>{};

  /// Programme channel ids not declared (yet): lower-cased -> spelling.
  final _undeclared = <String, String>{};

  /// Ids (as stored) with programmes written by this import.
  final _storedIds = <String>{};

  var _matches = const <String, EpgMatch>{};

  /// Lower-cased ids whose programmes are kept.
  var _wanted = const <String>{};
  bool _matched = false;
  int _reportedMatches = -1;
  int _written = 0;

  /// Whether the guide's previous programmes were deleted.
  bool replacedOld = false;

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
  Future<Map<String, EpgMatch>> run(Stream<List<int>> bytes) async {
    var sawProgrammes = false;
    final batches = service._parser.parse(
      bytes,
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
      await _replaceOld();
      await _epg.insertProgrammes(guideId, keep);
      for (final p in keep) {
        _storedIds.add(p.channelId);
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
      throw const ParseFailure('No guide channels or programmes found');
    }

    // Ids that never got a <channel> element can still match by tvg-id.
    final all = [
      ..._channels.values,
      for (final id in _undeclared.values) EpgChannel(id: id),
    ];
    _match(all);
    _spellings = {for (final c in all) c.id.toLowerCase(): c.id};
    final unwanted = [
      for (final id in _storedIds)
        if (!_wanted.contains(id.toLowerCase())) id,
    ];
    await service._deleteProgrammesFor(guideId, unwanted);
    await _replaceOld();
    await service._replaceGuideChannels(guideId, all);
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

  /// Deletes the guide's previous programmes once, before new ones go in.
  Future<void> _replaceOld() async {
    if (replacedOld) return;
    await _epg.deleteProgrammesOf(guideId);
    replacedOld = true;
  }
}
