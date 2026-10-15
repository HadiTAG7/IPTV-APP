import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/settings/settings_dialogs.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/tv/dpad_shortcuts.dart';

import 'settings_harness.dart' show focusDescription, focusedIn;

final _en = lookupAppLocalizations(const Locale('en'));

/// Opens an [AddEpgUrlDialog] with [onAdd]; returns what it popped.
Future<List<bool?>> _openAddDialog(
  WidgetTester tester,
  Future<AddEpgUrlResult> Function(String url) onAdd,
) async {
  final popped = <bool?>[];
  await tester.pumpWidget(
    MaterialApp(
      shortcuts: appShortcuts,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => popped.add(
            await showDialog<bool>(
              context: context,
              builder: (_) => AddEpgUrlDialog(onAdd: onAdd),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return popped;
}

const _field = ValueKey('epg-url-field');
const _add = ValueKey('epg-url-add');

bool _addEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(_add)).onPressed != null;

/// The saving spinner inside Add.
Finder _spinner() => find.descendant(
  of: find.byKey(_add),
  matching: find.byType(CircularProgressIndicator),
);

void main() {
  testWidgets('Add guide URL: a throwing save shows an error and Add works '
      'again', (tester) async {
    var calls = 0;
    final popped = await _openAddDialog(tester, (url) async {
      calls++;
      if (calls == 1) throw StateError('database closed');
      return AddEpgUrlResult.added;
    });
    await tester.enterText(find.byKey(_field), 'https://example.com/a.xml');
    await tester.tap(find.byKey(_add));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AddEpgUrlDialog), findsOneWidget);
    expect(find.text(_en.settings_saveFailed), findsOneWidget);
    expect(_addEnabled(tester), isTrue);

    // The second try succeeds and closes the dialog.
    await tester.tap(find.byKey(_add));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(AddEpgUrlDialog), findsNothing);
    expect(popped, [true]);
  });

  testWidgets('Add guide URL: Add ignores presses while saving; a duplicate '
      'says so', (tester) async {
    final pending = Completer<AddEpgUrlResult>();
    final urls = <String>[];
    await _openAddDialog(tester, (url) {
      urls.add(url);
      return pending.future;
    });
    await tester.enterText(find.byKey(_field), ' https://example.com/a.xml ');
    await tester.tap(find.byKey(_add));
    await tester.pump();
    expect(urls, ['https://example.com/a.xml']);
    expect(_spinner(), findsOneWidget);
    await tester.tap(find.byKey(_add));
    await tester.pump();
    expect(urls, hasLength(1));

    pending.complete(AddEpgUrlResult.exists);
    await tester.pumpAndSettle();
    expect(find.text(_en.settings_epgUrlExists), findsOneWidget);
    expect(_spinner(), findsNothing);
    expect(_addEnabled(tester), isTrue);
    expect(find.byType(AddEpgUrlDialog), findsOneWidget);
  });

  testWidgets('Add guide URL: with the remote, focus stays on Add during a '
      'slow save and the keyboard stays closed', (tester) async {
    final pending = Completer<AddEpgUrlResult>();
    final urls = <String>[];
    await _openAddDialog(tester, (url) {
      urls.add(url);
      return pending.future;
    });
    expect(focusedIn(_field), isTrue);
    await tester.enterText(find.byKey(_field), 'https://example.com/a.xml');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focusedIn(_add), isTrue, reason: focusDescription());
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(urls, ['https://example.com/a.xml']);
    expect(focusedIn(_add), isTrue, reason: focusDescription());
    expect(tester.testTextInput.isVisible, isFalse);
    expect(_spinner(), findsOneWidget);
    // A second OK while saving does nothing.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(urls, hasLength(1));

    pending.complete(AddEpgUrlResult.exists);
    await tester.pumpAndSettle();
    expect(find.text(_en.settings_epgUrlExists), findsOneWidget);
    expect(focusedIn(_add), isTrue, reason: focusDescription());
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('Add guide URL: a failed save shows the save error', (
    tester,
  ) async {
    await _openAddDialog(tester, (url) async => AddEpgUrlResult.failed);
    await tester.enterText(find.byKey(_field), 'https://example.com/a.xml');
    await tester.tap(find.byKey(_add));
    await tester.pumpAndSettle();
    expect(find.text(_en.settings_saveFailed), findsOneWidget);
    expect(_addEnabled(tester), isTrue);
  });
}
