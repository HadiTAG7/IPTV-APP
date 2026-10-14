import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A [TextField] that works with a D-pad.
///
/// Up/Down leave the field via [FocusNode.focusInDirection] (a single-line
/// field otherwise swallows them, flutter#147772). OK / Select opens the soft
/// keyboard. [textInputAction] `next` moves to [nextFocusNode] (or the next
/// field in traversal order); `done` and other actions hide the keyboard but
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
    final direction = key == LogicalKeyboardKey.arrowUp
        ? TraversalDirection.up
        : key == LogicalKeyboardKey.arrowDown
        ? TraversalDirection.down
        : null;
    if (direction != null) {
      _node.focusInDirection(direction);
      return KeyEventResult.handled;
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
