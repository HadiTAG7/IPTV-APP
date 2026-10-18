// On Windows and phones "Add to list…" is reachable from the player by
// click or tap (there is no Menu key).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';

import 'support/player_harness.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('Add to list is reachable by click or tap ($platform)', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(en);
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig, tv: false, platform: platform);
      await openPlayerFor(tester, liveRequest(id));
      await tester.tapAt(
        platform == TargetPlatform.windows
            ? const Offset(640, 360)
            : const Offset(195, 400),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(find.byKey(const ValueKey('player-osd')), findsOneWidget);
      final button = find.byKey(const ValueKey('player-osd-addToList'));
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await settle(tester);
      await tester.tap(button);
      await settle(tester);
      expect(find.text(l10n.liveAddToListTitle), findsOneWidget);
      await disposeRig(tester, rig);
    });
  }
}
