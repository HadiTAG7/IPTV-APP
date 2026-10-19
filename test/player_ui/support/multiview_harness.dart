// What the split-screen tests share: a desktop app with the player, a free
// M3U source next to the Xtream one, and finders for the tiles. Synthetic
// data only (127.0.0.1 URLs, made-up names).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/multiview/multiview_screen.dart';
import 'package:iptv_player/player/ui/play_request.dart';
import 'package:iptv_player/sources/models.dart';

import '../../support/fake_engine.dart';
import 'fake_detached_windows.dart';
import 'player_harness.dart';

/// The free list's channel [key]'s stream.
String freeUrl(String key) => 'http://127.0.0.1:9/free/$key.m3u8';

/// An M3U source "Free TV" (no connection limit) with channels `f1..fN`
/// ("Free 1"...).
Future<int> seedFree(PlayerRig rig, {int count = 3}) async {
  final db = rig.db;
  final id = await db.sourcesDao.create(
    const SourceConfig(
      kind: SourceKind.m3uUrl,
      url: 'http://127.0.0.1:9/free.m3u',
      name: 'Free TV',
    ),
  );
  final gen = await db.catalogDao.beginGeneration(id);
  await db.catalogDao.upsertCategories(id, gen, const [
    CategoryData(kind: ContentKind.live, key: 'free', name: 'Free'),
  ]);
  await db.catalogDao.upsertChannels(id, gen, [
    for (var i = 1; i <= count; i++)
      ChannelData(
        key: 'f$i',
        name: 'Free $i',
        num: 300 + i,
        url: freeUrl('f$i'),
        categoryKeys: const ['free'],
      ),
  ]);
  await db.catalogDao.commitGeneration(id, gen);
  return id;
}

/// A live request for the free channel [key].
PlayRequest freeRequest(int sourceId, String key) => PlayRequest(
  sourceId: sourceId,
  item: PlayableRef(kind: PlayableKind.live, key: key, url: freeUrl(key)),
  categoryKey: 'free',
);

/// Pumps the desktop app (Windows unless [platform]) with recorded
/// separate windows.
Future<RecordingDetachedWindows> pumpSplitApp(
  WidgetTester tester,
  PlayerRig rig, {
  Locale locale = en,
  TargetPlatform platform = TargetPlatform.windows,
  bool tv = false,
  List<DetachedViewer> windows = const [],
  List<Override> overrides = const [],
}) async {
  final recorded = RecordingDetachedWindows(rig, initial: windows);
  await pumpPlayerApp(
    tester,
    rig,
    tv: tv,
    locale: locale,
    platform: platform,
    overrides: [
      detachedWindowsProvider.overrideWith(() => recorded),
      ...overrides,
    ],
  );
  return recorded;
}

/// Opens the player on [request] and splits the screen with S.
Future<void> openSplit(WidgetTester tester, PlayRequest request) async {
  await openPlayerFor(tester, request);
  await press(tester, LogicalKeyboardKey.keyS);
  await settleSplit(tester);
}

/// Lets the player close, the split screen open and its tiles start.
Future<void> settleSplit(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await settle(tester);
  }
}

/// The tile in grid place [slot] (0-based).
Finder slot(int slot) => find.byKey(ValueKey('multiview-slot-$slot'));

Finder inSlot(int i, Finder finder) =>
    find.descendant(of: slot(i), matching: finder);

/// Whether the tile in [i] has the gold border of the active tile.
bool isActive(int i) => inSlot(
  i,
  find.byKey(const ValueKey('multiview-active')),
).evaluate().isNotEmpty;

/// The channel picker.
const pickerKey = ValueKey('channel-panel');

/// The engine that played the stream whose URL contains [part] last.
FakeEngine engineFor(PlayerRig rig, String part) => rig.engines.created
    .lastWhere((e) => e.opened.any((r) => r.url.contains(part)));

/// Opens the picker with the tile's big "+", waits past its click guard,
/// shows [sourceId]'s channels when given and picks [name].
Future<void> addChannel(
  WidgetTester tester,
  int i,
  String name, {
  int? sourceId,
}) async {
  await tester.tap(inSlot(i, find.byKey(const ValueKey('multiview-add'))));
  await openedPicker(tester);
  await pickChannel(tester, name, sourceId: sourceId);
}

/// Waits for the picker to read its lists and take clicks.
Future<void> openedPicker(WidgetTester tester) async {
  await settle(tester);
  await tester.pump(const Duration(milliseconds: 400));
  await settle(tester);
}

/// In the open picker: shows [sourceId]'s channels when given, then picks
/// [name].
Future<void> pickChannel(
  WidgetTester tester,
  String name, {
  int? sourceId,
}) async {
  expect(find.byKey(pickerKey), findsOneWidget);
  if (sourceId != null) {
    await tester.tap(find.byKey(ValueKey('multiview-source-$sourceId')));
    await openedPicker(tester);
  }
  await tester.tap(
    find.descendant(of: find.byKey(pickerKey), matching: find.text(name)),
  );
  await settleSplit(tester);
}

/// A mouse over the window (at [at]), once the window settled (moves right
/// after a fullscreen change are ignored).
Future<TestGesture> mouseAt(WidgetTester tester, Offset at) async {
  await tester.pump(const Duration(seconds: 1));
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: at - const Offset(5, 5));
  await mouse.moveTo(at);
  await settle(tester);
  return mouse;
}

/// The app's provider container.
ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MultiViewScreen)));

/// Double clicks [finder].
Future<void> doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 80));
  await tester.tap(finder);
  await settle(tester);
}

/// Clicks [finder] and waits past the double-click timeout.
Future<void> click(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
  await settle(tester);
}
