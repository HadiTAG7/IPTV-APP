// A split-screen tile whose stream fails: it frees its connection, and
// Retry asks the connection budget again. Synthetic data only.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/player/connection_budget.dart';

import 'support/multiview_harness.dart';
import 'support/player_harness.dart';

void main() {
  testWidgets('a failed tile frees its connection; Retry is refused while '
      'another tile uses it, and plays once it is free', (tester) async {
    final rig = PlayerRig();
    var failing = false;
    rig.engines.onCreate = (e) => e.onOpen = (e, r) {
      if (failing && r.url.contains('/501.')) {
        e.emitError('HTTP error 500 Internal Server Error', httpStatus: 500);
      } else {
        e.emitFirstFrame();
      }
    };
    final xtream = await seedXtream(rig);
    await pumpSplitApp(tester, rig);
    final l10n = await AppLocalizations.delegate.load(en);
    await openPlayerFor(tester, xtreamRequest(xtream, '501'));
    failing = true;
    await press(tester, LogicalKeyboardKey.keyS);
    await settleSplit(tester);

    expect(
      inSlot(0, find.byKey(const ValueKey('multiview-failure'))),
      findsOneWidget,
    );
    expect(inSlot(0, find.text(l10n.playerPlaybackFailed)), findsOneWidget);
    final container = containerOf(tester);
    expect(container.read(multiViewTilesProvider), isEmpty);

    // Its connection is free: tile 2 may use it.
    await addChannel(tester, 1, 'Panel Sport');
    expect(engineFor(rig, '/502.').opened, hasLength(1));
    expect(container.read(multiViewTilesProvider), {1: xtream});

    failing = false;
    final tile = engineFor(rig, '/501.');
    final opens = tile.opened.length;
    await tester.tap(inSlot(0, find.byKey(const ValueKey('multiview-retry'))));
    await settle(tester);
    expect(find.text(l10n.multiviewInUseTile('Panel', 2)), findsOneWidget);
    expect(tile.opened, hasLength(opens));
    await tester.tap(find.byKey(const ValueKey('multiview-in-use-ok')));
    await settle(tester);
    expect(isActive(0), isTrue);

    // Tile 2 removed: Enter on the failed tile retries it.
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.delete);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await press(tester, LogicalKeyboardKey.enter);
    await settleSplit(tester);
    expect(tile.opened, hasLength(opens + 1));
    expect(
      inSlot(0, find.byKey(const ValueKey('multiview-failure'))),
      findsNothing,
    );
    expect(container.read(multiViewTilesProvider), {0: xtream});
    await disposeRig(tester, rig);
  });
}
