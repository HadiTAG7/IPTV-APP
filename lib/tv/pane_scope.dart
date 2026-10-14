import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'focus_watchdog.dart';
import 'key_repeat.dart';
import 'tv_text_field.dart';

/// Focuses [scope]'s remembered child, or its first traversable descendant
/// when it has none. Returns false when nothing in the scope can take focus.
bool focusRememberedOrFirst(FocusScopeNode scope) {
  if (scope.context == null) return false;
  final policy =
      FocusTraversalGroup.maybeOfNode(scope) ?? ReadingOrderTraversalPolicy();
  final target = policy.findFirstFocus(scope);
  if (target == null || target == scope || !target.canRequestFocus) {
    final first = scope.traversalDescendants
        .where((n) => n is! FocusScopeNode && n.canRequestFocus)
        .firstOrNull;
    if (first == null) return false;
    first.requestFocus();
    return true;
  }
  if (target is FocusScopeNode) return focusRememberedOrFirst(target);
  target.requestFocus();
  return true;
}

/// A focus pane (rail, category list, channel list, info panel...).
///
/// Wraps [child] in a [FocusScope] whose node remembers the last focused
/// child, so returning to the pane lands on the same item. Left/right presses
/// that find nothing further inside the pane call [onExitStart] or
/// [onExitEnd]; in RTL the physical arrows are mirrored, so "start" is always
/// the reading-start side. Up/down exits are optional. Exits only happen on a
/// fresh key press, never on auto-repeat, so a held key stops at the edge.
/// In a text field Left/Right move the caret first and exit once it is at
/// that end of the text; Up/Down exit directly ([arrowLeavesTextField]).
///
/// Use a `GlobalKey<PaneScopeState>` and [PaneScopeState.requestFocus] to move
/// focus into a neighbour pane.
class PaneScope extends StatefulWidget {
  const PaneScope({
    super.key,
    required this.child,
    this.onExitStart,
    this.onExitEnd,
    this.onExitUp,
    this.onExitDown,
    this.autofocus = false,
    this.debugLabel,
  });

  final Widget child;
  final VoidCallback? onExitStart;
  final VoidCallback? onExitEnd;
  final VoidCallback? onExitUp;
  final VoidCallback? onExitDown;

  /// Focuses the first item after the first frame.
  final bool autofocus;
  final String? debugLabel;

  @override
  State<PaneScope> createState() => PaneScopeState();
}

class PaneScopeState extends State<PaneScope> {
  late final FocusScopeNode node = FocusScopeNode(
    debugLabel: widget.debugLabel ?? 'PaneScope',
  );
  FocusWatchdogState? _watchdog;

  /// The item focus returns to when the pane is entered again.
  FocusNode? get lastFocused => node.focusedChild;

  bool get hasFocus => node.hasFocus;

  /// Focuses the remembered item, or the first one.
  bool requestFocus() => focusRememberedOrFirst(node);

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !node.hasFocus) requestFocus();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final watchdog = FocusWatchdog.maybeOf(context);
    if (watchdog != _watchdog) {
      _watchdog?.unregister(node);
      _watchdog = watchdog;
    }
  }

  @override
  void dispose() {
    _watchdog?.unregister(node);
    node.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    if (focused) _watchdog?.register(node);
  }

  VoidCallback? _exitFor(TraversalDirection direction) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return switch (direction) {
      TraversalDirection.left => rtl ? widget.onExitEnd : widget.onExitStart,
      TraversalDirection.right => rtl ? widget.onExitStart : widget.onExitEnd,
      TraversalDirection.up => widget.onExitUp,
      TraversalDirection.down => widget.onExitDown,
    };
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final direction = arrowDirection(event.logicalKey);
    if (direction == null) return KeyEventResult.ignored;
    final exit = _exitFor(direction);
    if (exit == null) return KeyEventResult.ignored;
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || !arrowLeavesTextField(primary, direction)) {
      return KeyEventResult.ignored;
    }
    if (primary.focusInDirection(direction)) return KeyEventResult.handled;
    if (event is KeyDownEvent) exit();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: node,
      onKeyEvent: _onKey,
      onFocusChange: _onFocusChange,
      child: widget.child,
    );
  }
}
