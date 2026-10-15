// Pumps the real app (IptvApp + RootGate) on an in-memory database.
import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/app.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/core/platform/device_caps.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/sources/sync/sync_service.dart';
import 'package:iptv_player/tv/dpad_shortcuts.dart';
import 'package:iptv_player/tv/key_repeat.dart';
import 'package:iptv_player/tv/tv_focusable.dart';

const tvCaps = DeviceCaps(uiModeTv: true, leanback: true, touch: false);
const phoneCaps = DeviceCaps();

AppDatabase openAppTestDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

Future<int> addTestSource(
  AppDatabase db, {
  String name = 'Home',
  DateTime? lastSyncAt,
}) async {
  final id = await db.sourcesDao.create(
    SourceConfig(
      kind: SourceKind.m3uUrl,
      url: 'http://127.0.0.1:9/$name.m3u',
      name: name,
    ),
  );
  if (lastSyncAt != null) await db.sourcesDao.markSynced(id, lastSyncAt);
  return id;
}

/// A page with two focusable buttons, `<tab>-A` and `<tab>-B`, side by side.
class FakeTabPage extends StatelessWidget {
  const FakeTabPage(this.tab, {super.key});

  final HomeTab tab;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.topStart,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in ['A', 'B'])
          Padding(
            padding: const EdgeInsets.all(8),
            child: TvFocusable(
              key: ValueKey('${tab.name}-$s'),
              onSelect: () {},
              child: SizedBox(
                width: 120,
                height: 48,
                child: Text('${tab.name}-$s'),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Pumps [IptvApp] with [db]. Auto-sync is off unless [autoSync].
Future<void> pumpApp(
  WidgetTester tester, {
  required AppDatabase db,
  DeviceCaps caps = phoneCaps,
  AppSettings settings = const AppSettings(),
  Size? logicalSize,
  double devicePixelRatio = 2,
  bool fakePages = false,
  Widget Function(HomeTab tab)? pages,
  bool autoSync = false,
  Clock? clock,
  SyncRunner? runner,
  void Function()? onExit,
}) async {
  final size =
      logicalSize ?? (caps.isTv ? const Size(960, 540) : const Size(390, 800));
  tester.view.physicalSize = size * devicePixelRatio;
  tester.view.devicePixelRatio = devicePixelRatio;
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
        autoSyncOnStartProvider.overrideWithValue(autoSync),
        if (clock != null) clockProvider.overrideWithValue(clock),
        if (runner != null) syncRunnerProvider.overrideWithValue(runner),
        if (onExit != null) appExitProvider.overrideWithValue(onExit),
        if (pages != null || fakePages)
          homePageBuilderProvider.overrideWithValue(pages ?? FakeTabPage.new),
      ],
      child: const IptvApp(),
    ),
  );
  await settle(tester);
}

/// Lets drift streams deliver and frames settle.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Unmounts the app and closes [db].
Future<void> disposeApp(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  await db.close();
}

/// Presses [key] and lets frames settle.
Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await settle(tester);
}

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

/// A runner that never touches the network: it reports one progress event
/// and finishes when the test says so.
class ManualSyncRunner implements SyncRunner {
  final tasks = <SyncTask>[];
  final _runs = <Completer<SyncProgress>>[];

  @override
  SyncExecution start(
    AppDatabase db,
    SyncTask task,
    void Function(SyncProgress progress) onProgress,
  ) {
    tasks.add(task);
    final run = Completer<SyncProgress>();
    _runs.add(run);
    onProgress(
      SyncProgress(sourceId: task.sourceId, phase: SyncPhase.live, channels: 5),
    );
    return SyncExecution(run.future, () {
      if (!run.isCompleted) {
        run.complete(
          SyncProgress(sourceId: task.sourceId, phase: SyncPhase.cancelled),
        );
      }
    });
  }

  void finish(SyncProgress result) => _runs.last.complete(result);
}
