// The Arabic empty-favourites hint does not call the Menu key by the word
// the "New list…" tab beside it uses for a list.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/favorites/favorites_screen.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';

import '../live/support/live_test_utils.dart';

void main() {
  testWidgets('Arabic empty favourites hint does not say القائمة next to '
      'the New list tab', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('ar'));
    final db = openAppTestDb();
    await seedThreeCategories(db);
    await pumpLiveApp(tester, db, tv: false, locale: const Locale('ar'));
    await tester.tap(find.byKey(const ValueKey('nav-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('more-favorites')));
    await tester.pumpAndSettle();
    expect(find.byType(FavoritesView), findsOneWidget);
    expect(find.text(l10n.favoritesEmpty), findsOneWidget);
    expect(
      find.byKey(const ValueKey('favorites-tab-new-list')),
      findsOneWidget,
    );
    expect(l10n.favoritesEmpty.contains('القائمة'), isFalse);
    await disposeApp(tester, db);
  });
}
