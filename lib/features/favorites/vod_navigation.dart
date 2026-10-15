// How Favorites and Search open a movie or a series: through
// [vodDetailNavigatorProvider], which pushes the movie and series detail
// pages (tests replace it to record what was opened).
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_db.dart';
import '../../sources/models.dart';
import '../vod_common/vod_navigation.dart';

/// A movie or series to open.
@immutable
class VodTarget {
  const VodTarget.movie({required this.sourceId, required MovieRow this.movie})
    : series = null;

  const VodTarget.series({
    required this.sourceId,
    required SeriesRow this.series,
  }) : movie = null;

  final int sourceId;

  /// Set for a movie.
  final MovieRow? movie;

  /// Set for a series.
  final SeriesRow? series;

  ContentKind get kind =>
      movie != null ? ContentKind.movie : ContentKind.series;

  String get key => movie?.key ?? series!.key;

  String get title => movie?.name ?? series!.name;

  @override
  String toString() => 'VodTarget(${kind.name} $key)';
}

/// Opens [target]'s detail page. Completes when the user comes back.
typedef VodDetailNavigator = Future<void> Function(
  BuildContext context,
  WidgetRef ref,
  VodTarget target,
);

/// How Favorites and Search open movies and series: the detail pages
/// ([defaultVodDetailNavigator]).
final vodDetailNavigatorProvider = Provider<VodDetailNavigator>(
  (ref) => defaultVodDetailNavigator,
);

/// Pushes the movie detail page ([openMovieDetail]) or the series detail
/// page with its seasons and episodes ([openSeriesDetail]), the same pages
/// the Movies and Series grids open. Resume and playback start there.
Future<void> defaultVodDetailNavigator(
  BuildContext context,
  WidgetRef ref,
  VodTarget target,
) => switch (target.kind) {
  ContentKind.series => openSeriesDetail(context, target.sourceId, target.key),
  _ => openMovieDetail(context, target.sourceId, target.key),
};
