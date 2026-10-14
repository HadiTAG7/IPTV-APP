import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../theme/tokens.dart';

/// Centered spinner with an optional message (defaults to "Loading…").
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message ?? AppLocalizations.of(context).commonLoading;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 36,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Empty-state message with an icon and an optional action below it.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  /// Defaults to "Nothing here yet".
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = message ?? AppLocalizations.of(context).commonEmpty;
    return _StateLayout(
      icon: icon,
      iconColor: AppColors.textSecondary,
      message: text,
      action: action,
    );
  }
}

/// Error message with a localized Retry button (autofocused for the remote).
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    this.message,
    this.details,
    this.onRetry,
    this.autofocusRetry = true,
  });

  /// Defaults to "Something went wrong".
  final String? message;

  /// Secondary line, e.g. a redacted technical reason.
  final String? details;
  final VoidCallback? onRetry;
  final bool autofocusRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final retry = onRetry;
    return _StateLayout(
      icon: Icons.error_outline,
      iconColor: AppColors.error,
      message: message ?? l10n.commonErrorGeneric,
      details: details,
      action: retry == null
          ? null
          : FilledButton.icon(
              autofocus: autofocusRetry,
              onPressed: retry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.commonRetry),
            ),
    );
  }
}

class _StateLayout extends StatelessWidget {
  const _StateLayout({
    required this.icon,
    required this.iconColor,
    required this.message,
    this.details,
    this.action,
  });

  final IconData icon;
  final Color iconColor;
  final String message;
  final String? details;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final details = this.details;
    final action = this.action;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: iconColor),
              const SizedBox(height: Spacing.lg),
              Text(
                message,
                style: theme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (details != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  details,
                  style: theme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: Spacing.xl),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin progress bar for watch and programme progress in lists. It fills from
/// the reading-start edge; the player's seek bar is separate and not mirrored.
class ProgressLine extends StatelessWidget {
  const ProgressLine({
    super.key,
    required this.value,
    this.height = 3,
    this.color = AppColors.accent,
    this.trackColor = AppColors.progressTrack,
  });

  /// 0..1; values outside are clamped.
  final double value;
  final double height;
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: ColoredBox(
          color: trackColor,
          child: FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: v,
            heightFactor: 1,
            child: ColoredBox(color: color),
          ),
        ),
      ),
    );
  }
}
