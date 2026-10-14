import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/tv/tv_focusable.dart';
import 'package:iptv_player/tv/tv_text_field.dart';

import '../support/tv_harness.dart';

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

  Widget form({TextInputAction secondAction = TextInputAction.done}) => Center(
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
          ),
          const SizedBox(height: 16),
          TvTextField(
            focusNode: second,
            textInputAction: secondAction,
            decoration: const InputDecoration(labelText: 'Username'),
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
