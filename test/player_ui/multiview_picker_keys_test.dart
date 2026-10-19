// The split screen's channel picker with the keyboard: the source row
// above the lists. Synthetic data only.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/multiview_harness.dart';
import 'support/player_harness.dart';

bool _sourceFocused(int id) => focusedIn(ValueKey('multiview-source-$id'));

void main() {
  testWidgets('Up from the top of the categories reaches the sources; a '
      "source's channels take focus and OK plays one", (tester) async {
    final rig = PlayerRig()..autoPlay();
    final home = await seedLive(rig);
    final free = await seedFree(rig);
    await pumpSplitApp(tester, rig);
    await openSplit(tester, liveRequest(home));

    await press(tester, LogicalKeyboardKey.keyC);
    await openedPicker(tester);
    expect(focusedIn(const ValueKey('channel-row-0')), isTrue);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedIn(const ValueKey('live-category-cat:news')), isTrue);
    for (var i = 0; i < 8 && !_sourceFocused(home); i++) {
      await press(tester, LogicalKeyboardKey.arrowUp);
    }
    expect(_sourceFocused(home), isTrue);
    // Down goes back to the lists.
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedIn(pickerKey), isTrue);
    expect(_sourceFocused(home), isFalse);
    for (var i = 0; i < 8 && !_sourceFocused(home); i++) {
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowUp);
    }
    expect(_sourceFocused(home), isTrue);

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(_sourceFocused(free), isTrue);
    await press(tester, LogicalKeyboardKey.enter);
    await openedPicker(tester);
    expect(
      find.descendant(of: find.byKey(pickerKey), matching: find.text('Free 1')),
      findsOneWidget,
    );
    expect(focusedIn(const ValueKey('channel-row-0')), isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.enter);
    await settleSplit(tester);

    expect(find.byKey(pickerKey), findsNothing);
    expect(rig.openedUrls.last, freeUrl('f2'));
    expect(inSlot(0, find.text('Free 2')), findsOneWidget);
    // The keys are the split screen's again.
    await press(tester, LogicalKeyboardKey.keyL);
    expect(slot(3), findsOneWidget);
    await disposeRig(tester, rig);
  });
}
