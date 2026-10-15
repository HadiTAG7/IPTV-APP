// A closing player must not keep driving the shared PlaybackController:
// during its exit transition nothing it started (a debounced zap, a load in
// flight) may open a stream, and a player opened meanwhile keeps its
// channel, its video surface and (on phones) its landscape lock.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/player/player_providers.dart';
import 'package:iptv_player/player/ui/player_route.dart';
import 'package:iptv_player/player/ui/player_screen.dart';
import 'package:iptv_player/sources/source_repository.dart';

import 'support/player_harness.dart';

String _url(String key) => 'http://127.0.0.1:9/live/$key.ts';

Finder _inBanner(String text) => find.descendant(
  of: find.byKey(const ValueKey('player-banner')),
  matching: find.text(text),
);

Future<void> _pumpSteps(WidgetTester tester, int steps) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _openWithoutWaiting(WidgetTester tester, int sourceId, String key) =>
    unawaited(
      openPlayer(
        tester.element(find.byKey(launcherKey)),
        liveRequest(sourceId, key: key),
      ),
    );

void main() {
  group('closing player', () {
    forLocales((locale) {
      testWidgets('a zap pending at Back never opens its channel '
          '(${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedLive(rig);
        await pumpPlayerApp(tester, rig, locale: locale);
        await openPlayerFor(tester, liveRequest(id));
        expect(rig.openedUrls, [_url('ch1')]);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump(const Duration(milliseconds: 50));
        expect(_inBanner('Channel 2'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await _pumpSteps(tester, 20);

        expect(find.byType(PlayerScreen), findsNothing);
        expect(rig.openedUrls, [_url('ch1')]);
        expect(rig.played.map((p) => p.$2), ['ch1']);
        await disposeRig(tester, rig);
      });
    });

    testWidgets('a typed number pending at Back is dropped', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.pump();
      // The first Back drops the number, the second one closes.
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await _pumpSteps(tester, 40);
      expect(find.byType(PlayerScreen), findsNothing);
      expect(rig.openedUrls, [_url('ch1')]);
      await disposeRig(tester, rig);
    });

    testWidgets('Back while the source still loads opens nothing', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(
        tester,
        rig,
        overrides: [
          playerSourceLoaderProvider.overrideWith((ref) {
            final repo = ref.watch(sourceRepositoryProvider);
            return (sourceId) async {
              await Future<void>.delayed(const Duration(milliseconds: 300));
              final row = await repo.byId(sourceId);
              final config = await repo.configFor(sourceId);
              return PlayerSource(
                row: row!,
                adapter: repo.adapterFor(
                  config,
                  allowedFormats: row.allowedFormats,
                ),
                secrets: sourceSecrets(config),
              );
            };
          }),
        ],
      );
      _openWithoutWaiting(tester, id, 'ch1');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PlayerScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await _pumpSteps(tester, 20);
      expect(find.byType(PlayerScreen), findsNothing);
      expect(rig.openedUrls, isEmpty);
      await disposeRig(tester, rig);
    });

    testWidgets('a player opened during the exit transition keeps its '
        'channel and is the only one showing video', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 100));
      // Channel 4 is picked from the list while the old player fades out.
      _openWithoutWaiting(tester, id, 'ch4');
      await _pumpSteps(tester, 2);
      expect(find.byType(PlayerScreen), findsNWidgets(2));
      // The closing player no longer shows the shared engine's surface.
      expect(find.byKey(const ValueKey('fake-exo-fit')), findsOneWidget);

      await _pumpSteps(tester, 30);
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(rig.openedUrls, [_url('ch1'), _url('ch4')]);
      expect(rig.engine.lastRequest?.url, _url('ch4'));
      expect(_inBanner('Channel 4'), findsOneWidget);
      // Its keys work: it zaps from channel 4.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await _pumpSteps(tester, 10);
      expect(rig.openedUrls.last, _url('ch5'));
      await disposeRig(tester, rig);
    });

    forLocales((locale) {
      testWidgets('phone: the closing player leaves the next player '
          'landscape (${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedLive(rig);
        await pumpPlayerApp(tester, rig, tv: false, locale: locale);
        await openPlayerFor(tester, liveRequest(id));
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 100));
        _openWithoutWaiting(tester, id, 'ch4');
        await _pumpSteps(tester, 30);
        expect(find.byType(PlayerScreen), findsOneWidget);
        expect(
          rig.callsOf('SystemChrome.setPreferredOrientations').last.arguments,
          isNotEmpty,
        );
        expect(
          rig.callsOf('SystemChrome.setEnabledSystemUIMode').last.arguments,
          'SystemUiMode.immersiveSticky',
        );

        // Closing the second player gives the orientation back.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(PlayerScreen), findsNothing);
        expect(
          rig.callsOf('SystemChrome.setPreferredOrientations').last.arguments,
          isEmpty,
        );
        expect(
          rig.callsOf('SystemChrome.setEnabledSystemUIMode').last.arguments,
          'SystemUiMode.edgeToEdge',
        );
        await disposeRig(tester, rig);
      });
    });
  });
}
