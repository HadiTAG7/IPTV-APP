// Opening the split screen from the player (desktop only). Synthetic data.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/epg/epg_providers.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/player/connection_budget.dart';
import 'package:iptv_player/player/multiview/multiview_screen.dart';
import 'package:iptv_player/player/ui/player_screen.dart';
import 'package:iptv_player/tv/dpad_shortcuts.dart';

import 'support/multiview_harness.dart';
import 'support/player_harness.dart';

const _splitButton = ValueKey('player-osd-split');

void main() {
  group('desktop live', () {
    forLocales((locale) {
      testWidgets('S hands the channel over: the player stops first, then '
          'the first tile plays it (${locale.languageCode})', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedXtream(rig);
        await pumpSplitApp(tester, rig, locale: locale);
        final l10n = await AppLocalizations.delegate.load(locale);
        await openPlayerFor(tester, xtreamRequest(id, '501'));
        final player = rig.engine;
        final url = player.lastRequest!.url;
        expect(rig.window, ['enter']);

        await press(tester, LogicalKeyboardKey.keyS);
        await settleSplit(tester);

        expect(find.byType(PlayerScreen), findsNothing);
        expect(find.byType(MultiViewScreen), findsOneWidget);
        // The player's stream stopped before the tile's opened.
        final log = rig.engines.log;
        final stop = log.indexOf('mpv.stop');
        final opens = [
          for (final (i, l) in log.indexed)
            if (l == 'mpv.open $url') i,
        ];
        expect(opens, hasLength(2));
        expect(stop, greaterThan(opens.first));
        expect(stop, lessThan(opens.last));
        final tile = rig.engine;
        expect(identical(tile, player), isFalse);
        expect(tile.lastRequest!.url, url);
        expect(player.disposed, isTrue);
        // The first tile is the active one, heard, normal cache.
        expect(isActive(0), isTrue);
        expect(tile.muted, isFalse);
        expect(tile.lite, isFalse);
        expect(inSlot(0, find.text('Panel News')), findsOneWidget);
        expect(inSlot(1, find.text(l10n.multiviewAddChannel)), findsOneWidget);
        // The window stayed fullscreen.
        expect(rig.window, ['enter', 'enter']);
        final container = containerOf(tester);
        expect(container.read(multiViewTilesProvider), {0: id});
        expect(container.read(mainPlayerSourceProvider), isNull);
        expect(container.read(fullscreenPlaybackProvider), isTrue);
        expect(rig.played.last, (id, '501'));
        await disposeRig(tester, rig);
      });
    });

    testWidgets('the OSD button and the options list offer it; a windowed '
        'player opens it windowed', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpSplitApp(tester, rig, platform: TargetPlatform.linux);
      final l10n = await AppLocalizations.delegate.load(en);
      await openPlayerFor(tester, liveRequest(id, key: 'ch2'));
      // Windowed: F.
      await press(tester, LogicalKeyboardKey.keyF);
      expect(rig.window, ['enter', 'exit']);
      await mouseAt(tester, const Offset(640, 360));
      expect(find.byKey(_splitButton), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_splitButton),
          matching: find.text(l10n.playerSplitScreen),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(_splitButton));
      await settleSplit(tester);
      expect(find.byType(MultiViewScreen), findsOneWidget);
      expect(engineFor(rig, 'ch2').opened, hasLength(1));
      expect(rig.window, ['enter', 'exit']);
      await disposeRig(tester, rig);
    });

    testWidgets('the options list offers it', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpSplitApp(tester, rig, locale: ar);
      final l10n = await AppLocalizations.delegate.load(ar);
      await openPlayerFor(tester, liveRequest(id));
      await press(tester, menuKey);
      expect(find.text(l10n.playerSplitScreen), findsOneWidget);
      await tester.tap(find.text(l10n.playerSplitScreen));
      await settleSplit(tester);
      expect(find.byType(PlayerScreen), findsNothing);
      expect(find.byType(MultiViewScreen), findsOneWidget);
      expect(inSlot(0, find.text('Channel 1')), findsOneWidget);
      await disposeRig(tester, rig);
    });
  });

  group('never offered', () {
    testWidgets('on Android TV and phones', (tester) async {
      for (final tv in [true, false]) {
        final rig = PlayerRig()..autoPlay();
        final id = await seedLive(rig);
        await pumpSplitApp(
          tester,
          rig,
          tv: tv,
          platform: TargetPlatform.android,
        );
        final l10n = await AppLocalizations.delegate.load(en);
        await openPlayerFor(tester, liveRequest(id));
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(find.byKey(const ValueKey('player-osd')), findsOneWidget);
        expect(find.byKey(_splitButton), findsNothing);
        await tester.binding.handlePopRoute();
        await settle(tester);
        await press(tester, LogicalKeyboardKey.keyS);
        await settle(tester);
        expect(find.byType(PlayerScreen), findsOneWidget);
        expect(find.byType(MultiViewScreen), findsNothing);
        await press(tester, menuKey);
        expect(find.text(l10n.playerSplitScreen), findsNothing);
        await disposeRig(tester, rig);
      }
    });

    testWidgets('for movies on desktop', (tester) async {
      final rig = PlayerRig()..autoPlay(duration: const Duration(hours: 1));
      final id = await seedVod(rig);
      await pumpSplitApp(tester, rig);
      await openPlayerFor(tester, movieRequest(id));
      await mouseAt(tester, const Offset(640, 360));
      expect(find.byKey(const ValueKey('player-osd')), findsOneWidget);
      expect(find.byKey(_splitButton), findsNothing);
      await press(tester, LogicalKeyboardKey.keyS);
      await settle(tester);
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(find.byType(MultiViewScreen), findsNothing);
      await disposeRig(tester, rig);
    });
  });
}
