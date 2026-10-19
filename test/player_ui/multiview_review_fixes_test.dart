// The split screen's review fixes: the sound of a tile emptied while
// muted, the keyboard that never leaves the split screen (nor acts on it
// under a message) or the desktop player (its S key), double clicks on
// things that go away (the "no free connection" message too), a maximized
// tile (its sound icon, the way back to the grid, the layout), the
// picker's source row, Separate window on a failed tile or on one still
// opening (its connection stays counted), and the refusal of a
// subscription with more than one connection. Synthetic data only.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/player/connection_budget.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/multiview/multiview_screen.dart';
import 'package:iptv_player/sources/models.dart';

import '../support/fake_engine.dart';
import 'support/fake_detached_windows.dart';
import 'support/multiview_harness.dart';
import 'support/player_harness.dart';

const _inUse = ValueKey('multiview-in-use');
const _ok = ValueKey('multiview-in-use-ok');
const _showAll = ValueKey('multiview-show-all');

/// Two clicks at [at], 80 ms apart, then waits past the double-click
/// timeout.
Future<void> _doubleClickAt(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 80));
  await tester.tapAt(at);
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
  await settleSplit(tester);
}

/// Tile 1 (Xtream 501, one connection) failed and tile 2 plays Xtream 502
/// (active): Retry on tile 1 is refused.
Future<PlayerRig> _failedTileAndSport(WidgetTester tester) async {
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
  await openPlayerFor(tester, xtreamRequest(xtream, '501'));
  failing = true;
  await press(tester, LogicalKeyboardKey.keyS);
  await settleSplit(tester);
  await addChannel(tester, 1, 'Panel Sport');
  expect(isActive(1), isTrue);
  return rig;
}

/// Clicks Retry on the failed tile 1: the refusal opens, tile 1 is active
/// and tile 2 ([sport]) silent. Waits until the message takes clicks.
Future<void> _refusedRetry(WidgetTester tester, FakeEngine sport) async {
  await tester.tap(inSlot(0, find.byKey(const ValueKey('multiview-retry'))));
  await settle(tester);
  expect(find.byKey(_inUse), findsOneWidget);
  expect(isActive(0), isTrue);
  expect(sport.muted, isTrue);
  await tester.pump(kDoubleTapTimeout);
}

void main() {
  group('a muted active tile emptied and filled again', () {
    testWidgets('M, Delete, then a new channel in the same tile: it is '
        'heard', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpSplitApp(tester, rig);
      await openSplit(tester, liveRequest(id));
      final one = engineFor(rig, '/ch1.');
      expect(one.muted, isFalse);

      await press(tester, LogicalKeyboardKey.keyM);
      expect(one.muted, isTrue);
      await press(tester, LogicalKeyboardKey.delete);
      expect(one.disposed, isTrue);
      expect(isActive(0), isTrue);

      // Enter on the empty active tile opens the picker.
      await press(tester, LogicalKeyboardKey.enter);
      await openedPicker(tester);
      await pickChannel(tester, 'Channel 2');

      final two = engineFor(rig, '/ch2.');
      expect(isActive(0), isTrue);
      expect(
        inSlot(0, find.byKey(const ValueKey('multiview-audible'))),
        findsOneWidget,
      );
      // The only tile, active and not muted: it must be heard.
      expect(two.muted, isFalse);
      expect(two.lite, isFalse);
      await disposeRig(tester, rig);
    });

    testWidgets('M, D, then a new channel in the same tile: it is heard', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      final windows = await pumpSplitApp(tester, rig);
      await openSplit(tester, liveRequest(id));
      final one = engineFor(rig, '/ch1.');

      await press(tester, LogicalKeyboardKey.keyM);
      expect(one.muted, isTrue);
      await press(tester, LogicalKeyboardKey.keyD);
      await settleSplit(tester);
      expect(windows.detached, hasLength(1));
      expect(one.disposed, isTrue);

      await press(tester, LogicalKeyboardKey.enter);
      await openedPicker(tester);
      await pickChannel(tester, 'Channel 2');

      final two = engineFor(rig, '/ch2.');
      expect(
        inSlot(0, find.byKey(const ValueKey('multiview-audible'))),
        findsOneWidget,
      );
      expect(two.muted, isFalse);
      await disposeRig(tester, rig);
    });
  });

  group('the keyboard stays with the split screen', () {
    testWidgets('Tab and Shift+Tab: L still switches the layout', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpSplitApp(tester, rig);
      await openSplit(tester, liveRequest(id));
      expect(focusLabel, 'multiview');

      await press(tester, LogicalKeyboardKey.tab);
      expect(focusLabel, 'multiview');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await press(tester, LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(focusLabel, 'multiview');
      await press(tester, LogicalKeyboardKey.keyL);
      expect(slot(3), findsOneWidget);
      await disposeRig(tester, rig);
    });

    testWidgets('after Tab, Escape in fullscreen leaves fullscreen only; '
        'the split screen and its streams stay', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpSplitApp(tester, rig);
      await openSplit(tester, liveRequest(id));
      expect(rig.window, ['enter', 'enter']);
      final engine = engineFor(rig, '/ch1.');

      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.escape);
      await settleSplit(tester);
      expect(rig.window.last, 'exit');
      expect(find.byType(MultiViewScreen), findsOneWidget);
      expect(engine.count('stop'), 0);
      await disposeRig(tester, rig);
    });

    testWidgets('focus taken away: a click on a tile gives the keys back', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpSplitApp(tester, rig);
      await openSplit(tester, liveRequest(id));
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();
      expect(focusLabel, isNot('multiview'));

      await click(tester, slot(0));
      expect(focusLabel, 'multiview');
      await press(tester, LogicalKeyboardKey.keyL);
      expect(slot(3), findsOneWidget);
      await disposeRig(tester, rig);
    });

    testWidgets('keys before a message over it took the focus act on '
        'nothing: no tile stops and the split screen still works', (
      tester,
    ) async {
      final rig = await _failedTileAndSport(tester);
      final sport = engineFor(rig, '/502.');
      // Out of window fullscreen: Escape on the grid would leave.
      await press(tester, LogicalKeyboardKey.escape);
      expect(rig.window.last, 'exit');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(isActive(0), isTrue);

      // Enter retries tile 1, refused: the message opens. Escape and Enter
      // come before its first frame took the focus.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(focusLabel, 'multiview');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleSplit(tester);
      expect(find.byType(MultiViewScreen), findsOneWidget);
      expect(find.byKey(_inUse), findsOneWidget);
      expect(sport.count('stop'), 0);

      // The message has the keys now: Escape closes it, and only it.
      await press(tester, LogicalKeyboardKey.escape);
      await settleSplit(tester);
      expect(find.byKey(_inUse), findsNothing);
      expect(find.byType(MultiViewScreen), findsOneWidget);
      expect(focusLabel, 'multiview');
      await press(tester, LogicalKeyboardKey.keyL);
      expect(slot(3), findsOneWidget);
      expect(sport.count('stop'), 0);
      await disposeRig(tester, rig);
    });
  });

  group('the keyboard stays with the desktop player (its S key)', () {
    testWidgets('Tab and Shift+Tab: S still opens the split screen', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpSplitApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      expect(focusLabel, 'player');

      await press(tester, LogicalKeyboardKey.tab);
      expect(focusLabel, 'player');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await press(tester, LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(focusLabel, 'player');
      await press(tester, LogicalKeyboardKey.keyS);
      await settleSplit(tester);
      expect(find.byType(MultiViewScreen), findsOneWidget);
      await disposeRig(tester, rig);
    });

    testWidgets('after Tab, Escape in fullscreen leaves fullscreen only; '
        'the player stays', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpSplitApp(tester, rig);
      final closed = await openPlayerFor(tester, liveRequest(id));
      var done = false;
      ignore(closed.then((_) => done = true));
      expect(rig.window, ['enter']);

      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.escape);
      expect(rig.window, ['enter', 'exit']);
      expect(done, isFalse);
      expect(rig.engines.created.single.count('stop'), 0);
      await disposeRig(tester, rig);
    });

    testWidgets('focus taken away: a click on the video gives the keys back', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpSplitApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();
      expect(focusLabel, isNot('player'));

      await click(tester, find.byKey(const ValueKey('player-gestures')));
      expect(focusLabel, 'player');
      await press(tester, LogicalKeyboardKey.keyS);
      await settleSplit(tester);
      expect(find.byType(MultiViewScreen), findsOneWidget);
      await disposeRig(tester, rig);
    });

    testWidgets('the OSD opened with a key: Tab still moves between its '
        'buttons', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpSplitApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusLabel, 'player:osd-first');

      await press(tester, LogicalKeyboardKey.tab);
      expect(focusLabel, isNot('player:osd-first'));
      expect(focusedIn(const ValueKey('player-osd')), isTrue);
      await disposeRig(tester, rig);
    });
  });

  group('the second click of a double click on something that goes away', () {
    testWidgets('a channel in the picker: the new tile stays active and '
        'heard', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final xtream = await seedXtream(rig);
      await seedFree(rig);
      await pumpSplitApp(tester, rig);
      await openSplit(tester, xtreamRequest(xtream, '501'));
      final one = engineFor(rig, '/501.');
      await tester.tap(inSlot(1, find.byKey(const ValueKey('multiview-add'))));
      await openedPicker(tester);
      // The picker opened on the free list (the subscription's only
      // connection is in tile 1); "Free 2" is over tile 1.
      final at = tester.getCenter(
        find.descendant(
          of: find.byKey(pickerKey),
          matching: find.text('Free 2'),
        ),
      );
      expect(tester.getRect(slot(0)).contains(at), isTrue);

      await _doubleClickAt(tester, at);

      final two = engineFor(rig, freeUrl('f2'));
      expect(isActive(1), isTrue);
      expect(two.muted, isFalse);
      expect(one.muted, isTrue);
      // Clicks there work again afterwards.
      await click(tester, slot(0));
      expect(isActive(0), isTrue);
      await disposeRig(tester, rig);
    });

    testWidgets('Remove on a tile that is not heard: the sound stays where '
        'it was', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpSplitApp(tester, rig);
      await openSplit(tester, liveRequest(id));
      await addChannel(tester, 1, 'Channel 2');
      final one = engineFor(rig, '/ch1.');
      await click(tester, slot(0));
      expect(isActive(0), isTrue);
      expect(one.muted, isFalse);

      final mouse = await mouseAt(tester, tester.getCenter(slot(1)));
      final remove = inSlot(1, find.byKey(const ValueKey('multiview-remove')));
      expect(remove, findsOneWidget);
      final at = tester.getCenter(remove);
      await mouse.moveTo(at);
      await tester.pump();
      await mouse.down(at);
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 80));
      await mouse.down(at);
      await mouse.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await settle(tester);

      expect(inSlot(1, find.text('Channel 2')), findsNothing);
      expect(isActive(0), isTrue);
      expect(one.muted, isFalse);
      await disposeRig(tester, rig);
    });

    testWidgets('Delete (a key) leaves no guard: a click right after it '
        'works', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpSplitApp(tester, rig);
      await openSplit(tester, liveRequest(id));
      await press(tester, LogicalKeyboardKey.delete);
      expect(engineFor(rig, '/ch1.').disposed, isTrue);
      // Within kDoubleTapTimeout of the key.
      await tester.tap(inSlot(0, find.byKey(const ValueKey('multiview-add'))));
      await openedPicker(tester);
      expect(find.byKey(pickerKey), findsOneWidget);
      await disposeRig(tester, rig);
    });

    testWidgets('a channel of a one-connection subscription in use: the '
        'message stays until it is read', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final xtream = await seedXtream(rig);
      await seedFree(rig);
      await pumpSplitApp(tester, rig);
      await openSplit(tester, xtreamRequest(xtream, '501'));
      await tester.tap(inSlot(1, find.byKey(const ValueKey('multiview-add'))));
      await openedPicker(tester);
      await tester.tap(find.byKey(ValueKey('multiview-source-$xtream')));
      await openedPicker(tester);
      final at = tester.getCenter(
        find.descendant(
          of: find.byKey(pickerKey),
          matching: find.text('Panel Sport'),
        ),
      );

      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byKey(_inUse), findsOneWidget);
      await tester.tapAt(at);
      await settle(tester);

      expect(find.byKey(_inUse), findsOneWidget);
      expect(rig.openedUrls.where((u) => u.contains('/502.')), isEmpty);
      // Read: a click beside it still closes it.
      await tester.pump(kDoubleTapTimeout);
      await tester.tapAt(at);
      await settle(tester);
      expect(find.byKey(_inUse), findsNothing);
      expect(find.byKey(pickerKey), findsOneWidget);
      await disposeRig(tester, rig);
    });

    forLocales((locale) {
      testWidgets('OK of the "no free connection" message over the picker: '
          'the picker stays open (${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final xtream = await seedXtream(rig);
        final free = await seedFree(rig);
        await pumpSplitApp(tester, rig, locale: locale);
        await openSplit(tester, xtreamRequest(xtream, '501'));
        await tester.tap(
          inSlot(1, find.byKey(const ValueKey('multiview-add'))),
        );
        await openedPicker(tester);
        await tester.tap(find.byKey(ValueKey('multiview-source-$xtream')));
        await openedPicker(tester);
        await tester.tap(
          find.descendant(
            of: find.byKey(pickerKey),
            matching: find.text('Panel Sport'),
          ),
        );
        await settle(tester);
        expect(find.byKey(_inUse), findsOneWidget);
        await tester.pump(kDoubleTapTimeout);
        // OK is beside the picker, over its outside area (which closes it).
        final ok = tester.getCenter(find.byKey(_ok));
        expect(tester.getRect(find.byKey(pickerKey)).contains(ok), isFalse);

        await _doubleClickAt(tester, ok);
        expect(find.byKey(_inUse), findsNothing);
        // Open for another channel, as the message says.
        await pickChannel(tester, 'Free 2', sourceId: free);
        expect(find.byKey(pickerKey), findsNothing);
        expect(isActive(1), isTrue);
        expect(engineFor(rig, freeUrl('f2')).muted, isFalse);
        await disposeRig(tester, rig);
      });
    });

    testWidgets('OK of the refused Retry message, or beside it: the failed '
        'tile stays active and the other one silent', (tester) async {
      final rig = await _failedTileAndSport(tester);
      final sport = engineFor(rig, '/502.');
      await _refusedRetry(tester, sport);
      // OK is over tile 2.
      final ok = tester.getCenter(find.byKey(_ok));
      expect(tester.getRect(slot(1)).contains(ok), isTrue);

      await _doubleClickAt(tester, ok);
      expect(find.byKey(_inUse), findsNothing);
      expect(isActive(0), isTrue);
      expect(isActive(1), isFalse);
      expect(sport.muted, isTrue);

      await _refusedRetry(tester, sport);
      await _doubleClickAt(tester, const Offset(1200, 650));
      expect(find.byKey(_inUse), findsNothing);
      expect(isActive(0), isTrue);
      expect(sport.muted, isTrue);
      await disposeRig(tester, rig);
    });

    testWidgets('the message closed with Enter after a click on it leaves no '
        'guard: a click right after it works', (tester) async {
      final rig = await _failedTileAndSport(tester);
      final sport = engineFor(rig, '/502.');
      await _refusedRetry(tester, sport);
      // A click on the message (not on OK), over tile 2, leaves it open.
      final box = tester.getRect(
        find
            .descendant(of: find.byKey(_inUse), matching: find.byType(Material))
            .first,
      );
      final at = Offset(box.right - 8, box.center.dy);
      expect(tester.getRect(slot(1)).contains(at), isTrue);
      await tester.tapAt(at);
      await settle(tester);
      expect(find.byKey(_inUse), findsOneWidget);

      await press(tester, LogicalKeyboardKey.enter);
      expect(find.byKey(_inUse), findsNothing);
      await tester.tapAt(at);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await settle(tester);
      expect(isActive(1), isTrue);
      expect(sport.muted, isFalse);
      await disposeRig(tester, rig);
    });
  });

  group('a maximized tile', () {
    testWidgets('M shows the muted icon, as in the grid', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpSplitApp(tester, rig);
      await openSplit(tester, liveRequest(id));
      await addChannel(tester, 1, 'Channel 2');
      final two = engineFor(rig, '/ch2.');

      await doubleTap(tester, slot(1));
      expect(slot(0), findsNothing);
      expect(
        inSlot(1, find.byKey(const ValueKey('multiview-audible'))),
        findsOneWidget,
      );
      await press(tester, LogicalKeyboardKey.keyM);
      expect(two.muted, isTrue);
      expect(
        inSlot(1, find.byKey(const ValueKey('multiview-muted'))),
        findsOneWidget,
      );
      await disposeRig(tester, rig);
    });

    testWidgets('Escape shows the grid first, then leaves fullscreen, then '
        'the split screen; the hidden tiles keep playing', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpSplitApp(tester, rig);
      await openSplit(tester, liveRequest(id));
      await addChannel(tester, 1, 'Channel 2');
      final one = engineFor(rig, '/ch1.');
      final two = engineFor(rig, '/ch2.');
      expect(rig.window, ['enter', 'enter']);

      await doubleTap(tester, slot(1));
      expect(slot(0), findsNothing);
      await press(tester, LogicalKeyboardKey.escape);
      expect(slot(0), findsOneWidget);
      expect(slot(1), findsOneWidget);
      expect(isActive(1), isTrue);
      expect(rig.window, ['enter', 'enter']);
      expect(one.count('stop'), 0);
      expect(two.count('stop'), 0);

      await press(tester, LogicalKeyboardKey.escape);
      expect(rig.window, ['enter', 'enter', 'exit']);
      expect(find.byType(MultiViewScreen), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      await settleSplit(tester);
      expect(find.byType(MultiViewScreen), findsNothing);
      await disposeRig(tester, rig);
    });

    testWidgets("the bar's Back shows the grid again", (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpSplitApp(tester, rig);
      await openSplit(tester, liveRequest(id));
      await addChannel(tester, 1, 'Channel 2');
      final one = engineFor(rig, '/ch1.');
      await doubleTap(tester, slot(1));
      await mouseAt(tester, const Offset(640, 400));
      expect(find.byKey(const ValueKey('multiview-bar')), findsOneWidget);

      // A double click on it: the grid, and the split screen stays.
      await _doubleClickAt(
        tester,
        tester.getCenter(find.byKey(const ValueKey('multiview-back'))),
      );
      expect(find.byType(MultiViewScreen), findsOneWidget);
      expect(slot(0), findsOneWidget);
      expect(one.count('stop'), 0);
      await disposeRig(tester, rig);
    });

    forLocales((locale) {
      testWidgets('Show all tiles on it shows the grid again; a double click '
          'on it leaves the sound where it was (${locale.languageCode})', (
        tester,
      ) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedLive(rig);
        await pumpSplitApp(tester, rig, locale: locale);
        final l10n = await AppLocalizations.delegate.load(locale);
        await openSplit(tester, liveRequest(id));
        await addChannel(tester, 1, 'Channel 2');
        final one = engineFor(rig, '/ch1.');
        final two = engineFor(rig, '/ch2.');
        expect(find.byKey(_showAll), findsNothing);

        await doubleTap(tester, slot(0));
        expect(slot(1), findsNothing);
        final mouse = await mouseAt(tester, const Offset(640, 400));
        expect(inSlot(0, find.byKey(_showAll)), findsOneWidget);
        expect(find.byTooltip(l10n.multiviewShowAll), findsOneWidget);

        // Where it was, the other tile is now.
        await _doubleClickAt(tester, tester.getCenter(find.byKey(_showAll)));
        expect(slot(1), findsOneWidget);
        expect(isActive(0), isTrue);
        expect(one.muted, isFalse);
        expect(two.muted, isTrue);
        // Only a maximized tile offers it.
        await mouse.moveTo(tester.getCenter(slot(0)));
        await settle(tester);
        expect(
          inSlot(0, find.byKey(const ValueKey('multiview-remove'))),
          findsOneWidget,
        );
        expect(find.byKey(_showAll), findsNothing);
        await disposeRig(tester, rig);
      });
    });

    testWidgets('L shows the grid with the new layout', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpSplitApp(tester, rig);
      await openSplit(tester, liveRequest(id));
      await addChannel(tester, 1, 'Channel 2');
      await doubleTap(tester, slot(1));
      expect(slot(0), findsNothing);

      await press(tester, LogicalKeyboardKey.keyL);
      expect(slot(0), findsOneWidget);
      expect(slot(3), findsOneWidget);
      await disposeRig(tester, rig);
    });

    testWidgets('4 tiles: L or the layout button on a maximized one shows '
        'the grid first; no hidden channel stops before it was seen', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpSplitApp(tester, rig);
      await openSplit(tester, liveRequest(id));
      await press(tester, LogicalKeyboardKey.keyL);
      await addChannel(tester, 1, 'Channel 2');
      await addChannel(tester, 2, 'Channel 3');
      await addChannel(tester, 3, 'Channel 4');
      final engines = [for (var i = 1; i <= 4; i++) engineFor(rig, '/ch$i.')];
      void allShownAndPlaying() {
        for (var i = 0; i < 4; i++) {
          expect(slot(i), findsOneWidget);
          expect(engines[i].disposed, isFalse);
        }
        expect(isActive(3), isTrue);
      }

      await doubleTap(tester, slot(3));
      expect(slot(0), findsNothing);
      await press(tester, LogicalKeyboardKey.keyL);
      allShownAndPlaying();

      // The layout button, double clicked: the grid, and nothing stops.
      await doubleTap(tester, slot(3));
      expect(slot(0), findsNothing);
      await mouseAt(tester, const Offset(640, 400));
      await _doubleClickAt(
        tester,
        tester.getCenter(find.byKey(const ValueKey('multiview-layout'))),
      );
      allShownAndPlaying();

      // Every tile seen: now L goes to 2 (tile 4, active, and tile 1).
      await press(tester, LogicalKeyboardKey.keyL);
      expect(slot(2), findsNothing);
      expect(engines[1].disposed, isTrue);
      expect(engines[2].disposed, isTrue);
      expect(engines[0].disposed, isFalse);
      expect(engines[3].disposed, isFalse);
      expect(isActive(1), isTrue);
      await disposeRig(tester, rig);
    });
  });

  forLocales((locale) {
    testWidgets('picker: Up from the top of the channels reaches the '
        'sources (${locale.languageCode})', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final home = await seedLive(rig);
      await seedFree(rig);
      await pumpSplitApp(tester, rig, locale: locale);
      await openSplit(tester, liveRequest(home));

      await press(tester, LogicalKeyboardKey.keyC);
      await openedPicker(tester);
      expect(focusedIn(const ValueKey('channel-row-0')), isTrue);
      for (var i = 0; i < 4; i++) {
        await press(tester, LogicalKeyboardKey.arrowUp);
      }
      expect(focusedIn(ValueKey('multiview-source-$home')), isTrue);
      // Down goes back to the channel.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('channel-row-0')), isTrue);
      await disposeRig(tester, rig);
    });
  });

  testWidgets("the player's channel panel (no source row): Up stops at the "
      'top of the channels', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpPlayerApp(tester, rig);
    await openPlayerFor(tester, liveRequest(id, key: 'ch2'));
    await tester.pump(const Duration(seconds: 5));
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(pickerKey), findsOneWidget);
    expect(focusedIn(const ValueKey('channel-row-1')), isTrue);
    for (var i = 0; i < 3; i++) {
      await press(tester, LogicalKeyboardKey.arrowUp);
    }
    expect(focusedIn(const ValueKey('channel-row-0')), isTrue);
    expect(find.byKey(pickerKey), findsOneWidget);
    await disposeRig(tester, rig);
  });

  testWidgets('D on a failed tile does not say the separate window failed; '
      'the tile offers no Separate window button', (tester) async {
    final rig = PlayerRig();
    var failing = false;
    rig.engines.onCreate = (e) => e.onOpen = (e, r) {
      if (failing) {
        e.emitError('HTTP error 500 Internal Server Error', httpStatus: 500);
      } else {
        e.emitFirstFrame();
      }
    };
    final id = await seedLive(rig);
    final windows = await pumpSplitApp(tester, rig);
    final l10n = await AppLocalizations.delegate.load(en);
    await openPlayerFor(tester, liveRequest(id));
    failing = true;
    await press(tester, LogicalKeyboardKey.keyS);
    await settleSplit(tester);
    expect(
      inSlot(0, find.byKey(const ValueKey('multiview-failure'))),
      findsOneWidget,
    );

    await press(tester, LogicalKeyboardKey.keyD);
    await settleSplit(tester);
    expect(windows.detached, isEmpty);
    expect(find.text(l10n.playerDetachFailed), findsNothing);

    await mouseAt(tester, tester.getCenter(slot(0)) + const Offset(0, 200));
    expect(
      inSlot(0, find.byKey(const ValueKey('multiview-change'))),
      findsOneWidget,
    );
    expect(
      inSlot(0, find.byKey(const ValueKey('multiview-detach'))),
      findsNothing,
    );
    await disposeRig(tester, rig);
  });

  group('a subscription with more than one connection, all in use', () {
    /// Pumps the app with [xtream] allowing [limit] connections and one of
    /// them in a separate window.
    Future<int> pumpWithWindow(
      WidgetTester tester,
      PlayerRig rig,
      Locale locale,
      int limit,
    ) async {
      final xtream = await seedXtream(rig);
      await rig.db.sourcesDao.updateAccount(
        xtream,
        AccountInfo(
          maxConnections: limit,
          allowedFormats: const ['ts', 'm3u8'],
        ),
      );
      await pumpSplitApp(
        tester,
        rig,
        locale: locale,
        windows: [
          DetachedViewer(
            id: 3,
            sourceId: xtream,
            channelKey: '502',
            title: 'Panel Sport',
            maxConnections: limit,
            status: ViewerStatus.playing,
          ),
        ],
      );
      return xtream;
    }

    forLocales((locale) {
      final rtl = locale == ar;
      testWidgets('used by tile 1 and a separate window: the refusal names '
          'both (${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final xtream = await pumpWithWindow(tester, rig, locale, 2);
        final l10n = await AppLocalizations.delegate.load(locale);
        await openSplit(tester, xtreamRequest(xtream, '501'));
        await addChannel(tester, 1, 'Panel Sport', sourceId: xtream);

        expect(find.byKey(_inUse), findsOneWidget);
        expect(find.text(l10n.multiviewInUseMany('Panel', 2)), findsNothing);
        final places = rtl
            ? 'الخانة 1 ونافذة منفصلة'
            : 'tile 1 and a separate window';
        expect(
          find.text(l10n.multiviewInUseManyAt('Panel', 2, places)),
          findsOneWidget,
        );
        expect(rig.openedUrls.where((u) => u.contains('/502.')), isEmpty);
        await disposeRig(tester, rig);
      });

      testWidgets('used by tiles 1 and 2 and a separate window: the refusal '
          'names all three (${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final xtream = await pumpWithWindow(tester, rig, locale, 3);
        final l10n = await AppLocalizations.delegate.load(locale);
        await openSplit(tester, xtreamRequest(xtream, '501'));
        await addChannel(tester, 1, 'Panel Sport', sourceId: xtream);
        expect(find.byKey(_inUse), findsNothing);
        await press(tester, LogicalKeyboardKey.keyL);
        await addChannel(tester, 2, 'Panel News', sourceId: xtream);

        final places = rtl
            ? 'الخانة 1 والخانة 2 ونافذة منفصلة'
            : 'tile 1, tile 2 and a separate window';
        expect(
          find.text(l10n.multiviewInUseManyAt('Panel', 3, places)),
          findsOneWidget,
        );
        await disposeRig(tester, rig);
      });
    });
  });

  group('D on a tile still opening its stream', () {
    /// Tile 1 plays Panel News (Xtream, one connection), whose open takes
    /// 6 s: its stop waits for it. Free 1 is in tile 2. Returns the Xtream
    /// source.
    Future<int> slowNewsInTile1(
      WidgetTester tester,
      PlayerRig rig,
      RecordingDetachedWindows windows,
    ) async {
      rig.engines.onCreate = (e) => e.onOpen = (e, r) async {
        if (r.url.contains('/501.')) {
          await Future<void>.delayed(const Duration(seconds: 6));
        }
        e.emitFirstFrame();
      };
      final xtream = await seedXtream(rig);
      final free = await seedFree(rig);
      await pumpPlayerApp(
        tester,
        rig,
        tv: false,
        platform: TargetPlatform.windows,
        overrides: [detachedWindowsProvider.overrideWith(() => windows)],
      );
      await openSplit(tester, freeRequest(free, 'f1'));
      await press(tester, LogicalKeyboardKey.keyC);
      await openedPicker(tester);
      await pickChannel(tester, 'Panel News', sourceId: xtream);
      expect(
        containerOf(tester).read(connectionBudgetProvider).fits(xtream),
        isFalse,
      );
      return xtream;
    }

    testWidgets('its connection stays counted until the window has it: the '
        'same subscription in another tile waits for it, then is refused', (
      tester,
    ) async {
      final rig = PlayerRig();
      final windows = ListingDetachedWindows(rig);
      final xtream = await slowNewsInTile1(tester, rig, windows);
      final l10n = await AppLocalizations.delegate.load(en);
      final container = containerOf(tester);

      await press(tester, LogicalKeyboardKey.keyD);
      expect(windows.detached, isEmpty);
      expect(container.read(connectionBudgetProvider).usedOn(xtream), 1);
      await tester.tap(inSlot(1, find.byKey(const ValueKey('multiview-add'))));
      await openedPicker(tester);
      await pickChannel(tester, 'Panel Sport', sourceId: xtream);
      // Only a stream still stopping is in the way: the tile waits for it,
      // showing the channel opening.
      expect(find.byKey(_inUse), findsNothing);
      expect(
        inSlot(1, find.byKey(const ValueKey('multiview-buffering'))),
        findsOneWidget,
      );

      // The stop is done and the window listed: it holds the connection,
      // once, and the tile is refused.
      await tester.pump(const Duration(seconds: 7));
      await settleSplit(tester);
      expect(windows.detached.single.channelKey, '501');
      expect(find.text(l10n.multiviewInUseWindow('Panel')), findsOneWidget);
      await press(tester, LogicalKeyboardKey.enter);
      expect(
        inSlot(1, find.byKey(const ValueKey('multiview-failure'))),
        findsOneWidget,
      );
      final budget = container.read(connectionBudgetProvider);
      expect(budget.usedOn(xtream), 1);
      expect(budget.viewersOn(xtream), hasLength(1));
      expect(rig.openedUrls.where((u) => u.contains('/502.')), isEmpty);
      await disposeRig(tester, rig);
    });

    testWidgets('the window fails to open: the connection is free again', (
      tester,
    ) async {
      final rig = PlayerRig();
      final windows = RecordingDetachedWindows(rig)..fail = true;
      final xtream = await slowNewsInTile1(tester, rig, windows);
      final container = containerOf(tester);

      await press(tester, LogicalKeyboardKey.keyD);
      await tester.pump(const Duration(seconds: 7));
      await settleSplit(tester);
      expect(windows.detached.single.channelKey, '501');
      expect(container.read(connectionBudgetProvider).usedOn(xtream), 0);

      await addChannel(tester, 1, 'Panel Sport', sourceId: xtream);
      expect(find.byKey(_inUse), findsNothing);
      expect(rig.openedUrls.where((u) => u.contains('/502.')), hasLength(1));
      await disposeRig(tester, rig);
    });
  });
}
