import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/time/clock.dart';

/// Direction for an arrow key, or null for any other key.
TraversalDirection? arrowDirection(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.arrowUp) return TraversalDirection.up;
  if (key == LogicalKeyboardKey.arrowDown) return TraversalDirection.down;
  if (key == LogicalKeyboardKey.arrowLeft) return TraversalDirection.left;
  if (key == LogicalKeyboardKey.arrowRight) return TraversalDirection.right;
  return null;
}

/// Limits held arrow keys to about 10 moves per second and, once a key has
/// been held for [jumpAfter], reports jumps of [jumpSize] items.
///
/// [stepFor] is idempotent per event object, so every layer an event bubbles
/// through (item, list, pane) gets the same answer and state updates once.
class KeyRepeatThrottle {
  KeyRepeatThrottle({
    this.minInterval = const Duration(milliseconds: 100),
    this.jumpAfter = const Duration(seconds: 1),
    this.jumpSize = 5,
    this.clock = const SystemClock(),
  });

  /// Shared instance used by the TV widgets.
  static KeyRepeatThrottle instance = KeyRepeatThrottle();

  final Duration minInterval;
  final Duration jumpAfter;
  final int jumpSize;
  final Clock clock;

  LogicalKeyboardKey? _heldKey;
  DateTime? _downAt;
  DateTime? _lastMoveAt;
  bool _repeating = false;
  KeyEvent? _lastEvent;
  int _lastStep = 1;

  /// True while an arrow key is held and auto-repeating.
  bool get isRepeating => _repeating && _heldKey != null;

  /// How far a list should move for [event]: 0 drops the event, 1 is a normal
  /// move and [jumpSize] is a jump. Non-arrow keys and key-ups return 1 and 0.
  int stepFor(KeyEvent event) {
    if (identical(event, _lastEvent)) return _lastStep;
    _lastEvent = event;
    return _lastStep = _compute(event);
  }

  int _compute(KeyEvent event) {
    final key = event.logicalKey;
    if (arrowDirection(key) == null) return 1;
    final now = clock.now();
    switch (event) {
      case KeyDownEvent():
        _press(key, now);
        return 1;
      case KeyRepeatEvent():
        if (_heldKey != key) {
          _press(key, now);
          return 1;
        }
        _repeating = true;
        final last = _lastMoveAt ?? now;
        if (now.difference(last) < minInterval) return 0;
        _lastMoveAt = now;
        final held = now.difference(_downAt ?? now);
        return held >= jumpAfter ? jumpSize : 1;
      case KeyUpEvent():
        if (_heldKey == key) reset();
        return 0;
    }
    return 1;
  }

  void _press(LogicalKeyboardKey key, DateTime now) {
    _heldKey = key;
    _downAt = now;
    _lastMoveAt = now;
    _repeating = false;
  }

  /// Forgets any held key.
  void reset() {
    _heldKey = null;
    _downAt = null;
    _lastMoveAt = null;
    _repeating = false;
  }
}

/// Signature for a list's jump handler; returns true when it handled the jump.
typedef KeyJumpCallback = bool Function(
  TraversalDirection direction,
  int count,
);

/// Throttles held arrow keys for [child] and applies jump-by-N semantics.
///
/// Wrap a list or grid with it. When [KeyRepeatThrottle.stepFor] reports a
/// jump, [onJump] is called (for example to scroll a lazy list by index);
/// without it, focus moves [KeyRepeatThrottle.jumpSize] times in that
/// direction among the built items via [jumpFocus].
class KeyRepeatGuard extends StatelessWidget {
  const KeyRepeatGuard({
    super.key,
    required this.child,
    this.onJump,
    this.throttle,
  });

  final Widget child;
  final KeyJumpCallback? onJump;

  /// Defaults to [KeyRepeatThrottle.instance].
  final KeyRepeatThrottle? throttle;

  /// Moves primary focus [count] times towards [direction]; returns true if it
  /// moved at least once.
  static bool jumpFocus(TraversalDirection direction, int count) {
    var moved = false;
    for (var i = 0; i < count; i++) {
      final node = FocusManager.instance.primaryFocus;
      if (node == null || !node.focusInDirection(direction)) break;
      moved = true;
    }
    return moved;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final direction = arrowDirection(event.logicalKey);
    if (direction == null || event is KeyUpEvent) {
      (throttle ?? KeyRepeatThrottle.instance).stepFor(event);
      return KeyEventResult.ignored;
    }
    final step = (throttle ?? KeyRepeatThrottle.instance).stepFor(event);
    if (step == 0) return KeyEventResult.handled;
    if (step == 1) return KeyEventResult.ignored;
    final handled = onJump?.call(direction, step) ?? jumpFocus(direction, step);
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: _onKey,
      child: child,
    );
  }
}
