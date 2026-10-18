import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/ui/player_screen.dart';
import 'package:iptv_player/sources/models.dart';

import 'support/player_harness.dart';

const _osd = ValueKey('player-osd');
const _back = ValueKey('player-osd-back');
const _fullscreenButton = ValueKey('player-osd-fullscreen');

/// Desktop single clicks wait out the double-click timeout.
Future<void> _click(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 400));
  await settle(tester);
}

Future<void> _doubleClick(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(at);
  await settle(tester);
}

MouseCursor _cursor(WidgetTester tester) => tester
    .widget<MouseRegion>(find.byKey(const ValueKey('player-mouse')))
    .cursor;

void main() {
  group('desktop window fullscreen', () {
    forLocales((locale) {
      testWidgets('the player opens fullscreen and gives the window back '
          '(${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedLive(rig);
        await pumpPlayerApp(
          tester,
          rig,
          tv: false,
          locale: locale,
          platform: TargetPlatform.windows,
        );
        expect(rig.window, isEmpty);
        await openPlayerFor(tester, liveRequest(id));
        expect(rig.window, ['enter']);

        // Escape leaves fullscreen first and keeps playing.
        await press(tester, LogicalKeyboardKey.escape);
        expect(rig.window, ['enter', 'exit']);
        expect(find.byType(PlayerScreen), findsOneWidget);
        expect(rig.engine.count('stop'), 0);

        // Then it is Back.
        await press(tester, LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(PlayerScreen), findsNothing);
        expect(rig.window, ['enter', 'exit']);
        await disposeRig(tester, rig);
      });
    });

    testWidgets('closing the player in fullscreen gives the window back', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(
        tester,
        rig,
        tv: false,
        platform: TargetPlatform.linux,
      );
      await openPlayerFor(tester, liveRequest(id));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
      expect(rig.window, ['enter', 'exit']);
      await disposeRig(tester, rig);
    });

    testWidgets('F and F11 toggle; the choice decides the next player', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(
        tester,
        rig,
        tv: false,
        platform: TargetPlatform.windows,
      );
      await openPlayerFor(tester, liveRequest(id));
      await press(tester, LogicalKeyboardKey.keyF);
      expect(rig.window, ['enter', 'exit']);
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);

      // A window was chosen: the next player keeps it.
      await openPlayerFor(tester, liveRequest(id));
      expect(rig.window, ['enter', 'exit']);
      await press(tester, LogicalKeyboardKey.f11);
      expect(rig.window, ['enter', 'exit', 'enter']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(rig.window, ['enter', 'exit', 'enter', 'exit']);

      // Fullscreen was chosen again.
      await openPlayerFor(tester, liveRequest(id));
      expect(rig.window.last, 'enter');
      await disposeRig(tester, rig);
    });

    testWidgets('Escape leaving fullscreen is not a choice', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(
        tester,
        rig,
        tv: false,
        platform: TargetPlatform.windows,
      );
      await openPlayerFor(tester, liveRequest(id));
      await press(tester, LogicalKeyboardKey.escape);
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await openPlayerFor(tester, liveRequest(id));
      expect(rig.window, ['enter', 'exit', 'enter']);
      await disposeRig(tester, rig);
    });

    testWidgets('double clicks toggle fullscreen and never seek', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay(duration: const Duration(minutes: 90));
      final id = await seedVod(rig);
      await pumpPlayerApp(
        tester,
        rig,
        tv: false,
        platform: TargetPlatform.windows,
      );
      await openPlayerFor(tester, movieRequest(id));
      rig.engine.setState(position: const Duration(minutes: 1));
      await _doubleClick(tester, const Offset(1000, 360));
      expect(rig.window, ['enter', 'exit']);
      await _doubleClick(tester, const Offset(200, 360));
      expect(rig.window, ['enter', 'exit', 'enter']);
      await tester.pump(const Duration(seconds: 1));
      expect(rig.engine.calls.where((c) => c.startsWith('seek')), isEmpty);
      await disposeRig(tester, rig);
    });

    forLocales((locale) {
      testWidgets('the OSD has Back and a fullscreen button '
          '(${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedLive(rig);
        await pumpPlayerApp(
          tester,
          rig,
          tv: false,
          locale: locale,
          platform: TargetPlatform.windows,
        );
        await openPlayerFor(tester, liveRequest(id));
        await _click(tester, const Offset(640, 360));
        expect(find.byKey(_osd), findsOneWidget);

        final exitLabel = locale == ar
            ? 'خروج من الشاشة الكاملة'
            : 'Exit full screen';
        expect(find.byTooltip(exitLabel), findsOneWidget);
        await tester.tap(find.byKey(_fullscreenButton));
        await settle(tester);
        expect(rig.window, ['enter', 'exit']);
        expect(
          find.byTooltip(locale == ar ? 'شاشة كاملة' : 'Full screen'),
          findsOneWidget,
        );

        // Back sits at the start: the right edge in Arabic.
        final back = tester.getCenter(find.byKey(_back));
        final fullscreen = tester.getCenter(find.byKey(_fullscreenButton));
        expect(back.dx < fullscreen.dx, locale == en);

        // Back leaves the channel in one press, OSD or not.
        await tester.tap(find.byKey(_back));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerScreen), findsNothing);
        expect(rig.engine.count('stop'), greaterThan(0));
        await disposeRig(tester, rig);
      });
    });

    testWidgets('Back on a movie leaves and saves the position', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay(duration: const Duration(minutes: 90));
      final id = await seedVod(rig);
      await pumpPlayerApp(
        tester,
        rig,
        tv: false,
        platform: TargetPlatform.windows,
      );
      await openPlayerFor(tester, movieRequest(id));
      rig.engine.setState(position: const Duration(minutes: 12));
      await tester.pump();
      await _click(tester, const Offset(640, 360));
      await tester.tap(find.byKey(_back));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
      expect(rig.window, ['enter', 'exit']);
      final saved = await rig.db.progressDao.progressFor(
        id,
        PlayableKind.movie,
        'm1',
      );
      expect(saved?.position, const Duration(minutes: 12));
      await disposeRig(tester, rig);
    });

    testWidgets('moving the mouse shows the OSD; the cursor hides with it', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(
        tester,
        rig,
        tv: false,
        platform: TargetPlatform.windows,
      );
      await openPlayerFor(tester, liveRequest(id));
      expect(find.byKey(_osd), findsNothing);
      expect(_cursor(tester), SystemMouseCursors.none);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(600, 300));
      await mouse.moveTo(const Offset(640, 360));
      await settle(tester);
      expect(find.byKey(_osd), findsOneWidget);
      expect(_cursor(tester), MouseCursor.defer);

      // Moving keeps it up; resting hides it (and the cursor).
      await tester.pump(const Duration(seconds: 4));
      await mouse.moveTo(const Offset(650, 360));
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(_osd), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(find.byKey(_osd), findsNothing);
      expect(_cursor(tester), SystemMouseCursors.none);
      await disposeRig(tester, rig);
    });

    testWidgets('a player opened while one closes keeps fullscreen', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(
        tester,
        rig,
        tv: false,
        platform: TargetPlatform.windows,
      );
      await openPlayerFor(tester, liveRequest(id));
      await tester.binding.handlePopRoute();
      await tester.pump();
      // The first player is still on its way out.
      await openPlayerFor(tester, liveRequest(id, key: 'ch2'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(rig.window, ['enter', 'exit', 'enter']);
      await disposeRig(tester, rig);
    });
  });

  group('Back button on other devices', () {
    forLocales((locale) {
      testWidgets('phones get Back in the OSD and no window calls '
          '(${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedLive(rig);
        await pumpPlayerApp(tester, rig, tv: false, locale: locale);
        await openPlayerFor(tester, liveRequest(id));
        await tester.tapAt(const Offset(195, 400));
        await settle(tester);
        expect(find.byKey(_osd), findsOneWidget);
        expect(find.byKey(_fullscreenButton), findsNothing);
        // F is no shortcut here.
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.pump();
        await tester.tap(find.byKey(_back));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerScreen), findsNothing);
        expect(rig.window, isEmpty);
        await disposeRig(tester, rig);
      });
    });

    testWidgets('TVs keep the remote Back key only', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byKey(_osd), findsOneWidget);
      expect(find.byKey(_back), findsNothing);
      expect(find.byKey(_fullscreenButton), findsNothing);
      expect(find.byKey(const ValueKey('player-mouse')), findsNothing);
      await disposeRig(tester, rig);
    });
  });
}
