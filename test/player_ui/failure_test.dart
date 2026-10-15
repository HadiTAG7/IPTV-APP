import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/engine/player_engine.dart';

import 'support/player_harness.dart';

const _secret = 'Secret-Pass-9';

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 250);
  var left = total;
  while (left > Duration.zero) {
    await tester.pump(step);
    left -= step;
  }
}

/// Text of every [Text] and [RichText] on screen.
String _screenText(WidgetTester tester) => [
  for (final w in tester.widgetList<RichText>(find.byType(RichText)))
    w.text.toPlainText(),
].join('\n');

void main() {
  group('reconnect banner', () {
    forLocales((locale) {
      testWidgets('shows the attempt from the watchdog over the last frame '
          '(${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedLive(rig);
        await pumpPlayerApp(tester, rig, locale: locale);
        await openPlayerFor(tester, liveRequest(id));
        final banner = find.byKey(const ValueKey('player-reconnect'));
        expect(banner, findsNothing);

        // The stream drops after it played: the watchdog takes over.
        rig.engine.emitError('Source error');
        await tester.pump();
        expect(banner, findsOneWidget);
        expect(
          find.text(
            locale == ar ? 'جارٍ إعادة الاتصال… (1/8)' : 'Reconnecting… (1/8)',
          ),
          findsOneWidget,
        );
        // The video surface stays (last frame).
        expect(shownAspect(tester), AspectMode.fit);

        // Attempt 1 runs after 1 s and plays again.
        await _pumpFor(tester, const Duration(seconds: 2));
        expect(rig.openedUrls, hasLength(2));
        expect(banner, findsNothing);
        await disposeRig(tester, rig);
      });
    });
  });

  group('failure card', () {
    forLocales((locale) {
      testWidgets('Retry has the focus and replays (${locale.languageCode})', (
        tester,
      ) async {
        final rig = PlayerRig();
        var fail = true;
        rig.engines.onCreate = (e) =>
            e.onOpen = (e, _) =>
                fail ? e.emitError('Source error') : e.emitFirstFrame();
        final id = await seedLive(rig);
        await pumpPlayerApp(tester, rig, locale: locale);
        await openPlayerFor(tester, liveRequest(id));
        await settle(tester);

        // ExoPlayer, then mpv failed.
        expect(rig.engines.created.map((e) => e.kind), [
          EngineKind.exo,
          EngineKind.mpv,
        ]);
        final card = find.byKey(const ValueKey('player-failure'));
        expect(card, findsOneWidget);
        expect(
          find.text(locale == ar ? 'تعذّر التشغيل' : 'Playback failed'),
          findsOneWidget,
        );
        expect(focusLabel, 'player:retry');
        // M3U sources have no other format to try.
        expect(find.byKey(const ValueKey('player-other-format')), findsNothing);
        expect(rig.wakelock.last, isFalse);

        fail = false;
        await press(tester, LogicalKeyboardKey.select);
        expect(card, findsNothing);
        expect(focusLabel, 'player');
        expect(rig.engine.state.value.playing, isTrue);
        await disposeRig(tester, rig);
      });
    });

    testWidgets('«Try other format» re-resolves an Xtream channel as m3u8', (
      tester,
    ) async {
      final rig = PlayerRig();
      rig.engines.onCreate = (e) => e.onOpen = (e, r) => r.url.endsWith('.ts')
          ? e.emitError('Source error: ${r.url}')
          : e.emitFirstFrame();
      final id = await seedXtream(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, xtreamRequest(id, '501'));
      // Single-connection panel: held-connection retries come first.
      await _pumpFor(tester, const Duration(seconds: 12));
      expect(find.byKey(const ValueKey('player-failure')), findsOneWidget);
      expect(rig.openedUrls.every((u) => u.endsWith('/501.ts')), isTrue);
      expect(_screenText(tester), isNot(contains(_secret)));
      expect(_screenText(tester), isNot(contains('viewer7')));

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedIn(const ValueKey('player-other-format')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(rig.openedUrls.last, endsWith('/501.m3u8'));
      expect(rig.engine.lastRequest!.isHls, isTrue);
      expect(find.byKey(const ValueKey('player-failure')), findsNothing);

      // Zapping keeps the format that worked.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(rig.openedUrls.last, endsWith('/502.m3u8'));
      await disposeRig(tester, rig);
    });

    testWidgets('«Copy report» copies a redacted report', (tester) async {
      final rig = PlayerRig();
      rig.engines.onCreate = (e) =>
          e.onOpen = (e, r) =>
              e.emitError('HTTP 403 for ${r.url} (user viewer7)');
      final id = await seedXtream(rig);
      rig.log.info('Opening with password $_secret');
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, xtreamRequest(id, '501'));
      await _pumpFor(tester, const Duration(seconds: 12));
      expect(find.byKey(const ValueKey('player-failure')), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedIn(const ValueKey('player-copy-report')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      final report = rig.clipboard;
      expect(report, isNotNull);
      expect(report, contains('IPTV Player playback report'));
      expect(report, contains('Phase: failed'));
      expect(report, contains('Source: xtream, max connections 1'));
      expect(report, contains('App: 0.1.0+1'));
      expect(report, contains('/live/***/***/501.ts'));
      expect(report, isNot(contains(_secret)));
      expect(report, isNot(contains('viewer7')));
      expect(find.text('Copied'), findsOneWidget);
      await disposeRig(tester, rig);
    });
  });
}
