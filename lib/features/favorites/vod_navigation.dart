// How Favorites and Search open a movie or a series.
//
// The movie and series detail screens belong to another feature. Screens
// here go through [vodDetailNavigatorProvider], which integration
// overrides to push those detail screens. Until then the default plays a
// movie at once (resuming saved progress) and does nothing for a series.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../player/session/progress_saver.dart';
import '../../player/ui/play_request.dart';
import '../../sources/models.dart';
import '../live/live_actions.dart';

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

/// Opens [target] (a detail screen, or playback). Completes when the user
/// comes back.
typedef VodDetailNavigator = Future<void> Function(
  BuildContext context,
  WidgetRef ref,
  VodTarget target,
);

/// How Favorites and Search open movies and series. Override it at
/// integration to push the detail screens; see [defaultVodDetailNavigator].
final vodDetailNavigatorProvider = Provider<VodDetailNavigator>(
  (ref) => defaultVodDetailNavigator,
);

/// Plays a movie right away, from its saved position when the resume rule
/// applies (`ProgressSaver.shouldOfferResume`); does nothing for a series
/// (it needs the series detail screen).
Future<void> defaultVodDetailNavigator(
  BuildContext context,
  WidgetRef ref,
  VodTarget target,
) async {
  final movie = target.movie;
  if (movie == null) return;
  final progress = await ref
      .read(progressDaoProvider)
      .progressFor(target.sourceId, PlayableKind.movie, movie.key);
  if (!context.mounted) return;
  final resume =
      progress != null &&
          ProgressSaver.shouldOfferResume(progress.position, progress.duration)
      ? progress.position
      : null;
  await ref.read(playerLauncherProvider)(
    context,
    PlayRequest(
      sourceId: target.sourceId,
      item: movie.toPlayable(),
      startAt: resume,
    ),
  );
}
