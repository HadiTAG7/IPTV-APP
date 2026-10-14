import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keys that act as "OK" on remotes, keyboards and game pads.
final Set<LogicalKeyboardKey> selectKeys = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
};

/// The remote's Menu key (Android `KEYCODE_MENU`) and the keyboard menu key.
const LogicalKeyboardKey menuKey = LogicalKeyboardKey.contextMenu;

/// Root shortcuts for `MaterialApp.shortcuts` on every platform.
///
/// Arrows always move focus (web would otherwise scroll) and every select
/// key activates, so desktop and tests behave like a TV remote.
Map<ShortcutActivator, Intent> get appShortcuts => {
  ...WidgetsApp.defaultShortcuts,
  const SingleActivator(LogicalKeyboardKey.arrowUp):
      const DirectionalFocusIntent(TraversalDirection.up),
  const SingleActivator(LogicalKeyboardKey.arrowDown):
      const DirectionalFocusIntent(TraversalDirection.down),
  const SingleActivator(LogicalKeyboardKey.arrowLeft):
      const DirectionalFocusIntent(TraversalDirection.left),
  const SingleActivator(LogicalKeyboardKey.arrowRight):
      const DirectionalFocusIntent(TraversalDirection.right),
  for (final key in selectKeys) SingleActivator(key): const ActivateIntent(),
};

/// On TV the focus ring must show from the first frame, before any key press;
/// elsewhere Flutter switches between touch and keyboard highlighting.
void applyFocusHighlightStrategy({required bool tv}) {
  FocusManager.instance.highlightStrategy = tv
      ? FocusHighlightStrategy.alwaysTraditional
      : FocusHighlightStrategy.automatic;
}
