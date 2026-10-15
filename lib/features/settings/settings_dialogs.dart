import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';
import '../../tv/key_repeat.dart';
import '../../tv/tv_focusable.dart';
import '../../tv/tv_text_field.dart';
import '../../widgets/bidi_text.dart';
import 'settings_format.dart';

/// One option of a [ChoiceDialog].
typedef Choice<T> = ({T value, String label});

/// The test key of the option for [value]: `choice-<name>`.
ValueKey<String> choiceKey(Object? value) =>
    ValueKey('choice-${value is Enum ? value.name : value}');

/// Lets the user pick one of [choices]; completes with the picked value, or
/// null when cancelled. The current value has focus when the dialog opens.
Future<T?> showChoiceDialog<T extends Object>(
  BuildContext context, {
  required String title,
  required List<Choice<T>> choices,
  required T current,
}) => showDialog<T>(
  context: context,
  builder: (_) =>
      ChoiceDialog<T>(title: title, choices: choices, current: current),
);

/// A list of radio-style options; OK on one pops its value.
class ChoiceDialog<T extends Object> extends StatelessWidget {
  const ChoiceDialog({
    super.key,
    required this.title,
    required this.choices,
    required this.current,
  });

  final String title;
  final List<Choice<T>> choices;
  final T current;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hasCurrent = choices.any((c) => c.value == current);
    return AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.symmetric(vertical: Spacing.md),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
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
                    key: choiceKey(c.value),
                    autofocus: hasCurrent ? c.value == current : i == 0,
                    focusScale: 1.02,
                    semanticLabel: c.label,
                    onSelect: () => Navigator.of(context).pop(c.value),
                    child: ListTile(
                      selected: c.value == current,
                      leading: Icon(
                        c.value == current
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: c.value == current
                            ? theme.colorScheme.primary
                            : null,
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
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
      ],
    );
  }
}

/// Asks to confirm a destructive action; true when confirmed. The confirm
/// button has focus. [details] is shown left to right (e.g. a URL).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? details,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      final theme = Theme.of(context).textTheme;
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(message),
              if (details != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  details,
                  textDirection: TextDirection.ltr,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('confirm-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('confirm-ok'),
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

/// Edits a source's guide offset in [kEpgOffsetStepMin] steps between
/// [kMinEpgOffsetMin] and [kMaxEpgOffsetMin]; pops the new value on Save.
class EpgOffsetDialog extends StatefulWidget {
  const EpgOffsetDialog({super.key, required this.initial});

  final int initial;

  @override
  State<EpgOffsetDialog> createState() => _EpgOffsetDialogState();
}

class _EpgOffsetDialogState extends State<EpgOffsetDialog> {
  late int _value = stepEpgOffset(widget.initial, 0);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.settingsEpgOffset),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.settings_epgOffsetHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: Spacing.lg),
            Center(
              child: OffsetStepper(
                key: const ValueKey('offset-stepper'),
                value: _value,
                autofocus: true,
                onChanged: (v) => setState(() => _value = v),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('offset-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('offset-save'),
          onPressed: () => Navigator.of(context).pop(_value),
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}

/// A guide-offset value with − and + buttons.
///
/// One focus stop: Left/Right step the value (mirrored in RTL, so the arrow
/// toward the + button always adds), held keys repeat and speed up via
/// [KeyRepeatThrottle]; Up/Down move focus as usual. Touch uses the buttons.
class OffsetStepper extends StatefulWidget {
  const OffsetStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.autofocus = false,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool autofocus;

  @override
  State<OffsetStepper> createState() => _OffsetStepperState();
}

class _OffsetStepperState extends State<OffsetStepper> {
  final _node = FocusNode(debugLabel: 'offset stepper');
  bool _focused = false;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _step(int steps) {
    final next = stepEpgOffset(widget.value, steps);
    if (next != widget.value) widget.onChanged(next);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    final throttle = KeyRepeatThrottle.instance;
    final direction = arrowDirection(event.logicalKey);
    if (direction != TraversalDirection.left &&
        direction != TraversalDirection.right) {
      return KeyEventResult.ignored;
    }
    final steps = throttle.stepFor(event);
    if (event is KeyUpEvent) return KeyEventResult.handled;
    if (steps == 0) return KeyEventResult.handled;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final towardEnd = (direction == TraversalDirection.right) != rtl;
    _step(towardEnd ? steps : -steps);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final value = widget.value;
    return Semantics(
      label: l10n.settingsEpgOffset,
      value: formatEpgOffset(value),
      increasedValue: formatEpgOffset(stepEpgOffset(value, 1)),
      decreasedValue: formatEpgOffset(stepEpgOffset(value, -1)),
      onIncrease: () => _step(1),
      onDecrease: () => _step(-1),
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        onKeyEvent: _onKey,
        onFocusChange: (f) => setState(() => _focused = f),
        child: AnimatedContainer(
          duration: FocusTokens.animation,
          padding: const EdgeInsets.all(Spacing.xs),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: Radii.mdAll,
            border: Border.all(
              color: _focused ? FocusTokens.borderColor : AppColors.outline,
              width: _focused ? FocusTokens.borderWidth : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeFocus(
                child: IconButton(
                  key: const ValueKey('offset-earlier'),
                  tooltip: l10n.settings_epgOffsetEarlier,
                  onPressed: value > kMinEpgOffsetMin ? () => _step(-1) : null,
                  icon: const Icon(Icons.remove),
                ),
              ),
              SizedBox(
                width: 112,
                child: Text(
                  formatEpgOffset(value),
                  key: const ValueKey('offset-value'),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: theme.headlineSmall,
                ),
              ),
              ExcludeFocus(
                child: IconButton(
                  key: const ValueKey('offset-later'),
                  tooltip: l10n.settings_epgOffsetLater,
                  onPressed: value < kMaxEpgOffsetMin ? () => _step(1) : null,
                  icon: const Icon(Icons.add),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a guide URL. [onAdd] stores a valid http(s) URL and returns an
/// error message to show, or null on success (the dialog then pops true).
class AddEpgUrlDialog extends StatefulWidget {
  const AddEpgUrlDialog({super.key, required this.onAdd});

  final Future<String?> Function(String url) onAdd;

  @override
  State<AddEpgUrlDialog> createState() => _AddEpgUrlDialogState();
}

class _AddEpgUrlDialogState extends State<AddEpgUrlDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final url = parseGuideUrl(_controller.text);
    if (url == null) {
      setState(() => _error = l10n.errorInvalidUrl);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onAdd(url);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.settings_addEpgUrl),
      content: SizedBox(
        width: 460,
        child: TvTextField(
          key: const ValueKey('epg-url-field'),
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
          decoration: InputDecoration(
            labelText: l10n.fieldEpgUrl,
            hintText: l10n.settings_epgUrlHint,
            hintTextDirection: TextDirection.ltr,
            errorText: _error,
            errorMaxLines: 3,
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('epg-url-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('epg-url-add'),
          onPressed: _busy ? null : _submit,
          child: Text(l10n.commonAdd),
        ),
      ],
    );
  }
}
