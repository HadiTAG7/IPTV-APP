import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/form_factor.dart';
import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../epg/epg_providers.dart';
import '../../features/live/category_pane.dart';
import '../../features/live/channel_list.dart';
import '../../features/live/live_models.dart';
import '../../features/live/now_next_store.dart';
import '../../features/live/preferred_focus.dart';
import '../../features/live/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../sources/models.dart';
import '../../theme/tokens.dart';
import '../../tv/pane_scope.dart';
import '../../widgets/states.dart';
import 'player_overlays.dart';

const _panelColor = Color(0xEB0B0E13);

/// Called with a channel of the panel and whether it is a favourite.
typedef PanelChannelCallback = void Function(LiveEntry entry, bool favorite);

/// The live player's channel panel: the Live screen's lists and their
/// channels over the start edge of the video, which keeps playing behind.
///
/// * Two columns, each a [PaneScope]: the categories (the entries of the
///   Live screen's category pane: Favorites, the user's own lists, Recent,
///   All channels and the visible provider categories) and the channels of
///   the selected one ([ChannelList]: read from the database in pages, each
///   row with number, logo, name and the programme on air).
/// * Opens on [list] and the channel [playingKey]. Focusing a category
///   shows its channels after [selectDelay]; OK shows them at once and
///   moves into them. Left/Right cross between the columns (mirrored in
///   Arabic).
/// * OK, a click or a tap on a channel reports [onTune]; Menu (or a held
///   OK) on a channel reports [onChannelMenu]. Clicks and taps beside the
///   panel, and its close button (mouse and touch), report [onClose].
/// * About [widthFraction] of the width on large layouts (TV, desktop, wide
///   tablets); the whole screen on phones.
///
/// The player owns Back, the auto-hide timer and tuning. Pointer activity
/// on the panel reports [onActivity].
class ChannelPanel extends ConsumerStatefulWidget {
  const ChannelPanel({
    super.key,
    required this.sourceId,
    required this.list,
    required this.playingKey,
    required this.onTune,
    required this.onClose,
    this.onChannelMenu,
    this.onActivity,
  });

  /// Focus rests this long on a category before its channels show.
  static const selectDelay = Duration(milliseconds: 300);

  /// Share of the screen width the side panel takes (plus the TV overscan
  /// margin), within [minWidth] and [maxWidth].
  static const widthFraction = 0.45;
  static const minWidth = 360.0;
  static const maxWidth = 560.0;

  /// TV: a wider panel with a fixed category column, so channel names
  /// (variants like "beIN SPORTS 1 HD" next to "… FHD") show in full on
  /// the 960-wide TV canvas.
  static const tvWidthFraction = 0.575;
  static const tvMaxWidth = 620.0;
  static const tvCategoryWidth = 184.0;

  /// Pointer input is ignored this long after the panel opens: the second
  /// click of a double click on the Channels button would land on it.
  static const openGuard = kDoubleTapTimeout;

  final int sourceId;

  /// The list to open on; All channels when it has no entry (hidden or
  /// gone).
  final LiveList list;

  /// The channel playing: highlighted, and focused first where listed.
  final String playingKey;
  final ChannelEntryCallback onTune;
  final VoidCallback onClose;
  final PanelChannelCallback? onChannelMenu;
  final VoidCallback? onActivity;

  @override
  ConsumerState<ChannelPanel> createState() => ChannelPanelState();
}

class ChannelPanelState extends ConsumerState<ChannelPanel> {
  final _scope = FocusScopeNode(debugLabel: 'channel-panel');
  final _catsPane = GlobalKey<PaneScopeState>();
  final _channelsPane = GlobalKey<PaneScopeState>();
  final _categories = GlobalKey<LiveCategoryPaneState>();
  GlobalKey<ChannelListState> _list = GlobalKey(debugLabel: 'panel-list');
  late final NowNextStore _store;

  late LiveList _selected = widget.list;
  LiveList? _pending;
  Timer? _selectTimer;
  int _dataVersion = 0;

  /// Whether [_selected] was checked against the entries once they loaded.
  bool _resolved = false;

  /// Focus moves in once the entries have loaded.
  bool _focusWhenReady = true;

  /// Pointer input waits until [ChannelPanel.openGuard] has passed.
  bool _justOpened = true;
  Timer? _openGuardTimer;

  int get _id => widget.sourceId;

  /// The list shown, for tests.
  @visibleForTesting
  LiveList get selected => _selected;

  /// The channel list's state, for tests.
  @visibleForTesting
  ChannelListState? get channelList => _list.currentState;

  @override
  void initState() {
    super.initState();
    _openGuardTimer = Timer(ChannelPanel.openGuard, () {
      if (mounted) setState(() => _justOpened = false);
    });
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
  void dispose() {
    _selectTimer?.cancel();
    _openGuardTimer?.cancel();
    _store.dispose();
    _scope.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Focus and selection.

  /// Moves focus into the panel: onto the current channel, or onto the
  /// selected category while the channels load (and when there are none).
  /// Does nothing before the entries have loaded; they take focus then.
  void focusIn() {
    if (!mounted) return;
    final list = _list.currentState;
    if (list != null && list.focusCurrent()) {
      // The rows are still being read: focus waits on the category.
      if (!list.hasRows) _categories.currentState?.selectedNode?.requestFocus();
      return;
    }
    if (_categories.currentState?.hasEntry(_selected) ?? false) {
      _focusSelectedCategory();
    } else {
      focusRememberedOrFirst(_scope);
    }
  }

  /// Shows [list]; with [enter], focus moves into its channels.
  void _select(LiveList list, {bool enter = false}) {
    _selectTimer?.cancel();
    _pending = null;
    if (list != _selected) {
      setState(() {
        _selected = list;
        _list = GlobalKey(debugLabel: 'panel-list');
      });
    }
    if (enter) {
      afterNextFrame(() {
        if (mounted) _list.currentState?.focusCurrent();
      });
    }
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
    _selectTimer = Timer(ChannelPanel.selectDelay, () {
      if (mounted) _select(list);
    });
  }

  /// Categories -> channels (a category still pending opens first). A list
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

  /// Focuses the entry of the list shown (not just the column's remembered
  /// entry: focus first went straight to the channels).
  void _focusSelectedCategory() {
    final cats = _categories.currentState;
    if (cats != null && cats.hasEntry(_selected)) {
      cats.focusList(_selected);
    } else {
      _catsPane.currentState?.requestFocus();
    }
  }

  /// The list shown lost its entry (a sync dropped its category, or it was
  /// hidden or deleted elsewhere): All channels, keeping focus in the
  /// channels when it was there.
  void _onSelectedGone() {
    final inChannels = _channelsPane.currentState?.hasFocus ?? false;
    _select(const LiveList.all(), enter: inChannels);
    // Focus waits on the entry while the new rows load.
    if (inChannels) _focusSelectedCategory();
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
      if (_selected.kind == LiveListKind.favorites) {
        setState(() => _dataVersion++);
      }
    });
    final listId = _selected.listId;
    if (listId != null) {
      ref.listen(channelListKeysProvider(listId), (prev, next) {
        final before = prev?.value;
        final after = next.value;
        if (before == null || after == null || listEquals(before, after)) {
          return;
        }
        if (_selected.listId == listId) setState(() => _dataVersion++);
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
    final rows = categories.value;
    // The user's lists are only extra entries: a failed read shows none.
    final lists =
        listRows.value ?? (listRows.hasError ? const <ChannelListRow>[] : null);
    final Widget body;
    if (categories.hasError && rows == null) {
      body = ErrorView(
        onRetry: () => ref.invalidate(liveCategoriesProvider(_id)),
        autofocusRetry: false,
      );
    } else if (rows == null || lists == null) {
      body = const LoadingView();
    } else {
      final entries = liveCategoryEntries(
        l10n,
        categories: rows,
        lists: lists,
        favorites: favorites.length,
        recent: recent.length,
        total: total,
      );
      if (!entries.any((e) => e.list == _selected)) {
        if (_resolved) {
          final selected = _selected;
          afterNextFrame(() {
            if (mounted && _selected == selected) _onSelectedGone();
          });
        } else {
          // Opened on a list without an entry: All channels instead.
          _selected = const LiveList.all();
        }
      }
      _resolved = true;
      if (_focusWhenReady) {
        _focusWhenReady = false;
        afterNextFrame(focusIn);
      }
      body = _columns(l10n, entries, favorites);
    }
    return _frame(l10n, body);
  }

  Widget _columns(
    AppLocalizations l10n,
    List<LiveCategoryEntry> entries,
    Set<String> favorites,
  ) {
    final selected = _selected;
    final menu = widget.onChannelMenu;
    final categories = PaneScope(
      key: _catsPane,
      debugLabel: 'panel-categories',
      onExitEnd: _enterChannels,
      child: LiveCategoryPane(
        key: _categories,
        entries: entries,
        selected: _pending ?? selected,
        onFocusList: _onCategoryFocus,
        onSelectList: (l) => _select(l, enter: true),
        onFocusedEntryGone: _focusSelectedCategory,
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (FormFactorScope.isTv(context))
          SizedBox(width: ChannelPanel.tvCategoryWidth, child: categories)
        else
          Expanded(flex: 2, child: categories),
        const SizedBox(width: Spacing.xs),
        Expanded(
          flex: 3,
          child: PaneScope(
            key: _channelsPane,
            debugLabel: 'panel-channels',
            onExitStart: _focusSelectedCategory,
            child: ChannelList(
              key: _list,
              sourceId: _id,
              list: selected,
              store: _store,
              initialKey: widget.playingKey,
              itemExtent: isLargeLayout(context)
                  ? TvLayout.channelExtent
                  : TvLayout.channelExtentPhone,
              favorites: favorites,
              playingKey: widget.playingKey,
              dataVersion: _dataVersion,
              onPlay: widget.onTune,
              onMenu: menu == null
                  ? null
                  : (_, entry) => menu(entry, favorites.contains(entry.key)),
              onEmptied: (hadFocus, _) {
                if (hadFocus) _focusSelectedCategory();
              },
              emptyMessage: ChannelList.emptyMessageFor(l10n, selected),
              emptyIcon: ChannelList.emptyIconFor(selected),
            ),
          ),
        ),
      ],
    );
  }

  /// The panel's frame: the translucent column at the start edge (the
  /// whole screen on phones) under a title, and the area beside it that
  /// closes the panel when clicked or tapped.
  Widget _frame(AppLocalizations l10n, Widget body) {
    final formFactor = FormFactorScope.of(context);
    final overscan = overscanPadding(formFactor);
    // The TV overscan margin (the same on both sides).
    final side = overscan.horizontal / 2;
    final full = !isLargeLayout(context);
    final theme = Theme.of(context);
    final panel = Material(
      key: const ValueKey('channel-panel'),
      color: _panelColor,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            side + Spacing.sm,
            overscan.top + Spacing.sm,
            Spacing.sm,
            overscan.bottom + Spacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SizedBox(width: Spacing.sm),
                  const Icon(Icons.list, color: AppColors.accent),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      l10n.playerChannels,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  // Mouse and touch; the remote has Back.
                  if (formFactor != FormFactor.tv)
                    OsdIconButton(
                      key: const ValueKey('channel-panel-close'),
                      icon: Icons.close,
                      label: l10n.commonClose,
                      onSelect: widget.onClose,
                    ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
    void activity(PointerEvent _) => widget.onActivity?.call();
    final tv = formFactor == FormFactor.tv;
    return Listener(
      onPointerDown: activity,
      onPointerMove: activity,
      onPointerHover: activity,
      onPointerSignal: activity,
      onPointerPanZoomStart: activity,
      onPointerPanZoomUpdate: activity,
      child: LayoutBuilder(
        builder: (context, c) {
          final width = full
              ? c.maxWidth
              : math.min(
                  c.maxWidth,
                  (c.maxWidth *
                              (tv
                                  ? ChannelPanel.tvWidthFraction
                                  : ChannelPanel.widthFraction) +
                          side)
                      .clamp(
                        ChannelPanel.minWidth,
                        tv ? ChannelPanel.tvMaxWidth : ChannelPanel.maxWidth,
                      ),
                );
          final stack = Stack(
            children: [
              if (!full)
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('channel-panel-outside'),
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onClose,
                  ),
                ),
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: width,
                child: FocusScope(node: _scope, child: _slideIn(panel)),
              ),
            ],
          );
          // The click that opened the panel may be the first of a double
          // click: its second click must not pick a category or close it.
          return AbsorbPointer(absorbing: _justOpened, child: stack);
        },
      ),
    );
  }

  /// Slides [child] in from the start edge (at once where animations are
  /// off).
  Widget _slideIn(Widget child) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: -1, end: 0),
      duration: FocusTokens.scrollOf(context),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => FractionalTranslation(
        translation: Offset(rtl ? -t : t, 0),
        child: child,
      ),
      child: child,
    );
  }
}
