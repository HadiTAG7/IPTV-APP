import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../tv/tv_focusable.dart';
import '../../widgets/bidi_text.dart';
import '../../widgets/section_header.dart';

/// One row of the Settings list.
///
/// * Large layout (TV, desktop, wide landscape): a [TvFocusable] row with
///   the current [value] on the end side; OK calls [onSelect].
/// * Phone layout: a standard [ListTile].
///
/// Rows without [onSelect] still take focus on the large layout, so a remote
/// can scroll to them.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.large,
    required this.icon,
    required this.title,
    this.subtitle,
    this.detail,
    this.detailColor,
    this.value,
    this.valueDirection,
    this.titleDirection,
    this.trailing,
    this.onSelect,
    this.autofocus = false,
    this.focusNode,
  });

  final bool large;
  final IconData icon;
  final String title;
  final String? subtitle;

  /// A further line in its own direction, e.g. an error message.
  final String? detail;
  final Color? detailColor;

  /// The current value, shown on the end side.
  final String? value;

  /// Direction of [value] (e.g. LTR for `-1:30`); detected when null.
  final TextDirection? valueDirection;

  /// Direction of [title] (e.g. LTR for a URL); detected when null.
  final TextDirection? titleDirection;

  /// Shown after the value, e.g. a switch or a spinner.
  final Widget? trailing;
  final VoidCallback? onSelect;
  final bool autofocus;
  final FocusNode? focusNode;

  static const double _valueMaxWidth = 220;

  @override
  Widget build(BuildContext context) => large ? _large(context) : _phone();

  Widget _title(TextStyle? style) {
    final direction = titleDirection;
    if (direction == null) return BidiText(title, style: style, maxLines: 2);
    // Laid out in its own direction, aligned with the ambient start edge.
    return Builder(
      builder: (context) => Text(
        title,
        style: style,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textDirection: direction,
        textAlign: Directionality.of(context) == TextDirection.rtl
            ? TextAlign.right
            : TextAlign.left,
      ),
    );
  }

  Widget _value(String value, TextStyle? style) => Text(
    value,
    style: style,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textDirection: valueDirection ?? textDirectionFor(value),
  );

  Widget _large(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final subtitle = this.subtitle;
    final detail = this.detail;
    final value = this.value;
    final trailing = this.trailing;
    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      focusScale: 1.02,
      semanticLabel: value == null ? title : '$title: $value',
      onSelect: onSelect,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: Radii.mdAll,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _title(theme.titleSmall),
                  if (subtitle != null)
                    BidiText(
                      subtitle,
                      maxLines: 2,
                      style: theme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  if (detail != null)
                    BidiText(
                      detail,
                      maxLines: 2,
                      style: theme.bodySmall?.copyWith(color: detailColor),
                    ),
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: Spacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _valueMaxWidth),
                child: _value(
                  value,
                  theme.bodyMedium?.copyWith(color: AppColors.accent),
                ),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: Spacing.sm),
              trailing,
            ] else if (onSelect != null) ...[
              const SizedBox(width: Spacing.xs),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _phone() {
    final subtitle = this.subtitle;
    final detail = this.detail;
    final value = this.value;
    final trailing = this.trailing;
    final end = <Widget>[
      if (value != null)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: _value(value, null),
        ),
      ?trailing,
    ];
    return ListTile(
      focusNode: focusNode,
      autofocus: autofocus,
      leading: Icon(icon),
      title: _title(null),
      subtitle: subtitle == null && detail == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (subtitle != null) BidiText(subtitle, maxLines: 2),
                if (detail != null)
                  BidiText(
                    detail,
                    maxLines: 2,
                    style: TextStyle(color: detailColor),
                  ),
              ],
            ),
      trailing: end.isEmpty
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, w) in end.indexed) ...[
                  if (i > 0) const SizedBox(width: Spacing.sm),
                  w,
                ],
              ],
            ),
      onTap: onSelect,
    );
  }
}

/// A section title of the Settings list, with an optional second line.
class SettingsSection extends StatelessWidget {
  const SettingsSection(
    this.title, {
    super.key,
    required this.large,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    final header = SectionHeader(
      title,
      padding: large
          ? const EdgeInsetsDirectional.only(
              top: Spacing.lg,
              bottom: Spacing.xs,
            )
          : const EdgeInsetsDirectional.fromSTEB(
              Spacing.lg,
              Spacing.lg,
              Spacing.lg,
              Spacing.xs,
            ),
    );
    if (subtitle == null) return header;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: large ? 0 : Spacing.lg,
            end: large ? 0 : Spacing.lg,
            bottom: Spacing.sm,
          ),
          child: BidiText(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}
