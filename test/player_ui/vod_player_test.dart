import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/player/ui/player_screen.dart';
import 'package:iptv_player/sources/models.dart';

import '../support/fake_engine.dart';
import 'support/player_harness.dart';

const _movieUrl = 'http://127.0.0.1:9/movie/m1.mp4';
const _hour = Duration(minutes: 90);

Future<void> _saveProgress(
  PlayerRig rig,
  int id,
  Duration position, {
  Duration duration = _hour,
}) => rig.db.progressDao.saveProgress(
  id,
  PlayableKind.movie,
  'm1',
  position.inMilliseconds,
  duration.inMilliseconds,
);

List<String> _seeks(FakeEngine e) =>
    e.calls.where((c) => c.startsWith('seek')).toList();

void main() {
  group('resume prompt', () {
    forLocales((locale) {
      testWidgets('offers «resume from 42:10» before opening '
          '(${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay(duration: _hour);
        final id = await seedVod(rig);
        await _saveProgress(rig, id, const Duration(minutes: 42, seconds: 10));
        await pumpPlayerApp(tester, rig, locale: locale);
        await openPlayerFor(tester, movieRequest(id));

        expect(find.byKey(const ValueKey('player-resume')), findsOneWidget);
        expect(
          find.text(locale == ar ? 'استكمال من 42:10' : 'Resume from 42:10'),
          findsOneWidget,
        );
        expect(
          find.text(locale == ar ? 'من البداية' : 'Start over'),
          findsOneWidget,
        );
        expect(focusLabel, 'player:resume');
        expect(rig.openedUrls, isEmpty);

        await press(tester, LogicalKeyboardKey.select);
        expect(find.byKey(const ValueKey('player-resume')), findsNothing);
        expect(rig.openedUrls, [_movieUrl]);
        expect(
          rig.engine.lastRequest!.startAt,
          const Duration(minutes: 42, seconds: 10),
        );
        // VOD defaults to mpv on Android.
        expect(rig.engine.kind, EngineKind.mpv);
        expect(focusLabel, 'player');
        await disposeRig(tester, rig);
      });
    });

    testWidgets('«start over» plays from the beginning', (tester) async {
      final rig = PlayerRig()..autoPlay(duration: _hour);
      final id = await seedVod(rig);
      await _saveProgress(rig, id, const Duration(minutes: 10));
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, movieRequest(id));
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedIn(const ValueKey('player-start-over')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(rig.openedUrls, [_movieUrl]);
      expect(rig.engine.lastRequest!.startAt, isNull);
      await disposeRig(tester, rig);
    });

    for (final (name, position) in [
      ('under 30 s', const Duration(seconds: 20)),
      ('finished', const Duration(minutes: 89)),
    ]) {
      testWidgets('no prompt when the saved position is $name', (tester) async {
        final rig = PlayerRig()..autoPlay(duration: _hour);
        final id = await seedVod(rig);
        await _saveProgress(rig, id, position);
        await pumpPlayerApp(tester, rig);
        await openPlayerFor(tester, movieRequest(id));
        expect(find.byKey(const ValueKey('player-resume')), findsNothing);
        expect(rig.openedUrls, [_movieUrl]);
        expect(rig.engine.lastRequest!.startAt, isNull);
        await disposeRig(tester, rig);
      });
    }

    testWidgets('an explicit start position skips the prompt', (tester) async {
      final rig = PlayerRig()..autoPlay(duration: _hour);
      final id = await seedVod(rig);
      await _saveProgress(rig, id, const Duration(minutes: 10));
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(
        tester,
        movieRequest(id, startAt: const Duration(minutes: 5)),
      );
      expect(find.byKey(const ValueKey('player-resume')), findsNothing);
      expect(rig.engine.lastRequest!.startAt, const Duration(minutes: 5));
      await disposeRig(tester, rig);
    });
  });

  group('seeking', () {
    forLocales((locale) {
      testWidgets('Left/Right collect into one seek 600 ms after the last '
          'press (${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay(duration: _hour);
        final id = await seedVod(rig);
        await pumpPlayerApp(tester, rig, locale: locale);
        await openPlayerFor(tester, movieRequest(id));
        final engine = rig.engine;

        for (var i = 0; i < 3; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump(const Duration(milliseconds: 200));
        }
        // The OSD opened on the seek bar, which shows the target (LTR).
        expect(find.byKey(const ValueKey('player-osd')), findsOneWidget);
        expect(focusLabel, 'player:seek-bar');
        expect(find.byKey(const ValueKey('player-position')), findsOneWidget);
        expect(find.text('0:30'), findsOneWidget);
        expect(_seeks(engine), isEmpty);
        // The last press was 200 ms ago.
        await tester.pump(const Duration(milliseconds: 380));
        expect(_seeks(engine), isEmpty);
        await tester.pump(const Duration(milliseconds: 30));
        expect(_seeks(engine), ['seek 30000']);

        // Right is always forward on the seek bar, also in Arabic.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump(const Duration(milliseconds: 700));
        expect(_seeks(engine), ['seek 30000', 'seek 20000']);

        // FF/RW jump 30 s.
        await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
        await tester.pump(const Duration(milliseconds: 700));
        expect(_seeks(engine).last, 'seek 50000');
        await tester.sendKeyEvent(LogicalKeyboardKey.mediaRewind);
        await tester.pump(const Duration(milliseconds: 700));
        expect(_seeks(engine).last, 'seek 20000');
        await disposeRig(tester, rig);
      });
    });

    testWidgets('a held key accelerates', (tester) async {
      final rig = PlayerRig()..autoPlay(duration: _hour);
      final id = await seedVod(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, movieRequest(id));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 100));
      rig.clock.advance(const Duration(milliseconds: 500));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      rig.clock.advance(const Duration(milliseconds: 700));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      rig.clock.advance(const Duration(seconds: 2));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 700));
      // 10 + 10 + 30 (held 1.2 s) + 60 (held 3.2 s).
      expect(_seeks(rig.engine), ['seek 110000']);
      await disposeRig(tester, rig);
    });

    testWidgets('play/pause from the OSD and the media key', (tester) async {
      final rig = PlayerRig()..autoPlay(duration: _hour);
      final id = await seedVod(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, movieRequest(id));
      await press(tester, LogicalKeyboardKey.select);
      expect(focusLabel, 'player:seek-bar');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('player-osd-playPause')), isTrue);
      expect(find.text('Pause'), findsOneWidget);
      // The seek bar follows the engine.
      rig.engine.setState(position: const Duration(minutes: 5));
      await tester.pump();
      expect(find.text('5:00'), findsOneWidget);
      expect(find.text('1:30:00'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.select);
      expect(rig.engine.state.value.playing, isFalse);
      expect(find.text('Play'), findsOneWidget);
      // Paused: the OSD stays up.
      await tester.pump(const Duration(seconds: 6));
      expect(find.byKey(const ValueKey('player-osd')), findsOneWidget);
      await press(tester, LogicalKeyboardKey.mediaPlayPause);
      expect(rig.engine.state.value.playing, isTrue);
      await disposeRig(tester, rig);
    });

    testWidgets('progress is saved when the player closes', (tester) async {
      final rig = PlayerRig()..autoPlay(duration: _hour);
      final id = await seedVod(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, movieRequest(id));
      rig.engine.setState(position: const Duration(minutes: 7));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
      final saved = await rig.db.progressDao.progressFor(
        id,
        PlayableKind.movie,
        'm1',
      );
      expect(saved?.position, const Duration(minutes: 7));
      expect(saved?.duration, _hour);
      await disposeRig(tester, rig);
    });
  });

  group('next episode', () {
    forLocales((locale) {
      testWidgets('counts down near the end and plays the next episode '
          '(${locale.languageCode})', (tester) async {
        final rig = PlayerRig()
          ..autoPlay(duration: const Duration(minutes: 40));
        final id = await seedVod(rig);
        await pumpPlayerApp(tester, rig, locale: locale);
        await openPlayerFor(tester, episodeRequest(id));
        expect(rig.openedUrls, ['http://127.0.0.1:9/series/e1.mp4']);

        rig.engine.setState(position: const Duration(minutes: 39, seconds: 50));
        await settle(tester);
        final card = find.byKey(const ValueKey('player-next-episode'));
        expect(card, findsOneWidget);
        expect(
          find.text(
            locale == ar
                ? 'الحلقة التالية خلال 10 ثوانٍ'
                : 'Next episode in 10 seconds',
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text('Episode title 2')),
          findsOneWidget,
        );
        expect(focusLabel, 'player:next-episode');
        await tester.pump(const Duration(seconds: 3));
        expect(
          find.text(
            locale == ar
                ? 'الحلقة التالية خلال 7 ثوانٍ'
                : 'Next episode in 7 seconds',
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 7));
        await settle(tester);
        expect(rig.openedUrls.last, 'http://127.0.0.1:9/series/e2.mp4');
        expect(card, findsNothing);
        expect(focusLabel, 'player');
        await disposeRig(tester, rig);
      });
    });

    testWidgets('Back cancels the countdown for this episode', (tester) async {
      final rig = PlayerRig()..autoPlay(duration: const Duration(minutes: 40));
      final id = await seedVod(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, episodeRequest(id));
      rig.engine.emitEnded();
      await settle(tester);
      expect(find.byKey(const ValueKey('player-next-episode')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byKey(const ValueKey('player-next-episode')), findsNothing);
      expect(find.byType(PlayerScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 12));
      expect(rig.openedUrls, ['http://127.0.0.1:9/series/e1.mp4']);
      // It does not come back for this episode.
      rig.engine.setState(position: const Duration(minutes: 39, seconds: 55));
      await settle(tester);
      expect(find.byKey(const ValueKey('player-next-episode')), findsNothing);
      await disposeRig(tester, rig);
    });

    testWidgets('«Play now» starts the next episode at once; the last '
        'episode has no countdown', (tester) async {
      final rig = PlayerRig()..autoPlay(duration: const Duration(minutes: 40));
      final id = await seedVod(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, episodeRequest(id, key: 'e2'));
      rig.engine.emitEnded();
      await settle(tester);
      await press(tester, LogicalKeyboardKey.select);
      expect(rig.openedUrls.last, 'http://127.0.0.1:9/series/e3.mp4');
      rig.engine.emitEnded();
      await settle(tester);
      expect(find.byKey(const ValueKey('player-next-episode')), findsNothing);
      await disposeRig(tester, rig);
    });
  });
}
