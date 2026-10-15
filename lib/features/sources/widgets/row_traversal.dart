import 'package:flutter/widgets.dart';

/// Reading-order traversal whose Left/Right only move along the current row.
///
/// Flutter's directional search falls back to targets outside the focused
/// item's row (a diagonal jump into the next card or field) when the row
/// has nothing further that way. On a remote that feels like losing your
/// place, so here a Left/Right press with nothing beside the item fails
/// instead: focus stays put, and an enclosing `PaneScope` (the TV shell)
/// can still take that press to the neighbouring pane. Up/Down are
/// unchanged.
class RowTraversalPolicy extends ReadingOrderTraversalPolicy {
  RowTraversalPolicy({super.requestFocusCallback});

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final horizontal =
        direction == TraversalDirection.left ||
        direction == TraversalDirection.right;
    final scope = currentNode.nearestScope;
    if (horizontal &&
        scope != null &&
        !_hasRowNeighbour(currentNode, scope, direction)) {
      return false;
    }
    return super.inDirection(currentNode, direction);
  }

  static bool _hasRowNeighbour(
    FocusNode current,
    FocusScopeNode scope,
    TraversalDirection direction,
  ) {
    final rect = current.rect;
    const slack = 1.0;
    for (final node in scope.traversalDescendants) {
      if (node == current || node is FocusScopeNode) continue;
      final r = node.rect;
      final sameRow =
          r.top < rect.bottom - slack && r.bottom > rect.top + slack;
      if (!sameRow) continue;
      final beyond = direction == TraversalDirection.right
          ? r.left >= rect.right - slack
          : r.right <= rect.left + slack;
      if (beyond) return true;
    }
    return false;
  }
}
