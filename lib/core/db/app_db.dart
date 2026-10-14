import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../player/engine/player_engine.dart';
import '../../sources/models.dart';
import '../time/clock.dart';
import 'daos/catalog_dao.dart';
import 'daos/detail_cache_dao.dart';
import 'daos/epg_dao.dart';
import 'daos/favorites_dao.dart';
import 'daos/prefs_dao.dart';
import 'daos/progress_dao.dart';
import 'daos/recent_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/sources_dao.dart';
import 'tables.dart';

export 'daos/catalog_dao.dart';
export 'daos/detail_cache_dao.dart';
export 'daos/epg_dao.dart';
export 'daos/favorites_dao.dart';
export 'daos/prefs_dao.dart';
export 'daos/progress_dao.dart';
export 'daos/recent_dao.dart';
export 'daos/settings_dao.dart';
export 'daos/sources_dao.dart';
export 'mappers.dart';
export 'tables.dart' show EpgMatchKind;

part 'app_db.g.dart';

/// The app database (schema v1).
///
/// Schema changes: bump [schemaVersion], run
/// `dart run drift_dev make-migrations`, write the step in [migration] and
/// commit the new `drift_schemas/` snapshot plus the generated tests.
@DriftDatabase(
  tables: [
    Sources,
    Secrets,
    Categories,
    CategoryItems,
    Channels,
    Movies,
    Series,
    Episodes,
    DetailCache,
    EpgSources,
    EpgChannels,
    Programmes,
    ChannelEpgMap,
    ChannelPrefs,
    Favorites,
    WatchProgress,
    RecentChannels,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e, {this.clock = const SystemClock()});

  /// Opens `iptv.sqlite` in the app-support directory, shared by every
  /// isolate (UI and sync) through one background connection.
  static AppDatabase open() => AppDatabase(
    driftDatabase(
      name: 'iptv',
      native: const DriftNativeOptions(
        shareAcrossIsolates: true,
        databaseDirectory: getApplicationSupportDirectory,
      ),
    ),
  );

  /// Time source for `addedAt`, `updatedAt` and cache stamps.
  final Clock clock;

  late final sourcesDao = SourcesDao(this);
  late final catalogDao = CatalogDao(this);
  late final favoritesDao = FavoritesDao(this);
  late final progressDao = ProgressDao(this);
  late final recentDao = RecentDao(this);
  late final settingsDao = SettingsDao(this);
  late final prefsDao = PrefsDao(this);
  late final detailCacheDao = DetailCacheDao(this);
  late final epgDao = EpgDao(this);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (details) async {
      if (!kIsWeb) {
        try {
          await customStatement('PRAGMA journal_mode = WAL');
          await customStatement('PRAGMA synchronous = NORMAL');
        } on Object catch (_) {
          // Not fatal: some file systems refuse WAL.
        }
      }
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
