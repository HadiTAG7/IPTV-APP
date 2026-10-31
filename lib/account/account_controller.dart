import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app/providers.dart';
import '../core/db/app_db.dart';
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
  const AccountView({this.email, this.busy = false, this.error, this.lastSync});
  final String? email;
  final bool busy;
  final String? error;
  final DateTime? lastSync;
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
    this.onPreferences,
    this.pollInterval = const Duration(seconds: 30),
  }) : local = local ?? LocalSyncStore(db);
  final AppDatabase db;
  final FirebaseAccountApi api;
  final SessionVault vault;
  final LocalSyncStore local;
  final void Function(Set<int>)? onImported;
  final Future<void> Function()? onPreferences;
  final Duration pollInterval;
  final _views = StreamController<AccountView>.broadcast();
  Stream<AccountView> get views => _views.stream;
  AccountView view = const AccountView();
  AccountSession? _session;
  Timer? _poll;
  Timer? _debounce;
  StreamSubscription<dynamic>? _updates;
  Future<void>? _running;
  bool _disposed = false;
  bool _applying = false;
  bool _paused = false;
  bool _started = false;
  final _restored = Completer<void>();
  bool _authBusy = false;
  bool _needsSync = false;
  String? _revision;
  bool _hasRead = false;
  static const bindingKey = 'account_sync_owner_v1';
  String _baselineKey(String uid) => 'account_sync_baseline_v1:$uid';

  void _emit({bool busy = false, String? error, DateTime? synced}) {
    if (_disposed) return;
    view = AccountView(
      email: _session?.email,
      busy: busy,
      error: error,
      lastSync: synced ?? view.lastSync,
    );
    _views.add(view);
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
      if (_applying || !updates.any((u) => watched.contains(u.table))) return;
      _needsSync = true;
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 2), () => unawaited(sync()));
    });
    // Lost Android TV keystores only require signing in again; local data stays.
    try {
      final saved = await vault.read();
      if (_disposed) return;
      if (saved != null) {
        _session = AccountSession.fromJson(
          jsonDecode(saved) as Map<String, dynamic>,
        );
      }
    } on Object {
      _emit(error: 'SESSION_STORAGE');
    } finally {
      if (!_restored.isCompleted) _restored.complete();
    }
    if (_disposed) return;
    _poll = Timer.periodic(pollInterval, (_) => unawaited(sync()));
    _emit();
    await sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _paused = state != AppLifecycleState.resumed;
    if (!_paused) unawaited(sync(force: true));
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
      await vault.write(jsonEncode(session.toJson()));
      await db.settingsDao.setString(bindingKey, session.uid);
      _session = session;
      _hasRead = false;
      _needsSync = true;
    } on AccountException catch (e) {
      _emit(error: e.code);
      rethrow;
    } on Object {
      _emit(error: 'SESSION_STORAGE');
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
      await vault.write(null);
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
      if (_needsSync && !_disposed && view.error == null) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(seconds: 2), () => unawaited(sync()));
      }
    });
  }

  Future<void> _sync({required bool force}) async {
    _emit(busy: true);
    try {
      var session = _session!;
      if (session.expiresAt.isBefore(
        DateTime.now().add(const Duration(minutes: 2)),
      )) {
        session = await api.refresh(session);
        if (_disposed) return;
        await vault.write(jsonEncode(session.toJson()));
        _session = session;
      }
      final owner = await db.settingsDao.getString(bindingKey);
      if (owner != session.uid) throw const AccountException('OTHER_ACCOUNT');
      final baseline = decodeSyncData(
        await db.settingsDao.getJson(_baselineKey(session.uid)),
      );
      final before = await local.export();
      if (!force &&
          _hasRead &&
          syncChanges(baseline, before).isEmpty &&
          await api.revision(session) == _revision) {
        _needsSync = false;
        _emit(synced: DateTime.now());
        return;
      }
      for (var attempt = 0; attempt < 4; attempt++) {
        final remote = await api.read(session);
        final sent = await local.export();
        final pending = syncChanges(baseline, sent);
        if (baseline.isEmpty) {
          // Account state wins when an already-configured second device joins.
          // Local-only additions merge; old order, credentials and deleted
          // favourites cannot replace choices already saved to the account.
          pending.removeWhere(
            (key, value) =>
                remote.deletedKeys.contains(key) ||
                (remote.data.containsKey(key) && value?['type'] != 'progress'),
          );
        }
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
        String? committedRevision;
        try {
          committedRevision = await api.write(
            session,
            remote,
            syncChanges(remote.data, merged),
          );
        } on AccountException catch (e) {
          if (e.code == 'CONFLICT' && attempt < 3) continue;
          rethrow;
        }
        if (_disposed) return;
        _applying = true;
        Set<int> imports = {};
        try {
          await db.transaction(() async {
            final latest = await local.export();
            final withLateChanges = mergeSyncData(
              merged,
              syncChanges(sent, latest),
            );
            imports = await local.apply(withLateChanges);
            await db.settingsDao.setJson(_baselineKey(session.uid), merged);
          });
          await onPreferences?.call();
        } finally {
          _applying = false;
        }
        onImported?.call(imports);
        _revision = committedRevision;
        _hasRead = true;
        _needsSync = syncChanges(merged, await local.export()).isNotEmpty;
        _emit(synced: DateTime.now());
        return;
      }
    } on AccountException catch (e) {
      _emit(error: e.code);
    } on Object {
      _emit(error: 'SYNC_ERROR');
    }
  }

  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _debounce?.cancel();
    unawaited(_updates?.cancel());
    if (_started) WidgetsBinding.instance.removeObserver(this);
    unawaited(_views.close());
  }
}
