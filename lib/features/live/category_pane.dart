import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../tv/tv_focusable.dart';
import '../../widgets/bidi_text.dart';
import 'live_models.dart';
import 'preferred_focus.dart';

/// The category column of the large Live layout: Favorites, the user's own
/// lists, Recent and All channels, then the source's categories with their
/// channel counts.
///
/// Focusing an entry reports it ([onFocusList], the screen switches lists
/// after a short pause); OK reports [onSelectList] (switch now and move to
/// the channels); Menu reports [onMenu]. Focus nodes are kept per entry so
/// list updates (a sync, hiding a category) keep focus on its entry; when
/// the focused entry itself goes, [onFocusedEntryGone] lets the screen pick
/// where focus goes.
class LiveCategoryPane extends StatefulWidget {
  const LiveCategoryPane({
    super.key,
    required this.entries,
    required this.selected,
    this.onFocusList,
    this.onSelectList,
    this.onMenu,
    this.onFocusedEntryGone,
  });

  /// Row height.
  static const itemExtent = 48.0;

  final List<LiveCategoryEntry> entries;
  final LiveList selected;
  final ValueChanged<LiveList>? onFocusList;
  final ValueChanged<LiveList>? onSelectList;
  final ValueChanged<LiveCategoryEntry>? onMenu;

  /// The focused entry left the list (a sync dropped its category). Called
  /// after the frame, before focus falls back to the pane itself.
  final VoidCallback? onFocusedEntryGone;

  @override
  State<LiveCategoryPane> createState() => LiveCategoryPaneState();
}

class LiveCategoryPaneState extends State<LiveCategoryPane> {
  final _nodes = <String, FocusNode>{};
  ScrollController? _scroll;

  /// The selected entry's node, when it is built.
  FocusNode? get selectedNode {
    final node = _nodes[widget.selected.id];
    return isAttached(node) ? node : null;
  }

  FocusNode _nodeFor(LiveList list) =>
      _nodes.putIfAbsent(list.id, () => FocusNode(debugLabel: list.id));

  int _indexOf(LiveList list) =>
      widget.entries.indexWhere((e) => e.list == list);

  /// Whether [list] has an entry.
  bool hasEntry(LiveList list) => _indexOf(list) >= 0;

  /// Focuses the entry of [list], scrolling to it first when needed.
  void focusList(LiveList list) {
    final index = _indexOf(list);
    if (index < 0) return;
    final node = _nodes[list.id];
    if (isAttached(node)) {
      _focusEntry(node!);
      return;
    }
    final c = _scroll;
    if (c != null && c.hasClients) {
      final pos = c.position;
      c.jumpTo(
        (index * LiveCategoryPane.itemExtent -
                (pos.viewportDimension - LiveCategoryPane.itemExtent) / 2)
            .clamp(pos.minScrollExtent, pos.maxScrollExtent),
      );
    }
    afterNextFrame(() {
      if (mounted) _focusEntry(_nodeFor(list));
    });
  }

  /// Focuses an entry moved to on purpose (not by an arrow). The scope's
  /// arrow history goes first, or the next arrow opposite to the last one
  /// would pop back to an old entry (or stay put).
  void _focusEntry(FocusNode node) {
    final scope = node.nearestScope;
    if (scope != null) {
      FocusTraversalGroup.maybeOfNode(node)?.invalidateScopeData(scope);
    }
    node.requestFocus();
  }

  /// Whether [list]'s entry has focus.
  bool hasFocusOn(LiveList list) => _nodes[list.id]?.hasFocus ?? false;

  /// Moves focus off [list] to its neighbour (before hiding it).
  void focusNeighbourOf(LiveList list) {
    final index = _indexOf(list);
    if (index < 0) return;
    final neighbour = index > 0 ? index - 1 : index + 1;
    if (neighbour < widget.entries.length) {
      focusList(widget.entries[neighbour].list);
    }
  }

  @override
  void didUpdateWidget(LiveCategoryPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = {for (final e in widget.entries) e.list.id};
    final lostFocus = _nodes.entries.any(
      (e) => !ids.contains(e.key) && e.value.hasFocus,
    );
    if (lostFocus) {
      afterNextFrame(() {
        if (mounted) widget.onFocusedEntryGone?.call();
      });
    }
    final gone = [
      for (final MapEntry(:key, :value) in _nodes.entries)
        if (!ids.contains(key) && !value.hasFocus) key,
    ];
    if (gone.isEmpty) return;
    final nodes = [for (final id in gone) _nodes.remove(id)!];
    // Their widgets leave the tree in this frame; dispose afterwards.
    afterNextFrame(() {
      for (final node in nodes) {
        node.dispose();
      }
    });
  }

  @override
  void dispose() {
    _scroll?.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _scroll ??= ScrollController(
          initialScrollOffset: _initialOffset(constraints.maxHeight),
        );
        return ListView.builder(
          controller: _scroll,
          itemExtent: LiveCategoryPane.itemExtent,
          itemCount: widget.entries.length,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
          itemBuilder: (context, i) {
            final entry = widget.entries[i];
            return _CategoryTile(
              key: ValueKey('live-category-${entry.list.id}'),
              entry: entry,
              selected: entry.list == widget.selected,
              focusNode: _nodeFor(entry.list),
              onFocus: () => widget.onFocusList?.call(entry.list),
              onSelect: () => widget.onSelectList?.call(entry.list),
              onMenu: widget.onMenu == null
                  ? null
                  : () => widget.onMenu!(entry),
            );
          },
        );
      },
    );
  }

  double _initialOffset(double viewport) {
    final index = _indexOf(widget.selected);
    if (!viewport.isFinite || index <= 0) return 0;
    const extent = LiveCategoryPane.itemExtent;
    final max = math.max(0.0, widget.entries.length * extent - viewport);
    return (index * extent - (viewport - extent) / 2).clamp(0.0, max);
  }
}

IconData _iconFor(LiveList list) => switch (list.kind) {
  LiveListKind.favorites => Icons.star_rounded,
  LiveListKind.channelList => Icons.playlist_play_rounded,
  LiveListKind.recent => Icons.history,
  LiveListKind.all => Icons.view_list_rounded,
  LiveListKind.category => Icons.folder_outlined,
};

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    super.key,
    required this.entry,
    required this.selected,
    required this.focusNode,
    required this.onFocus,
    required this.onSelect,
    this.onMenu,
  });

  final LiveCategoryEntry entry;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onFocus;
  final VoidCallback onSelect;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final color = selected ? AppColors.accent : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
      child: TvFocusable(
        focusNode: focusNode,
        focusScale: 1.03,
        semanticLabel: '${entry.name} ${entry.count}',
        onFocusChange: (focused) {
          if (focused) onFocus();
        },
        onSelect: onSelect,
        onMenu: onMenu,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          decoration: BoxDecoration(
            color: selected ? AppColors.surfaceHigh : null,
            borderRadius: Radii.mdAll,
          ),
          child: Row(
            children: [
              if (!entry.list.isCategory) ...[
                Icon(_iconFor(entry.list), size: 18, color: color),
                const SizedBox(width: Spacing.sm),
              ],
              Expanded(
                child: BidiText(
                  entry.name,
                  style: theme.titleSmall?.copyWith(color: color),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                '${entry.count}',
                textDirection: TextDirection.ltr,
                style: theme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
