import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_shell.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';
import '../../tv/focus_watchdog.dart';
import '../../tv/tv_focusable.dart';
import 'providers.dart';

/// Help and legal guidance: the app is only a player, free legal sources
/// (the iptv-org playlists, shown as text to type), official apps, the
/// warning signs of unlicensed sellers, and how to install updates.
///
/// Every section is a focus stop, so a remote scrolls the page with Up and
/// Down. "Add as source" shows only when the app provides a source editor
/// ([addSourcePrefillProvider]); the app never adds a playlist on its own.
///
/// Renders body content only (pushed pages get their app bar and, on TV,
/// overscan margins from `pushHomePage`).
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  final _firstNode = FocusNode(debugLabel: 'help:first');
  final _scroll = ScrollController();
  FocusWatchdogState? _watchdog;

  /// Whether this page is a home-shell tab (not a pushed page).
  bool get _inTab => HomeBackScope.maybeOf(context) != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pushed, the first section is autofocused; make it the watchdog's
    // fallback too so a racing restore does not pick the app bar instead.
    final watchdog = _inTab ? null : FocusWatchdog.maybeOf(context);
    if (watchdog != _watchdog) {
      _watchdog?.unregister(_firstNode);
      _watchdog = watchdog?..register(_firstNode);
    }
  }

  @override
  void dispose() {
    _watchdog?.unregister(_firstNode);
    _firstNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inTab = _inTab;
    final prefill = ref.watch(addSourcePrefillProvider);

    AddSourceCallback? addFor(String url, String name) =>
        prefill == null ? null : () => prefill(context, url: url, name: name);

    final sections = <Widget>[
      HelpSection(
        key: const ValueKey('help-intro'),
        focusNode: _firstNode,
        autofocus: !inTab,
        body: l10n.helpLegalBody,
        footnote: '${l10n.helpAsOf} · ${l10n.helpNotLegalAdvice}',
      ),
      HelpSection(
        key: const ValueKey('help-player'),
        title: l10n.help_playerOnlyTitle,
        body: l10n.help_playerOnlyBody,
      ),
      HelpSection(
        key: const ValueKey('help-free'),
        title: l10n.help_freeSourcesTitle,
        body: l10n.help_freeSourcesBody,
      ),
      HelpLink(
        key: const ValueKey('help-url-sa'),
        label: l10n.help_iptvOrgSaudi,
        url: kIptvOrgSaudiUrl,
        actionLabel: l10n.help_addAsSource,
        onSelect: addFor(
          kIptvOrgSaudiUrl,
          'iptv-org: ${l10n.help_iptvOrgSaudi}',
        ),
      ),
      HelpLink(
        key: const ValueKey('help-url-ara'),
        label: l10n.help_iptvOrgArabic,
        url: kIptvOrgArabicUrl,
        actionLabel: l10n.help_addAsSource,
        onSelect: addFor(
          kIptvOrgArabicUrl,
          'iptv-org: ${l10n.help_iptvOrgArabic}',
        ),
      ),
      HelpSection(
        key: const ValueKey('help-receiver'),
        body: l10n.help_receiverBody,
      ),
      HelpSection(
        key: const ValueKey('help-official'),
        title: l10n.help_officialAppsTitle,
        body: l10n.help_officialAppsBody,
      ),
      HelpSection(
        key: const ValueKey('help-warning'),
        title: l10n.helpWarningSignsTitle,
        body: '${l10n.helpWarningSigns}\n${l10n.help_warningSignsMore}',
        footnote: l10n.help_legitServices,
      ),
      HelpSection(
        key: const ValueKey('help-updates'),
        title: l10n.help_updatesTitle,
        body: l10n.help_updatesBody,
      ),
      HelpLink(
        key: const ValueKey('help-url-apk'),
        label: l10n.help_downloadLink,
        url: kLatestApkUrl,
      ),
    ];

    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.all(Spacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Spacing.md,
              children: sections,
            ),
          ),
        ),
      ),
    );
  }
}

/// Signature of the "Add as source" action of a [HelpLink].
typedef AddSourceCallback = void Function();

/// A focusable block of help text: optional [title], [body] and a smaller
/// [footnote].
class HelpSection extends StatelessWidget {
  const HelpSection({
    super.key,
    required this.body,
    this.title,
    this.footnote,
    this.focusNode,
    this.autofocus = false,
  });

  final String? title;
  final String body;
  final String? footnote;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final title = this.title;
    final footnote = this.footnote;
    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      focusScale: 1,
      // Show a section from its top, so long ones read from the start.
      ensureVisibleAlignment: 0.1,
      child: Container(
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: Radii.mdAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Semantics(
                header: true,
                child: Text(title, style: theme.titleMedium),
              ),
              const SizedBox(height: Spacing.sm),
            ],
            Text(body, style: theme.bodyMedium?.copyWith(height: 1.5)),
            if (footnote != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                footnote,
                style: theme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A playlist or download link shown as text the user can type (always left
/// to right). With [onSelect], OK (or a tap) runs it and an [actionLabel]
/// button look is shown on the end side.
class HelpLink extends StatelessWidget {
  const HelpLink({
    super.key,
    required this.label,
    required this.url,
    this.actionLabel,
    this.onSelect,
  });

  final String label;
  final String url;
  final String? actionLabel;
  final AddSourceCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final actionLabel = this.actionLabel;
    final showAction = onSelect != null && actionLabel != null;
    return TvFocusable(
      focusScale: 1.02,
      semanticLabel: showAction ? '$label, $actionLabel' : label,
      onSelect: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.md,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: Radii.mdAll,
        ),
        child: Row(
          children: [
            const Icon(Icons.link, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(label, style: theme.titleSmall),
                  const SizedBox(height: Spacing.xxs),
                  // A URL reads left to right, aligned with the label.
                  Text(
                    url,
                    textDirection: TextDirection.ltr,
                    textAlign: Directionality.of(context) == TextDirection.rtl
                        ? TextAlign.right
                        : TextAlign.left,
                    style: theme.bodyMedium?.copyWith(color: AppColors.accent),
                  ),
                ],
              ),
            ),
            if (showAction) ...[
              const SizedBox(width: Spacing.md),
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: Radii.mdAll,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.lg,
                    vertical: Spacing.sm,
                  ),
                  child: Text(
                    actionLabel,
                    style: theme.labelLarge?.copyWith(
                      color: AppColors.onAccent,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
