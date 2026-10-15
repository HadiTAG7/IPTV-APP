import 'package:flutter/material.dart';

import '../../app/form_factor.dart';
import '../../theme/tokens.dart';
import '../../widgets/poster_card.dart';
import '../live/preferred_focus.dart';

/// One poster of a [PosterGrid].
@immutable
class PosterItem {
  const PosterItem({
    required this.key,
    required this.title,
    this.posterUrl,
    this.progress,
  });

  /// Stable item key (focus is kept per key).
  final String key;
  final String title;
  final String? posterUrl;
  final double? progress;
}

/// A remote-friendly grid of 2:3 posters: 6 columns on TV, 3 on phones,
/// fixed cell extents, one focus node per item key (so reloads keep focus).
class PosterGrid extends StatefulWidget {
  const PosterGrid({
    super.key,
    required this.items,
    this.onSelect,
    this.onMenu,
  });

  final List<PosterItem> items;
  final ValueChanged<PosterItem>? onSelect;
  final ValueChanged<PosterItem>? onMenu;

  @override
  State<PosterGrid> createState() => PosterGridState();
}

class PosterGridState extends State<PosterGrid> {
  final _nodes = <String, FocusNode>{};

  /// The first poster's node, when it is built (entry point of the grid).
  FocusNode? get firstNode {
    if (widget.items.isEmpty) return null;
    final node = _nodes[widget.items.first.key];
    return isAttached(node) ? node : null;
  }

  FocusNode _nodeFor(String key) =>
      _nodes.putIfAbsent(key, () => FocusNode(debugLabel: 'poster-$key'));

  /// Moves focus off [key] to a neighbour (before the item disappears).
  void focusNeighbourOf(String key) {
    final i = widget.items.indexWhere((item) => item.key == key);
    if (i < 0) return;
    final n = i + 1 < widget.items.length ? i + 1 : i - 1;
    if (n < 0) return;
    final node = _nodes[widget.items[n].key];
    if (isAttached(node)) node!.requestFocus();
  }

  @override
  void didUpdateWidget(PosterGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final keys = {for (final item in widget.items) item.key};
    final gone = [
      for (final MapEntry(:key, :value) in _nodes.entries)
        if (!keys.contains(key) && !value.hasFocus) key,
    ];
    if (gone.isEmpty) return;
    final nodes = [for (final key in gone) _nodes.remove(key)!];
    afterNextFrame(() {
      for (final node in nodes) {
        node.dispose();
      }
    });
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final large = useLargeLayout(
      FormFactorScope.of(context),
      MediaQuery.sizeOf(context),
    );
    final columns = large
        ? TvLayout.posterColumnsTv
        : TvLayout.posterColumnsPhone;
    const spacing = Spacing.md;
    const padding = Spacing.md;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            (constraints.maxWidth - 2 * padding - (columns - 1) * spacing) /
            columns;
        return GridView.builder(
          padding: const EdgeInsets.all(padding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: Spacing.lg,
            mainAxisExtent: PosterCard.heightForWidth(width < 1 ? 1 : width),
          ),
          itemCount: widget.items.length,
          itemBuilder: (context, i) {
            final item = widget.items[i];
            return PosterCard(
              key: ValueKey('poster-${item.key}'),
              focusNode: _nodeFor(item.key),
              title: item.title,
              posterUrl: item.posterUrl,
              progress: item.progress,
              onSelect: widget.onSelect == null
                  ? null
                  : () => widget.onSelect!(item),
              onMenu: widget.onMenu == null ? null : () => widget.onMenu!(item),
            );
          },
        );
      },
    );
  }
}
