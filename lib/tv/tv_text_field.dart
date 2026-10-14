import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'key_repeat.dart';

/// Whether an arrow press towards [direction] should move focus away from
/// [node] rather than move a caret.
///
/// True when [node] is not in a text field, for up/down in a single-line
/// field, when the field is empty or has no caret, and when the collapsed
/// caret already sits at the end the press would move it to. Flutter moves
/// the caret logically (Left and Up go backward) in either text direction,
/// so those ends are offset 0 and the text length.
bool arrowLeavesTextField(FocusNode node, TraversalDirection direction) {
  final editable = node.context?.findAncestorStateOfType<EditableTextState>();
  if (editable == null) return true;
  final value = editable.textEditingValue;
  final selection = value.selection;
  if (value.text.isEmpty || !selection.isValid) return true;
  final vertical =
      direction == TraversalDirection.up ||
      direction == TraversalDirection.down;
  if (vertical && editable.widget.maxLines == 1) return true;
  if (!selection.isCollapsed) return false;
  final backward =
      direction == TraversalDirection.left ||
      direction == TraversalDirection.up;
  return backward
      ? selection.baseOffset <= 0
      : selection.baseOffset >= value.text.length;
}

/// A [TextField] that works with a D-pad.
///
/// Up/Down leave the field via [FocusNode.focusInDirection] (a single-line
/// field otherwise swallows them, flutter#147772); Left/Right move the caret
/// and leave the field once it is at that end ([arrowLeavesTextField]), on a
/// fresh press only. A press with nowhere to go inside the pane is left to an
/// enclosing `PaneScope`, so a pane holding only a field never traps focus.
///
/// OK / Select opens the soft keyboard. [textInputAction] `next` moves to
/// [nextFocusNode] (or the next field in traversal order); `done` and other
/// actions hide the keyboard but keep focus on the field, so a TV never ends
/// up with nothing focused.
class TvTextField extends StatefulWidget {
  const TvTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.nextFocusNode,
    this.decoration = const InputDecoration(),
    this.textInputAction = TextInputAction.next,
    this.keyboardType,
    this.obscureText = false,
    this.autofocus = false,
    this.enabled,
    this.autocorrect = false,
    this.autofillHints,
    this.inputFormatters,
    this.textDirection,
    this.style,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Field focused on `TextInputAction.next`.
  final FocusNode? nextFocusNode;
  final InputDecoration decoration;
  final TextInputAction textInputAction;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool autofocus;
  final bool? enabled;
  final bool autocorrect;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;

  /// Force a direction, e.g. LTR for URLs and passwords in an Arabic UI.
  final TextDirection? textDirection;
  final TextStyle? style;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> {
  FocusNode? _ownNode;

  FocusNode get _node =>
      widget.focusNode ?? (_ownNode ??= FocusNode(debugLabel: 'TvTextField'));

  @override
  void didUpdateWidget(TvTextField oldWidget) {
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

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (!_node.hasPrimaryFocus || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final direction = arrowDirection(key);
    if (direction != null) {
      if (!arrowLeavesTextField(_node, direction)) {
        return KeyEventResult.ignored;
      }
      final horizontal =
          direction == TraversalDirection.left ||
          direction == TraversalDirection.right;
      // A held Left/Right stops at the end of the text.
      if (horizontal && event is KeyRepeatEvent) return KeyEventResult.handled;
      return _node.focusInDirection(direction)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (event is KeyDownEvent) _requestKeyboard();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _requestKeyboard() {
    _node.context
        ?.findAncestorStateOfType<EditableTextState>()
        ?.requestKeyboard();
  }

  void _onEditingComplete() {
    if (widget.textInputAction == TextInputAction.next) {
      final next = widget.nextFocusNode;
      if (next != null) {
        next.requestFocus();
      } else {
        _node.nextFocus();
      }
      return;
    }
    if (widget.textInputAction == TextInputAction.previous) {
      _node.previousFocus();
      return;
    }
    // Keep focus on TV; just close the keyboard.
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide').ignore();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: _onKey,
      child: TextField(
        controller: widget.controller,
        focusNode: _node,
        decoration: widget.decoration,
        textInputAction: widget.textInputAction,
        keyboardType: widget.keyboardType,
        obscureText: widget.obscureText,
        autofocus: widget.autofocus,
        enabled: widget.enabled,
        autocorrect: widget.autocorrect,
        enableSuggestions: !widget.obscureText,
        autofillHints: widget.autofillHints,
        inputFormatters: widget.inputFormatters,
        textDirection: widget.textDirection,
        style: widget.style,
        maxLines: 1,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        onEditingComplete: _onEditingComplete,
      ),
    );
  }
}
