// The Rename/Delete row above a list's channels does not overflow on a
// 360-wide phone with a large Android font in Arabic.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/favorites/favorites_screen.dart';

import '../live/support/live_test_utils.dart';

void main() {
  for (final (width, scale) in [(360.0, 1.15), (360.0, 1.3), (390.0, 1.3)]) {
    testWidgets('ar phone ${width}w x$scale: list header fits', (tester) async {
      final db = openAppTestDb();
      final id = await addTestSource(db, lastSyncAt: DateTime.now());
      await seedCatalog(
        db,
        id,
        categories: [liveCategory('news', 'News', 0)],
        channels: [for (var n = 1; n <= 5; n++) testChannel(n)],
      );
      final listId = await db.channelListsDao.createList(
        id,
        'الرياضة',
        channels: ['k1', 'k3'],
      );
      await pumpLiveApp(tester, db, tv: false, locale: const Locale('ar'));
      tester.view.physicalSize = Size(width, 780) * 2;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('more-favorites')));
      await tester.pumpAndSettle();
      expect(find.byType(FavoritesView), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('favorites-tab-list-$listId')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('favorites-list-delete')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await disposeApp(tester, db);
    });
  }
}
