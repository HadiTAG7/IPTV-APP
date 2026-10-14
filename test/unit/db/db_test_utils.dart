// Shared helpers for database tests. All data is synthetic.
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/sources/models.dart';

final testEpoch = DateTime.utc(2026, 1, 10, 12);

/// In-memory database with a controllable clock.
AppDatabase openTestDb({FakeClock? clock}) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(
    NativeDatabase.memory(),
    clock: clock ?? FakeClock(testEpoch),
  );
}

Future<int> addSource(
  AppDatabase db, {
  String name = 'Test source',
  SourceKind kind = SourceKind.m3uUrl,
  String url = 'http://127.0.0.1:8080/playlist.m3u',
}) => db.sourcesDao.create(SourceConfig(kind: kind, url: url, name: name));

ChannelData channel(
  String key, {
  String? name,
  int? num,
  List<String> categories = const ['news'],
  String? tvgId,
}) => ChannelData(
  key: key,
  name: name ?? 'Channel $key',
  num: num,
  url: 'http://127.0.0.1:8080/live/$key.ts',
  categoryKeys: categories,
  tvgId: tvgId,
);

MovieData movie(
  String key, {
  String? name,
  List<String> categories = const ['films'],
}) => MovieData(
  key: key,
  name: name ?? 'Movie $key',
  ext: 'mkv',
  categoryKeys: categories,
);

SeriesData series(
  String key, {
  String? name,
  List<String> categories = const ['shows'],
}) =>
    SeriesData(key: key, name: name ?? 'Series $key', categoryKeys: categories);

EpisodeData episode(
  String seriesKey,
  String key, {
  int season = 1,
  int number = 1,
  String? title,
}) => EpisodeData(
  seriesKey: seriesKey,
  key: key,
  season: season,
  number: number,
  title: title ?? 'Episode $key',
);

CategoryData category(
  ContentKind kind,
  String key, {
  String? name,
  int sortIndex = 0,
}) =>
    CategoryData(kind: kind, key: key, name: name ?? key, sortIndex: sortIndex);

/// Writes one full generation with the given items and commits it.
Future<int> syncCatalog(
  AppDatabase db,
  int sourceId, {
  List<CategoryData> categories = const [],
  List<ChannelData> channels = const [],
  List<MovieData> movies = const [],
  List<SeriesData> seriesList = const [],
  List<EpisodeData> episodes = const [],
}) async {
  final dao = db.catalogDao;
  final gen = await dao.beginGeneration(sourceId);
  await dao.upsertCategories(sourceId, gen, categories);
  await dao.upsertChannels(sourceId, gen, channels);
  await dao.upsertMovies(sourceId, gen, movies);
  await dao.upsertSeries(sourceId, gen, seriesList);
  await dao.upsertEpisodes(sourceId, gen, episodes);
  await dao.commitGeneration(sourceId, gen);
  return gen;
}

/// Raw `category_items` rows of one category, ordered by position.
Future<List<({int generation, int position, String itemKey})>> membership(
  AppDatabase db,
  int sourceId,
  ContentKind kind,
  String categoryKey,
) async {
  final rows =
      await (db.select(db.categoryItems)
            ..where(
              (c) =>
                  c.sourceId.equals(sourceId) &
                  c.kind.equalsValue(kind) &
                  c.categoryKey.equals(categoryKey),
            )
            ..orderBy([
              (c) => OrderingTerm.asc(c.generation),
              (c) => OrderingTerm.asc(c.position),
            ]))
          .get();
  return [
    for (final r in rows)
      (generation: r.generation, position: r.position, itemKey: r.itemKey),
  ];
}

Future<int> countRows(AppDatabase db, String table) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS n FROM $table')
      .getSingle();
  return row.read<int>('n');
}
