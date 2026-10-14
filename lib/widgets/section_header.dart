import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'bidi_text.dart';

/// Title above a row or grid ("Continue watching", category names), with an
/// optional trailing widget such as a count or a "See all" button.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsetsDirectional.only(
      top: Spacing.lg,
      bottom: Spacing.sm,
    ),
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: BidiText(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: Spacing.md),
            DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: AppColors.textSecondary),
              child: trailing,
            ),
          ],
        ],
      ),
    );
  }
}
