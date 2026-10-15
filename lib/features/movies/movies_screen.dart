import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';

/// Movie categories, poster grid and details.
///
/// Placeholder until the feature is built. Screens render body content only;
/// the home shells (and pushed routes) provide the Scaffold and app bar.
class MoviesScreen extends ConsumerWidget {
  const MoviesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.navMovies, style: theme.textTheme.headlineSmall),
          const SizedBox(height: Spacing.sm),
          Text(l10n.commonEmpty, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
