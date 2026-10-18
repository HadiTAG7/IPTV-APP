// The user's channel lists in the player: "Add to list…" in the Menu-key
// options (live only), and zapping within a list opened from the Live
// screen. All data is synthetic.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/live/channel_source.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/player/ui/player_screen.dart';

import '../support/text_entry.dart';
import 'support/player_harness.dart';

String _url(String key) => 'http://127.0.0.1:9/live/$key.ts';

/// Opens the Menu-key options and moves to "Add to list…".
Future<void> _openAddToList(WidgetTester tester, AppLocalizations l10n) async {
  await press(tester, LogicalKeyboardKey.contextMenu);
  expect(find.text(l10n.player_options), findsOneWidget);
  for (var i = 0; i < 10; i++) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        find
            .descendant(
              of: find.byWidget(focused.widget),
              matching: find.text(l10n.liveAddToList),
            )
            .evaluate()
            .isNotEmpty) {
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text(l10n.liveAddToListTitle), findsOneWidget);
      return;
    }
    await press(tester, LogicalKeyboardKey.arrowDown);
  }
  fail('"Add to list…" not reached');
}

void main() {
  forLocales((locale) {
    final l10n = lookupAppLocalizations(locale);
    final rtl = locale == ar;
    final sports = rtl ? 'الرياضة' : 'Sports';
    final news = rtl ? 'الأخبار' : 'News';

    testWidgets('Add to list from the options adds to an existing and a new '
        'list (${locale.languageCode})', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      final dao = rig.db.channelListsDao;
      final listId = await dao.createList(id, sports);
      await pumpPlayerApp(tester, rig, locale: locale);
      await openPlayerFor(tester, liveRequest(id, key: 'ch2'));

      await _openAddToList(tester, l10n);
      expect(focusedIn(ValueKey('add-to-list-$listId')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text(l10n.liveListAdded(sports)), findsOneWidget);
      expect(await dao.channelKeys(listId), ['ch2']);
      expect(focusLabel, 'player');

      // "New list…" names a list holding the channel.
      await _openAddToList(tester, l10n);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('add-to-list-new')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      await typeText(
        tester,
        find.byKey(const ValueKey('channel-list-name-field')),
        news,
      );
      await settle(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text(l10n.liveListAdded(news)), findsOneWidget);
      final lists = await dao.lists(id);
      expect(lists.map((l) => (l.name, l.count)), [(sports, 1), (news, 1)]);
      expect(await dao.listsWithChannel(id, 'ch2'), {
        for (final l in lists) l.id,
      });
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(focusLabel, 'player');
      // Still playing the same channel.
      expect(rig.openedUrls, [_url('ch2')]);
      await disposeRig(tester, rig);
    });
  });

  testWidgets('movies have no Add to list', (tester) async {
    final rig = PlayerRig()..autoPlay(duration: const Duration(minutes: 90));
    final id = await seedVod(rig);
    await pumpPlayerApp(tester, rig);
    await openPlayerFor(tester, movieRequest(id));
    await press(tester, LogicalKeyboardKey.contextMenu);
    expect(find.text('Options'), findsOneWidget);
    expect(find.text('Add to list…'), findsNothing);
    await disposeRig(tester, rig);
  });

  testWidgets('a channel opened from a list zaps within the list', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    final listId = await rig.db.channelListsDao.createList(
      id,
      'Evening',
      channels: ['ch4', 'gone', 'ch2', 'ch5'],
    );
    // The request the Live screen builds for the list's channel 2.
    final source = ListChannelsSource(rig.db, id, listId);
    await source.count();
    final row = await rig.db.catalogDao.channelByKey(id, 'ch2');
    final request = await source.requestFor(row!);
    expect(request.zapKeys, ['ch4', 'ch2', 'ch5']);
    await pumpPlayerApp(tester, rig);
    await openPlayerFor(tester, request);
    Future<void> zap(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
    }

    await zap(LogicalKeyboardKey.arrowUp);
    expect(rig.openedUrls.last, _url('ch5'));
    // The end wraps to the start of the list, never to other channels.
    await zap(LogicalKeyboardKey.arrowUp);
    expect(rig.openedUrls.last, _url('ch4'));
    await zap(LogicalKeyboardKey.arrowDown);
    expect(rig.openedUrls.last, _url('ch5'));
    expect(rig.openedUrls, [
      _url('ch2'),
      _url('ch5'),
      _url('ch4'),
      _url('ch5'),
    ]);
    await disposeRig(tester, rig);
  });
}
