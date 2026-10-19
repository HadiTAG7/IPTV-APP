import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_shell.dart';
import '../../l10n/gen/app_localizations.dart';
import '../connection_budget.dart';
import '../detach/detached_windows.dart';
import 'play_request.dart';
import 'player_dialogs.dart';
import 'player_screen.dart';

/// Route name of the fullscreen player.
const kPlayerRouteName = '/player';

/// How long the player takes to fade in and out.
const kPlayerFadeIn = Duration(milliseconds: 180);
const kPlayerFadeOut = Duration(milliseconds: 120);

/// Opens the fullscreen player for [request]. Completes when the player is
/// closed.
///
/// The player fades in and out quickly: the page zoom of other routes
/// looked poor over a black video surface while the desktop window enters
/// or leaves fullscreen at the same time.
///
/// When [context] is inside a home tab, the player's Guide button closes the
/// player and shows the Guide tab ([PlayerGuideScope]); elsewhere it just
/// closes the player.
///
/// A live channel whose source has no connection left because detached
/// windows use them ([connectionBudgetProvider]) asks first: play it in the
/// (newest) window instead, close that window and play here, or cancel.
Future<void> openPlayer(BuildContext context, PlayRequest request) {
  if (request.isLive) {
    final container = ProviderScope.containerOf(context, listen: false);
    final window = _windowInTheWay(container, request);
    if (window != null) {
      return _offerWindow(context, container, request, window);
    }
  }
  return _pushPlayer(context, request);
}

/// The newest detached window playing from [request]'s source when that
/// source has no connection left for the player; else null.
DetachedViewer? _windowInTheWay(
  ProviderContainer container,
  PlayRequest request,
) {
  final windows = container.read(detachedWindowsProvider);
  if (windows.isEmpty || connectionFits(container, request.sourceId)) {
    return null;
  }
  final ids = container
      .read(connectionBudgetProvider)
      .viewersOn(request.sourceId);
  return windows.where((w) => ids.contains(w.id)).lastOrNull;
}

/// What to do with a channel whose source's connections are all in
/// detached windows.
enum _WindowChoice { playInWindow, closeWindow }

Future<void> _offerWindow(
  BuildContext context,
  ProviderContainer container,
  PlayRequest request,
  DetachedViewer window,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final windows = container.read(detachedWindowsProvider.notifier);
  final choice = await showPlayerChoiceDialog<_WindowChoice>(
    context,
    title: l10n.detachInUseTitle(
      window.title.isEmpty ? l10n.playerDetach : window.title,
    ),
    message: l10n.detachInUseMessage,
    choices: [
      PlayerChoice(
        value: _WindowChoice.playInWindow,
        label: l10n.detachPlayInWindow,
        icon: Icons.open_in_new,
      ),
      PlayerChoice(
        value: _WindowChoice.closeWindow,
        label: l10n.detachCloseWindow,
        icon: Icons.close,
      ),
    ],
  );
  switch (choice) {
    case null:
      return;
    case _WindowChoice.playInWindow:
      if (!await windows.playInWindow(window.id, request)) {
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(l10n.detachPlayInWindowFailed)),
          );
      }
    case _WindowChoice.closeWindow:
      // Its connection is free once it has stopped and exited.
      await windows.close(window.id);
      if (!context.mounted) return;
      await _pushPlayer(context, request);
  }
}

Future<void> _pushPlayer(BuildContext context, PlayRequest request) {
  final openGuide = guideOpenerFor(context);
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      settings: RouteSettings(name: kPlayerRouteName, arguments: request),
      fullscreenDialog: true,
      transitionDuration: kPlayerFadeIn,
      reverseTransitionDuration: kPlayerFadeOut,
      pageBuilder: (_, _, _) => PlayerGuideScope(
        openGuide: openGuide,
        child: PlayerScreen(request: request),
      ),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    ),
  );
}

/// Shows the Guide tab of the home shell around [context], or null when
/// [context] is not inside a home tab (e.g. a pushed page). It goes through
/// [HomeShellState.showTab], so it still works when the layout changed while
/// the player was open (a phone held in landscape swaps in the large
/// layout).
VoidCallback? guideOpenerFor(BuildContext context) {
  final shell = HomeShell.maybeOf(context);
  if (shell == null) return null;
  return () => shell.showTab(HomeTab.guide, enter: true);
}

/// Tells the player how to reach the Guide tab after it closes.
class PlayerGuideScope extends InheritedWidget {
  const PlayerGuideScope({
    super.key,
    required this.openGuide,
    required super.child,
  });

  /// Shows the Guide tab; null when the player was not opened from a home
  /// tab (its Guide button then just closes the player).
  final VoidCallback? openGuide;

  static VoidCallback? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PlayerGuideScope>()?.openGuide;

  @override
  bool updateShouldNotify(PlayerGuideScope oldWidget) =>
      oldWidget.openGuide != openGuide;
}
