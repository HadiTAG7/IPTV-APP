// Providers shared by the movie and series screens (no code generation).
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../player/ui/play_request.dart';
import '../../player/ui/player_route.dart';
import '../../sources/models.dart';
import 'vod_detail_service.dart';

export 'vod_detail_service.dart' show DetailResult, VodAdapterLoader;

/// The two VOD families.
enum VodKind {
  movie,
  series;

  ContentKind get contentKind => switch (this) {
    movie => ContentKind.movie,
    series => ContentKind.series,
  };

  /// The kind saved in watch progress: movies, or the series' episodes.
  PlayableKind get progressKind => switch (this) {
    movie => PlayableKind.movie,
    series => PlayableKind.episode,
  };
}

/// A movie or series of a source.
typedef VodItemRef = ({int sourceId, String key});

/// Builds adapters for lazy detail fetches; tests swap in fakes.
final vodAdapterLoaderProvider = Provider<VodAdapterLoader>(
  (ref) => ref.watch(sourceRepositoryProvider).adapterForSource,
);

final vodDetailServiceProvider = Provider<VodDetailService>(
  (ref) => VodDetailService(
    db: ref.watch(databaseProvider),
    adapters: ref.watch(vodAdapterLoaderProvider),
    log: ref.watch(ringLogProvider),
  ),
);

/// Opens the player; tests swap in a recorder.
typedef PlayerLauncher = Future<void> Function(
  BuildContext context,
  PlayRequest request,
);

final vodPlayerLauncherProvider = Provider<PlayerLauncher>((ref) => openPlayer);

/// Visible categories of one family of a source, updated after each sync.
final vodCategoriesProvider = StreamProvider.autoDispose
    .family<List<CategoryRow>, (int, ContentKind)>(
      (ref, arg) =>
          ref.watch(catalogDaoProvider).watchCategories(arg.$1, arg.$2),
    );

/// Items of one family in the committed catalog; the generation in the key
/// makes it re-count after a sync.
final vodTotalCountProvider = FutureProvider.autoDispose
    .family<int, (int, ContentKind, int)>(
      (ref, arg) => ref.watch(catalogDaoProvider).totalCount(arg.$1, arg.$2),
    );

/// How many unfinished titles the database is asked for; the list is
/// filtered by kind afterwards.
const _continueScan = 200;

/// Most recent first, at most this many per family.
const kContinueWatchingLimit = 20;

/// Unfinished movies, or series (by their latest episode), newest first.
final continueWatchingProvider = StreamProvider.autoDispose
    .family<List<ContinueWatchingItem>, (int, PlayableKind)>(
      (ref, arg) => ref
          .watch(progressDaoProvider)
          .watchContinueWatching(arg.$1, limit: _continueScan)
          .map(
            (items) => items
                .where((i) => i.kind == arg.$2)
                .take(kContinueWatchingLimit)
                .toList(),
          ),
    );

/// Whether an item is a favourite; updated after every toggle.
final vodFavoriteProvider = StreamProvider.autoDispose
    .family<bool, (int, ContentKind, String)>(
      (ref, arg) => ref
          .watch(favoritesDaoProvider)
          .watchFavorites(arg.$1, arg.$2)
          .map((keys) => keys.contains(arg.$3)),
    );
