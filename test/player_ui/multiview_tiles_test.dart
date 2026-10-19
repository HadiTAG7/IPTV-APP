// The split screen's tiles: adding channels from other sources, the
// connection budget, the active tile and its sound, maximizing, changing,
// removing and detaching tiles, and the layouts. Synthetic data only.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/player/connection_budget.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/multiview/multiview_screen.dart';
import 'package:iptv_player/sources/models.dart';

import 'support/multiview_harness.dart';
import 'support/player_harness.dart';

const _inUse = ValueKey('multiview-in-use');

void main() {
  testWidgets('a channel from another source plays in tile 2, which becomes '
      'the one heard; the others use the Lite cache', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final xtream = await seedXtream(rig);
    final free = await seedFree(rig);
    await pumpSplitApp(tester, rig);
    final l10n = await AppLocalizations.delegate.load(en);
    await openSplit(tester, xtreamRequest(xtream, '501'));
    final first = engineFor(rig, '/501.');

    await tester.tap(inSlot(1, find.byKey(const ValueKey('multiview-add'))));
    await openedPicker(tester);
    // Every source on top; opened on the one with a connection free (the
    // subscription's only one is in tile 1).
    Finder inPicker(String text) =>
        find.descendant(of: find.byKey(pickerKey), matching: find.text(text));
    expect(inPicker(l10n.multiviewAddChannel), findsOneWidget);
    expect(inPicker(l10n.multiviewSource), findsOneWidget);
    expect(find.byKey(ValueKey('multiview-source-$xtream')), findsOneWidget);
    expect(find.byKey(ValueKey('multiview-source-$free')), findsOneWidget);
    expect(inPicker('Free 1'), findsOneWidget);
    expect(inPicker('Panel News'), findsNothing);
    // The subscription's channels are a click away.
    await tester.tap(find.byKey(ValueKey('multiview-source-$xtream')));
    await openedPicker(tester);
    expect(inPicker('Panel News'), findsOneWidget);
    await pickChannel(tester, 'Free 2', sourceId: free);

    expect(find.byKey(pickerKey), findsNothing);
    final second = engineFor(rig, freeUrl('f2'));
    expect(second.lastRequest!.url, freeUrl('f2'));
    expect(inSlot(1, find.text('Free 2')), findsOneWidget);
    expect(isActive(1), isTrue);
    expect(isActive(0), isFalse);
    expect(second.muted, isFalse);
    expect(first.muted, isTrue);
    expect(second.lite, isFalse);
    expect(first.lite, isTrue);
    // Both hold a connection; the first stream never stopped.
    expect(containerOf(tester).read(multiViewTilesProvider), {
      0: xtream,
      1: free,
    });
    expect(first.count('stop'), 0);
    expect(rig.played.last, (free, 'f2'));
    await disposeRig(tester, rig);
  });

  testWidgets('the sound stays where it was while the picker is open, and '
      'after it is closed without a pick', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpSplitApp(tester, rig);
    await openSplit(tester, liveRequest(id));
    final one = engineFor(rig, '/ch1.');
    await tester.tap(inSlot(1, find.byKey(const ValueKey('multiview-add'))));
    await openedPicker(tester);
    expect(find.byKey(pickerKey), findsOneWidget);
    expect(isActive(0), isTrue);
    expect(one.muted, isFalse);
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byKey(pickerKey), findsNothing);
    expect(isActive(0), isTrue);
    expect(one.muted, isFalse);
    // A click beside the picker closes it too.
    await tester.tap(inSlot(1, find.byKey(const ValueKey('multiview-add'))));
    await openedPicker(tester);
    await tester.tapAt(const Offset(1200, 360));
    await settle(tester);
    expect(find.byKey(pickerKey), findsNothing);
    expect(one.muted, isFalse);
    await disposeRig(tester, rig);
  });

  forLocales((locale) {
    testWidgets('a one-connection subscription in use in tile 1 is refused '
        'with a clear message; another source still works '
        '(${locale.languageCode})', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final xtream = await seedXtream(rig);
      final free = await seedFree(rig);
      await pumpSplitApp(tester, rig, locale: locale);
      final l10n = await AppLocalizations.delegate.load(locale);
      await openSplit(tester, xtreamRequest(xtream, '501'));
      final created = rig.engines.created.length;

      await tester.tap(inSlot(1, find.byKey(const ValueKey('multiview-add'))));
      await openedPicker(tester);
      await pickChannel(tester, 'Panel Sport', sourceId: xtream);

      expect(find.byKey(_inUse), findsOneWidget);
      expect(find.text(l10n.multiviewNoConnectionTitle), findsOneWidget);
      final message = l10n.multiviewInUseTile('Panel', 1);
      expect(find.text(message), findsOneWidget);
      expect(message, contains('Panel'));
      expect(message, contains('1'));
      // Nothing opened; the picker stays for another channel.
      expect(rig.engines.created, hasLength(created));
      expect(rig.openedUrls.where((u) => u.contains('/502.')), isEmpty);
      await tester.tap(find.byKey(const ValueKey('multiview-in-use-ok')));
      await settle(tester);
      expect(find.byKey(_inUse), findsNothing);
      expect(find.byKey(pickerKey), findsOneWidget);
      expect(containerOf(tester).read(multiViewTilesProvider), {0: xtream});

      await pickChannel(tester, 'Free 1', sourceId: free);
      expect(find.byKey(pickerKey), findsNothing);
      expect(engineFor(rig, freeUrl('f1')).opened, hasLength(1));
      await disposeRig(tester, rig);
    });
  });

  testWidgets('a two-connection subscription plays in two tiles; a third '
      'is refused', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final xtream = await seedXtream(rig);
    await rig.db.sourcesDao.updateAccount(
      xtream,
      const AccountInfo(maxConnections: 2, allowedFormats: ['ts', 'm3u8']),
    );
    await pumpSplitApp(tester, rig);
    final l10n = await AppLocalizations.delegate.load(en);
    await openSplit(tester, xtreamRequest(xtream, '501'));
    await addChannel(tester, 1, 'Panel Sport');
    expect(engineFor(rig, '/502.').opened, hasLength(1));
    await press(tester, LogicalKeyboardKey.keyL);
    await addChannel(tester, 2, 'Panel News', sourceId: xtream);
    // The message says where the connections are.
    final places = l10n.multiviewPlacesAnd(
      l10n.multiviewPlaceTile(1),
      l10n.multiviewPlaceTile(2),
    );
    expect(places, 'tile 1 and tile 2');
    expect(
      find.text(l10n.multiviewInUseManyAt('Panel', 2, places)),
      findsOneWidget,
    );
    expect(containerOf(tester).read(multiViewTilesProvider), {
      0: xtream,
      1: xtream,
    });
    await disposeRig(tester, rig);
  });

  testWidgets('a separate window holding the connection is named', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final xtream = await seedXtream(rig);
    final free = await seedFree(rig);
    await pumpSplitApp(
      tester,
      rig,
      locale: ar,
      windows: [
        DetachedViewer(
          id: 3,
          sourceId: xtream,
          channelKey: '502',
          title: 'Panel Sport',
          maxConnections: 1,
          status: ViewerStatus.playing,
        ),
      ],
    );
    final l10n = await AppLocalizations.delegate.load(ar);
    await openSplit(tester, freeRequest(free, 'f1'));
    await tester.tap(inSlot(1, find.byKey(const ValueKey('multiview-add'))));
    await openedPicker(tester);
    await pickChannel(tester, 'Panel News', sourceId: xtream);
    expect(find.text(l10n.multiviewInUseWindow('Panel')), findsOneWidget);
    expect(rig.openedUrls.where((u) => u.contains('/501.')), isEmpty);
    await disposeRig(tester, rig);
  });

  forLocales((locale) {
    final rtl = locale == ar;
    testWidgets('clicks and arrows move the active tile, mirrored in Arabic; '
        'the sound follows it (${locale.languageCode})', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await pumpSplitApp(tester, rig, locale: locale);
      await openSplit(tester, liveRequest(id));
      await addChannel(tester, 1, 'Channel 2');
      final one = engineFor(rig, '/ch1.');
      final two = engineFor(rig, '/ch2.');
      expect(isActive(1), isTrue);

      // The first tile is at the start: left in English, right in Arabic.
      final towardsFirst = rtl
          ? LogicalKeyboardKey.arrowRight
          : LogicalKeyboardKey.arrowLeft;
      final away = rtl
          ? LogicalKeyboardKey.arrowLeft
          : LogicalKeyboardKey.arrowRight;
      final first = tester.getCenter(slot(0));
      final second = tester.getCenter(slot(1));
      expect(rtl ? first.dx > second.dx : first.dx < second.dx, isTrue);

      await press(tester, towardsFirst);
      expect(isActive(0), isTrue);
      expect(one.muted, isFalse);
      expect(two.muted, isTrue);
      expect(one.lite, isFalse);
      expect(two.lite, isTrue);
      // The edge: nothing further.
      await press(tester, towardsFirst);
      expect(isActive(0), isTrue);
      await press(tester, away);
      expect(isActive(1), isTrue);
      expect(two.muted, isFalse);
      expect(one.muted, isTrue);

      await click(tester, slot(0));
      expect(isActive(0), isTrue);
      expect(one.muted, isFalse);
      expect(two.muted, isTrue);

      // Four tiles: Down and Up too.
      await press(tester, LogicalKeyboardKey.keyL);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(isActive(2), isTrue);
      await press(tester, away);
      expect(isActive(3), isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(isActive(1), isTrue);
      await disposeRig(tester, rig);
    });
  });

  testWidgets('M mutes the active tile; it stays muted when active again', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpSplitApp(tester, rig);
    await openSplit(tester, liveRequest(id));
    await addChannel(tester, 1, 'Channel 2');
    final one = engineFor(rig, '/ch1.');
    final two = engineFor(rig, '/ch2.');
    await press(tester, LogicalKeyboardKey.keyM);
    expect(two.muted, isTrue);
    expect(one.muted, isTrue);
    expect(
      inSlot(1, find.byKey(const ValueKey('multiview-muted'))),
      findsOneWidget,
    );
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(one.muted, isFalse);
    expect(two.muted, isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(one.muted, isTrue);
    expect(two.muted, isTrue);
    await press(tester, LogicalKeyboardKey.keyM);
    expect(two.muted, isFalse);
    await disposeRig(tester, rig);
  });

  testWidgets('a double click and Enter maximize and restore; the others '
      'keep playing, hidden', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpSplitApp(tester, rig);
    await openSplit(tester, liveRequest(id));
    await addChannel(tester, 1, 'Channel 2');
    final one = engineFor(rig, '/ch1.');

    await doubleTap(tester, slot(0));
    expect(slot(1), findsNothing);
    expect(
      find.byKey(const ValueKey('multiview-slot-1'), skipOffstage: false),
      findsOneWidget,
    );
    expect(tester.getSize(slot(0)), const Size(1280, 720));
    expect(one.muted, isFalse);
    final two = engineFor(rig, '/ch2.');
    expect(one.count('stop'), 0);
    expect(two.count('stop'), 0);
    // Arrows wait while one tile is alone.
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(one.muted, isFalse);

    await doubleTap(tester, slot(0));
    expect(slot(1), findsOneWidget);
    expect(tester.getSize(slot(0)), const Size(640, 720));

    await press(tester, LogicalKeyboardKey.enter);
    expect(slot(1), findsNothing);
    await press(tester, LogicalKeyboardKey.enter);
    expect(slot(1), findsOneWidget);
    await disposeRig(tester, rig);
  });

  testWidgets("C changes the active tile's channel on the same player; the "
      'hover button too', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    final free = await seedFree(rig);
    await pumpSplitApp(tester, rig);
    final l10n = await AppLocalizations.delegate.load(en);
    await openSplit(tester, liveRequest(id));
    final engine = engineFor(rig, '/ch1.');

    await press(tester, LogicalKeyboardKey.keyC);
    await openedPicker(tester);
    expect(
      find.descendant(
        of: find.byKey(pickerKey),
        matching: find.text(l10n.multiviewChangeChannel),
      ),
      findsOneWidget,
    );
    await pickChannel(tester, 'Channel 3');
    expect(engine.opened.last.url, 'http://127.0.0.1:9/live/ch3.ts');
    expect(engine.calls, containsAllInOrder(['open', 'stop', 'open']));
    expect(inSlot(0, find.text('Channel 3')), findsOneWidget);
    expect(containerOf(tester).read(multiViewTilesProvider), {0: id});

    // The mouse: the hover button, to another source.
    await mouseAt(tester, tester.getCenter(slot(0)));
    await tester.tap(inSlot(0, find.byKey(const ValueKey('multiview-change'))));
    await openedPicker(tester);
    await pickChannel(tester, 'Free 3', sourceId: free);
    expect(engine.opened.last.url, freeUrl('f3'));
    expect(containerOf(tester).read(multiViewTilesProvider), {0: free});
    await disposeRig(tester, rig);
  });

  testWidgets('Delete and the Remove button empty a tile, stop its stream '
      'and free its connection', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final xtream = await seedXtream(rig);
    final free = await seedFree(rig);
    await pumpSplitApp(tester, rig);
    await openSplit(tester, xtreamRequest(xtream, '501'));
    await addChannel(tester, 1, 'Free 1', sourceId: free);
    final one = engineFor(rig, '/501.');
    final two = engineFor(rig, freeUrl('f1'));

    await press(tester, LogicalKeyboardKey.delete);
    expect(two.count('stop'), 1);
    expect(two.disposed, isTrue);
    expect(
      inSlot(1, find.byKey(const ValueKey('multiview-add'))),
      findsOneWidget,
    );
    expect(containerOf(tester).read(multiViewTilesProvider), {0: xtream});

    await mouseAt(tester, tester.getCenter(slot(0)));
    await tester.tap(inSlot(0, find.byKey(const ValueKey('multiview-remove'))));
    await settle(tester);
    expect(one.disposed, isTrue);
    expect(containerOf(tester).read(multiViewTilesProvider), isEmpty);
    expect(rig.wakelock.last, isFalse);

    // The subscription's connection is free again for a tile.
    await addChannel(tester, 1, 'Panel Sport', sourceId: xtream);
    expect(find.byKey(_inUse), findsNothing);
    expect(engineFor(rig, '/502.').opened, hasLength(1));
    await disposeRig(tester, rig);
  });

  testWidgets('D plays the active tile in a separate window once its stream '
      'stopped, and empties the tile', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final xtream = await seedXtream(rig);
    final windows = await pumpSplitApp(tester, rig, locale: ar);
    await openSplit(tester, xtreamRequest(xtream, '501'));
    final engine = engineFor(rig, '/501.');
    final url = engine.lastRequest!.url;

    await press(tester, LogicalKeyboardKey.keyD);
    await settleSplit(tester);
    final request = windows.detached.single;
    expect(request.sourceId, xtream);
    expect(request.channelKey, '501');
    expect(request.title, 'Panel News');
    expect(request.stream.url, url);
    expect(request.maxConnections, 1);
    expect(request.secrets, contains('Secret-Pass-9'));
    expect(request.locale, 'ar');
    // One connection: the tile's stream stopped before the window opened.
    final log = windows.engineLogAtDetach.single;
    expect(
      log.lastIndexOf('mpv.stop'),
      greaterThan(log.lastIndexOf('mpv.open $url')),
    );
    expect(engine.disposed, isTrue);
    expect(
      inSlot(0, find.byKey(const ValueKey('multiview-add'))),
      findsOneWidget,
    );
    expect(containerOf(tester).read(multiViewTilesProvider), isEmpty);
    expect(find.byType(MultiViewScreen), findsOneWidget);
    await disposeRig(tester, rig);
  });

  testWidgets('the hover button detaches too; a failed window says so', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    final windows = await pumpSplitApp(tester, rig);
    windows.fail = true;
    await openSplit(tester, liveRequest(id, key: 'ch4'));
    await mouseAt(tester, tester.getCenter(slot(0)));
    await tester.tap(inSlot(0, find.byKey(const ValueKey('multiview-detach'))));
    await settleSplit(tester);
    expect(windows.detached.single.channelKey, 'ch4');
    expect(find.text("Couldn't open the separate window."), findsOneWidget);
    await disposeRig(tester, rig);
  });

  testWidgets('L and the layout button switch 2 and 4 tiles; back to 2 keeps '
      'the active tile and the next one', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpSplitApp(tester, rig);
    final l10n = await AppLocalizations.delegate.load(en);
    await openSplit(tester, liveRequest(id));
    expect(slot(2), findsNothing);

    await mouseAt(tester, const Offset(640, 400));
    expect(find.byKey(const ValueKey('multiview-bar')), findsOneWidget);
    expect(find.byTooltip(l10n.multiviewFourChannels), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('multiview-layout')));
    await settle(tester);
    expect(slot(3), findsOneWidget);
    expect(tester.getSize(slot(0)), const Size(640, 360));

    await addChannel(tester, 1, 'Channel 2');
    await addChannel(tester, 2, 'Channel 3');
    final one = engineFor(rig, '/ch1.');
    final two = engineFor(rig, '/ch2.');
    final three = engineFor(rig, '/ch3.');
    expect(isActive(2), isTrue);

    // Kept: tile 3 (active) and the next with a channel, tile 1.
    await press(tester, LogicalKeyboardKey.keyL);
    expect(slot(2), findsNothing);
    expect(inSlot(0, find.text('Channel 1')), findsOneWidget);
    expect(inSlot(1, find.text('Channel 3')), findsOneWidget);
    expect(isActive(1), isTrue);
    expect(three.muted, isFalse);
    expect(one.muted, isTrue);
    expect(two.disposed, isTrue);
    expect(one.disposed, isFalse);
    expect(three.disposed, isFalse);
    // The kept tiles kept their streams.
    expect(one.opened, hasLength(1));
    expect(three.opened, hasLength(1));
    expect(containerOf(tester).read(multiViewTilesProvider).values, [id, id]);
    await disposeRig(tester, rig);
  });

  testWidgets('back to 2 from an empty active tile keeps the next two with '
      'a channel', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await pumpSplitApp(tester, rig);
    await openSplit(tester, liveRequest(id));
    await press(tester, LogicalKeyboardKey.keyL);
    await addChannel(tester, 1, 'Channel 2');
    await addChannel(tester, 3, 'Channel 4');
    final two = engineFor(rig, '/ch2.');
    final four = engineFor(rig, '/ch4.');
    // The empty tile 3 is active: nothing is heard.
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(isActive(2), isTrue);
    expect(four.muted, isTrue);

    await press(tester, LogicalKeyboardKey.keyL);
    // Tiles 4 and 1 (after tile 3, wrapping around) stay; tile 4 is heard.
    expect(inSlot(0, find.text('Channel 1')), findsOneWidget);
    expect(inSlot(1, find.text('Channel 4')), findsOneWidget);
    expect(isActive(1), isTrue);
    expect(four.muted, isFalse);
    expect(two.disposed, isTrue);
    await disposeRig(tester, rig);
  });
}
