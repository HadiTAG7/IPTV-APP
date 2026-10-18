import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_shell.dart';
import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../core/text/normalize.dart';
import '../../epg/epg_providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../player/ui/play_request.dart';
import '../../sources/models.dart';
import '../../theme/tokens.dart';
import '../../tv/focus_watchdog.dart';
import '../../tv/pane_scope.dart';
import '../../tv/tv_text_field.dart';
import '../../widgets/channel_tile.dart';
import '../../widgets/poster_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/states.dart';
import '../channel_lists/channel_list_dialogs.dart';
import '../favorites/vod_navigation.dart';
import '../live/live_actions.dart';
import '../live/now_next_store.dart';
import '../live/options_sheet.dart';
import '../live/preferred_focus.dart';
import '../live/providers.dart';

/// Search across the active source's channels, movies and series.
///
/// A [TvTextField] on top (Down moves into the results), results grouped as
/// Channels, Movies and Series (`CatalogDao.search`: case-insensitive with
/// Arabic letter folding), queried 300 ms after typing stops. Channels play
/// (zapping within the results); movies and series open through
/// [vodDetailNavigatorProvider].
///
/// Renders body content only; the home shells (or `pushHomePage`) provide
/// the chrome.
class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceId = ref.watch(activeSourceIdProvider);
    if (sourceId == null) return const LoadingView();
    return SearchView(
      key: ValueKey('search-source-$sourceId'),
      sourceId: sourceId,
    );
  }
}

/// The Search screen for one source (see [SearchScreen]).
class SearchView extends ConsumerStatefulWidget {
  const SearchView({super.key, required this.sourceId});

  /// Typing must pause this long before a query runs.
  static const debounce = Duration(milliseconds: 300);

  /// Hits per kind.
  static const limitPerKind = 50;

  final int sourceId;

  @override
  ConsumerState<SearchView> createState() => SearchViewState();
}

class SearchViewState extends ConsumerState<SearchView> {
  final _controller = TextEditingController();
  final _fieldNode = FocusNode(debugLabel: 'search-field');
  final _resultsPane = GlobalKey<PaneScopeState>();
  final _fieldPane = GlobalKey<PaneScopeState>();
  final _nodes = <String, FocusNode>{};
  late final _policy = PreferredFirstTraversalPolicy(_preferred);
  late final NowNextStore _store;
  Timer? _debounce;
  int _seq = 0;
  bool _searching = false;
  String _query = '';
  SearchResults _results = SearchResults.empty;
  FocusWatchdogState? _watchdog;

  int get _id => widget.sourceId;

  /// Queries run so far, for tests.
  @visibleForTesting
  int searches = 0;

  /// The latest results, for tests.
  @visibleForTesting
  SearchResults get results => _results;

  bool get _inShell => HomeBackScope.maybeOf(context) != null;

  @override
  void initState() {
    super.initState();
    _store = NowNextStore(
      load: (keys, now) => ref.read(epgDaoProvider).nowNext(_id, keys, now),
      clock: ref.read(clockProvider),
    );
    // New guide data: the now/next on screen is read again.
    ref.listenManual<GuideRefreshStatus>(guideRefreshProvider(_id), (
      previous,
      next,
    ) {
      if (next is GuideRefreshDone && previous is! GuideRefreshDone) {
        unawaited(_store.reload());
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final watchdog = _inShell ? null : FocusWatchdog.maybeOf(context);
    if (watchdog != _watchdog) {
      _watchdog?.unregister(_fieldNode);
      _watchdog = watchdog?..register(_fieldNode);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _watchdog?.unregister(_fieldNode);
    _controller.dispose();
    _fieldNode.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    _store.dispose();
    super.dispose();
  }

  List<FocusNode?> _preferred() => [_fieldPane.currentState?.node, _fieldNode];

  FocusNode _nodeFor(String id) =>
      _nodes.putIfAbsent(id, () => FocusNode(debugLabel: 'search-$id'));

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(SearchView.debounce, () => unawaited(_run(text)));
  }

  void _onSubmitted(String text) {
    _debounce?.cancel();
    unawaited(_run(text));
  }

  Future<void> _run(String text) async {
    final query = text.trim();
    final seq = ++_seq;
    if (normalizeForSearch(query).isEmpty) {
      setState(() {
        _query = '';
        _results = SearchResults.empty;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    searches++;
    SearchResults results;
    try {
      results = await ref
          .read(catalogDaoProvider)
          .search(_id, query, limitPerKind: SearchView.limitPerKind);
    } on Object catch (e, st) {
      ref.read(ringLogProvider).error('Search failed', e, st);
      results = SearchResults.empty;
    }
    if (!mounted || seq != _seq) return;
    setState(() {
      _query = query;
      _results = results;
      _searching = false;
    });
    _pruneNodes(results);
    // At most [SearchView.limitPerKind] channels: one query covers them all,
    // so rows scrolled to later have their programme too.
    _store.showing([for (final c in results.channels) c.key]);
  }

  /// Drops the focus nodes of items no longer listed (after this frame,
  /// once their widgets are gone).
  void _pruneNodes(SearchResults results) {
    final keep = {
      for (final c in results.channels) 'channel:${c.key}',
      for (final m in results.movies) 'movie:${m.key}',
      for (final s in results.series) 'series:${s.key}',
    };
    final gone = [
      for (final MapEntry(:key, :value) in _nodes.entries)
        if (!keep.contains(key) && !value.hasFocus) key,
    ];
    if (gone.isEmpty) return;
    final nodes = [for (final key in gone) _nodes.remove(key)!];
    afterNextFrame(() {
      for (final node in nodes) {
        node.dispose();
      }
    });
  }

  void _enterResults() => _resultsPane.currentState?.requestFocus();

  void _enterField() => _fieldNode.requestFocus();

  bool _onBack() {
    if (_resultsPane.currentState?.hasFocus ?? false) {
      _enterField();
      return true;
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Actions.

  Future<void> _playChannel(ChannelRow channel) {
    final request = PlayRequest(
      sourceId: _id,
      item: channel.toPlayable(),
      zapKeys: [for (final c in _results.channels) c.key],
    );
    return ref
        .read(playGateProvider)
        .run(() => playLiveChannel(context, ref, request));
  }

  Future<void> _channelMenu(ChannelRow channel, bool isFavorite) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showOptionsSheet<LiveChannelAction>(
      context,
      title: channel.name,
      options: [
        SheetOption(
          value: LiveChannelAction.favorite,
          icon: isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
          label: isFavorite ? l10n.liveRemoveFavorite : l10n.liveAddFavorite,
        ),
        SheetOption(
          value: LiveChannelAction.addToList,
          icon: Icons.playlist_add_rounded,
          label: l10n.liveAddToList,
        ),
        if (hasOtherLiveEngine(ref))
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
        await setFavorite(ref, _id, ContentKind.live, channel.key, !isFavorite);
      case LiveChannelAction.addToList:
        await showAddToListDialog(
          context,
          ref,
          sourceId: _id,
          channelKey: channel.key,
        );
      case LiveChannelAction.otherPlayer:
        final request = PlayRequest(
          sourceId: _id,
          item: channel.toPlayable(),
          zapKeys: [for (final c in _results.channels) c.key],
        );
        await ref
            .read(playGateProvider)
            .run(() => playWithOtherEngine(context, ref, request));
      case LiveChannelAction.moveUp ||
          LiveChannelAction.moveDown ||
          LiveChannelAction.removeFromList ||
          null:
        break;
    }
  }

  Future<void> _vodMenu(ContentKind kind, String key, String title) async {
    // Read the database: nothing here keeps the movie and series favourite
    // providers alive, so their value may not be loaded.
    final bool isFavorite;
    try {
      isFavorite = await ref
          .read(favoritesDaoProvider)
          .isFavorite(_id, kind, key);
    } on Object catch (e, st) {
      ref.read(ringLogProvider).error('Reading a favourite failed', e, st);
      return;
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final choice = await showOptionsSheet<bool>(
      context,
      title: title,
      options: [
        SheetOption(
          value: true,
          icon: isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
          label: isFavorite ? l10n.vodRemoveFavorite : l10n.vodAddFavorite,
        ),
      ],
    );
    if (!mounted || choice != true) return;
    await setFavorite(ref, _id, kind, key, !isFavorite);
  }

  void _open(VodTarget target) => unawaited(
    ref
        .read(playGateProvider)
        .run(() => ref.read(vodDetailNavigatorProvider)(context, ref, target)),
  );

  // -------------------------------------------------------------------------
  // Build.

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HomeTabBackHandler(
      onBack: _onBack,
      child: FocusTraversalGroup(
        policy: _policy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PaneScope(
              key: _fieldPane,
              debugLabel: 'search-field',
              onExitDown: _enterResults,
              child: Padding(
                padding: const EdgeInsets.all(Spacing.sm),
                child: TvTextField(
                  key: const ValueKey('search-field'),
                  controller: _controller,
                  focusNode: _fieldNode,
                  autofocus: !_inShell,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: l10n.navSearch,
                    hintText: l10n.commonSearchHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: _onChanged,
                  onSubmitted: _onSubmitted,
                ),
              ),
            ),
            SizedBox(
              height: 2,
              child: _searching
                  ? const LinearProgressIndicator(minHeight: 2)
                  : null,
            ),
            Expanded(
              child: PaneScope(
                key: _resultsPane,
                debugLabel: 'search-results',
                onExitUp: _enterField,
                child: _buildResults(l10n),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(AppLocalizations l10n) {
    if (_query.isEmpty) {
      return EmptyView(message: l10n.commonSearchHint, icon: Icons.search);
    }
    final results = _results;
    if (results.isEmpty) {
      return EmptyView(
        message: l10n.searchNoResults(_query),
        icon: Icons.search_off,
      );
    }
    final favorites =
        ref.watch(favoriteKeysProvider((_id, ContentKind.live))).value ??
        const <String>{};
    final large = isLargeLayout(context);
    final extent = large ? TvLayout.channelExtent : TvLayout.channelExtentPhone;
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final now = ref.read(clockProvider).now();
        return ListView(
          key: ValueKey('search-results-$_query'),
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          children: [
            if (results.channels.isNotEmpty) ...[
              SectionHeader(
                l10n.searchChannels,
                trailing: Text('${results.channels.length}'),
              ),
              for (final c in results.channels)
                SizedBox(
                  height: extent,
                  child: ChannelTile(
                    key: ValueKey('search-channel-${c.key}'),
                    focusNode: _nodeFor('channel:${c.key}'),
                    name: c.name,
                    number: c.num,
                    logoUrl: c.logo,
                    // Blank (not "no programme info") until it is known.
                    nowTitle: _store.has(c.key)
                        ? _store[c.key]?.now?.title
                        : '',
                    progress: programmeProgress(_store[c.key]?.now, now),
                    isFavorite: favorites.contains(c.key),
                    onSelect: () => unawaited(_playChannel(c)),
                    onMenu: () =>
                        unawaited(_channelMenu(c, favorites.contains(c.key))),
                    onFocusChange: (focused) {
                      if (focused) _store.pin(c.key);
                    },
                  ),
                ),
            ],
            if (results.movies.isNotEmpty) ...[
              SectionHeader(
                l10n.searchMovies,
                trailing: Text('${results.movies.length}'),
              ),
              _PosterRow(
                large: large,
                children: [
                  for (final m in results.movies)
                    PosterCard(
                      key: ValueKey('search-movie-${m.key}'),
                      focusNode: _nodeFor('movie:${m.key}'),
                      title: m.name,
                      posterUrl: m.poster,
                      onSelect: () =>
                          _open(VodTarget.movie(sourceId: _id, movie: m)),
                      onMenu: () =>
                          unawaited(_vodMenu(ContentKind.movie, m.key, m.name)),
                    ),
                ],
              ),
            ],
            if (results.series.isNotEmpty) ...[
              SectionHeader(
                l10n.searchSeries,
                trailing: Text('${results.series.length}'),
              ),
              _PosterRow(
                large: large,
                children: [
                  for (final s in results.series)
                    PosterCard(
                      key: ValueKey('search-series-${s.key}'),
                      focusNode: _nodeFor('series:${s.key}'),
                      title: s.name,
                      posterUrl: s.poster,
                      onSelect: () =>
                          _open(VodTarget.series(sourceId: _id, series: s)),
                      onMenu: () => unawaited(
                        _vodMenu(ContentKind.series, s.key, s.name),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: Spacing.lg),
          ],
        );
      },
    );
  }
}

/// A horizontal row of posters (at most [SearchView.limitPerKind]).
class _PosterRow extends StatelessWidget {
  const _PosterRow({required this.large, required this.children});

  final bool large;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final width = large ? 96.0 : 104.0;
    return SizedBox(
      height: PosterCard.heightForWidth(width) + Spacing.md,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: Spacing.md),
        itemBuilder: (context, i) => SizedBox(width: width, child: children[i]),
      ),
    );
  }
}
