import 'package:drift/drift.dart';

import '../db/app_db.dart';
import '../net/redact.dart';

/// Credentials per source (Xtream password, tokenised playlist and guide
/// URLs).
///
/// Backed by the app-private database rather than the Android Keystore,
/// which silently wipes data on many TV boxes. This relies on the manifest's
/// `android:allowBackup="false"` keeping the database out of device
/// backups. Values must never be logged; pass them to `redact` as secrets.
abstract interface class SecretStore {
  Future<String?> read(int sourceId, String name);
  Future<void> write(int sourceId, String name, String value);
  Future<void> delete(int sourceId, String name);
  Future<void> deleteAll(int sourceId);
}

/// Secret names used by the app.
abstract final class SecretNames {
  /// Xtream password.
  static const password = 'password';

  /// Full playlist URL when it embeds credentials.
  static const url = 'url';

  /// Full URL of guide source [epgSourceId] when it embeds credentials.
  static String epgUrl(int epgSourceId) => 'epgUrl:$epgSourceId';
}

/// Whether [url] carries credentials that `redact` masks (query
/// `username`/`password`/`token`..., `user:pass@`, Xtream path segments).
bool urlHasCredentials(String url) => redact(url) != url;

/// [SecretStore] on the `secrets` table. Rows go away with their source.
///
/// Calls made inside a transaction of the same database join it.
class DbSecretStore implements SecretStore {
  DbSecretStore(this._db);

  final AppDatabase _db;

  @override
  Future<String?> read(int sourceId, String name) async {
    final row =
        await (_db.select(_db.secrets)
              ..where((s) => s.sourceId.equals(sourceId) & s.name.equals(name)))
            .getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> write(int sourceId, String name, String value) => _db
      .into(_db.secrets)
      .insertOnConflictUpdate(
        SecretsCompanion.insert(sourceId: sourceId, name: name, value: value),
      );

  @override
  Future<void> delete(int sourceId, String name) => (_db.delete(
    _db.secrets,
  )..where((s) => s.sourceId.equals(sourceId) & s.name.equals(name))).go();

  @override
  Future<void> deleteAll(int sourceId) =>
      (_db.delete(_db.secrets)..where((s) => s.sourceId.equals(sourceId))).go();
}

/// Volatile [SecretStore] for tests and previews.
class InMemorySecretStore implements SecretStore {
  final _values = <(int, String), String>{};

  @override
  Future<String?> read(int sourceId, String name) async =>
      _values[(sourceId, name)];

  @override
  Future<void> write(int sourceId, String name, String value) async =>
      _values[(sourceId, name)] = value;

  @override
  Future<void> delete(int sourceId, String name) async =>
      _values.remove((sourceId, name));

  @override
  Future<void> deleteAll(int sourceId) async =>
      _values.removeWhere((k, _) => k.$1 == sourceId);
}
