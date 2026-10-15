import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/db/app_db.dart';
import '../../epg/epg_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';
import '../../tv/tv_focusable.dart';
import '../../widgets/bidi_text.dart';
import '../../widgets/states.dart';
import 'guide_data.dart';
import 'guide_format.dart';

/// A compact pill button for the guide header (filter, refresh).
class GuideHeaderButton extends StatelessWidget {
  const GuideHeaderButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onSelect,
    this.busy = false,
    this.maxLabelWidth = 200,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelect;

  /// Shows a spinner instead of [icon].
  final bool busy;
  final double maxLabelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return TvFocusable(
      focusScale: 1.04,
      semanticLabel: label,
      onSelect: onSelect,
      child: Container(
        height: 32,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: Spacing.md),
        decoration: const BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: Radii.mdAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: Spacing.sm),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxLabelWidth),
              child: BidiText(label, style: theme.labelLarge),
            ),
          ],
        ),
      ),
    );
  }
}

/// "No guide data": how to add a guide URL, with Refresh (a spinner while
/// [running]) and Settings.
class GuideNoData extends StatelessWidget {
  const GuideNoData({
    super.key,
    required this.onRefresh,
    required this.onSettings,
    this.running = false,
  });

  final VoidCallback onRefresh;
  final VoidCallback onSettings;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EmptyView(
      icon: Icons.view_timeline_outlined,
      message: l10n.guideEmpty,
      action: Wrap(
        alignment: WrapAlignment.center,
        spacing: Spacing.md,
        runSpacing: Spacing.sm,
        children: [
          // First in the page's focus order (see GuideScreen). It stays
          // enabled while running so it keeps focus.
          FocusTraversalOrder(
            order: const NumericFocusOrder(0),
            child: FilledButton.icon(
              key: const ValueKey('guide-empty-refresh'),
              onPressed: running ? () {} : onRefresh,
              icon: running
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onAccent,
                      ),
                    )
                  : const Icon(Icons.refresh),
              label: Text(running ? l10n.guideUpdating : l10n.guideRefresh),
            ),
          ),
          OutlinedButton.icon(
            key: const ValueKey('guide-empty-settings'),
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined),
            label: Text(l10n.navSettings),
          ),
        ],
      ),
    );
  }
}

/// Shows a programme (or, with no [programme], the channel without
/// programme info) with "Watch channel" and Close (focused).
Future<void> showGuideProgrammeInfo(
  BuildContext context, {
  required ChannelRow channel,
  required EpgProgramme? programme,
  required DateTime now,
  required DateFormat timeFormat,
  required VoidCallback onWatch,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      final theme = Theme.of(context).textTheme;
      final locale = Localizations.localeOf(context).toLanguageTag();
      final desc = programme?.desc ?? programme?.subTitle;
      final number = channel.num;
      return AlertDialog(
        key: const ValueKey('guide-info'),
        title: BidiText(
          programme?.title ?? l10n.liveNoProgrammeInfo,
          maxLines: 3,
          style: theme.titleLarge,
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BidiText(
                number == null ? channel.name : '$number  ${channel.name}',
                style: theme.labelMedium,
              ),
              if (programme != null) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  guideProgrammeTimes(l10n, locale, timeFormat, programme, now),
                  style: theme.bodySmall,
                ),
              ],
              if (desc != null && desc.isNotEmpty) ...[
                const SizedBox(height: Spacing.md),
                BidiText(desc, maxLines: 8, style: theme.bodyMedium),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('guide-info-watch'),
            onPressed: () {
              Navigator.of(context).pop();
              onWatch();
            },
            child: Text(l10n.guideWatchChannel),
          ),
          FilledButton(
            key: const ValueKey('guide-info-close'),
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonClose),
          ),
        ],
      );
    },
  );
}

/// One choice of the filter picker.
typedef GuideFilterOption = ({GuideFilter filter, String label, int? count});

/// Lets the user pick the guide's channel list; the current one is
/// focused. Returns the pick, or null.
Future<GuideFilter?> showGuideFilterPicker(
  BuildContext context, {
  required List<GuideFilterOption> options,
  required GuideFilter current,
}) => showDialog<GuideFilter>(
  context: context,
  builder: (_) => _GuideFilterPicker(options: options, current: current),
);

class _GuideFilterPicker extends StatefulWidget {
  const _GuideFilterPicker({required this.options, required this.current});

  final List<GuideFilterOption> options;
  final GuideFilter current;

  static const extent = 48.0;

  @override
  State<_GuideFilterPicker> createState() => _GuideFilterPickerState();
}

class _GuideFilterPickerState extends State<_GuideFilterPicker> {
  late final int _index = widget.options.indexWhere(
    (o) => o.filter == widget.current,
  );

  // Opens at the current choice so it is built and can take focus.
  late final _scroll = ScrollController(
    initialScrollOffset: _index <= 2
        ? 0
        : (_index - 2) * _GuideFilterPicker.extent,
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const extent = _GuideFilterPicker.extent;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final options = widget.options;
    final height = (options.length * extent).clamp(extent, 6 * extent);
    return AlertDialog(
      title: Text(l10n.liveCategories),
      contentPadding: const EdgeInsets.symmetric(vertical: Spacing.md),
      content: SizedBox(
        width: 360,
        height: height,
        child: ListView.builder(
          controller: _scroll,
          itemExtent: extent,
          itemCount: options.length,
          itemBuilder: (context, i) {
            final o = options[i];
            final selected = o.filter == widget.current;
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.xxs,
              ),
              child: TvFocusable(
                key: ValueKey('guide-filter-$i'),
                autofocus: _index < 0 ? i == 0 : selected,
                focusScale: 1.02,
                onSelect: () => Navigator.of(context).pop(o.filter),
                child: Container(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: Spacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.surfaceHighest : null,
                    borderRadius: Radii.mdAll,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: selected
                            ? theme.colorScheme.primary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: BidiText(
                          o.label,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (o.count case final count?)
                        Text(
                          '$count',
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.labelMedium,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
      ],
    );
  }
}

/// The picker's choices: favourites (when there are any), all channels,
/// then every visible category that has channels.
List<GuideFilterOption> guideFilterOptions(
  AppLocalizations l10n, {
  required List<String> favoriteKeys,
  required List<CategoryRow> categories,
}) => [
  if (favoriteKeys.isNotEmpty)
    (
      filter: GuideFilter.favorites,
      label: l10n.liveFavorites,
      count: favoriteKeys.length,
    ),
  (filter: GuideFilter.all, label: l10n.liveAllChannels, count: null),
  for (final c in categories)
    if (c.itemCount > 0)
      (filter: GuideFilter.category(c.key), label: c.name, count: c.itemCount),
];
