import 'dart:async';
import 'dart:isolate';

import '../../core/db/app_db.dart';
import '../../core/log/ring_log.dart';
import '../../core/net/redact.dart';
import '../../core/time/clock.dart';
import '../models.dart';
import '../source_adapter.dart';
import '../source_repository.dart';
import 'sync_progress.dart';

export 'sync_progress.dart';

/// Everything one sync run needs. Plain data, so it can be sent to a
/// background isolate.
class SyncTask {
  const SyncTask({
    required this.sourceId,
    required this.config,
    this.scope = SyncScope.all,
    this.lowMemory = false,
    this.replaceEmptyFamilies = false,
    this.clock = const SystemClock(),
  });

  final int sourceId;

  /// Full configuration, credentials included (read on the main isolate).
  final SourceConfig config;
  final SyncScope scope;
  final bool lowMemory;

  /// A family that comes back empty replaces the stored one (the user asked
  /// for this sync). Otherwise it is kept: a busy panel's blank answer looks
  /// the same as a provider removing everything.
  final bool replaceEmptyFamilies;

  /// Stamps `sources.lastSyncAt`.
  final Clock clock;
}

/// Cancels a running pipeline: closes the adapter (aborting its downloads)
/// and makes the pipeline stop before the next write.
class SyncCancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  /// Runs [listener] on [cancel] (at once if already cancelled).
  void onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }
}

/// A started pipeline.
class SyncExecution {
  SyncExecution(this.result, this._cancel);

  /// The final progress ([SyncPhase.done], [SyncPhase.failed] or
  /// [SyncPhase.cancelled]).
  final Future<SyncProgress> result;
  final void Function() _cancel;

  void cancel() => _cancel();
}

/// Where the fetch + write pipeline ([runSyncPipeline]) runs.
///
/// * [IsolateSyncRunner] (production): a short-lived background isolate via
///   drift's `computeWithDatabase`, so parsing and SQL never block the UI.
/// * [InlineSyncRunner] (tests, or as a fallback): the calling isolate. The
///   pipeline is streaming and writes short batches, so the UI keeps working
///   there too, just with less headroom on slow devices.
abstract interface class SyncRunner {
  SyncExecution start(
    AppDatabase db,
    SyncTask task,
    void Function(SyncProgress progress) onProgress,
  );
}

/// Runs the pipeline on the calling isolate with adapters from
/// [buildAdapter] (for example `SourceRepository.adapterFor`, which honours
/// an injected HTTP client).
class InlineSyncRunner implements SyncRunner {
  const InlineSyncRunner(this.buildAdapter);

  final SourceAdapter Function(SourceConfig config) buildAdapter;

  @override
  SyncExecution start(
    AppDatabase db,
    SyncTask task,
    void Function(SyncProgress progress) onProgress,
  ) {
    final token = SyncCancelToken();
    final result = Future(
      () => runSyncPipeline(
        db,
        task,
        buildAdapter(task.config),
        token,
        onProgress,
      ),
    );
    return SyncExecution(result, token.cancel);
  }
}

/// Builds an adapter inside the sync isolate.
typedef IsolateAdapterBuilder = SourceAdapter Function(
  SourceConfig config,
  bool lowMemory,
);

SourceAdapter _defaultIsolateAdapter(SourceConfig config, bool lowMemory) =>
    createSourceAdapter(config, lowMemory: lowMemory);

/// Runs the pipeline in a background isolate that shares the app database
/// through `computeWithDatabase` (the database is opened with
/// `shareAcrossIsolates`; an in-memory test database is proxied by drift).
/// Progress and cancellation travel over ports.
class IsolateSyncRunner implements SyncRunner {
  const IsolateSyncRunner({this.buildAdapter = _defaultIsolateAdapter});

  /// Sent to the isolate, so it must be a top-level or static function.
  final IsolateAdapterBuilder buildAdapter;

  static const _cancelMessage = 'cancel';

  @override
  SyncExecution start(
    AppDatabase db,
    SyncTask task,
    void Function(SyncProgress progress) onProgress,
  ) {
    final events = ReceivePort('sync ${task.sourceId}');
    SendPort? control;
    var cancelled = false;
    events.listen((message) {
      if (message is SendPort) {
        control = message;
        if (cancelled) message.send(_cancelMessage);
      } else if (message is SyncProgress) {
        onProgress(message);
      }
    });
    final result = db
        .computeWithDatabase<SyncProgress, AppDatabase>(
          connect: AppDatabase.new,
          computation: _computation(task, buildAdapter, events.sendPort),
        )
        .whenComplete(events.close);
    return SyncExecution(result, () {
      cancelled = true;
      control?.send(_cancelMessage);
    });
  }

  /// Built in its own scope so the closure captures only sendable values.
  static Future<SyncProgress> Function(AppDatabase) _computation(
    SyncTask task,
    IsolateAdapterBuilder build,
    SendPort out,
  ) => (db) async {
    final control = ReceivePort();
    final token = SyncCancelToken();
    control.listen((_) => token.cancel());
    out.send(control.sendPort);
    try {
      final adapter = build(task.config, task.lowMemory);
      return await runSyncPipeline(db, task, adapter, token, out.send);
    } finally {
      control.close();
    }
  };
}

/// Fetches the catalog of [task] with [adapter] and swaps it in, one
/// content family at a time.
///
/// 1. `verify()`; the account fields are saved and an expired, banned or
///    disabled account stops here.
/// 2. Batches are upserted into an open catalog generation, each in its own
///    short transaction, while the committed catalog stays visible.
/// 3. When a family is complete ([PhaseDoneBatch]) its generation is
///    committed at once, so live channels are usable while movies and series
///    still download, and a later failure keeps them. A playlist that mixes
///    families in one pass (M3U) commits them together after the last one.
/// 4. After the stream completes: the remaining families are committed,
///    guide URLs are saved (adapter `epgSpecs()` + `EpgHintBatch`es; manual
///    ones are kept and stale automatic ones removed) and `lastSyncAt` is
///    stamped.
///
/// On an error or [token] cancellation the open generation is aborted:
/// families committed earlier in this run keep their new rows, the others
/// (and all favourites and progress) stay as they were. A family that comes
/// back empty while the source had items of it keeps its stored rows unless
/// [SyncTask.replaceEmptyFamilies]; the run then ends as failed
/// ([VerifyErrorReason.incomplete], after committing the other families)
/// without stamping `lastSyncAt`, so it is tried again. A sync that returns
/// nothing at all while the source had items fails. Never throws; [emit]
/// gets the running progress and the returned value is the final one.
/// Closes [adapter].
Future<SyncProgress> runSyncPipeline(
  AppDatabase db,
  SyncTask task,
  SourceAdapter adapter,
  SyncCancelToken token,
  void Function(SyncProgress progress) emit,
) async {
  final id = task.sourceId;
  final catalog = db.catalogDao;
  var p = SyncProgress(sourceId: id);
  int? gen;
  token.onCancel(adapter.close);
  void check() {
    if (token.isCancelled) throw const CancelledFailure();
  }

  try {
    emit(p);
    final info = await adapter.verify();
    check();
    await db.sourcesDao.updateAccount(id, info);
    final blocked = accountError(info);
    if (blocked != null) throw blocked;

    final kinds = _kindsOf(task.scope);
    final previous = <ContentKind, int>{
      for (final kind in kinds) kind: await catalog.totalCount(id, kind),
    };
    check();
    p = p.copyWith(phase: _firstPhase(task.scope));
    emit(p);

    // Families committed by this run, families that came back empty and
    // keep their stored rows, and the state of the open generation:
    // families written to it, families finished in it. Items written per
    // family in this run.
    final committed = <ContentKind>{};
    final kept = <ContentKind>{};
    final touched = <ContentKind>{};
    final finished = <ContentKind>{};
    final written = <ContentKind, int>{};
    Future<int> open() async => gen ??= await catalog.beginGeneration(id);
    void touch(ContentKind kind) {
      if (kinds.contains(kind) &&
          !committed.contains(kind) &&
          !kept.contains(kind)) {
        touched.add(kind);
      }
    }

    void count(ContentKind kind, int items) =>
        written[kind] = (written[kind] ?? 0) + items;

    Future<void> commit(Set<ContentKind> families) async {
      check();
      await catalog.commitGeneration(id, gen!, kinds: families);
      gen = null;
      committed.addAll(families);
      touched.clear();
      finished.clear();
    }

    final hints = <String>[];
    await for (final batch in adapter.fetchCatalog(task.scope)) {
      check();
      switch (batch) {
        case CategoriesBatch(:final items):
          await catalog.upsertCategories(id, await open(), items);
          items.map((c) => c.kind).forEach(touch);
          p = p.copyWith(categories: p.categories + items.length);
        case ChannelsBatch(:final items):
          await catalog.upsertChannels(id, await open(), items);
          touch(ContentKind.live);
          count(ContentKind.live, items.length);
          p = p.copyWith(
            phase: SyncPhase.live,
            channels: p.channels + items.length,
          );
        case MoviesBatch(:final items):
          await catalog.upsertMovies(id, await open(), items);
          touch(ContentKind.movie);
          count(ContentKind.movie, items.length);
          p = p.copyWith(
            phase: SyncPhase.movies,
            movies: p.movies + items.length,
          );
        case SeriesBatch(:final items):
          await catalog.upsertSeries(id, await open(), items);
          touch(ContentKind.series);
          count(ContentKind.series, items.length);
          p = p.copyWith(
            phase: SyncPhase.series,
            series: p.series + items.length,
          );
        case EpisodesBatch(:final items):
          await catalog.upsertEpisodes(id, await open(), items);
          touch(ContentKind.series);
          count(ContentKind.series, items.length);
          p = p.copyWith(
            phase: SyncPhase.series,
            episodes: p.episodes + items.length,
          );
        case EpgHintBatch(:final urls):
          hints.addAll(urls);
          continue;
        case PhaseDoneBatch(:final kind):
          if (kinds.contains(kind) &&
              !committed.contains(kind) &&
              !kept.contains(kind)) {
            final emptied =
                (written[kind] ?? 0) == 0 && (previous[kind] ?? 0) > 0;
            if (gen == null && (previous[kind] ?? 0) == 0) {
              // Nothing written and nothing to remove: no swap needed.
              committed.add(kind);
            } else if (emptied && !task.replaceEmptyFamilies) {
              // Left out of every commit, so its stored rows are carried.
              kept.add(kind);
              touched.remove(kind);
              if (touched.isNotEmpty && finished.containsAll(touched)) {
                await commit({...finished});
              }
            } else {
              await open();
              touched.add(kind);
              finished.add(kind);
              if (finished.containsAll(touched)) {
                await commit({...finished});
              }
            }
          }
          p = p.copyWith(phase: _phaseAfter(kind, task.scope));
      }
      check();
      emit(p);
    }
    check();
    final hadItems = previous.values.any((n) => n > 0);
    if (p.items == 0 && hadItems) {
      throw const ParseFailure('The source returned an empty catalog');
    }

    p = p.copyWith(phase: SyncPhase.saving);
    emit(p);
    final remaining = kinds.difference(committed).difference(kept);
    if (remaining.isNotEmpty) {
      await open();
      await commit(remaining);
    } else if (gen case final stray?) {
      // Rows of families that were already committed (or kept): drop them.
      gen = null;
      await catalog.abortGeneration(id, stray);
    }
    // The new catalog is live; bookkeeping below must not undo "done".
    try {
      await saveEpgSources(db, id, adapter.epgSpecs(), hints);
    } on Object {
      // Guide URLs are found again on the next sync.
    }
    if (kept.isNotEmpty) {
      // Not stamped as synced: the next launch tries again.
      final names = [for (final k in kept) k.name].join(', ');
      return p.copyWith(
        phase: SyncPhase.failed,
        error: VerifyError(
          VerifyErrorReason.incomplete,
          message: 'Came back empty, previous items kept: $names',
        ),
      );
    }
    try {
      await db.sourcesDao.markSynced(id, task.clock.now());
    } on Object {
      // Worst case the next launch syncs again.
    }
    return p.copyWith(phase: SyncPhase.done);
  } on Object catch (e) {
    final pending = gen;
    if (pending != null) {
      try {
        await catalog.abortGeneration(id, pending);
      } on Object {
        // The source may be gone; the next beginGeneration cleans up.
      }
    }
    if (token.isCancelled || e is CancelledFailure) {
      return p.copyWith(phase: SyncPhase.cancelled);
    }
    return p.copyWith(
      phase: SyncPhase.failed,
      error: VerifyError.fromError(
        e,
        kind: task.config.kind,
        secrets: sourceSecrets(task.config),
      ),
    );
  } finally {
    adapter.close();
  }
}

/// Records the guide URLs found by a sync in `epg_sources`: Xtream
/// `xmltv.php` first, then playlist header URLs. Manual entries are kept;
/// automatic entries that were not found again are removed. Credentials in
/// URLs go to the secret store (see `EpgDao.addEpgSource`).
Future<void> saveEpgSources(
  AppDatabase db,
  int sourceId,
  List<EpgSourceSpec> specs,
  List<String> hints,
) async {
  final wanted = <String, EpgOrigin>{};
  for (final spec in specs) {
    wanted.putIfAbsent(spec.url.trim(), () => spec.origin);
  }
  for (final url in hints) {
    wanted.putIfAbsent(url.trim(), () => EpgOrigin.m3uHeader);
  }
  wanted.removeWhere((url, _) => !_isHttpUrl(url));
  final ordered = wanted.entries.toList()
    ..sort((a, b) => a.value.index.compareTo(b.value.index));
  final epg = db.epgDao;
  final keep = <String>{};
  for (final (i, entry) in ordered.indexed) {
    keep.add(redact(entry.key));
    await epg.addEpgSource(sourceId, entry.key, entry.value, priority: i);
  }
  for (final row in await epg.epgSources(sourceId)) {
    if (row.origin != EpgOrigin.manual && !keep.contains(row.url)) {
      await epg.deleteEpgSource(row.id);
    }
  }
}

bool _isHttpUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

Set<ContentKind> _kindsOf(SyncScope scope) => {
  if (scope.live) ContentKind.live,
  if (scope.movies) ContentKind.movie,
  if (scope.series) ContentKind.series,
};

SyncPhase _firstPhase(SyncScope scope) => scope.live
    ? SyncPhase.live
    : scope.movies
    ? SyncPhase.movies
    : SyncPhase.series;

SyncPhase _phaseAfter(ContentKind done, SyncScope scope) => switch (done) {
  ContentKind.live =>
    scope.movies
        ? SyncPhase.movies
        : scope.series
        ? SyncPhase.series
        : SyncPhase.saving,
  ContentKind.movie => scope.series ? SyncPhase.series : SyncPhase.saving,
  ContentKind.series => SyncPhase.saving,
};

/// Runs catalog syncs, at most one per source at a time.
///
/// [sync] starts a run (or joins the one already running for that source)
/// and returns its progress; the run continues whether or not anyone
/// listens. [statusOf] / [watchStatus] expose idle / running / done / failed
/// per source for the UI. After a successful sync [onSynced] is called and
/// [syncedSources] emits the source id (the EPG service hooks in here).
class SyncService {
  SyncService(
    this._db,
    this._repo, {
    this._clock = const SystemClock(),
    SyncRunner? runner,
    this.onSynced,
    RingLog? log,
  }) : _runner = runner ?? InlineSyncRunner(_repo.adapterFor),
       _log = log ?? RingLog.instance;

  final AppDatabase _db;
  final SourceRepository _repo;
  final Clock _clock;
  final SyncRunner _runner;
  final RingLog _log;

  /// Called on the main isolate after each successful sync.
  final void Function(int sourceId)? onSynced;

  final _jobs = <int, _SyncJob>{};
  final _status = <int, SyncStatus>{};
  final _statusChanges = StreamController<(int, SyncStatus)>.broadcast(
    sync: true,
  );
  final _synced = StreamController<int>.broadcast();
  bool _disposed = false;

  /// Starts a full sync of [sourceId] (or joins the running one) and
  /// returns its progress, starting with the latest snapshot. The stream
  /// ends after the final [SyncPhase.done] / [SyncPhase.failed] /
  /// [SyncPhase.cancelled] event; it never emits errors.
  ///
  /// [replaceEmptyFamilies]: the user asked for this sync, so a family that
  /// comes back empty is removed rather than kept
  /// ([SyncTask.replaceEmptyFamilies]). Joining a running sync keeps its
  /// setting.
  Stream<SyncProgress> sync(
    int sourceId, {
    SyncScope scope = SyncScope.all,
    bool replaceEmptyFamilies = false,
  }) {
    if (_disposed) throw StateError('SyncService disposed');
    return (_jobs[sourceId] ??
            _start(sourceId, scope, replaceEmptyFamilies: replaceEmptyFamilies))
        .watch();
  }

  /// [sync] and wait for the final progress.
  Future<SyncProgress> syncAndWait(
    int sourceId, {
    SyncScope scope = SyncScope.all,
    bool replaceEmptyFamilies = false,
  }) => sync(
    sourceId,
    scope: scope,
    replaceEmptyFamilies: replaceEmptyFamilies,
  ).last;

  bool isRunning(int sourceId) => _jobs.containsKey(sourceId);

  /// Stops the running sync of [sourceId], if any. Families the run already
  /// committed keep their new rows; the others stay as they were.
  void cancel(int sourceId) => _jobs[sourceId]?.cancel();

  /// [cancel] and wait until the run has stopped.
  Future<void> cancelAndWait(int sourceId) async {
    final job = _jobs[sourceId];
    if (job == null) return;
    job.cancel();
    await job.done;
  }

  SyncStatus statusOf(int sourceId) => _status[sourceId] ?? const SyncIdle();

  /// The current status, then every change.
  Stream<SyncStatus> watchStatus(int sourceId) => Stream.multi((c) {
    c.add(statusOf(sourceId));
    final sub = _statusChanges.stream
        .where((e) => e.$1 == sourceId)
        .listen((e) => c.add(e.$2));
    c.onCancel = sub.cancel;
  });

  /// Ids of sources whose sync just committed.
  Stream<int> get syncedSources => _synced.stream;

  /// Cancels every run. The service cannot be used afterwards.
  void dispose() {
    _disposed = true;
    for (final job in _jobs.values) {
      job.cancel();
    }
    unawaited(_statusChanges.close());
    unawaited(_synced.close());
  }

  _SyncJob _start(
    int sourceId,
    SyncScope scope, {
    required bool replaceEmptyFamilies,
  }) {
    final job = _SyncJob(sourceId);
    _jobs[sourceId] = job;
    _setStatus(sourceId, SyncRunning(job.latest));
    _log.info('Sync of source $sourceId started');
    unawaited(_run(job, scope, replaceEmptyFamilies: replaceEmptyFamilies));
    return job;
  }

  Future<void> _run(
    _SyncJob job,
    SyncScope scope, {
    required bool replaceEmptyFamilies,
  }) async {
    final id = job.sourceId;
    SyncProgress result;
    try {
      final config = await _repo.configFor(id);
      if (job.cancelRequested) {
        result = job.latest.copyWith(phase: SyncPhase.cancelled);
      } else {
        final execution = _runner.start(
          _db,
          SyncTask(
            sourceId: id,
            config: config,
            scope: scope,
            lowMemory: _repo.lowMemory,
            replaceEmptyFamilies: replaceEmptyFamilies,
            clock: _clock,
          ),
          (p) => _onProgress(job, p),
        );
        job.execution = execution;
        result = await execution.result;
      }
    } on Object catch (e, st) {
      _log.error('Sync of source $id crashed', e, st);
      result = job.latest.copyWith(
        phase: job.cancelRequested ? SyncPhase.cancelled : SyncPhase.failed,
        error: job.cancelRequested ? null : VerifyError.fromError(e),
      );
    }
    _jobs.remove(id);
    job.finish(result);
    switch (result.phase) {
      case SyncPhase.done:
        _log.info('Sync of source $id done: $result');
        _setStatus(id, SyncDone(result, finishedAt: _clock.now()));
        try {
          onSynced?.call(id);
        } on Object catch (e, st) {
          _log.error('onSynced($id) failed', e, st);
        }
        if (!_synced.isClosed) _synced.add(id);
      case SyncPhase.cancelled:
        _log.info('Sync of source $id cancelled');
        _setStatus(id, SyncFailed(result));
      default:
        _log.warn('Sync of source $id failed: ${result.error}');
        _setStatus(id, SyncFailed(result));
    }
  }

  void _onProgress(_SyncJob job, SyncProgress p) {
    if (p.isTerminal || !identical(_jobs[job.sourceId], job)) return;
    job.update(p);
    _setStatus(job.sourceId, SyncRunning(p));
  }

  void _setStatus(int sourceId, SyncStatus status) {
    _status[sourceId] = status;
    if (!_statusChanges.isClosed) _statusChanges.add((sourceId, status));
  }
}

class _SyncJob {
  _SyncJob(this.sourceId) : latest = SyncProgress(sourceId: sourceId);

  final int sourceId;
  SyncProgress latest;
  SyncExecution? execution;
  bool cancelRequested = false;
  final _events = StreamController<SyncProgress>.broadcast(sync: true);
  final _done = Completer<SyncProgress>();

  Future<SyncProgress> get done => _done.future;

  void cancel() {
    cancelRequested = true;
    execution?.cancel();
  }

  void update(SyncProgress p) {
    if (latest.isTerminal) return;
    latest = p;
    _events.add(p);
  }

  void finish(SyncProgress p) {
    if (latest.isTerminal) return;
    latest = p;
    _events.add(p);
    unawaited(_events.close());
    _done.complete(p);
  }

  /// The latest snapshot, then every update until the run ends.
  Stream<SyncProgress> watch() => Stream.multi((c) {
    c.add(latest);
    if (latest.isTerminal) {
      unawaited(c.close());
      return;
    }
    final sub = _events.stream.listen(c.add, onDone: c.close);
    c.onCancel = sub.cancel;
  });
}
