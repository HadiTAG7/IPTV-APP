import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/form_factor.dart';
import '../../app/home_shell.dart' show describeSourceError;
import '../../app/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../sources/models.dart';
import '../../sources/source_repository.dart';
import '../../sources/sync/sync_progress.dart';
import '../../theme/tokens.dart';
import '../../widgets/bidi_text.dart';
import '../../widgets/states.dart';
import 'providers.dart';
import 'source_editor_screen.dart';
import 'widgets/row_traversal.dart';
import 'widgets/tv_buttons.dart';

/// Days before expiry from which a source shows a warning.
const kExpiryWarningDays = 7;

/// Source management: every saved source with its type, last import,
/// account state (expiry warning within [kExpiryWarningDays] days) and item
/// counts, and the actions Set active, Refresh (with inline progress,
/// cancellable), Edit, Delete (confirmed) and Add source.
///
/// Body content only: opened from Settings and the phone's More page as a
/// pushed page that provides the app bar.
class SourcesScreen extends ConsumerStatefulWidget {
  const SourcesScreen({super.key});

  @override
  ConsumerState<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends ConsumerState<SourcesScreen> {
  var _deleting = false;

  /// Each card's Refresh button, where focus goes after the card's Set
  /// active button disappears or a card is deleted.
  final _refreshNodes = <int, FocusNode>{};

  FocusNode _refreshNodeFor(int id) => _refreshNodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'source-$id-refresh'),
  );

  @override
  void dispose() {
    for (final node in _refreshNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Moves focus to [id]'s Refresh button after the next frame, when focus
  /// is in this screen (remote use).
  void _focusRefreshAfterBuild(int id) {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        final node = _refreshNodes[id];
        if (mounted && node != null && node.context != null) {
          node.requestFocus();
        }
      })
      ..ensureVisualUpdate();
  }

  /// Autofocus only as a pushed page: inside the TV rail shell, building a
  /// tab must not pull focus off the rail.
  bool get _pushed => ModalRoute.of(context)?.isFirst == false;

  Future<void> _add() => openSourceEditor(context);

  Future<void> _edit(SourceView s) => openSourceEditor(context, sourceId: s.id);

  Future<void> _setActive(SourceView s) async {
    // The Set active button is about to disappear: keep the remote's focus
    // on this card.
    _focusRefreshAfterBuild(s.id);
    await ref.read(activeSourceIdProvider.notifier).select(s.id);
  }

  void _refresh(SourceView s) {
    final sync = ref.read(syncServiceProvider);
    if (sync.isRunning(s.id)) {
      sync.cancel(s.id);
    } else {
      // Asked for: a list that comes back empty replaces the stored one.
      sync.sync(s.id, replaceEmptyFamilies: true);
    }
  }

  Future<void> _delete(SourceView s) async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => DeleteSourceDialog(name: s.name),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    // Read before the awaits: `ref` is unusable once the page closed.
    final repo = ref.read(sourceRepositoryProvider);
    final log = ref.read(ringLogProvider);
    try {
      await repo.delete(s.id);
      final left = await repo.list();
      if (!mounted) return;
      if (left.isEmpty) {
        // Back to the root, which now shows onboarding.
        if (_pushed) Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
      final active = ref.read(activeSourceIdProvider);
      _focusRefreshAfterBuild(
        left.any((r) => r.id == active) ? active! : left.first.id,
      );
    } on Object catch (e) {
      log.warn('Deleting source ${s.id} failed: $e');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).commonErrorGeneric),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sources = ref.watch(sourcesProvider);
    final activeId = ref.watch(activeSourceIdProvider);
    final pushed = _pushed;
    final tv = FormFactorScope.isTv(context);
    final padding = tv && pushed
        ? const EdgeInsetsDirectional.fromSTEB(
            TvLayout.overscanHorizontal,
            Spacing.md,
            TvLayout.overscanHorizontal,
            TvLayout.overscanVertical,
          )
        : const EdgeInsetsDirectional.all(Spacing.lg);

    final list = sources.value;
    if (list == null) {
      return sources.hasError
          ? ErrorView(onRetry: () => ref.invalidate(sourcesProvider))
          : const LoadingView();
    }
    final addButton = TvButton(
      key: const ValueKey('sources-add'),
      autofocus: pushed && list.isEmpty,
      icon: Icons.add,
      label: l10n.settingsAddSource,
      onSelect: () => unawaited(_add()),
    );
    if (list.isEmpty) {
      return EmptyView(
        message: l10n.settingsNoSources,
        icon: Icons.playlist_add,
        action: addButton,
      );
    }
    final focusId = list.any((s) => s.id == activeId)
        ? activeId
        : list.first.id;
    // A handful of sources: one scrolling column, so every card is built
    // and reachable with the remote.
    return FocusTraversalGroup(
      policy: RowTraversalPolicy(),
      child: SingleChildScrollView(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: addButton,
            ),
            const SizedBox(height: Spacing.md),
            for (final s in list)
              Padding(
                key: ValueKey('source-${s.id}'),
                padding: const EdgeInsets.only(bottom: Spacing.md),
                child: _SourceCard(
                  source: s,
                  active: s.id == activeId,
                  refreshNode: _refreshNodeFor(s.id),
                  autofocus: pushed && s.id == focusId,
                  onSetActive: () => unawaited(_setActive(s)),
                  onRefresh: () => _refresh(s),
                  onEdit: () => unawaited(_edit(s)),
                  onDelete: () => unawaited(_delete(s)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SourceCard extends ConsumerWidget {
  const _SourceCard({
    required this.source,
    required this.active,
    required this.refreshNode,
    required this.autofocus,
    required this.onSetActive,
    required this.onRefresh,
    required this.onEdit,
    required this.onDelete,
  });

  final SourceView source;
  final bool active;
  final FocusNode refreshNode;
  final bool autofocus;
  final VoidCallback onSetActive;
  final VoidCallback onRefresh;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = source;
    final status = ref.watch(syncStatusProvider(s.id));
    final counts = ref.watch(sourceCountsProvider(countsKeyOf(s))).value;
    final now = ref.watch(clockProvider).now();
    final running = status is SyncRunning;
    final account = _accountLine(l10n, s, now);
    final id = s.id;

    final details = <Widget>[
      Text(
        _kindLabel(l10n, s.kind),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      if (counts != null && s.hasCatalog)
        Text(
          [
            l10n.importLiveCount(counts.live),
            if (counts.movies > 0) l10n.importMoviesCount(counts.movies),
            if (counts.series > 0) l10n.importSeriesCount(counts.series),
          ].join(' · '),
          key: ValueKey('source-$id-counts'),
          style: theme.textTheme.bodyMedium,
        ),
      Text(
        _syncedLine(context, l10n, s),
        key: ValueKey('source-$id-synced'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      if (account != null)
        Row(
          key: ValueKey('source-$id-account'),
          children: [
            if (account.icon case final icon?) ...[
              Icon(icon, size: 16, color: account.color),
              const SizedBox(width: Spacing.xs),
            ],
            Expanded(
              child: Text(
                account.text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: account.color,
                ),
              ),
            ),
          ],
        ),
    ];

    final progress = switch (status) {
      SyncRunning(:final progress) => progress,
      _ => null,
    };
    final failure = switch (status) {
      SyncFailed(cancelled: false, :final error?) => describeSourceError(
        l10n,
        error,
      ),
      _ => null,
    };

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: Radii.mdAll,
        border: Border.all(
          color: active ? AppColors.accent : AppColors.surfaceHighest,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_kindIcon(s.kind), color: AppColors.accent),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: BidiText(s.name, style: theme.textTheme.titleMedium),
              ),
              if (active)
                Container(
                  key: ValueKey('source-$id-active'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: Spacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(
                    l10n.settingsActive,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.accent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          ...details,
          if (progress != null) ...[
            const SizedBox(height: Spacing.sm),
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: Spacing.xs),
            Text(
              [
                switch (progress.phase) {
                  SyncPhase.verifying => l10n.validating,
                  SyncPhase.saving => l10n.sourcesImportSaving,
                  _ => l10n.importTitle,
                },
                l10n.importLiveCount(progress.channels),
                if (progress.movies > 0)
                  l10n.importMoviesCount(progress.movies),
                if (progress.series > 0)
                  l10n.importSeriesCount(progress.series),
              ].join(' · '),
              key: ValueKey('source-$id-progress'),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (failure != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              '${l10n.importFailed}: $failure',
              key: ValueKey('source-$id-error'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.error,
              ),
            ),
          ],
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              if (!active)
                TvButton(
                  key: ValueKey('source-$id-activate'),
                  autofocus: autofocus,
                  height: 36,
                  icon: Icons.radio_button_checked,
                  label: l10n.settingsSetActive,
                  onSelect: onSetActive,
                ),
              TvButton(
                key: ValueKey('source-$id-refresh'),
                focusNode: refreshNode,
                autofocus: autofocus && active,
                height: 36,
                icon: running ? Icons.close : Icons.refresh,
                label: running ? l10n.importCancel : l10n.settingsRefresh,
                onSelect: onRefresh,
              ),
              TvButton(
                key: ValueKey('source-$id-edit'),
                height: 36,
                icon: Icons.edit_outlined,
                label: l10n.commonEdit,
                onSelect: onEdit,
              ),
              TvButton(
                key: ValueKey('source-$id-delete'),
                height: 36,
                icon: Icons.delete_outline,
                label: l10n.commonDelete,
                onSelect: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks before deleting a source; pops true to delete. Cancel has the
/// focus, so a stray OK never deletes.
class DeleteSourceDialog extends StatelessWidget {
  const DeleteSourceDialog({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.settingsDeleteSource),
      content: Text(l10n.settingsDeleteSourceConfirm(name)),
      actions: [
        TextButton(
          key: const ValueKey('delete-cancel'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const ValueKey('delete-confirm'),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.commonDelete),
        ),
      ],
    );
  }
}

String _kindLabel(AppLocalizations l10n, SourceKind kind) => switch (kind) {
  SourceKind.m3uUrl => l10n.sourceTypeM3uUrl,
  SourceKind.m3uFile => l10n.sourceTypeM3uFile,
  SourceKind.xtream => l10n.sourceTypeXtream,
};

IconData _kindIcon(SourceKind kind) => switch (kind) {
  SourceKind.m3uUrl => Icons.link,
  SourceKind.m3uFile => Icons.description_outlined,
  SourceKind.xtream => Icons.dns_outlined,
};

String _syncedLine(BuildContext context, AppLocalizations l10n, SourceView s) {
  final at = s.lastSyncAt;
  if (at == null) return l10n.sourcesNeverImported;
  final local = at.toLocal();
  final time = MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '${l10n.settingsLastUpdated(local)} $time';
}

/// The account line: blocked states, expiry (a warning under
/// [kExpiryWarningDays] days) or no expiry for Xtream; null otherwise.
({String text, Color color, IconData? icon})? _accountLine(
  AppLocalizations l10n,
  SourceView s,
  DateTime now,
) {
  final expires = s.expiresAt;
  switch (s.accountStatus) {
    case AccountStatus.banned:
      return (
        text: l10n.errorBanned,
        color: AppColors.error,
        icon: Icons.block,
      );
    case AccountStatus.disabled:
      return (
        text: l10n.errorDisabled,
        color: AppColors.error,
        icon: Icons.block,
      );
    case AccountStatus.expired:
      return (
        text: expires == null
            ? l10n.errorExpiredNoDate
            : l10n.errorExpired(expires.toLocal()),
        color: AppColors.error,
        icon: Icons.event_busy,
      );
    case AccountStatus.active || AccountStatus.unknown:
      break;
  }
  if (expires == null) {
    return s.kind == SourceKind.xtream &&
            s.accountStatus == AccountStatus.active
        ? (
            text: l10n.settingsAccountNoExpiry,
            color: AppColors.textSecondary,
            icon: null,
          )
        : null;
  }
  if (!expires.isAfter(now)) {
    return (
      text: l10n.errorExpired(expires.toLocal()),
      color: AppColors.error,
      icon: Icons.event_busy,
    );
  }
  final left = expires.difference(now);
  if (left.inDays < kExpiryWarningDays) {
    return (
      text:
          '${l10n.settingsExpiresSoon} · '
          '${l10n.settingsExpiresInDays(left.inDays)}',
      color: AppColors.warning,
      icon: Icons.warning_amber_rounded,
    );
  }
  return (
    text: l10n.settingsAccountExpires(expires.toLocal()),
    color: AppColors.textSecondary,
    icon: null,
  );
}
