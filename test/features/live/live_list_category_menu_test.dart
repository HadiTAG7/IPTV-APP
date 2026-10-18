// Deleting and renaming a user list from its Live category menu (remote
// and mouse).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/features/live/live_models.dart';
import 'package:iptv_player/features/live/live_screen.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';

import '../../support/text_entry.dart';
import 'support/live_test_utils.dart';

LiveViewState liveState(WidgetTester tester) =>
    tester.state<LiveViewState>(find.byType(LiveView));

ValueKey<String> cat(String id) => ValueKey('live-category-$id');

void main() {
  for (final rtl in [false, true]) {
    final locale = Locale(rtl ? 'ar' : 'en');
    final l10n = lookupAppLocalizations(locale);

    Future<({int source, int alpha, int beta})> seed(AppDatabase db) async {
      final id = await seedThreeCategories(db);
      final alpha = await db.channelListsDao.createList(
        id,
        'Alpha',
        channels: ['k3', 'k4'],
      );
      final beta = await db.channelListsDao.createList(
        id,
        'Beta',
        channels: ['k5', 'k6'],
      );
      return (source: id, alpha: alpha, beta: beta);
    }

    Future<void> deleteFocusedList(WidgetTester tester) async {
      await press(tester, LogicalKeyboardKey.contextMenu);
      expectFocusOn(l10n.liveRenameList);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn(l10n.liveDeleteList);
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, toEnd(rtl));
      expect(focusedIn(const ValueKey('delete-list-confirm')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
    }

    testWidgets('${locale.languageCode}: delete the selected list from its '
        'category menu; focus on neighbour, Up then moves', (tester) async {
      final db = openAppTestDb();
      final s = await seed(db);
      await db.settingsDao.setString(
        'live.lastList.${s.source}',
        'list:${s.alpha}',
      );
      await pumpLiveApp(
        tester,
        db,
        locale: locale,
        overrides: [
          targetPlatformProvider.overrideWithValue(TargetPlatform.linux),
        ],
      );
      expect(liveState(tester).selected, LiveList.channelList(s.alpha));
      await press(tester, toEnd(rtl));
      expectFocusOn('Channel 3');
      await press(tester, toStart(rtl));
      expect(focusedIn(cat('list:${s.alpha}')), isTrue);
      // Down to Beta (it opens after the pause).
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(cat('list:${s.beta}')), isTrue);
      await wait(tester, LiveView.selectDelay);
      expect(liveState(tester).selected, LiveList.channelList(s.beta));

      await deleteFocusedList(tester);
      await settle(tester);
      expect(await db.channelListsDao.listById(s.beta), isNull);
      expect(find.byKey(cat('list:${s.beta}')), findsNothing);
      expect(focusedIn(cat('list:${s.alpha}')), isTrue);
      expect(tester.takeException(), isNull);

      // The entry above the neighbour is Favorites.
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(
        focusedIn(cat('fav')),
        isTrue,
        reason: 'still on Alpha: ${focusedIn(cat('list:${s.alpha}'))}',
      );
      await disposeApp(tester, db);
    });

    testWidgets('${locale.languageCode}: desktop: long press delete of an '
        'unselected list leaves focus and selection alone', (tester) async {
      final db = openAppTestDb();
      final s = await seed(db);
      await pumpLiveApp(
        tester,
        db,
        locale: locale,
        overrides: [
          targetPlatformProvider.overrideWithValue(TargetPlatform.linux),
        ],
      );
      expect(liveState(tester).selected, const LiveList.all());
      await press(tester, toEnd(rtl));
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocusOn('Channel 2');
      // Mouse: long press on Beta (not selected, not focused).
      await tester.longPress(find.byKey(cat('list:${s.beta}')));
      await settle(tester);
      await tester.tap(find.text(l10n.liveDeleteList));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('delete-list-confirm')));
      await settle(tester);
      expect(await db.channelListsDao.listById(s.beta), isNull);
      await wait(tester, LiveView.selectDelay);
      expect(
        liveState(tester).selected,
        const LiveList.all(),
        reason: 'focus on Alpha: ${focusedIn(cat('list:${s.alpha}'))}',
      );
      await disposeApp(tester, db);
    });

    testWidgets('${locale.languageCode}: rename from the category menu '
        'updates the label and keeps focus', (tester) async {
      final db = openAppTestDb();
      final s = await seed(db);
      await db.settingsDao.setString(
        'live.lastList.${s.source}',
        'list:${s.alpha}',
      );
      await pumpLiveApp(
        tester,
        db,
        locale: locale,
        overrides: [
          targetPlatformProvider.overrideWithValue(TargetPlatform.linux),
        ],
      );
      await press(tester, toEnd(rtl));
      await press(tester, toStart(rtl));
      expect(focusedIn(cat('list:${s.alpha}')), isTrue);
      await press(tester, LogicalKeyboardKey.contextMenu);
      expectFocusOn(l10n.liveRenameList);
      await press(tester, LogicalKeyboardKey.select);
      await typeText(
        tester,
        find.byKey(const ValueKey('channel-list-name-field')),
        'Omega',
      );
      await settle(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      await settle(tester);
      expect((await db.channelListsDao.listById(s.alpha))!.name, 'Omega');
      expect(
        find.descendant(
          of: find.byKey(cat('list:${s.alpha}')),
          matching: find.text('Omega'),
        ),
        findsOneWidget,
      );
      expect(focusedIn(cat('list:${s.alpha}')), isTrue);
      await disposeApp(tester, db);
    });
  }
}
