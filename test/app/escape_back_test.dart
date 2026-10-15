// Escape (and the browser Back key) is Back on desktop. It reaches the
// app's Back action from any page: in TV mode on Windows the source editor,
// the movie/series detail frame and the licences page have no back button,
// so Escape is the only way out. On the home route it goes through the
// shell's own Back handling.
import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseEntryWithLineBreaks;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/app.dart';
import 'package:iptv_player/app/form_factor.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/features/help/help_screen.dart';
import 'package:iptv_player/features/help/licenses_page.dart';
import 'package:iptv_player/features/sources/source_editor_screen.dart';
import 'package:iptv_player/features/vod_common/vod_widgets.dart';
import 'package:iptv_player/tv/tv_focusable.dart';

import '../features/sources/support.dart';

Future<AppDatabase> _pumpWindows(
  WidgetTester tester, {
  required bool tv,
}) async {
  final db = openAppTestDb();
  await addTestSource(db, lastSyncAt: DateTime.now());
  await pumpApp(
    tester,
    db: db,
    fakePages: true,
    logicalSize: tv ? const Size(960, 540) : const Size(1280, 800),
    settings: AppSettings(
      formFactor: tv ? FormFactorOverride.tv : FormFactorOverride.auto,
    ),
    overrides: [
      targetPlatformProvider.overrideWithValue(TargetPlatform.windows),
    ],
  );
  return db;
}

NavigatorState _navigator(WidgetTester tester) =>
    containerOf(tester).read(navigatorKeyProvider).currentState!;

/// Pushes [page] on the root navigator and waits for the transition.
Future<void> _push(WidgetTester tester, Widget page) async {
  _navigator(tester)
      .push(MaterialPageRoute<void>(builder: (_) => page))
      .ignore();
  await settleRoute(tester);
  await settle(tester);
}

Stream<LicenseEntry> _licenses() => Stream.value(
  const LicenseEntryWithLineBreaks(['some_package'], 'License text.'),
);

void main() {
  testWidgets('Windows desktop: Escape closes Help', (tester) async {
    final db = await _pumpWindows(tester, tv: false);
    expect(
      FormFactorScope.of(tester.element(find.byType(HomeShell))),
      FormFactor.desktop,
    );
    await _push(tester, const HelpScreen());
    expect(find.byType(HelpScreen), findsOneWidget);

    await press(tester, LogicalKeyboardKey.escape);
    await settleRoute(tester);
    expect(find.byType(HelpScreen), findsNothing);
    await drainNetworkTimers(tester);
    await disposeApp(tester, db);
  });

  group('Windows in TV mode', () {
    testWidgets('Escape closes the source editor, from a text field too', (
      tester,
    ) async {
      final db = await _pumpWindows(tester, tv: true);
      expect(
        FormFactorScope.of(tester.element(find.byType(HomeShell))),
        FormFactor.tv,
      );
      await _push(tester, const SourceEditorScreen());
      expect(find.byType(SourceEditorScreen), findsOneWidget);
      expect(find.byType(BackButton), findsNothing, reason: 'no back button');

      await press(tester, LogicalKeyboardKey.escape);
      await settleRoute(tester);
      expect(find.byType(SourceEditorScreen), findsNothing);

      // Again with focus in a text field: Escape is still Back.
      await _push(tester, const SourceEditorScreen());
      final field = find.descendant(
        of: find.byType(SourceEditorScreen),
        matching: find.byType(EditableText),
      );
      tester
          .state<EditableTextState>(field.first)
          .widget
          .focusNode
          .requestFocus();
      await settle(tester);
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorStateOfType<EditableTextState>(),
        isNotNull,
      );
      await press(tester, LogicalKeyboardKey.escape);
      await settleRoute(tester);
      expect(find.byType(SourceEditorScreen), findsNothing);
      await drainNetworkTimers(tester);
      await disposeApp(tester, db);
    });

    testWidgets('Escape closes a movie/series detail page', (tester) async {
      final db = await _pumpWindows(tester, tv: true);
      await _push(
        tester,
        VodDetailFrame(
          title: 'Movie',
          child: TvFocusable(
            key: const ValueKey('detail-play'),
            autofocus: true,
            onSelect: () {},
            child: const SizedBox(width: 120, height: 48),
          ),
        ),
      );
      expect(find.byType(VodDetailFrame), findsOneWidget);
      expectFocus('detail-play');

      await press(tester, LogicalKeyboardKey.escape);
      await settleRoute(tester);
      expect(find.byType(VodDetailFrame), findsNothing);
      await drainNetworkTimers(tester);
      await disposeApp(tester, db);
    });

    testWidgets('the browser Back key closes the licences page', (
      tester,
    ) async {
      final db = await _pumpWindows(tester, tv: true);
      await _push(
        tester,
        const TvLicensePage(applicationName: 'IPTV', licenses: _licenses),
      );
      expect(find.byType(TvLicensePage), findsOneWidget);

      // The Back key of a Windows keyboard or media remote.
      await tester.sendKeyEvent(
        LogicalKeyboardKey.browserBack,
        platform: 'windows',
      );
      await settleRoute(tester);
      expect(find.byType(TvLicensePage), findsNothing);
      await drainNetworkTimers(tester);
      await disposeApp(tester, db);
    });

    testWidgets('Escape on the home route moves to the rail, then asks '
        'to press again to exit', (tester) async {
      final db = await _pumpWindows(tester, tv: true);
      expectFocus('rail-live');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expectFocus('live-A');

      await press(tester, LogicalKeyboardKey.escape);
      expectFocus('rail-live');

      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.text(enL10n.commonPressBackAgainToExit), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await drainNetworkTimers(tester);
      await disposeApp(tester, db);
    });
  });
}
