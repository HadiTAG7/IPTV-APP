import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/epg/epg_providers.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/player/ui/player_screen.dart';
import 'package:iptv_player/sources/models.dart';

import '../support/fake_epg_service.dart';
import 'support/player_harness.dart';

void main() {
  group('live OSD', () {
    forLocales((locale) {
      testWidgets(
        'Right shows the OSD; it hides after 5 s (${locale.languageCode})',
        (tester) async {
          final rig = PlayerRig()..autoPlay();
          final id = await seedLive(rig);
          await pumpPlayerApp(tester, rig, locale: locale);
          await openPlayerFor(tester, liveRequest(id));

          expect(find.byType(PlayerScreen), findsOneWidget);
          expect(rig.openedUrls, ['http://127.0.0.1:9/live/ch1.ts']);
          expect(rig.engine.kind, EngineKind.exo);
          expect(focusLabel, 'player');
          expect(find.byKey(const ValueKey('player-osd')), findsNothing);

          // OK opens the channel panel; Left/Right show the OSD.
          await press(tester, LogicalKeyboardKey.arrowRight);
          expect(find.byKey(const ValueKey('player-osd')), findsOneWidget);
          expect(focusLabel, 'player:osd-first');
          expect(focusedIn(const ValueKey('player-osd-channels')), isTrue);

          // Moving between buttons restarts the timer.
          await tester.pump(const Duration(seconds: 3));
          // The next button is on the reading-end side (left in Arabic).
          await press(
            tester,
            locale == ar
                ? LogicalKeyboardKey.arrowLeft
                : LogicalKeyboardKey.arrowRight,
          );
          expect(focusedIn(const ValueKey('player-osd-audio')), isTrue);
          await tester.pump(const Duration(seconds: 4));
          expect(find.byKey(const ValueKey('player-osd')), findsOneWidget);
          await tester.pump(const Duration(seconds: 1, milliseconds: 100));
          await settle(tester);
          expect(find.byKey(const ValueKey('player-osd')), findsNothing);
          expect(focusLabel, 'player');

          await disposeRig(tester, rig);
        },
      );
    });

    testWidgets('the OSD shows the channel, now/next and the clock', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await seedGuide(rig, id);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      await press(tester, LogicalKeyboardKey.arrowLeft);

      final osd = find.byKey(const ValueKey('player-osd'));
      expect(
        find.descendant(of: osd, matching: find.text('Channel 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: osd, matching: find.text('101')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: osd, matching: find.textContaining('Evening News')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: osd, matching: find.textContaining('Late Show')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('player-clock')), findsOneWidget);
      for (final b in [
        'channels',
        'audio',
        'subtitles',
        'aspect',
        'favorite',
        'switchPlayer',
        'guide',
        'stats',
      ]) {
        expect(find.byKey(ValueKey('player-osd-$b')), findsOneWidget);
      }
      await disposeRig(tester, rig);
    });

    testWidgets('outside a home tab Guide just closes the player; '
        'fullscreen playback is reported while it is open', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig);
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(launcherKey)),
      );
      expect(container.read(fullscreenPlaybackProvider), isFalse);
      await openPlayerFor(tester, liveRequest(id));
      expect(container.read(fullscreenPlaybackProvider), isTrue);

      await tester.sendKeyEvent(
        LogicalKeyboardKey.guide,
        physicalKey: PhysicalKeyboardKey.f1,
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
      expect(find.byKey(launcherKey), findsOneWidget);
      expect(rig.engine.calls, contains('stop'));
      expect(container.read(fullscreenPlaybackProvider), isFalse);
      await disposeRig(tester, rig);
    });

    testWidgets('a finished guide refresh brings new now/next to the OSD', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      final epg = FakeEpgService();
      await pumpPlayerApp(
        tester,
        rig,
        overrides: [epgServiceProvider.overrideWithValue(epg)],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(launcherKey)),
      );
      await openPlayerFor(tester, liveRequest(id));
      await press(tester, LogicalKeyboardKey.arrowRight);
      final osd = find.byKey(const ValueKey('player-osd'));
      expect(
        find.descendant(of: osd, matching: find.textContaining('Evening')),
        findsNothing,
      );

      // A refresh imports the guide (written here) and ends.
      container.read(guideRefreshProvider(id).notifier).refresh();
      await seedGuide(rig, id);
      await epg.finish(id);
      await settle(tester);
      expect(
        find.descendant(of: osd, matching: find.textContaining('Evening News')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: osd, matching: find.textContaining('Late Show')),
        findsOneWidget,
      );
      await disposeRig(tester, rig);
    });

    testWidgets('marks the channel as played once it plays; wakelock on', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      expect(rig.played, [(id, 'ch1')]);
      expect(rig.wakelock, contains(true));
      await disposeRig(tester, rig);
      expect(rig.wakelock.last, isFalse);
    });
  });

  group('banner', () {
    forLocales((locale) {
      testWidgets('shows on open, hides after 4 s; Info shows it again '
          '(${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedLive(rig);
        await seedGuide(rig, id);
        await pumpPlayerApp(tester, rig, locale: locale);
        await openPlayerFor(tester, liveRequest(id));
        final banner = find.byKey(const ValueKey('player-banner'));
        expect(banner, findsOneWidget);
        expect(
          find.descendant(of: banner, matching: find.text('Channel 1')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: banner,
            matching: find.textContaining('Evening News'),
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 4));
        expect(banner, findsNothing);

        await tester.sendKeyEvent(
          LogicalKeyboardKey.info,
          physicalKey: PhysicalKeyboardKey.f2,
        );
        await tester.pump();
        expect(banner, findsOneWidget);
        await tester.pump(const Duration(seconds: 5, milliseconds: 100));
        expect(banner, findsNothing);
        await disposeRig(tester, rig);
      });
    });

    testWidgets('a channel without a stream URL shows the failure card', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(
        tester,
        liveRequest(id).copyWith(
          item: const PlayableRef(kind: PlayableKind.live, key: 'missing'),
        ),
      );
      expect(find.byKey(const ValueKey('player-failure')), findsOneWidget);
      expect(find.text("This item can't be played."), findsOneWidget);
      expect(focusLabel, 'player:retry');
      expect(rig.openedUrls, isEmpty);
      await disposeRig(tester, rig);
    });
  });

  group('Back', () {
    forLocales((locale) {
      testWidgets(
        'hides the OSD first, then stops and closes (${locale.languageCode})',
        (tester) async {
          final rig = PlayerRig()..autoPlay();
          final id = await seedLive(rig);
          await pumpPlayerApp(tester, rig, locale: locale);
          var closed = false;
          final done = await openPlayerFor(tester, liveRequest(id));
          ignore(done.then((_) => closed = true));

          await press(tester, LogicalKeyboardKey.arrowRight);
          expect(find.byKey(const ValueKey('player-osd')), findsOneWidget);

          await tester.binding.handlePopRoute();
          await settle(tester);
          expect(find.byKey(const ValueKey('player-osd')), findsNothing);
          expect(find.byType(PlayerScreen), findsOneWidget);
          expect(rig.engine.calls, isNot(contains('stop')));

          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.byType(PlayerScreen), findsNothing);
          expect(closed, isTrue);
          expect(rig.engine.calls, contains('stop'));
          // The provider disposed the controller and its engine.
          await tester.pump(const Duration(milliseconds: 100));
          expect(rig.engine.disposed, isTrue);
          await disposeRig(tester, rig);
        },
      );
    });

    testWidgets('Escape (desktop Back) behaves the same', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.byKey(const ValueKey('player-osd')), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byKey(const ValueKey('player-osd')), findsNothing);
      expect(find.byType(PlayerScreen), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
      await disposeRig(tester, rig);
    });
  });
}
