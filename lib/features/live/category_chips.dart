import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../tv/tv_focusable.dart';
import '../../widgets/bidi_text.dart';
import 'live_models.dart';
import 'preferred_focus.dart';

/// The phone Live layout's category row: horizontally scrolling chips for
/// Favorites, Recent, All channels and the source's categories. Tap selects
/// (OK on a keyboard); a long press opens the category options.
///
/// Chips are built lazily: big providers list thousands of categories.
class LiveCategoryChips extends StatefulWidget {
  const LiveCategoryChips({
    super.key,
    required this.entries,
    required this.selected,
    this.onSelectList,
    this.onMenu,
  });

  static const height = 52.0;

  final List<LiveCategoryEntry> entries;
  final LiveList selected;
  final ValueChanged<LiveList>? onSelectList;
  final ValueChanged<LiveCategoryEntry>? onMenu;

  @override
  State<LiveCategoryChips> createState() => _LiveCategoryChipsState();
}

class _LiveCategoryChipsState extends State<LiveCategoryChips> {
  static const _keyPrefix = 'live-chip-';

  /// Jumps toward a selected chip that is not built yet before revealing it.
  static const _revealJumps = 4;

  final _scroll = ScrollController();

  /// One key per list id, so a chip keeps its state (and focus) when it is
  /// selected and the selected one can be found.
  final _chipKeys = <String, GlobalKey>{};
  Map<String, int> _indexById = const {};

  @override
  void initState() {
    super.initState();
    _index();
    _revealSelected();
  }

  @override
  void didUpdateWidget(LiveCategoryChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entries, widget.entries)) _index();
    if (oldWidget.selected != widget.selected) _revealSelected();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _index() {
    _indexById = {for (final (i, e) in widget.entries.indexed) e.list.id: i};
    _chipKeys.removeWhere((id, _) => !_indexById.containsKey(id));
  }

  GlobalKey _keyFor(LiveList list) =>
      _chipKeys.putIfAbsent(list.id, () => GlobalKey(debugLabel: list.id));

  /// Scrolls the selected chip into view once it is laid out. A chip far
  /// along the row is not built yet: jump to where it should be (from the
  /// average size of the chips built so far) and try again.
  void _revealSelected([int jumps = _revealJumps]) {
    afterNextFrame(() {
      if (!mounted) return;
      final selected = widget.selected;
      final ctx = _chipKeys[selected.id]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: jumps == _revealJumps
              ? FocusTokens.scrollOf(context)
              : Duration.zero,
        ).ignore();
        return;
      }
      final index = _indexById[selected.id];
      if (jumps == 0 || index == null || !_scroll.hasClients) return;
      final position = _scroll.position;
      final total = position.maxScrollExtent + position.viewportDimension;
      final target =
          total * index / widget.entries.length -
          position.viewportDimension / 2;
      _scroll.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      _revealSelected(jumps - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final entries = widget.entries;
    return SizedBox(
      height: LiveCategoryChips.height,
      child: ListView.builder(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        itemCount: entries.length,
        findChildIndexCallback: (key) =>
            key is ValueKey<String> && key.value.startsWith(_keyPrefix)
            ? _indexById[key.value.substring(_keyPrefix.length)]
            : null,
        itemBuilder: (context, i) {
          final entry = entries[i];
          return Padding(
            key: ValueKey('$_keyPrefix${entry.list.id}'),
            padding: const EdgeInsetsDirectional.only(end: Spacing.sm),
            child: _Chip(
              key: _keyFor(entry.list),
              entry: entry,
              selected: entry.list == widget.selected,
              style: theme.labelLarge,
              onSelect: () => widget.onSelectList?.call(entry.list),
              onMenu: widget.onMenu == null
                  ? null
                  : () => widget.onMenu!(entry),
            ),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.entry,
    required this.selected,
    required this.onSelect,
    this.style,
    this.onMenu,
  });

  final LiveCategoryEntry entry;
  final bool selected;
  final TextStyle? style;
  final VoidCallback onSelect;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.onAccent : AppColors.textPrimary;
    return TvFocusable(
      focusScale: 1.04,
      borderRadius: BorderRadius.circular(Radii.pill),
      semanticLabel: '${entry.name} ${entry.count}',
      onSelect: onSelect,
      onMenu: onMenu,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.outline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: BidiText(entry.name, style: style?.copyWith(color: fg)),
            ),
            const SizedBox(width: Spacing.xs),
            Text(
              '${entry.count}',
              textDirection: TextDirection.ltr,
              style: style?.copyWith(
                color: selected ? AppColors.onAccent : AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
