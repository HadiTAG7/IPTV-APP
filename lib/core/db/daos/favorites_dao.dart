import 'package:drift/drift.dart';

import '../../../sources/models.dart';
import '../app_db.dart';

/// Favourites per source and kind, keyed by stable item keys so they survive
/// every catalog refresh. Items that vanished show as unavailable.
class FavoritesDao extends DatabaseAccessor<AppDatabase> {
  FavoritesDao(super.attachedDatabase);

  Expression<bool> _match(
    $FavoritesTable f,
    int sourceId,
    ContentKind kind,
    String key,
  ) =>
      f.sourceId.equals(sourceId) &
      f.kind.equalsValue(kind) &
      f.key.equals(key);

  /// Flips the favourite state and returns the new one.
  Future<bool> toggleFavorite(int sourceId, ContentKind kind, String key) =>
      transaction(() async {
        final now = !await isFavorite(sourceId, kind, key);
        await setFavorite(sourceId, kind, key, now);
        return now;
      });

  /// Adds (at the end) or removes a favourite. Adding twice keeps the
  /// original position.
  Future<void> setFavorite(
    int sourceId,
    ContentKind kind,
    String key,
    bool favorite,
  ) async {
    if (!favorite) {
      await (delete(
        db.favorites,
      )..where((f) => _match(f, sourceId, kind, key))).go();
      return;
    }
    await transaction(() async {
      final max = db.favorites.position.max();
      final last =
          await (selectOnly(db.favorites)
                ..addColumns([max])
                ..where(
                  db.favorites.sourceId.equals(sourceId) &
                      db.favorites.kind.equalsValue(kind),
                ))
              .map((r) => r.read(max))
              .getSingle();
      await into(db.favorites).insert(
        FavoritesCompanion.insert(
          sourceId: sourceId,
          kind: kind,
          key: key,
          addedAt: toEpochSec(db.clock.now()),
          position: (last ?? -1) + 1,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  Future<bool> isFavorite(int sourceId, ContentKind kind, String key) async =>
      await (select(
        db.favorites,
      )..where((f) => _match(f, sourceId, kind, key))).getSingleOrNull() !=
      null;

  SimpleSelectStatement<$FavoritesTable, FavoriteRecord> _ordered(
    int sourceId,
    ContentKind kind,
  ) => select(db.favorites)
    ..where((f) => f.sourceId.equals(sourceId) & f.kind.equalsValue(kind))
    ..orderBy([
      (f) => OrderingTerm.asc(f.position),
      (f) => OrderingTerm.asc(f.key),
    ]);

  /// Favourite keys in favourite order (also usable as a zapping list).
  Future<List<String>> favoriteKeys(int sourceId, ContentKind kind) async => [
    for (final r in await _ordered(sourceId, kind).get()) r.key,
  ];

  /// Favourite keys in favourite order; emits after every change.
  Stream<Set<String>> watchFavorites(int sourceId, ContentKind kind) =>
      _ordered(
        sourceId,
        kind,
      ).watch().map((rows) => {for (final r in rows) r.key});

  /// Rewrites positions from the order of [keys].
  Future<void> reorder(int sourceId, ContentKind kind, List<String> keys) =>
      batch((b) {
        for (final (i, key) in keys.indexed) {
          b.update(
            db.favorites,
            FavoritesCompanion(position: Value(i)),
            where: (f) => _match(f, sourceId, kind, key),
          );
        }
      });

  Future<List<FavoriteItem<ChannelRow>>> favoriteChannelsPage(
    int sourceId, {
    int offset = 0,
    int limit = 200,
  }) => _page(
    sourceId,
    ContentKind.live,
    db.channels,
    offset,
    limit,
    (r) => r.toRow(),
  );

  Future<List<FavoriteItem<MovieRow>>> favoriteMoviesPage(
    int sourceId, {
    int offset = 0,
    int limit = 200,
  }) => _page(
    sourceId,
    ContentKind.movie,
    db.movies,
    offset,
    limit,
    (r) => r.toRow(),
  );

  Future<List<FavoriteItem<SeriesRow>>> favoriteSeriesPage(
    int sourceId, {
    int offset = 0,
    int limit = 200,
  }) => _page(
    sourceId,
    ContentKind.series,
    db.series,
    offset,
    limit,
    (r) => r.toRow(),
  );

  Future<List<FavoriteItem<R>>> _page<D, R>(
    int sourceId,
    ContentKind kind,
    TableInfo<Table, D> table,
    int offset,
    int limit,
    R Function(D) toRow,
  ) async {
    if (limit <= 0) return const [];
    final name = table.actualTableName;
    final rows = await customSelect(
      'SELECT f."key" AS fav_key, f.added_at AS fav_added_at, t.* '
      'FROM favorites f LEFT JOIN $name t '
      'ON t.source_id = f.source_id AND t."key" = f."key" '
      'WHERE f.source_id = ?1 AND f.kind = ?2 '
      'ORDER BY f.position, f."key" LIMIT ?3 OFFSET ?4',
      variables: [
        Variable.withInt(sourceId),
        Variable.withString(kind.name),
        Variable.withInt(limit),
        Variable.withInt(offset < 0 ? 0 : offset),
      ],
      readsFrom: {db.favorites, table},
    ).get();
    return [
      for (final r in rows)
        FavoriteItem<R>(
          kind: kind,
          key: r.read<String>('fav_key'),
          addedAt: fromEpochSec(r.read<int>('fav_added_at')),
          item: r.data['source_id'] == null
              ? null
              : toRow(await table.map(r.data)),
        ),
    ];
  }
}
