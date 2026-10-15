import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../tv/tv_focusable.dart';
import '../../widgets/bidi_text.dart';
import 'live_models.dart';
import 'preferred_focus.dart';

/// The phone Live layout's category row: horizontally scrolling chips for
/// Favorites, Recent, All channels and the source's categories. Tap selects
/// (OK on a keyboard); a long press opens the category options.
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
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  @override
  void didUpdateWidget(LiveCategoryChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) _revealSelected();
  }

  /// Scrolls the selected chip into view once it is laid out.
  void _revealSelected() {
    afterNextFrame(() {
      final ctx = _selectedKey.currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: FocusTokens.scroll,
      ).ignore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return SizedBox(
      height: LiveCategoryChips.height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        child: Row(
          children: [
            for (final entry in widget.entries)
              Padding(
                key: entry.list == widget.selected ? _selectedKey : null,
                padding: const EdgeInsetsDirectional.only(end: Spacing.sm),
                child: _Chip(
                  key: ValueKey('live-chip-${entry.list.id}'),
                  entry: entry,
                  selected: entry.list == widget.selected,
                  style: theme.labelLarge,
                  onSelect: () => widget.onSelectList?.call(entry.list),
                  onMenu: widget.onMenu == null
                      ? null
                      : () => widget.onMenu!(entry),
                ),
              ),
          ],
        ),
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
