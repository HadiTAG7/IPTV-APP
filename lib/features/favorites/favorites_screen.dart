import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_shell.dart';
import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../sources/models.dart';
import '../../theme/tokens.dart';
import '../../tv/focus_watchdog.dart';
import '../../tv/pane_scope.dart';
import '../../tv/tv_focusable.dart';
import '../../widgets/states.dart';
import '../live/channel_list.dart';
import '../live/channel_source.dart';
import '../live/live_actions.dart';
import '../live/live_models.dart';
import '../live/now_next_store.dart';
import '../live/options_sheet.dart';
import '../live/preferred_focus.dart';
import '../live/providers.dart';
import 'poster_grid.dart';
import 'providers.dart';
import 'vod_navigation.dart';

/// The parts of the Favorites screen.
enum FavoritesSegment { live, movies, series }

/// Favourite channels, movies and series of the active source, as three
/// segments. Live favourites play like channels (zapping within the
/// favourites); movies and series open through [vodDetailNavigatorProvider].
///
/// Renders body content only; the home shells (or `pushHomePage`) provide
/// the chrome.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceId = ref.watch(activeSourceIdProvider);
    if (sourceId == null) return const LoadingView();
    return FavoritesView(
      key: ValueKey('favorites-source-$sourceId'),
      sourceId: sourceId,
    );
  }
}

/// The Favorites screen for one source (see [FavoritesScreen]).
class FavoritesView extends ConsumerStatefulWidget {
  const FavoritesView({super.key, required this.sourceId});

  final int sourceId;

  @override
  ConsumerState<FavoritesView> createState() => FavoritesViewState();
}

class FavoritesViewState extends ConsumerState<FavoritesView> {
  final _tabsPane = GlobalKey<PaneScopeState>();
  final _contentPane = GlobalKey<PaneScopeState>();
  final _grid = GlobalKey<PosterGridState>();
  final _list = GlobalKey<ChannelListState>(debugLabel: 'favorites-list');
  final _tabNodes = {
    for (final s in FavoritesSegment.values)
      s: FocusNode(debugLabel: 'favorites-${s.name}'),
  };
  late final _policy = PreferredFirstTraversalPolicy(_preferred);
  late final NowNextStore _store;
  FavoritesSegment _segment = FavoritesSegment.live;
  int _liveVersion = 0;
  FocusWatchdogState? _watchdog;

  int get _id => widget.sourceId;

  /// The segment shown, for tests.
  @visibleForTesting
  FavoritesSegment get segment => _segment;

  /// Inside a home shell tab (else a pushed page that focuses itself).
  bool get _inShell => HomeBackScope.maybeOf(context) != null;

  @override
  void initState() {
    super.initState();
    _store = NowNextStore(
      load: (keys, now) => ref.read(epgDaoProvider).nowNext(_id, keys, now),
      clock: ref.read(clockProvider),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final watchdog = _inShell ? null : FocusWatchdog.maybeOf(context);
    if (watchdog != _watchdog) {
      _watchdog?.unregister(_tabNodes[_segment]!);
      _watchdog = watchdog?..register(_tabNodes[_segment]!);
    }
  }

  @override
  void dispose() {
    for (final node in _tabNodes.values) {
      _watchdog?.unregister(node);
      node.dispose();
    }
    _store.dispose();
    super.dispose();
  }

  List<FocusNode?> _preferred() => [
    _tabsPane.currentState?.node,
    _tabNodes[_segment],
    _list.currentState?.preferredNode,
    _grid.currentState?.firstNode,
  ];

  void _show(FavoritesSegment segment, {bool enter = false}) {
    if (segment != _segment) setState(() => _segment = segment);
    if (enter) afterNextFrame(_enterContent);
  }

  void _enterContent() {
    if (_segment == FavoritesSegment.live) {
      _list.currentState?.focusCurrent();
    } else {
      _contentPane.currentState?.requestFocus();
    }
  }

  void _enterTabs() => _tabNodes[_segment]!.requestFocus();

  bool _onBack() {
    if (_list.currentState?.clearDigits() ?? false) return true;
    if (_contentPane.currentState?.hasFocus ?? false) {
      _enterTabs();
      return true;
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Channels.

  Future<void> _playChannel(ChannelListSource source, LiveEntry entry) {
    final row = entry.row;
    if (row == null) return Future.value();
    return ref.read(playGateProvider).run(() async {
      final request = await source.requestFor(row);
      if (!mounted) return;
      final wasFocused = _list.currentState?.hasFocus ?? false;
      await playLiveChannel(context, ref, request);
      if (!mounted) return;
      final last =
          (await ref.read(recentDaoProvider).recentChannelKeys(_id, limit: 1))
              .firstOrNull;
      if (!mounted) return;
      await _list.currentState?.refresh(focusKey: last, focus: wasFocused);
    });
  }

  Future<void> _channelMenu(ChannelListSource source, LiveEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final row = entry.row;
    final choice = await showOptionsSheet<LiveChannelAction>(
      context,
      title: row?.name ?? l10n.commonUnavailable,
      options: [
        SheetOption(
          value: LiveChannelAction.favorite,
          icon: Icons.star_outline_rounded,
          label: l10n.liveRemoveFavorite,
        ),
        if (row != null && hasOtherLiveEngine(ref))
          SheetOption(
            value: LiveChannelAction.otherPlayer,
            icon: Icons.swap_horiz,
            label: l10n.livePlayWithOtherPlayer,
          ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case LiveChannelAction.favorite:
        await setFavorite(ref, _id, ContentKind.live, entry.key, false);
      case LiveChannelAction.otherPlayer:
        await ref.read(playGateProvider).run(() async {
          final request = await source.requestFor(row!);
          if (!mounted) return;
          await playWithOtherEngine(context, ref, request);
        });
      case null:
        break;
    }
  }

  // -------------------------------------------------------------------------
  // Movies and series.

  Future<void> _openVod(VodTarget target) =>
      ref.read(playGateProvider).run(() async {
        await ref.read(vodDetailNavigatorProvider)(context, ref, target);
        if (!mounted) return;
        ref.invalidate(favoriteMoviesProvider(_id));
      });

  /// A segment's favourites changed. When the segment shown has none left
  /// its content pane leaves the tree (see [build]); focus in it moves to
  /// the tabs first, before the rows it is on go.
  void _onKeysChanged(FavoritesSegment segment, Set<String>? after) {
    if (after == null || after.isNotEmpty || segment != _segment) return;
    if (_contentPane.currentState?.hasFocus ?? false) _enterTabs();
  }

  Future<void> _vodMenu(ContentKind kind, PosterItem item) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showOptionsSheet<bool>(
      context,
      title: item.title,
      options: [
        SheetOption(
          value: true,
          icon: Icons.star_outline_rounded,
          label: l10n.vodRemoveFavorite,
        ),
      ],
    );
    if (!mounted || choice != true) return;
    // Keep focus alive: on a neighbour, or on the tabs for the last one.
    final grid = _grid.currentState;
    if (grid == null || grid.widget.items.length <= 1) {
      _enterTabs();
    } else {
      grid.focusNeighbourOf(item.key);
    }
    await setFavorite(ref, _id, kind, item.key, false);
  }

  // -------------------------------------------------------------------------
  // Build.

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen(favoriteKeysProvider((_id, ContentKind.live)), (prev, next) {
      final before = prev?.value;
      final after = next.value;
      if (before == null || after == null || setEquals(before, after)) return;
      _onKeysChanged(FavoritesSegment.live, after);
      setState(() => _liveVersion++);
    });
    ref.listen(
      favoriteKeysProvider((_id, ContentKind.movie)),
      (_, next) => _onKeysChanged(FavoritesSegment.movies, next.value),
    );
    ref.listen(
      favoriteKeysProvider((_id, ContentKind.series)),
      (_, next) => _onKeysChanged(FavoritesSegment.series, next.value),
    );
    final counts = {
      FavoritesSegment.live: ref
          .watch(favoriteKeysProvider((_id, ContentKind.live)))
          .value
          ?.length,
      FavoritesSegment.movies: ref
          .watch(favoriteKeysProvider((_id, ContentKind.movie)))
          .value
          ?.length,
      FavoritesSegment.series: ref
          .watch(favoriteKeysProvider((_id, ContentKind.series)))
          .value
          ?.length,
    };
    final labels = {
      FavoritesSegment.live: l10n.navLive,
      FavoritesSegment.movies: l10n.navMovies,
      FavoritesSegment.series: l10n.navSeries,
    };
    final autofocus = !_inShell;
    // Pushed pages have an app bar; in a shell tab the page names itself.
    final title = _inShell && isLargeLayout(context);
    final (content, empty) = switch (_segment) {
      FavoritesSegment.live => _buildChannels(l10n),
      FavoritesSegment.movies => _buildMovies(l10n),
      FavoritesSegment.series => _buildSeries(l10n),
    };
    return HomeTabBackHandler(
      onBack: _onBack,
      child: FocusTraversalGroup(
        policy: _policy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PaneScope(
              key: _tabsPane,
              debugLabel: 'favorites-tabs',
              onExitDown: _enterContent,
              child: Padding(
                padding: const EdgeInsets.all(Spacing.sm),
                child: Row(
                  children: [
                    if (title)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: Spacing.xs,
                          end: Spacing.xl,
                        ),
                        child: Text(
                          l10n.navFavorites,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    for (final s in FavoritesSegment.values)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: Spacing.sm,
                        ),
                        child: _SegmentTab(
                          key: ValueKey('favorites-tab-${s.name}'),
                          focusNode: _tabNodes[s]!,
                          label: labels[s]!,
                          count: counts[s],
                          selected: s == _segment,
                          autofocus: autofocus && s == _segment,
                          onFocus: () => _show(s),
                          onSelect: () => _show(s, enter: true),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              // An empty segment is not a pane. A pane in the tree is
              // remembered by the page's focus scope as the way back in, and
              // one with nothing focusable would leave the rail unable to
              // enter the page; without it the page re-enters on the tabs.
              child: empty
                  ? KeyedSubtree(
                      key: ValueKey('favorites-${_segment.name}-empty'),
                      child: content,
                    )
                  : PaneScope(
                      key: _contentPane,
                      debugLabel: 'favorites-content',
                      onExitUp: _enterTabs,
                      child: KeyedSubtree(
                        key: ValueKey('favorites-${_segment.name}'),
                        child: content,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// The content of a segment, and whether it is empty (nothing to focus).
  (Widget, bool) _buildChannels(AppLocalizations l10n) {
    final keys = ref.watch(favoriteKeysProvider((_id, ContentKind.live))).value;
    if (keys != null && keys.isEmpty) {
      final empty = EmptyView(
        message: l10n.favoritesEmpty,
        icon: Icons.star_outline_rounded,
      );
      return (empty, true);
    }
    final favorites = keys ?? const <String>{};
    final recent = ref.watch(recentChannelKeysProvider(_id)).value;
    final list = ChannelList(
      key: _list,
      sourceId: _id,
      list: const LiveList.favorites(),
      store: _store,
      itemExtent: isLargeLayout(context)
          ? TvLayout.channelExtent
          : TvLayout.channelExtentPhone,
      favorites: favorites,
      playingKey: recent?.firstOrNull,
      dataVersion: _liveVersion,
      onPlay: _playChannel,
      onMenu: _channelMenu,
      onEmptied: (hadFocus, _) {
        if (hadFocus || (_contentPane.currentState?.hasFocus ?? false)) {
          _enterTabs();
        }
      },
      emptyMessage: l10n.favoritesEmpty,
      emptyIcon: Icons.star_outline_rounded,
    );
    return (list, false);
  }

  (Widget, bool) _buildMovies(AppLocalizations l10n) {
    final movies = ref.watch(favoriteMoviesProvider(_id));
    final value = movies.value;
    if (value == null) {
      final state = movies.hasError
          ? ErrorView(
              onRetry: () => ref.invalidate(favoriteMoviesProvider(_id)),
              autofocusRetry: false,
            )
          : const LoadingView();
      return (state, false);
    }
    if (value.items.isEmpty) {
      final empty = EmptyView(
        message: l10n.favoritesEmptyMovies,
        icon: Icons.movie_outlined,
      );
      return (empty, true);
    }
    final rows = {for (final f in value.items) f.key: f.item};
    final grid = PosterGrid(
      key: _grid,
      items: [
        for (final f in value.items)
          PosterItem(
            key: f.key,
            title: f.item?.name ?? l10n.commonUnavailable,
            posterUrl: f.item?.poster,
            progress: _fraction(value.progress[f.key]),
          ),
      ],
      onSelect: (item) {
        final movie = rows[item.key];
        if (movie == null) return;
        unawaited(_openVod(VodTarget.movie(sourceId: _id, movie: movie)));
      },
      onMenu: (item) => unawaited(_vodMenu(ContentKind.movie, item)),
    );
    return (grid, false);
  }

  (Widget, bool) _buildSeries(AppLocalizations l10n) {
    final series = ref.watch(favoriteSeriesProvider(_id));
    final items = series.value;
    if (items == null) {
      final state = series.hasError
          ? ErrorView(
              onRetry: () => ref.invalidate(favoriteSeriesProvider(_id)),
              autofocusRetry: false,
            )
          : const LoadingView();
      return (state, false);
    }
    if (items.isEmpty) {
      final empty = EmptyView(
        message: l10n.favoritesEmptySeries,
        icon: Icons.video_library_outlined,
      );
      return (empty, true);
    }
    final rows = {for (final f in items) f.key: f.item};
    final grid = PosterGrid(
      key: _grid,
      items: [
        for (final f in items)
          PosterItem(
            key: f.key,
            title: f.item?.name ?? l10n.commonUnavailable,
            posterUrl: f.item?.poster,
          ),
      ],
      onSelect: (item) {
        final row = rows[item.key];
        if (row == null) return;
        unawaited(_openVod(VodTarget.series(sourceId: _id, series: row)));
      },
      onMenu: (item) => unawaited(_vodMenu(ContentKind.series, item)),
    );
    return (grid, false);
  }
}

/// Watch progress to draw on a poster: unfinished titles only.
double? _fraction(ProgressRow? p) =>
    p == null || p.finished || p.fraction <= 0 ? null : p.fraction;

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    super.key,
    required this.focusNode,
    required this.label,
    required this.selected,
    required this.onFocus,
    required this.onSelect,
    this.count,
    this.autofocus = false,
  });

  final FocusNode focusNode;
  final String label;
  final int? count;
  final bool selected;
  final bool autofocus;
  final VoidCallback onFocus;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    final fg = selected ? AppColors.onAccent : AppColors.textPrimary;
    final count = this.count;
    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      focusScale: 1.04,
      borderRadius: BorderRadius.circular(Radii.pill),
      semanticLabel: label,
      onFocusChange: (focused) {
        if (focused) onFocus();
      },
      onSelect: onSelect,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: style?.copyWith(color: fg)),
            if (count != null) ...[
              const SizedBox(width: Spacing.sm),
              Text(
                '$count',
                textDirection: TextDirection.ltr,
                style: style?.copyWith(
                  color: selected
                      ? AppColors.onAccent
                      : AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
