// Movie detail providers (no code generation).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../sources/models.dart';
import '../vod_common/vod_providers.dart';

/// The catalog row of a movie, or null when it is no longer in the source.
final movieRowProvider = FutureProvider.autoDispose
    .family<MovieRow?, VodItemRef>(
      (ref, r) => ref.watch(catalogDaoProvider).movieByKey(r.sourceId, r.key),
    );

/// Lazily fetched details (plot, cast, genre, runtime, backdrop); never
/// fails, see [DetailResult].
final movieDetailProvider = FutureProvider.autoDispose
    .family<DetailResult<MovieDetail>, VodItemRef>(
      (ref, r) =>
          ref.watch(vodDetailServiceProvider).movieDetail(r.sourceId, r.key),
    );

/// Saved progress of a movie; updated while the player saves.
final movieProgressProvider = StreamProvider.autoDispose
    .family<ProgressRow?, VodItemRef>(
      (ref, r) => ref
          .watch(progressDaoProvider)
          .watchProgressFor(r.sourceId, PlayableKind.movie, r.key),
    );
