import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/live/live_models.dart';
import 'package:iptv_player/features/live/live_screen.dart';
import 'package:iptv_player/features/live/providers.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';

import 'support/live_test_utils.dart';

void main() {
  for (final rtl in [false, true]) {
    final locale = Locale(rtl ? 'ar' : 'en');
    final l10n = lookupAppLocalizations(locale);

    testWidgets('${locale.languageCode}: three panes cross with mirrored '
        'arrows and remember their item', (tester) async {
      final db = openAppTestDb();
      await seedThreeCategories(db);
      await pumpLiveApp(tester, db, locale: locale);
      final live = tester.state<LiveViewState>(find.byType(LiveView));
      expect(live.selected, const LiveList.all());

      // Panes run from the start side: categories, channels, info.
      final catX = tester.getCenter(find.text(l10n.liveAllChannels)).dx;
      final chX = tester.getCenter(find.text('Channel 1')).dx;
      final railX = tester
          .getCenter(find.byKey(const ValueKey('rail-live')))
          .dx;
      expect(rtl ? railX > catX : railX < catX, isTrue);
      expect(rtl ? catX > chX : catX < chX, isTrue);

      // The shell starts on the rail; entering the page lands on the
      // current channel.
      expect(focusedIn(const ValueKey('rail-live')), isTrue);
      await press(tester, toEnd(rtl));
      expectFocusOn('Channel 1');

      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Channel 3');

      // Toward the end: the info pane shows the channel, Play focused.
      await press(tester, toEnd(rtl));
      expectFocusOn(l10n.vodPlay);
      expect(find.byKey(const ValueKey('live-info-k3')), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn(l10n.liveAddFavorite);

      // Back toward the start: the channel we left; the info pane remembers
      // its button.
      await press(tester, toStart(rtl));
      expectFocusOn('Channel 3');
      await press(tester, toEnd(rtl));
      expectFocusOn(l10n.liveAddFavorite);
      await press(tester, toStart(rtl));
      expectFocusOn('Channel 3');
      await press(tester, toStart(rtl));
      expectFocusOn(l10n.liveAllChannels);

      // Down to News; it opens after a short rest.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('News');
      await wait(tester, LiveView.selectDelay);
      expect(live.selected, const LiveList.category('news'));
      await press(tester, toEnd(rtl));
      expectFocusOn('Channel 1');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Channel 2');

      // The info pane follows the focused channel.
      await press(tester, toEnd(rtl));
      expect(find.byKey(const ValueKey('live-info-k2')), findsOneWidget);
      expectFocusOn(l10n.vodPlay);

      // Back to the categories, then the rail; re-entering the page returns
      // to the pane we left.
      await press(tester, toStart(rtl));
      await press(tester, toStart(rtl));
      expectFocusOn('News');
      await press(tester, toStart(rtl));
      expect(focusedIn(const ValueKey('rail-live')), isTrue);
      await press(tester, toEnd(rtl));
      expectFocusOn('News');

      // Moving quickly to a category and straight on opens it at once.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Sports');
      await press(tester, toEnd(rtl));
      expect(live.selected, const LiveList.category('sports'));
      expectFocusOn('Channel 11');

      // Back: channels -> categories -> rail.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expectFocusOn('Sports');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(focusedIn(const ValueKey('rail-live')), isTrue);
      await disposeApp(tester, db);
    });
  }

  testWidgets('Back from the info pane returns to the channel; the list '
      'shown last is saved and comes back on the next start', (tester) async {
    final db = openAppTestDb();
    final id = await seedThreeCategories(db);
    await pumpLiveApp(tester, db);
    expect(await db.settingsDao.getString(liveLastListKey(id)), isNull);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expectFocusOn('Sports');
    await press(tester, LogicalKeyboardKey.select);
    expectFocusOn('Channel 11');
    expect(await db.settingsDao.getString(liveLastListKey(id)), 'cat:sports');
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.byKey(const ValueKey('live-info-k12')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expectFocusOn('Channel 12');

    // A new app start on the same database reopens Sports.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await pumpLiveApp(tester, db);
    final live = tester.state<LiveViewState>(find.byType(LiveView));
    expect(live.selected, const LiveList.category('sports'));
    expect(find.text('Channel 11'), findsOneWidget);
    expect(find.text('Channel 1'), findsNothing);
    await disposeApp(tester, db);
  });
}
