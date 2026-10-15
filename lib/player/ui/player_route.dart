import 'package:flutter/material.dart';

import 'play_request.dart';
import 'player_screen.dart';

/// Route name of the fullscreen player.
const kPlayerRouteName = '/player';

/// Opens the fullscreen player for [request]. Completes when the player is
/// closed.
Future<void> openPlayer(BuildContext context, PlayRequest request) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: kPlayerRouteName, arguments: request),
        fullscreenDialog: true,
        builder: (_) => PlayerScreen(request: request),
      ),
    );
