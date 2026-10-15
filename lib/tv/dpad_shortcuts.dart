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

/// Back from a keyboard or desktop remote (Escape, the browser Back key).
///
/// Not [DismissIntent]: every route defines a DismissIntent action, disabled
/// on pages, and the nearest action wins even when it is disabled, so the
/// key would never reach the app's Back action. The app handles this intent
/// above the navigator (`AppFrame`) with `maybePop`, so each route's
/// `PopScope` still decides.
class BackIntent extends Intent {
  const BackIntent();
}

/// Keys that mean Back on keyboards and desktop remotes. A TV remote's Back
/// key is the system back button, not a key event.
final Set<LogicalKeyboardKey> backKeys = {
  LogicalKeyboardKey.escape,
  LogicalKeyboardKey.browserBack,
};

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
/// again or confirm a dialog that the first press opened. Escape and the
/// browser Back key mean Back ([BackIntent]).
Map<ShortcutActivator, Intent> get appShortcuts => {
  for (final MapEntry(:key, :value) in WidgetsApp.defaultShortcuts.entries)
    if (!_isActivation(key, value) && !_isBack(key)) key: value,
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
  for (final key in backKeys)
    SingleActivator(key, includeRepeats: false): const BackIntent(),
};

/// A default activation shortcut. [SingleActivator] has no value equality,
/// so these are removed rather than overridden.
bool _isActivation(ShortcutActivator activator, Intent intent) =>
    activator is SingleActivator &&
    _activationKeys.contains(activator.trigger) &&
    (intent is ActivateIntent || intent is ButtonActivateIntent);

/// A default shortcut on a Back key (Escape is DismissIntent by default).
bool _isBack(ShortcutActivator activator) =>
    activator is SingleActivator && backKeys.contains(activator.trigger);

/// On TV the focus ring must show from the first frame, before any key press;
/// elsewhere Flutter switches between touch and keyboard highlighting.
void applyFocusHighlightStrategy({required bool tv}) {
  FocusManager.instance.highlightStrategy = tv
      ? FocusHighlightStrategy.alwaysTraditional
      : FocusHighlightStrategy.automatic;
}
