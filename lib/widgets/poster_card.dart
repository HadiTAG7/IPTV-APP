import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../tv/tv_focusable.dart';
import 'bidi_text.dart';
import 'logo_image.dart';
import 'states.dart';

/// Movie or series card: a 2:3 poster (focusable) with the title below and,
/// for continue-watching, a progress bar along the poster's bottom edge.
///
/// For grids use a fixed main-axis extent of [PosterCard.heightForWidth].
class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.title,
    this.posterUrl,
    this.progress,
    this.onSelect,
    this.onLongSelect,
    this.onMenu,
    this.onFocusChange,
    this.autofocus = false,
    this.focusNode,
  });

  /// Height reserved for the one-line title.
  static const double titleHeight = 22;

  /// Total card height for a given card width.
  static double heightForWidth(double width) =>
      width * 1.5 + Spacing.sm + titleHeight;

  final String title;
  final String? posterUrl;

  /// Watch progress 0..1; null hides the bar.
  final double? progress;
  final VoidCallback? onSelect;
  final VoidCallback? onLongSelect;
  final VoidCallback? onMenu;
  final ValueChanged<bool>? onFocusChange;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _focused = false;

  void _onFocusChange(bool focused) {
    if (focused != _focused) setState(() => _focused = focused);
    widget.onFocusChange?.call(focused);
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final style = Theme.of(context).textTheme.titleSmall
        ?.copyWith(color: _focused ? AppColors.accent : AppColors.textPrimary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 2 / 3,
          child: TvFocusable(
            onSelect: widget.onSelect,
            onLongSelect: widget.onLongSelect,
            onMenu: widget.onMenu,
            onFocusChange: _onFocusChange,
            autofocus: widget.autofocus,
            focusNode: widget.focusNode,
            semanticLabel: widget.title,
            child: ClipRRect(
              borderRadius: Radii.mdAll,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _PosterImage(url: widget.posterUrl, title: widget.title),
                  if (progress != null)
                    PositionedDirectional(
                      start: 0,
                      end: 0,
                      bottom: 0,
                      child: ProgressLine(
                        value: progress,
                        height: 4,
                        trackColor: AppColors.scrim,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        SizedBox(
          height: PosterCard.titleHeight,
          child: BidiText(widget.title, style: style),
        ),
      ],
    );
  }
}

class _PosterImage extends StatelessWidget {
  const _PosterImage({required this.url, required this.title});

  final String? url;
  final String title;

  @override
  Widget build(BuildContext context) {
    final placeholder = _PosterPlaceholder(title: title);
    final u = url?.trim();
    if (u == null ||
        u.isEmpty ||
        !(u.startsWith('http://') || u.startsWith('https://')) ||
        FailedImageCache.contains(u)) {
      return placeholder;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 160.0;
        return Image.network(
          u,
          fit: BoxFit.cover,
          cacheWidth: (w * dpr).round().clamp(1, 600),
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, sync) =>
              frame == null && !sync ? placeholder : child,
          errorBuilder: (context, error, stackTrace) {
            FailedImageCache.add(u);
            return placeholder;
          },
        );
      },
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceHigh,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.sm),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.movie_outlined,
              size: 28,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: Spacing.sm),
            Flexible(
              child: Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textDirection: textDirectionFor(title),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
