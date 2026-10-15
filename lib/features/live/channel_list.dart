import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';
import '../../tv/dpad_shortcuts.dart';
import '../../tv/key_repeat.dart';
import '../../widgets/channel_tile.dart';
import '../../widgets/states.dart';
import 'channel_pager.dart';
import 'channel_source.dart';
import 'live_models.dart';
import 'now_next_store.dart';
import 'preferred_focus.dart';

/// Called with the list's source and an entry (play, options).
typedef ChannelEntryCallback = void Function(
  ChannelListSource source,
  LiveEntry entry,
);

/// Called when a refresh finds no rows: whether a row had focus (or was
/// meant to get it back), and the channel that was current (or was to be
/// focused).
typedef ListEmptiedCallback = void Function(bool hadFocus, String? lastKey);

/// A remote-friendly, paged list of channels ([ChannelTile] rows).
///
/// * Rows are read from the database by position in pages of
///   [ChannelList.pageSize] ([ChannelPager]); a fixed [itemExtent] keeps
///   scrolling cheap on 50k-channel lists.
/// * Opens already scrolled to [initialKey] (e.g. the last played channel).
/// * Each row's focus node lives in this state, keyed by position, so
///   rows keep focus while their page loads or reloads.
/// * Remote keys: held arrows are throttled and jump 5 rows after 1 s
///   ([KeyRepeatGuard]); Page Up/Down (and CH+/CH−) move one screen; digits
///   jump to that channel number after [ChannelList.digitDelay].
/// * Now/next of the rows on screen comes from [store] once scrolling has
///   settled.
///
/// Use a `GlobalKey<ChannelListState>` to move focus into the list
/// ([ChannelListState.focusCurrent]) or to a channel
/// ([ChannelListState.refresh] with `focusKey`). Give each list its own key:
/// a new [list] needs a new state.
class ChannelList extends ConsumerStatefulWidget {
  const ChannelList({
    super.key,
    required this.sourceId,
    required this.list,
    required this.store,
    this.initialKey,
    this.itemExtent = TvLayout.channelExtent,
    this.favorites = const {},
    this.playingKey,
    this.dataVersion = 0,
    this.onPlay,
    this.onMenu,
    this.onFocusEntry,
    this.onEmptied,
    this.emptyMessage,
    this.emptyIcon = Icons.live_tv_outlined,
    this.sourceBuilder,
  });

  /// Rows per database page.
  static const pageSize = 200;

  /// Pages kept in memory.
  static const maxPages = 10;

  /// Typed digits jump this long after the last one (OK jumps at once).
  static const digitDelay = Duration(seconds: 1);

  /// How long "No channel N" stays up.
  static const missDuration = Duration(milliseconds: 1500);

  final int sourceId;
  final LiveList list;
  final NowNextStore store;

  /// Channel to open scrolled to (and focus first).
  final String? initialKey;
  final double itemExtent;

  /// Favourite channel keys (star on the row).
  final Set<String> favorites;

  /// The channel playing or played last (highlighted).
  final String? playingKey;

  /// Bump when the list's data changed (sync, favourites); the list re-reads
  /// its source and keeps focus on the same channel where it can.
  final int dataVersion;
  final ChannelEntryCallback? onPlay;
  final ChannelEntryCallback? onMenu;

  /// The focused entry (null while its page loads).
  final ValueChanged<LiveEntry?>? onFocusEntry;

  /// A refresh found no rows. Called whether or not a row had focus, so
  /// a screen can also move focus out of a neighbour pane that showed the
  /// list's channel.
  final ListEmptiedCallback? onEmptied;
  final String? emptyMessage;
  final IconData emptyIcon;

  /// A custom source (e.g. search results); defaults to [list]'s source.
  final ChannelListSource Function(AppDatabase db)? sourceBuilder;

  @override
  ConsumerState<ChannelList> createState() => ChannelListState();
}

class ChannelListState extends ConsumerState<ChannelList> {
  ChannelListSource? _source;
  ChannelPager? _pager;
  ScrollController? _scroll;
  final _nodes = <int, FocusNode>{};
  int _current = 0;
  Object? _error;
  bool _focusWhenReady = false;
  int _openSeq = 0;
  String _digits = '';
  int? _digitMiss;
  Timer? _digitTimer;

  /// The pager, for tests.
  @visibleForTesting
  ChannelPager? get pager => _pager;

  /// Whether the list has loaded and has rows.
  bool get hasRows => (_pager?.length ?? 0) > 0;

  /// Position of the focused (or, before any focus, the initial) row.
  int get currentIndex => _current;

  /// The focused (or initial) entry, when its page is loaded.
  LiveEntry? get currentEntry => _pager?.entryAt(_current);

  /// Whether a row has focus.
  bool get hasFocus => _nodes.values.any((n) => n.hasFocus);

  /// The node the list should be entered on (for traversal policies).
  FocusNode? get preferredNode {
    final node = _nodes[_current];
    return isAttached(node) ? node : null;
  }

  double get _extent => widget.itemExtent;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    unawaited(_open());
  }

  @override
  void didUpdateWidget(ChannelList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStore);
      widget.store.addListener(_onStore);
    }
    if (oldWidget.dataVersion != widget.dataVersion) unawaited(refresh());
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    _digitTimer?.cancel();
    _pager?.dispose();
    _scroll?.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  ChannelListSource _newSource() {
    final db = ref.read(databaseProvider);
    return widget.sourceBuilder?.call(db) ??
        channelSourceFor(db, widget.sourceId, widget.list);
  }

  Future<void> _open() async {
    final seq = ++_openSeq;
    final source = _newSource();
    try {
      final count = await source.count();
      final key = widget.initialKey;
      final index = key == null || count == 0
          ? null
          : await source.indexOfKey(key);
      if (!mounted || seq != _openSeq) return;
      _pager?.dispose();
      setState(() {
        _error = null;
        _source = source;
        _current = count == 0 ? 0 : (index ?? 0).clamp(0, count - 1);
        _pager = ChannelPager(
          source,
          count,
          pageSize: ChannelList.pageSize,
          maxPages: ChannelList.maxPages,
          window: _window,
          onError: _onPageError,
        )..addListener(_onPager);
      });
      if (_focusWhenReady) {
        _focusWhenReady = false;
        if (count > 0) afterNextFrame(() => focusIndex(_current));
      }
    } on Object catch (e, st) {
      ref.read(ringLogProvider).error('Loading channels failed', e, st);
      if (mounted && seq == _openSeq) setState(() => _error = e);
    }
  }

  void _onPageError(Object e, StackTrace st) =>
      ref.read(ringLogProvider).error('Loading a channel page failed', e, st);

  /// Re-reads the source (after a sync, a favourite change or playback) and
  /// keeps focus on the same channel, or on [focusKey] when given and
  /// listed. Focus moves only when the list has it (or [focus] is true);
  /// otherwise just the remembered row changes.
  Future<void> refresh({String? focusKey, bool? focus}) async {
    final pager = _pager;
    final source = _source;
    if (pager == null || source == null) return;
    final hadFocus = focus ?? hasFocus;
    final key = focusKey ?? currentEntry?.key;
    int count;
    int? index;
    try {
      count = await source.count();
      index = key == null || count == 0 ? null : await source.indexOfKey(key);
    } on Object catch (e, st) {
      if (mounted) {
        ref.read(ringLogProvider).error('Reloading channels failed', e, st);
      }
      return;
    }
    if (!mounted || pager != _pager) return;
    pager.reset(count);
    if (count == 0) {
      setState(() => _current = 0);
      widget.onEmptied?.call(hadFocus, key);
      return;
    }
    final target = (index ?? _current).clamp(0, count - 1);
    if (hadFocus) {
      focusIndex(target);
    } else {
      _current = target;
    }
    setState(() {});
  }

  void _onPager() {
    if (!mounted) return;
    setState(() {});
    _reportVisible();
    if (_nodes[_current]?.hasFocus ?? false) {
      widget.onFocusEntry?.call(_pager?.entryAt(_current));
    }
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  RowWindow? _window() {
    final c = _scroll;
    final pager = _pager;
    if (c == null || !c.hasClients || pager == null || pager.length == 0) {
      return null;
    }
    final pos = c.position;
    if (!pos.hasContentDimensions || !pos.hasViewportDimension) return null;
    final first = (pos.pixels / _extent).floor();
    final last = ((pos.pixels + pos.viewportDimension) / _extent).ceil() - 1;
    return (
      first: first.clamp(0, pager.length - 1),
      last: last.clamp(0, pager.length - 1),
    );
  }

  /// Tells the now/next store which channels are on screen.
  void _reportVisible() {
    final window = _window();
    final pager = _pager;
    if (window == null || pager == null) return;
    widget.store.showing([
      for (var i = window.first; i <= window.last; i++)
        ?pager.entryAt(i)?.row?.key,
    ]);
  }

  FocusNode _nodeFor(int index) {
    final existing = _nodes[index];
    if (existing != null) return existing;
    if (_nodes.length >= 300) _pruneNodes();
    return _nodes[index] = FocusNode(debugLabel: 'channel-row-$index');
  }

  void _pruneNodes() {
    _nodes.removeWhere((i, node) {
      final drop =
          (i - _current).abs() > 60 && node.parent == null && !node.hasFocus;
      if (drop) node.dispose();
      return drop;
    });
  }

  bool _onScreen(int index) {
    final w = _window();
    return w != null && index >= w.first && index <= w.last;
  }

  /// Focuses row [index] (clamped), scrolling it into view first.
  void focusIndex(int index) {
    final pager = _pager;
    if (pager == null) {
      _current = index;
      _focusWhenReady = true;
      return;
    }
    if (pager.length == 0) return;
    final i = index.clamp(0, pager.length - 1);
    _current = i;
    final node = _nodes[i];
    if (isAttached(node) && _onScreen(i)) {
      node!.requestFocus();
      return;
    }
    final c = _scroll;
    if (c != null && c.hasClients) {
      final pos = c.position;
      final target = (i * _extent - (pos.viewportDimension - _extent) / 2)
          .clamp(pos.minScrollExtent, pos.maxScrollExtent);
      c.jumpTo(target);
    }
    afterNextFrame(() {
      if (mounted && _current == i) _nodeFor(i).requestFocus();
    });
  }

  /// Focuses the remembered row (the last focused, else the one the list
  /// opened on). Before the rows have loaded, focus follows once they have.
  /// Returns false when the list is empty or failed to load.
  bool focusCurrent() {
    if (_error != null) return false;
    final pager = _pager;
    if (pager == null) {
      _focusWhenReady = true;
      return true;
    }
    if (pager.length == 0) return false;
    focusIndex(_current);
    return true;
  }

  /// Clears a pending number entry; returns whether there was one.
  bool clearDigits() {
    if (_digits.isEmpty && _digitMiss == null) return false;
    _digitTimer?.cancel();
    setState(() {
      _digits = '';
      _digitMiss = null;
    });
    return true;
  }

  int _rowsPerScreen() {
    final c = _scroll;
    if (c == null || !c.hasClients) return 1;
    return math.max(1, (c.position.viewportDimension / _extent).floor());
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final digit = _digitOf(key);
    if (digit != null) {
      if (event is KeyDownEvent) _typeDigit(digit);
      return KeyEventResult.handled;
    }
    if (_digits.isNotEmpty && selectKeys.contains(key)) {
      if (event is KeyDownEvent) unawaited(_commitDigits());
      return KeyEventResult.handled;
    }
    final page = _pageStepOf(key);
    if (page != 0 && hasFocus) {
      focusIndex(_current + page * _rowsPerScreen());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _onJump(TraversalDirection direction, int count) {
    switch (direction) {
      case TraversalDirection.up:
        focusIndex(_current - count);
        return true;
      case TraversalDirection.down:
        focusIndex(_current + count);
        return true;
      case TraversalDirection.left:
      case TraversalDirection.right:
        return false;
    }
  }

  void _typeDigit(int digit) {
    _digitTimer?.cancel();
    setState(() {
      if (_digits.length >= 5) _digits = '';
      _digits += '$digit';
      _digitMiss = null;
    });
    _digitTimer = Timer(ChannelList.digitDelay, () {
      unawaited(_commitDigits());
    });
  }

  Future<void> _commitDigits() async {
    _digitTimer?.cancel();
    final number = int.tryParse(_digits);
    if (_digits.isNotEmpty) setState(() => _digits = '');
    final source = _source;
    if (number == null || source == null) return;
    final index = await source.indexOfNumber(number);
    if (!mounted) return;
    if (index != null) {
      focusIndex(index);
      return;
    }
    setState(() => _digitMiss = number);
    _digitTimer = Timer(ChannelList.missDuration, () {
      if (mounted) setState(() => _digitMiss = null);
    });
  }

  /// [action], or committing a typed number when there is one. A row with
  /// a menu takes OK itself (a held OK opens the menu), so [_onKey] never
  /// sees that OK.
  VoidCallback _orCommitDigits(VoidCallback action) => () {
    if (_digits.isNotEmpty) {
      unawaited(_commitDigits());
    } else {
      action();
    }
  };

  void _onRowFocus(int index) {
    _current = index;
    widget.onFocusEntry?.call(_pager?.entryAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_error != null) {
      return ErrorView(onRetry: _open, autofocusRetry: false);
    }
    final pager = _pager;
    if (pager == null) return const LoadingView();
    if (pager.length == 0) {
      return EmptyView(
        message: widget.emptyMessage ?? l10n.liveNoChannels,
        icon: widget.emptyIcon,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _scroll ??= ScrollController(
          initialScrollOffset: _initialOffset(constraints.maxHeight),
        );
        return Stack(
          children: [
            Positioned.fill(
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                includeSemantics: false,
                onKeyEvent: _onKey,
                child: KeyRepeatGuard(
                  onJump: _onJump,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (_) {
                      _reportVisible();
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scroll,
                      itemExtent: _extent,
                      itemCount: pager.length,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                      ),
                      itemBuilder: _buildRow,
                    ),
                  ),
                ),
              ),
            ),
            if (_digits.isNotEmpty || _digitMiss != null)
              PositionedDirectional(
                top: Spacing.sm,
                end: Spacing.lg,
                child: _NumberBadge(
                  text: _digits.isNotEmpty
                      ? _digits
                      : l10n.liveNoChannelNumber(_digitMiss!),
                  miss: _digits.isEmpty,
                ),
              ),
          ],
        );
      },
    );
  }

  double _initialOffset(double viewport) {
    final count = _pager?.length ?? 0;
    if (!viewport.isFinite || count == 0) return 0;
    final max = math.max(0.0, count * _extent - viewport);
    return (_current * _extent - (viewport - _extent) / 2).clamp(0.0, max);
  }

  Widget _buildRow(BuildContext context, int index) {
    final l10n = AppLocalizations.of(context);
    final entry = _pager!.entryAt(index);
    final row = entry?.row;
    final key = entry?.key;
    final nowNext = row == null ? null : widget.store[row.key];
    final now = ref.read(clockProvider).now();
    final source = _source!;
    return ChannelTile(
      key: ValueKey('channel-row-$index'),
      focusNode: _nodeFor(index),
      name: row?.name ?? (entry == null ? '' : l10n.commonUnavailable),
      number: row?.num,
      logoUrl: row?.logo,
      // Blank (not "no programme info") until the guide has been read.
      nowTitle: row == null || widget.store.has(row.key)
          ? nowNext?.now?.title
          : '',
      progress: programmeProgress(nowNext?.now, now),
      isFavorite: key != null && widget.favorites.contains(key),
      selected: key != null && key == widget.playingKey,
      showNowLine: row != null,
      onSelect: row == null
          ? null
          : _orCommitDigits(() => widget.onPlay?.call(source, entry!)),
      onMenu: entry == null || widget.onMenu == null
          ? null
          : _orCommitDigits(() => widget.onMenu!(source, entry)),
      onFocusChange: (focused) {
        if (focused) _onRowFocus(index);
      },
    );
  }
}

int? _digitOf(LogicalKeyboardKey key) {
  final digits = [
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  final numpad = [
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];
  final d = digits.indexOf(key);
  if (d >= 0) return d;
  final n = numpad.indexOf(key);
  return n >= 0 ? n : null;
}

/// -1 for a page up, 1 for a page down, else 0. CH+/CH− page the list
/// too: remotes without Page keys have them.
int _pageStepOf(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.channelUp) {
    return -1;
  }
  if (key == LogicalKeyboardKey.pageDown ||
      key == LogicalKeyboardKey.channelDown) {
    return 1;
  }
  return 0;
}

/// The typed channel number (or "No channel N").
class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.text, required this.miss});

  final String text;
  final bool miss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey('channel-number-badge'),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighest,
        borderRadius: Radii.mdAll,
        border: Border.all(color: miss ? AppColors.error : AppColors.accent),
      ),
      child: Text(
        text,
        textDirection: miss ? null : TextDirection.ltr,
        style: miss
            ? theme.titleMedium
            : theme.headlineMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
      ),
    );
  }
}
