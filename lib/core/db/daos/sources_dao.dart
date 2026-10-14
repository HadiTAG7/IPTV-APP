import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../player/engine/player_engine.dart';
import '../../../sources/models.dart';
import '../../secure/secret_store.dart';
import '../app_db.dart';

/// Saved sources, their account state and the active-source setting.
///
/// Passwords are not stored here; use a `SecretStore`.
class SourcesDao extends DatabaseAccessor<AppDatabase> {
  SourcesDao(super.attachedDatabase);

  SimpleSelectStatement<$SourcesTable, SourceRecord> get _ordered =>
      select(db.sources)..orderBy([
        (s) => OrderingTerm.asc(s.sortIndex),
        (s) => OrderingTerm.asc(s.id),
      ]);

  /// Adds a source at the end of the list and returns its id.
  /// [SourceConfig.password] is ignored.
  Future<int> create(SourceConfig config) => transaction(() async {
    final max = db.sources.sortIndex.max();
    final last = await (selectOnly(
      db.sources,
    )..addColumns([max])).map((r) => r.read(max)).getSingle();
    return into(db.sources).insert(
      SourcesCompanion.insert(
        name: config.name,
        kind: config.kind,
        url: config.url,
        username: Value(config.username),
        userAgent: Value(config.userAgent),
        referer: Value(config.referer),
        liveFormat: Value(config.liveFormat),
        epgOffsetMin: Value(config.epgOffsetMin),
        sortIndex: Value((last ?? -1) + 1),
      ),
    );
  });

  /// Writes the editable fields of [config] ([SourceConfig.password] is
  /// ignored).
  Future<void> updateConfig(int id, SourceConfig config) => _write(
    id,
    SourcesCompanion(
      name: Value(config.name),
      kind: Value(config.kind),
      url: Value(config.url),
      username: Value(config.username),
      userAgent: Value(config.userAgent),
      referer: Value(config.referer),
      liveFormat: Value(config.liveFormat),
      epgOffsetMin: Value(config.epgOffsetMin),
    ),
  );

  /// Deletes the source with its catalog, guide, secrets and user data.
  Future<void> deleteSource(int id) => transaction(() async {
    await (delete(db.sources)..where((s) => s.id.equals(id))).go();
    if (await activeSourceId() == id) await setActive(null);
  });

  Future<SourceRow?> byId(int id) async => (await (select(
    db.sources,
  )..where((s) => s.id.equals(id))).getSingleOrNull())?.toRow();

  Future<List<SourceRow>> all() async => [
    for (final r in await _ordered.get()) r.toRow(),
  ];

  Stream<List<SourceRow>> watchAll() =>
      _ordered.watch().map((rows) => [for (final r in rows) r.toRow()]);

  /// Sets `sortIndex` from the order of [ids].
  Future<void> reorder(List<int> ids) => batch((b) {
    for (final (i, id) in ids.indexed) {
      b.update(
        db.sources,
        SourcesCompanion(sortIndex: Value(i)),
        where: (s) => s.id.equals(id),
      );
    }
  });

  /// Stores the active source in the `activeSourceId` setting; null clears.
  Future<void> setActive(int? id) async {
    if (id != null && await byId(id) == null) {
      throw StateError('Unknown source $id');
    }
    await db.settingsDao.setInt(SettingKeys.activeSourceId, id);
  }

  Future<int?> activeSourceId() =>
      db.settingsDao.getInt(SettingKeys.activeSourceId);

  Stream<int?> watchActiveSourceId() =>
      db.settingsDao.watchInt(SettingKeys.activeSourceId);

  /// The active source, falling back to the first one.
  Future<SourceRow?> activeSource() async {
    final id = await activeSourceId();
    final active = id == null ? null : await byId(id);
    if (active != null) return active;
    final first = await (_ordered..limit(1)).getSingleOrNull();
    return first?.toRow();
  }

  /// Committed catalog generation (0 = never synced).
  Future<int> generationOf(int id) => db.catalogDao.committedGeneration(id);

  /// Stores what `SourceAdapter.verify` reported.
  Future<void> updateAccount(int id, AccountInfo info) => _write(
    id,
    SourcesCompanion(
      accountStatus: Value(info.status),
      expiresAt: Value(
        info.expiresAt == null ? null : toEpochSec(info.expiresAt!),
      ),
      maxConnections: Value(info.maxConnections),
      allowedFormatsJson: Value(jsonEncode(info.allowedFormats)),
    ),
  );

  /// Per-source engine overrides; null means "use the policy default".
  Future<void> setEngines(
    int id, {
    required EngineKind? live,
    required EngineKind? vod,
  }) => _write(
    id,
    SourcesCompanion(engineLive: Value(live), engineVod: Value(vod)),
  );

  Future<void> markSynced(int id, [DateTime? at]) => _write(
    id,
    SourcesCompanion(lastSyncAt: Value(toEpochSec(at ?? db.clock.now()))),
  );

  Future<void> markEpgFetched(int id, [DateTime? at]) => _write(
    id,
    SourcesCompanion(lastEpgAt: Value(toEpochSec(at ?? db.clock.now()))),
  );

  /// Full adapter configuration including the password from [secrets].
  Future<SourceConfig?> configFor(int id, SecretStore secrets) async {
    final row = await byId(id);
    if (row == null) return null;
    return row.toConfig(password: await secrets.read(id, SecretNames.password));
  }

  Future<void> _write(int id, SourcesCompanion values) =>
      (update(db.sources)..where((s) => s.id.equals(id))).write(values);
}
