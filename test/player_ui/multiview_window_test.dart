// The split screen as a whole: window fullscreen and Escape, the app
// lifecycle, the wakelock and closing it. Synthetic data only.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/epg/epg_providers.dart';
import 'package:iptv_player/player/connection_budget.dart';
import 'package:iptv_player/player/multiview/multiview_screen.dart';
import 'package:iptv_player/player/player_providers.dart';

import 'support/multiview_harness.dart';
import 'support/player_harness.dart';

Future<void> _lifecycle(
  WidgetTester tester,
  List<AppLifecycleState> states,
) async {
  for (final s in states) {
    tester.binding.handleAppLifecycleStateChanged(s);
    await tester.pump();
  }
  await settle(tester);
}

const _toBackground = [AppLifecycleState.inactive, AppLifecycleState.hidden];
const _toForeground = [AppLifecycleState.inactive, AppLifecycleState.resumed];

void main() {
  testWidgets('F and F11 toggle the window; Escape leaves fullscreen first, '
      'then the split screen', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpSplitApp(tester, rig);
    await openSplit(tester, liveRequest(id));
    expect(rig.window, ['enter', 'enter']);

    await press(tester, LogicalKeyboardKey.keyF);
    expect(rig.window, ['enter', 'enter', 'exit']);
    await press(tester, LogicalKeyboardKey.f11);
    expect(rig.window, ['enter', 'enter', 'exit', 'enter']);

    // The bar's button says what it does.
    await mouseAt(tester, const Offset(640, 400));
    expect(find.byTooltip('Exit full screen'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.escape);
    expect(rig.window.last, 'exit');
    expect(find.byType(MultiViewScreen), findsOneWidget);
    final calls = rig.window.length;

    await press(tester, LogicalKeyboardKey.escape);
    await settleSplit(tester);
    expect(find.byType(MultiViewScreen), findsNothing);
    expect(find.byKey(launcherKey), findsOneWidget);
    expect(rig.window, hasLength(calls));
    await disposeRig(tester, rig);
  });

  testWidgets('Escape in the picker closes the picker only', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpSplitApp(tester, rig);
    await openSplit(tester, liveRequest(id));
    await press(tester, LogicalKeyboardKey.keyC);
    await openedPicker(tester);
    expect(find.byKey(pickerKey), findsOneWidget);

    await press(tester, LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byKey(pickerKey), findsNothing);
    expect(find.byType(MultiViewScreen), findsOneWidget);
    expect(rig.window, ['enter', 'enter']);
    // The keys are the split screen's again.
    await press(tester, LogicalKeyboardKey.keyL);
    expect(slot(3), findsOneWidget);
    await disposeRig(tester, rig);
  });

  testWidgets('the app lifecycle reaches every tile: live stops in the '
      'background and reopens on return', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpSplitApp(tester, rig);
    await openSplit(tester, liveRequest(id));
    await addChannel(tester, 1, 'Channel 2');
    final one = engineFor(rig, '/ch1.');
    final two = engineFor(rig, '/ch2.');
    expect(rig.wakelock.last, isTrue);

    await _lifecycle(tester, _toBackground);
    expect(one.count('stop'), 1);
    expect(two.count('stop'), 1);
    expect(rig.wakelock.last, isFalse);
    // Still theirs: they come back.
    final tiles = containerOf(tester).read(multiViewTilesProvider);
    expect(tiles, {0: id, 1: id});

    await _lifecycle(tester, _toForeground);
    expect(one.opened, hasLength(2));
    expect(two.opened, hasLength(2));
    expect(rig.wakelock.last, isTrue);
    // The sound stayed with the active tile.
    expect(two.muted, isFalse);
    expect(one.muted, isTrue);
    await disposeRig(tester, rig);
  });

  testWidgets('the wakelock stays on while any tile plays', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpSplitApp(tester, rig);
    await openSplit(tester, liveRequest(id));
    await addChannel(tester, 1, 'Channel 2');
    final turnedOn = rig.wakelock.lastIndexOf(true);
    expect(rig.wakelock.sublist(turnedOn), [true]);

    await press(tester, LogicalKeyboardKey.delete);
    expect(rig.wakelock.sublist(turnedOn), [true]);
    final holds = containerOf(tester).read(playerWakelockHoldsProvider);
    expect(holds.isOn, isTrue);

    await press(tester, LogicalKeyboardKey.arrowLeft);
    await press(tester, LogicalKeyboardKey.delete);
    expect(rig.wakelock.sublist(turnedOn), [true, false]);
    expect(holds.isOn, isFalse);
    await disposeRig(tester, rig);
  });

  testWidgets('closing stops every stream and frees every connection', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final xtream = await seedXtream(rig);
    final free = await seedFree(rig);
    await pumpSplitApp(tester, rig);
    await openSplit(tester, xtreamRequest(xtream, '501'));
    await addChannel(tester, 1, 'Free 1', sourceId: free);
    final container = containerOf(tester);
    final tiles = [engineFor(rig, '/501.'), engineFor(rig, freeUrl('f1'))];
    expect(container.read(fullscreenPlaybackProvider), isTrue);

    await mouseAt(tester, const Offset(640, 400));
    await tester.tap(find.byKey(const ValueKey('multiview-back')));
    // At once: the streams stop and the connections are free.
    await tester.pump();
    for (final e in tiles) {
      expect(e.count('stop'), 1);
    }
    expect(container.read(multiViewTilesProvider), isEmpty);
    expect(container.read(fullscreenPlaybackProvider), isFalse);
    expect(rig.window.last, 'exit');
    await settleSplit(tester);
    expect(find.byType(MultiViewScreen), findsNothing);
    expect(tiles.every((e) => e.disposed), isTrue);
    expect(rig.wakelock.last, isFalse);
    expect(container.read(connectionBudgetProvider).fits(xtream), isTrue);
    await disposeRig(tester, rig);
  });

  testWidgets('unmounted without Back, it releases everything too', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpSplitApp(tester, rig);
    await openSplit(tester, liveRequest(id));
    await addChannel(tester, 1, 'Channel 2');
    final container = containerOf(tester);
    // The route goes away under it (as when the app replaces its pages).
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.popUntil((route) => route.isFirst);
    await settleSplit(tester);
    expect(find.byType(MultiViewScreen), findsNothing);
    expect(rig.engines.created.every((e) => e.disposed), isTrue);
    expect(container.read(multiViewTilesProvider), isEmpty);
    expect(container.read(fullscreenPlaybackProvider), isFalse);
    expect(rig.window.last, 'exit');
    expect(rig.wakelock.last, isFalse);
    await disposeRig(tester, rig);
  });
}
