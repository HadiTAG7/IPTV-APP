import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/form_factor.dart';
import 'dpad_shortcuts.dart';
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
/// OK / Select opens the soft keyboard. On Android TV focus alone never
/// does: a field the D-pad passes through (or an autofocused one) stays
/// read-only until OK or a tap, so the soft keyboard (often fullscreen) does
/// not pop up at every field and capture the D-pad. [textInputAction] `next`
/// moves to [nextFocusNode] (or the next field in traversal order) and keeps
/// the keyboard open there; `done` and other actions hide the keyboard but
/// keep focus on the field, so a TV never ends up with nothing focused.
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
  /// Set while Next/Previous on the soft keyboard moves focus, so the field
  /// that gets it opens the keyboard too.
  static bool _keyboardHandoff = false;

  FocusNode? _ownNode;
  FocusNode? _listening;

  /// Android TV: the field is read-only (no input connection, so no soft
  /// keyboard) until [_editing].
  bool _deferKeyboard = false;

  /// OK, a tap or Next opened the keyboard; ends when the field loses focus.
  bool _editing = false;

  FocusNode get _node =>
      widget.focusNode ?? (_ownNode ??= FocusNode(debugLabel: 'TvTextField'));

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    final node = _node;
    if (identical(node, _listening)) return;
    _listening?.removeListener(_onFocusChange);
    _listening = node..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(TvTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final stale = widget.focusNode != null ? _ownNode : null;
    if (stale != null) _ownNode = null;
    _listen();
    stale?.dispose();
  }

  @override
  void dispose() {
    _listening?.removeListener(_onFocusChange);
    _ownNode?.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_node.hasFocus) {
      if (_editing) setState(() => _editing = false);
    } else if (_keyboardHandoff) {
      _keyboardHandoff = false;
      _startEditing();
    }
  }

  /// Makes the field editable; once it is laid out with focus, EditableText
  /// opens the input connection and shows the keyboard.
  void _startEditing() {
    if (_editing || !mounted) return;
    setState(() => _editing = true);
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
    // Enter goes to the open keyboard; on a read-only field it opens it
    // (some remotes send Enter for OK).
    final opens =
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        (selectKeys.contains(key) && _readOnly);
    if (opens) {
      if (event is KeyDownEvent) _requestKeyboard();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool get _readOnly => _deferKeyboard && !_editing;

  void _requestKeyboard() {
    if (_readOnly) {
      _startEditing();
      return;
    }
    _node.context
        ?.findAncestorStateOfType<EditableTextState>()
        ?.requestKeyboard();
  }

  /// Also calls [TvTextField.onSubmitted]: given to the [TextField], it would
  /// make the field, still focused after Done, restart its input connection
  /// and show the keyboard again (flutter#84240), over what the submission
  /// shows.
  void _onEditingComplete() {
    final text =
        _node.context
            ?.findAncestorStateOfType<EditableTextState>()
            ?.textEditingValue
            .text ??
        widget.controller?.text ??
        '';
    _moveOnOrHide();
    widget.onSubmitted?.call(text);
  }

  void _moveOnOrHide() {
    if (widget.textInputAction == TextInputAction.next) {
      _handOffKeyboard(() {
        final next = widget.nextFocusNode;
        if (next != null) {
          next.requestFocus();
        } else {
          _node.nextFocus();
        }
      });
      return;
    }
    if (widget.textInputAction == TextInputAction.previous) {
      _handOffKeyboard(_node.previousFocus);
      return;
    }
    // Keep focus on TV; just close the keyboard.
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide').ignore();
  }

  /// Runs [moveFocus] so that the field it focuses opens the keyboard too.
  /// The focus change is applied in a microtask queued by the request (or
  /// earlier); the flag is cleared in one queued after it, in case no field
  /// took it.
  void _handOffKeyboard(void Function() moveFocus) {
    _keyboardHandoff = _deferKeyboard;
    moveFocus();
    scheduleMicrotask(() => _keyboardHandoff = false);
  }

  @override
  Widget build(BuildContext context) {
    _deferKeyboard =
        defaultTargetPlatform == TargetPlatform.android &&
        FormFactorScope.isTv(context);
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
        onEditingComplete: _onEditingComplete,
        // Read-only keeps the caret, so Left/Right still show where it is.
        readOnly: _readOnly,
        showCursor: true,
        onTap: _startEditing,
      ),
    );
  }
}
