import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_shell.dart';
import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../epg/epg_providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../sources/source_repository.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';
import 'guide_data.dart';
import 'guide_format.dart';
import 'guide_grid.dart';
import 'guide_phone.dart';
import 'guide_widgets.dart';
import 'providers.dart';

/// The TV guide of the active source.
///
/// * Large layout (TV, desktop, wide landscape): a header (title, last
///   update, channel filter, "Refresh guide") above the [GuideGrid].
///   Entering the page from the rail focuses the grid (or, while the page
///   loads, a placeholder in its place); Up from the first row reaches the
///   header buttons. When the body is replaced while it has focus (loaded,
///   guide data arrived, the filter fell back), its successor takes focus.
/// * Phone: a header with refresh, filter chips and the channel list
///   ([GuidePhoneList]); a channel opens its day schedule.
/// * Without any guide data: how to add a guide URL, with Refresh and a
///   way to Settings.
///
/// Renders body content only; the home shells provide the chrome. Keeps
/// [epgAutoRefreshProvider] alive while it exists.
class GuideScreen extends ConsumerWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(epgAutoRefreshProvider, (_, _) {});
    final source = ref.watch(activeSourceProvider);
    if (source == null) return const SizedBox.shrink();
    return _GuidePage(key: ValueKey('guide-${source.id}'), source: source);
  }
}

/// One policy for every rebuild, so directional focus history survives.
final _focusPolicy = OrderedTraversalPolicy();

class _GuidePage extends ConsumerStatefulWidget {
  const _GuidePage({super.key, required this.source});

  final SourceView source;

  static const headerHeight = 36.0;

  @override
  ConsumerState<_GuidePage> createState() => _GuidePageState();
}

/// What the page body shows; focus follows a change of it.
sealed class _Body {
  const _Body();
}

final class _BodyLoading extends _Body {
  const _BodyLoading();
}

final class _BodyError extends _Body {
  const _BodyError();
}

final class _BodyNoData extends _Body {
  const _BodyNoData();
}

final class _BodyChannels extends _Body {
  const _BodyChannels(this.filter);

  final GuideFilter filter;

  @override
  bool operator ==(Object other) =>
      other is _BodyChannels && other.filter == filter;

  @override
  int get hashCode => filter.hashCode;
}

class _GuidePageState extends ConsumerState<_GuidePage> {
  /// Around the body (not focusable itself): whether focus is in it.
  final _bodyNode = FocusNode(
    debugLabel: 'guide-body',
    canRequestFocus: false,
    skipTraversal: true,
  );
  _Body? _body;

  @override
  void dispose() {
    _bodyNode.dispose();
    super.dispose();
  }

  /// Notes the body about to be built. When it replaces one that has focus,
  /// the new body's first item takes focus after the frame; otherwise focus
  /// would go back to what the page focused before (often the header).
  void _bodyChanged(_Body body) {
    if (body == _body) return;
    _body = body;
    if (!_bodyNode.hasFocus) return;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted) return;
        _bodyNode.traversalDescendants
            .where((n) => n is! FocusScopeNode)
            .firstOrNull
            ?.requestFocus();
      })
      ..ensureVisualUpdate();
  }

  void _onStatus(
    BuildContext context,
    AppLocalizations l10n,
    GuideRefreshStatus? previous,
    GuideRefreshStatus next,
  ) {
    // Only for runs the user started ("Refresh guide").
    if (previous is! GuideRefreshRunning || !previous.forced) return;
    final message = switch (next) {
      GuideRefreshFailed(cancelled: false) => l10n.guideRefreshFailed,
      GuideRefreshDone(:final result) when result.guides == 0 =>
        l10n.guideEmpty,
      _ => null,
    };
    if (message == null) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final l10n = AppLocalizations.of(context);
    final id = source.id;
    final large = isLargeLayout(context);
    final hasData = ref.watch(guideHasDataProvider(id));
    final favorites = ref.watch(guideFavoriteKeysProvider(id));
    final categories = ref.watch(guideCategoriesProvider(id));
    final picked = ref.watch(guideFilterProvider(id));
    final status = ref.watch(guideRefreshProvider(id));
    ref.listen<GuideRefreshStatus>(
      guideRefreshProvider(id),
      (previous, next) => _onStatus(context, l10n, previous, next),
    );

    final favoriteKeys = favorites.value ?? const <String>[];
    final categoryRows = categories.value ?? const <CategoryRow>[];
    final filter = effectiveGuideFilter(picked, favoriteKeys, categories.value);
    if (picked == null && favorites.hasValue) {
      // Keep the default once known, so the list does not jump when a
      // favourite is added elsewhere.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(guideFilterProvider(id)) == null) {
          ref.read(guideFilterProvider(id).notifier).select(filter);
        }
      });
    }
    final options = guideFilterOptions(
      l10n,
      favoriteKeys: favoriteKeys,
      categories: categoryRows,
    );

    void refresh() =>
        ref.read(guideRefreshProvider(id).notifier).refresh(force: true);
    void select(GuideFilter f) =>
        ref.read(guideFilterProvider(id).notifier).select(f);
    Future<void> pickFilter() async {
      final f = await showGuideFilterPicker(
        context,
        options: options,
        current: filter,
      );
      if (f != null) select(f);
    }

    final Widget body;
    if (hasData.hasError) {
      _bodyChanged(const _BodyError());
      body = ErrorView(
        autofocusRetry: false,
        onRetry: () => ref.invalidate(guideHasDataProvider(id)),
      );
    } else if (!hasData.hasValue || !favorites.hasValue) {
      _bodyChanged(const _BodyLoading());
      // Focusable, so entering the page now lands in the body.
      body = const FocusTraversalOrder(
        order: NumericFocusOrder(0),
        child: Focus(debugLabel: 'guide-loading', child: LoadingView()),
      );
    } else if (hasData.value != true) {
      _bodyChanged(const _BodyNoData());
      body = GuideNoData(
        running: status.isRunning,
        onRefresh: refresh,
        onSettings: () =>
            unawaited(pushHomePage(context, ref, HomeTab.settings)),
      );
    } else if (large) {
      _bodyChanged(_BodyChannels(filter));
      body = GuideGrid(
        key: ValueKey(filter),
        sourceId: id,
        filter: filter,
        favoriteKeys: favoriteKeys,
        catalogVersion: source.generation,
      );
    } else {
      _bodyChanged(_BodyChannels(filter));
      body = GuidePhoneList(
        key: ValueKey(filter),
        sourceId: id,
        filter: filter,
        favoriteKeys: favoriteKeys,
        catalogVersion: source.generation,
      );
    }

    final filterLabel = filter.label(l10n, categoryRows);
    final Widget page;
    if (large) {
      page = MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _GuidePage.headerHeight,
              child: _TvHeader(
                updatedAt: source.lastEpgAt,
                filterLabel: filterLabel,
                running: status.isRunning,
                onFilter: () => unawaited(pickFilter()),
                onRefresh: refresh,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Expanded(
              child: Focus(focusNode: _bodyNode, child: body),
            ),
          ],
        ),
      );
    } else {
      page = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhoneHeader(
            updatedAt: source.lastEpgAt,
            running: status.isRunning,
            onRefresh: refresh,
          ),
          _FilterChips(options: options, current: filter, onSelect: select),
          Expanded(
            child: Focus(focusNode: _bodyNode, child: body),
          ),
        ],
      );
    }
    // The grid (or the empty state's Refresh) comes first in focus order.
    return FocusTraversalGroup(policy: _focusPolicy, child: page);
  }
}

class _TvHeader extends StatelessWidget {
  const _TvHeader({
    required this.updatedAt,
    required this.filterLabel,
    required this.running,
    required this.onFilter,
    required this.onRefresh,
  });

  final DateTime? updatedAt;
  final String filterLabel;
  final bool running;
  final VoidCallback onFilter;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final updated = updatedAt;
    return Row(
      children: [
        Text(l10n.navGuide, style: theme.titleLarge),
        if (updated != null) ...[
          const SizedBox(width: Spacing.md),
          Flexible(
            child: Text(
              guideUpdatedText(l10n, updated),
              key: const ValueKey('guide-updated'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.bodySmall,
            ),
          ),
        ],
        const Spacer(),
        GuideHeaderButton(
          key: const ValueKey('guide-filter'),
          icon: Icons.filter_list,
          label: filterLabel,
          maxLabelWidth: 180,
          onSelect: onFilter,
        ),
        const SizedBox(width: Spacing.sm),
        GuideHeaderButton(
          key: const ValueKey('guide-refresh'),
          icon: Icons.refresh,
          label: running ? l10n.guideUpdating : l10n.guideRefresh,
          busy: running,
          onSelect: onRefresh,
        ),
      ],
    );
  }
}

class _PhoneHeader extends StatelessWidget {
  const _PhoneHeader({
    required this.updatedAt,
    required this.running,
    required this.onRefresh,
  });

  final DateTime? updatedAt;
  final bool running;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final updated = updatedAt;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: Spacing.lg,
        end: Spacing.sm,
        top: Spacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.navGuide, style: theme.titleLarge),
                if (updated != null)
                  Text(
                    guideUpdatedText(l10n, updated),
                    key: const ValueKey('guide-updated'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall,
                  ),
              ],
            ),
          ),
          if (running)
            Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  semanticsLabel: l10n.guideUpdating,
                ),
              ),
            )
          else
            IconButton(
              key: const ValueKey('guide-refresh'),
              tooltip: l10n.guideRefresh,
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.options,
    required this.current,
    required this.onSelect,
  });

  final List<GuideFilterOption> options;
  final GuideFilter current;
  final ValueChanged<GuideFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: Spacing.sm),
        itemBuilder: (context, i) {
          final o = options[i];
          return ChoiceChip(
            key: ValueKey('guide-chip-$i'),
            label: Text(o.label),
            selected: o.filter == current,
            onSelected: (_) => onSelect(o.filter),
          );
        },
      ),
    );
  }
}
