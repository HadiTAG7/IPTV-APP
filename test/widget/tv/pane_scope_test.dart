import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/tv/key_repeat.dart';
import 'package:iptv_player/tv/pane_scope.dart';
import 'package:iptv_player/tv/tv_focusable.dart';

import '../support/tv_harness.dart';

/// Three panes laid out start -> end: a rail, a list and an info pane whose
/// two buttons sit side by side.
class _ThreePanes extends StatelessWidget {
  const _ThreePanes({
    required this.rail,
    required this.list,
    required this.info,
    required this.railKey,
    required this.listKey,
    required this.infoKey,
    required this.exits,
  });

  final List<FocusNode> rail;
  final List<FocusNode> list;
  final List<FocusNode> info;
  final GlobalKey<PaneScopeState> railKey;
  final GlobalKey<PaneScopeState> listKey;
  final GlobalKey<PaneScopeState> infoKey;
  final List<String> exits;

  Widget _item(FocusNode node, String label, {bool autofocus = false}) =>
      TvFocusable(
        focusNode: node,
        autofocus: autofocus,
        onSelect: () {},
        child: SizedBox(width: 120, height: 48, child: Text(label)),
      );

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PaneScope(
          key: railKey,
          debugLabel: 'rail',
          onExitEnd: () {
            exits.add('rail>end');
            listKey.currentState!.requestFocus();
          },
          child: Column(
            children: [
              for (var i = 0; i < rail.length; i++)
                _item(rail[i], 'R$i', autofocus: i == 0),
            ],
          ),
        ),
        const SizedBox(width: 40),
        PaneScope(
          key: listKey,
          debugLabel: 'list',
          onExitStart: () {
            exits.add('list>start');
            railKey.currentState!.requestFocus();
          },
          onExitEnd: () {
            exits.add('list>end');
            infoKey.currentState!.requestFocus();
          },
          child: Column(
            children: [
              for (var i = 0; i < list.length; i++) _item(list[i], 'L$i'),
            ],
          ),
        ),
        const SizedBox(width: 40),
        PaneScope(
          key: infoKey,
          debugLabel: 'info',
          onExitStart: () {
            exits.add('info>start');
            listKey.currentState!.requestFocus();
          },
          child: Row(
            children: [
              for (var i = 0; i < info.length; i++) _item(info[i], 'I$i'),
            ],
          ),
        ),
      ],
    );
  }
}

void main() {
  late List<FocusNode> rail;
  late List<FocusNode> list;
  late List<FocusNode> info;
  late GlobalKey<PaneScopeState> railKey;
  late GlobalKey<PaneScopeState> listKey;
  late GlobalKey<PaneScopeState> infoKey;
  late List<String> exits;

  setUp(() {
    rail = List.generate(3, (i) => FocusNode(debugLabel: 'R$i'));
    list = List.generate(5, (i) => FocusNode(debugLabel: 'L$i'));
    info = List.generate(2, (i) => FocusNode(debugLabel: 'I$i'));
    railKey = GlobalKey();
    listKey = GlobalKey();
    infoKey = GlobalKey();
    exits = [];
  });

  tearDown(() {
    for (final n in [...rail, ...list, ...info]) {
      n.dispose();
    }
  });

  Widget panes() => _ThreePanes(
    rail: rail,
    list: list,
    info: info,
    railKey: railKey,
    listKey: listKey,
    infoKey: infoKey,
    exits: exits,
  );

  for (final locale in testLocales) {
    final rtl = locale == ar;
    // Physical arrows towards the reading end / start of the screen.
    final toEnd = rtl
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight;
    final toStart = rtl
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;

    group('PaneScope (${locale.languageCode})', () {
      testWidgets('rail sits on the reading-start side', (tester) async {
        await pumpTv(tester, panes(), locale: locale);
        final railX = tester.getCenter(find.text('R0')).dx;
        final listX = tester.getCenter(find.text('L0')).dx;
        expect(rtl ? railX > listX : railX < listX, isTrue);
      });

      testWidgets('crosses panes at the edge, mirrored in RTL', (tester) async {
        await pumpTv(tester, panes(), locale: locale);
        expect(rail[0].hasPrimaryFocus, isTrue);

        await press(tester, toEnd);
        expect(list[0].hasPrimaryFocus, isTrue);
        expect(exits, ['rail>end']);

        await press(tester, toEnd);
        expect(info[0].hasPrimaryFocus, isTrue);

        // Inside the info pane the arrow moves between its own items first.
        await press(tester, toEnd);
        expect(info[1].hasPrimaryFocus, isTrue);
        // No end neighbour: focus stays.
        await press(tester, toEnd);
        expect(info[1].hasPrimaryFocus, isTrue);

        await press(tester, toStart);
        expect(info[0].hasPrimaryFocus, isTrue);
        await press(tester, toStart);
        expect(list[0].hasPrimaryFocus, isTrue);
        await press(tester, toStart);
        expect(rail[0].hasPrimaryFocus, isTrue);
        expect(exits, ['rail>end', 'list>end', 'info>start', 'list>start']);
      });

      testWidgets('remembers the last focused item of each pane', (
        tester,
      ) async {
        await pumpTv(tester, panes(), locale: locale);
        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(rail[2].hasPrimaryFocus, isTrue);

        await press(tester, toEnd);
        expect(list[0].hasPrimaryFocus, isTrue, reason: 'first visit');
        for (var i = 0; i < 3; i++) {
          await press(tester, LogicalKeyboardKey.arrowDown);
        }
        expect(list[3].hasPrimaryFocus, isTrue);

        await press(tester, toStart);
        expect(rail[2].hasPrimaryFocus, isTrue);
        expect(railKey.currentState!.lastFocused, rail[2]);

        await press(tester, toEnd);
        expect(list[3].hasPrimaryFocus, isTrue);
        expect(listKey.currentState!.lastFocused, list[3]);
      });

      testWidgets('held arrow stops at the pane edge', (tester) async {
        await pumpTv(tester, panes(), locale: locale);
        final clock = FakeClock(DateTime.utc(2026));
        KeyRepeatThrottle.instance = KeyRepeatThrottle(clock: clock);
        expect(rail[0].hasPrimaryFocus, isTrue);

        // The key-down crosses into the list; auto-repeat must not carry on
        // into the info pane.
        await tester.sendKeyDownEvent(toEnd);
        await tester.pumpAndSettle();
        expect(list[0].hasPrimaryFocus, isTrue);
        for (var i = 0; i < 3; i++) {
          clock.advance(const Duration(milliseconds: 150));
          await tester.sendKeyRepeatEvent(toEnd);
          await tester.pumpAndSettle();
        }
        await tester.sendKeyUpEvent(toEnd);
        await tester.pumpAndSettle();
        expect(list[0].hasPrimaryFocus, isTrue);
        expect(exits, ['rail>end']);

        // A fresh press crosses again.
        await press(tester, toEnd);
        expect(info[0].hasPrimaryFocus, isTrue);
        expect(exits, ['rail>end', 'list>end']);
      });

      testWidgets('requestFocus on an unvisited pane takes its first item', (
        tester,
      ) async {
        await pumpTv(tester, panes(), locale: locale);
        expect(infoKey.currentState!.lastFocused, isNull);
        expect(infoKey.currentState!.requestFocus(), isTrue);
        await tester.pump();
        expect(info[0].hasPrimaryFocus, isTrue);
        expect(infoKey.currentState!.hasFocus, isTrue);
      });
    });
  }

  testWidgets('autofocus pane focuses its first item', (tester) async {
    final a = FocusNode();
    addTearDown(a.dispose);
    await pumpTv(
      tester,
      PaneScope(
        autofocus: true,
        child: Column(
          children: [
            TvFocusable(focusNode: a, child: const SizedBox(height: 40)),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(a.hasPrimaryFocus, isTrue);
  });

  testWidgets('arrows in a text field are left to the field', (tester) async {
    final field = FocusNode();
    final controller = TextEditingController(text: 'abc');
    final exits = <String>[];
    addTearDown(field.dispose);
    addTearDown(controller.dispose);
    await pumpTv(
      tester,
      PaneScope(
        onExitStart: () => exits.add('start'),
        onExitEnd: () => exits.add('end'),
        child: SizedBox(
          width: 300,
          child: TextField(focusNode: field, controller: controller),
        ),
      ),
    );
    field.requestFocus();
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(exits, isEmpty);
    expect(field.hasPrimaryFocus, isTrue);
  });
}
