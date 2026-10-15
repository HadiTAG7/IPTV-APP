import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';

/// Help and legal guidance.
///
/// Placeholder until the feature is built. Screens render body content only;
/// the home shells (and pushed routes) provide the Scaffold and app bar.
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.helpTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: Spacing.sm),
          Text(l10n.commonEmpty, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
