import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../tv/tv_focusable.dart';
import '../../widgets/bidi_text.dart';

/// One choice of an [showOptionsSheet].
class SheetOption<T> {
  const SheetOption({
    required this.value,
    required this.icon,
    required this.label,
  });

  final T value;
  final IconData icon;
  final String label;
}

/// A remote-friendly options sheet (the Menu key, or a long press): a title
/// and a list of choices, the first one focused. Returns the chosen value,
/// or null when dismissed (Back pops the sheet's route).
Future<T?> showOptionsSheet<T>(
  BuildContext context, {
  required String title,
  required List<SheetOption<T>> options,
}) {
  if (options.isEmpty) return Future.value();
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    showDragHandle: false,
    builder: (_) => OptionsSheet<T>(title: title, options: options),
  );
}

/// The body of [showOptionsSheet].
class OptionsSheet<T> extends StatelessWidget {
  const OptionsSheet({super.key, required this.title, required this.options});

  final String title;
  final List<SheetOption<T>> options;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: Spacing.sm,
              bottom: Spacing.md,
            ),
            child: BidiText(title, style: theme.textTheme.titleLarge),
          ),
          for (final (i, option) in options.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
              child: TvFocusable(
                key: ValueKey('option-${option.value}'),
                autofocus: i == 0,
                focusScale: 1.02,
                semanticLabel: option.label,
                onSelect: () => Navigator.of(context).pop(option.value),
                child: ListTile(
                  leading: Icon(option.icon),
                  title: Text(option.label),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
