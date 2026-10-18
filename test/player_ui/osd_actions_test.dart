import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/player/ui/player_screen.dart';
import 'package:iptv_player/sources/models.dart';

import 'support/player_harness.dart';

/// Opens the OSD and moves to the button [name] with the remote.
Future<void> focusOsdButton(
  WidgetTester tester,
  String name, {
  Locale locale = en,
}) async {
  if (find.byKey(const ValueKey('player-osd')).evaluate().isEmpty) {
    await press(tester, LogicalKeyboardKey.select);
  }
  final next = locale == ar
      ? LogicalKeyboardKey.arrowLeft
      : LogicalKeyboardKey.arrowRight;
  for (var i = 0; i < 10; i++) {
    if (focusedIn(ValueKey('player-osd-$name'))) return;
    await press(tester, next);
  }
  fail('OSD button $name not reached');
}

void main() {
  group('aspect ratio', () {
    forLocales((locale) {
      testWidgets('is picked from the OSD and saved per channel '
          '(${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedLive(rig);
        await pumpPlayerApp(
          tester,
          rig,
          locale: locale,
          settings: const AppSettings(defaultAspect: AspectMode.ratio16x9),
        );
        await openPlayerFor(tester, liveRequest(id));
        expect(shownAspect(tester), AspectMode.ratio16x9);

        await focusOsdButton(tester, 'aspect', locale: locale);
        await press(tester, LogicalKeyboardKey.select);
        expect(find.byType(AlertDialog), findsOneWidget);
        // The current choice (16:9, the fourth) has the focus.
        expect(focusedIn(const ValueKey('player-choice-3')), isTrue);
        await press(tester, LogicalKeyboardKey.arrowUp);
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(focusedIn(const ValueKey('player-choice-1')), isTrue);
        await press(tester, LogicalKeyboardKey.select);
        expect(find.byType(AlertDialog), findsNothing);
        expect(shownAspect(tester), AspectMode.fill);
        // Focus came back to the OSD button.
        expect(focusedIn(const ValueKey('player-osd-aspect')), isTrue);
        final prefs = await rig.db.prefsDao.prefsFor(id, 'ch1');
        expect(prefs.aspect, AspectMode.fill);

        // Another channel uses the default; back on ch1 the choice returns.
        await tester.binding.handlePopRoute();
        await settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump(const Duration(milliseconds: 400));
        await settle(tester);
        expect(shownAspect(tester), AspectMode.ratio16x9);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 400));
        await settle(tester);
        expect(shownAspect(tester), AspectMode.fill);
        await disposeRig(tester, rig);
      });
    });

    testWidgets('a reopened player applies the saved choice', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await rig.db.prefsDao.setAspect(id, 'ch1', AspectMode.ratio4x3);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      expect(shownAspect(tester), AspectMode.ratio4x3);
      await disposeRig(tester, rig);
    });
  });

  group('tracks and engines', () {
    testWidgets('audio tracks are listed and selected', (tester) async {
      final rig = PlayerRig()..autoPlay();
      rig.engines.onCreate = (e) {
        e.audio = const [
          TrackInfo(id: 'a1', language: 'ara', selected: true),
          TrackInfo(id: 'a2', language: 'eng', codec: 'aac'),
        ];
        e.onOpen = (e, _) => e.emitFirstFrame();
      };
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      await focusOsdButton(tester, 'audio');
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text('ara'), findsOneWidget);
      expect(find.text('eng · aac'), findsOneWidget);
      expect(focusedIn(const ValueKey('player-choice-0')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      expect(rig.engine.selectedAudio, 'a2');
      await disposeRig(tester, rig);
    });

    testWidgets('subtitles on ExoPlayer offer to switch to mpv, which is '
        'remembered for the channel', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      expect(rig.engine.kind, EngineKind.exo);
      await focusOsdButton(tester, 'subtitles');
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text('Subtitles need the mpv player.'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.select);
      expect(rig.engine.kind, EngineKind.mpv);
      expect(
        (await rig.db.prefsDao.prefsFor(id, 'ch1')).engine,
        EngineKind.mpv,
      );

      // Subtitle tracks on mpv, with Off.
      rig.engine.subtitles = const [TrackInfo(id: 's1', language: 'ara')];
      await focusOsdButton(tester, 'subtitles');
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text('Off'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      expect(rig.engine.selectedSubtitle, 's1');
      await disposeRig(tester, rig);
    });

    testWidgets('a saved engine preference is used when the channel opens', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await rig.db.prefsDao.setEngine(id, 'ch1', EngineKind.mpv);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      expect(rig.engine.kind, EngineKind.mpv);
      await disposeRig(tester, rig);
    });

    testWidgets('Switch player swaps engines', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      await focusOsdButton(tester, 'switchPlayer');
      await press(tester, LogicalKeyboardKey.select);
      expect(rig.engines.created.map((e) => e.kind), [
        EngineKind.exo,
        EngineKind.mpv,
      ]);
      expect(rig.engines.created.first.disposed, isTrue);
      await disposeRig(tester, rig);
    });
  });

  group('favourite, stats and options', () {
    forLocales((locale) {
      testWidgets('Favourite toggles the channel (${locale.languageCode})', (
        tester,
      ) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedLive(rig);
        await pumpPlayerApp(tester, rig, locale: locale);
        await openPlayerFor(tester, liveRequest(id));
        await focusOsdButton(tester, 'favorite', locale: locale);
        await press(tester, LogicalKeyboardKey.select);
        expect(
          await rig.db.favoritesDao.isFavorite(id, ContentKind.live, 'ch1'),
          isTrue,
        );
        expect(find.byType(SnackBar), findsOneWidget);
        await press(tester, LogicalKeyboardKey.select);
        expect(
          await rig.db.favoritesDao.isFavorite(id, ContentKind.live, 'ch1'),
          isFalse,
        );
        await disposeRig(tester, rig);
      });
    });

    testWidgets('Stats shows engine, time to first frame and buffer', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      rig.engines.onCreate = (e) {
        e.statsMap = const {'resolution': '1920x1080', 'video': 'h264'};
        e.onOpen = (e, _) => e.emitFirstFrame();
      };
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      await focusOsdButton(tester, 'stats');
      await press(tester, LogicalKeyboardKey.select);
      final stats = find.byKey(const ValueKey('player-stats'));
      expect(stats, findsOneWidget);
      for (final text in [
        'Engine',
        'exo',
        'Resolution',
        '1920x1080',
        'Codec',
        'h264',
        'Time to first frame',
        '0 ms',
      ]) {
        expect(
          find.descendant(of: stats, matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
      // Back hides the OSD, then the stats, then closes.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(stats, findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(stats, findsNothing);
      expect(find.byType(PlayerScreen), findsOneWidget);
      await disposeRig(tester, rig);
    });

    testWidgets('Menu opens the options list', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      await press(tester, LogicalKeyboardKey.contextMenu);
      expect(find.text('Options'), findsOneWidget);
      expect(focusedIn(const ValueKey('player-choice-0')), isTrue);
      // Audio, Subtitles, Aspect, Favourite, Add to list, Switch player,
      // Guide, Stats.
      for (var i = 0; i < 7; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byKey(const ValueKey('player-stats')), findsOneWidget);
      expect(focusLabel, 'player');
      await disposeRig(tester, rig);
    });
  });
}
