import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Types [text] into the text field at [finder] (or below it) the way a
/// remote user does.
///
/// On Android TV a `TvTextField` is read-only, with no keyboard, until OK
/// opens it; this focuses such a field and presses OK first. Elsewhere it is
/// [WidgetTester.enterText].
Future<void> typeText(WidgetTester tester, Finder finder, String text) async {
  final editable = find.descendant(
    of: finder,
    matching: find.byType(EditableText),
    matchRoot: true,
  );
  final state = tester.state<EditableTextState>(editable);
  if (state.widget.readOnly) {
    final node = state.widget.focusNode;
    if (!node.hasPrimaryFocus) {
      node.requestFocus();
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    // One frame to drop read-only, whose end opens the keyboard.
    await tester.pump();
    await tester.pump();
  }
  await tester.enterText(finder, text);
}
