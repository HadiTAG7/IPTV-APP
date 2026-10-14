import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../theme/tokens.dart';
import '../tv/tv_focusable.dart';
import 'bidi_text.dart';
import 'logo_image.dart';
import 'states.dart';

/// One row of a channel list: number, logo, name, current programme with a
/// thin progress bar, and a favourite star. Fits [TvLayout.channelExtent]:
/// lists use a fixed item extent, so the system font size is honoured only up
/// to [maxTextScale].
///
/// Each text line takes its own direction ([BidiText]), so Latin names in an
/// Arabic list (and the reverse) render correctly.
class ChannelTile extends StatelessWidget {
  const ChannelTile({
    super.key,
    required this.name,
    this.number,
    this.logoUrl,
    this.nowTitle,
    this.progress,
    this.isFavorite = false,
    this.selected = false,
    this.showNowLine = true,
    this.onSelect,
    this.onLongSelect,
    this.onMenu,
    this.onFocusChange,
    this.autofocus = false,
    this.focusNode,
  });

  final String name;
  final int? number;
  final String? logoUrl;

  /// Current programme; null shows "No programme info".
  final String? nowTitle;

  /// Programme progress 0..1; null hides the bar.
  final double? progress;
  final bool isFavorite;

  /// Marks the channel that is currently playing.
  final bool selected;
  final bool showNowLine;
  final VoidCallback? onSelect;
  final VoidCallback? onLongSelect;
  final VoidCallback? onMenu;
  final ValueChanged<bool>? onFocusChange;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Largest text scale the fixed-height row can hold without overflowing.
  static const double maxTextScale = 1.1;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onSelect: onSelect,
      onLongSelect: onLongSelect,
      onMenu: onMenu,
      onFocusChange: onFocusChange,
      autofocus: autofocus,
      focusNode: focusNode,
      semanticLabel: number == null ? name : '$number $name',
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: maxTextScale,
        child: _ChannelTileBody(tile: this),
      ),
    );
  }
}

class _ChannelTileBody extends StatelessWidget {
  const _ChannelTileBody({required this.tile});

  final ChannelTile tile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final highlighted = TvHighlight.of(context);
    final number = tile.number;
    final progress = tile.progress;
    final nameColor = tile.selected ? AppColors.accent : AppColors.textPrimary;
    final background = highlighted
        ? AppColors.surfaceHighest
        : tile.selected
        ? AppColors.surfaceHigh
        : Colors.transparent;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      decoration: BoxDecoration(color: background, borderRadius: Radii.mdAll),
      child: Row(
        children: [
          if (number != null)
            SizedBox(
              width: 44,
              child: Text(
                '$number',
                textAlign: TextAlign.end,
                textDirection: TextDirection.ltr,
                maxLines: 1,
                style: theme.labelLarge?.copyWith(
                  color: AppColors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          const SizedBox(width: Spacing.sm),
          LogoImage(url: tile.logoUrl, name: tile.name, size: 36),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BidiText(
                  tile.name,
                  style: theme.titleMedium?.copyWith(color: nameColor),
                ),
                if (tile.showNowLine)
                  BidiText(
                    tile.nowTitle ??
                        AppLocalizations.of(context).liveNoProgrammeInfo,
                    style: theme.bodySmall,
                  ),
                if (progress != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: Spacing.xs),
                    child: ProgressLine(value: progress),
                  ),
              ],
            ),
          ),
          if (tile.isFavorite)
            const Padding(
              padding: EdgeInsetsDirectional.only(start: Spacing.sm),
              child: Icon(
                Icons.star_rounded,
                size: 18,
                color: AppColors.favorite,
              ),
            ),
        ],
      ),
    );
  }
}
