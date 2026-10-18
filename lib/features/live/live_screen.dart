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
import '../../tv/pane_scope.dart';
import '../../widgets/states.dart';
import '../channel_lists/channel_list_dialogs.dart';
import 'category_chips.dart';
import 'category_pane.dart';
import 'channel_list.dart';
import 'channel_source.dart';
import 'info_pane.dart';
import 'live_actions.dart';
import 'live_models.dart';
import 'now_next_store.dart';
import 'options_sheet.dart';
import 'preferred_focus.dart';
import 'providers.dart';

/// Live channels of the active source.
///
/// The category list starts with Favorites and the user's own channel lists
/// (in list order, each zapping within itself), then Recent, All channels
/// and the provider's categories.
///
/// * Large layout (TV, desktop, wide landscape): three panes, categories
///   (about 25 %), channels (45 %) and info (30 %), each a [PaneScope]; the
///   arrows cross between them (mirrored in Arabic) and each pane remembers
///   its item. Entering the page lands on the current channel.
/// * Phone layout: category chips over the channel list; tap plays.
///
/// Renders body content only; the home shells provide the chrome.
class LiveScreen extends ConsumerWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceId = ref.watch(activeSourceIdProvider);
    if (sourceId == null) return const LoadingView();
    return LiveView(key: ValueKey('live-source-$sourceId'), sourceId: sourceId);
  }
}

/// The Live screen for one source (see [LiveScreen]).
class LiveView extends ConsumerStatefulWidget {
  const LiveView({super.key, required this.sourceId});

  /// Focus rests this long on a category before its channels load.
  static const selectDelay = Duration(milliseconds: 300);

  /// Focus rests this long on a channel before the info pane follows.
  static const infoDelay = Duration(milliseconds: 250);

  final int sourceId;

  @override
  ConsumerState<LiveView> createState() => LiveViewState();
}

class LiveViewState extends ConsumerState<LiveView> {
  final _catsPane = GlobalKey<PaneScopeState>();
  final _channelsPane = GlobalKey<PaneScopeState>();
  final _infoPane = GlobalKey<PaneScopeState>();
  final _categories = GlobalKey<LiveCategoryPaneState>();
  final _info = GlobalKey<LiveInfoPaneState>();
  GlobalKey<ChannelListState> _list = GlobalKey(debugLabel: 'live-list');
  late final _policy = PreferredFirstTraversalPolicy(_preferred);
  late final NowNextStore _store;

  LiveList? _selected;
  LiveList? _pending;
  String? _openKey;

  /// Channel the next list opens on instead of the last played one (set
  /// when a list is swapped under the user, to keep their place).
  String? _keepKey;
  bool _ready = false;
  LiveEntry? _infoEntry;
  Timer? _infoTimer;
  Timer? _selectTimer;
  int _dataVersion = 0;

  int get _id => widget.sourceId;

  /// The list shown, for tests.
  @visibleForTesting
  LiveList? get selected => _selected;

  /// The channel list's state, for tests.
  @visibleForTesting
  ChannelListState? get channelList => _list.currentState;

  /// The now/next store, for tests.
  @visibleForTesting
  NowNextStore get nowNext => _store;

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
    unawaited(_init());
  }

  Future<void> _init() async {
    String? saved;
    String? last;
    try {
      saved = await ref
          .read(settingsDaoProvider)
          .getString(liveLastListKey(_id));
      last =
          (await ref.read(recentDaoProvider).recentChannelKeys(_id, limit: 1))
              .firstOrNull;
    } on Object catch (e, st) {
      ref.read(ringLogProvider).error('Reading the Live state failed', e, st);
    }
    if (!mounted) return;
    setState(() {
      _selected = LiveList.fromId(saved) ?? const LiveList.all();
      _openKey = last;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _infoTimer?.cancel();
    _selectTimer?.cancel();
    _store.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Selection and focus.

  /// Shows [list]; with [enter], focus moves into it. [keepKey] opens the
  /// new list on that channel (when listed) rather than the last played one.
  void _select(LiveList list, {bool enter = false, String? keepKey}) {
    _selectTimer?.cancel();
    _pending = null;
    if (list != _selected) {
      setState(() {
        _selected = list;
        _keepKey = keepKey;
        _list = GlobalKey(debugLabel: 'live-list');
        _infoEntry = null;
      });
      _store.pin(null);
      unawaited(
        ref
            .read(settingsDaoProvider)
            .setString(liveLastListKey(_id), list.id)
            .catchError((Object _) {}),
      );
    }
    if (enter) afterNextFrame(() => _list.currentState?.focusCurrent());
  }

  void _onCategoryFocus(LiveList list) {
    _selectTimer?.cancel();
    if (list == _selected) {
      _pending = null;
      return;
    }
    // The user moved on: the list shown must not pull focus back into its
    // rows once they have loaded.
    _list.currentState?.cancelPendingFocus();
    _pending = list;
    _selectTimer = Timer(LiveView.selectDelay, () {
      if (mounted) _select(list);
    });
  }

  /// Categories -> channels (commits a pending category first). A list
  /// without rows may still offer Retry.
  void _enterChannels() {
    final pending = _pending;
    if (pending != null) {
      _select(pending, enter: true);
      return;
    }
    if (_list.currentState?.focusCurrent() ?? false) return;
    _channelsPane.currentState?.requestFocus();
  }

  void _enterCategories() => _catsPane.currentState?.requestFocus();

  /// Before [list]'s category entry goes (hidden or deleted from its menu).
  /// When the entry was [focused] (the menu came from the remote), focus
  /// moves to its neighbour and the list shown gives way to All channels;
  /// a pending switch to it is dropped. A menu opened by a mouse or touch
  /// long press on another entry leaves focus and the list shown alone:
  /// when [list] is the one shown, [_onSelectedGone] takes over once it has
  /// gone, and focus in the channels follows into All.
  void _beforeEntryGoes(LiveList list, {required bool focused}) {
    if (_pending == list) {
      _selectTimer?.cancel();
      _pending = null;
    }
    if (!focused) return;
    if (_selected == list) _select(const LiveList.all());
    _categories.currentState?.focusNeighbourOf(list);
  }

  /// Info -> channels, or the categories when the list has no rows (it
  /// emptied while the info pane had focus).
  void _leaveInfo() {
    if (_list.currentState?.focusCurrent() ?? false) return;
    _focusSelectedCategory();
  }

  /// Focuses the entry of the list shown (not just the pane's remembered
  /// entry, which may have gone).
  void _focusSelectedCategory() {
    final cats = _categories.currentState;
    final selected = _selected;
    if (cats != null && selected != null && cats.hasEntry(selected)) {
      cats.focusList(selected);
    } else {
      _enterCategories();
    }
  }

  bool get _contentHasFocus =>
      (_channelsPane.currentState?.hasFocus ?? false) ||
      (_infoPane.currentState?.hasFocus ?? false);

  /// Channels -> info: shows the focused channel at once, then enters.
  void _enterInfo() {
    final entry = _list.currentState?.currentEntry;
    if (entry?.row == null) return;
    _infoTimer?.cancel();
    setState(() => _infoEntry = entry);
    _store.pin(entry!.key);
    afterNextFrame(() => _infoPane.currentState?.requestFocus());
  }

  void _onFocusEntry(LiveEntry? entry) {
    _infoTimer?.cancel();
    _infoTimer = Timer(LiveView.infoDelay, () {
      if (!mounted) return;
      setState(() => _infoEntry = entry);
      _store.pin(entry?.row?.key);
    });
  }

  /// The list has no rows any more (favourites removed, a sync emptied or
  /// removed its category). Focus in the channel or info pane must not be
  /// stranded there: a provider category falls back to All channels on the
  /// same channel; Favorites, the user's lists and Recent stay (they say how
  /// to fill them) and focus goes to their entry.
  void _onListEmptied(bool hadFocus, String? lastKey) {
    if (!mounted) return;
    final large = isLargeLayout(context);
    final focused = large && (hadFocus || _contentHasFocus);
    final selected = _selected;
    if (focused) {
      if (selected != null && selected.isCategory) {
        _select(const LiveList.all(), enter: true, keepKey: lastKey);
        return;
      }
      _focusSelectedCategory();
    }
    // The channel shown in the info pane is no longer listed. Its buttons
    // go once focus has left them (the request above applies first).
    _infoTimer?.cancel();
    if (_infoEntry != null) setState(() => _infoEntry = null);
    _store.pin(null);
  }

  /// The list shown is gone (a sync dropped its category, or it was hidden
  /// elsewhere): show All channels. Focus in the channel or info pane
  /// follows into All on the same channel; a category being hovered still
  /// opens after its pause.
  void _onSelectedGone() {
    final inContent = isLargeLayout(context) && _contentHasFocus;
    final key = inContent
        ? (_list.currentState?.currentEntry?.key ?? _infoEntry?.key)
        : null;
    final pending = _pending;
    _select(const LiveList.all(), enter: inContent, keepKey: key);
    if (pending != null &&
        (_categories.currentState?.hasEntry(pending) ?? false)) {
      _onCategoryFocus(pending);
    }
  }

  /// The focused category left the list (a sync): focus goes to the list
  /// shown, which is All channels when that was the one that left (see
  /// [_onSelectedGone], which runs first), never to the first entry, which
  /// would open Favorites after the pause.
  void _onFocusedCategoryGone() {
    final pending = _pending;
    if (pending != null &&
        !(_categories.currentState?.hasEntry(pending) ?? false)) {
      _selectTimer?.cancel();
      _pending = null;
    }
    _focusSelectedCategory();
  }

  List<FocusNode?> _preferred() {
    final list = _list.currentState;
    final row = list?.preferredNode;
    return [
      row != null
          ? _channelsPane.currentState?.node
          : _catsPane.currentState?.node,
      row,
      _categories.currentState?.selectedNode,
      _info.currentState?.playNode,
    ];
  }

  bool _onBack() {
    final list = _list.currentState;
    if (list?.clearDigits() ?? false) return true;
    if (!isLargeLayout(context)) return false;
    if (_infoPane.currentState?.hasFocus ?? false) {
      _leaveInfo();
      return true;
    }
    if (_channelsPane.currentState?.hasFocus ?? false) {
      _enterCategories();
      return true;
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Actions.

  /// Runs [open] (which shows the player) and then puts focus on the channel
  /// played last, which may differ after zapping in the player.
  Future<void> _withPlayer(Future<void> Function() open) async {
    final wasFocused = _list.currentState?.hasFocus ?? false;
    await open();
    if (!mounted) return;
    final recent = ref.read(recentDaoProvider);
    final last = (await recent.recentChannelKeys(_id, limit: 1)).firstOrNull;
    if (!mounted) return;
    await _list.currentState?.refresh(focusKey: last, focus: wasFocused);
  }

  Future<void> _play(ChannelListSource source, LiveEntry entry) {
    final row = entry.row;
    if (row == null) return Future.value();
    return ref.read(playGateProvider).run(() async {
      final request = await source.requestFor(row);
      if (!mounted) return;
      await _withPlayer(() => playLiveChannel(context, ref, request));
    });
  }

  Future<void> _toggleFavorite(LiveEntry entry) {
    final favorites =
        ref.read(favoriteKeysProvider((_id, ContentKind.live))).value ??
        const <String>{};
    return setFavorite(
      ref,
      _id,
      ContentKind.live,
      entry.key,
      !favorites.contains(entry.key),
    );
  }

  Future<void> _channelMenu(ChannelListSource source, LiveEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final favorites =
        ref.read(favoriteKeysProvider((_id, ContentKind.live))).value ??
        const <String>{};
    final isFavorite = favorites.contains(entry.key);
    final row = entry.row;
    final choice = await showOptionsSheet<LiveChannelAction>(
      context,
      title: row?.name ?? l10n.commonUnavailable,
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
        await setFavorite(ref, _id, ContentKind.live, entry.key, !isFavorite);
      case LiveChannelAction.addToList:
        await showAddToListDialog(
          context,
          ref,
          sourceId: _id,
          channelKey: entry.key,
        );
      case LiveChannelAction.otherPlayer:
        await ref.read(playGateProvider).run(() async {
          final request = await source.requestFor(row!);
          if (!mounted) return;
          await _withPlayer(() => playWithOtherEngine(context, ref, request));
        });
      case LiveChannelAction.moveUp ||
          LiveChannelAction.moveDown ||
          LiveChannelAction.removeFromList ||
          null:
        break;
    }
  }

  Future<void> _categoryMenu(LiveCategoryEntry entry) async {
    final l10n = AppLocalizations.of(context);
    // Read before the sheet takes focus: a remote's Menu key opens it on
    // the focused entry, a long press on any entry.
    final entryFocused =
        _categories.currentState?.hasFocusOn(entry.list) ?? false;
    final rows = ref.read(liveCategoriesProvider(_id)).value ?? const [];
    final anyHidden = rows.any((c) => c.hidden);
    final listId = entry.list.listId;
    final userList = listId == null
        ? null
        : (ref.read(channelListsProvider(_id)).value ?? const [])
              .where((l) => l.id == listId)
              .firstOrNull;
    final choice = await showOptionsSheet<LiveCategoryAction>(
      context,
      title: entry.name,
      options: [
        if (entry.list.isCategory)
          SheetOption(
            value: LiveCategoryAction.hide,
            icon: Icons.visibility_off_outlined,
            label: l10n.liveHideCategory,
          ),
        if (userList != null) ...[
          SheetOption(
            value: LiveCategoryAction.renameList,
            icon: Icons.edit_outlined,
            label: l10n.liveRenameList,
          ),
          SheetOption(
            value: LiveCategoryAction.deleteList,
            icon: Icons.delete_outline_rounded,
            label: l10n.liveDeleteList,
          ),
        ],
        if (anyHidden)
          SheetOption(
            value: LiveCategoryAction.showHidden,
            icon: Icons.visibility_outlined,
            label: l10n.liveShowHiddenCategories,
          ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case LiveCategoryAction.hide:
        _beforeEntryGoes(entry.list, focused: entryFocused);
        await setLiveCategoryHidden(ref, _id, entry.list.categoryKey!, true);
      case LiveCategoryAction.showHidden:
        await showHiddenLiveCategories(ref, _id);
      case LiveCategoryAction.renameList:
        await renameChannelList(context, ref, userList!);
      case LiveCategoryAction.deleteList:
        final dao = ref.read(channelListsDaoProvider);
        final log = ref.read(ringLogProvider);
        if (!await confirmDeleteChannelList(context, userList!) || !mounted) {
          return;
        }
        _beforeEntryGoes(entry.list, focused: entryFocused);
        try {
          await dao.deleteList(userList.id);
        } on Object catch (e, st) {
          log.error('Deleting a channel list failed', e, st);
        }
      case null:
        break;
    }
  }

  // -------------------------------------------------------------------------
  // Build.

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen(sourceGenerationProvider(_id), (previous, next) {
      if (previous == next) return;
      // The now/next on screen stays until it is read again.
      unawaited(_store.reload());
      setState(() => _dataVersion++);
    });
    ref.listen(favoriteKeysProvider((_id, ContentKind.live)), (prev, next) {
      final before = prev?.value;
      final after = next.value;
      if (before == null || after == null || setEquals(before, after)) return;
      if (_selected?.kind == LiveListKind.favorites) {
        setState(() => _dataVersion++);
      }
    });
    final listId = _selected?.listId;
    if (listId != null) {
      // The list shown changed (here, in Favorites or in the player).
      ref.listen(channelListKeysProvider(listId), (prev, next) {
        final before = prev?.value;
        final after = next.value;
        if (before == null || after == null || listEquals(before, after)) {
          return;
        }
        if (_selected?.listId == listId) setState(() => _dataVersion++);
      });
    }
    final categories = ref.watch(liveCategoriesProvider(_id));
    final listRows = ref.watch(channelListsProvider(_id));
    final favorites =
        ref.watch(favoriteKeysProvider((_id, ContentKind.live))).value ??
        const <String>{};
    final recent =
        ref.watch(recentChannelKeysProvider(_id)).value ?? const <String>[];
    final total = ref.watch(liveChannelCountProvider(_id)).value ?? 0;
    final selected = _selected;
    if (categories.hasError && !categories.hasValue) {
      return ErrorView(
        onRetry: () => ref.invalidate(liveCategoriesProvider(_id)),
        autofocusRetry: false,
      );
    }
    final rows = categories.value;
    // Wait for the user's lists too: without them a saved list would look
    // gone. They are only extra entries, so a failed read shows none.
    final lists =
        listRows.value ?? (listRows.hasError ? const <ChannelListRow>[] : null);
    if (!_ready || selected == null || rows == null || lists == null) {
      return const LoadingView();
    }
    final entries = liveCategoryEntries(
      l10n,
      categories: rows,
      lists: lists,
      favorites: favorites.length,
      recent: recent.length,
      total: total,
    );
    if (!entries.any((e) => e.list == selected)) {
      // The saved or shown category is gone or hidden: show all channels.
      afterNextFrame(() {
        if (mounted && _selected == selected) _onSelectedGone();
      });
    }
    final list = ChannelList(
      key: _list,
      sourceId: _id,
      list: selected,
      store: _store,
      initialKey: _keepKey ?? recent.firstOrNull ?? _openKey,
      itemExtent: isLargeLayout(context)
          ? TvLayout.channelExtent
          : TvLayout.channelExtentPhone,
      favorites: favorites,
      playingKey: recent.firstOrNull,
      dataVersion: _dataVersion,
      onPlay: _play,
      onMenu: _channelMenu,
      onFocusEntry: _onFocusEntry,
      onEmptied: _onListEmptied,
      emptyMessage: ChannelList.emptyMessageFor(l10n, selected),
      emptyIcon: ChannelList.emptyIconFor(selected),
    );
    return HomeTabBackHandler(
      onBack: _onBack,
      child: isLargeLayout(context)
          ? _buildLarge(entries, selected, list, favorites)
          : _buildPhone(entries, selected, list),
    );
  }

  Widget _buildLarge(
    List<LiveCategoryEntry> entries,
    LiveList selected,
    Widget list,
    Set<String> favorites,
  ) {
    final info = _infoEntry;
    return FocusTraversalGroup(
      policy: _policy,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(top: Spacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 25,
              child: PaneScope(
                key: _catsPane,
                debugLabel: 'live-categories',
                onExitEnd: _enterChannels,
                child: LiveCategoryPane(
                  key: _categories,
                  entries: entries,
                  selected: _pending ?? selected,
                  onFocusList: _onCategoryFocus,
                  onSelectList: (l) => _select(l, enter: true),
                  onMenu: _categoryMenu,
                  onFocusedEntryGone: _onFocusedCategoryGone,
                ),
              ),
            ),
            const SizedBox(width: Spacing.xs),
            Expanded(
              flex: 45,
              child: PaneScope(
                key: _channelsPane,
                debugLabel: 'live-channels',
                onExitStart: _enterCategories,
                onExitEnd: _enterInfo,
                child: list,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              flex: 30,
              child: PaneScope(
                key: _infoPane,
                debugLabel: 'live-info',
                onExitStart: _leaveInfo,
                child: LiveInfoPane(
                  key: _info,
                  entry: info,
                  store: _store,
                  isFavorite: info != null && favorites.contains(info.key),
                  onPlay: info?.row == null ? null : () => _playEntry(info!),
                  onToggleFavorite: info == null
                      ? null
                      : () => unawaited(_toggleFavorite(info)),
                  onOptions: info == null ? null : () => _optionsFor(info),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The list's source, for actions started from the info pane.
  ChannelListSource? get _source {
    final db = ref.read(databaseProvider);
    final selected = _selected;
    return selected == null ? null : channelSourceFor(db, _id, selected);
  }

  Future<void> _playEntry(LiveEntry entry) async {
    final source = _source;
    if (source == null || ref.read(playGateProvider).busy) return;
    await source.count(); // keyed sources load their keys here
    if (!mounted) return;
    await _play(source, entry);
  }

  Future<void> _optionsFor(LiveEntry entry) async {
    final source = _source;
    if (source == null) return;
    await source.count();
    if (!mounted) return;
    await _channelMenu(source, entry);
  }

  Widget _buildPhone(
    List<LiveCategoryEntry> entries,
    LiveList selected,
    Widget list,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LiveCategoryChips(
          entries: entries,
          selected: selected,
          onSelectList: _select,
          onMenu: _categoryMenu,
        ),
        Expanded(child: list),
      ],
    );
  }
}
