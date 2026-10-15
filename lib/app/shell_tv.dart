import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../theme/tokens.dart';
import '../tv/focus_watchdog.dart';
import '../tv/pane_scope.dart';
import '../tv/tv_focusable.dart';
import '../widgets/bidi_text.dart';
import 'form_factor.dart';
import 'home_shell.dart';
import 'providers.dart';

/// Large-layout home (TV, desktop, wide tablets): a focusable rail on the
/// start side (the right in Arabic) and the selected tab's page.
///
/// * The rail and the content are separate [PaneScope]s. Moving toward the
///   content from the rail's end edge enters the page (its remembered item);
///   moving toward the rail from the page's start edge returns to the
///   selected rail item. Physical arrows are mirrored in RTL.
/// * Focusing a rail item shows its tab; OK also moves into the page.
/// * Pages live in an [IndexedStack] that builds a tab on first visit and
///   keeps its state; each page has its own focus scope, so returning to a
///   tab restores its focused item.
/// * Inner panes of a page should leave `onExitStart` unset on their first
///   pane: the content pane then takes focus back to the rail.
class TvShell extends ConsumerStatefulWidget {
  const TvShell({super.key});

  static const railWidth = 176.0;

  @override
  ConsumerState<TvShell> createState() => TvShellState();
}

class TvShellState extends ConsumerState<TvShell> {
  static const tabs = HomeTab.tvTabs;

  final _railKey = GlobalKey<PaneScopeState>();
  final _contentKey = GlobalKey<PaneScopeState>();
  late final List<FocusNode> _tabNodes = [
    for (final t in tabs) FocusNode(debugLabel: 'rail:${t.name}'),
  ];
  late final List<FocusScopeNode> _pageScopes = [
    for (final t in tabs) FocusScopeNode(debugLabel: 'page:${t.name}'),
  ];
  final _backs = [for (final _ in tabs) HomeBackRegistry()];
  final _visited = <int>{0};
  int _index = 0;
  FocusWatchdogState? _watchdog;

  /// The selected tab.
  HomeTab get current => tabs[_index];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The watchdog may restore focus before autofocus applies; make the
    // selected rail item its fallback so the first focus lands there.
    final watchdog = FocusWatchdog.maybeOf(context);
    if (watchdog != _watchdog) {
      _watchdog?.unregister(_tabNodes[_index]);
      _watchdog = watchdog?..register(_tabNodes[_index]);
    }
  }

  @override
  void dispose() {
    for (final n in _tabNodes) {
      _watchdog?.unregister(n);
    }
    for (final n in _tabNodes) {
      n.dispose();
    }
    for (final n in _pageScopes) {
      n.dispose();
    }
    super.dispose();
  }

  /// Back inside a page: the page's [HomeTabBackHandler]s, else to the
  /// rail. On the rail: not handled (the home screen offers to exit).
  bool handleBack() {
    if (!(_contentKey.currentState?.hasFocus ?? false)) return false;
    if (_backs[_index].handle()) return true;
    _focusRail();
    return true;
  }

  /// Shows [tab] (and, with [enter], moves focus into its page).
  void select(HomeTab tab, {bool enter = false}) {
    final i = tabs.indexOf(tab);
    if (i < 0) return;
    _select(i);
    if (enter) _enterContentAfterBuild();
  }

  void _select(int i) {
    if (i == _index && _visited.contains(i)) return;
    setState(() {
      _index = i;
      _visited.add(i);
    });
  }

  void _focusRail() => _tabNodes[_index].requestFocus();

  bool _enterContent() => focusRememberedOrFirst(_pageScopes[_index]);

  void _enterContentAfterBuild() {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted) _enterContent();
      })
      ..ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final pageFor = ref.watch(homePageBuilderProvider);
    final formFactor = FormFactorScope.of(context);
    return Scaffold(
      body: Padding(
        padding: overscanPadding(formFactor),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: TvShell.railWidth,
              child: PaneScope(
                key: _railKey,
                debugLabel: 'rail',
                onExitEnd: _enterContent,
                child: _Rail(
                  tabs: tabs,
                  nodes: _tabNodes,
                  selected: _index,
                  onFocusTab: _select,
                  onSelectTab: (i) {
                    _select(i);
                    _enterContentAfterBuild();
                  },
                ),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: PaneScope(
                      key: _contentKey,
                      debugLabel: 'content',
                      onExitStart: _focusRail,
                      child: IndexedStack(
                        index: _index,
                        sizing: StackFit.expand,
                        children: [
                          for (final (i, tab) in tabs.indexed)
                            FocusScope(
                              node: _pageScopes[i],
                              child: HomeBackScope(
                                registry: _backs[i],
                                child: _visited.contains(i)
                                    ? KeyedSubtree(
                                        key: ValueKey(tab),
                                        child: pageFor(tab),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const PositionedDirectional(
                    top: 0,
                    start: 0,
                    end: 0,
                    child: SyncIndicator(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rail extends ConsumerWidget {
  const _Rail({
    required this.tabs,
    required this.nodes,
    required this.selected,
    required this.onFocusTab,
    required this.onSelectTab,
  });

  final List<HomeTab> tabs;
  final List<FocusNode> nodes;
  final int selected;
  final ValueChanged<int> onFocusTab;
  final ValueChanged<int> onSelectTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: AppColors.surface,
      borderRadius: Radii.lgAll,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SourceSwitcherButton(),
            const SizedBox(height: Spacing.sm),
            for (final (i, tab) in tabs.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
                child: _RailItem(
                  key: ValueKey('rail-${tab.name}'),
                  icon: tab.icon,
                  label: tab.label(l10n),
                  selected: i == selected,
                  focusNode: nodes[i],
                  autofocus: i == selected,
                  onFocus: () => onFocusTab(i),
                  onSelect: () => onSelectTab(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.focusNode,
    required this.autofocus,
    required this.onFocus,
    required this.onSelect,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final FocusNode focusNode;
  final bool autofocus;
  final VoidCallback onFocus;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? AppColors.accent : AppColors.textSecondary;
    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      focusScale: 1.03,
      semanticLabel: label,
      onFocusChange: (focused) {
        if (focused) onFocus();
      },
      onSelect: onSelect,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent.withValues(alpha: 0.14) : null,
          borderRadius: Radii.mdAll,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? AppColors.textPrimary : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Active source name; OK opens the source switcher.
class _SourceSwitcherButton extends ConsumerWidget {
  const _SourceSwitcherButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final source = ref.watch(activeSourceProvider);
    final count = ref.watch(sourcesProvider).value?.length ?? 0;
    return TvFocusable(
      key: const ValueKey('rail-source'),
      focusScale: 1.03,
      semanticLabel: l10n.navSwitchSource,
      enabled: count > 0,
      onSelect: () => showSourceSwitcher(context, ref),
      child: Container(
        padding: const EdgeInsets.all(Spacing.sm),
        decoration: const BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: Radii.mdAll,
        ),
        child: Row(
          children: [
            const Icon(Icons.playlist_play, size: 20, color: AppColors.accent),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: BidiText(
                source?.name ?? l10n.settingsNoSources,
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (count > 1)
              const Icon(
                Icons.unfold_more,
                size: 18,
                color: AppColors.textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}
