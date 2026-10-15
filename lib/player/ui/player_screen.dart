import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import 'play_request.dart';

/// Fullscreen player.
///
/// Placeholder until the player UI is built: shows the title on black.
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key, required this.request});

  final PlayRequest request;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: Center(
        child: Text(
          request.displayTitle ?? l10n.playerBuffering,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
  }
}
