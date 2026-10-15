import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/ui/player_screen.dart';
import 'package:iptv_player/sources/models.dart';

import 'support/player_harness.dart';

Future<void> _background(WidgetTester tester) async {
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
    await tester.pump();
  }
  await settle(tester);
}

Future<void> _foreground(WidgetTester tester) async {
  for (final s in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
    await tester.pump();
  }
  await settle(tester);
}

const _landscape = [
  'DeviceOrientation.landscapeLeft',
  'DeviceOrientation.landscapeRight',
];

void main() {
  group('app lifecycle', () {
    testWidgets('live stops in the background and reopens on return', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      expect(rig.engine.count('stop'), 0);

      await _background(tester);
      expect(rig.engine.count('stop'), 1);
      expect(rig.wakelock.last, isFalse);
      expect(rig.openedUrls, hasLength(1));

      await _foreground(tester);
      expect(rig.openedUrls, [
        'http://127.0.0.1:9/live/ch1.ts',
        'http://127.0.0.1:9/live/ch1.ts',
      ]);
      expect(rig.wakelock.last, isTrue);
      await disposeRig(tester, rig);
    });

    testWidgets('VOD pauses, saves progress and resumes', (tester) async {
      final rig = PlayerRig()..autoPlay(duration: const Duration(minutes: 90));
      final id = await seedVod(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, movieRequest(id));
      rig.engine.setState(position: const Duration(minutes: 12));
      await tester.pump();

      await _background(tester);
      expect(rig.engine.calls, contains('pause'));
      expect(rig.engine.count('stop'), 0);
      final saved = await rig.db.progressDao.progressFor(
        id,
        PlayableKind.movie,
        'm1',
      );
      expect(saved?.position, const Duration(minutes: 12));

      final plays = rig.engine.count('play');
      await _foreground(tester);
      expect(rig.engine.count('play'), plays + 1);
      expect(rig.engine.state.value.playing, isTrue);
      await disposeRig(tester, rig);
    });
  });

  group('orientation', () {
    forLocales((locale) {
      testWidgets('phones are forced to landscape while the player is open '
          '(${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedLive(rig);
        await pumpPlayerApp(tester, rig, tv: false, locale: locale);
        expect(rig.callsOf('SystemChrome.setPreferredOrientations'), isEmpty);
        await openPlayerFor(tester, liveRequest(id));
        final calls = rig.callsOf('SystemChrome.setPreferredOrientations');
        expect(calls, hasLength(1));
        expect(calls.single.arguments, _landscape);
        expect(
          rig.callsOf('SystemChrome.setEnabledSystemUIMode').single.arguments,
          'SystemUiMode.immersiveSticky',
        );

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(PlayerScreen), findsNothing);
        final after = rig.callsOf('SystemChrome.setPreferredOrientations');
        expect(after, hasLength(2));
        expect(after.last.arguments, isEmpty);
        expect(
          rig.callsOf('SystemChrome.setEnabledSystemUIMode').last.arguments,
          'SystemUiMode.edgeToEdge',
        );
        await disposeRig(tester, rig);
      });
    });

    testWidgets('TVs never touch the orientation', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(rig.callsOf('SystemChrome.setPreferredOrientations'), isEmpty);
      expect(rig.callsOf('SystemChrome.setEnabledSystemUIMode'), isEmpty);
      await disposeRig(tester, rig);
    });
  });

  group('phone gestures', () {
    forLocales((locale) {
      testWidgets('tap toggles the OSD (${locale.languageCode})', (
        tester,
      ) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedLive(rig);
        await pumpPlayerApp(tester, rig, tv: false, locale: locale);
        await openPlayerFor(tester, liveRequest(id));
        final osd = find.byKey(const ValueKey('player-osd'));
        await tester.tapAt(const Offset(195, 100));
        await settle(tester);
        expect(osd, findsOneWidget);
        // Buttons work by touch (the row scrolls on narrow screens).
        final stats = find.byKey(const ValueKey('player-osd-stats'));
        await tester.ensureVisible(stats);
        await settle(tester);
        await tester.tap(stats);
        await settle(tester);
        expect(find.byKey(const ValueKey('player-stats')), findsOneWidget);
        await tester.tapAt(const Offset(195, 320));
        await settle(tester);
        expect(osd, findsNothing);
        await disposeRig(tester, rig);
      });

      testWidgets('double tap seeks 10 s by screen half, never mirrored '
          '(${locale.languageCode})', (tester) async {
        final rig = PlayerRig()
          ..autoPlay(duration: const Duration(minutes: 90));
        final id = await seedVod(rig);
        await pumpPlayerApp(tester, rig, tv: false, locale: locale);
        await openPlayerFor(tester, movieRequest(id));
        rig.engine.setState(position: const Duration(minutes: 1));

        Future<void> doubleTap(Offset at) async {
          await tester.tapAt(at);
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tapAt(at);
          await tester.pump(const Duration(milliseconds: 700));
        }

        await doubleTap(const Offset(350, 100));
        expect(rig.engine.calls.where((c) => c.startsWith('seek')), [
          'seek 70000',
        ]);
        await doubleTap(const Offset(40, 100));
        expect(
          rig.engine.calls.where((c) => c.startsWith('seek')).last,
          'seek 60000',
        );
        await disposeRig(tester, rig);
      });
    });
  });
}
