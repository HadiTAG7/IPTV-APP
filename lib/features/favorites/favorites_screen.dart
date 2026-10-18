import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_shell.dart';
import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../epg/epg_providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../sources/models.dart';
import '../../theme/tokens.dart';
import '../../tv/focus_watchdog.dart';
import '../../tv/pane_scope.dart';
import '../../tv/tv_focusable.dart';
import '../../widgets/bidi_text.dart';
import '../../widgets/states.dart';
import '../channel_lists/channel_list_dialogs.dart';
import '../live/channel_list.dart';
import '../live/channel_source.dart';
import '../live/live_actions.dart';
import '../live/live_models.dart';
import '../live/now_next_store.dart';
import '../live/options_sheet.dart';
import '../live/preferred_focus.dart';
import '../live/providers.dart';
import '../sources/widgets/tv_buttons.dart';
import 'poster_grid.dart';
import 'providers.dart';
import 'vod_navigation.dart';

/// The parts of the Favorites screen.
enum FavoritesSegment { live, movies, series }

/// Favourite channels, movies and series of the active source, as three
/// segments. Live favourites play like channels (zapping within the
/// favourites); movies and series open through [vodDetailNavigatorProvider].
///
/// The user's own channel lists get a tab each after the live favourites;
/// "New list…" ends the row. A list plays like the favourites (zapping
/// within the list); its tab's options and the buttons above its channels
/// rename or delete it, and a channel's options move it up or down or
/// remove it.
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

  /// A new key for each channel list shown: a [ChannelList] keeps its list.
  GlobalKey<ChannelListState> _list = GlobalKey(debugLabel: 'favorites-list');
  final _tabNodes = {
    for (final s in FavoritesSegment.values)
      s: FocusNode(debugLabel: 'favorites-${s.name}'),
  };

  /// Tab nodes of the user's channel lists, by list id.
  final _listTabNodes = <int, FocusNode>{};
  final _newListNode = FocusNode(debugLabel: 'favorites-new-list');
  final _renameNode = FocusNode(debugLabel: 'favorites-list-rename');
  late final _policy = _FavoritesTraversalPolicy(_preferred, _upFrom);
  late final NowNextStore _store;
  FavoritesSegment _segment = FavoritesSegment.live;

  /// The user's channel list shown instead of the live favourites, if any
  /// ([_segment] is then [FavoritesSegment.live]).
  int? _listId;

  /// A list just created, whose tab takes focus once it is built.
  int? _focusListTab;
  int _liveVersion = 0;
  int _listVersion = 0;
  FocusWatchdogState? _watchdog;

  int get _id => widget.sourceId;

  /// The segment shown, for tests.
  @visibleForTesting
  FavoritesSegment get segment => _segment;

  /// The channel list shown, for tests.
  @visibleForTesting
  int? get listId => _listId;

  /// Inside a home shell tab (else a pushed page that focuses itself).
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
    for (final node in _listTabNodes.values) {
      node.dispose();
    }
    _newListNode.dispose();
    _renameNode.dispose();
    _store.dispose();
    super.dispose();
  }

  List<FocusNode?> _preferred() => [
    _tabsPane.currentState?.node,
    _currentTabNode,
    _list.currentState?.preferredNode,
    _grid.currentState?.firstNode,
  ];

  /// Up from a list's first channel goes to its first button (Rename);
  /// plain geometry would pick the button nearest the middle (Delete).
  FocusNode? _upFrom(FocusNode node) {
    final list = _list.currentState;
    if (_listId == null ||
        list == null ||
        list.currentIndex != 0 ||
        node != list.preferredNode ||
        !isAttached(_renameNode)) {
      return null;
    }
    return _renameNode;
  }

  FocusNode _listTabNode(int listId) => _listTabNodes.putIfAbsent(
    listId,
    () => FocusNode(debugLabel: 'favorites-list-$listId'),
  );

  /// The tab of what is shown.
  FocusNode get _currentTabNode {
    final listId = _listId;
    return listId == null ? _tabNodes[_segment]! : _listTabNode(listId);
  }

  void _show(FavoritesSegment segment, {bool enter = false}) {
    if (segment != _segment || _listId != null) {
      setState(() {
        if (_listId != null) _list = GlobalKey(debugLabel: 'favorites-list');
        _segment = segment;
        _listId = null;
      });
    }
    if (enter) afterNextFrame(_enterContent);
  }

  /// Shows the user's channel list [listId].
  void _showList(int listId, {bool enter = false}) {
    if (listId != _listId) {
      setState(() {
        _list = GlobalKey(debugLabel: 'favorites-list');
        _segment = FavoritesSegment.live;
        _listId = listId;
      });
    }
    if (enter) afterNextFrame(_enterContent);
  }

  void _enterContent() {
    if (_segment == FavoritesSegment.live) {
      // A list without channels still has its Rename and Delete buttons.
      if (!(_list.currentState?.focusCurrent() ?? false) && _listId != null) {
        _contentPane.currentState?.requestFocus();
      }
    } else {
      _contentPane.currentState?.requestFocus();
    }
  }

  void _enterTabs() => _currentTabNode.requestFocus();

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
        SheetOption(
          value: LiveChannelAction.addToList,
          icon: Icons.playlist_add_rounded,
          label: l10n.liveAddToList,
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
      case LiveChannelAction.addToList:
        await showAddToListDialog(
          context,
          ref,
          sourceId: _id,
          channelKey: entry.key,
        );
      case LiveChannelAction.otherPlayer:
        await _playWithOtherEngine(source, row!);
      case LiveChannelAction.moveUp ||
          LiveChannelAction.moveDown ||
          LiveChannelAction.removeFromList ||
          null:
        break;
    }
  }

  Future<void> _playWithOtherEngine(ChannelListSource source, ChannelRow row) =>
      ref.read(playGateProvider).run(() async {
        final request = await source.requestFor(row);
        if (!mounted) return;
        await playWithOtherEngine(context, ref, request);
      });

  // -------------------------------------------------------------------------
  // The user's channel lists.

  /// The list shown, once the lists have loaded.
  ChannelListRow? get _shownList {
    final listId = _listId;
    if (listId == null) return null;
    final lists = ref.read(channelListsProvider(_id)).value;
    return lists?.where((l) => l.id == listId).firstOrNull;
  }

  /// Options of a channel in the list shown: move up or down, remove, add
  /// to a list, play with the other player.
  Future<void> _listChannelMenu(
    ChannelListSource source,
    LiveEntry entry,
  ) async {
    final list = _shownList;
    if (list == null) return;
    final l10n = AppLocalizations.of(context);
    final dao = ref.read(channelListsDaoProvider);
    final List<String> keys;
    try {
      keys = await dao.channelKeys(list.id);
    } on Object catch (e, st) {
      ref.read(ringLogProvider).error('Reading a channel list failed', e, st);
      return;
    }
    if (!mounted) return;
    final index = keys.indexOf(entry.key);
    final row = entry.row;
    final choice = await showOptionsSheet<LiveChannelAction>(
      context,
      title: row?.name ?? l10n.commonUnavailable,
      options: [
        if (index > 0)
          SheetOption(
            value: LiveChannelAction.moveUp,
            icon: Icons.arrow_upward_rounded,
            label: l10n.liveMoveUp,
          ),
        if (index >= 0 && index < keys.length - 1)
          SheetOption(
            value: LiveChannelAction.moveDown,
            icon: Icons.arrow_downward_rounded,
            label: l10n.liveMoveDown,
          ),
        SheetOption(
          value: LiveChannelAction.removeFromList,
          icon: Icons.playlist_remove_rounded,
          label: l10n.liveRemoveFromList(list.name),
        ),
        SheetOption(
          value: LiveChannelAction.addToList,
          icon: Icons.playlist_add_rounded,
          label: l10n.liveAddToList,
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
    // Focus stays with the channel: the list re-reads and follows its key
    // after a move, or keeps the row after a removal (onEmptied takes the
    // last one).
    try {
      switch (choice) {
        case LiveChannelAction.moveUp:
          await dao.moveChannel(list.id, entry.key, -1);
        case LiveChannelAction.moveDown:
          await dao.moveChannel(list.id, entry.key, 1);
        case LiveChannelAction.removeFromList:
          await dao.setChannel(list.id, entry.key, false);
        case LiveChannelAction.addToList:
          await showAddToListDialog(
            context,
            ref,
            sourceId: _id,
            channelKey: entry.key,
          );
        case LiveChannelAction.otherPlayer:
          await _playWithOtherEngine(source, row!);
        case LiveChannelAction.favorite || null:
          break;
      }
    } on Object catch (e, st) {
      if (mounted) {
        ref
            .read(ringLogProvider)
            .error('Changing a channel list failed', e, st);
      }
    }
  }

  /// "New list…": names and creates a list, then shows it with its tab
  /// focused.
  Future<void> _createList() async {
    final listId = await createChannelList(context, ref, _id);
    if (listId == null || !mounted) return;
    _focusListTab = listId;
    _showList(listId);
  }

  /// Deletes [list] (the one shown) once confirmed. Focus and the selection
  /// move to the tab before it (the previous list, or the live favourites)
  /// first: the dialog would hand focus back to the list's tab or button,
  /// which go with it.
  Future<void> _deleteList(ChannelListRow list) async {
    final dao = ref.read(channelListsDaoProvider);
    final log = ref.read(ringLogProvider);
    if (!await confirmDeleteChannelList(context, list) || !mounted) return;
    if (_listId == list.id) {
      final lists = ref.read(channelListsProvider(_id)).value ?? const [];
      final i = lists.indexWhere((l) => l.id == list.id);
      final before = i > 0 ? lists[i - 1] : null;
      if (before == null) {
        _tabNodes[FavoritesSegment.live]!.requestFocus();
        _show(FavoritesSegment.live);
      } else {
        _listTabNode(before.id).requestFocus();
        _showList(before.id);
      }
    }
    try {
      await dao.deleteList(list.id);
    } on Object catch (e, st) {
      log.error('Deleting a channel list failed', e, st);
    }
  }

  /// A list tab's options (Menu or a long press): rename, delete.
  Future<void> _listMenu(ChannelListRow list) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showOptionsSheet<bool>(
      context,
      title: list.name,
      options: [
        SheetOption(
          value: false,
          icon: Icons.edit_outlined,
          label: l10n.liveRenameList,
        ),
        SheetOption(
          value: true,
          icon: Icons.delete_outline_rounded,
          label: l10n.liveDeleteList,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice) {
      await _deleteList(list);
    } else {
      await renameChannelList(context, ref, list);
    }
  }

  /// The lists changed. When the one shown left (deleted elsewhere) the
  /// live favourites show instead; focus on its tab or channels moves to
  /// their tab first, before those widgets go.
  void _onListsChanged(List<ChannelListRow>? lists) {
    final listId = _listId;
    if (lists == null || listId == null || lists.any((l) => l.id == listId)) {
      return;
    }
    if ((_contentPane.currentState?.hasFocus ?? false) ||
        (_listTabNodes[listId]?.hasFocus ?? false)) {
      _tabNodes[FavoritesSegment.live]!.requestFocus();
    }
    _show(FavoritesSegment.live);
  }

  /// Drops the tab nodes of lists that are gone (once their tabs left the
  /// tree) and focuses a just created list's tab once it is built.
  void _syncListTabs(List<ChannelListRow> lists) {
    final ids = {for (final l in lists) l.id};
    final gone = [
      for (final MapEntry(:key, :value) in _listTabNodes.entries)
        if (!ids.contains(key) && !value.hasFocus) key,
    ];
    if (gone.isNotEmpty) {
      final nodes = [for (final id in gone) _listTabNodes.remove(id)!];
      afterNextFrame(() {
        for (final node in nodes) {
          node.dispose();
        }
      });
    }
    final focus = _focusListTab;
    if (focus != null && ids.contains(focus)) {
      _focusListTab = null;
      afterNextFrame(() {
        if (mounted && _listId == focus) _listTabNode(focus).requestFocus();
      });
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
    ref.listen(
      channelListsProvider(_id),
      (_, next) => _onListsChanged(next.value),
    );
    final listId = _listId;
    if (listId != null) {
      ref.listen(channelListKeysProvider(listId), (prev, next) {
        final before = prev?.value;
        final after = next.value;
        if (before == null || after == null || listEquals(before, after)) {
          return;
        }
        // Its last channel left: focus goes to the list's buttons before
        // the rows go.
        if (after.isEmpty && (_contentPane.currentState?.hasFocus ?? false)) {
          _renameNode.requestFocus();
        }
        if (_listId == listId) setState(() => _listVersion++);
      });
    }
    final lists = ref.watch(channelListsProvider(_id)).value;
    if (lists != null) _syncListTabs(lists);
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
    final (content, empty) = listId != null
        ? _buildList(l10n, lists?.where((l) => l.id == listId).firstOrNull)
        : switch (_segment) {
            FavoritesSegment.live => _buildChannels(l10n),
            FavoritesSegment.movies => _buildMovies(l10n),
            FavoritesSegment.series => _buildSeries(l10n),
          };
    final contentKey = listId != null ? 'list-$listId' : _segment.name;
    Widget segmentTab(FavoritesSegment s) => Padding(
      padding: const EdgeInsetsDirectional.only(end: Spacing.sm),
      child: _SegmentTab(
        key: ValueKey('favorites-tab-${s.name}'),
        focusNode: _tabNodes[s]!,
        label: labels[s]!,
        count: counts[s],
        selected: listId == null && s == _segment,
        autofocus: autofocus && listId == null && s == _segment,
        onFocus: () => _show(s),
        onSelect: () => _show(s, enter: true),
      ),
    );
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
              // Scrolls sideways once the user's lists fill the row.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
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
                    segmentTab(FavoritesSegment.live),
                    for (final list in lists ?? const <ChannelListRow>[])
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: Spacing.sm,
                        ),
                        child: _SegmentTab(
                          key: ValueKey('favorites-tab-list-${list.id}'),
                          focusNode: _listTabNode(list.id),
                          label: list.name,
                          count: list.count,
                          selected: list.id == listId,
                          icon: Icons.playlist_play_rounded,
                          onFocus: () => _showList(list.id),
                          onSelect: () => _showList(list.id, enter: true),
                          onMenu: () => unawaited(_listMenu(list)),
                        ),
                      ),
                    segmentTab(FavoritesSegment.movies),
                    segmentTab(FavoritesSegment.series),
                    if (lists != null)
                      _SegmentTab(
                        key: const ValueKey('favorites-tab-new-list'),
                        focusNode: _newListNode,
                        label: l10n.liveNewList,
                        selected: false,
                        icon: Icons.add_rounded,
                        onSelect: () => unawaited(_createList()),
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
                      key: ValueKey('favorites-$contentKey-empty'),
                      child: content,
                    )
                  : PaneScope(
                      key: _contentPane,
                      debugLabel: 'favorites-content',
                      onExitUp: _enterTabs,
                      child: KeyedSubtree(
                        key: ValueKey('favorites-$contentKey'),
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

  /// One of the user's channel lists: Rename and Delete, then its channels
  /// (or how to add some). Never empty: the buttons can take focus.
  (Widget, bool) _buildList(AppLocalizations l10n, ChannelListRow? list) {
    if (list == null) return (const LoadingView(), false);
    final keys = ref.watch(channelListKeysProvider(list.id)).value;
    final Widget body;
    if (keys != null && keys.isEmpty) {
      body = EmptyView(
        message: l10n.liveListEmpty,
        icon: Icons.playlist_add_rounded,
      );
    } else {
      final favorites =
          ref.watch(favoriteKeysProvider((_id, ContentKind.live))).value ??
          const <String>{};
      final recent = ref.watch(recentChannelKeysProvider(_id)).value;
      body = ChannelList(
        key: _list,
        sourceId: _id,
        list: LiveList.channelList(list.id),
        store: _store,
        itemExtent: isLargeLayout(context)
            ? TvLayout.channelExtent
            : TvLayout.channelExtentPhone,
        favorites: favorites,
        playingKey: recent?.firstOrNull,
        dataVersion: _listVersion,
        onPlay: _playChannel,
        onMenu: _listChannelMenu,
        onEmptied: (hadFocus, _) {
          if (hadFocus || (_contentPane.currentState?.hasFocus ?? false)) {
            _renameNode.requestFocus();
          }
        },
        emptyMessage: l10n.liveListEmpty,
        emptyIcon: Icons.playlist_add_rounded,
      );
    }
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Spacing.md,
            Spacing.xxs,
            Spacing.md,
            Spacing.sm,
          ),
          child: Row(
            children: [
              TvButton(
                key: const ValueKey('favorites-list-rename'),
                focusNode: _renameNode,
                icon: Icons.edit_outlined,
                label: l10n.liveRenameList,
                height: 40,
                onSelect: () =>
                    unawaited(renameChannelList(context, ref, list)),
              ),
              const SizedBox(width: Spacing.sm),
              TvButton(
                key: const ValueKey('favorites-list-delete'),
                icon: Icons.delete_outline_rounded,
                label: l10n.liveDeleteList,
                height: 40,
                onSelect: () => unawaited(_deleteList(list)),
              ),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
    return (column, false);
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

/// [PreferredFirstTraversalPolicy] where [upFrom] can name the node Up
/// moves to instead of the geometric choice.
class _FavoritesTraversalPolicy extends PreferredFirstTraversalPolicy {
  _FavoritesTraversalPolicy(super.preferred, this.upFrom);

  final FocusNode? Function(FocusNode currentNode) upFrom;

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final target = direction == TraversalDirection.up
        ? upFrom(currentNode)
        : null;
    if (target != null) {
      target.requestFocus();
      return true;
    }
    return super.inDirection(currentNode, direction);
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
    required this.onSelect,
    this.onFocus,
    this.onMenu,
    this.icon,
    this.count,
    this.autofocus = false,
  });

  final FocusNode focusNode;
  final String label;
  final int? count;
  final IconData? icon;
  final bool selected;
  final bool autofocus;

  /// Called when the tab gets focus (it shows its content at once).
  final VoidCallback? onFocus;
  final VoidCallback onSelect;
  final VoidCallback? onMenu;

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
        if (focused) onFocus?.call();
      },
      onSelect: onSelect,
      onMenu: onMenu,
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
            if (icon case final icon?) ...[
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: Spacing.xs),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: BidiText(
                label,
                maxLines: 1,
                style: style?.copyWith(color: fg),
              ),
            ),
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
