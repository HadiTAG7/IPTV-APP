import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'dpad_shortcuts.dart';
import 'key_repeat.dart';

/// A D-pad, keyboard, mouse and touch friendly focusable item.
///
/// Built on [FocusableActionDetector]: [ActivateIntent] (OK / Enter / Select /
/// game pad A, see `appShortcuts`) calls [onSelect]. The Menu key calls
/// [onMenu]. With [onLongSelect] (or else [onMenu]) set, a held OK key fires
/// it once and a short press fires [onSelect] on key up, so remotes without
/// a Menu key reach the options too; without either, auto-repeated OK is
/// ignored.
///
/// Focus look: scale 1.0 -> [FocusTokens.scale] plus a
/// [FocusTokens.borderWidth] accent border, no blur. On keyboard focus the
/// item is scrolled to [ensureVisibleAlignment] (instantly while a key is
/// held). Held arrow keys are throttled via [KeyRepeatThrottle.instance].
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    this.onSelect,
    this.onLongSelect,
    this.onMenu,
    this.onFocusChange,
    this.autofocus = false,
    this.focusNode,
    this.enabled = true,
    this.borderRadius = Radii.mdAll,
    this.focusScale = FocusTokens.scale,
    this.ensureVisibleAlignment = 0.5,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onSelect;
  final VoidCallback? onLongSelect;
  final VoidCallback? onMenu;
  final ValueChanged<bool>? onFocusChange;
  final bool autofocus;

  /// Optional external node; otherwise one is kept in this widget's state so
  /// rebuilds keep focus.
  final FocusNode? focusNode;

  /// When false the item cannot take focus and ignores taps and clicks.
  final bool enabled;
  final BorderRadius borderRadius;
  final double focusScale;

  /// Scroll alignment applied on keyboard focus; null disables scrolling.
  final double? ensureVisibleAlignment;
  final String? semanticLabel;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  FocusNode? _ownNode;
  bool _focusHighlight = false;
  bool _hoverHighlight = false;
  bool _selectHeld = false;
  bool _longFired = false;

  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _select()),
    ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
      onInvoke: (_) => _select(),
    ),
  };

  FocusNode get _node =>
      widget.focusNode ?? (_ownNode ??= FocusNode(debugLabel: 'TvFocusable'));

  @override
  void didUpdateWidget(TvFocusable oldWidget) {
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

  Object? _select() {
    if (widget.enabled) widget.onSelect?.call();
    return null;
  }

  void _handleFocusChange(bool focused) {
    if (!focused) {
      _selectHeld = false;
      _longFired = false;
    }
    widget.onFocusChange?.call(focused);
    if (focused) _ensureVisible();
  }

  void _ensureVisible() {
    final alignment = widget.ensureVisibleAlignment;
    if (alignment == null || !mounted) return;
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
      return;
    }
    if (Scrollable.maybeOf(context) == null) return;
    final instant = KeyRepeatThrottle.instance.isRepeating;
    unawaited(
      Scrollable.ensureVisible(
        context,
        alignment: alignment,
        duration: instant ? Duration.zero : FocusTokens.scroll,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (!widget.enabled || !_node.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (arrowDirection(key) != null) {
      final step = KeyRepeatThrottle.instance.stepFor(event);
      return step == 0 && event is KeyRepeatEvent
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == menuKey) {
      final onMenu = widget.onMenu;
      if (onMenu == null) return KeyEventResult.ignored;
      if (event is KeyDownEvent) onMenu();
      return KeyEventResult.handled;
    }
    if (selectKeys.contains(key)) return _onSelectKey(event);
    return KeyEventResult.ignored;
  }

  KeyEventResult _onSelectKey(KeyEvent event) {
    // Like a touch long-press: a held OK opens the options when there is no
    // long-select action of its own.
    final onLong = widget.onLongSelect ?? widget.onMenu;
    if (onLong == null) {
      // Let the root shortcut turn the key-down into ActivateIntent, but never
      // re-activate on auto-repeat.
      return event is KeyRepeatEvent
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    switch (event) {
      case KeyDownEvent():
        _selectHeld = true;
        _longFired = false;
      case KeyRepeatEvent():
        if (_selectHeld && !_longFired) {
          _longFired = true;
          onLong();
        }
      case KeyUpEvent():
        final fire = _selectHeld && !_longFired;
        _selectHeld = false;
        _longFired = false;
        if (fire) _select();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final focused = _focusHighlight;
    final highlighted = focused || _hoverHighlight;
    final onTap = enabled ? widget.onSelect : null;
    final onLongPress = enabled ? widget.onLongSelect ?? widget.onMenu : null;

    Widget content = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: highlighted
          ? BoxDecoration(
              border: Border.all(
                color: FocusTokens.borderColor,
                width: FocusTokens.borderWidth,
              ),
              borderRadius: widget.borderRadius,
            )
          : const BoxDecoration(),
      child: TvHighlight(highlighted: highlighted, child: widget.child),
    );
    content = AnimatedScale(
      scale: focused ? widget.focusScale : 1.0,
      duration: FocusTokens.animation,
      curve: Curves.easeOut,
      child: content,
    );
    if (onTap != null || onLongPress != null) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: content,
      );
    }

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: _onKey,
      child: Semantics(
        button: widget.onSelect != null,
        enabled: widget.onSelect != null ? enabled : null,
        label: widget.semanticLabel,
        child: FocusableActionDetector(
          enabled: enabled,
          focusNode: _node,
          autofocus: widget.autofocus,
          actions: _actions,
          mouseCursor: onTap != null
              ? SystemMouseCursors.click
              : MouseCursor.defer,
          onShowFocusHighlight: (v) {
            if (v != _focusHighlight) setState(() => _focusHighlight = v);
          },
          onShowHoverHighlight: (v) {
            if (v != _hoverHighlight) setState(() => _hoverHighlight = v);
          },
          onFocusChange: _handleFocusChange,
          child: content,
        ),
      ),
    );
  }
}

/// Tells descendants of a [TvFocusable] whether it is highlighted (focused
/// with a visible focus ring, or hovered), e.g. to brighten text.
class TvHighlight extends InheritedWidget {
  const TvHighlight({
    super.key,
    required this.highlighted,
    required super.child,
  });

  final bool highlighted;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvHighlight>()?.highlighted ??
      false;

  @override
  bool updateShouldNotify(TvHighlight oldWidget) =>
      oldWidget.highlighted != highlighted;
}
