import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/theme/tokens.dart';
import 'package:iptv_player/tv/dpad_shortcuts.dart';
import 'package:iptv_player/tv/tv_focusable.dart';

import '../support/tv_harness.dart';

/// 3 rows x 4 columns of focusable cells.
class _Grid extends StatelessWidget {
  const _Grid({required this.nodes, required this.selected});

  final List<FocusNode> nodes;
  final List<int> selected;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      padding: const EdgeInsets.all(24),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 2,
      children: [
        for (var i = 0; i < nodes.length; i++)
          TvFocusable(
            key: ValueKey('cell-$i'),
            focusNode: nodes[i],
            autofocus: i == 0,
            onSelect: () => selected.add(i),
            child: ColoredBox(
              color: AppColors.surfaceHigh,
              child: Center(child: Text('Cell $i')),
            ),
          ),
      ],
    );
  }
}

int? _focusedIndex(List<FocusNode> nodes) {
  final i = nodes.indexWhere((n) => n.hasPrimaryFocus);
  return i < 0 ? null : i;
}

double _scaleOf(WidgetTester tester, String key) => tester
    .widget<AnimatedScale>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(AnimatedScale),
      ),
    )
    .scale;

bool _hasBorder(WidgetTester tester, String key) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.position == DecorationPosition.foreground,
          ),
        )
        .first,
  );
  final border = (box.decoration as BoxDecoration).border as Border?;
  return border != null && border.top.width == FocusTokens.borderWidth;
}

void main() {
  late List<FocusNode> nodes;
  late List<int> selected;

  setUp(() {
    nodes = List.generate(12, (i) => FocusNode(debugLabel: 'cell-$i'));
    selected = [];
  });

  tearDown(() {
    for (final n in nodes) {
      n.dispose();
    }
  });

  for (final locale in testLocales) {
    final rtl = locale == ar;
    group('grid traversal (${locale.languageCode})', () {
      testWidgets('arrows move focus spatially and mirror in RTL', (
        tester,
      ) async {
        await pumpTv(
          tester,
          _Grid(nodes: nodes, selected: selected),
          locale: locale,
        );
        expect(_focusedIndex(nodes), 0);

        // Cell 1 is physically right of cell 0 in LTR and left of it in RTL.
        final towardsOne = rtl
            ? LogicalKeyboardKey.arrowLeft
            : LogicalKeyboardKey.arrowRight;
        final towardsZero = rtl
            ? LogicalKeyboardKey.arrowRight
            : LogicalKeyboardKey.arrowLeft;

        await press(tester, towardsOne);
        expect(_focusedIndex(nodes), 1);
        await press(tester, towardsOne);
        expect(_focusedIndex(nodes), 2);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(_focusedIndex(nodes), 6);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(_focusedIndex(nodes), 10);
        // Bottom edge: stays put.
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(_focusedIndex(nodes), 10);
        await press(tester, towardsZero);
        expect(_focusedIndex(nodes), 9);
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(_focusedIndex(nodes), 5);
        await press(tester, towardsZero);
        await press(tester, towardsZero);
        expect(_focusedIndex(nodes), 4);
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(_focusedIndex(nodes), 0);
      });

      testWidgets('focused cell is scaled and bordered', (tester) async {
        await pumpTv(
          tester,
          _Grid(nodes: nodes, selected: selected),
          locale: locale,
        );
        await tester.pumpAndSettle();
        expect(_scaleOf(tester, 'cell-0'), FocusTokens.scale);
        expect(_hasBorder(tester, 'cell-0'), isTrue);
        expect(_scaleOf(tester, 'cell-1'), 1.0);
        expect(_hasBorder(tester, 'cell-1'), isFalse);

        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(_scaleOf(tester, 'cell-0'), 1.0);
        expect(_scaleOf(tester, 'cell-4'), FocusTokens.scale);
        expect(_hasBorder(tester, 'cell-4'), isTrue);
      });

      testWidgets('select, enter, numpad enter and game A activate', (
        tester,
      ) async {
        await pumpTv(
          tester,
          _Grid(nodes: nodes, selected: selected),
          locale: locale,
        );
        await press(tester, LogicalKeyboardKey.select);
        expect(selected, [0]);
        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.enter);
        await press(tester, LogicalKeyboardKey.numpadEnter);
        await press(tester, LogicalKeyboardKey.gameButtonA);
        expect(selected, [0, 4, 4, 4]);
      });
    });
  }

  group('TvFocusable keys', () {
    testWidgets('held OK does not re-activate', (tester) async {
      var count = 0;
      await pumpTv(
        tester,
        TvFocusable(
          autofocus: true,
          onSelect: () => count++,
          child: const SizedBox(width: 100, height: 50),
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(count, 1);
    });

    for (final locale in testLocales) {
      testWidgets('held OK does not confirm the dialog it opened '
          '(${locale.languageCode})', (tester) async {
        var deleted = false;
        await pumpTv(
          tester,
          Builder(
            builder: (context) => TvFocusable(
              autofocus: true,
              onSelect: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  content: const Text('Delete source?'),
                  actions: [
                    TextButton(
                      autofocus: true,
                      onPressed: () => deleted = true,
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ),
              child: const SizedBox(width: 100, height: 50),
            ),
          ),
          locale: locale,
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(find.text('Delete source?'), findsOneWidget);
        for (var i = 0; i < 3; i++) {
          await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
          await tester.pump();
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(deleted, isFalse);

        // A fresh press on the focused button confirms.
        await press(tester, LogicalKeyboardKey.select);
        expect(deleted, isTrue);
      });
    }

    testWidgets('appShortcuts activate once per press on every OK key', (
      tester,
    ) async {
      final shortcuts = appShortcuts;
      for (final key in {...selectKeys, LogicalKeyboardKey.space}) {
        final activators = shortcuts.entries
            .where(
              (e) =>
                  e.key is SingleActivator &&
                  (e.key as SingleActivator).trigger == key,
            )
            .toList();
        expect(activators, hasLength(1), reason: key.debugName);
        expect(activators.single.value, isA<ActivateIntent>());
        expect(
          (activators.single.key as SingleActivator).includeRepeats,
          isFalse,
          reason: key.debugName,
        );
      }
      expect(
        shortcuts[const SingleActivator(LogicalKeyboardKey.arrowUp)],
        isA<DirectionalFocusIntent>(),
      );
      expect(
        shortcuts[const SingleActivator(LogicalKeyboardKey.escape)],
        isA<DismissIntent>(),
      );
    });

    testWidgets('long OK fires onLongSelect once, short OK fires onSelect', (
      tester,
    ) async {
      var short = 0;
      var long = 0;
      await pumpTv(
        tester,
        TvFocusable(
          autofocus: true,
          onSelect: () => short++,
          onLongSelect: () => long++,
          child: const SizedBox(width: 100, height: 50),
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      expect(short, 0, reason: 'short press fires on key up');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      expect((short, long), (1, 0));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      expect((short, long), (1, 1));
    });

    testWidgets('Menu key calls onMenu', (tester) async {
      var menu = 0;
      await pumpTv(
        tester,
        TvFocusable(
          autofocus: true,
          onSelect: () {},
          onMenu: () => menu++,
          child: const SizedBox(width: 100, height: 50),
        ),
      );
      await press(tester, LogicalKeyboardKey.contextMenu);
      expect(menu, 1);
    });

    testWidgets('onFocusChange reports focus in and out', (tester) async {
      final events = <String>[];
      await pumpTv(
        tester,
        Column(
          children: [
            TvFocusable(
              autofocus: true,
              onFocusChange: (f) => events.add('a:$f'),
              child: const SizedBox(width: 100, height: 50),
            ),
            TvFocusable(
              onFocusChange: (f) => events.add('b:$f'),
              child: const SizedBox(width: 100, height: 50),
            ),
          ],
        ),
      );
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(events, ['a:true', 'a:false', 'b:true']);
    });

    testWidgets('disabled item is skipped', (tester) async {
      final a = FocusNode();
      final c = FocusNode();
      addTearDown(a.dispose);
      addTearDown(c.dispose);
      await pumpTv(
        tester,
        Column(
          children: [
            TvFocusable(
              focusNode: a,
              autofocus: true,
              child: const SizedBox(width: 100, height: 50),
            ),
            const TvFocusable(
              enabled: false,
              child: SizedBox(width: 100, height: 50),
            ),
            TvFocusable(
              focusNode: c,
              child: const SizedBox(width: 100, height: 50),
            ),
          ],
        ),
      );
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(c.hasPrimaryFocus, isTrue);
    });
  });

  group('mouse and touch', () {
    testWidgets('hover shows the border and tap selects', (tester) async {
      var taps = 0;
      await pumpTv(
        tester,
        Center(
          child: TvFocusable(
            key: const ValueKey('item'),
            onSelect: () => taps++,
            child: const SizedBox(width: 120, height: 60),
          ),
        ),
      );
      expect(_hasBorder(tester, 'item'), isFalse);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('item'))));
      await tester.pumpAndSettle();
      expect(_hasBorder(tester, 'item'), isTrue);

      await tester.tap(find.byKey(const ValueKey('item')));
      expect(taps, 1);
    });

    testWidgets('disabled item ignores taps, long presses and clicks', (
      tester,
    ) async {
      var taps = 0;
      var longs = 0;
      await pumpTv(
        tester,
        Center(
          child: TvFocusable(
            key: const ValueKey('item'),
            enabled: false,
            onSelect: () => taps++,
            onLongSelect: () => longs++,
            child: const SizedBox(width: 120, height: 60),
          ),
        ),
      );
      final item = find.byKey(const ValueKey('item'));
      await tester.tap(item);
      await tester.longPress(item);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: tester.getCenter(item));
      await tester.pumpAndSettle();
      await mouse.down(tester.getCenter(item));
      await mouse.up();
      await tester.pumpAndSettle();
      expect((taps, longs), (0, 0));
      expect(_hasBorder(tester, 'item'), isFalse, reason: 'no hover ring');
      final detector = tester.widget<FocusableActionDetector>(
        find.descendant(
          of: item,
          matching: find.byType(FocusableActionDetector),
        ),
      );
      expect(detector.mouseCursor, MouseCursor.defer);
      expect(
        tester.getSemantics(item),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      );
    });

    testWidgets('long press falls back to onMenu', (tester) async {
      var menu = 0;
      await pumpTv(
        tester,
        Center(
          child: TvFocusable(
            key: const ValueKey('item'),
            onSelect: () {},
            onMenu: () => menu++,
            child: const SizedBox(width: 120, height: 60),
          ),
        ),
      );
      await tester.longPress(find.byKey(const ValueKey('item')));
      expect(menu, 1);
    });
  });

  group('ensureVisible', () {
    testWidgets('keeps the focused row centred while scrolling', (
      tester,
    ) async {
      final rows = List.generate(40, (i) => FocusNode(debugLabel: 'row-$i'));
      addTearDown(() {
        for (final n in rows) {
          n.dispose();
        }
      });
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpTv(
        tester,
        ListView.builder(
          controller: controller,
          itemExtent: TvLayout.channelExtent,
          itemCount: rows.length,
          itemBuilder: (context, i) => TvFocusable(
            key: ValueKey('row-$i'),
            focusNode: rows[i],
            autofocus: i == 0,
            child: Text('Row $i'),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(rows[20].hasPrimaryFocus, isTrue);
      expect(controller.offset, greaterThan(0));
      final viewport = tester.getRect(find.byType(ListView));
      final row = tester.getRect(find.byKey(const ValueKey('row-20')));
      expect(
        (row.center.dy - viewport.center.dy).abs(),
        lessThan(TvLayout.channelExtent),
      );
    });
  });
}
