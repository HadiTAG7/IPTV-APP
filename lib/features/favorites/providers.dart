import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../core/db/queries/live_queries.dart';
import '../../sources/models.dart';
import '../live/providers.dart';

/// Most favourites of one kind a grid shows.
const maxFavoritesShown = 2000;

/// Favourite movies (gone ones as unavailable) with their watch progress.
typedef FavoriteMovies = ({
  List<FavoriteItem<MovieRow>> items,
  Map<String, ProgressRow> progress,
});

/// Favourite movies of a source; reloads when the favourites change.
final favoriteMoviesProvider = FutureProvider.autoDispose
    .family<FavoriteMovies, int>((ref, sourceId) async {
      ref.watch(favoriteKeysProvider((sourceId, ContentKind.movie)));
      final db = ref.watch(databaseProvider);
      final items = await db.favoritesDao.favoriteMoviesPage(
        sourceId,
        limit: maxFavoritesShown,
      );
      final progress = await db.progressForKeys(sourceId, PlayableKind.movie, [
        for (final i in items)
          if (i.available) i.key,
      ]);
      return (items: items, progress: progress);
    });

/// Favourite series of a source; reloads when the favourites change.
final favoriteSeriesProvider = FutureProvider.autoDispose
    .family<List<FavoriteItem<SeriesRow>>, int>((ref, sourceId) {
      ref.watch(favoriteKeysProvider((sourceId, ContentKind.series)));
      return ref
          .watch(favoritesDaoProvider)
          .favoriteSeriesPage(sourceId, limit: maxFavoritesShown);
    });
