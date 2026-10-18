// With Stats on, the on-screen Back button still takes clicks.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/ui/player_screen.dart';

import 'support/player_harness.dart';

void main() {
  forLocales((locale) {
    for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
      testWidgets('Back works with Stats on ($platform, '
          '${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedLive(rig);
        await pumpPlayerApp(
          tester,
          rig,
          tv: false,
          locale: locale,
          platform: platform,
        );
        await openPlayerFor(tester, liveRequest(id));
        await tester.tapAt(
          platform == TargetPlatform.windows
              ? const Offset(640, 360)
              : const Offset(195, 400),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await settle(tester);
        const stats = ValueKey('player-osd-stats');
        await tester.ensureVisible(find.byKey(stats));
        await settle(tester);
        await tester.tap(find.byKey(stats));
        await settle(tester);
        expect(find.byKey(const ValueKey('player-osd')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('player-osd-back')));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerScreen), findsNothing);
        await disposeRig(tester, rig);
      });
    }
  });
}
