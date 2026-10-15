// Riverpod wiring of the guide pipeline: the one EpgService of the app,
// per-source refresh status for the UI and the background refresh schedule.
//
// Wiring: `IptvApp.build` keeps the schedule alive for the app's lifetime
// (`ref.listen(epgAutoRefreshProvider, (_, _) {})`; the guide screen does
// the same). The fullscreen player reports itself through
// [fullscreenPlaybackProvider], so Lite devices hold guide imports while it
// plays. Settings' "Refresh guide" and the player, Live, Favorites and
// Search screens use [guideRefreshProvider] (a finished run makes them read
// now/next again).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/net/http.dart';
import '../sources/source_repository.dart';
import '../sources/sync/sync_service.dart';
import 'epg_progress.dart';
import 'epg_service.dart';

// ---------------------------------------------------------------------------
// The service.

/// HTTP clients for guide downloads (`createDio`; tests swap in a fake).
final epgDioFactoryProvider = Provider<EpgDioFactory>((ref) => createDio);

/// Whether guide imports run in a background isolate. Widget tests that run
/// real imports override it with false.
final epgRunInIsolateProvider = Provider<bool>((ref) => true);

/// The guide pipeline of the app database: one instance, so it can allow
/// one refresh per source and cancel runs (see [EpgService]).
///
/// Source configurations are loaded through [SourceRepository.configFor],
/// which also registers the source's credentials with the log.
final epgServiceProvider = Provider<EpgService>((ref) {
  final repo = ref.watch(sourceRepositoryProvider);
  final service = EpgService(
    db: ref.watch(databaseProvider),
    dioFactory: ref.watch(epgDioFactoryProvider),
    configLoader: (id) async {
      try {
        return await repo.configFor(id);
      } on StateError {
        return null; // Deleted meanwhile.
      }
    },
    clock: ref.watch(clockProvider),
    runInIsolate: ref.watch(epgRunInIsolateProvider),
  );
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

// ---------------------------------------------------------------------------
// Refresh status per source.

/// Guide refresh state of one source, for the UI.
@immutable
sealed class GuideRefreshStatus {
  const GuideRefreshStatus();

  bool get isRunning => this is GuideRefreshRunning;
}

/// No refresh was started through [guideRefreshProvider] in this run.
final class GuideRefreshIdle extends GuideRefreshStatus {
  const GuideRefreshIdle();

  @override
  bool operator ==(Object other) => other is GuideRefreshIdle;

  @override
  int get hashCode => 0;
}

/// A refresh is running; [latest] is its most recent progress event.
final class GuideRefreshRunning extends GuideRefreshStatus {
  const GuideRefreshRunning({this.latest, this.forced = false});

  final EpgProgress? latest;

  /// Whether the run downloads every guide in full ("Refresh guide").
  final bool forced;
}

/// The last refresh finished; some guides may have failed (see [result]).
final class GuideRefreshDone extends GuideRefreshStatus {
  const GuideRefreshDone(this.result, {required this.finishedAt});

  final EpgRefreshDone result;
  final DateTime finishedAt;
}

/// The last refresh failed as a whole or was cancelled.
final class GuideRefreshFailed extends GuideRefreshStatus {
  const GuideRefreshFailed({this.message, this.cancelled = false});

  /// Redacted reason (never contains credentials); null when [cancelled].
  final String? message;
  final bool cancelled;
}

/// Refresh status of each source; the notifier starts refreshes.
final guideRefreshProvider =
    NotifierProvider.family<GuideRefreshController, GuideRefreshStatus, int>(
      GuideRefreshController.new,
    );

/// Starts guide refreshes of one source and follows their progress.
///
/// * [refresh]: "Refresh guide" uses `force: true` (every guide is
///   downloaded in full); so must Settings after changing the source's
///   guide offset.
/// * [refreshAfterSync]: after a catalog sync. A run that was already going
///   may have matched the old channel list, so a new run follows it.
class GuideRefreshController extends Notifier<GuideRefreshStatus> {
  GuideRefreshController(this.sourceId);

  final int sourceId;

  StreamSubscription<EpgProgress>? _sub;
  bool _again = false;

  /// Callers of [run] waiting for the run to end.
  final _waiters = <Completer<GuideRefreshStatus>>[];

  @override
  GuideRefreshStatus build() {
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      _sub = null;
      _completeWaiters(const GuideRefreshFailed(cancelled: true));
    });
    return const GuideRefreshIdle();
  }

  /// [refresh], completing with the status the run ends in: done, failed
  /// or cancelled (also when it is cancelled to pause imports).
  Future<GuideRefreshStatus> run({bool force = false}) {
    refresh(force: force);
    if (!state.isRunning) return Future.value(state);
    final waiter = Completer<GuideRefreshStatus>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void _completeWaiters(GuideRefreshStatus status) {
    final waiters = List.of(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete(status);
    }
  }

  /// Starts a refresh, or joins the running one (see [EpgService.refresh]).
  void refresh({bool force = false}) {
    final EpgService service;
    final Stream<EpgProgress> events;
    try {
      service = ref.read(epgServiceProvider);
      events = service.refresh(
        sourceId,
        force: force,
        lite: ref.read(liteModeProvider),
        refreshHours: ref.read(settingsProvider).epgRefreshHours,
      );
    } on StateError catch (e) {
      state = GuideRefreshFailed(message: '$e');
      return;
    }
    unawaited(_sub?.cancel());
    state = GuideRefreshRunning(forced: force);
    _sub = events.listen(_onEvent);
  }

  /// Refreshes after a catalog sync of this source: at once, or after the
  /// refresh that is running now.
  void refreshAfterSync() {
    final running = ref.read(epgServiceProvider).isRefreshing(sourceId);
    if (running && state.isRunning) {
      _again = true;
      return;
    }
    // Joins a run started elsewhere, then runs again once it has ended.
    _again = running;
    refresh();
  }

  /// Cancels the running refresh, if any.
  Future<void> cancel() async {
    _again = false;
    await ref.read(epgServiceProvider).cancel(sourceId);
  }

  void _onEvent(EpgProgress event) {
    if (!ref.mounted) return;
    final forced = switch (state) {
      GuideRefreshRunning(:final forced) => forced,
      _ => false,
    };
    switch (event) {
      case final EpgRefreshDone done:
        state = GuideRefreshDone(
          done,
          finishedAt: ref.read(clockProvider).now(),
        );
      case EpgRefreshFailed(:final message):
        state = GuideRefreshFailed(message: message);
      case EpgRefreshCancelled():
        state = const GuideRefreshFailed(cancelled: true);
      default:
        state = GuideRefreshRunning(latest: event, forced: forced);
        return;
    }
    _sub = null;
    _completeWaiters(state);
    if (_again) {
      _again = false;
      // Not from inside the event handler of the run that just ended.
      scheduleMicrotask(() {
        if (ref.mounted) refresh();
      });
    }
  }
}

// ---------------------------------------------------------------------------
// Background schedule.

/// Whether the fullscreen player is playing. The player screen sets it
/// while it is open; nothing else reads it to decide anything but guide
/// imports.
final fullscreenPlaybackProvider = NotifierProvider<FullscreenPlayback, bool>(
  FullscreenPlayback.new,
);

class FullscreenPlayback extends Notifier<bool> {
  @override
  bool build() => false;

  /// Fullscreen playback started ([active]) or ended. Ignored once the
  /// app is shutting down.
  void set(bool active) {
    if (ref.mounted) state = active;
  }
}

/// Whether guide imports wait: fullscreen playback on a Lite device, where
/// a download and XMLTV parse next to the player could make it stutter.
final epgImportsPausedProvider = Provider<bool>(
  (ref) => ref.watch(liteModeProvider) && ref.watch(fullscreenPlaybackProvider),
);

/// How often the active source's guide is checked while the app runs (TV
/// boxes stay on for days); null turns the periodic check off.
final epgAutoRefreshIntervalProvider = Provider<Duration?>(
  (ref) => const Duration(hours: 1),
);

/// Keeps guides fresh in the background while it is alive (`IptvApp`
/// keeps it alive for the app's lifetime):
///
/// * after every successful catalog sync of any source
///   ([SyncService.syncedSources]): [GuideRefreshController.refreshAfterSync];
/// * once per launch and source, when a source becomes active and has a
///   catalog: a refresh if [EpgService.needsRefresh] says a guide is due
///   (Settings' refresh interval). A sync of that source that is running
///   decides instead: done refreshes anyway, failed runs this check;
/// * every [epgAutoRefreshIntervalProvider], the same check for the active
///   source.
///
/// While [epgImportsPausedProvider] is true (fullscreen playback on a Lite
/// device), refreshes it would start are held, and running ones (also
/// "Refresh guide" runs) are cancelled and held; held runs start when the
/// pause ends, followed by the periodic check.
final epgAutoRefreshProvider = Provider<EpgAutoRefresh>((ref) {
  final auto = EpgAutoRefresh._(ref);
  ref.onDispose(auto._dispose);
  final synced = ref
      .watch(syncServiceProvider)
      .syncedSources
      .listen(auto._onSynced);
  ref.onDispose(synced.cancel);
  ref.listen<int?>(activeSourceIdProvider, (_, id) {
    if (id != null) unawaited(auto.checkSource(id));
  }, fireImmediately: true);
  ref.listen<bool>(epgImportsPausedProvider, (_, paused) {
    if (paused) {
      auto._pause();
    } else {
      auto._resume();
    }
  });
  final every = ref.watch(epgAutoRefreshIntervalProvider);
  if (every != null) {
    auto._timer = Timer.periodic(every, (_) => unawaited(auto._periodic()));
  }
  return auto;
});

/// A refresh [EpgAutoRefresh] holds while imports are paused; a later
/// value includes the earlier ones.
enum _Held {
  /// A plain refresh (a due check, a cancelled background run).
  refresh,

  /// [GuideRefreshController.refreshAfterSync].
  afterSync,

  /// A cancelled "Refresh guide" run.
  forced,
}

/// The state behind [epgAutoRefreshProvider].
class EpgAutoRefresh {
  EpgAutoRefresh._(this._ref);

  final Ref _ref;

  /// Sources whose launch check is done.
  final _checked = <int>{};

  /// Sources whose launch check is running.
  final _checking = <int>{};
  final _waits = <StreamSubscription<SyncStatus>, Completer<SyncStatus?>>{};

  /// Refreshes waiting for the import pause to end, by source.
  final _held = <int, _Held>{};
  Timer? _timer;
  bool _disposed = false;

  /// Whether the launch check of [sourceId] has run.
  @visibleForTesting
  bool checked(int sourceId) => _checked.contains(sourceId);

  /// Sources with a refresh waiting for the import pause to end.
  @visibleForTesting
  Set<int> get held => Set.unmodifiable(_held.keys);

  bool get _paused => _ref.read(epgImportsPausedProvider);

  /// The launch check of [sourceId] (does nothing after the first time).
  Future<void> checkSource(int sourceId) async {
    if (_checked.contains(sourceId) || !_checking.add(sourceId)) return;
    try {
      // Leave the provider build that may have called this.
      await Future<void>.value();
      while (!_disposed && !_checked.contains(sourceId)) {
        final sync = _ref.read(syncServiceProvider);
        if (sync.isRunning(sourceId)) {
          final end = await _syncEnd(sync, sourceId);
          if (end == null) return;
          // Done: the synced event refreshes. Failed: check now.
          if (end is SyncDone) _checked.add(sourceId);
          continue;
        }
        final source = await _ref.read(sourcesDaoProvider).byId(sourceId);
        // No catalog yet: the first sync's end refreshes the guide.
        if (_disposed || source == null || !source.hasCatalog) return;
        final due = await _isDue(sourceId);
        if (_disposed) return;
        if (sync.isRunning(sourceId)) continue;
        _checked.add(sourceId);
        if (due) _start(sourceId, _Held.refresh);
      }
    } on Object catch (e, st) {
      if (!_disposed) {
        _ref.read(ringLogProvider).error('Guide check failed', e, st);
      }
    } finally {
      _checking.remove(sourceId);
    }
  }

  void _onSynced(int sourceId) {
    if (_disposed) return;
    _checked.add(sourceId);
    _start(sourceId, _Held.afterSync);
  }

  /// Starts [what] for [sourceId], or holds it while imports are paused.
  void _start(int sourceId, _Held what) {
    if (_paused) {
      _hold(sourceId, what);
      return;
    }
    final controller = _controller(sourceId);
    switch (what) {
      case _Held.refresh:
        controller.refresh();
      case _Held.afterSync:
        controller.refreshAfterSync();
      case _Held.forced:
        controller.refresh(force: true);
    }
  }

  void _hold(int sourceId, _Held what) {
    final held = _held[sourceId];
    if (held == null || what.index > held.index) _held[sourceId] = what;
  }

  /// Imports paused: cancels the refreshes that are running and holds them.
  void _pause() {
    if (_disposed) return;
    final service = _ref.read(epgServiceProvider);
    final sources = _ref.read(sourcesProvider).value ?? const <SourceView>[];
    for (final source in sources) {
      final id = source.id;
      if (!service.isRefreshing(id)) continue;
      final known = _ref.exists(guideRefreshProvider(id));
      final status = known ? _ref.read(guideRefreshProvider(id)) : null;
      final forced = status is GuideRefreshRunning && status.forced;
      // Whatever it was for, run it again in full once playback ends.
      _hold(id, forced ? _Held.forced : _Held.afterSync);
      unawaited(known ? _controller(id).cancel() : service.cancel(id));
    }
  }

  /// Imports may run again: starts what was held, then checks the active
  /// source as the periodic check would.
  void _resume() {
    if (_disposed) return;
    final held = Map.of(_held);
    _held.clear();
    for (final MapEntry(key: id, value: what) in held.entries) {
      _start(id, what);
    }
    unawaited(_periodic());
  }

  Future<void> _periodic() async {
    bool busy(int id) =>
        _paused ||
        _ref.read(syncServiceProvider).isRunning(id) ||
        _ref.read(guideRefreshProvider(id)).isRunning;
    final id = _ref.read(activeSourceIdProvider);
    if (id == null || !_checked.contains(id) || busy(id)) return;
    try {
      final due = await _isDue(id);
      // Checked again: another check (the timer, the end of a pause) may
      // have started a refresh while this one read the guide state.
      if (due && !_disposed && !busy(id)) _start(id, _Held.refresh);
    } on Object catch (e, st) {
      if (!_disposed) {
        _ref.read(ringLogProvider).error('Guide check failed', e, st);
      }
    }
  }

  Future<bool> _isDue(int sourceId) => _ref
      .read(epgServiceProvider)
      .needsRefresh(
        sourceId,
        refreshHours: _ref.read(settingsProvider).epgRefreshHours,
      );

  GuideRefreshController _controller(int sourceId) =>
      _ref.read(guideRefreshProvider(sourceId).notifier);

  /// The final status of the running sync of [sourceId]; null when this
  /// object is disposed first.
  Future<SyncStatus?> _syncEnd(SyncService sync, int sourceId) {
    final done = Completer<SyncStatus?>();
    late final StreamSubscription<SyncStatus> sub;
    sub = sync.watchStatus(sourceId).listen((s) {
      if (s is SyncRunning || done.isCompleted) return;
      _waits.remove(sub);
      unawaited(sub.cancel());
      done.complete(s);
    });
    _waits[sub] = done;
    return done.future;
  }

  void _dispose() {
    _disposed = true;
    _timer?.cancel();
    for (final MapEntry(key: sub, value: done) in _waits.entries) {
      unawaited(sub.cancel());
      if (!done.isCompleted) done.complete(null);
    }
    _waits.clear();
  }
}
