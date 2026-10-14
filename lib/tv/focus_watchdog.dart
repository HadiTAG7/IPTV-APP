import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'pane_scope.dart';

/// Restores focus on TV when it gets lost.
///
/// Listens to [FocusManager]. When [enabled] and the primary focus becomes
/// null, the root scope, or a bare [FocusScopeNode] (typical after a dialog,
/// sheet or route pop whose previously focused item was disposed), it waits
/// for the frame to settle and then re-focuses, in order:
/// 1. the most recently registered fallback inside the bare scope;
/// 2. the bare scope's first traversable item;
/// 3. when focus fell to the root, the most recent fallback in the current
///    route.
///
/// [PaneScope]s register themselves when focused, so their remembered item is
/// what comes back. Screens can [FocusWatchdogState.register] extra nodes.
class FocusWatchdog extends StatefulWidget {
  const FocusWatchdog({super.key, required this.child, this.enabled = true});

  final Widget child;

  /// Usually true only in TV mode.
  final bool enabled;

  static FocusWatchdogState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<FocusWatchdogState>();

  @override
  State<FocusWatchdog> createState() => FocusWatchdogState();
}

class FocusWatchdogState extends State<FocusWatchdog> {
  // Most recent last.
  final List<FocusNode> _fallbacks = [];
  bool _scheduled = false;

  /// Registered fallbacks, most recent first.
  @visibleForTesting
  List<FocusNode> get fallbacks => _fallbacks.reversed.toList();

  /// Adds [node] (or moves it to the front) as a focus fallback.
  void register(FocusNode node) {
    _fallbacks
      ..remove(node)
      ..add(node);
  }

  void unregister(FocusNode node) => _fallbacks.remove(node);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    super.dispose();
  }

  static bool _isLost(FocusNode? node) =>
      node == null ||
      node == FocusManager.instance.rootScope ||
      node is FocusScopeNode;

  void _onFocusChanged() {
    if (!widget.enabled || _scheduled) return;
    if (!_isLost(FocusManager.instance.primaryFocus)) return;
    _scheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _scheduled = false;
        if (mounted && widget.enabled) restore();
      })
      ..ensureVisualUpdate();
  }

  /// Re-focuses something sensible if focus is lost. Returns true if it moved
  /// focus.
  bool restore() {
    final primary = FocusManager.instance.primaryFocus;
    if (!_isLost(primary)) return false;
    _fallbacks.removeWhere((n) => n.context == null);
    final root = FocusManager.instance.rootScope;
    final scope = primary is FocusScopeNode && primary != root ? primary : null;

    for (final node in _fallbacks.reversed) {
      if (node == primary || !_usable(node)) continue;
      if (scope != null && !node.ancestors.contains(scope)) continue;
      if (_focus(node)) return true;
    }
    if (scope != null) return focusRememberedOrFirst(scope);
    return false;
  }

  bool _usable(FocusNode node) {
    final ctx = node.context;
    if (ctx == null || !ctx.mounted || !node.canRequestFocus) return false;
    final route = ModalRoute.of(ctx);
    return route == null || route.isCurrent;
  }

  static bool _focus(FocusNode node) {
    if (node is FocusScopeNode) return focusRememberedOrFirst(node);
    node.requestFocus();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
