import 'package:flutter/material.dart';

import '../../app/home_shell.dart';
import '../../app/shell_phone.dart';
import '../../app/shell_tv.dart';
import 'play_request.dart';
import 'player_screen.dart';

/// Route name of the fullscreen player.
const kPlayerRouteName = '/player';

/// Opens the fullscreen player for [request]. Completes when the player is
/// closed.
///
/// When [context] is inside a home tab, the player's Guide button closes the
/// player and shows the Guide tab ([PlayerGuideScope]).
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
/// [context] is not inside a home tab (e.g. a pushed page).
VoidCallback? guideOpenerFor(BuildContext context) {
  final tv = context.findAncestorStateOfType<TvShellState>();
  if (tv != null) {
    return () {
      if (tv.mounted) tv.select(HomeTab.guide, enter: true);
    };
  }
  final phone = context.findAncestorStateOfType<PhoneShellState>();
  if (phone != null) {
    return () {
      if (phone.mounted) phone.select(HomeTab.guide);
    };
  }
  return null;
}

/// Tells the player how to reach the Guide tab after it closes.
class PlayerGuideScope extends InheritedWidget {
  const PlayerGuideScope({
    super.key,
    required this.openGuide,
    required super.child,
  });

  /// Shows the Guide tab; null hides the player's Guide button.
  final VoidCallback? openGuide;

  static VoidCallback? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PlayerGuideScope>()?.openGuide;

  @override
  bool updateShouldNotify(PlayerGuideScope oldWidget) =>
      oldWidget.openGuide != openGuide;
}
