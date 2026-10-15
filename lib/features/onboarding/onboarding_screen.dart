import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/form_factor.dart';
import '../../app/home_shell.dart';
import '../../app/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';
import '../../tv/focus_watchdog.dart';
import '../../tv/tv_focusable.dart';
import '../sources/source_editor_screen.dart';
import '../sources/widgets/row_traversal.dart';
import '../sources/widgets/tv_buttons.dart';

/// First-run flow: language, the player-only disclaimer (Learn more opens
/// Help) and Add a source, which opens the source editor.
///
/// Shown by the root gate (inside its `Scaffold`) while there is no source.
/// The editor imports the first source and then returns to the root, where
/// the home shell takes over.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _arabicNode = FocusNode(debugLabel: 'onboarding-lang-ar');
  final _englishNode = FocusNode(debugLabel: 'onboarding-lang-en');
  FocusWatchdogState? _watchdog;
  FocusNode? _registered;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final watchdog = FocusWatchdog.maybeOf(context);
    final preferred = _nodeFor(Localizations.localeOf(context).languageCode);
    if (watchdog != _watchdog || preferred != _registered) {
      if (_registered case final old?) _watchdog?.unregister(old);
      _watchdog = watchdog?..register(preferred);
      _registered = preferred;
    }
  }

  @override
  void dispose() {
    if (_registered case final node?) _watchdog?.unregister(node);
    _arabicNode.dispose();
    _englishNode.dispose();
    super.dispose();
  }

  FocusNode _nodeFor(String language) =>
      language == 'ar' ? _arabicNode : _englishNode;

  void _setLanguage(AppLocaleSetting locale) {
    unawaited(
      ref
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(locale: locale)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final formFactor = FormFactorScope.of(context);
    final large = isLargeLayout(context);
    final language = Localizations.localeOf(context).languageCode;

    return Padding(
      padding: overscanPadding(formFactor),
      child: Center(
        child: FocusTraversalGroup(
          policy: RowTraversalPolicy(),
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: large ? Spacing.xl : Spacing.lg,
              vertical: large ? Spacing.lg : Spacing.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.live_tv, size: 40, color: AppColors.accent),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    l10n.onboardingWelcomeTitle,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    l10n.onboardingWelcomeBody,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: large ? Spacing.lg : Spacing.xl),
                  Text(
                    l10n.onboardingChooseLanguage,
                    style: theme.textTheme.titleSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Spacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _LanguageButton(
                          key: const ValueKey('onboarding-lang-ar'),
                          focusNode: _arabicNode,
                          autofocus: language == 'ar',
                          label: l10n.languageArabic,
                          textDirection: TextDirection.rtl,
                          selected: language == 'ar',
                          onSelect: () => _setLanguage(AppLocaleSetting.ar),
                        ),
                      ),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: _LanguageButton(
                          key: const ValueKey('onboarding-lang-en'),
                          focusNode: _englishNode,
                          autofocus: language != 'ar',
                          label: l10n.languageEnglish,
                          textDirection: TextDirection.ltr,
                          selected: language != 'ar',
                          onSelect: () => _setLanguage(AppLocaleSetting.en),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: large ? Spacing.lg : Spacing.xl),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: Spacing.sm),
                      Flexible(
                        child: Text(
                          l10n.onboardingDisclaimer,
                          key: const ValueKey('onboarding-disclaimer'),
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.sm),
                  Center(
                    child: TvButton(
                      key: const ValueKey('onboarding-learn-more'),
                      height: 36,
                      icon: Icons.help_outline,
                      label: l10n.onboardingLearnMore,
                      onSelect: () =>
                          unawaited(pushHomePage(context, ref, HomeTab.help)),
                    ),
                  ),
                  SizedBox(height: large ? Spacing.lg : Spacing.xl),
                  Text(
                    l10n.onboardingAddSourceBody,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Spacing.sm),
                  TvButton(
                    key: const ValueKey('onboarding-add-source'),
                    primary: true,
                    expand: true,
                    height: 48,
                    icon: Icons.add,
                    label: l10n.onboardingAddSourceTitle,
                    onSelect: () =>
                        unawaited(openSourceEditor(context, onboarding: true)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the two big language buttons, labelled in its own language.
class _LanguageButton extends StatelessWidget {
  const _LanguageButton({
    super.key,
    required this.focusNode,
    required this.autofocus,
    required this.label,
    required this.textDirection,
    required this.selected,
    required this.onSelect,
  });

  final FocusNode focusNode;
  final bool autofocus;
  final String label;
  final TextDirection textDirection;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              height: 64,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.accent.withValues(alpha: 0.18)
                    : (highlighted
                          ? AppColors.surfaceHighest
                          : AppColors.surfaceHigh),
                borderRadius: Radii.mdAll,
                border: Border.all(
                  color: selected ? AppColors.accent : AppColors.outline,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selected) ...[
                    const Icon(
                      Icons.check_circle,
                      size: 22,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: Spacing.sm),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textDirection: textDirection,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge,
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
