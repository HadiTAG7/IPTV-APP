import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/db/app_db.dart';
import '../../epg/epg_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';
import '../../tv/tv_focusable.dart';
import '../../widgets/bidi_text.dart';
import '../../widgets/logo_image.dart';
import '../../widgets/states.dart';
import '../session/playback_controller.dart';
import '../session/reconnect_watchdog.dart';
import 'player_format.dart';

const _panelColor = Color(0xE6151A22);

/// A large icon + label button of the OSD and player cards.
class OsdButton extends StatelessWidget {
  const OsdButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onSelect,
    this.focusNode,
    this.active = false,
    this.onFocus,
    this.width = 88,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final FocusNode? focusNode;

  /// Highlights the icon (favourite on, stats shown...).
  final bool active;

  /// Called when the button gains focus (keeps the OSD from hiding).
  final VoidCallback? onFocus;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
      child: TvFocusable(
        focusNode: focusNode,
        semanticLabel: label,
        onSelect: onSelect,
        onFocusChange: (focused) {
          if (focused) onFocus?.call();
        },
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(
            vertical: Spacing.sm,
            horizontal: Spacing.xs,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: Radii.mdAll,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 24,
                color: active ? AppColors.accent : AppColors.textPrimary,
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A focusable text button for player cards (failure, resume, next
/// episode).
class PlayerCardButton extends StatelessWidget {
  const PlayerCardButton({
    super.key,
    required this.label,
    required this.onSelect,
    this.icon,
    this.focusNode,
    this.primary = false,
  });

  final String label;
  final VoidCallback onSelect;
  final IconData? icon;
  final FocusNode? focusNode;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = primary ? AppColors.onAccent : AppColors.textPrimary;
    return TvFocusable(
      focusNode: focusNode,
      semanticLabel: label,
      onSelect: onSelect,
      focusScale: 1.04,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: primary ? AppColors.accent : AppColors.surfaceHighest,
          borderRadius: Radii.mdAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: Spacing.sm),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Number, logo, name and now/next of a live channel (banner and OSD).
class ChannelInfoRow extends StatelessWidget {
  const ChannelInfoRow({
    super.key,
    required this.name,
    required this.now,
    this.number,
    this.logo,
    this.nowNext,
    this.favorite = false,
  });

  final String name;
  final int? number;
  final String? logo;
  final NowNext? nowNext;
  final DateTime now;
  final bool favorite;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final current = nowNext?.now;
    final next = nowNext?.next;
    final number = this.number;
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (number != null) ...[
          Container(
            key: const ValueKey('player-channel-number'),
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm,
              vertical: Spacing.xs,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surfaceHighest,
              borderRadius: Radii.smAll,
            ),
            child: Text(
              '$number',
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(width: Spacing.md),
        ],
        LogoImage(url: logo, name: name, size: 48),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: BidiText(name, style: theme.textTheme.titleLarge),
                  ),
                  if (favorite) ...[
                    const SizedBox(width: Spacing.xs),
                    const Icon(Icons.star, size: 18, color: AppColors.favorite),
                  ],
                ],
              ),
              const SizedBox(height: Spacing.xxs),
              if (current == null)
                Text(l10n.liveNoProgrammeInfo, style: secondary)
              else ...[
                Text(
                  '${formatClock(current.start)}  '
                  '${l10n.liveNowTitle(current.title)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.xxs),
                SizedBox(
                  width: 220,
                  child: ProgressLine(value: _fraction(current, now)),
                ),
              ],
              if (next != null) ...[
                const SizedBox(height: Spacing.xxs),
                Text(
                  '${formatClock(next.start)}  ${l10n.liveNextTitle(next.title)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: secondary,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: Spacing.md),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatClock(now),
              key: const ValueKey('player-clock'),
              textDirection: TextDirection.ltr,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Spacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.sm,
                vertical: Spacing.xxs,
              ),
              decoration: const BoxDecoration(
                color: AppColors.error,
                borderRadius: Radii.smAll,
              ),
              child: Text(
                l10n.playerLive,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static double _fraction(EpgProgramme p, DateTime now) {
    final total = p.stop.difference(p.start).inSeconds;
    if (total <= 0) return 0;
    return now.difference(p.start).inSeconds / total;
  }
}

/// A rounded dark panel used for banners and cards.
class PlayerPanel extends StatelessWidget {
  const PlayerPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Spacing.lg),
    this.maxWidth = 640,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Material(
        color: _panelColor,
        borderRadius: Radii.lgAll,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// The big number typed on the remote, with the channel it points at.
class PlayerNumberBadge extends StatelessWidget {
  const PlayerNumberBadge({
    super.key,
    required this.digits,
    this.channelName,
    this.searching = false,
  });

  final String digits;

  /// The matching channel, or null when the number is not in the list.
  final String? channelName;

  /// The number is still being looked up (neither a name nor "no channel").
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = channelName;
    final number = int.tryParse(digits);
    return PlayerPanel(
      key: const ValueKey('player-number-badge'),
      maxWidth: 260,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.xl,
        vertical: Spacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            digits,
            textDirection: TextDirection.ltr,
            style: theme.textTheme.displaySmall?.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (name != null)
            BidiText(name, style: theme.textTheme.bodyMedium)
          else if (!searching && number != null && number > 0)
            Text(
              l10n.player_noChannelNumber(number),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

/// «Reconnecting… (n/8)» over the last frame while the watchdog retries.
class PlayerReconnectBanner extends StatelessWidget {
  const PlayerReconnectBanner({super.key, required this.status});

  final ValueListenable<ReconnectStatus> status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ValueListenableBuilder<ReconnectStatus>(
      valueListenable: status,
      builder: (context, s, _) {
        if (s is! ReconnectWaiting) return const SizedBox.shrink();
        return Container(
          key: const ValueKey('player-reconnect'),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.sm,
          ),
          decoration: const BoxDecoration(
            color: _panelColor,
            borderRadius: BorderRadius.all(Radius.circular(Radii.pill)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                l10n.playerReconnecting(s.attempt, s.maxAttempts),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Error card when every engine failed or reconnecting gave up.
class PlayerFailureCard extends StatelessWidget {
  const PlayerFailureCard({
    super.key,
    required this.message,
    required this.retryNode,
    required this.onRetry,
    required this.onCopyReport,
    this.details,
    this.onTryOtherFormat,
  });

  final String message;
  final String? details;
  final FocusNode retryNode;
  final VoidCallback onRetry;
  final VoidCallback? onTryOtherFormat;
  final VoidCallback onCopyReport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final details = this.details;
    final other = onTryOtherFormat;
    return PlayerPanel(
      key: const ValueKey('player-failure'),
      padding: const EdgeInsets.all(Spacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: AppColors.error),
          const SizedBox(height: Spacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          if (details != null && details.isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              details,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: Spacing.lg),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              PlayerCardButton(
                key: const ValueKey('player-retry'),
                focusNode: retryNode,
                primary: true,
                icon: Icons.refresh,
                label: l10n.playerRetry,
                onSelect: onRetry,
              ),
              if (other != null)
                PlayerCardButton(
                  key: const ValueKey('player-other-format'),
                  icon: Icons.swap_horiz,
                  label: l10n.playerTryOtherFormat,
                  onSelect: other,
                ),
              PlayerCardButton(
                key: const ValueKey('player-copy-report'),
                icon: Icons.copy_all_outlined,
                label: l10n.playerCopyReport,
                onSelect: onCopyReport,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// «Resume from 42:10» / «Start over» before a title starts.
class PlayerResumePrompt extends StatelessWidget {
  const PlayerResumePrompt({
    super.key,
    required this.title,
    required this.position,
    required this.resumeNode,
    required this.onResume,
    required this.onStartOver,
  });

  final String? title;
  final Duration position;
  final FocusNode resumeNode;
  final VoidCallback onResume;
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final title = this.title;
    return PlayerPanel(
      key: const ValueKey('player-resume'),
      padding: const EdgeInsets.all(Spacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            BidiText(
              title,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: Spacing.lg),
          ],
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              PlayerCardButton(
                key: const ValueKey('player-resume-from'),
                focusNode: resumeNode,
                primary: true,
                icon: Icons.play_arrow,
                label: l10n.vodResumeFrom(formatPosition(position)),
                onSelect: onResume,
              ),
              PlayerCardButton(
                key: const ValueKey('player-start-over'),
                icon: Icons.replay,
                label: l10n.vodStartOver,
                onSelect: onStartOver,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The cancellable "Next episode in n seconds" card.
class PlayerNextEpisodeCard extends StatelessWidget {
  const PlayerNextEpisodeCard({
    super.key,
    required this.seconds,
    required this.episode,
    required this.playNode,
    required this.onPlay,
    required this.onCancel,
  });

  final int seconds;
  final EpisodeRow episode;
  final FocusNode playNode;
  final VoidCallback onPlay;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final title = episode.title;
    return PlayerPanel(
      key: const ValueKey('player-next-episode'),
      maxWidth: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.vodNextEpisodeIn(seconds),
            key: const ValueKey('player-next-countdown'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            l10n.player_episodeLabel(episode.season, episode.number),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (title != null) BidiText(title, style: theme.textTheme.bodyMedium),
          const SizedBox(height: Spacing.md),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayerCardButton(
                key: const ValueKey('player-next-play'),
                focusNode: playNode,
                primary: true,
                icon: Icons.skip_next,
                label: l10n.player_playNow,
                onSelect: onPlay,
              ),
              const SizedBox(width: Spacing.sm),
              PlayerCardButton(
                key: const ValueKey('player-next-cancel'),
                label: l10n.commonCancel,
                onSelect: onCancel,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Engine, codec, resolution, buffer and time to first frame, refreshed
/// every second while shown.
class PlayerStatsOverlay extends StatefulWidget {
  const PlayerStatsOverlay({
    super.key,
    required this.controller,
    required this.redactValue,
  });

  final PlaybackController controller;

  /// Masks credentials in values (URLs in error texts).
  final String Function(String value) redactValue;

  @override
  State<PlayerStatsOverlay> createState() => _PlayerStatsOverlayState();
}

class _PlayerStatsOverlayState extends State<PlayerStatsOverlay> {
  Map<String, String> _stats = const {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final stats = await widget.controller.stats();
      if (mounted) setState(() => _stats = stats);
    } on Object catch (_) {
      // The engine may be switching; try again on the next tick.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final labels = <String, String>{
      'engine': l10n.statsEngine,
      'resolution': l10n.statsResolution,
      'video': l10n.statsCodec,
      'audio': l10n.player_statsAudioCodec,
      'cache': l10n.player_statsBuffer,
      'ttff': l10n.statsFirstFrame,
      'hwdec': l10n.settingsHardwareDecoding,
      'view': l10n.player_statsVideoOutput,
      'format': l10n.player_statsFormat,
      'dropped': l10n.statsDroppedFrames,
      'reconnects': l10n.player_statsReconnects,
    };
    final buffering = widget.controller.state.value.buffering;
    final rows = <(String, String)>[
      for (final MapEntry(:key, :value) in labels.entries)
        if (_stats[key] != null)
          (
            value,
            key == 'cache' && buffering
                ? '${_stats[key]} · ${l10n.playerBuffering}'
                : _stats[key]!,
          ),
      if (_stats['cache'] == null && buffering)
        (l10n.player_statsBuffer, l10n.playerBuffering),
      for (final MapEntry(:key, :value) in _stats.entries)
        if (!labels.containsKey(key)) (key, value),
    ];
    return PlayerPanel(
      key: const ValueKey('player-stats'),
      maxWidth: 320,
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.playerStats, style: theme.textTheme.titleSmall),
          const SizedBox(height: Spacing.xs),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.redactValue(value),
                      textDirection: TextDirection.ltr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The VOD seek bar. Always left-to-right (media timelines are never
/// mirrored). Focusable; the player screen handles Left/Right while it has
/// focus. Taps and drags seek on touch screens.
class PlayerSeekBar extends StatelessWidget {
  const PlayerSeekBar({
    super.key,
    required this.focusNode,
    required this.position,
    required this.duration,
    required this.onSeekTo,
    this.target,
    this.onFocus,
  });

  final FocusNode focusNode;
  final Duration position;
  final Duration duration;

  /// Pending seek target (shown instead of [position]).
  final Duration? target;
  final ValueChanged<Duration> onSeekTo;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = target ?? position;
    final total = duration.inMilliseconds;
    final fraction = total <= 0
        ? 0.0
        : (shown.inMilliseconds / total).clamp(0.0, 1.0);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Focus(
        focusNode: focusNode,
        onFocusChange: (focused) {
          if (focused) onFocus?.call();
        },
        child: ListenableBuilder(
          listenable: focusNode,
          builder: (context, _) {
            final focused = focusNode.hasFocus;
            return Row(
              children: [
                Text(
                  formatPosition(shown),
                  key: const ValueKey('player-position'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: target != null ? AppColors.accent : null,
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      void seekAt(double dx) {
                        if (total <= 0 || c.maxWidth <= 0) return;
                        final f = (dx / c.maxWidth).clamp(0.0, 1.0);
                        onSeekTo(Duration(milliseconds: (total * f).round()));
                      }

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) => seekAt(d.localPosition.dx),
                        onHorizontalDragUpdate: (d) =>
                            seekAt(d.localPosition.dx),
                        child: SizedBox(
                          height: 28,
                          child: CustomPaint(
                            painter: _SeekBarPainter(
                              fraction: fraction,
                              focused: focused,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Text(
                  formatPosition(duration),
                  key: const ValueKey('player-duration'),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SeekBarPainter extends CustomPainter {
  _SeekBarPainter({required this.fraction, required this.focused});

  final double fraction;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final h = focused ? 6.0 : 4.0;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, y - h / 2, size.width, h),
      Radius.circular(h / 2),
    );
    canvas.drawRRect(track, Paint()..color = AppColors.progressTrack);
    final x = size.width * fraction;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y - h / 2, x, h),
        Radius.circular(h / 2),
      ),
      Paint()..color = AppColors.accent,
    );
    canvas.drawCircle(
      Offset(x, y),
      focused ? 9 : 6,
      Paint()..color = focused ? AppColors.textPrimary : AppColors.accent,
    );
  }

  @override
  bool shouldRepaint(_SeekBarPainter old) =>
      old.fraction != fraction || old.focused != focused;
}
