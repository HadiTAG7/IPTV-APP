import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/features/sources/sources_screen.dart';
import 'package:iptv_player/sources/models.dart';

import 'support.dart';

void main() {
  for (final rtl in [false, true]) {
    final name = rtl ? 'ar' : 'en';
    final toContent = rtl
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight;
    final toRail = rtl
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;

    testWidgets('TV $name: as a rail tab it never steals the rail focus and '
        'its row start leads back to the rail', (tester) async {
      final db = openAppTestDb();
      final id = await db.sourcesDao.create(
        const SourceConfig(
          kind: SourceKind.m3uUrl,
          url: 'http://127.0.0.1:9/a.m3u',
          name: 'Salon',
        ),
      );
      await db.sourcesDao.markSynced(id, DateTime.now());
      await pumpAppWith(
        tester,
        db: db,
        caps: tvCaps,
        settings: AppSettings(
          locale: rtl ? AppLocaleSetting.ar : AppLocaleSetting.en,
        ),
        pages: (tab) =>
            tab == HomeTab.live ? const SourcesScreen() : FakeTabPage(tab),
      );
      expect(find.byType(SourcesScreen), findsOneWidget);
      // Built as the first tab, it leaves the focus on the rail.
      expectFocus('rail-live');

      await press(tester, toContent);
      expect(focusedKey(), anyOf('sources-add', 'source-$id-refresh'));
      // Along a card's action row, then past its start edge to the rail.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expectFocus('source-$id-refresh');
      await press(tester, toContent);
      expectFocus('source-$id-edit');
      await press(tester, toRail);
      expectFocus('source-$id-refresh');
      await press(tester, toRail);
      expectFocus('rail-live');
      // Back into the page lands on the remembered item.
      await press(tester, toContent);
      expectFocus('source-$id-refresh');
      await disposeApp(tester, db);
    });
  }
}
