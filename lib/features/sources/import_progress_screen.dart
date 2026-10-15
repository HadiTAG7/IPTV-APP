import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/form_factor.dart';
import '../../app/home_shell.dart' show describeSourceError;
import '../../app/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../sources/sync/sync_progress.dart';
import '../../theme/tokens.dart';
import '../../tv/focus_watchdog.dart';
import '../../widgets/bidi_text.dart';
import 'widgets/tv_buttons.dart';

/// How an import ended for the screen that pushed [ImportProgressScreen].
enum ImportOutcome {
  /// The catalog was imported.
  done,

  /// The user cancelled (Cancel or Back).
  cancelled,

  /// It failed and the user chose to edit the source.
  edit,
}

/// Pushes [ImportProgressScreen] for [sourceId] and returns how it ended
/// (null if the route was removed some other way).
Future<ImportOutcome?> showImportProgress(BuildContext context, int sourceId) =>
    Navigator.of(context).push<ImportOutcome>(
      MaterialPageRoute<ImportOutcome>(
        settings: const RouteSettings(name: '/import'),
        builder: (_) => ImportProgressScreen(sourceId: sourceId),
      ),
    );

/// Full-screen progress of a catalog import: live channels, movies and
/// series counted as they arrive. Cancel (or Back) stops the sync; a failure
/// shows the localized reason with Retry and Edit.
class ImportProgressScreen extends ConsumerStatefulWidget {
  const ImportProgressScreen({super.key, required this.sourceId});

  final int sourceId;

  @override
  ConsumerState<ImportProgressScreen> createState() =>
      _ImportProgressScreenState();
}

class _ImportProgressScreenState extends ConsumerState<ImportProgressScreen> {
  final _cancelNode = FocusNode(debugLabel: 'import-cancel');
  final _retryNode = FocusNode(debugLabel: 'import-retry');
  StreamSubscription<SyncProgress>? _sub;
  late SyncProgress _progress = SyncProgress(sourceId: widget.sourceId);
  FocusWatchdogState? _watchdog;
  var _cancelling = false;
  var _finished = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final watchdog = FocusWatchdog.maybeOf(context);
    if (watchdog != _watchdog) {
      _watchdog?.unregister(_cancelNode);
      _watchdog = watchdog?..register(_cancelNode);
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _watchdog?.unregister(_cancelNode);
    _watchdog?.unregister(_retryNode);
    _cancelNode.dispose();
    _retryNode.dispose();
    super.dispose();
  }

  void _start() {
    unawaited(_sub?.cancel());
    _cancelling = false;
    _sub = ref
        .read(syncServiceProvider)
        // The user added or edited the source (or retried): its lists
        // replace the stored ones even when one comes back empty.
        .sync(widget.sourceId, replaceEmptyFamilies: true)
        .listen(_onProgress);
  }

  void _onProgress(SyncProgress p) {
    if (!mounted) return;
    setState(() => _progress = p);
    switch (p.phase) {
      case SyncPhase.done:
        _finish(ImportOutcome.done);
      case SyncPhase.cancelled:
        _finish(ImportOutcome.cancelled);
      case SyncPhase.failed:
        _focusAfterBuild(_retryNode);
      default:
        break;
    }
  }

  void _focusAfterBuild(FocusNode node) {
    _watchdog?.register(node);
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted && node.context != null) node.requestFocus();
      })
      ..ensureVisualUpdate();
  }

  void _finish(ImportOutcome outcome) {
    if (_finished) return;
    _finished = true;
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent) {
      Navigator.of(context).pop(outcome);
    } else if (route != null) {
      Navigator.of(context).removeRoute(route, outcome);
    }
  }

  void _cancel() {
    if (_progress.isTerminal) return;
    setState(() => _cancelling = true);
    ref.read(syncServiceProvider).cancel(widget.sourceId);
  }

  void _retry() {
    setState(() => _progress = SyncProgress(sourceId: widget.sourceId));
    _focusAfterBuild(_cancelNode);
    _start();
  }

  void _onBack() {
    if (_progress.isFailed) {
      _finish(ImportOutcome.edit);
    } else {
      _cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = _progress;
    final source = ref
        .watch(sourcesProvider)
        .value
        ?.where((s) => s.id == widget.sourceId)
        .firstOrNull;
    final failed = p.isFailed;
    final error = p.error;
    final status = switch (p.phase) {
      SyncPhase.verifying => l10n.validating,
      SyncPhase.saving => l10n.sourcesImportSaving,
      SyncPhase.done => l10n.importDone,
      SyncPhase.cancelled => l10n.sourcesImportCancelled,
      SyncPhase.failed => l10n.importFailed,
      SyncPhase.live ||
      SyncPhase.movies ||
      SyncPhase.series => l10n.importTitle,
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        body: SafeArea(
          minimum: overscanPadding(FormFactorScope.of(context)),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.importTitle,
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    if (source != null) ...[
                      const SizedBox(height: Spacing.xs),
                      BidiText(
                        source.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: Spacing.xl),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        status,
                        key: const ValueKey('import-status'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: failed ? AppColors.error : null,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    if (!p.isTerminal)
                      const LinearProgressIndicator(minHeight: 4)
                    else
                      const SizedBox(height: 4),
                    const SizedBox(height: Spacing.lg),
                    _CountRow(
                      key: const ValueKey('import-live'),
                      text: l10n.importLiveCount(p.channels),
                      state: _stateOf(p, SyncPhase.live),
                    ),
                    _CountRow(
                      key: const ValueKey('import-movies'),
                      text: l10n.importMoviesCount(p.movies),
                      state: _stateOf(p, SyncPhase.movies),
                    ),
                    _CountRow(
                      key: const ValueKey('import-series'),
                      text: l10n.importSeriesCount(p.series),
                      state: _stateOf(p, SyncPhase.series),
                    ),
                    if (failed && error != null) ...[
                      const SizedBox(height: Spacing.lg),
                      Text(
                        describeSourceError(l10n, error),
                        key: const ValueKey('import-error'),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: AppColors.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: Spacing.xl),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: Spacing.md,
                      runSpacing: Spacing.md,
                      children: [
                        if (failed) ...[
                          TvButton(
                            key: const ValueKey('import-retry'),
                            focusNode: _retryNode,
                            primary: true,
                            icon: Icons.refresh,
                            label: l10n.commonRetry,
                            onSelect: _retry,
                          ),
                          TvButton(
                            key: const ValueKey('import-edit'),
                            icon: Icons.edit_outlined,
                            label: l10n.commonEdit,
                            onSelect: () => _finish(ImportOutcome.edit),
                          ),
                        ] else
                          TvButton(
                            key: const ValueKey('import-cancel'),
                            focusNode: _cancelNode,
                            autofocus: true,
                            busy: _cancelling,
                            icon: Icons.close,
                            label: l10n.importCancel,
                            onSelect: _cancel,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _RowState { pending, active, done }

const _order = [
  SyncPhase.verifying,
  SyncPhase.live,
  SyncPhase.movies,
  SyncPhase.series,
  SyncPhase.saving,
  SyncPhase.done,
];

_RowState _stateOf(SyncProgress p, SyncPhase row) {
  if (p.phase == SyncPhase.done) return _RowState.done;
  if (p.isTerminal) {
    final count = switch (row) {
      SyncPhase.live => p.channels,
      SyncPhase.movies => p.movies,
      _ => p.series,
    };
    return count > 0 ? _RowState.done : _RowState.pending;
  }
  final at = _order.indexOf(p.phase);
  final mine = _order.indexOf(row);
  if (at == mine) return _RowState.active;
  return at > mine ? _RowState.done : _RowState.pending;
}

class _CountRow extends StatelessWidget {
  const _CountRow({super.key, required this.text, required this.state});

  final String text;
  final _RowState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 20,
            child: switch (state) {
              _RowState.active => const CircularProgressIndicator(
                strokeWidth: 2,
              ),
              _RowState.done => const Icon(
                Icons.check_circle,
                size: 20,
                color: AppColors.success,
              ),
              _RowState.pending => const Icon(
                Icons.radio_button_unchecked,
                size: 20,
                color: AppColors.textDisabled,
              ),
            },
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: state == _RowState.pending
                  ? AppColors.textDisabled
                  : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
