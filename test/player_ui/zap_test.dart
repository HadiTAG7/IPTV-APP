import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_harness.dart';

Finder _inBanner(String text) => find.descendant(
  of: find.byKey(const ValueKey('player-banner')),
  matching: find.text(text),
);

Finder _inBadge(String text) => find.descendant(
  of: find.byKey(const ValueKey('player-number-badge')),
  matching: find.text(text),
);

String _url(String key) => 'http://127.0.0.1:9/live/$key.ts';

void main() {
  group('zapping', () {
    forLocales((locale) {
      testWidgets('Up/Down move the banner at once and tune after 350 ms '
          '(${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedLive(rig);
        await pumpPlayerApp(tester, rig, locale: locale);
        await openPlayerFor(tester, liveRequest(id));
        expect(rig.openedUrls, [_url('ch1')]);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(_inBanner('Channel 2'), findsOneWidget);
        expect(_inBanner('102'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 340));
        expect(rig.openedUrls, [_url('ch1')]);
        await tester.pump(const Duration(milliseconds: 20));
        await settle(tester);
        expect(rig.openedUrls, [_url('ch1'), _url('ch2')]);
        expect(rig.played.map((p) => p.$2), ['ch1', 'ch2']);

        // A burst of presses opens only the last channel (wrapping around).
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 100));
        expect(_inBanner('Channel 5'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 400));
        await settle(tester);
        expect(rig.openedUrls, [_url('ch1'), _url('ch2'), _url('ch5')]);

        // Channel keys and Page keys zap too.
        await tester.sendKeyEvent(LogicalKeyboardKey.channelUp);
        await tester.pump(const Duration(milliseconds: 400));
        await settle(tester);
        expect(rig.openedUrls.last, _url('ch1'));
        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pump(const Duration(milliseconds: 400));
        await settle(tester);
        expect(rig.openedUrls.last, _url('ch5'));
        // One engine, reused: every switch stopped the previous stream.
        expect(rig.engines.created, hasLength(1));
        expect(rig.engine.count('stop'), rig.openedUrls.length - 1);
        await disposeRig(tester, rig);
      });

      testWidgets('digits tune after 1.5 s; a lone 0 recalls '
          '(${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedLive(rig);
        await pumpPlayerApp(tester, rig, locale: locale);
        await openPlayerFor(tester, liveRequest(id));

        for (final k in [
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit0,
          LogicalKeyboardKey.digit3,
        ]) {
          await tester.sendKeyEvent(k);
          await tester.pump();
        }
        expect(_inBadge('103'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 100));
        expect(_inBadge('Channel 3'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1300));
        expect(rig.openedUrls, [_url('ch1')]);
        await tester.pump(const Duration(milliseconds: 200));
        await settle(tester);
        expect(rig.openedUrls.last, _url('ch3'));
        expect(find.byKey(const ValueKey('player-number-badge')), findsNothing);

        // OK tunes at once.
        await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
        await tester.pump();
        await press(tester, LogicalKeyboardKey.select);
        expect(rig.openedUrls.last, _url('ch5'));
        // OK committed the number; it did not open the OSD.
        expect(find.byKey(const ValueKey('player-osd')), findsNothing);

        // A lone 0 returns to the previous channel.
        await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
        await tester.pump(const Duration(milliseconds: 1600));
        await settle(tester);
        expect(rig.openedUrls.last, _url('ch3'));

        // A number not in the list says so and tunes nothing.
        final before = rig.openedUrls.length;
        await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('player-number-badge')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('player-number-badge')),
            matching: find.textContaining('9'),
          ),
          findsWidgets,
        );
        await tester.pump(const Duration(milliseconds: 1600));
        await settle(tester);
        expect(rig.openedUrls, hasLength(before));
        await disposeRig(tester, rig);
      });
    });

    testWidgets('Back cancels a half-typed number before anything else', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pump();
      expect(find.byKey(const ValueKey('player-number-badge')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byKey(const ValueKey('player-number-badge')), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(rig.openedUrls, [_url('ch1')]);
      await disposeRig(tester, rig);
    });

    testWidgets('playlists without numbers use list positions', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig, numbered: false);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.pump(const Duration(milliseconds: 1600));
      await settle(tester);
      expect(rig.openedUrls.last, _url('ch4'));
      await disposeRig(tester, rig);
    });

    testWidgets('zapping follows an explicit key list (favourites)', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(
        tester,
        liveRequest(id, key: 'ch4').copyWith(zapKeys: ['ch4', 'ch2', 'gone']),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(rig.openedUrls, [_url('ch4'), _url('ch2')]);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(rig.openedUrls.last, _url('ch4'));
      await disposeRig(tester, rig);
    });
  });
}
