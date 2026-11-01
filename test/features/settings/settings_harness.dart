// Pumps the real app (IptvApp + RootGate + home shell) with the real
// Settings and Help screens on an in-memory database. Other tabs and pushed
// pages are simple placeholders, so these tests do not depend on other
// features.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
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
import 'package:iptv_player/epg/epg_providers.dart';
import 'package:iptv_player/features/help/help_screen.dart';
import 'package:iptv_player/features/help/providers.dart';
import 'package:iptv_player/features/settings/providers.dart';
import 'package:iptv_player/features/settings/settings_screen.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/tv/dpad_shortcuts.dart';
import 'package:iptv_player/tv/key_repeat.dart';

import '../../support/fake_epg_service.dart';

const tvCaps = DeviceCaps(uiModeTv: true, leanback: true, touch: false);
const phoneCaps = DeviceCaps();

final en = lookupAppLocalizations(const Locale('en'));
final ar = lookupAppLocalizations(const Locale('ar'));

/// Text of the placeholder page shown for [tab].
String stubPageText(HomeTab tab) => '${tab.name}-page';

Widget _page(HomeTab tab) => switch (tab) {
  HomeTab.settings => const SettingsScreen(),
  HomeTab.help => const HelpScreen(),
  _ => Center(child: Text(stubPageText(tab))),
};

/// One call of the injected guide refresh.
typedef RefreshCall = ({int sourceId, bool force});

/// One call of the injected "Add as source".
typedef PrefillCall = ({String url, String name});

/// The pumped app and what it recorded.
class SettingsHarness {
  SettingsHarness(this.db, this.sourceId);

  final AppDatabase db;
  final int sourceId;

  /// The app's log.
  final log = RingLog();
  final refreshCalls = <RefreshCall>[];
  final prefillCalls = <PrefillCall>[];

  /// The app's provider container.
  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(IptvApp)));

  /// Saved settings JSON (after queued writes have finished).
  Future<Map<String, Object?>> savedSettings(WidgetTester tester) async {
    await container(tester).read(settingsProvider.notifier).flush();
    final json = await db.settingsDao.getJson(kAppSettingsKey);
    return (json! as Map).cast<String, Object?>();
  }

  Future<SourceRow> source() async => (await db.sourcesDao.byId(sourceId))!;

  /// Unmounts the app (letting snack bars and animations end) and closes
  /// the database. Call at the end of every test.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    await db.close();
  }
}

/// Pumps the app with one source ("Home", already synced).
///
/// [seed] runs before the app starts. [refresh] replaces the recording guide
/// refresh action. With [prefill] the Help screen gets an "Add as source"
/// action that records its calls. [overrides] come after the harness's own.
Future<SettingsHarness> pumpSettingsApp(
  WidgetTester tester, {
  bool tv = true,
  Locale locale = const Locale('en'),
  AppSettings settings = const AppSettings(),
  TargetPlatform platform = TargetPlatform.android,
  DeviceCaps? caps,
  String? version = '1.2.3 (45)',
  bool prefill = false,
  RefreshGuideAction? refresh,
  Future<void> Function(AppDatabase db, int sourceId)? seed,
  List<Override> overrides = const [],
}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = AppDatabase(NativeDatabase.memory());
  final sourceId = await db.sourcesDao.create(
    const SourceConfig(
      kind: SourceKind.m3uUrl,
      url: 'http://127.0.0.1:9/home.m3u',
      name: 'Home',
    ),
  );
  await db.sourcesDao.markSynced(sourceId, DateTime.now());
  if (seed != null) await seed(db, sourceId);
  final h = SettingsHarness(db, sourceId);

  final size = tv ? const Size(960, 540) : const Size(390, 800);
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  addTearDown(() => applyFocusHighlightStrategy(tv: false));
  KeyRepeatThrottle.instance = KeyRepeatThrottle();

  final language = switch (locale.languageCode) {
    'ar' => AppLocaleSetting.ar,
    _ => AppLocaleSetting.en,
  };
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceCapsProvider.overrideWithValue(caps ?? (tv ? tvCaps : phoneCaps)),
        initialSettingsProvider.overrideWithValue(
          settings.locale == AppLocaleSetting.auto
              ? settings.copyWith(locale: language)
              : settings,
        ),
        ringLogProvider.overrideWithValue(h.log),
        autoSyncOnStartProvider.overrideWithValue(false),
        // No guide downloads: the schedule in IptvApp is always alive.
        epgServiceProvider.overrideWithValue(FakeEpgService()),
        targetPlatformProvider.overrideWithValue(platform),
        appVersionProvider.overrideWith((ref) async => version),
        refreshGuideActionProvider.overrideWithValue(
          refresh ??
              (id, {required force}) async =>
                  h.refreshCalls.add((sourceId: id, force: force)),
        ),
        if (prefill)
          addSourcePrefillProvider.overrideWithValue(
            (context, {required url, required name}) async =>
                h.prefillCalls.add((url: url, name: name)),
          ),
        homePageBuilderProvider.overrideWithValue(_page),
        ...overrides,
      ],
      child: const IptvApp(),
    ),
  );
  await settle(tester);
  return h;
}

/// Lets drift streams deliver and animations finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

/// Presses [key] and settles.
Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await settle(tester);
}

/// Arrow toward the reading end (right in English, left in Arabic).
LogicalKeyboardKey toEnd(bool rtl) =>
    rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight;

/// Arrow toward the reading start.
LogicalKeyboardKey toStart(bool rtl) =>
    rtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft;

/// Whether the primary focus is inside the widget with [key].
bool focusedIn(Key key) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  if (ctx.widget.key == key) return true;
  var found = false;
  ctx.visitAncestorElements((e) {
    if (e.widget.key == key) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// Describes where focus is (for failure messages).
String focusDescription() =>
    FocusManager.instance.primaryFocus?.toString() ?? 'nothing';

const settingsRail = ValueKey('rail-settings');

/// TV: walks the rail down to Settings and enters the page with OK.
Future<void> openSettingsTv(WidgetTester tester) async {
  for (var i = 0; i < HomeTab.tvTabs.indexOf(HomeTab.settings); i++) {
    await press(tester, LogicalKeyboardKey.arrowDown);
  }
  expect(focusedIn(settingsRail), isTrue, reason: focusDescription());
  await press(tester, LogicalKeyboardKey.select);
}

/// Phone: More, then Settings (a pushed page).
Future<void> openSettingsPhone(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav-more')));
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('more-settings')));
  await settle(tester);
}

/// Presses [arrow] until focus is inside [key] (at most [max] presses).
Future<void> moveTo(
  WidgetTester tester,
  Key key, {
  LogicalKeyboardKey arrow = LogicalKeyboardKey.arrowDown,
  int max = 40,
}) async {
  for (var i = 0; i < max && !focusedIn(key); i++) {
    await press(tester, arrow);
  }
  expect(focusedIn(key), isTrue, reason: 'to $key: ${focusDescription()}');
}

/// Whether the widget found by [finder] lies fully inside the screen.
bool onScreen(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  final view = tester.view;
  final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
  return rect.top >= screen.top - 1 && rect.bottom <= screen.bottom + 1;
}
