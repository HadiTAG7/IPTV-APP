import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';
import '../../widgets/bidi_text.dart';
import '../engine/player_engine.dart';
import '../session/playback_controller.dart';
import '../ui/player_overlays.dart';
import 'multiview_tile.dart';

const _panelColor = Color(0xE6151A22);

/// A round icon button for the mouse (tiles, the split screen's bar). It
/// never takes keyboard focus: the split screen keeps the keyboard and has
/// keys for all of these.
class MultiViewButton extends StatelessWidget {
  const MultiViewButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 36,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Material(
      color: AppColors.surfaceHigh,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        canRequestFocus: false,
        onTap: onPressed,
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, size: size * 0.55, color: AppColors.textPrimary),
        ),
      ),
    ),
  );
}

/// One tile of the split screen on screen: the video, its number, the
/// channel's name, the opening and reconnect states, the failure with
/// Retry, the big "Add channel" button when empty, and on hover the
/// Change channel, Separate window (not when failed) and Remove buttons,
/// and Show all tiles on a maximized tile.
///
/// [active] draws the gold border of the tile that is heard and that the
/// keys act on; [heard] puts the speaker (or the muted one) by its name.
/// Clicks report [onTap] and [onDoubleTap]; pointer enter/exit report
/// [onHover]. Rebuilt by the screen when [tile] changes.
class MultiViewTileView extends StatelessWidget {
  const MultiViewTileView({
    super.key,
    required this.tile,
    required this.number,
    required this.active,
    required this.heard,
    required this.hovered,
    required this.aspect,
    required this.onTap,
    required this.onDoubleTap,
    required this.onHover,
    required this.onAdd,
    required this.onChange,
    required this.onRemove,
    required this.onRetry,
    this.onDetach,
    this.onShowAll,
  });

  final MultiViewTile tile;

  /// 1-based, as the messages name tiles.
  final int number;
  final bool active;

  /// Whether the sound is this tile's (the active one, also while it is
  /// shown alone without the border).
  final bool heard;
  final bool hovered;
  final AspectMode aspect;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<bool> onHover;
  final VoidCallback onAdd;
  final VoidCallback onChange;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  /// Null where there are no separate windows.
  final VoidCallback? onDetach;

  /// Shows every tile again; set while this one is maximized.
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = tile.controller;
    final status = tile.status;
    final channel = tile.channel;
    final failed = status == MultiViewTileStatus.failed;
    // A failed tile has no stream to hand over (Retry first).
    final detach = failed ? null : onDetach;
    final showAll = onShowAll;
    final buttons = detach == null ? 2 : 3;
    // The buttons sit above the click area, so their clicks never wait for
    // the tile's double click.
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              onDoubleTap: onDoubleTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  if (controller != null && !failed)
                    controller.buildView(aspect: aspect),
                  if (status == MultiViewTileStatus.opening)
                    _buffering(tile.waiting ? null : controller),
                  if (controller != null && !failed)
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.all(Spacing.sm),
                        child: PlayerReconnectBanner(
                          status: controller.reconnectStatus,
                        ),
                      ),
                    ),
                  PositionedDirectional(
                    start: Spacing.sm,
                    top: Spacing.sm,
                    child: _number(context, l10n),
                  ),
                  if (channel != null)
                    PositionedDirectional(
                      start: Spacing.sm,
                      end: hovered
                          ? buttons * 36 + (buttons + 1) * Spacing.sm
                          : Spacing.sm,
                      bottom: Spacing.sm,
                      child: Align(
                        alignment: AlignmentDirectional.bottomStart,
                        child: _name(context, channel),
                      ),
                    ),
                ],
              ),
            ),
            if (failed) Center(child: _failure(context, l10n)),
            if (channel == null) Center(child: _add(context, l10n)),
            if (hovered && channel != null)
              PositionedDirectional(
                end: Spacing.sm,
                bottom: Spacing.sm,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MultiViewButton(
                      key: const ValueKey('multiview-change'),
                      icon: Icons.swap_horiz,
                      label: l10n.multiviewChangeChannel,
                      onPressed: onChange,
                    ),
                    if (detach != null) ...[
                      const SizedBox(width: Spacing.sm),
                      MultiViewButton(
                        key: const ValueKey('multiview-detach'),
                        icon: Icons.open_in_new,
                        label: l10n.playerDetach,
                        onPressed: detach,
                      ),
                    ],
                    const SizedBox(width: Spacing.sm),
                    MultiViewButton(
                      key: const ValueKey('multiview-remove'),
                      icon: Icons.close,
                      label: l10n.multiviewRemoveChannel,
                      onPressed: onRemove,
                    ),
                  ],
                ),
              ),
            // The way back to the grid (also Back, Escape, Enter and a
            // double click).
            if (hovered && showAll != null)
              PositionedDirectional(
                end: Spacing.sm,
                top: Spacing.sm,
                child: MultiViewButton(
                  key: const ValueKey('multiview-show-all'),
                  icon: Icons.close_fullscreen,
                  label: l10n.multiviewShowAll,
                  onPressed: showAll,
                ),
              ),
            IgnorePointer(
              child: DecoratedBox(
                key: active ? const ValueKey('multiview-active') : null,
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: active ? AppColors.accent : AppColors.outline,
                    width: active ? 3 : 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The spinner while the tile waits for a connection, the source loads
  /// or the stream opens (and while the engine rebuffers).
  Widget _buffering(PlaybackController? controller) {
    const spinner = Center(
      key: ValueKey('multiview-buffering'),
      child: SizedBox.square(
        dimension: 36,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
    );
    if (controller == null) return spinner;
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: controller.state,
      builder: (context, st, _) {
        final phase = controller.phase;
        final buffering =
            phase == PlaybackPhase.opening ||
            (st.buffering && phase == PlaybackPhase.playing);
        return buffering ? spinner : const SizedBox.shrink();
      },
    );
  }

  Widget _number(BuildContext context, AppLocalizations l10n) => Semantics(
    label: l10n.multiviewTile(number),
    excludeSemantics: true,
    child: Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? AppColors.accent : _panelColor,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: active ? AppColors.onAccent : AppColors.textPrimary,
        ),
      ),
    ),
  );

  Widget _name(BuildContext context, MultiViewChannel channel) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      decoration: const BoxDecoration(
        color: _panelColor,
        borderRadius: Radii.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (heard) ...[
            Icon(
              tile.userMuted ? Icons.volume_off : Icons.volume_up,
              key: ValueKey(
                tile.userMuted ? 'multiview-muted' : 'multiview-audible',
              ),
              size: 16,
              color: AppColors.accent,
            ),
            const SizedBox(width: Spacing.xs),
          ],
          Flexible(
            child: BidiText(
              channel.name ?? channel.item.title ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _add(BuildContext context, AppLocalizations l10n) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: const ValueKey('multiview-add'),
      canRequestFocus: false,
      borderRadius: Radii.lgAll,
      onTap: onAdd,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                shape: BoxShape.circle,
                border: Border.all(
                  color: active ? AppColors.accent : AppColors.outline,
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.add,
                size: 44,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              l10n.multiviewAddChannel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _failure(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('multiview-failure'),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: const BoxDecoration(
        color: _panelColor,
        borderRadius: Radii.mdAll,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 28, color: AppColors.error),
          const SizedBox(height: Spacing.xs),
          Text(
            l10n.playerPlaybackFailed,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: Spacing.sm),
          Material(
            color: AppColors.accent,
            borderRadius: Radii.mdAll,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('multiview-retry'),
              canRequestFocus: false,
              onTap: onRetry,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.refresh,
                      size: 18,
                      color: AppColors.onAccent,
                    ),
                    const SizedBox(width: Spacing.xs),
                    Text(
                      l10n.playerRetry,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.onAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
