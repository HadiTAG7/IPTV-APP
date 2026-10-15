import 'package:flutter/widgets.dart';

/// Reading-order traversal that puts [preferred] nodes first when a scope
/// picks its first focus (entering a screen or pane that remembers nothing
/// yet), so the remote lands on the meaningful item: the current channel,
/// the selected category, the first search result.
///
/// The order only changes for first-focus lookups (`currentNode` is the
/// scope being entered); Tab traversal from a focused item keeps reading
/// order, and arrow keys stay geometric.
class PreferredFirstTraversalPolicy extends ReadingOrderTraversalPolicy {
  PreferredFirstTraversalPolicy(this.preferred);

  /// Nodes to try first, most preferred first; nulls are skipped.
  final List<FocusNode?> Function() preferred;

  @override
  Iterable<FocusNode> sortDescendants(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) {
    final sorted = super.sortDescendants(descendants, currentNode).toList();
    if (currentNode is! FocusScopeNode) return sorted;
    for (final node in preferred().reversed) {
      if (node != null && node.canRequestFocus && sorted.remove(node)) {
        sorted.insert(0, node);
      }
    }
    return sorted;
  }
}

/// Runs [action] after the next frame (and makes sure one is scheduled).
void afterNextFrame(VoidCallback action) {
  WidgetsBinding.instance
    ..addPostFrameCallback((_) => action())
    ..ensureVisualUpdate();
}

/// Whether [node] is in the focus tree of a mounted widget.
bool isAttached(FocusNode? node) =>
    node != null && node.parent != null && (node.context?.mounted ?? false);
