// Detaching the live channel into a separate window (desktop).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/ui/player_screen.dart';
import 'package:iptv_player/tv/dpad_shortcuts.dart';

import 'support/fake_detached_windows.dart';
import 'support/player_harness.dart';

const _detachButton = ValueKey('player-osd-detach');

/// Shows the OSD with the mouse (desktop), once the window has settled
/// into fullscreen (moves right after it are ignored).
Future<void> _hover(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: const Offset(600, 300));
  await mouse.moveTo(const Offset(640, 360));
  await settle(tester);
}

Future<RecordingDetachedWindows> _pump(
  WidgetTester tester,
  PlayerRig rig, {
  Locale locale = en,
  TargetPlatform platform = TargetPlatform.windows,
  bool tv = false,
}) async {
  final windows = RecordingDetachedWindows(rig);
  await pumpPlayerApp(
    tester,
    rig,
    tv: tv,
    locale: locale,
    platform: platform,
    overrides: [detachedWindowsProvider.overrideWith(() => windows)],
  );
  return windows;
}

void main() {
  group('desktop live', () {
    forLocales((locale) {
      testWidgets('the OSD button stops the stream, closes the player, then '
          'opens the window (${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedXtream(rig);
        final windows = await _pump(tester, rig, locale: locale);
        final l10n = await AppLocalizations.delegate.load(locale);
        await openPlayerFor(tester, xtreamRequest(id, '501'));
        expect(rig.window, ['enter']);
        final url = rig.engine.lastRequest!.url;

        await _hover(tester);
        expect(find.byKey(_detachButton), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(_detachButton),
            matching: find.text(l10n.playerDetach),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(_detachButton));
        await tester.pumpAndSettle();

        expect(find.byType(PlayerScreen), findsNothing);
        final request = windows.detached.single;
        expect(request.sourceId, id);
        expect(request.channelKey, '501');
        expect(request.title, 'Panel News');
        expect(request.stream.url, url);
        expect(request.stream.isLive, isTrue);
        expect(request.maxConnections, 1);
        expect(request.secrets, contains('Secret-Pass-9'));
        expect(request.locale, locale.languageCode);
        // One connection: the player's stream was stopped first.
        final log = windows.engineLogAtDetach.single;
        expect(log.where((l) => l.endsWith('.open $url')), hasLength(1));
        expect(log.last, endsWith('.stop'));
        expect(rig.engines.created, hasLength(1));
        // The window left fullscreen.
        expect(rig.window, ['enter', 'exit']);
        await disposeRig(tester, rig);
      });
    });

    testWidgets('D detaches; on Linux too', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      final windows = await _pump(tester, rig, platform: TargetPlatform.linux);
      await openPlayerFor(tester, liveRequest(id, key: 'ch2'));
      await press(tester, LogicalKeyboardKey.keyD);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
      expect(windows.detached.single.channelKey, 'ch2');
      expect(windows.detached.single.title, 'Channel 2');
      expect(windows.detached.single.maxConnections, isNull);
      expect(windows.engineLogAtDetach.single.last, endsWith('.stop'));
      await disposeRig(tester, rig);
    });

    testWidgets('the options list offers it', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      final windows = await _pump(tester, rig, locale: ar);
      final l10n = await AppLocalizations.delegate.load(ar);
      await openPlayerFor(tester, liveRequest(id));
      await press(tester, menuKey);
      expect(find.text(l10n.playerDetach), findsOneWidget);
      await tester.tap(find.text(l10n.playerDetach));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
      expect(windows.detached, hasLength(1));
      await disposeRig(tester, rig);
    });

    testWidgets('a window that cannot open says so', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      final windows = await _pump(tester, rig);
      windows.fail = true;
      await openPlayerFor(tester, liveRequest(id));
      await press(tester, LogicalKeyboardKey.keyD);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
      expect(find.text("Couldn't open the separate window."), findsOneWidget);
      expect(rig.log.dump(), contains('separate window failed'));
      await disposeRig(tester, rig);
    });
  });

  group('never offered', () {
    testWidgets('on Android TV and phones', (tester) async {
      for (final tv in [true, false]) {
        final rig = PlayerRig()..autoPlay();
        final id = await seedLive(rig);
        final windows = await _pump(
          tester,
          rig,
          tv: tv,
          platform: TargetPlatform.android,
        );
        final l10n = await AppLocalizations.delegate.load(en);
        await openPlayerFor(tester, liveRequest(id));
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(find.byKey(const ValueKey('player-osd')), findsOneWidget);
        expect(find.byKey(_detachButton), findsNothing);
        await press(tester, LogicalKeyboardKey.keyD);
        expect(find.byType(PlayerScreen), findsOneWidget);
        await tester.binding.handlePopRoute();
        await settle(tester);
        await press(tester, menuKey);
        expect(find.text(l10n.playerDetach), findsNothing);
        expect(windows.detached, isEmpty);
        await disposeRig(tester, rig);
      }
    });

    testWidgets('for movies on desktop', (tester) async {
      final rig = PlayerRig()..autoPlay(duration: const Duration(hours: 1));
      final id = await seedVod(rig);
      final windows = await _pump(tester, rig);
      await openPlayerFor(tester, movieRequest(id));
      await _hover(tester);
      expect(find.byKey(const ValueKey('player-osd')), findsOneWidget);
      expect(find.byKey(_detachButton), findsNothing);
      await press(tester, LogicalKeyboardKey.keyD);
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(windows.detached, isEmpty);
      await disposeRig(tester, rig);
    });
  });
}
