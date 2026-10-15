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
import '../../tv/key_repeat.dart';
import '../../tv/pane_scope.dart';
import '../../tv/tv_focusable.dart';
import '../../widgets/bidi_text.dart';
import '../../widgets/states.dart';
import '../vod_common/vod_format.dart';
import '../vod_common/vod_providers.dart';
import '../vod_common/vod_widgets.dart';
import 'providers.dart';

/// A series: cover, plot, genre and rating, a Play / Resume button for the
/// episode to watch next, a favourite toggle, and the Seasons and Episodes
/// panes with progress bars.
///
/// * Episodes come from the database: the playlist import (M3U) or a lazy
///   `get_series_info` fetch (Xtream), which stores them and caches the
///   header for 24 h. Stored episodes show while a fetch runs; a failed
///   fetch only adds a short note.
/// * Large layout: header on top, Seasons pane on the start side and the
///   Episodes pane next to it. Arrows cross between panes (mirrored in RTL);
///   up from a pane's top reaches the header buttons. Focusing a season
///   shows its episodes. Phone: one scrolling page with season chips.
/// * The selected season is remembered per series ([saveLastSeason]); else
///   the page opens on the season of the last watched episode.
/// * OK on an episode plays it, resuming past 30 s of progress; Menu (long
///   press) offers Start over.
class SeriesDetailScreen extends ConsumerStatefulWidget {
  const SeriesDetailScreen({
    super.key,
    required this.sourceId,
    required this.seriesKey,
  });

  final int sourceId;
  final String seriesKey;

  @override
  ConsumerState<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

/// What the primary button plays.
typedef _NextUp = ({EpisodeRow episode, Duration? resumeAt});

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen> {
  final _primary = FocusNode(debugLabel: 'series-primary');
  final _headerPane = GlobalKey<PaneScopeState>();
  final _seasonsPane = GlobalKey<PaneScopeState>();
  final _episodesPane = GlobalKey<PaneScopeState>();
  final _seasonNodes = <int, FocusNode>{};
  FocusWatchdogState? _watchdog;

  /// The season picked on this page (null: the remembered or default one).
  int? _season;
  int? _storedSeason;
  bool _storedLoaded = false;

  VodItemRef get _ref => (sourceId: widget.sourceId, key: widget.seriesKey);

  @override
  void initState() {
    super.initState();
    unawaited(_loadStoredSeason());
  }

  Future<void> _loadStoredSeason() async {
    int? season;
    try {
      season = await loadLastSeason(
        ref.read(settingsDaoProvider),
        widget.sourceId,
        widget.seriesKey,
      );
    } on Object {
      season = null;
    }
    if (!mounted) return;
    setState(() {
      _storedSeason = season;
      _storedLoaded = true;
    });
  }

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
    for (final node in _seasonNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _seasonNode(int season) => _seasonNodes.putIfAbsent(
    season,
    () => FocusNode(debugLabel: 'season-$season'),
  );

  void _selectSeason(int season, int current) {
    if (season == current) return;
    setState(() => _season = season);
    unawaited(_remember(season));
  }

  Future<void> _remember(int season) async {
    try {
      await saveLastSeason(
        ref.read(settingsDaoProvider),
        widget.sourceId,
        widget.seriesKey,
        season,
      );
    } on Object {
      // Remembering the season is a convenience only.
    }
  }

  void _focusHeader() => _headerPane.currentState?.requestFocus();

  void _focusSeasons(int season) {
    final node = _seasonNodes[season];
    if (node != null && node.context != null && node.canRequestFocus) {
      node.requestFocus();
    } else {
      _seasonsPane.currentState?.requestFocus();
    }
  }

  void _enterEpisodes() {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted) return;
        final entered = _episodesPane.currentState?.requestFocus() ?? false;
        if (!entered) _seasonsPane.currentState?.requestFocus();
      })
      ..ensureVisualUpdate();
  }

  void _play(SeriesRow series, EpisodeRow episode, Duration? startAt) {
    final l10n = AppLocalizations.of(context);
    final name = episode.title?.trim();
    final title = name == null || name.isEmpty
        ? '${series.name} · ${l10n.vodEpisodeN(episode.number)}'
        : name;
    final request = PlayRequest(
      sourceId: widget.sourceId,
      item: PlayableRef(
        kind: PlayableKind.episode,
        key: episode.key,
        url: episode.url,
        ext: episode.ext,
        headers: episode.headers,
        title: title,
      ),
      seriesKey: series.key,
      startAt: startAt,
      title: title,
    );
    unawaited(ref.read(vodPlayerLauncherProvider)(context, request));
    // The next visit opens on this season; this one stays where it is.
    unawaited(_remember(episode.season));
  }

  Future<void> _episodeOptions(
    SeriesRow series,
    EpisodeRow episode,
    Duration resumeAt,
  ) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showDialog<Duration>(
      context: context,
      builder: (context) => AlertDialog(
        title: BidiText(
          episode.title ?? l10n.vodEpisodeN(episode.number),
          maxLines: 2,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VodActionButton(
              key: const ValueKey('vod-option-resume'),
              autofocus: true,
              primary: true,
              icon: Icons.play_arrow_rounded,
              label: l10n.vodResumeFrom(formatPlayPosition(resumeAt)),
              onSelect: () => Navigator.of(context).pop(resumeAt),
            ),
            const SizedBox(height: Spacing.md),
            VodActionButton(
              key: const ValueKey('vod-option-start-over'),
              icon: Icons.replay_rounded,
              label: l10n.vodStartOver,
              onSelect: () => Navigator.of(context).pop(Duration.zero),
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) _play(series, episode, picked);
  }

  Future<void> _toggleFavorite() => ref
      .read(favoritesDaoProvider)
      .toggleFavorite(widget.sourceId, ContentKind.series, widget.seriesKey);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rowAsync = ref.watch(seriesRowProvider(_ref));
    final detailAsync = ref.watch(seriesDetailProvider(_ref));
    final episodesAsync = ref.watch(seriesEpisodesProvider(_ref));
    final progress =
        ref.watch(seriesProgressProvider(_ref)).value ??
        const <String, ProgressRow>{};
    final favorite =
        ref
            .watch(
              vodFavoriteProvider((
                widget.sourceId,
                ContentKind.series,
                widget.seriesKey,
              )),
            )
            .value ??
        false;

    if (!rowAsync.hasValue) {
      return VodDetailFrame(
        title: '',
        child: rowAsync.hasError
            ? ErrorView(onRetry: () => ref.invalidate(seriesRowProvider(_ref)))
            : const LoadingView(),
      );
    }
    final series = rowAsync.value;
    if (series == null) {
      return VodDetailFrame(
        title: '',
        child: EmptyView(
          message: l10n.commonUnavailable,
          icon: Icons.video_library_outlined,
        ),
      );
    }

    final result = detailAsync.value;
    final detail = result?.value;
    final stored = episodesAsync.value ?? const <EpisodeRow>[];
    // Right after a fetch the stored list may not have re-run yet.
    final episodes = stored.isNotEmpty
        ? stored
        : [for (final e in detail?.episodes ?? const <EpisodeData>[]) _row(e)];
    final loading =
        episodes.isEmpty && (detailAsync.isLoading || !episodesAsync.hasValue);
    final ready = !loading && _storedLoaded;

    final counts = <int, int>{};
    for (final e in episodes) {
      counts[e.season] = (counts[e.season] ?? 0) + 1;
    }
    final seasons = counts.keys.toList()..sort();
    final next = _nextUp(episodes, progress);
    var season = _season;
    if (season == null || !counts.containsKey(season)) {
      final remembered = _storedSeason;
      season = remembered != null && counts.containsKey(remembered)
          ? remembered
          : next?.episode.season ?? seasons.firstOrNull ?? 0;
    }
    final inSeason = [
      for (final e in episodes)
        if (e.season == season) e,
    ];

    final view = _SeriesView(
      series: series,
      detail: detail,
      failed: result?.failed ?? false,
      ready: ready,
      seasons: [
        for (final n in seasons)
          (
            number: n,
            label: _seasonLabel(l10n, n, detail?.seasons ?? const []),
            count: counts[n]!,
          ),
      ],
      season: season,
      episodes: inSeason,
      progress: progress,
      buttons: _buttons(l10n, series, next, favorite),
      state: this,
    );
    return VodDetailFrame(
      title: series.name,
      backdrop: detail?.backdrop,
      child: isLargeLayout(context) ? view.large(context) : view.phone(context),
    );
  }

  List<Widget> _buttons(
    AppLocalizations l10n,
    SeriesRow series,
    _NextUp? next,
    bool favorite,
  ) {
    final resumeAt = next?.resumeAt;
    final episode = next?.episode;
    return [
      VodActionButton(
        key: const ValueKey('vod-play'),
        focusNode: _primary,
        autofocus: true,
        primary: true,
        icon: Icons.play_arrow_rounded,
        label: episode == null
            ? l10n.vodPlay
            : resumeAt != null
            ? l10n.vod_resumeEpisode(episode.season, episode.number)
            : l10n.vod_playEpisode(episode.season, episode.number),
        onSelect: episode == null
            ? null
            : () => _play(series, episode, resumeAt),
      ),
      if (episode != null && resumeAt != null)
        VodActionButton(
          key: const ValueKey('vod-start-over'),
          icon: Icons.replay_rounded,
          label: l10n.vodStartOver,
          onSelect: () => _play(series, episode, Duration.zero),
        ),
      VodActionButton(
        key: const ValueKey('vod-favorite'),
        icon: favorite ? Icons.star_rounded : Icons.star_outline_rounded,
        label: favorite ? l10n.vodRemoveFavorite : l10n.vodAddFavorite,
        onSelect: () => unawaited(_toggleFavorite()),
      ),
    ];
  }

  /// The episode the primary button plays: the last watched one when it can
  /// be resumed, the one after it when it was finished, else the first.
  static _NextUp? _nextUp(
    List<EpisodeRow> episodes,
    Map<String, ProgressRow> progress,
  ) {
    if (episodes.isEmpty) return null;
    var index = -1;
    ProgressRow? last;
    for (final (i, e) in episodes.indexed) {
      final p = progress[e.key];
      if (p != null && (last == null || p.updatedAt.isAfter(last.updatedAt))) {
        last = p;
        index = i;
      }
    }
    if (last == null) return (episode: episodes.first, resumeAt: null);
    if (ProgressSaver.shouldOfferResume(last.position, last.duration)) {
      return (episode: episodes[index], resumeAt: last.position);
    }
    if (last.finished ||
        ProgressSaver.isFinished(last.position, last.duration)) {
      final after = index + 1 < episodes.length ? episodes[index + 1] : null;
      return (episode: after ?? episodes.first, resumeAt: null);
    }
    return (episode: episodes[index], resumeAt: null);
  }

  static final _genericSeasonName = RegExp(
    r'^season\s*\d+$',
    caseSensitive: false,
  );

  static String _seasonLabel(
    AppLocalizations l10n,
    int number,
    List<SeasonInfo> infos,
  ) {
    final name = infos
        .where((s) => s.number == number)
        .firstOrNull
        ?.name
        ?.trim();
    if (name != null && name.isNotEmpty && !_genericSeasonName.hasMatch(name)) {
      return name;
    }
    return l10n.vodSeasonN(number);
  }

  static EpisodeRow _row(EpisodeData e) => EpisodeRow(
    seriesKey: e.seriesKey,
    key: e.key,
    season: e.season,
    number: e.number,
    title: e.title,
    ext: e.ext,
    url: e.url,
    headers: e.headers,
    durationSec: e.durationSec,
    plot: e.plot,
    still: e.still,
  );
}

typedef _SeasonEntry = ({int number, String label, int count});

/// The page layouts (large and phone) over one state snapshot.
class _SeriesView {
  const _SeriesView({
    required this.series,
    required this.detail,
    required this.failed,
    required this.ready,
    required this.seasons,
    required this.season,
    required this.episodes,
    required this.progress,
    required this.buttons,
    required this.state,
  });

  final SeriesRow series;
  final SeriesDetail? detail;
  final bool failed;

  /// False while the episodes (or the remembered season) are loading.
  final bool ready;
  final List<_SeasonEntry> seasons;
  final int season;

  /// Episodes of [season].
  final List<EpisodeRow> episodes;
  final Map<String, ProgressRow> progress;
  final List<Widget> buttons;
  final _SeriesDetailScreenState state;

  Widget _info(BuildContext context, {required bool large}) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final plot = (detail?.plot ?? series.plot)?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        BidiText(
          series.name,
          maxLines: large ? 1 : 2,
          style: theme.headlineSmall,
        ),
        const SizedBox(height: Spacing.xs),
        VodMetaLine(
          year: series.year,
          rating: series.rating,
          genre: detail?.genre,
        ),
        if (plot != null && plot.isNotEmpty) ...[
          const SizedBox(height: Spacing.xs),
          BidiText(
            plot,
            key: const ValueKey('vod-plot'),
            maxLines: large ? 2 : null,
            // Without a line limit an ellipsis would cut it to one line.
            overflow: large ? TextOverflow.ellipsis : TextOverflow.visible,
            style: theme.bodyMedium,
          ),
        ],
        if (failed)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: Spacing.xs),
            child: Text(
              l10n.vod_detailsFailed,
              key: const ValueKey('vod-details-failed'),
              style: theme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _buttons({required bool large}) {
    final wrap = Wrap(
      spacing: Spacing.md,
      runSpacing: Spacing.md,
      children: buttons,
    );
    if (!large) return wrap;
    return PaneScope(
      key: state._headerPane,
      debugLabel: 'series-header',
      onExitDown: state._enterEpisodes,
      child: wrap,
    );
  }

  _EpisodeTile _episodeTile(EpisodeRow e) {
    final p = progress[e.key];
    final resumeAt =
        p != null && ProgressSaver.shouldOfferResume(p.position, p.duration)
        ? p.position
        : null;
    return _EpisodeTile(
      key: ValueKey('vod-ep-${e.key}'),
      episode: e,
      progress: p,
      onSelect: () => state._play(series, e, resumeAt),
      onMenu: resumeAt == null
          ? null
          : () => unawaited(state._episodeOptions(series, e, resumeAt)),
    );
  }

  Widget? _episodesState(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!ready) return const LoadingView();
    if (episodes.isEmpty) {
      return failed
          ? ErrorView(
              autofocusRetry: false,
              message: l10n.vod_detailsFailed,
              onRetry: () =>
                  state.ref.invalidate(seriesDetailProvider(state._ref)),
            )
          : EmptyView(
              message: l10n.vodNoEpisodes,
              icon: Icons.video_library_outlined,
            );
    }
    return null;
  }

  Widget large(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final placeholder = _episodesState(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VodPoster(url: series.poster, width: 96),
            const SizedBox(width: Spacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _info(context, large: true),
                  const SizedBox(height: Spacing.md),
                  _buttons(large: true),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        Expanded(
          child: placeholder != null
              ? PaneScope(
                  // Reaches a Retry button from the header.
                  key: state._episodesPane,
                  debugLabel: 'series-episodes-state',
                  onExitUp: state._focusHeader,
                  child: placeholder,
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 196,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PaneTitle(l10n.vodSeasons),
                          Expanded(
                            child: PaneScope(
                              key: state._seasonsPane,
                              debugLabel: 'series-seasons',
                              onExitEnd: state._enterEpisodes,
                              onExitUp: state._focusHeader,
                              child: ListView.builder(
                                key: const ValueKey('vod-seasons'),
                                padding: const EdgeInsets.all(Spacing.xs),
                                itemExtent: 48,
                                itemCount: seasons.length,
                                itemBuilder: (context, i) => _seasonTile(i),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PaneTitle(
                            '${l10n.vodEpisodes} · '
                            '${l10n.vodEpisodeCount(episodes.length)}',
                          ),
                          Expanded(
                            child: PaneScope(
                              key: state._episodesPane,
                              debugLabel: 'series-episodes',
                              onExitStart: () => state._focusSeasons(season),
                              onExitUp: state._focusHeader,
                              child: KeyRepeatGuard(
                                child: ListView.builder(
                                  key: ValueKey('vod-episodes-$season'),
                                  padding: const EdgeInsets.all(Spacing.xs),
                                  itemExtent: _EpisodeTile.extent,
                                  itemCount: episodes.length,
                                  itemBuilder: (context, i) =>
                                      _episodeTile(episodes[i]),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _seasonTile(int i, {bool chip = false}) {
    final s = seasons[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
      child: VodCategoryTile(
        key: ValueKey('vod-season-${s.number}'),
        focusNode: chip ? null : state._seasonNode(s.number),
        chip: chip,
        label: s.label,
        count: chip ? null : s.count,
        selected: s.number == season,
        onFocusChange: chip
            ? null
            : (focused) {
                if (focused) state._selectSeason(s.number, season);
              },
        onSelect: () {
          state._selectSeason(s.number, season);
          if (!chip) state._enterEpisodes();
        },
      ),
    );
  }

  Widget phone(BuildContext context) {
    final placeholder = _episodesState(context);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(Spacing.lg),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VodPoster(url: series.poster, width: 110),
                    const SizedBox(width: Spacing.lg),
                    Expanded(child: _info(context, large: false)),
                  ],
                ),
                const SizedBox(height: Spacing.lg),
                _buttons(large: false),
              ],
            ),
          ),
        ),
        if (placeholder != null)
          SliverToBoxAdapter(child: SizedBox(height: 240, child: placeholder))
        else ...[
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView.builder(
                key: const ValueKey('vod-seasons'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                itemCount: seasons.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsetsDirectional.only(end: Spacing.sm),
                  child: _seasonTile(i, chip: true),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
            sliver: SliverFixedExtentList(
              key: ValueKey('vod-episodes-$season'),
              itemExtent: _EpisodeTile.extent,
              delegate: SliverChildBuilderDelegate(
                (context, i) => _episodeTile(episodes[i]),
                childCount: episodes.length,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PaneTitle extends StatelessWidget {
  const _PaneTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: Spacing.sm,
        bottom: Spacing.xs,
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

/// One episode: still, number and title, runtime, watched mark and a
/// progress bar.
class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    super.key,
    required this.episode,
    required this.onSelect,
    this.progress,
    this.onMenu,
  });

  /// Fixed row height of episode lists.
  static const double extent = 68;

  final EpisodeRow episode;
  final ProgressRow? progress;
  final VoidCallback onSelect;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = episode.title?.trim();
    final title = name == null || name.isEmpty
        ? l10n.vodEpisodeN(episode.number)
        : '${episode.number}. $name';
    return TvFocusable(
      focusScale: 1.02,
      semanticLabel: title,
      onSelect: onSelect,
      onMenu: onMenu,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.1,
        child: Builder(builder: (context) => _body(context, title)),
      ),
    );
  }

  Widget _body(BuildContext context, String title) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final highlighted = TvHighlight.of(context);
    final progress = this.progress;
    final watched =
        progress != null &&
        (progress.finished ||
            ProgressSaver.isFinished(progress.position, progress.duration));
    final minutes = runtimeMinutes(
      episode.durationSec ??
          (progress == null || progress.duration <= Duration.zero
              ? null
              : progress.duration.inSeconds),
    );
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.surfaceHighest : Colors.transparent,
        borderRadius: Radii.mdAll,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            height: 54,
            child: ClipRRect(
              borderRadius: Radii.smAll,
              child: VodImage(
                url: episode.still,
                icon: Icons.ondemand_video_outlined,
                maxCacheWidth: 320,
              ),
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BidiText(
                  title,
                  style: theme.titleSmall?.copyWith(
                    color: highlighted ? AppColors.accent : null,
                  ),
                ),
                Row(
                  children: [
                    if (minutes != null)
                      Text(l10n.vodMinutes(minutes), style: theme.bodySmall),
                    if (minutes != null && watched)
                      const SizedBox(width: Spacing.sm),
                    if (watched) ...[
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 14,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: Spacing.xs),
                      Text(l10n.vodWatched, style: theme.bodySmall),
                    ],
                  ],
                ),
                if (progress != null && !watched && progress.fraction > 0)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: Spacing.xs),
                    child: ProgressLine(value: progress.fraction),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
