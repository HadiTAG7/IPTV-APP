// Riverpod providers of the Live, Favorites and Search screens.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../sources/models.dart';

/// Live categories of a source in provider order, hidden ones included
/// (each row says whether it is hidden). Updates after every sync.
final liveCategoriesProvider = StreamProvider.autoDispose
    .family<List<CategoryRow>, int>(
      (ref, sourceId) => ref
          .watch(catalogDaoProvider)
          .watchCategories(sourceId, ContentKind.live, includeHidden: true),
    );

/// Number of live channels of a source, read again when a sync commits
/// (not on every batch a running sync writes).
final liveChannelCountProvider = FutureProvider.autoDispose.family<int, int>((
  ref,
  sourceId,
) {
  ref.watch(sourceGenerationProvider(sourceId));
  return ref.watch(catalogDaoProvider).totalCount(sourceId, ContentKind.live);
});

/// Favourite keys of one kind in favourite order; updates on every change.
final favoriteKeysProvider = StreamProvider.autoDispose
    .family<Set<String>, (int, ContentKind)>(
      (ref, arg) =>
          ref.watch(favoritesDaoProvider).watchFavorites(arg.$1, arg.$2),
    );

/// Recently played channel keys, newest first.
final recentChannelKeysProvider = StreamProvider.autoDispose
    .family<List<String>, int>(
      (ref, sourceId) =>
          ref.watch(recentDaoProvider).watchRecentChannelKeys(sourceId),
    );

/// Committed catalog generation of a source (changes when a sync commits).
final sourceGenerationProvider = Provider.autoDispose.family<int, int>((
  ref,
  sourceId,
) {
  final sources = ref.watch(sourcesProvider).value ?? const <SourceRow>[];
  return sources.where((s) => s.id == sourceId).firstOrNull?.generation ?? 0;
});

/// Settings key of the channel list the Live screen showed last for a
/// source (a `LiveList.id`).
String liveLastListKey(int sourceId) => 'live.lastList.$sourceId';
