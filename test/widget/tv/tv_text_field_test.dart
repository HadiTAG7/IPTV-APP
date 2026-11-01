import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/form_factor.dart';
import 'package:iptv_player/tv/pane_scope.dart';
import 'package:iptv_player/tv/tv_focusable.dart';
import 'package:iptv_player/tv/tv_text_field.dart';

import '../support/tv_harness.dart';

/// A rail pane next to a pane that holds only a search field (the Search
/// screen with no results yet).
class _FieldPane extends StatelessWidget {
  const _FieldPane({
    required this.railItem,
    required this.field,
    required this.controller,
    required this.railKey,
    required this.exits,
    this.button,
  });

  final FocusNode railItem;
  final FocusNode field;
  final TextEditingController controller;
  final GlobalKey<PaneScopeState> railKey;
  final List<String> exits;

  /// Optional button beside the field inside the same pane.
  final FocusNode? button;

  @override
  Widget build(BuildContext context) {
    final button = this.button;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PaneScope(
          key: railKey,
          child: TvFocusable(
            focusNode: railItem,
            onSelect: () {},
            child: const SizedBox(width: 120, height: 48, child: Text('Rail')),
          ),
        ),
        const SizedBox(width: 40),
        PaneScope(
          onExitStart: () {
            exits.add('start');
            railKey.currentState!.requestFocus();
          },
          onExitEnd: () => exits.add('end'),
          onExitUp: () => exits.add('up'),
          onExitDown: () => exits.add('down'),
          child: Row(
            children: [
              SizedBox(
                width: 300,
                child: TvTextField(focusNode: field, controller: controller),
              ),
              if (button != null)
                TvFocusable(
                  focusNode: button,
                  onSelect: () {},
                  child: const SizedBox(width: 48, height: 48),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

void main() {
  late FocusNode above;
  late FocusNode first;
  late FocusNode second;
  late FocusNode below;

  setUp(() {
    above = FocusNode(debugLabel: 'above');
    first = FocusNode(debugLabel: 'first');
    second = FocusNode(debugLabel: 'second');
    below = FocusNode(debugLabel: 'below');
  });

  tearDown(() {
    for (final n in [above, first, second, below]) {
      n.dispose();
    }
  });

  Widget form({
    TextInputAction secondAction = TextInputAction.done,
    ValueChanged<String>? onSubmitted,
  }) => Center(
    child: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TvFocusable(
            focusNode: above,
            onSelect: () {},
            child: const SizedBox(height: 48, child: Text('Above')),
          ),
          const SizedBox(height: 16),
          TvTextField(
            focusNode: first,
            nextFocusNode: second,
            decoration: const InputDecoration(labelText: 'Server'),
            onSubmitted: onSubmitted,
          ),
          const SizedBox(height: 16),
          TvTextField(
            focusNode: second,
            textInputAction: secondAction,
            decoration: const InputDecoration(labelText: 'Username'),
            onSubmitted: onSubmitted,
          ),
          const SizedBox(height: 16),
          TvFocusable(
            focusNode: below,
            onSelect: () {},
            child: const SizedBox(height: 48, child: Text('Below')),
          ),
        ],
      ),
    ),
  );

  for (final locale in testLocales) {
    group('TvTextField (${locale.languageCode})', () {
      testWidgets('up/down escape the field', (tester) async {
        await pumpTv(tester, form(), locale: locale);
        first.requestFocus();
        await tester.pumpAndSettle();
        expect(first.hasPrimaryFocus, isTrue);

        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(second.hasPrimaryFocus, isTrue);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(below.hasPrimaryFocus, isTrue);
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(second.hasPrimaryFocus, isTrue);
        await press(tester, LogicalKeyboardKey.arrowUp);
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(above.hasPrimaryFocus, isTrue);
      });

      testWidgets('left/right still edit inside the field', (tester) async {
        await pumpTv(tester, form(), locale: locale);
        first.requestFocus();
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'abc');
        await press(tester, LogicalKeyboardKey.arrowLeft);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(first.hasPrimaryFocus, isTrue);
      });

      testWidgets('next chains to the next field, done keeps focus', (
        tester,
      ) async {
        await pumpTv(tester, form(), locale: locale);
        first.requestFocus();
        await tester.pumpAndSettle();
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pumpAndSettle();
        expect(second.hasPrimaryFocus, isTrue);

        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(second.hasPrimaryFocus, isTrue);
        expect(tester.testTextInput.isVisible, isFalse);
      });

      testWidgets('OK re-opens the keyboard', (tester) async {
        await pumpTv(tester, form(), locale: locale);
        second.requestFocus();
        await tester.pumpAndSettle();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isFalse);

        await press(tester, LogicalKeyboardKey.select);
        expect(tester.testTextInput.isVisible, isTrue);
        expect(second.hasPrimaryFocus, isTrue);
      });
    });
  }

  group('TV: the soft keyboard waits for OK', () {
    Widget tv(Widget child) =>
        FormFactorScope(formFactor: FormFactor.tv, child: child);

    /// Methods sent on the text input channel since the last [clear].
    List<String> sent(WidgetTester tester) => [
      for (final call in tester.testTextInput.log) call.method,
    ];

    void clear(WidgetTester tester) => tester.testTextInput.log.clear();

    testWidgets('D-pad focus opens no keyboard; OK does, Next keeps it', (
      tester,
    ) async {
      await pumpTv(tester, tv(form()));
      above.requestFocus();
      await tester.pumpAndSettle();
      clear(tester);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(first.hasPrimaryFocus, isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(second.hasPrimaryFocus, isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(first.hasPrimaryFocus, isTrue);
      expect(sent(tester), isNot(contains('TextInput.show')));
      expect(sent(tester), isNot(contains('TextInput.setClient')));
      expect(tester.testTextInput.isVisible, isFalse);

      await press(tester, LogicalKeyboardKey.select);
      expect(
        sent(tester),
        containsAllInOrder(['TextInput.setClient', 'TextInput.show']),
      );
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.enterText(find.byType(TextField).first, 'host');
      expect(find.text('host'), findsOneWidget);

      // Next on the keyboard moves on and keeps it open for the next field.
      clear(tester);
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(second.hasPrimaryFocus, isTrue);
      expect(sent(tester), contains('TextInput.show'));
      expect(tester.testTextInput.isVisible, isTrue);

      // Done closes it and keeps focus; the D-pad leaves without reopening.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(second.hasPrimaryFocus, isTrue);
      expect(tester.testTextInput.isVisible, isFalse);
      clear(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(below.hasPrimaryFocus, isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(second.hasPrimaryFocus, isTrue);
      expect(sent(tester), isNot(contains('TextInput.show')));
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('Done submits and the keyboard stays closed over what the '
        'submission shows; Next submits and moves on', (tester) async {
      final submitted = <String>[];
      await pumpTv(tester, tv(form(onSubmitted: submitted.add)));
      first.requestFocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.select);
      await tester.enterText(find.byType(TextField).first, 'host');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(second.hasPrimaryFocus, isTrue);
      expect(submitted, ['host']);
      await tester.enterText(find.byType(TextField).last, 'user');
      clear(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(submitted, ['host', 'user']);
      expect(second.hasPrimaryFocus, isTrue);
      expect(sent(tester), isNot(contains('TextInput.show')));
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('an autofocused field waits for OK too', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await pumpTv(
        tester,
        tv(
          SizedBox(
            width: 300,
            child: TvTextField(focusNode: node, autofocus: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(node.hasPrimaryFocus, isTrue);
      expect(sent(tester), isNot(contains('TextInput.show')));

      await press(tester, LogicalKeyboardKey.select);
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('a tap opens the keyboard', (tester) async {
      await pumpTv(tester, tv(form()));
      await tester.tap(find.byType(TextField).last);
      await tester.pumpAndSettle();
      expect(second.hasPrimaryFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('elsewhere focus still opens the keyboard', (tester) async {
      await pumpTv(tester, form());
      above.requestFocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(first.hasPrimaryFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });
  });

  for (final locale in testLocales) {
    final rtl = locale == ar;
    // Physical arrows towards the reading start / end of the screen.
    final toStart = rtl
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;
    final toEnd = rtl
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight;

    group('field-only pane (${locale.languageCode})', () {
      late FocusNode railItem;
      late FocusNode field;
      late FocusNode button;
      late TextEditingController controller;
      late GlobalKey<PaneScopeState> railKey;
      late List<String> exits;

      setUp(() {
        railItem = FocusNode(debugLabel: 'rail');
        field = FocusNode(debugLabel: 'field');
        button = FocusNode(debugLabel: 'button');
        controller = TextEditingController();
        railKey = GlobalKey();
        exits = [];
      });

      tearDown(() {
        railItem.dispose();
        field.dispose();
        button.dispose();
        controller.dispose();
      });

      Future<void> pumpPane(WidgetTester tester, {bool withButton = false}) =>
          pumpTv(
            tester,
            _FieldPane(
              railItem: railItem,
              field: field,
              controller: controller,
              railKey: railKey,
              exits: exits,
              button: withButton ? button : null,
            ),
            locale: locale,
          );

      Future<void> focusField(WidgetTester tester, {int? caret}) async {
        field.requestFocus();
        await tester.pumpAndSettle();
        if (caret != null) {
          controller.selection = TextSelection.collapsed(offset: caret);
          await tester.pump();
        }
      }

      testWidgets('an empty field exits to the neighbour pane', (tester) async {
        await pumpPane(tester);
        await focusField(tester);
        await press(tester, toStart);
        expect(exits, ['start']);
        expect(railItem.hasPrimaryFocus, isTrue);
      });

      testWidgets('up and down exit the pane from the field', (tester) async {
        await pumpPane(tester);
        controller.text = 'news';
        await focusField(tester, caret: 2);
        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(exits, ['down', 'up']);
        expect(controller.selection.baseOffset, 2, reason: 'caret untouched');
      });

      testWidgets('left/right move the caret, then exit at the text end', (
        tester,
      ) async {
        await pumpPane(tester);
        controller.text = 'abc';
        await focusField(tester, caret: 3);

        // Flutter moves the caret logically: Left goes back, Right forward.
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(controller.selection.baseOffset, 2);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(controller.selection.baseOffset, 3);
        expect(exits, isEmpty);
        expect(field.hasPrimaryFocus, isTrue);

        // At the end Right leaves: the reading end in LTR, start in RTL.
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(exits, [if (rtl) 'start' else 'end']);
      });

      testWidgets('caret at the start: Left leaves the field', (tester) async {
        await pumpPane(tester);
        controller.text = 'abc';
        await focusField(tester, caret: 0);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(exits, [if (rtl) 'end' else 'start']);
      });

      testWidgets('a selection collapses before the field is left', (
        tester,
      ) async {
        await pumpPane(tester);
        controller.text = 'abc';
        await focusField(tester);
        controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 3,
        );
        await tester.pump();
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(controller.selection, const TextSelection.collapsed(offset: 0));
        expect(exits, isEmpty);
      });

      testWidgets('a held arrow stops at the text end', (tester) async {
        await pumpPane(tester);
        controller.text = 'abc';
        await focusField(tester, caret: 1);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(controller.selection.baseOffset, 0);
        for (var i = 0; i < 3; i++) {
          await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pump();
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(exits, isEmpty);
        expect(field.hasPrimaryFocus, isTrue);

        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(exits, hasLength(1));
      });

      testWidgets('reaches a button beside the field before exiting', (
        tester,
      ) async {
        await pumpPane(tester, withButton: true);
        await focusField(tester);
        await press(tester, toEnd);
        expect(button.hasPrimaryFocus, isTrue);
        expect(exits, isEmpty);
        await press(tester, toStart);
        expect(field.hasPrimaryFocus, isTrue);
        await press(tester, toStart);
        expect(railItem.hasPrimaryFocus, isTrue);
        expect(exits, ['start']);
      });
    });
  }

  group('arrowLeavesTextField', () {
    testWidgets('outside a text field always leaves', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await pumpTv(
        tester,
        TvFocusable(focusNode: node, child: const SizedBox(width: 10)),
      );
      for (final d in TraversalDirection.values) {
        expect(arrowLeavesTextField(node, d), isTrue, reason: d.name);
      }
    });

    testWidgets('multi-line fields keep up/down until the text end', (
      tester,
    ) async {
      final node = FocusNode();
      final controller = TextEditingController(text: 'one\ntwo');
      addTearDown(node.dispose);
      addTearDown(controller.dispose);
      await pumpTv(
        tester,
        SizedBox(
          width: 300,
          child: TextField(
            focusNode: node,
            controller: controller,
            maxLines: 3,
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();
      controller.selection = const TextSelection.collapsed(offset: 5);
      expect(arrowLeavesTextField(node, TraversalDirection.up), isFalse);
      expect(arrowLeavesTextField(node, TraversalDirection.down), isFalse);
      controller.selection = const TextSelection.collapsed(offset: 7);
      expect(arrowLeavesTextField(node, TraversalDirection.down), isTrue);
      controller.selection = const TextSelection.collapsed(offset: 0);
      expect(arrowLeavesTextField(node, TraversalDirection.up), isTrue);
      expect(arrowLeavesTextField(node, TraversalDirection.left), isTrue);
      expect(arrowLeavesTextField(node, TraversalDirection.right), isFalse);
    });
  });

  testWidgets('next without nextFocusNode uses traversal order', (
    tester,
  ) async {
    final a = FocusNode();
    final b = FocusNode();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await pumpTv(
      tester,
      Column(
        children: [
          TvTextField(focusNode: a),
          TvTextField(focusNode: b),
        ],
      ),
    );
    a.requestFocus();
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(b.hasPrimaryFocus, isTrue);
  });
}
