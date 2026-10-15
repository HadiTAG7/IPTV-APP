import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/app.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/app/shell_phone.dart';
import 'package:iptv_player/app/shell_tv.dart';
import 'package:iptv_player/features/live/live_screen.dart';
import 'package:iptv_player/features/onboarding/onboarding_screen.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';

import 'app_harness.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  testWidgets('no sources: onboarding; first source: the shell', (
    tester,
  ) async {
    final db = openAppTestDb();
    await pumpApp(tester, db: db);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
    expect(find.text(en.onboardingWelcomeTitle), findsOneWidget);

    final id = await addTestSource(db);
    await settle(tester);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(PhoneShell), findsOneWidget);
    expect(find.byType(LiveScreen), findsOneWidget);

    // Deleting the last source returns to onboarding.
    await db.sourcesDao.deleteSource(id);
    await settle(tester);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await disposeApp(tester, db);
  });

  testWidgets('one source on a TV opens the rail shell in Arabic', (
    tester,
  ) async {
    final db = openAppTestDb();
    await addTestSource(db, name: 'Salon', lastSyncAt: DateTime.now());
    await pumpApp(
      tester,
      db: db,
      caps: tvCaps,
      settings: const AppSettings(locale: AppLocaleSetting.ar),
    );
    expect(find.byType(TvShell), findsOneWidget);
    expect(find.text(ar.navLive), findsWidgets);
    expect(find.text('Salon'), findsOneWidget);
    final context = tester.element(find.byType(TvShell));
    expect(Directionality.of(context), TextDirection.rtl);
    await disposeApp(tester, db);
  });

  testWidgets('onboarding hold keeps onboarding over a saved source', (
    tester,
  ) async {
    final db = openAppTestDb();
    await pumpApp(tester, db: db);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(IptvApp)),
    );
    container.read(onboardingHoldProvider.notifier).set(true);
    await addTestSource(db);
    await settle(tester);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    container.read(onboardingHoldProvider.notifier).set(false);
    await settle(tester);
    expect(find.byType(HomeShell), findsOneWidget);
    await disposeApp(tester, db);
  });

  test('app locale: Arabic or English, else English', () {
    const supported = [Locale('ar'), Locale('en')];
    expect(
      resolveAppLocale(const [Locale('ar', 'SA')], supported),
      const Locale('ar'),
    );
    expect(
      resolveAppLocale(const [Locale('fr'), Locale('en', 'GB')], supported),
      const Locale('en'),
    );
    expect(
      resolveAppLocale(const [Locale('de')], supported),
      const Locale('en'),
    );
    expect(resolveAppLocale(null, supported), const Locale('en'));
  });
}
