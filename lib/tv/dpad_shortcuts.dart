import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Page Up / Page Down outside the screens that page on their own (channel
/// list, guide, licences, Diagnostics log): moves focus about one screen of
/// items up or down ([PageFocusAction]) instead of scrolling the page away
/// from the focused item.
class PageFocusIntent extends Intent {
  const PageFocusIntent(this.direction);

  /// [TraversalDirection.up] or [TraversalDirection.down].
  final TraversalDirection direction;
}

/// Handles [PageFocusIntent]: moves focus in its direction one item at a
/// time until it has gone about the height of the nearest vertical
/// scrollable. It stops early at the last item that is built, or on the
/// first item outside the scrollable (where an arrow would have gone).
/// Without a focused item in a vertical scrollable it scrolls by a page, as
/// the default shortcut did.
class PageFocusAction extends Action<PageFocusIntent> {
  @override
  Object? invoke(PageFocusIntent intent) {
    final start = FocusManager.instance.primaryFocus;
    final context = start?.context;
    if (start == null || context == null) return null;
    final scrollable = start is FocusScopeNode
        ? null
        : Scrollable.maybeOf(context, axis: Axis.vertical);
    final box = scrollable?.context.findRenderObject();
    if (scrollable == null || box is! RenderBox || !box.hasSize) {
      return Actions.maybeInvoke(
        context,
        ScrollIntent(
          direction: intent.direction == TraversalDirection.up
              ? AxisDirection.up
              : AxisDirection.down,
          type: ScrollIncrementType.page,
        ),
      );
    }
    final view = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    final scope = scrollable.context;
    // About one screen, keeping the item at the far edge in view.
    final distance = view.height - start.rect.height;
    final from = start.rect.center.dy;
    for (var i = 0; i < 200; i++) {
      final node = FocusManager.instance.primaryFocus;
      if (node == null || !node.focusInDirection(intent.direction)) break;
      final moved = FocusManager.instance.primaryFocus;
      final movedContext = moved?.context;
      if (moved == null || movedContext == null) break;
      // Left the scrollable (a header or another pane): stop there, as an
      // arrow would.
      if (!_isInside(movedContext, scope)) break;
      if ((moved.rect.center.dy - from).abs() >= distance) break;
    }
    return null;
  }

  static bool _isInside(BuildContext context, BuildContext ancestor) {
    if (context == ancestor) return true;
    var found = false;
    context.visitAncestorElements((e) {
      found = e == ancestor;
      return !found;
    });
    return found;
  }
}

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
/// browser Back key mean Back ([BackIntent]). Page Up and Page Down move
/// focus by about a screen ([PageFocusIntent]); the default scrolls the page
/// and leaves focus behind, off screen.
Map<ShortcutActivator, Intent> get appShortcuts => {
  for (final MapEntry(:key, :value) in WidgetsApp.defaultShortcuts.entries)
    if (!_isActivation(key, value) && !_isBack(key) && !_isPage(key))
      key: value,
  const SingleActivator(LogicalKeyboardKey.pageUp): const PageFocusIntent(
    TraversalDirection.up,
  ),
  const SingleActivator(LogicalKeyboardKey.pageDown): const PageFocusIntent(
    TraversalDirection.down,
  ),
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

/// A default shortcut on Page Up or Page Down (a page scroll by default).
bool _isPage(ShortcutActivator activator) =>
    activator is SingleActivator &&
    (activator.trigger == LogicalKeyboardKey.pageUp ||
        activator.trigger == LogicalKeyboardKey.pageDown);

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
