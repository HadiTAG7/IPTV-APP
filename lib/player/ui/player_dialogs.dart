import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';
import '../../tv/tv_focusable.dart';
import '../../widgets/bidi_text.dart';

/// One option of [showPlayerChoiceDialog].
class PlayerChoice<T> {
  const PlayerChoice({
    required this.value,
    required this.label,
    this.selected = false,
    this.icon,
  });

  final T value;
  final String label;

  /// Shown with a checked radio; it gets the initial focus.
  final bool selected;

  /// Shown instead of the radio (action lists).
  final IconData? icon;
}

/// A remote-friendly list dialog (tracks, aspect ratio, options). Returns
/// the picked value, or null when dismissed. The selected option (else the
/// first) has the initial focus.
Future<T?> showPlayerChoiceDialog<T>(
  BuildContext context, {
  required String title,
  required List<PlayerChoice<T>> choices,
  String? emptyMessage,
}) => showDialog<T>(
  context: context,
  builder: (context) => _PlayerChoiceDialog<T>(
    title: title,
    choices: choices,
    emptyMessage: emptyMessage,
  ),
);

class _PlayerChoiceDialog<T> extends StatelessWidget {
  const _PlayerChoiceDialog({
    required this.title,
    required this.choices,
    this.emptyMessage,
  });

  final String title;
  final List<PlayerChoice<T>> choices;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final focusIndex = choices.indexWhere((c) => c.selected);
    final empty = emptyMessage;
    return AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.symmetric(vertical: Spacing.md),
      content: SizedBox(
        width: 360,
        child: choices.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
                child: Text(
                  empty ?? l10n.player_noTracks,
                  style: theme.textTheme.bodyMedium,
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, c) in choices.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.md,
                          vertical: Spacing.xxs,
                        ),
                        child: TvFocusable(
                          key: ValueKey('player-choice-$i'),
                          autofocus: i == (focusIndex < 0 ? 0 : focusIndex),
                          focusScale: 1.02,
                          semanticLabel: c.label,
                          onSelect: () => Navigator.of(context).pop(c.value),
                          child: ListTile(
                            leading: Icon(
                              c.icon ??
                                  (c.selected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked),
                              color: c.selected ? AppColors.accent : null,
                            ),
                            title: BidiText(c.label),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          autofocus: choices.isEmpty,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(choices.isEmpty ? l10n.commonClose : l10n.commonCancel),
        ),
      ],
    );
  }
}

/// Subtitles need mpv: offers to switch players. True when the user chose
/// "Switch player".
Future<bool> showSubtitlesNeedMpvDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final picked = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.playerSubtitles),
      content: Text(l10n.playerSubtitlesNeedMpv),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('player-subtitles-switch'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.playerSwitchPlayer),
        ),
      ],
    ),
  );
  return picked ?? false;
}
