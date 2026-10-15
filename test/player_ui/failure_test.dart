import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/player/ui/play_request.dart';
import 'package:iptv_player/sources/models.dart';

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

/// An M3U source with `ch1` and `nourl`, a channel without a stream URL.
Future<int> _seedWithBrokenChannel(PlayerRig rig) async {
  final db = rig.db;
  final id = await db.sourcesDao.create(
    const SourceConfig(
      kind: SourceKind.m3uUrl,
      url: 'http://127.0.0.1:9/list.m3u',
      name: 'Home',
    ),
  );
  final gen = await db.catalogDao.beginGeneration(id);
  await db.catalogDao.upsertChannels(id, gen, const [
    ChannelData(
      key: 'ch1',
      name: 'Channel 1',
      num: 101,
      url: 'http://127.0.0.1:9/live/ch1.ts',
    ),
    ChannelData(key: 'nourl', name: 'No URL', num: 999),
  ]);
  await db.catalogDao.commitGeneration(id, gen);
  return id;
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
      // The stream shows as scheme, host, port and extension only.
      expect(report, contains('Stream: http://127.0.0.1:9/***.ts'));
      expect(report, isNot(contains('/live/')));
      expect(report, isNot(contains(_secret)));
      expect(report, isNot(contains('viewer7')));
      expect(find.text('Copied'), findsOneWidget);
      await disposeRig(tester, rig);
    });

    testWidgets('credentials in bare stream path segments stay hidden', (
      tester,
    ) async {
      // An imported Xtream playlist (m3u_plus, output=ts): the account sits
      // in the path, and the source itself knows no secrets.
      final rig = PlayerRig();
      rig.engines.onCreate = (e) =>
          e.onOpen = (e, r) => e.emitError('HTTP 403 for ${r.url}');
      final db = rig.db;
      final id = await db.sourcesDao.create(
        const SourceConfig(
          kind: SourceKind.m3uUrl,
          url: 'http://127.0.0.1:9/list.m3u',
          name: 'Imported',
        ),
      );
      final gen = await db.catalogDao.beginGeneration(id);
      await db.catalogDao.upsertChannels(id, gen, const [
        ChannelData(
          key: 'x501',
          name: 'Panel News',
          url: 'http://127.0.0.1:9/viewer7/$_secret/501',
        ),
      ]);
      await db.catalogDao.commitGeneration(id, gen);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(
        tester,
        PlayRequest(
          sourceId: id,
          item: const PlayableRef(kind: PlayableKind.live, key: 'x501'),
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('player-failure')), findsOneWidget);
      final screen = _screenText(tester);
      expect(screen, contains('HTTP 403 for http://127.0.0.1:9/***'));
      expect(screen, isNot(contains(_secret)));
      expect(screen, isNot(contains('viewer7')));

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedIn(const ValueKey('player-copy-report')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      final report = rig.clipboard!;
      expect(report, contains('Stream: http://127.0.0.1:9/***'));
      expect(report, isNot(contains(_secret)));
      expect(report, isNot(contains('viewer7')));
      await disposeRig(tester, rig);
    });
  });

  group('cards behind a dialog', () {
    forLocales((locale) {
      testWidgets('a failure that appears while the options are open gets '
          'the focus when they close (${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await _seedWithBrokenChannel(rig);
        await pumpPlayerApp(tester, rig, locale: locale);
        await openPlayerFor(
          tester,
          liveRequest(id).copyWith(zapKeys: ['ch1', 'nourl']),
        );
        // Zap to a channel that cannot play, and open the options before
        // the zap happens: the failure card appears behind the dialog.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
        await _pumpFor(tester, const Duration(milliseconds: 500));
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byKey(const ValueKey('player-failure')), findsOneWidget);

        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(find.byType(AlertDialog), findsNothing);
        expect(focusLabel, 'player:retry');
        // The D-pad stays on the card; the buttons follow the reading
        // direction.
        for (final key in [
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
        ]) {
          await press(tester, key);
          expect(focusLabel, 'player:retry', reason: '$key');
        }
        await press(
          tester,
          locale == ar
              ? LogicalKeyboardKey.arrowLeft
              : LogicalKeyboardKey.arrowRight,
        );
        expect(focusedIn(const ValueKey('player-copy-report')), isTrue);
        await disposeRig(tester, rig);
      });
    });

    testWidgets('from the player itself, arrows and OK reach the card', (
      tester,
    ) async {
      final rig = PlayerRig();
      rig.engines.onCreate = (e) =>
          e.onOpen = (e, _) => e.emitError('Source error');
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      await settle(tester);
      expect(find.byKey(const ValueKey('player-failure')), findsOneWidget);
      // Focus falls back to the player (e.g. a dialog's route restored it).
      final root = FocusManager.instance.primaryFocus!.ancestors.firstWhere(
        (n) => n.debugLabel == 'player',
      );
      root.requestFocus();
      await tester.pump();
      expect(focusLabel, 'player');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusLabel, 'player:retry');
      root.requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.select);
      expect(focusLabel, 'player:retry');
      await disposeRig(tester, rig);
    });

    testWidgets('a next-episode countdown that starts behind a dialog gets '
        'the focus when it closes', (tester) async {
      final rig = PlayerRig()..autoPlay(duration: const Duration(minutes: 40));
      final id = await seedVod(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, episodeRequest(id));
      await press(tester, LogicalKeyboardKey.contextMenu);
      expect(find.byType(AlertDialog), findsOneWidget);
      rig.engine.setState(position: const Duration(minutes: 39, seconds: 50));
      await settle(tester);
      expect(find.byKey(const ValueKey('player-next-episode')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(focusLabel, 'player:next-episode');
      await press(tester, LogicalKeyboardKey.select);
      expect(rig.openedUrls.last, 'http://127.0.0.1:9/series/e2.mp4');
      await disposeRig(tester, rig);
    });
  });
}
