import 'package:flutter/material.dart';

import '../../app/home_shell.dart';
import 'play_request.dart';
import 'player_screen.dart';

/// Route name of the fullscreen player.
const kPlayerRouteName = '/player';

/// Opens the fullscreen player for [request]. Completes when the player is
/// closed.
///
/// When [context] is inside a home tab, the player's Guide button closes the
/// player and shows the Guide tab ([PlayerGuideScope]); elsewhere it just
/// closes the player.
Future<void> openPlayer(BuildContext context, PlayRequest request) {
  final openGuide = guideOpenerFor(context);
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: kPlayerRouteName, arguments: request),
      fullscreenDialog: true,
      builder: (_) => PlayerGuideScope(
        openGuide: openGuide,
        child: PlayerScreen(request: request),
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
