import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';
import '../../../tv/tv_focusable.dart';

/// A remote-friendly button: a [TvFocusable] (focus ring, scale, scroll
/// into view, OK / tap) around a pill with an optional icon.
///
/// It never disables itself while [busy] (a disabled control would drop the
/// remote's focus); presses are ignored instead and a spinner replaces the
/// icon.
class TvButton extends StatelessWidget {
  const TvButton({
    super.key,
    required this.label,
    required this.onSelect,
    this.icon,
    this.focusNode,
    this.autofocus = false,
    this.primary = false,
    this.busy = false,
    this.expand = false,
    this.height = 44,
  });

  final String label;
  final VoidCallback onSelect;
  final IconData? icon;
  final FocusNode? focusNode;
  final bool autofocus;

  /// The screen's main action (accent fill).
  final bool primary;
  final bool busy;

  /// Fills the available width.
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      focusScale: 1.04,
      onSelect: busy ? () {} : onSelect,
      child: Builder(
        builder: (context) {
          final highlighted = TvHighlight.of(context);
          final theme = Theme.of(context);
          final foreground = primary
              ? AppColors.onAccent
              : AppColors.textPrimary;
          final background = primary
              ? (highlighted
                    ? Color.lerp(AppColors.accent, Colors.white, 0.3)!
                    : AppColors.accent)
              : (highlighted
                    ? AppColors.surfaceHighest
                    : AppColors.surfaceHigh);
          return Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            decoration: BoxDecoration(
              color: background,
              borderRadius: Radii.mdAll,
              border: primary && highlighted
                  ? Border.all(color: AppColors.textPrimary, width: 2)
                  : null,
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  )
                else if (icon case final icon?)
                  Icon(icon, size: 20, color: foreground),
                if (busy || icon != null) const SizedBox(width: Spacing.sm),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A selectable option (source type, User-Agent preset, live format...).
class TvChoiceChip extends StatelessWidget {
  const TvChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelect,
    this.icon,
    this.subtitle,
    this.focusNode,
    this.autofocus = false,
    this.minWidth = 0,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final IconData? icon;
  final String? subtitle;
  final FocusNode? focusNode;
  final bool autofocus;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: TvFocusable(
        focusNode: focusNode,
        autofocus: autofocus,
        focusScale: 1.04,
        onSelect: onSelect,
        child: Builder(
          builder: (context) {
            final highlighted = TvHighlight.of(context);
            return Container(
              constraints: BoxConstraints(minWidth: minWidth, minHeight: 40),
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.accent.withValues(alpha: 0.18)
                    : (highlighted
                          ? AppColors.surfaceHighest
                          : AppColors.surfaceHigh),
                borderRadius: Radii.mdAll,
                border: Border.all(
                  color: selected ? AppColors.accent : AppColors.outline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected
                        ? Icons.check_circle
                        : (icon ?? Icons.radio_button_unchecked),
                    size: 18,
                    color: selected
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
