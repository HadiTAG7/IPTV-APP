import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/theme/app_theme.dart';
import 'package:iptv_player/tv/dpad_shortcuts.dart';
import 'package:iptv_player/tv/key_repeat.dart';
import 'package:iptv_player/widgets/logo_image.dart';

const en = Locale('en');
const ar = Locale('ar');
const testLocales = [en, ar];

/// Minimal app shell matching the real one: dark theme, l10n, root shortcuts.
class TestApp extends StatelessWidget {
  const TestApp({super.key, required this.child, this.locale = en});

  final Widget child;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(tv: true),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      shortcuts: appShortcuts,
      home: Scaffold(body: child),
    );
  }
}

/// Pumps [child] on a 1920x1080 TV at device pixel ratio 2 (960x540 dp).
Future<void> pumpTv(
  WidgetTester tester,
  Widget child, {
  Locale locale = en,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  applyFocusHighlightStrategy(tv: true);
  addTearDown(() => applyFocusHighlightStrategy(tv: false));
  KeyRepeatThrottle.instance = KeyRepeatThrottle();
  FailedImageCache.clear();
  await tester.pumpWidget(TestApp(locale: locale, child: child));
  await tester.pump();
}

/// Presses and releases [key], then lets animations settle.
Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

/// The node with primary focus, if any.
FocusNode? get primary => FocusManager.instance.primaryFocus;
