import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/ui/play_request.dart';
import 'package:iptv_player/sources/models.dart';

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

/// The now/next query of the guide (one per read, whatever the key count).
const _nowNextSql = 'JOIN programmes';

/// A request without a category or key list: zapping walks every channel.
PlayRequest _allChannels(int sourceId, String key) => PlayRequest(
  sourceId: sourceId,
  item: PlayableRef(kind: PlayableKind.live, key: key, url: _url(key)),
);

Future<void> _zapAndSettle(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump(const Duration(milliseconds: 400));
  await settle(tester);
}

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

  group('banner now/next', () {
    testWidgets('a channel without guide data is read once, not every '
        'frame', (tester) async {
      final queries = QueryCounter();
      final rig = PlayerRig(queries: queries)..autoPlay();
      final id = await seedLive(rig);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id));
      await tester.pump(const Duration(seconds: 1));
      queries.reset();

      // The zap banner rests on channel 2 (no guide data) while the
      // debounce runs; then number entry keeps a badge up for 1.5 s.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(queries.count(_nowNextSql), lessThanOrEqualTo(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(queries.count(_nowNextSql), lessThanOrEqualTo(2));
      await disposeRig(tester, rig);
    });

    testWidgets('now/next of the zap target shows once the banner rests '
        'on it', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await seedGuide(rig, id);
      await pumpPlayerApp(tester, rig);
      await openPlayerFor(tester, liveRequest(id, key: 'ch2'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(_inBanner('Channel 1'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('player-banner')),
          matching: find.textContaining('Evening News'),
        ),
        findsOneWidget,
      );
      await disposeRig(tester, rig);
    });
  });

  group('large lists', () {
    for (final category in [null, 'news']) {
      final name = category == null ? 'all channels' : 'a category';
      testWidgets('$name: zapping reads windows, never the whole list', (
        tester,
      ) async {
        final queries = QueryCounter();
        final rig = PlayerRig(queries: queries)..autoPlay();
        final id = await seedLive(rig, count: 1000);
        await pumpPlayerApp(tester, rig);
        queries.reset();
        await openPlayerFor(
          tester,
          category == null
              ? _allChannels(id, 'ch200')
              : liveRequest(id, key: 'ch200', category: category),
        );
        await settle(tester);
        expect(rig.openedUrls, [_url('ch200')]);

        // Across a page boundary (index 199 -> 200).
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(_inBanner('Channel 201'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 400));
        await settle(tester);
        expect(rig.openedUrls.last, _url('ch201'));

        // A number far away (ch950 is number 1050).
        for (final k in [
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit0,
          LogicalKeyboardKey.digit5,
          LogicalKeyboardKey.digit0,
        ]) {
          await tester.sendKeyEvent(k);
        }
        await settle(tester);
        expect(_inBadge('Channel 950'), findsOneWidget);
        await press(tester, LogicalKeyboardKey.select);
        expect(rig.openedUrls.last, _url('ch950'));
        await _zapAndSettle(tester, LogicalKeyboardKey.arrowDown);
        expect(rig.openedUrls.last, _url('ch949'));

        // The list wraps around from the first channel to the last.
        await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
        await press(tester, LogicalKeyboardKey.select);
        expect(rig.openedUrls.last, _url('ch1'));
        await _zapAndSettle(tester, LogicalKeyboardKey.arrowDown);
        expect(rig.openedUrls.last, _url('ch1000'));
        await _zapAndSettle(tester, LogicalKeyboardKey.arrowUp);
        expect(rig.openedUrls.last, _url('ch1'));
        // A lone 0 recalls the channel before.
        await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
        await press(tester, LogicalKeyboardKey.select);
        expect(rig.openedUrls.last, _url('ch1000'));

        // No read returned more than one page of the 1000 channels.
        expect(queries.maxRows, lessThanOrEqualTo(200));
        await disposeRig(tester, rig);
      });
    }
  });
}
