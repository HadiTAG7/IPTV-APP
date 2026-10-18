// On a computer the Favorites tab row scrolls by mouse once the user's lists
// fill it: the wheel moves it sideways and an arrow pages it.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';

import '../live/support/live_test_utils.dart';

const _forward = ValueKey('row-scroll-forward');
const _back = ValueKey('row-scroll-back');
const _newList = ValueKey('favorites-tab-new-list');

Future<void> _seed(AppDatabase db) async {
  final id = await addTestSource(db, lastSyncAt: DateTime.now());
  await seedCatalog(
    db,
    id,
    categories: [liveCategory('news', 'News', 0)],
    channels: [for (var n = 1; n <= 10; n++) testChannel(n)],
  );
  for (var i = 1; i <= 12; i++) {
    await db.channelListsDao.createList(
      id,
      'beIN Sports $i',
      channels: ['k1', 'k2'],
    );
  }
}

Future<void> _openFavorites(WidgetTester tester, bool rtl) async {
  final steps = HomeTab.tvTabs.indexOf(HomeTab.favorites);
  for (var i = 0; i < steps; i++) {
    await press(tester, LogicalKeyboardKey.arrowDown);
  }
  await press(
    tester,
    rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight,
  );
}

Future<void> _wheel(WidgetTester tester, Offset at, double dy) async {
  final mouse = TestPointer(7, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(mouse.hover(at));
  await tester.sendEventToBinding(mouse.scroll(Offset(0, dy)));
  await settle(tester);
}

bool _onScreen(WidgetTester tester, Finder f) {
  final r = tester.getRect(f);
  final w = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  return r.left >= 0 && r.right <= w;
}

void main() {
  for (final rtl in [false, true]) {
    final locale = Locale(rtl ? 'ar' : 'en');
    testWidgets('${locale.languageCode}: the wheel and the arrows reach '
        'every list tab', (tester) async {
      final db = openAppTestDb();
      await _seed(db);
      await pumpLiveApp(
        tester,
        db,
        locale: locale,
        overrides: [
          targetPlatformProvider.overrideWithValue(TargetPlatform.windows),
        ],
      );
      await _openFavorites(tester, rtl);
      expect(find.byKey(_newList).hitTestable(), findsNothing);
      expect(find.byKey(_forward), findsOneWidget);
      expect(find.byKey(_back), findsNothing);
      // The arrow sits at the row's far end: left in Arabic.
      final width = tester.view.physicalSize.width / 2;
      final arrowX = tester.getCenter(find.byKey(_forward)).dx;
      expect(rtl ? arrowX < width / 2 : arrowX > width / 2, isTrue);

      // The wheel over the row moves it sideways.
      final row = tester.getCenter(
        find.byKey(const ValueKey('favorites-tab-live')),
      );
      for (
        var i = 0;
        i < 40 && find.byKey(_forward).evaluate().isNotEmpty;
        i++
      ) {
        await _wheel(tester, Offset(width / 2, row.dy), 120);
      }
      expect(find.byKey(_forward), findsNothing);
      expect(_onScreen(tester, find.byKey(_newList)), isTrue);
      expect(find.byKey(_back), findsOneWidget);

      // The back arrow pages toward the start.
      for (var i = 0; i < 20 && find.byKey(_back).evaluate().isNotEmpty; i++) {
        await tester.tap(find.byKey(_back));
        await tester.pumpAndSettle();
      }
      expect(
        _onScreen(tester, find.byKey(const ValueKey('favorites-tab-live'))),
        isTrue,
      );
      await disposeApp(tester, db);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }
}
