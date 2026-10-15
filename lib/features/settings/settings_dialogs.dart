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

/// Reading-order traversal where Down from one of [from] goes straight to
/// [primary] (a dialog's main button).
///
/// Dialog buttons sit at the end of the action row, so the nearest button
/// below a centred control or a full-width field is Cancel. A remote user
/// who adjusts a value and presses Down, then OK, means to save it.
/// While [primary] cannot take focus (a disabled button), Down moves as
/// usual.
class PrimaryBelowTraversalPolicy extends ReadingOrderTraversalPolicy {
  PrimaryBelowTraversalPolicy({required this.from, required this.primary});

  final List<FocusNode> from;
  final FocusNode primary;

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    if (direction == TraversalDirection.down &&
        from.contains(currentNode) &&
        primary.context != null &&
        primary.canRequestFocus) {
      primary.requestFocus();
      return true;
    }
    return super.inDirection(currentNode, direction);
  }
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
  final _stepperNode = FocusNode(debugLabel: 'offset stepper');
  final _saveNode = FocusNode(debugLabel: 'offset save');
  late final _policy = PrimaryBelowTraversalPolicy(
    from: [_stepperNode],
    primary: _saveNode,
  );

  @override
  void dispose() {
    _stepperNode.dispose();
    _saveNode.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_value);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dialog = AlertDialog(
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
                focusNode: _stepperNode,
                value: _value,
                autofocus: true,
                onChanged: (v) => setState(() => _value = v),
                // OK on the value saves it, like Save.
                onSubmit: _save,
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
          focusNode: _saveNode,
          onPressed: _save,
          child: Text(l10n.commonSave),
        ),
      ],
    );
    return FocusTraversalGroup(policy: _policy, child: dialog);
  }
}

/// A guide-offset value with − and + buttons.
///
/// One focus stop: Left/Right step the value (mirrored in RTL, so the arrow
/// toward the + button always adds), held keys repeat and speed up via
/// [KeyRepeatThrottle]; Up/Down move focus as usual and OK calls
/// [onSubmit]. Touch uses the buttons.
class OffsetStepper extends StatefulWidget {
  const OffsetStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.onSubmit,
    this.autofocus = false,
    this.focusNode,
  });

  final int value;
  final ValueChanged<int> onChanged;

  /// Called by OK (or Enter) while the stepper has focus.
  final VoidCallback? onSubmit;
  final bool autofocus;

  /// Optional external node; otherwise one is kept in this widget's state.
  final FocusNode? focusNode;

  @override
  State<OffsetStepper> createState() => _OffsetStepperState();
}

class _OffsetStepperState extends State<OffsetStepper> {
  FocusNode? _ownNode;
  bool _focused = false;

  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        widget.onSubmit?.call();
        return null;
      },
    ),
  };

  FocusNode get _node =>
      widget.focusNode ??
      (_ownNode ??= FocusNode(debugLabel: 'offset stepper'));

  @override
  void didUpdateWidget(OffsetStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != null && _ownNode != null) {
      _ownNode!.dispose();
      _ownNode = null;
    }
  }

  @override
  void dispose() {
    _ownNode?.dispose();
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
      child: Actions(
        actions: _actions,
        child: Focus(
          focusNode: _node,
          autofocus: widget.autofocus,
          onKeyEvent: _onKey,
          onFocusChange: (f) => setState(() => _focused = f),
          child: AnimatedContainer(
            duration: FocusTokens.animationOf(context),
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
                    onPressed: value > kMinEpgOffsetMin
                        ? () => _step(-1)
                        : null,
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
      ),
    );
  }
}

/// What [AddEpgUrlDialog.onAdd] did with a URL.
enum AddEpgUrlResult {
  /// Saved; the dialog closes.
  added,

  /// The source already lists this URL.
  exists,

  /// Saving failed (already logged).
  failed,
}

/// Asks for a guide URL. [onAdd] stores a valid http(s) URL; the dialog
/// pops true once it is added and otherwise shows why not. Down from the
/// field goes to Add.
///
/// [onAdd] must not depend on the page that opened the dialog: that page
/// can be gone by the time the user presses Add (for example a large phone
/// rotated to portrait drops the Settings tab).
class AddEpgUrlDialog extends StatefulWidget {
  const AddEpgUrlDialog({super.key, required this.onAdd});

  final Future<AddEpgUrlResult> Function(String url) onAdd;

  @override
  State<AddEpgUrlDialog> createState() => _AddEpgUrlDialogState();
}

class _AddEpgUrlDialogState extends State<AddEpgUrlDialog> {
  final _controller = TextEditingController();
  final _fieldNode = FocusNode(debugLabel: 'epg url field');
  final _addNode = FocusNode(debugLabel: 'epg url add');
  late final _policy = PrimaryBelowTraversalPolicy(
    from: [_fieldNode],
    primary: _addNode,
  );
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _fieldNode.dispose();
    _addNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final url = parseGuideUrl(_controller.text);
    if (url == null) {
      setState(() => _error = AppLocalizations.of(context).errorInvalidUrl);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    AddEpgUrlResult result;
    try {
      result = await widget.onAdd(url);
    } on Object {
      result = AddEpgUrlResult.failed;
    }
    if (!mounted) return;
    if (result == AddEpgUrlResult.added) {
      Navigator.of(context).pop(true);
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      _error = result == AddEpgUrlResult.exists
          ? l10n.settings_epgUrlExists
          : l10n.settings_saveFailed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dialog = AlertDialog(
      title: Text(l10n.settings_addEpgUrl),
      content: SizedBox(
        width: 460,
        child: TvTextField(
          key: const ValueKey('epg-url-field'),
          controller: _controller,
          focusNode: _fieldNode,
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
        // Stays enabled while saving (_submit ignores the press): a
        // disabled button gives up focus, which falls back to the field
        // and reopens the soft keyboard over the dialog.
        FilledButton(
          key: const ValueKey('epg-url-add'),
          focusNode: _addNode,
          onPressed: _submit,
          child: _BusyLabel(label: l10n.commonAdd, busy: _busy),
        ),
      ],
    );
    return FocusTraversalGroup(policy: _policy, child: dialog);
  }
}

/// A button label that shows a spinner in its place while [busy], keeping
/// the button's size and spoken label.
class _BusyLabel extends StatelessWidget {
  const _BusyLabel({required this.label, required this.busy});

  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: AlignmentDirectional.center,
      children: [
        Visibility(
          visible: !busy,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          maintainSemantics: true,
          child: Text(label),
        ),
        if (busy)
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: DefaultTextStyle.of(context).style.color,
            ),
          ),
      ],
    );
  }
}
