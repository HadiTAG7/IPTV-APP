import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../core/db/queries/guide_queries.dart';
import '../../player/ui/play_request.dart';
import '../../player/ui/player_route.dart';
import '../../sources/models.dart';
import '../live/live_models.dart';
import 'guide_data.dart';

/// Opens the player (tests record the request instead).
typedef GuidePlayer = Future<void> Function(
  BuildContext context,
  PlayRequest request,
);

/// How the guide starts playback: [openPlayer].
final guidePlayerProvider = Provider<GuidePlayer>((ref) => openPlayer);

/// The filter the user picked in the guide, per source; null until they
/// pick one (the guide then shows favourites when there are any, else all
/// channels).
final guideFilterProvider =
    NotifierProvider.family<GuideFilterController, GuideFilter?, int>(
      GuideFilterController.new,
    );

class GuideFilterController extends Notifier<GuideFilter?> {
  GuideFilterController(this.sourceId);

  final int sourceId;

  @override
  GuideFilter? build() => null;

  void select(GuideFilter filter) => state = filter;
}

/// Visible live categories of a source.
final guideCategoriesProvider = StreamProvider.autoDispose
    .family<List<CategoryRow>, int>(
      (ref, sourceId) => ref
          .watch(catalogDaoProvider)
          .watchCategories(sourceId, ContentKind.live),
    );

/// Favourite channel keys of a source in favourite order, without the
/// channels that are not in the catalog (any more): what the guide lists
/// and zaps through for [GuideFilter.favorites].
final guideFavoriteKeysProvider = StreamProvider.autoDispose
    .family<List<String>, int>(
      (ref, sourceId) => ref
          .watch(databaseProvider)
          .watchAvailableFavoriteChannelKeys(sourceId),
    );

/// Whether the source has any guide data to show.
final guideHasDataProvider = StreamProvider.autoDispose.family<bool, int>(
  (ref, sourceId) => ref.watch(databaseProvider).watchHasGuideData(sourceId),
);

/// The filter in effect: the picked one while it still has channels to
/// show (a category that still exists, favourites while there are any),
/// else favourites when there are any, else all channels.
GuideFilter effectiveGuideFilter(
  GuideFilter? picked,
  List<String> favoriteKeys,
  List<CategoryRow>? categories,
) {
  final fallback = favoriteKeys.isEmpty
      ? GuideFilter.all
      : GuideFilter.favorites;
  if (picked == null) return fallback;
  final gone = switch (picked.kind) {
    GuideFilterKind.favorites => favoriteKeys.isEmpty,
    GuideFilterKind.category =>
      categories != null && !categories.any((c) => c.key == picked.categoryKey),
    GuideFilterKind.all => false,
  };
  return gone ? fallback : picked;
}

/// What the player zaps through when started from the guide with [filter]:
/// the same channels in the same order. For favourites, [favoriteKeys] is
/// the whole list ([guideFavoriteKeysProvider]), not just the rows loaded.
PlayRequest guidePlayRequest({
  required int sourceId,
  required ChannelRow channel,
  required GuideFilter filter,
  List<String> favoriteKeys = const [],
}) => PlayRequest(
  sourceId: sourceId,
  item: channel.toPlayable(),
  title: channel.name,
  categoryKey: filter.kind == GuideFilterKind.category
      ? filter.categoryKey
      : null,
  zapKeys: filter.kind == GuideFilterKind.favorites
      ? List.unmodifiable(favoriteKeys)
      : null,
  list: switch (filter.kind) {
    GuideFilterKind.favorites => const LiveList.favorites(),
    GuideFilterKind.category => LiveList.category(filter.categoryKey!),
    GuideFilterKind.all => const LiveList.all(),
  },
);
