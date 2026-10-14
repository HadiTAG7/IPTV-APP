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

/// Keys that activate the focused control: [selectKeys] plus Space.
final Set<LogicalKeyboardKey> _activationKeys = {
  ...selectKeys,
  LogicalKeyboardKey.space,
};

/// Root shortcuts for `MaterialApp.shortcuts` on every platform.
///
/// Arrows always move focus (web would otherwise scroll) and every select
/// key activates, so desktop and tests behave like a TV remote. Activation
/// ignores auto-repeat: a held OK fires once, so it cannot fire a button
/// again or confirm a dialog that the first press opened.
Map<ShortcutActivator, Intent> get appShortcuts => {
  for (final MapEntry(:key, :value) in WidgetsApp.defaultShortcuts.entries)
    if (!_isActivation(key, value)) key: value,
  const SingleActivator(LogicalKeyboardKey.arrowUp):
      const DirectionalFocusIntent(TraversalDirection.up),
  const SingleActivator(LogicalKeyboardKey.arrowDown):
      const DirectionalFocusIntent(TraversalDirection.down),
  const SingleActivator(LogicalKeyboardKey.arrowLeft):
      const DirectionalFocusIntent(TraversalDirection.left),
  const SingleActivator(LogicalKeyboardKey.arrowRight):
      const DirectionalFocusIntent(TraversalDirection.right),
  for (final key in _activationKeys)
    SingleActivator(key, includeRepeats: false): const ActivateIntent(),
};

/// A default activation shortcut. [SingleActivator] has no value equality,
/// so these are removed rather than overridden.
bool _isActivation(ShortcutActivator activator, Intent intent) =>
    activator is SingleActivator &&
    _activationKeys.contains(activator.trigger) &&
    (intent is ActivateIntent || intent is ButtonActivateIntent);

/// On TV the focus ring must show from the first frame, before any key press;
/// elsewhere Flutter switches between touch and keyboard highlighting.
void applyFocusHighlightStrategy({required bool tv}) {
  FocusManager.instance.highlightStrategy = tv
      ? FocusHighlightStrategy.alwaysTraditional
      : FocusHighlightStrategy.automatic;
}
