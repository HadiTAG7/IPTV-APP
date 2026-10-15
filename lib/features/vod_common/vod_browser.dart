import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_shell.dart';
import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../sources/models.dart';
import '../../theme/tokens.dart';
import '../../tv/key_repeat.dart';
import '../../tv/pane_scope.dart';
import '../../widgets/poster_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/states.dart';
import 'paged_items.dart';
import 'vod_navigation.dart';
import 'vod_providers.dart';
import 'vod_widgets.dart';

/// One poster of the grid.
typedef VodTile = ({String key, String name, String? poster});

/// Movie or series browser: a category list and a poster grid paged from
/// the database.
///
/// * Large layout (TV, desktop, landscape tablets): a category pane on the
///   start side and the grid pane. Arrows cross between them (mirrored in
///   RTL); the start edge of the category pane goes back to the shell's
///   rail. Focusing a category shows it after [focusDelay]; OK shows it at
///   once and moves into the grid. Back in the grid returns to the
///   categories.
/// * Phone: category chips above the grid.
/// * Virtual categories: All (first) and Continue watching (when there is
///   something to continue). All also shows a Continue watching row above
///   the grid.
/// * Grids read pages of 200 items ([PagedItems]) with a fixed 2:3 extent
///   ([VodGridLayout]); OK opens the detail page.
class VodBrowser extends ConsumerStatefulWidget {
  const VodBrowser({super.key, required this.kind});

  final VodKind kind;

  /// How long a category must keep focus before the grid switches to it.
  static const focusDelay = Duration(milliseconds: 250);

  @override
  ConsumerState<VodBrowser> createState() => VodBrowserState();
}

class VodBrowserState extends ConsumerState<VodBrowser> {
  static const allId = 'all';
  static const continueId = 'cw';

  /// Entry id of a provider category.
  static String categoryId(String key) => 'c:$key';

  final _categoriesPane = GlobalKey<PaneScopeState>();
  final _gridPane = GlobalKey<PaneScopeState>();
  String _selected = allId;
  String? _pending;
  Timer? _focusTimer;
  int? _sourceId;

  /// The last item count shown, kept while a sync's new count is read.
  int? _lastTotal;

  /// The entry the grid shows.
  String get selected => _selected;

  @override
  void dispose() {
    _focusTimer?.cancel();
    super.dispose();
  }

  void _select(String id) {
    _focusTimer?.cancel();
    _pending = null;
    if (id != _selected) setState(() => _selected = id);
  }

  void _onEntryFocus(String id, bool focused) {
    if (!focused || !isLargeLayout(context)) return;
    _focusTimer?.cancel();
    if (id == _selected) {
      _pending = null;
      return;
    }
    _pending = id;
    _focusTimer = Timer(VodBrowser.focusDelay, () {
      if (mounted) _select(id);
    });
  }

  void _openEntry(String id) {
    _select(id);
    if (isLargeLayout(context)) _enterGridAfterBuild();
  }

  void _enterGrid() {
    final pending = _pending;
    if (pending != null) _select(pending);
    _enterGridAfterBuild();
  }

  void _enterGridAfterBuild() {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted) _gridPane.currentState?.requestFocus();
      })
      ..ensureVisualUpdate();
  }

  void _focusCategories() => _categoriesPane.currentState?.requestFocus();

  bool _onBack() {
    if (_gridPane.currentState?.hasFocus ?? false) {
      _focusCategories();
      return true;
    }
    return false;
  }

  void _openTile(int sourceId, VodTile tile) {
    switch (widget.kind) {
      case VodKind.movie:
        unawaited(openMovieDetail(context, sourceId, tile.key));
      case VodKind.series:
        unawaited(openSeriesDetail(context, sourceId, tile.key));
    }
  }

  Future<void> _openContinue(int sourceId, ContinueWatchingItem item) async {
    if (item.kind == PlayableKind.movie) {
      return openMovieDetail(context, sourceId, item.key);
    }
    final seriesKey =
        item.progress.seriesKey ??
        (await ref.read(catalogDaoProvider).episodeByKey(sourceId, item.key))
            ?.seriesKey;
    if (seriesKey == null || !mounted) return;
    return openSeriesDetail(context, sourceId, seriesKey);
  }

  PageLoader<VodTile> _loaderFor(int sourceId, String id) {
    final catalog = ref.read(catalogDaoProvider);
    final category = id.startsWith('c:') ? id.substring(2) : null;
    return switch (widget.kind) {
      VodKind.movie => (offset, limit) async => [
        for (final m
            in await (category == null
                ? catalog.allMoviesPage(sourceId, offset, limit)
                : catalog.moviesPage(sourceId, category, offset, limit)))
          (key: m.key, name: m.name, poster: m.poster),
      ],
      VodKind.series => (offset, limit) async => [
        for (final s
            in await (category == null
                ? catalog.allSeriesPage(sourceId, offset, limit)
                : catalog.seriesPage(sourceId, category, offset, limit)))
          (key: s.key, name: s.name, poster: s.poster),
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kind = widget.kind;
    final emptyMessage = switch (kind) {
      VodKind.movie => l10n.vod_noMovies,
      VodKind.series => l10n.vod_noSeries,
    };
    final sourceId = ref.watch(activeSourceIdProvider);
    if (sourceId == null) return EmptyView(message: emptyMessage);
    if (sourceId != _sourceId) {
      // Another source: start over on All.
      _sourceId = sourceId;
      _selected = allId;
      _pending = null;
      _lastTotal = null;
      _focusTimer?.cancel();
    }
    final generation = ref.watch(
      activeSourceProvider.select((s) => s?.generation ?? 0),
    );
    final categoriesAsync = ref.watch(
      vodCategoriesProvider((sourceId, kind.contentKind)),
    );
    final totalAsync = ref.watch(
      vodTotalCountProvider((sourceId, kind.contentKind, generation)),
    );
    final continueItems =
        ref
            .watch(continueWatchingProvider((sourceId, kind.progressKind)))
            .value ??
        const <ContinueWatchingItem>[];
    final categories = categoriesAsync.value;
    final total = totalAsync.value ?? _lastTotal;
    _lastTotal = total;
    if (categories == null || total == null) {
      if (categoriesAsync.hasError || totalAsync.hasError) {
        return ErrorView(
          autofocusRetry: false,
          onRetry: () {
            ref.invalidate(vodCategoriesProvider);
            ref.invalidate(vodTotalCountProvider);
          },
        );
      }
      return const LoadingView();
    }
    if (total == 0 && continueItems.isEmpty) {
      // Nothing to browse: the page title over the empty message.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.all(Spacing.lg),
            child: Text(
              kind == VodKind.movie ? l10n.navMovies : l10n.navSeries,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Expanded(
            child: EmptyView(
              message: emptyMessage,
              icon: kind == VodKind.movie
                  ? Icons.movie_outlined
                  : Icons.video_library_outlined,
            ),
          ),
        ],
      );
    }

    final entries = <_Entry>[
      _Entry(
        allId,
        kind == VodKind.movie ? l10n.vod_allMovies : l10n.vod_allSeries,
        total,
        Icons.apps,
      ),
      if (continueItems.isNotEmpty)
        _Entry(
          continueId,
          l10n.vodContinueWatching,
          continueItems.length,
          Icons.history,
        ),
      for (final c in categories)
        _Entry(categoryId(c.key), c.name, c.itemCount, null),
    ];
    final current =
        entries.where((e) => e.id == _selected).firstOrNull ?? entries.first;
    final large = isLargeLayout(context);

    final Widget grid;
    if (current.id == continueId) {
      grid = _ContinueGrid(
        key: ValueKey('vod-grid:$sourceId:$continueId'),
        items: continueItems,
        large: large,
        onOpen: (item) => unawaited(_openContinue(sourceId, item)),
      );
    } else {
      final showRow = current.id == allId && continueItems.isNotEmpty;
      grid = _PagedGrid(
        // A sync that keeps the item count refreshes the grid in place, so
        // focus and scroll position stay.
        key: ValueKey('vod-grid:$sourceId:${current.id}:${current.count}'),
        generation: generation,
        count: current.count,
        load: _loaderFor(sourceId, current.id),
        large: large,
        emptyMessage: emptyMessage,
        onOpen: (tile) => _openTile(sourceId, tile),
        header: showRow
            ? (cardWidth) => ContinueWatchingRow(
                items: continueItems,
                cardWidth: cardWidth,
                onOpen: (item) => unawaited(_openContinue(sourceId, item)),
              )
            : null,
      );
    }

    final body = large
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 156,
                child: PaneScope(
                  key: _categoriesPane,
                  debugLabel: 'vod-categories',
                  // No onExitStart: the shell takes focus back to the rail.
                  onExitEnd: _enterGrid,
                  child: KeyRepeatGuard(
                    child: ListView.builder(
                      key: const ValueKey('vod-categories'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.xs,
                        vertical: Spacing.xs,
                      ),
                      itemExtent: 44,
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: Spacing.xxs,
                          ),
                          child: VodCategoryTile(
                            key: ValueKey('vod-cat-${e.id}'),
                            label: e.label,
                            count: e.count,
                            icon: e.icon,
                            selected: e.id == current.id,
                            onFocusChange: (f) => _onEntryFocus(e.id, f),
                            onSelect: () => _openEntry(e.id),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: PaneScope(
                  key: _gridPane,
                  debugLabel: 'vod-grid',
                  onExitStart: _focusCategories,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: VodGridLayout.padding,
                        ),
                        child: SectionHeader(
                          current.label,
                          padding: const EdgeInsetsDirectional.only(
                            top: Spacing.xs,
                          ),
                          trailing: Text(
                            '${current.count}',
                            textDirection: TextDirection.ltr,
                          ),
                        ),
                      ),
                      Expanded(child: grid),
                    ],
                  ),
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 52,
                child: ListView.separated(
                  key: const ValueKey('vod-categories'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.sm,
                  ),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(width: Spacing.sm),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return VodCategoryTile(
                      key: ValueKey('vod-cat-${e.id}'),
                      chip: true,
                      label: e.label,
                      icon: e.icon,
                      selected: e.id == current.id,
                      onSelect: () => _openEntry(e.id),
                    );
                  },
                ),
              ),
              Expanded(child: grid),
            ],
          );
    return HomeTabBackHandler(onBack: _onBack, child: body);
  }
}

class _Entry {
  const _Entry(this.id, this.label, this.count, this.icon);

  final String id;
  final String label;
  final int count;
  final IconData? icon;
}

/// A poster grid over a paged list, with an optional header row.
class _PagedGrid extends StatefulWidget {
  const _PagedGrid({
    super.key,
    required this.generation,
    required this.count,
    required this.load,
    required this.large,
    required this.emptyMessage,
    required this.onOpen,
    this.header,
  });

  /// Catalog generation; a new one re-reads the pages in memory.
  final int generation;
  final int count;
  final PageLoader<VodTile> load;
  final bool large;
  final String emptyMessage;
  final ValueChanged<VodTile> onOpen;
  final Widget Function(double cardWidth)? header;

  @override
  State<_PagedGrid> createState() => _PagedGridState();
}

class _PagedGridState extends State<_PagedGrid> {
  late final PagedItems<VodTile> _items = PagedItems(
    count: widget.count,
    load: (offset, limit) => widget.load(offset, limit),
  );

  @override
  void didUpdateWidget(_PagedGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.generation != widget.generation) _items.refresh();
  }

  @override
  void dispose() {
    _items.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final header = widget.header;
    if (widget.count == 0 && header == null) {
      return EmptyView(message: widget.emptyMessage);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = VodGridLayout.forWidth(
          constraints.maxWidth,
          large: widget.large,
        );
        return ListenableBuilder(
          listenable: _items,
          builder: (context, _) {
            if (_items.error != null && _items.isEmpty) {
              return ErrorView(autofocusRetry: false, onRetry: _items.retry);
            }
            return KeyRepeatGuard(
              child: CustomScrollView(
                slivers: [
                  if (header != null)
                    SliverToBoxAdapter(child: header(layout.cellWidth)),
                  SliverPadding(
                    padding: const EdgeInsets.all(VodGridLayout.padding),
                    sliver: SliverGrid(
                      gridDelegate: layout.delegate,
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final tile = _items.itemAt(i);
                          return PosterCard(
                            key: ValueKey('vod-grid-$i'),
                            title: tile?.name ?? '',
                            posterUrl: tile?.poster,
                            onSelect: tile == null
                                ? null
                                : () => widget.onOpen(tile),
                          );
                        },
                        childCount: widget.count,
                        addAutomaticKeepAlives: false,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// The Continue watching category as a grid (newest first).
class _ContinueGrid extends StatelessWidget {
  const _ContinueGrid({
    super.key,
    required this.items,
    required this.large,
    required this.onOpen,
  });

  final List<ContinueWatchingItem> items;
  final bool large;
  final ValueChanged<ContinueWatchingItem> onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = VodGridLayout.forWidth(
          constraints.maxWidth,
          large: large,
        );
        return KeyRepeatGuard(
          child: GridView.builder(
            padding: const EdgeInsets.all(VodGridLayout.padding),
            gridDelegate: layout.delegate,
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              return PosterCard(
                key: ValueKey('vod-cwg-${item.kind.name}-${item.key}'),
                title: continueTitle(item),
                posterUrl: item.poster,
                progress: item.progress.fraction,
                onSelect: () => onOpen(item),
              );
            },
          ),
        );
      },
    );
  }
}
