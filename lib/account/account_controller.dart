import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app/providers.dart';
import '../core/db/app_db.dart';
import '../features/settings/providers.dart';
import 'firebase_api.dart';
import 'firebase_config.dart';
import 'local_sync_store.dart';
import 'sync_model.dart';

abstract interface class SessionVault {
  Future<String?> read();
  Future<void> write(String? value);
}

class SecureSessionVault implements SessionVault {
  const SecureSessionVault();
  static const _storage = FlutterSecureStorage();
  static const _key = 'iptv_firebase_session_v1';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String? value) => value == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: value);
}

class AccountView {
  const AccountView({
    this.email,
    this.busy = false,
    this.error,
    this.lastSync,
    this.linked = false,
  });
  final String? email;
  final bool busy;
  final String? error;
  final DateTime? lastSync;

  /// This device's data belongs to an account, also while signed out: its
  /// changes, deletions included, reach the other devices once it syncs.
  final bool linked;
}

final accountControllerProvider = Provider<AccountController>((ref) {
  final controller = AccountController(
    db: ref.watch(databaseProvider),
    api: FirebaseAccountApi(
      projectId: FirebaseConfig.projectId,
      apiKey: FirebaseConfig.apiKey,
    ),
    vault: const SecureSessionVault(),
    onImported: (ids) {
      for (final id in ids) {
        final sync = ref.read(syncServiceProvider);
        if (!sync.isRunning(id)) sync.sync(id);
      }
    },
    // As Settings does after an offset change: offsets apply at import.
    onGuideOffset: (ids) {
      final refresh = ref.read(refreshGuideActionProvider);
      final log = ref.read(ringLogProvider);
      for (final id in ids) {
        unawaited(
          refresh(id, force: true).catchError(
            (Object e, StackTrace st) =>
                log.error('Guide refresh failed', e, st),
          ),
        );
      }
    },
    onPreferences: () async {
      final settings = await loadAppSettings(ref.read(settingsDaoProvider));
      await ref
          .read(settingsProvider.notifier)
          .update(
            (s) => s.copyWith(
              locale: settings.locale,
              preferredAudioLang: settings.preferredAudioLang,
              preferredSubLang: settings.preferredSubLang,
            ),
          );
    },
  );
  ref.onDispose(controller.dispose);
  if (FirebaseConfig.enabled) unawaited(controller.start());
  return controller;
});

final accountViewProvider = StreamProvider<AccountView>((ref) async* {
  final controller = ref.watch(accountControllerProvider);
  yield controller.view;
  yield* controller.views;
});

class AccountController with WidgetsBindingObserver {
  AccountController({
    required this.db,
    required this.api,
    required this.vault,
    LocalSyncStore? local,
    this.onImported,
    this.onGuideOffset,
    this.onPreferences,
    this.pollInterval = const Duration(seconds: 30),
    this.playbackDelay = const Duration(minutes: 2),
    this.vaultTimeout = const Duration(seconds: 10),
  }) : local = local ?? LocalSyncStore(db);
  final AppDatabase db;
  final FirebaseAccountApi api;
  final SessionVault vault;
  final LocalSyncStore local;
  final void Function(Set<int>)? onImported;

  /// Sources whose guide offset changed: their guides need a forced refresh.
  final void Function(Set<int>)? onGuideOffset;
  final Future<void> Function()? onPreferences;
  final Duration pollInterval;

  /// How long playback progress and recent channels wait for an upload.
  final Duration playbackDelay;

  /// How long a secure-storage call may take before it counts as failed.
  /// A store can stop answering: the Windows one retries a file it cannot
  /// write forever, and queues every later call behind it.
  final Duration vaultTimeout;
  final _views = StreamController<AccountView>.broadcast();
  Stream<AccountView> get views => _views.stream;
  AccountView view = const AccountView();
  AccountSession? _session;
  Timer? _poll;
  Timer? _debounce;
  final _vaultTimers = <Timer>{};
  StreamSubscription<dynamic>? _updates;
  Future<void>? _running;
  bool _disposed = false;
  bool _applying = false;
  bool _paused = false;
  bool _started = false;
  bool _linked = false;

  /// The saved sign-in expired or was lost: the view asks for a new one
  /// until a sign-in succeeds.
  bool _expired = false;
  final _restored = Completer<void>();
  bool _authBusy = false;
  bool _needsSync = false;

  /// Counts the local changes seen, so a change made while a sync runs is
  /// never taken as synced.
  int _changes = 0;

  /// The pending local changes are playback only and wait for [_debounce].
  bool _deferred = false;
  String? _revision;
  bool _hasRead = false;
  static const bindingKey = 'account_sync_owner_v1';

  /// True from a sign-in to a sign-out, false after it; unset before this
  /// version. The secure storage can lose the saved sign-in (Android resets
  /// an entry it can no longer decrypt rather than fail) or fail to delete
  /// it, and this tells either case apart from a device never signed in.
  static const signedInKey = 'account_signed_in_v1';
  static const _playbackTables = {'watch_progress', 'recent_channels'};

  /// Replies meaning the saved sign-in can never work again: the password
  /// was changed or reset, or the account was disabled or deleted.
  static const _deadSession = {
    'TOKEN_EXPIRED',
    'INVALID_REFRESH_TOKEN',
    'USER_DISABLED',
    'USER_NOT_FOUND',
    'UNAUTHENTICATED',
  };
  String _baselineKey(String uid) => 'account_sync_baseline_v1:$uid';

  void _emit({bool busy = false, String? error, DateTime? synced}) {
    if (_disposed) return;
    view = AccountView(
      email: _session?.email,
      busy: busy,
      error: error ?? (_expired ? 'SESSION_EXPIRED' : null),
      lastSync: synced ?? view.lastSync,
      linked: _linked,
    );
    _views.add(view);
  }

  /// A secure-storage call that fails instead of hanging past [vaultTimeout].
  /// [dispose] cancels the timers of calls still waiting.
  Future<T> _vault<T>(Future<T> Function() call) {
    final done = Completer<T>();
    final timer = Timer(vaultTimeout, () {
      if (!done.isCompleted) {
        done.completeError(TimeoutException('Secure storage', vaultTimeout));
      }
    });
    _vaultTimers.add(timer);
    Future.sync(call).then(
      (value) {
        if (!done.isCompleted) done.complete(value);
      },
      onError: (Object e, StackTrace st) {
        if (!done.isCompleted) done.completeError(e, st);
      },
    );
    return done.future.whenComplete(() {
      timer.cancel();
      _vaultTimers.remove(timer);
    });
  }

  /// Removes the saved sign-in. Should that fail, [start] skips a sign-in
  /// saved before a sign-out, and an expired one only fails again.
  Future<void> _forgetSession() async {
    try {
      await _vault(() => vault.write(null));
    } on Object {
      // The session is dropped from memory either way.
    }
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _updates = db.tableUpdates().listen((updates) {
      const watched = {
        'sources',
        'secrets',
        'favorites',
        'channel_lists',
        'channel_list_items',
        'watch_progress',
        'recent_channels',
        'settings',
      };
      final tables = {
        for (final u in updates)
          if (watched.contains(u.table)) u.table,
      };
      if (_applying || tables.isEmpty) return;
      _changes++;
      // Playback saves progress every 10 s and every zap marks a recent
      // channel: batch those rather than commit to the account each time,
      // unless other changes wait too (an upload that failed).
      if (tables.every(_playbackTables.contains)) {
        if (!_needsSync) _deferred = true;
        _needsSync = true;
        if (_debounce?.isActive ?? false) return;
        _debounce = Timer(playbackDelay, () {
          _deferred = false;
          unawaited(sync());
        });
        return;
      }
      _needsSync = true;
      _deferred = false;
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 2), () => unawaited(sync()));
    });
    // A lost or unreadable keystore only requires signing in again; local
    // data stays.
    String? restoreError;
    try {
      _linked = await db.settingsDao.getString(bindingKey) != null;
      final signedIn = await db.settingsDao.getBool(signedInKey);
      final saved = await _vault(vault.read);
      if (_disposed) return;
      if (saved != null && signedIn == false) {
        // Signed out, but the secure storage failed to delete the sign-in.
        await _forgetSession();
      } else if (saved != null) {
        _session = AccountSession.fromJson(
          jsonDecode(saved) as Map<String, dynamic>,
        );
        if (signedIn == null) await db.settingsDao.setBool(signedInKey, true);
      } else if (signedIn ?? false) {
        // The secure storage lost the saved sign-in.
        _expired = true;
      }
    } on Object {
      restoreError = 'SESSION_STORAGE';
    } finally {
      if (!_restored.isCompleted) _restored.complete();
    }
    if (_disposed) return;
    _poll = Timer.periodic(pollInterval, (_) => unawaited(sync()));
    _emit(error: restoreError);
    await sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // An unfocused desktop window or a split-screen app is still on screen
    // and keeps playing: only hidden, paused and detached are background.
    if (state == AppLifecycleState.inactive) return;
    final paused = state != AppLifecycleState.resumed;
    if (paused == _paused) return;
    // Batched playback progress is uploaded before the app is backgrounded.
    if (paused && _needsSync) {
      _deferred = false;
      unawaited(sync());
    }
    _paused = paused;
    // Back in the foreground: the revision check finds changes made
    // elsewhere without reading the whole account.
    if (!paused) unawaited(sync());
  }

  Future<void> authenticate(
    String email,
    String password, {
    bool create = false,
  }) async {
    if (_authBusy) return;
    _authBusy = true;
    _emit(busy: true);
    try {
      if (_started) await _restored.future;
      await _running;
      if (_disposed) return;
      final session = await api.signIn(email, password, create: create);
      final owner = await db.settingsDao.getString(bindingKey);
      if (owner != null && owner != session.uid) {
        throw const AccountException('OTHER_ACCOUNT');
      }
      await _vault(() => vault.write(jsonEncode(session.toJson())));
      await db.settingsDao.setString(bindingKey, session.uid);
      await db.settingsDao.setBool(signedInKey, true);
      _session = session;
      _linked = true;
      _expired = false;
      _hasRead = false;
      _needsSync = true;
    } on AccountException {
      // The caller shows sign-in failures; the view keeps sync state only.
      _emit();
      rethrow;
    } on Object {
      _emit();
      throw const AccountException('SESSION_STORAGE');
    } finally {
      _authBusy = false;
    }
    await sync(force: true);
  }

  Future<void> signOut() async {
    if (_authBusy) return;
    _authBusy = true;
    try {
      if (_started) await _restored.future;
      await _running;
      // Recorded first, so a sign-in the secure storage fails to delete
      // stays signed out after a restart too.
      await db.settingsDao.setBool(signedInKey, false);
      await _forgetSession();
      _session = null;
      _hasRead = false;
      _revision = null;
      _emit();
    } finally {
      _authBusy = false;
    }
  }

  Future<void> sync({bool force = false}) {
    if (_disposed || _session == null || _paused || _authBusy) {
      return Future.value();
    }
    if (_running != null) return _running!;
    final result = _sync(force: force);
    _running = result;
    return result.whenComplete(() {
      _running = null;
      if (_needsSync && !_deferred && !_disposed && view.error == null) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(seconds: 2), () => unawaited(sync()));
      }
    });
  }

  Future<void> _sync({required bool force}) async {
    _emit(busy: true);
    try {
      try {
        await _exchange(force: force);
      } on AccountException catch (e) {
        if (e.code != 'UNAUTHENTICATED') rethrow;
        // Firestore refused the ID token before it expired here (a clock
        // change or a revoked sign-in): refresh once before giving up on it.
        await _exchange(force: force, refresh: true);
      }
    } on AccountException catch (e) {
      if (_deadSession.contains(e.code)) {
        await _expire();
      } else {
        _emit(error: e.code);
      }
    } on Object {
      _emit(error: 'SYNC_ERROR');
    }
  }

  /// Drops a sign-in that can never work again, as [signOut] does (the
  /// device binding, baseline and data stay), and asks for a new sign-in,
  /// also after a restart.
  Future<void> _expire() async {
    await _forgetSession();
    _session = null;
    _expired = true;
    _hasRead = false;
    _revision = null;
    _emit();
  }

  Future<void> _exchange({required bool force, bool refresh = false}) async {
    var session = _session!;
    if (refresh ||
        session.expiresAt.isBefore(
          DateTime.now().add(const Duration(minutes: 2)),
        )) {
      session = await api.refresh(session);
      if (_disposed) return;
      // Used at once: a token the secure storage cannot save still syncs
      // until a restart, which refreshes again with the saved one.
      _session = session;
      try {
        await _vault(() => vault.write(jsonEncode(session.toJson())));
      } on Object {
        // The saved refresh token stays valid.
      }
    }
    final owner = await db.settingsDao.getString(bindingKey);
    if (owner != session.uid) throw const AccountException('OTHER_ACCOUNT');
    // No local change since the last sync, or only batched playback, which
    // uploads when its delay ends: while the account is unchanged, nothing
    // here is read or exported. Changes are seen once [start] has run.
    if (!force &&
        _hasRead &&
        (_deferred || _started && !_needsSync) &&
        await api.revision(session) == _revision) {
      _emit(synced: DateTime.now());
      return;
    }
    final baseline = decodeSyncData(
      await db.settingsDao.getJson(_baselineKey(session.uid)),
    );
    await local.remember(baseline);
    final seen = _changes;
    final before = await local.export();
    final edits = syncChanges(baseline, before);
    if (!force &&
        _hasRead &&
        edits.isEmpty &&
        await api.revision(session) == _revision) {
      _needsSync = _changes != seen;
      _emit(synced: DateTime.now());
      return;
    }
    // Only local edits: commit them on top of the last synced state. Its
    // revision is the write precondition, so a change made elsewhere since
    // then fails as a CONFLICT and falls back to a full read and merge.
    var known = !force && _hasRead && edits.isNotEmpty
        ? RemoteState(baseline, _revision)
        : null;
    for (var attempt = 0; attempt < 4; attempt++) {
      final remote = known ?? await api.read(session);
      if (baseline.isEmpty) await local.link(remote.data);
      final sent = known != null ? before : await local.export();
      known = null;
      final pending = baseline.isEmpty
          ? initialSyncChanges(remote.data, remote.deletedKeys, sent)
          : syncChanges(baseline, sent);
      // A source or list deleted elsewhere wins over an edit made here before
      // this device heard of it: reviving it alone would drop its contents.
      pending.removeWhere(
        (key, r) =>
            (r?['type'] == 'source' || r?['type'] == 'list') &&
            baseline.containsKey(key) &&
            remote.deletedKeys.contains(key),
      );
      final merged = mergeSyncData(remote.data, pending);
      // Source/list deletion wins over orphaned children from offline devices.
      merged.removeWhere(
        (key, r) =>
            r['type'] != 'source' &&
            r.containsKey('source') &&
            !merged.containsKey('source:${r['source']}'),
      );
      merged.removeWhere(
        (key, r) =>
            r['type'] == 'item' && !merged.containsKey('list:${r['list']}'),
      );
      // Playlist chunks commit before their source record, so an upload cut
      // off between commits never publishes a playlist with missing chunks.
      final changes = syncChanges(remote.data, merged);
      String? committedRevision;
      try {
        committedRevision = await api.write(session, remote, {
          for (final e in changes.entries)
            if (e.key.startsWith('file:')) e.key: e.value,
          ...changes,
        });
      } on AccountException catch (e) {
        if (e.code == 'CONFLICT' && attempt < 3) continue;
        rethrow;
      }
      if (_disposed) return;
      _applying = true;
      var applied = (imports: <int>{}, guides: <int>{});
      try {
        await db.transaction(() async {
          // Nothing to apply when the account now holds what was sent.
          if (syncChanges(sent, merged).isNotEmpty) {
            final latest = await local.export();
            final withLateChanges = mergeSyncData(
              merged,
              syncChanges(sent, latest),
            );
            applied = await local.apply(withLateChanges);
          }
          await db.settingsDao.setJson(_baselineKey(session.uid), merged);
        });
        await onPreferences?.call();
      } finally {
        _applying = false;
      }
      onImported?.call(applied.imports);
      // An import refreshes the guides after the catalogue anyway.
      final guides = applied.guides.difference(applied.imports);
      if (guides.isNotEmpty) onGuideOffset?.call(guides);
      _revision = committedRevision;
      _hasRead = true;
      final settled = _changes;
      _needsSync =
          syncChanges(merged, await local.export()).isNotEmpty ||
          _changes != settled;
      _emit(synced: DateTime.now());
      return;
    }
  }

  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _debounce?.cancel();
    for (final timer in _vaultTimers) {
      timer.cancel();
    }
    unawaited(_updates?.cancel());
    if (_started) WidgetsBinding.instance.removeObserver(this);
    unawaited(_views.close());
  }
}
