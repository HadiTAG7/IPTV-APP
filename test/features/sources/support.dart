// Helpers shared by the onboarding and source management widget tests.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/app.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/core/platform/device_caps.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/sources/source_repository.dart';
import 'package:iptv_player/sources/sync/sync_service.dart';
import 'package:iptv_player/tv/dpad_shortcuts.dart';
import 'package:iptv_player/tv/key_repeat.dart';

import '../../app/app_harness.dart';

export '../../app/app_harness.dart';

final enL10n = lookupAppLocalizations(const Locale('en'));
final arL10n = lookupAppLocalizations(const Locale('ar'));

/// Syncs in the test isolate with real HTTP (for the fake panel).
SyncRunner inlineRunner() =>
    InlineSyncRunner((config) => createSourceAdapter(config));

/// Alternates real time (sockets, the fake panel) with frames until [done]
/// holds; fails after [timeout].
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 30),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) {
      fail('Timed out waiting${reason == null ? '' : ' for $reason'}');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Lets pending socket timers (dio keep-alive) run out so the test ends
/// without pending timers.
Future<void> drainNetworkTimers(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump(const Duration(seconds: 30));
}

/// Presses [key] [times] times.
Future<void> pressN(
  WidgetTester tester,
  LogicalKeyboardKey key,
  int times,
) async {
  for (var i = 0; i < times; i++) {
    await press(tester, key);
  }
}

/// The value key of the widget that holds the primary focus (the nearest
/// ancestor with a string `ValueKey`), for readable failures.
String? focusedKey() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return null;
  if (ctx.widget.key case ValueKey<String>(:final value)) return value;
  String? found;
  ctx.visitAncestorElements((e) {
    if (e.widget.key case ValueKey<String>(:final value)) {
      found = value;
      return false;
    }
    return true;
  });
  return found;
}

/// Expects the primary focus inside the widget keyed [key].
void expectFocus(String key) {
  expect(
    focusedIn(ValueKey(key)),
    isTrue,
    reason: 'focus is on ${focusedKey()}, expected $key',
  );
}

/// Types [text] into the field keyed [key] (taps it first).
Future<void> typeInto(WidgetTester tester, String key, String text) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(EditableText),
    ),
    text,
  );
  await settle(tester);
}

/// Scrolls the widget keyed [key] into view and taps it.
Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await settle(tester);
  await tester.tap(finder);
  await settle(tester);
}

/// Presses Back (the system back button) and waits for the route
/// transition to finish.
Future<void> back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await settleRoute(tester);
}

/// Pumps long enough for a page transition to finish.
Future<void> settleRoute(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Completes [future] in real time (for work that touches sockets).
Future<T?> real<T>(WidgetTester tester, Future<T> Function() body) =>
    tester.runAsync(body);

/// [pumpApp] with extra provider [overrides] (feature providers).
Future<void> pumpAppWith(
  WidgetTester tester, {
  required AppDatabase db,
  DeviceCaps caps = phoneCaps,
  AppSettings settings = const AppSettings(),
  Widget Function(HomeTab tab)? pages,
  SyncRunner? runner,
  Clock? clock,
  List<Override> overrides = const [],
}) async {
  final size = caps.isTv ? const Size(960, 540) : const Size(390, 800);
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  addTearDown(() => applyFocusHighlightStrategy(tv: false));
  KeyRepeatThrottle.instance = KeyRepeatThrottle();
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceCapsProvider.overrideWithValue(caps),
        initialSettingsProvider.overrideWithValue(settings),
        ringLogProvider.overrideWithValue(RingLog()),
        autoSyncOnStartProvider.overrideWithValue(false),
        if (clock != null) clockProvider.overrideWithValue(clock),
        if (runner != null) syncRunnerProvider.overrideWithValue(runner),
        homePageBuilderProvider.overrideWithValue(pages ?? FakeTabPage.new),
        ...overrides,
      ],
      child: const IptvApp(),
    ),
  );
  await settle(tester);
}

/// The app's provider container.
ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(IptvApp)));

/// The text of the field keyed [key].
String fieldText(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;
