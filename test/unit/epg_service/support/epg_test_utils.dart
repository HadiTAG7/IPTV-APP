// Helpers shared by the EpgService tests. All data is synthetic.
import 'package:drift/drift.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/epg/epg_progress.dart';
import 'package:iptv_player/epg/epg_service.dart';
import 'package:iptv_player/sources/models.dart';

/// Runs a refresh to its end and returns every event.
Future<List<EpgProgress>> runRefresh(
  EpgService service,
  int sourceId, {
  bool force = false,
  bool lite = false,
}) => service.refresh(sourceId, force: force, lite: lite).toList();

T lastOf<T>(List<EpgProgress> events) => events.whereType<T>().last;

/// Stored programmes of one guide, ordered by channel and start.
Future<List<ProgrammeRecord>> storedProgrammes(
  AppDatabase db,
  int epgSourceId,
) =>
    (db.select(db.programmes)
          ..where((p) => p.epgSourceId.equals(epgSourceId))
          ..orderBy([
            (p) => OrderingTerm.asc(p.xmltvId),
            (p) => OrderingTerm.asc(p.startUtc),
          ]))
        .get();

/// Guide channel ids that have stored programmes.
Future<Set<String>> storedIds(AppDatabase db, int epgSourceId) async => {
  for (final p in await storedProgrammes(db, epgSourceId)) p.xmltvId,
};

Future<int> guideChannelCount(AppDatabase db, int epgSourceId) async =>
    (await db.epgDao.epgChannels(epgSourceId)).length;

Future<EpgSourceRow> guideRow(AppDatabase db, int epgSourceId) async =>
    (await db.epgDao.epgSourceById(epgSourceId))!;

/// Commits a new catalog generation holding exactly [channels].
Future<void> syncChannels(
  AppDatabase db,
  int sourceId,
  List<ChannelData> channels,
) async {
  final dao = db.catalogDao;
  final gen = await dao.beginGeneration(sourceId);
  await dao.upsertCategories(sourceId, gen, const [
    CategoryData(kind: ContentKind.live, key: 'all', name: 'All'),
  ]);
  await dao.upsertChannels(sourceId, gen, channels);
  await dao.commitGeneration(sourceId, gen);
}

DateTime fromSec(int s) =>
    DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);
