// Queries used by the Settings screen that the shared DAOs do not offer.
import 'package:drift/drift.dart';

import '../../../sources/models.dart';
import '../app_db.dart';

/// Settings-screen writes on [AppDatabase].
extension SettingsHelpQueries on AppDatabase {
  /// Stores the guide time offset of one source (minutes, may be negative).
  /// Unknown ids are a no-op.
  ///
  /// Offsets are applied at import, so the source's guides also forget their
  /// validators and import time: every later refresh downloads them in full,
  /// even when the forced refresh that should follow fails.
  Future<void> setSourceEpgOffset(int sourceId, int minutes) =>
      transaction(() async {
        await (update(sources)..where((s) => s.id.equals(sourceId))).write(
          SourcesCompanion(epgOffsetMin: Value(minutes)),
        );
        await epgDao.forgetGuideVersions(sourceId);
      });

  /// Adds a guide URL typed by the user for [sourceId] after the existing
  /// ones (automatic guides keep their priority; manual ones are tried after
  /// them in the order they were added). Returns the guide source id, or the
  /// id of an existing entry with the same (masked) URL.
  Future<int> addManualEpgSource(int sourceId, String url) async {
    final max = epgSources.priority.max();
    final last =
        await (selectOnly(epgSources)
              ..addColumns([max])
              ..where(epgSources.sourceId.equals(sourceId)))
            .map((r) => r.read(max))
            .getSingle();
    return epgDao.addEpgSource(
      sourceId,
      url,
      EpgOrigin.manual,
      priority: (last ?? -1) + 1,
    );
  }
}
