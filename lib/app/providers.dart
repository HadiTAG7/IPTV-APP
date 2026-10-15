// App-wide Riverpod providers (no code generation).
//
// Bootstrap overrides [databaseProvider], [deviceCapsProvider] and
// [initialSettingsProvider]; tests override the same with an in-memory
// database (`AppDatabase(NativeDatabase.memory())`), fake caps and settings.
import 'dart:async';
import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/app_db.dart';
import '../core/log/ring_log.dart';
import '../core/platform/device_caps.dart';
import '../core/secure/secret_store.dart';
import '../core/time/clock.dart';
import '../player/engine/engine_factory.dart';
import '../sources/source_repository.dart';
import '../sources/sync/sync_service.dart';
import 'form_factor.dart';
import 'settings.dart';

export 'settings.dart';

// ---------------------------------------------------------------------------
// Core services.

/// The app database. Must be overridden (bootstrap: `AppDatabase.open()`).
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
  name: 'databaseProvider',
);

final sourcesDaoProvider = Provider<SourcesDao>(
  (ref) => ref.watch(databaseProvider).sourcesDao,
);
final catalogDaoProvider = Provider<CatalogDao>(
  (ref) => ref.watch(databaseProvider).catalogDao,
);
final favoritesDaoProvider = Provider<FavoritesDao>(
  (ref) => ref.watch(databaseProvider).favoritesDao,
);
final progressDaoProvider = Provider<ProgressDao>(
  (ref) => ref.watch(databaseProvider).progressDao,
);
final recentDaoProvider = Provider<RecentDao>(
  (ref) => ref.watch(databaseProvider).recentDao,
);
final settingsDaoProvider = Provider<SettingsDao>(
  (ref) => ref.watch(databaseProvider).settingsDao,
);
final prefsDaoProvider = Provider<PrefsDao>(
  (ref) => ref.watch(databaseProvider).prefsDao,
);
final detailCacheDaoProvider = Provider<DetailCacheDao>(
  (ref) => ref.watch(databaseProvider).detailCacheDao,
);
final epgDaoProvider = Provider<EpgDao>(
  (ref) => ref.watch(databaseProvider).epgDao,
);

/// Credentials store (the `secrets` table of the app database).
final secretStoreProvider = Provider<SecretStore>(
  (ref) => DbSecretStore(ref.watch(databaseProvider)),
);

/// Hardware and TV signals. Bootstrap overrides it with `DeviceCaps.load()`.
final deviceCapsProvider = Provider<DeviceCaps>((ref) => const DeviceCaps());

/// The platform the app runs on (overridable in tests).
final targetPlatformProvider = Provider<TargetPlatform>(
  (ref) => defaultTargetPlatform,
);

final clockProvider = Provider<Clock>((ref) => const SystemClock());

final ringLogProvider = Provider<RingLog>((ref) => RingLog.instance);

/// Exits the app (the "press back again" action on the home screen).
final appExitProvider = Provider<void Function()>((ref) {
  final platform = ref.watch(targetPlatformProvider);
  final log = ref.watch(ringLogProvider);
  return () => unawaited(exitApp(platform, log: log));
});

/// Closes the app on [platform]. Android finishes the activity
/// (`SystemNavigator.pop`, or [pop]); the desktop embedders only understand
/// `System.exitApplication` (they answer anything else with "not
/// implemented"), so desktop asks for a cancelable exit instead (or calls
/// [desktopExit]). Failures are logged, never thrown.
Future<void> exitApp(
  TargetPlatform platform, {
  RingLog? log,
  Future<void> Function()? pop,
  Future<void> Function()? desktopExit,
}) async {
  try {
    switch (platform) {
      case TargetPlatform.windows ||
          TargetPlatform.linux ||
          TargetPlatform.macOS:
        await (desktopExit ?? _requestDesktopExit)();
      case TargetPlatform.android ||
          TargetPlatform.iOS ||
          TargetPlatform.fuchsia:
        await (pop ?? SystemNavigator.pop)();
    }
  } on Object catch (e) {
    (log ?? RingLog.instance).warn('Exit failed: $e');
  }
}

Future<void> _requestDesktopExit() =>
    ServicesBinding.instance.exitApplication(AppExitType.cancelable);

// ---------------------------------------------------------------------------
// Settings.

/// Settings read at bootstrap; the start value of [settingsProvider].
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => const AppSettings(),
);

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// Whether Lite mode is in effect (Settings override, else the device).
final liteModeProvider = Provider<bool>(
  (ref) =>
      effectiveLite(ref.watch(deviceCapsProvider), ref.watch(settingsProvider)),
);

/// Options for new player engines, from Settings and Lite mode.
final engineOptionsProvider = Provider<EngineOptions>(
  (ref) => ref
      .watch(settingsProvider)
      .engineOptions(lite: ref.watch(liteModeProvider)),
);

// ---------------------------------------------------------------------------
// Form factor.

/// TV / phone / desktop for a logical screen [Size], from the device, the
/// Settings override and the platform. Widgets normally read
/// `FormFactorScope.of(context)` (installed by the app) instead.
final formFactorProvider = Provider.autoDispose.family<FormFactor, Size>(
  (ref, size) => resolveFormFactor(
    ref.watch(deviceCapsProvider),
    ref.watch(settingsProvider.select((s) => s.formFactor)),
    size,
    ref.watch(targetPlatformProvider),
  ),
);

/// Whether the app runs in TV mode (remote focus highlight, overscan margins,
/// 960 dp design canvas). TV mode never depends on the screen size.
final tvModeProvider = Provider<bool>(
  (ref) =>
      resolveFormFactor(
        ref.watch(deviceCapsProvider),
        ref.watch(settingsProvider.select((s) => s.formFactor)),
        Size.zero,
        ref.watch(targetPlatformProvider),
      ) ==
      FormFactor.tv,
);

/// Whether this screen uses the large (rail, multi-pane) layout.
bool isLargeLayout(BuildContext context) =>
    useLargeLayout(FormFactorScope.of(context), MediaQuery.sizeOf(context));

// ---------------------------------------------------------------------------
// Sources.

/// Saved sources in display order, updated on every change.
///
/// Each source's credentials are registered with the [RingLog] before the
/// list is delivered, so Diagnostics masks them from the first frame on
/// (stream URLs such as `http://host/user/pass/1` are not recognisable
/// without them).
final sourcesProvider = StreamProvider<List<SourceView>>((ref) {
  final repo = ref.watch(sourceRepositoryProvider);
  return ref.watch(sourcesDaoProvider).watchAll().asyncMap((rows) async {
    await repo.rememberSecretsOf(rows);
    return rows;
  });
});

/// The id stored under the `activeSourceId` setting (may be stale).
final storedActiveSourceIdProvider = StreamProvider<int?>(
  (ref) => ref.watch(sourcesDaoProvider).watchActiveSourceId(),
);

/// The source the UI shows: the stored choice when it still exists, else
/// the first source, else null. [ActiveSourceController.select] changes and
/// persists it.
///
/// Null until both the sources and the stored choice have loaded (see
/// [activeSourceReadyProvider]): falling back to the first source in the
/// meantime would briefly show, and auto-sync, a source the user did not
/// pick.
final activeSourceIdProvider = NotifierProvider<ActiveSourceController, int?>(
  ActiveSourceController.new,
);

class ActiveSourceController extends Notifier<int?> {
  @override
  int? build() {
    if (!ref.watch(activeSourceReadyProvider)) return null;
    final sources = ref.watch(sourcesProvider).value ?? const <SourceView>[];
    final stored = ref.watch(storedActiveSourceIdProvider).value;
    if (sources.isEmpty) return null;
    if (stored != null && sources.any((s) => s.id == stored)) return stored;
    return sources.first.id;
  }

  /// Makes [sourceId] the active source and saves the choice.
  Future<void> select(int sourceId) async {
    state = sourceId;
    await ref.read(sourcesDaoProvider).setActive(sourceId);
  }
}

/// Whether the sources and the stored active source id have loaded (or
/// failed to load), so [activeSourceIdProvider] is final. The root screen
/// waits for it.
final activeSourceReadyProvider = Provider<bool>((ref) {
  bool settled(AsyncValue<Object?> v) => v.hasValue || v.hasError;
  return settled(ref.watch(sourcesProvider)) &&
      settled(ref.watch(storedActiveSourceIdProvider));
});

/// The active source row, or null when there are no sources.
final activeSourceProvider = Provider<SourceView?>((ref) {
  final id = ref.watch(activeSourceIdProvider);
  if (id == null) return null;
  final sources = ref.watch(sourcesProvider).value ?? const <SourceView>[];
  return sources.where((s) => s.id == id).firstOrNull;
});

/// Keeps onboarding on screen after its flow saved the first source (for
/// example while the first import runs). The onboarding screen sets it to
/// true while busy and back to false when done.
final onboardingHoldProvider = NotifierProvider<OnboardingHold, bool>(
  OnboardingHold.new,
);

class OnboardingHold extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool hold) => state = hold;
}

final sourceRepositoryProvider = Provider<SourceRepository>((ref) {
  return SourceRepository(
    ref.watch(databaseProvider),
    ref.watch(secretStoreProvider),
    lowMemory: () => ref.read(liteModeProvider),
    clock: ref.watch(clockProvider),
    log: ref.watch(ringLogProvider),
  );
});

// ---------------------------------------------------------------------------
// Sync.

/// Where catalog syncs run: a background isolate in the app. Tests override
/// it with `InlineSyncRunner(repo.adapterFor)`.
final syncRunnerProvider = Provider<SyncRunner>(
  (ref) => const IsolateSyncRunner(),
);

/// Called after each successful sync. The guide schedule
/// (`epgAutoRefreshProvider`) follows [SyncService.syncedSources] instead,
/// so this is free for other listeners.
final onSourceSyncedProvider = Provider<void Function(int sourceId)?>(
  (ref) => null,
);

/// Runs catalog syncs. Deleting a source through [sourceRepositoryProvider]
/// first cancels that source's running sync.
final syncServiceProvider = Provider<SyncService>((ref) {
  final repo = ref.watch(sourceRepositoryProvider);
  final service = SyncService(
    ref.watch(databaseProvider),
    repo,
    clock: ref.watch(clockProvider),
    runner: ref.watch(syncRunnerProvider),
    onSynced: ref.watch(onSourceSyncedProvider),
    log: ref.watch(ringLogProvider),
  );
  repo.beforeDelete = service.cancelAndWait;
  ref.onDispose(() {
    if (repo.beforeDelete == service.cancelAndWait) repo.beforeDelete = null;
    service.dispose();
  });
  return service;
});

/// Sync state of one source: idle, running (with progress), done or failed.
final syncStatusProvider =
    NotifierProvider.family<SyncStatusNotifier, SyncStatus, int>(
      SyncStatusNotifier.new,
    );

class SyncStatusNotifier extends Notifier<SyncStatus> {
  SyncStatusNotifier(this.sourceId);

  final int sourceId;

  @override
  SyncStatus build() {
    final service = ref.watch(syncServiceProvider);
    final sub = service.watchStatus(sourceId).skip(1).listen((s) {
      if (ref.mounted) state = s;
    });
    ref.onDispose(sub.cancel);
    return service.statusOf(sourceId);
  }
}

/// Whether the home screen starts a sync on launch when the active source's
/// catalog is older than [autoSyncMaxAge] (or was never synced).
final autoSyncOnStartProvider = Provider<bool>((ref) => true);

/// Age after which the active source is re-synced on launch.
const autoSyncMaxAge = Duration(hours: 24);

/// Whether [source] should be synced on launch at [now].
bool needsAutoSync(SourceView source, DateTime now) {
  final last = source.lastSyncAt;
  return last == null || now.difference(last) >= autoSyncMaxAge;
}
