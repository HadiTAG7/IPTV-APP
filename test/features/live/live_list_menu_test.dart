// A long press on a user's list chip in Live (phone) offers rename and
// delete, like the list's tab in Favorites.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/live/category_chips.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';

import 'support/live_test_utils.dart';

final chipRow = find.descendant(
  of: find.byType(LiveCategoryChips),
  matching: find.byType(Scrollable),
);

void main() {
  for (final rtl in [false, true]) {
    final locale = Locale(rtl ? 'ar' : 'en');
    final l10n = lookupAppLocalizations(locale);
    testWidgets('${locale.languageCode}: long press on a list chip offers '
        'rename and delete', (tester) async {
      final db = openAppTestDb();
      final id = await seedThreeCategories(db);
      final listId = await db.channelListsDao.createList(
        id,
        rtl ? 'الرياضة' : 'Sports',
        channels: ['k3'],
      );
      await pumpLiveApp(tester, db, tv: false, locale: locale);
      final chip = find.byKey(ValueKey('live-chip-list:$listId'));
      await tester.scrollUntilVisible(chip, -200, scrollable: chipRow);
      await settle(tester);
      await tester.longPress(chip);
      await settle(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text(l10n.liveRenameList), findsOneWidget);
      expect(find.text(l10n.liveDeleteList), findsOneWidget);
      await disposeApp(tester, db);
    });
  }
}
