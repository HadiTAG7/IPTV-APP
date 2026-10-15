import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../epg/epg_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';
import '../../tv/tv_focusable.dart';
import '../../widgets/bidi_text.dart';
import '../../widgets/logo_image.dart';
import '../../widgets/states.dart';
import 'live_models.dart';
import 'now_next_store.dart';
import 'preferred_focus.dart';

/// Local wall-clock time of [t] in the app's format (12/24 h per device).
String formatClock(BuildContext context, DateTime t) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(t.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

/// "20:00 – 21:00" for [p].
String formatProgrammeTimes(BuildContext context, EpgProgramme p) =>
    AppLocalizations.of(context).liveTimeRange(
      formatClock(context, p.start),
      formatClock(context, p.stop),
    );

/// The info column of the large Live layout: the focused channel, its
/// current programme (times, progress, description) and the next one, plus
/// Play / Favourite / More options buttons for remotes without a Menu key.
class LiveInfoPane extends ConsumerStatefulWidget {
  const LiveInfoPane({
    super.key,
    required this.entry,
    required this.store,
    required this.isFavorite,
    this.onPlay,
    this.onToggleFavorite,
    this.onOptions,
  });

  /// The channel shown; null shows nothing.
  final LiveEntry? entry;
  final NowNextStore store;
  final bool isFavorite;
  final VoidCallback? onPlay;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onOptions;

  @override
  ConsumerState<LiveInfoPane> createState() => LiveInfoPaneState();
}

class LiveInfoPaneState extends ConsumerState<LiveInfoPane> {
  // Kept here so the pane remembers its button when the channel changes.
  final _playNode = FocusNode(debugLabel: 'live-info-play');
  final _favoriteNode = FocusNode(debugLabel: 'live-info-favorite');
  final _optionsNode = FocusNode(debugLabel: 'live-info-options');

  /// The Play button's node, when it is built.
  FocusNode? get playNode => isAttached(_playNode) ? _playNode : null;

  @override
  void dispose() {
    _playNode.dispose();
    _favoriteNode.dispose();
    _optionsNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.entry?.row;
    if (row == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final nowNext = widget.store[row.key];
        final now = ref.read(clockProvider).now();
        final current = nowNext?.now;
        final next = nowNext?.next;
        final number = row.num;
        return SingleChildScrollView(
          padding: const EdgeInsetsDirectional.only(
            start: Spacing.sm,
            end: Spacing.sm,
            bottom: Spacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                key: ValueKey('live-info-${row.key}'),
                children: [
                  LogoImage(url: row.logo, name: row.name, size: 48),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        BidiText(row.name, style: theme.titleLarge),
                        if (number != null)
                          Text(
                            l10n.liveChannelNumber(number),
                            style: theme.labelMedium,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              _Heading(l10n.liveNow),
              if (current == null)
                Text(l10n.liveNoProgrammeInfo, style: theme.bodySmall)
              else ...[
                BidiText(
                  current.title,
                  key: const ValueKey('live-info-now-title'),
                  style: theme.titleMedium,
                  maxLines: 2,
                ),
                const SizedBox(height: Spacing.xxs),
                Text(
                  formatProgrammeTimes(context, current),
                  style: theme.bodySmall,
                ),
                const SizedBox(height: Spacing.xs),
                ProgressLine(
                  value: programmeProgress(current, now) ?? 0,
                  height: 4,
                ),
                if (current.desc case final desc? when desc.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: Spacing.sm),
                    child: BidiText(
                      desc.trim(),
                      key: const ValueKey('live-info-now-desc'),
                      style: theme.bodyMedium,
                      maxLines: 5,
                    ),
                  ),
              ],
              if (next != null) ...[
                const SizedBox(height: Spacing.md),
                _Heading(l10n.liveNext),
                BidiText(
                  next.title,
                  key: const ValueKey('live-info-next-title'),
                  style: theme.titleSmall,
                ),
                Text(
                  formatProgrammeTimes(context, next),
                  style: theme.bodySmall,
                ),
              ],
              const SizedBox(height: Spacing.lg),
              _InfoButton(
                key: const ValueKey('live-info-play'),
                focusNode: _playNode,
                icon: Icons.play_arrow_rounded,
                label: l10n.vodPlay,
                onSelect: widget.onPlay,
              ),
              _InfoButton(
                key: const ValueKey('live-info-favorite'),
                focusNode: _favoriteNode,
                icon: widget.isFavorite
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                label: widget.isFavorite
                    ? l10n.liveRemoveFavorite
                    : l10n.liveAddFavorite,
                onSelect: widget.onToggleFavorite,
              ),
              _InfoButton(
                key: const ValueKey('live-info-options'),
                focusNode: _optionsNode,
                icon: Icons.more_horiz,
                label: l10n.liveMoreOptions,
                onSelect: widget.onOptions,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: Spacing.xs),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: AppColors.accent),
    ),
  );
}

class _InfoButton extends StatelessWidget {
  const _InfoButton({
    super.key,
    required this.icon,
    required this.label,
    this.focusNode,
    this.onSelect,
  });

  final IconData icon;
  final String label;
  final FocusNode? focusNode;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
      child: TvFocusable(
        focusNode: focusNode,
        focusScale: 1.03,
        semanticLabel: label,
        onSelect: onSelect,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          decoration: const BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: Radii.mdAll,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
