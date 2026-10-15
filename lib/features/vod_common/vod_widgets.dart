import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/form_factor.dart';
import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';
import '../../tv/tv_focusable.dart';
import '../../widgets/bidi_text.dart';
import '../../widgets/logo_image.dart';
import '../../widgets/poster_card.dart';
import '../../widgets/section_header.dart';
import 'vod_format.dart';

/// Focuses [node] when its widget is in the tree and returns true. Nodes
/// kept in a State outlive the tiles of lazy lists, and a node keeps its
/// last context after its tile was disposed, so that alone proves nothing.
bool focusIfMounted(FocusNode? node) {
  final context = node?.context;
  if (node == null ||
      context == null ||
      !context.mounted ||
      !node.canRequestFocus) {
    return false;
  }
  node.requestFocus();
  return true;
}

/// Poster grid geometry for a given width: 6 columns on the large layout
/// (more on wide desktop windows), 3 on phones (more in a wide window).
class VodGridLayout {
  const VodGridLayout._(this.columns, this.cellWidth);

  factory VodGridLayout.forWidth(double width, {required bool large}) {
    final usable = math.max(0.0, width - padding * 2);
    final columns = large
        ? math.max(TvLayout.posterColumnsTv, (usable / 132).floor())
        : math.max(TvLayout.posterColumnsPhone, (usable / 130).floor());
    final cell = (usable - spacing * (columns - 1)) / columns;
    return VodGridLayout._(columns, math.max(1.0, cell));
  }

  static const double spacing = Spacing.md;

  /// Room around the grid so a focused (scaled) card is not clipped.
  static const double padding = Spacing.sm;

  final int columns;
  final double cellWidth;

  /// Fixed card height: a 2:3 poster plus the title line.
  double get extent => PosterCard.heightForWidth(cellWidth);

  SliverGridDelegate get delegate => SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    mainAxisExtent: extent,
    crossAxisSpacing: spacing,
    mainAxisSpacing: spacing,
  );
}

/// Network artwork (poster, cover, still, backdrop) decoded at the size it
/// is shown, with an icon placeholder while loading and after a failure.
class VodImage extends StatelessWidget {
  const VodImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.icon = Icons.movie_outlined,
    this.maxCacheWidth = 600,
  });

  final String? url;
  final BoxFit fit;
  final IconData icon;

  /// Upper bound of the decoded width in physical pixels.
  final int maxCacheWidth;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: AppColors.surfaceHigh,
      child: Center(child: Icon(icon, color: AppColors.textDisabled)),
    );
    final u = url?.trim();
    if (u == null ||
        !(u.startsWith('http://') || u.startsWith('https://')) ||
        FailedImageCache.contains(u)) {
      return placeholder;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 200.0;
        return Image.network(
          u,
          fit: fit,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: (w * dpr).round().clamp(1, maxCacheWidth),
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, sync) =>
              frame == null && !sync ? placeholder : child,
          errorBuilder: (context, error, stackTrace) {
            FailedImageCache.add(u, error: error);
            return placeholder;
          },
        );
      },
    );
  }
}

/// A remote-friendly pill button (Play, Resume, Start over, Favourite).
/// The focused button turns light so it stands out from the accent one.
class VodActionButton extends StatelessWidget {
  const VodActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onSelect,
    this.primary = false,
    this.autofocus = false,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onSelect;
  final bool primary;
  final bool autofocus;
  final FocusNode? focusNode;

  static const _radius = BorderRadius.all(Radius.circular(Radii.pill));

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      focusScale: 1.04,
      borderRadius: _radius,
      semanticLabel: label,
      onSelect: onSelect,
      child: Builder(
        builder: (context) {
          final highlighted = TvHighlight.of(context);
          final (background, foreground) = highlighted
              ? (AppColors.textPrimary, AppColors.background)
              : primary
              ? (AppColors.accent, AppColors.onAccent)
              : (AppColors.surfaceHighest, AppColors.textPrimary);
          return Container(
            height: 40,
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Spacing.lg,
            ),
            decoration: BoxDecoration(color: background, borderRadius: _radius),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: Spacing.sm),
                Text(
                  label,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: foreground),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One entry of a category list (TV pane) or a category chip (phone).
class VodCategoryTile extends StatelessWidget {
  const VodCategoryTile({
    super.key,
    required this.label,
    required this.selected,
    this.count,
    this.icon,
    this.chip = false,
    this.onSelect,
    this.onFocusChange,
    this.focusNode,
  });

  final String label;
  final bool selected;
  final int? count;
  final IconData? icon;
  final FocusNode? focusNode;

  /// Phone style: a rounded chip sized to its label.
  final bool chip;
  final VoidCallback? onSelect;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    final radius = chip
        ? const BorderRadius.all(Radius.circular(Radii.pill))
        : Radii.mdAll;
    return TvFocusable(
      focusNode: focusNode,
      focusScale: 1.03,
      borderRadius: radius,
      semanticLabel: count == null ? label : '$label ($count)',
      onSelect: onSelect,
      onFocusChange: onFocusChange,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context).textTheme;
          final highlighted = TvHighlight.of(context);
          final background = highlighted
              ? AppColors.surfaceHighest
              : selected
              ? AppColors.accent.withValues(alpha: chip ? 0.22 : 0.14)
              : chip
              ? AppColors.surfaceHigh
              : Colors.transparent;
          final color = selected ? AppColors.accent : AppColors.textPrimary;
          final count = this.count;
          final icon = this.icon;
          final text = chip
              ? Text(
                  label,
                  maxLines: 1,
                  textDirection: textDirectionFor(label),
                  style: theme.labelLarge?.copyWith(color: color),
                )
              : BidiText(
                  label,
                  // Two lines fit the 40 dp rows of the narrow TV pane.
                  maxLines: 2,
                  style: theme.labelLarge?.copyWith(color: color),
                );
          return Container(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Spacing.md,
            ),
            decoration: BoxDecoration(color: background, borderRadius: radius),
            child: Row(
              mainAxisSize: chip ? MainAxisSize.min : MainAxisSize.max,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: Spacing.sm),
                ],
                if (chip) text else Expanded(child: text),
                if (count != null) ...[
                  const SizedBox(width: Spacing.sm),
                  Text(
                    '$count',
                    textDirection: TextDirection.ltr,
                    style: theme.labelMedium,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Year · rating · genre · runtime, skipping what is unknown.
class VodMetaLine extends StatelessWidget {
  const VodMetaLine({
    super.key,
    this.year,
    this.rating,
    this.genre,
    this.runtimeSec,
  });

  final int? year;
  final double? rating;
  final String? genre;
  final int? runtimeSec;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: AppColors.textSecondary);
    final rating = formatRating(this.rating);
    final minutes = runtimeMinutes(runtimeSec);
    final genre = this.genre?.trim();
    final parts = <Widget>[
      if (year != null)
        Text('$year', textDirection: TextDirection.ltr, style: style),
      if (rating != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, size: 16, color: AppColors.favorite),
            const SizedBox(width: Spacing.xxs),
            Text(rating, textDirection: TextDirection.ltr, style: style),
          ],
        ),
      if (genre != null && genre.isNotEmpty)
        Text(genre, textDirection: textDirectionFor(genre), style: style),
      if (minutes != null) Text(l10n.vodMinutes(minutes), style: style),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (i, part) in parts.indexed) ...[
          if (i > 0) Text('·', style: style),
          part,
        ],
      ],
    );
  }
}

/// The "Continue watching" row above the poster grid: newest first, each
/// card with its progress bar.
class ContinueWatchingRow extends StatelessWidget {
  const ContinueWatchingRow({
    super.key,
    required this.items,
    required this.cardWidth,
    required this.onOpen,
  });

  final List<ContinueWatchingItem> items;
  final double cardWidth;
  final ValueChanged<ContinueWatchingItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final itemExtent = cardWidth + VodGridLayout.spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: VodGridLayout.padding,
          ),
          child: SectionHeader(
            l10n.vodContinueWatching,
            padding: const EdgeInsetsDirectional.only(top: Spacing.xs),
          ),
        ),
        SizedBox(
          height:
              PosterCard.heightForWidth(cardWidth) + VodGridLayout.padding * 2,
          child: ListView.builder(
            key: const ValueKey('vod-continue-row'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(VodGridLayout.padding),
            itemExtent: itemExtent,
            itemCount: items.length,
            findChildIndexCallback: continueIndexOf(items, _slotKey),
            itemBuilder: (context, i) {
              final item = items[i];
              return Padding(
                key: _slotKey(item),
                padding: const EdgeInsetsDirectional.only(
                  end: VodGridLayout.spacing,
                ),
                child: PosterCard(
                  key: ValueKey('vod-cw-${item.kind.name}-${item.key}'),
                  title: continueTitle(item),
                  posterUrl: item.poster,
                  progress: item.progress.fraction,
                  onSelect: () => onOpen(item),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

Key _slotKey(ContinueWatchingItem item) =>
    ValueKey('vod-cw-slot-${item.kind.name}-${item.key}');

/// `findChildIndexCallback` of a continue-watching list whose children are
/// keyed with [keyOf]. Watching a title moves it to the front: its card
/// moves along instead of being rebuilt, so a focused card keeps its focus
/// node (and Back from the title returns to it).
ChildIndexGetter continueIndexOf(
  List<ContinueWatchingItem> items,
  Key Function(ContinueWatchingItem item) keyOf,
) => (key) {
  final i = items.indexWhere((item) => keyOf(item) == key);
  return i < 0 ? null : i;
};

/// Card title of a continue-watching entry: the movie, or the series of an
/// episode.
String continueTitle(ContinueWatchingItem item) =>
    item.seriesName ?? item.title ?? item.key;

/// Detail page frame: a dimmed backdrop (skipped in Lite mode), overscan
/// margins on TV and an app bar with Back everywhere else (phones, tablets
/// and desktop windows, where a mouse needs a way back).
///
/// The tree keeps the same shape whether or not there is a backdrop, so a
/// backdrop arriving with the lazy details (or Lite mode changing) never
/// remounts the page: focus and scroll positions stay.
class VodDetailFrame extends ConsumerWidget {
  const VodDetailFrame({
    super.key,
    required this.title,
    required this.child,
    this.backdrop,
  });

  final String title;
  final String? backdrop;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formFactor = FormFactorScope.of(context);
    final tv = formFactor == FormFactor.tv;
    // The large layouts show the title in the page header.
    final large = isLargeLayout(context);
    final lite = ref.watch(liteModeProvider);
    final backdrop = this.backdrop;
    final showBackdrop = backdrop != null && backdrop.isNotEmpty && !lite;
    return Scaffold(
      appBar: tv ? null : AppBar(title: large ? null : BidiText(title)),
      body: Stack(
        children: [
          Positioned.fill(
            key: const ValueKey('vod-detail-backdrop'),
            child: showBackdrop
                ? ExcludeSemantics(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        VodImage(
                          url: backdrop,
                          icon: Icons.image_outlined,
                          maxCacheWidth: 1280,
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: AlignmentDirectional.centerStart,
                              end: AlignmentDirectional.centerEnd,
                              colors: [Color(0xF20B0E13), Color(0xB30B0E13)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Positioned.fill(
            key: const ValueKey('vod-detail-content'),
            child: SafeArea(
              // Below an app bar the Scaffold already removed the top inset.
              minimum: overscanPadding(formFactor),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// A 2:3 poster that is not focusable (detail pages).
class VodPoster extends StatelessWidget {
  const VodPoster({super.key, required this.url, required this.width});

  final String? url;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 1.5,
      child: ClipRRect(
        borderRadius: Radii.mdAll,
        child: VodImage(url: url),
      ),
    );
  }
}
