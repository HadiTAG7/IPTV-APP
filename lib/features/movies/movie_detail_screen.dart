import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../player/session/progress_saver.dart';
import '../../player/ui/play_request.dart';
import '../../sources/models.dart';
import '../../theme/tokens.dart';
import '../../tv/focus_watchdog.dart';
import '../../widgets/bidi_text.dart';
import '../../widgets/states.dart';
import '../vod_common/vod_format.dart';
import '../vod_common/vod_providers.dart';
import '../vod_common/vod_widgets.dart';
import 'providers.dart';

/// A movie: poster, backdrop, title, year, rating, genre, runtime and plot,
/// with Play, Resume from m:ss / Start over (when there is progress) and a
/// favourite toggle.
///
/// The catalog row shows at once; details are fetched lazily (Xtream
/// `get_vod_info`, cached for 24 h) and a failure only adds a short note.
/// The primary button has focus when the page opens. Pushed as a route
/// (`openMovieDetail`); Back closes it.
class MovieDetailScreen extends ConsumerStatefulWidget {
  const MovieDetailScreen({
    super.key,
    required this.sourceId,
    required this.movieKey,
  });

  final int sourceId;
  final String movieKey;

  @override
  ConsumerState<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends ConsumerState<MovieDetailScreen> {
  final _primary = FocusNode(debugLabel: 'movie-primary');
  FocusWatchdogState? _watchdog;

  VodItemRef get _ref => (sourceId: widget.sourceId, key: widget.movieKey);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final watchdog = FocusWatchdog.maybeOf(context);
    if (watchdog != _watchdog) {
      _watchdog?.unregister(_primary);
      _watchdog = watchdog?..register(_primary);
    }
  }

  @override
  void dispose() {
    _watchdog?.unregister(_primary);
    _primary.dispose();
    super.dispose();
  }

  void _play(MovieRow movie, MovieDetail? detail, Duration? startAt) {
    final request = PlayRequest(
      sourceId: widget.sourceId,
      item: PlayableRef(
        kind: PlayableKind.movie,
        key: movie.key,
        url: movie.url,
        ext: movie.ext ?? detail?.ext,
        headers: movie.headers,
        title: movie.name,
      ),
      startAt: startAt,
      title: movie.name,
    );
    unawaited(ref.read(vodPlayerLauncherProvider)(context, request));
  }

  Future<void> _toggleFavorite() => ref
      .read(favoritesDaoProvider)
      .toggleFavorite(widget.sourceId, ContentKind.movie, widget.movieKey);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rowAsync = ref.watch(movieRowProvider(_ref));
    final progressAsync = ref.watch(movieProgressProvider(_ref));
    final detailAsync = ref.watch(movieDetailProvider(_ref));
    final favorite =
        ref
            .watch(
              vodFavoriteProvider((
                widget.sourceId,
                ContentKind.movie,
                widget.movieKey,
              )),
            )
            .value ??
        false;

    if (!rowAsync.hasValue || !progressAsync.hasValue) {
      return VodDetailFrame(
        title: '',
        child: rowAsync.hasError
            ? ErrorView(onRetry: () => ref.invalidate(movieRowProvider(_ref)))
            : const LoadingView(),
      );
    }
    final movie = rowAsync.value;
    if (movie == null) {
      return VodDetailFrame(
        title: '',
        child: EmptyView(
          message: l10n.commonUnavailable,
          icon: Icons.movie_outlined,
        ),
      );
    }
    final result = detailAsync.value;
    final detail = result?.value;
    final progress = progressAsync.value;
    final resumeAt =
        progress != null &&
            ProgressSaver.shouldOfferResume(
              progress.position,
              progress.duration,
            )
        ? progress.position
        : null;

    final buttons = <Widget>[
      VodActionButton(
        key: const ValueKey('vod-play'),
        focusNode: _primary,
        autofocus: true,
        primary: true,
        icon: Icons.play_arrow_rounded,
        label: resumeAt == null
            ? l10n.vodPlay
            : l10n.vodResumeFrom(formatPlayPosition(resumeAt)),
        onSelect: () => _play(movie, detail, resumeAt),
      ),
      if (resumeAt != null)
        VodActionButton(
          key: const ValueKey('vod-start-over'),
          icon: Icons.replay_rounded,
          label: l10n.vodStartOver,
          onSelect: () => _play(movie, detail, Duration.zero),
        ),
      VodActionButton(
        key: const ValueKey('vod-favorite'),
        icon: favorite ? Icons.star_rounded : Icons.star_outline_rounded,
        label: favorite ? l10n.vodRemoveFavorite : l10n.vodAddFavorite,
        onSelect: () => unawaited(_toggleFavorite()),
      ),
    ];

    final info = _MovieInfo(
      movie: movie,
      detail: detail,
      detailLoading: detailAsync.isLoading && detail == null,
      detailFailed: result?.failed ?? false,
      progress: resumeAt == null ? null : progress,
      buttons: buttons,
    );
    return VodDetailFrame(
      title: movie.name,
      backdrop: detail?.backdrop,
      child: isLargeLayout(context) ? info.large(context) : info.phone(context),
    );
  }
}

class _MovieInfo {
  const _MovieInfo({
    required this.movie,
    required this.detail,
    required this.detailLoading,
    required this.detailFailed,
    required this.progress,
    required this.buttons,
  });

  final MovieRow movie;
  final MovieDetail? detail;
  final bool detailLoading;
  final bool detailFailed;

  /// Shown as a bar under the poster when resumable.
  final ProgressRow? progress;
  final List<Widget> buttons;

  Widget _title(BuildContext context) => BidiText(
    movie.name,
    maxLines: 2,
    style: Theme.of(context).textTheme.headlineSmall,
  );

  Widget _meta() => VodMetaLine(
    year: releaseYear(movie.year, detail?.releaseDate),
    rating: detail?.rating ?? movie.rating,
    genre: detail?.genre,
    runtimeSec: detail?.durationSec,
  );

  Widget _buttons() =>
      Wrap(spacing: Spacing.md, runSpacing: Spacing.md, children: buttons);

  Widget _poster(double width) {
    final progress = this.progress;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        VodPoster(url: movie.poster, width: width),
        if (progress != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: Spacing.sm),
            child: SizedBox(
              width: width,
              child: ProgressLine(value: progress.fraction, height: 4),
            ),
          ),
      ],
    );
  }

  /// Plot, credits and the loading or failure note.
  List<Widget> _texts(BuildContext context, {int? plotLines}) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final plot = detail?.plot?.trim();
    final cast = detail?.cast?.trim();
    final director = detail?.director?.trim();
    final secondary = theme.bodyMedium?.copyWith(
      color: AppColors.textSecondary,
    );
    return [
      if (plot != null && plot.isNotEmpty)
        BidiText(
          plot,
          key: const ValueKey('vod-plot'),
          maxLines: plotLines,
          // Without a line limit an ellipsis would cut the text to one line.
          overflow: plotLines == null
              ? TextOverflow.visible
              : TextOverflow.ellipsis,
          style: theme.bodyLarge,
        ),
      if (director != null && director.isNotEmpty)
        Padding(
          padding: const EdgeInsetsDirectional.only(top: Spacing.sm),
          child: Text(l10n.vod_director(director), style: secondary),
        ),
      if (cast != null && cast.isNotEmpty)
        Padding(
          padding: const EdgeInsetsDirectional.only(top: Spacing.xs),
          child: Text(
            l10n.vod_cast(cast),
            maxLines: plotLines == null ? null : 2,
            overflow: plotLines == null ? null : TextOverflow.ellipsis,
            style: secondary,
          ),
        ),
      if (detailLoading)
        const Padding(
          padding: EdgeInsetsDirectional.only(top: Spacing.sm),
          child: SizedBox(
            width: double.infinity,
            child: LinearProgressIndicator(minHeight: 2),
          ),
        )
      else if (detailFailed)
        Padding(
          padding: const EdgeInsetsDirectional.only(top: Spacing.sm),
          child: Text(
            l10n.vod_detailsFailed,
            key: const ValueKey('vod-details-failed'),
            style: theme.bodySmall,
          ),
        ),
    ];
  }

  Widget large(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _poster(180),
        const SizedBox(width: Spacing.xl),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title(context),
              const SizedBox(height: Spacing.sm),
              _meta(),
              const SizedBox(height: Spacing.lg),
              _buttons(),
              const SizedBox(height: Spacing.lg),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // The remote cannot scroll text: fit the plot to the
                    // room left (bodyLarge is 16 px at 1.45).
                    final lines = (constraints.maxHeight / 23.2 - 3)
                        .floor()
                        .clamp(2, 40);
                    return SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _texts(context, plotLines: lines),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget phone(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _poster(120),
            const SizedBox(width: Spacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _title(context),
                  const SizedBox(height: Spacing.sm),
                  _meta(),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        _buttons(),
        const SizedBox(height: Spacing.lg),
        ..._texts(context),
      ],
    );
  }
}
