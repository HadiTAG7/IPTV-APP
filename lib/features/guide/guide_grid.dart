import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/home_shell.dart';
import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../core/time/clock.dart';
import '../../epg/epg_models.dart';
import '../../epg/epg_providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';
import '../../tv/dpad_shortcuts.dart';
import '../../tv/focus_watchdog.dart';
import '../../tv/key_repeat.dart';
import '../../widgets/bidi_text.dart';
import '../../widgets/logo_image.dart';
import '../../widgets/states.dart';
import 'guide_data.dart';
import 'guide_format.dart';
import 'guide_model.dart';
import 'guide_painter.dart';
import 'guide_widgets.dart';
import 'providers.dart';

/// The guide grid of the large layout (TV, desktop, wide tablets).
///
/// * An info panel for the focused programme, a time header with half-hour
///   labels and a "now" marker, then one row per channel: the channel
///   (number, logo, name) on the start side and its programmes painted by
///   [GuideRowPainter] over a 2.5-hour window. Time runs away from the
///   channel column, so it is mirrored in RTL.
/// * ONE [Focus] for the whole grid. Its key handler drives a
///   [GuidePosition] (row, anchor time, window): Up/Down change rows and
///   keep the time, Left/Right step to the previous/next programme
///   (mirrored in RTL) and the window follows. A fresh press past the
///   first programme or above the first row is left to the page, so focus
///   goes to the rail or to the header buttons. The [Focus] is there from
///   the first frame, while the channels load, so entering the page early
///   lands in the grid and stays there once the rows arrive.
/// * OK on the programme on air (or a row without guide data) plays the
///   channel with the guide's list as the zap list; on any other programme
///   it shows its details. Menu/Info show the details too. Back returns to
///   now before the shell takes focus to the rail.
/// * Channels come from the database in pages ([GuideChannelPager]) and
///   programmes of the visible rows ± [rowMargin] from one query
///   ([GuideProgrammeStore]), debounced while scrolling, over the visible
///   window plus [GuideTimes.loadBehind] / [GuideTimes.loadAhead]. Time
///   outside the loaded block shows as loading, not as a gap.
class GuideGrid extends ConsumerStatefulWidget {
  const GuideGrid({
    super.key,
    required this.sourceId,
    required this.filter,
    this.favoriteKeys = const [],
    this.catalogVersion = 0,
  });

  final int sourceId;
  final GuideFilter filter;

  /// Favourite order, for [GuideFilter.favorites].
  final List<String> favoriteKeys;

  /// Changes when the catalog was replaced (a sync), to reload the rows.
  final int catalogVersion;

  static const rowExtent = 64.0;
  static const infoHeight = 88.0;
  static const headerHeight = 24.0;

  /// Rows loaded around the visible ones.
  static const rowMargin = 20;

  @override
  ConsumerState<GuideGrid> createState() => GuideGridState();
}

class GuideGridState extends ConsumerState<GuideGrid> {
  final _gridNode = FocusNode(debugLabel: 'guide-grid');
  final _scroll = ScrollController();
  late final GuideChannelPager _pager;
  late final GuideProgrammeStore _store;
  late final Clock _clock;
  late GuideWindow _window;
  late GuidePosition _pos;
  late DateFormat _timeFormat;

  /// Whether the position follows the clock (nothing moved in time yet).
  bool _follow = true;
  bool _focused = false;

  /// OK is down on the grid (pressed here, not on the view before), and
  /// whether holding it already showed the details.
  bool _selectHeld = false;
  bool _longFired = false;

  Timer? _tick;
  FocusWatchdogState? _watchdog;
  double _drag = 0;

  final _slots = <String, List<GuideSlot>>{};
  int _slotsVersion = -1;
  GuideWindow? _slotsWindow;

  /// The focus position (for tests).
  @visibleForTesting
  GuidePosition get position => _pos;

  /// The browsable range now (for tests).
  @visibleForTesting
  GuideWindow get window => _window;

  /// Time range of the programmes in memory (for tests).
  @visibleForTesting
  ({DateTime from, DateTime to})? get loadedRange => _store.range;

  /// The grid's focus node.
  FocusNode get focusNode => _gridNode;

  @override
  void initState() {
    super.initState();
    _clock = ref.read(clockProvider);
    _window = GuideWindow(_clock.now());
    _pos = GuidePosition.at(_window);
    _store = GuideProgrammeStore(_loadProgrammes)..addListener(_onData);
    _pager = _newPager();
    _scroll.addListener(_maybeLoad);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _onTick());
    // The grid's Focus is built in the first frame (also while loading).
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _claimLostFocus())
      ..ensureVisualUpdate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timeFormat = guideTimeFormat(context);
    final watchdog = FocusWatchdog.maybeOf(context);
    if (watchdog != _watchdog) {
      _watchdog?.unregister(_gridNode);
      _watchdog = watchdog;
      if (_focused) watchdog?.register(_gridNode);
    }
  }

  @override
  void didUpdateWidget(GuideGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    final favorites = widget.filter.kind == GuideFilterKind.favorites;
    // Reloaded in place, so a focused grid stays mounted.
    if (favorites && !listEquals(old.favoriteKeys, widget.favoriteKeys)) {
      unawaited(_pager.reload());
    } else if (old.catalogVersion != widget.catalogVersion) {
      unawaited(_pager.reload());
      _store.reload();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _watchdog?.unregister(_gridNode);
    _pager.dispose();
    _store.dispose();
    _scroll.dispose();
    _gridNode.dispose();
    super.dispose();
  }

  GuideChannelPager _newPager() {
    final pager = GuideChannelPager.forFilter(
      ref.read(databaseProvider),
      widget.sourceId,
      widget.filter,
      favoriteKeys: () => widget.favoriteKeys,
    )..addListener(_onData);
    unawaited(pager.init());
    return pager;
  }

  Future<Map<String, List<EpgProgramme>>> _loadProgrammes(
    List<String> keys,
    DateTime from,
    DateTime to,
  ) => ref
      .read(epgDaoProvider)
      .programmesForChannels(widget.sourceId, keys, from, to);

  // -------------------------------------------------------------------------
  // Data.

  void _onData() {
    if (!mounted) return;
    final n = _pager.length ?? 0;
    setState(() {
      if (n > 0 && _pos.row >= n) _pos = _pos.copyWith(row: n - 1);
    });
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted) _maybeLoad();
      })
      ..ensureVisualUpdate();
  }

  void _onTick() {
    if (!mounted) return;
    final window = GuideWindow(_clock.now());
    setState(() {
      _window = window;
      _pos = _follow
          ? GuidePosition.at(window, row: _pos.row)
          : clampPosition(_pos, window);
    });
    _maybeLoad();
  }

  /// Loads the channel pages and the programmes around the visible rows:
  /// one block over the visible window (and the focused programme) plus
  /// [GuideTimes.loadBehind] before and [GuideTimes.loadAhead] after, again
  /// once the block ends less than [GuideTimes.prefetch] from them.
  void _maybeLoad() {
    final n = _pager.length ?? 0;
    if (n == 0 || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasViewportDimension) return;
    final first = (position.pixels / GuideGrid.rowExtent).floor();
    final last =
        first + (position.viewportDimension / GuideGrid.rowExtent).ceil();
    const margin = GuideGrid.rowMargin;
    _pager.ensure(first - margin, last + margin);
    final needed = _pager.keysIn(first - margin ~/ 4, last + margin ~/ 4);
    if (needed.isEmpty) return;
    // A long programme counts in full, so the ones next to it are known.
    final focused = _focusedSlot?.programme;
    var start = _pos.viewStart;
    var end = _pos.viewEnd;
    if (focused != null) {
      if (focused.start.isBefore(start)) start = focused.start;
      if (focused.stop.isAfter(end)) end = focused.stop;
    }
    DateTime from(Duration d) => _later(_window.minTime, start.subtract(d));
    DateTime to(Duration d) => _earliest(end.add(d), _window.maxTime);
    const prefetch = GuideTimes.prefetch;
    if (_store.covers(needed, from(prefetch), to(prefetch))) return;
    _store.request(
      _pager.keysIn(first - margin, last + margin),
      from(GuideTimes.loadBehind),
      to(GuideTimes.loadAhead),
      // At once when nothing of the window is there (first load, jumps);
      // after a failed load only after the debounce, so a failing query is
      // not retried every frame.
      immediate: _store.version == 0 || (!_viewLoaded && _store.error == null),
    );
  }

  static DateTime _earliest(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
  static DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

  /// Whether the delivered block covers the visible window.
  bool get _viewLoaded => _store.hasRange(
    _later(_pos.viewStart, _window.minTime),
    _earliest(_pos.viewEnd, _window.maxTime),
  );

  /// Slots of a row over the loaded block, or null while its programmes
  /// (or those of the visible window) load.
  List<GuideSlot>? _slotsOf(String key) {
    if (_slotsVersion != _store.version || _slotsWindow != _window) {
      _slots.clear();
      _slotsVersion = _store.version;
      _slotsWindow = _window;
    }
    final block = _store.range;
    if (block == null || !_viewLoaded) return null;
    final programmes = _store.programmesOf(key);
    if (programmes == null) return null;
    return _slots[key] ??= buildSlots(
      programmes,
      _later(block.from, _window.minTime),
      _earliest(block.to, _window.maxTime),
    );
  }

  /// Whether the browsable range goes on past the loaded block, after
  /// ([forward]) or before it.
  bool _moreBeyondBlock({required bool forward}) {
    final block = _store.range;
    if (block == null) return false;
    return forward
        ? block.to.isBefore(_window.maxTime)
        : block.from.isAfter(_window.minTime);
  }

  /// The focused slot; null while the row loads.
  GuideSlot? get _focusedSlot {
    final channel = _pager.rowAt(_pos.row);
    if (channel == null) return null;
    final slots = _slotsOf(channel.key);
    if (slots == null || slots.isEmpty) return null;
    return slots[slotIndexAt(slots, _pos.anchor)];
  }

  // -------------------------------------------------------------------------
  // Focus and keys.

  void _onFocusChange(bool focused) {
    if (!focused) {
      _selectHeld = false;
      _longFired = false;
    }
    setState(() => _focused = focused);
    if (focused) _watchdog?.register(_gridNode);
  }

  /// Takes focus when it fell back to the page (the view this grid
  /// replaced had it and no focus watchdog restored it).
  void _claimLostFocus() {
    if (!mounted) return;
    final primary = FocusManager.instance.primaryFocus;
    if (primary is FocusScopeNode &&
        primary != FocusManager.instance.rootScope &&
        _gridNode.ancestors.contains(primary)) {
      _gridNode.requestFocus();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final direction = arrowDirection(key);
    if (direction != null) {
      final step = KeyRepeatThrottle.instance.stepFor(event);
      if (event is KeyUpEvent) return KeyEventResult.ignored;
      if (step == 0) return KeyEventResult.handled;
      if (_move(direction, step)) return KeyEventResult.handled;
      // A held key stops at the edge; a fresh press may leave the grid.
      return event is KeyRepeatEvent
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    // A short OK plays or shows details on key up; a held OK shows the
    // details (remotes without a Menu or Info key).
    if (selectKeys.contains(key)) {
      switch (event) {
        case KeyDownEvent():
          _selectHeld = true;
          _longFired = false;
        case KeyRepeatEvent():
          if (_selectHeld && !_longFired) {
            _longFired = true;
            _showInfo();
          }
        case KeyUpEvent():
          final fire = _selectHeld && !_longFired;
          _selectHeld = false;
          _longFired = false;
          if (fire) _activate();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final down = event is KeyDownEvent;
    if (key == menuKey || key == LogicalKeyboardKey.info) {
      if (down) _showInfo();
      return KeyEventResult.handled;
    }
    final page = switch (key) {
      LogicalKeyboardKey.pageDown || LogicalKeyboardKey.channelDown => 1,
      LogicalKeyboardKey.pageUp || LogicalKeyboardKey.channelUp => -1,
      _ => 0,
    };
    if (page != 0) {
      final rows = _scroll.hasClients
          ? (_scroll.position.viewportDimension / GuideGrid.rowExtent).floor()
          : 5;
      final next = moveRows(_pos, page * (rows < 1 ? 1 : rows), _rowCount);
      if (next != null) _setPosition(next);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  int get _rowCount => _pager.length ?? 0;

  bool _move(TraversalDirection direction, int step) {
    final forward = movesForward(direction, Directionality.of(context));
    if (forward == null) {
      final delta = direction == TraversalDirection.down ? step : -step;
      final next = moveRows(_pos, delta, _rowCount);
      if (next == null) return false;
      _setPosition(next);
      return true;
    }
    // No rows (yet): the page decides (the rail is that way).
    if (_rowCount == 0) return false;
    final channel = _pager.rowAt(_pos.row);
    final slots = channel == null ? null : _slotsOf(channel.key);
    // The row is loading: stay in the grid.
    if (slots == null) return true;
    final next = moveSlot(_pos, slots, _window, forward: forward);
    if (next == null) {
      if (!_moreBeyondBlock(forward: forward)) return false;
      // The row goes on past the loaded block: scroll that way while it
      // loads.
      _follow = false;
      _setPosition(shiftView(_pos, forward ? 1 : -1, _window));
      return true;
    }
    _follow = false;
    _setPosition(next);
    return true;
  }

  void _setPosition(GuidePosition next) {
    setState(() => _pos = next);
    _ensureRowVisible(next.row);
    _maybeLoad();
  }

  /// Scrolls so [row] and, when there is room, its neighbours are visible.
  void _ensureRowVisible(int row) {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    if (!p.hasViewportDimension) return;
    const extent = GuideGrid.rowExtent;
    final view = p.viewportDimension;
    final context = view >= 3 * extent ? extent : 0.0;
    final top = row * extent - context;
    final bottom = (row + 1) * extent + context;
    var target = p.pixels;
    if (top < target) {
      target = top;
    } else if (bottom > target + view) {
      target = bottom - view;
    }
    target = target.clamp(p.minScrollExtent, p.maxScrollExtent);
    if (target != p.pixels) _scroll.jumpTo(target);
  }

  /// Back: return to now first; at now the shell moves focus to the rail.
  bool _onBack() {
    if (!_gridNode.hasPrimaryFocus) return false;
    final home = GuidePosition.at(_window, row: _pos.row);
    final slot = _focusedSlot;
    final atNow =
        _pos.viewStart == home.viewStart &&
        (slot == null || slot.contains(_window.now));
    if (atNow) return false;
    _follow = true;
    _setPosition(home);
    return true;
  }

  // -------------------------------------------------------------------------
  // Actions.

  void _activate() {
    final channel = _pager.rowAt(_pos.row);
    if (channel == null) return;
    final slot = _focusedSlot;
    if (slot == null || slot.contains(_window.now)) {
      _play(channel);
    } else {
      _showInfo();
    }
  }

  void _play(ChannelRow channel) => _player(channel)();

  /// Plays [channel] with the guide's zap list when called. Safe to call
  /// after this grid is gone (from a dialog it opened): the player and the
  /// request are taken now, and the navigator is used without the grid.
  VoidCallback _player(ChannelRow channel) {
    final player = ref.read(guidePlayerProvider);
    final request = guidePlayRequest(
      sourceId: widget.sourceId,
      channel: channel,
      filter: widget.filter,
      favoriteKeys: widget.favoriteKeys,
    );
    final navigator = Navigator.of(context);
    return () {
      if (mounted) {
        unawaited(player(context, request));
      } else if (navigator.mounted) {
        unawaited(player(navigator.context, request));
      }
    };
  }

  void _showInfo() {
    final channel = _pager.rowAt(_pos.row);
    if (channel == null) return;
    unawaited(
      showGuideProgrammeInfo(
        context,
        channel: channel,
        programme: _focusedSlot?.programme,
        now: _window.now,
        timeFormat: _timeFormat,
        onWatch: _player(channel),
      ),
    );
  }

  // Touch and mouse.

  void _tapChannel(int row) {
    final channel = _pager.rowAt(row);
    if (channel == null) return;
    _setPosition(_pos.copyWith(row: row));
    _gridNode.requestFocus();
    _play(channel);
  }

  void _tapTimeline(int row, double x, double width) {
    final channel = _pager.rowAt(row);
    final slots = channel == null ? null : _slotsOf(channel.key);
    if (slots == null) return;
    final scale = GuideTimeScale(
      viewStart: _pos.viewStart,
      width: width,
      textDirection: Directionality.of(context),
    );
    final i = scale.slotIndexAtX(slots, x);
    if (i == null) return;
    final slot = slots[i];
    final same = row == _pos.row && identical(_focusedSlot, slot);
    _gridNode.requestFocus();
    if (same) {
      _activate();
      return;
    }
    if (!slot.contains(_pos.anchor)) _follow = false;
    _setPosition(
      _pos.copyWith(
        row: row,
        anchor: slot.contains(_pos.anchor)
            ? _pos.anchor
            : slot.start.isAfter(_pos.viewStart)
            ? slot.start
            : _pos.viewStart,
      ),
    );
  }

  void _dragTimeline(double dx, double width) {
    if (width <= 0) return;
    final slotPx =
        width * GuideTimes.slot.inMinutes / GuideTimes.span.inMinutes;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    _drag += rtl ? -dx : dx;
    var steps = 0;
    while (_drag <= -slotPx) {
      _drag += slotPx;
      steps++;
    }
    while (_drag >= slotPx) {
      _drag -= slotPx;
      steps--;
    }
    if (steps == 0) return;
    _follow = false;
    _setPosition(shiftView(_pos, steps, _window));
  }

  // -------------------------------------------------------------------------
  // Build.

  @override
  Widget build(BuildContext context) {
    ref.listen<GuideRefreshStatus>(guideRefreshProvider(widget.sourceId), (
      previous,
      next,
    ) {
      if (next is GuideRefreshDone && previous is! GuideRefreshDone) {
        _store.reload();
      }
    });
    final l10n = AppLocalizations.of(context);
    final n = _pager.length;
    final Widget content;
    if (n == null) {
      content = _pager.error != null
          ? ErrorView(
              autofocusRetry: false,
              onRetry: () => unawaited(_pager.reload()),
            )
          : const LoadingView();
    } else if (n == 0) {
      content = EmptyView(
        icon: Icons.live_tv_outlined,
        message: widget.filter.kind == GuideFilterKind.favorites
            ? l10n.favoritesEmpty
            : l10n.liveNoChannels,
      );
    } else {
      content = _grid(context, l10n, n);
    }
    return HomeTabBackHandler(
      onBack: _onBack,
      child: FocusTraversalOrder(
        // First in the page: entering the Guide lands here, also while the
        // channels load, and focus stays when they arrive.
        order: const NumericFocusOrder(0),
        child: Focus(
          focusNode: _gridNode,
          // Retry, or the header for an empty list, take focus instead.
          canRequestFocus: n == null ? _pager.error == null : n > 0,
          onKeyEvent: _onKey,
          onFocusChange: _onFocusChange,
          child: content,
        ),
      ),
    );
  }

  Widget _grid(BuildContext context, AppLocalizations l10n, int n) {
    final theme = Theme.of(context).textTheme;
    final direction = Directionality.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final style = GuideGridStyle.of(context);
    final focusedChannel = _pager.rowAt(_pos.row);
    final focusedSlot = _focusedSlot;
    final now = _window.now;

    return LayoutBuilder(
      builder: (context, constraints) {
        final channelWidth = (constraints.maxWidth * 0.22).clamp(112.0, 260.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: GuideGrid.infoHeight,
              child: GuideInfoPanel(
                channel: focusedChannel,
                slot: focusedSlot,
                now: now,
                timeFormat: _timeFormat,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            SizedBox(
              height: GuideGrid.headerHeight,
              child: Row(
                children: [
                  SizedBox(
                    width: channelWidth,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: Spacing.sm,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          guideDayLabel(l10n, locale, _pos.viewStart, now),
                          key: const ValueKey('guide-day'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.labelMedium,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: CustomPaint(
                      key: const ValueKey('guide-header'),
                      painter: GuideHeaderPainter(
                        viewStart: _pos.viewStart,
                        now: now,
                        textDirection: direction,
                        labelStyle: style.time.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        timeFormat: _timeFormat,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Semantics(
                key: const ValueKey('guide-grid'),
                focusable: true,
                focused: _focused,
                label: _semanticLabel(l10n, focusedChannel, focusedSlot),
                child: ListView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.zero,
                  itemExtent: GuideGrid.rowExtent,
                  itemCount: n,
                  itemBuilder: (context, i) =>
                      _row(i, channelWidth, style, l10n, direction),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _semanticLabel(
    AppLocalizations l10n,
    ChannelRow? channel,
    GuideSlot? slot,
  ) {
    if (channel == null) return '';
    final programme = slot?.programme;
    return [
      channel.name,
      programme?.title ?? l10n.liveNoProgrammeInfo,
      if (programme != null)
        guideTimeRange(_timeFormat, programme.start, programme.stop),
    ].join(', ');
  }

  Widget _row(
    int i,
    double channelWidth,
    GuideGridStyle style,
    AppLocalizations l10n,
    TextDirection direction,
  ) {
    final channel = _pager.rowAt(i);
    final focusedRow = i == _pos.row;
    final slots = channel == null ? null : _slotsOf(channel.key);
    final focusedIndex = focusedRow && slots != null && slots.isNotEmpty
        ? slotIndexAt(slots, _pos.anchor)
        : null;
    return _GuideRow(
      key: ValueKey('guide-row-$i'),
      channel: channel,
      channelWidth: channelWidth,
      focused: focusedRow,
      onTapChannel: () => _tapChannel(i),
      onTapTimeline: (x, width) => _tapTimeline(i, x, width),
      onDragTimeline: _dragTimeline,
      onDragEnd: () => _drag = 0,
      painter: GuideRowPainter(
        slots: slots,
        viewStart: _pos.viewStart,
        now: _window.now,
        textDirection: direction,
        style: style,
        timeFormat: _timeFormat,
        noInfoLabel: l10n.liveNoProgrammeInfo,
        focusedIndex: focusedIndex,
        gridFocused: _focused,
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({
    super.key,
    required this.channel,
    required this.channelWidth,
    required this.focused,
    required this.painter,
    required this.onTapChannel,
    required this.onTapTimeline,
    required this.onDragTimeline,
    required this.onDragEnd,
  });

  final ChannelRow? channel;
  final double channelWidth;
  final bool focused;
  final GuideRowPainter painter;
  final VoidCallback onTapChannel;
  final void Function(double x, double width) onTapTimeline;
  final void Function(double dx, double width) onDragTimeline;
  final VoidCallback onDragEnd;

  double _width(BuildContext context) =>
      (context.findRenderObject() as RenderBox?)?.size.width ?? 0;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTapChannel,
          child: _ChannelCell(
            channel: channel,
            width: channelWidth,
            focused: focused,
          ),
        ),
        Expanded(
          child: Builder(
            builder: (context) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) =>
                  onTapTimeline(d.localPosition.dx, _width(context)),
              onHorizontalDragUpdate: (d) =>
                  onDragTimeline(d.delta.dx, _width(context)),
              onHorizontalDragEnd: (_) => onDragEnd(),
              child: CustomPaint(painter: painter, size: Size.infinite),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChannelCell extends StatelessWidget {
  const _ChannelCell({
    required this.channel,
    required this.width,
    required this.focused,
  });

  final ChannelRow? channel;
  final double width;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final channel = this.channel;
    final number = channel?.num;
    return Container(
      width: width,
      margin: const EdgeInsetsDirectional.only(end: Spacing.xs),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Spacing.xs),
      decoration: BoxDecoration(
        color: focused ? AppColors.surfaceHigh : null,
        borderRadius: Radii.smAll,
      ),
      child: channel == null
          ? null
          : Row(
              children: [
                SizedBox(
                  width: 30,
                  child: number == null
                      ? null
                      : Text(
                          '$number',
                          textAlign: TextAlign.end,
                          textDirection: TextDirection.ltr,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: theme.labelMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                ),
                const SizedBox(width: Spacing.xs),
                LogoImage(url: channel.logo, name: channel.name, size: 32),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: BidiText(
                    channel.name,
                    maxLines: 2,
                    style: theme.labelLarge?.copyWith(
                      color: focused ? AppColors.accent : null,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The focused programme above the grid: channel and times, title and the
/// start of the description.
class GuideInfoPanel extends StatelessWidget {
  const GuideInfoPanel({
    super.key,
    required this.channel,
    required this.slot,
    required this.now,
    required this.timeFormat,
  });

  final ChannelRow? channel;
  final GuideSlot? slot;
  final DateTime now;
  final DateFormat timeFormat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final channel = this.channel;
    final programme = slot?.programme;
    final number = channel?.num;
    // The line follows the UI direction; the channel name, isolated (FSI
    // .. PDI), keeps its own.
    final head = [
      if (channel != null)
        '\u2068${number == null ? channel.name : '$number  ${channel.name}'}'
            '\u2069',
      if (programme != null)
        guideProgrammeTimes(l10n, locale, timeFormat, programme, now),
    ].join('  ·  ');
    final title =
        programme?.title ??
        (slot != null ? l10n.liveNoProgrammeInfo : channel?.name ?? '');
    final desc = programme?.desc ?? programme?.subTitle;
    return Container(
      key: const ValueKey('guide-info-panel'),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: Radii.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            head,
            key: const ValueKey('guide-info-head'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.labelMedium,
          ),
          BidiText(
            title,
            key: const ValueKey('guide-info-title'),
            style: theme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (desc != null && desc.isNotEmpty)
            BidiText(desc, maxLines: 2, style: theme.bodySmall),
        ],
      ),
    );
  }
}
