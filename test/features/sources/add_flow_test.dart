@Timeout(Duration(seconds: 120))
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/app.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/features/onboarding/onboarding_screen.dart';
import 'package:iptv_player/features/sources/import_progress_screen.dart';
import 'package:iptv_player/features/sources/source_editor_screen.dart';
import 'package:iptv_player/sources/models.dart';

import '../../support/fake_panel.dart';
import '../../support/real_http.dart';
import 'support.dart';

const _user = 'flowUser';
const _pass = 'Flow-Pw-42';

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(IptvApp)));

void main() {
  useRealHttp();

  Future<FakePanel> startPanel(WidgetTester tester) async {
    final panel = (await tester.runAsync(
      () => FakePanel.start(
        username: _user,
        password: _pass,
        mediaDir: null,
        liveCount: 12,
        vodCount: 6,
        seriesCount: 3,
      ),
    ))!;
    addTearDown(() => tester.runAsync(panel.close));
    return panel;
  }

  Future<int> countOf(WidgetTester tester, AppDatabase db, ContentKind k) =>
      tester
          .runAsync(() async {
            final id = (await db.sourcesDao.all()).single.id;
            return db.catalogDao.totalCount(id, k);
          })
          .then((v) => v!);

  for (final rtl in [false, true]) {
    final name = rtl ? 'ar' : 'en';
    testWidgets('TV $name: onboarding adds an Xtream source and lands home', (
      tester,
    ) async {
      final panel = await startPanel(tester);
      final db = openAppTestDb();
      await pumpApp(
        tester,
        db: db,
        caps: tvCaps,
        settings: AppSettings(
          locale: rtl ? AppLocaleSetting.ar : AppLocaleSetting.en,
        ),
        runner: inlineRunner(),
        fakePages: true,
      );
      expect(find.byType(OnboardingScreen), findsOneWidget);
      await pressN(tester, LogicalKeyboardKey.arrowDown, 2);
      expectFocus('onboarding-add-source');
      await press(tester, LogicalKeyboardKey.select);
      await settleRoute(tester);
      expect(find.byType(SourceEditorScreen), findsOneWidget);

      // Pick Xtream with the remote: toward the end of the type row.
      final toEnd = rtl
          ? LogicalKeyboardKey.arrowLeft
          : LogicalKeyboardKey.arrowRight;
      await pressN(tester, toEnd, 2);
      expectFocus('type-xtream');
      await press(tester, LogicalKeyboardKey.select);
      await typeInto(tester, 'field-server', panel.baseUrl);
      await typeInto(tester, 'field-username', _user);
      await typeInto(tester, 'field-password', _pass);
      // The password is obscured.
      final password = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('field-password')),
          matching: find.byType(EditableText),
        ),
      );
      expect(password.obscureText, isTrue);

      await tapKey(tester, 'save');
      await pumpUntil(
        tester,
        () => find.byType(HomeShell).evaluate().isNotEmpty,
        reason: 'the home shell',
      );
      await settleRoute(tester);
      expect(find.byType(SourceEditorScreen), findsNothing);
      expect(find.byType(ImportProgressScreen), findsNothing);
      expect(find.byType(OnboardingScreen), findsNothing);

      // The catalog is in, the source is active and saved without its
      // password in the sources table.
      expect(await countOf(tester, db, ContentKind.live), 12);
      expect(await countOf(tester, db, ContentKind.movie), 6);
      expect(await countOf(tester, db, ContentKind.series), 3);
      final container = _container(tester);
      final sources = (await tester.runAsync(db.sourcesDao.all))!;
      expect(sources.single.kind, SourceKind.xtream);
      expect(sources.single.name, '127.0.0.1');
      expect(container.read(activeSourceIdProvider), sources.single.id);
      expect(container.read(onboardingHoldProvider), isFalse);
      expect(sources.single.url, isNot(contains(_pass)));
      expect(container.read(ringLogProvider).dump(), isNot(contains(_pass)));

      await drainNetworkTimers(tester);
      await disposeApp(tester, db);
    });
  }

  testWidgets('phone: a get.php link is offered as Xtream and imported', (
    tester,
  ) async {
    final panel = await startPanel(tester);
    final db = openAppTestDb();
    await pumpApp(tester, db: db, runner: inlineRunner(), fakePages: true);
    await tapKey(tester, 'onboarding-add-source');
    await settleRoute(tester);
    expect(find.byKey(const ValueKey('convert-card')), findsNothing);
    await typeInto(tester, 'field-url', panel.m3uUrl(output: 'm3u8'));
    expect(find.text(enL10n.sourcesXtreamLinkTitle), findsOneWidget);
    expect(find.text(enL10n.sourcesXtreamLinkBody), findsOneWidget);

    await tapKey(tester, 'convert-xtream');
    expect(find.byKey(const ValueKey('convert-card')), findsNothing);
    expect(find.byKey(const ValueKey('field-server')), findsOneWidget);
    String text(String key) => tester
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(EditableText),
          ),
        )
        .controller
        .text;
    expect(text('field-server'), panel.baseUrl);
    expect(text('field-username'), _user);
    expect(text('field-password'), _pass);
    expect(find.text(enL10n.sourcesXtreamLinkConverted), findsOneWidget);
    // The password stays hidden unless revealed.
    bool obscured() => tester
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(const ValueKey('field-password')),
            matching: find.byType(EditableText),
          ),
        )
        .obscureText;
    expect(obscured(), isTrue);
    await tapKey(tester, 'toggle-password');
    expect(obscured(), isFalse);
    expect(find.text(enL10n.fieldHidePassword), findsOneWidget);
    await tapKey(tester, 'toggle-password');
    expect(obscured(), isTrue);

    await typeInto(tester, 'field-name', 'Living room');
    await tapKey(tester, 'save');
    await pumpUntil(
      tester,
      () => find.byType(HomeShell).evaluate().isNotEmpty,
      reason: 'the home shell',
    );
    final source = (await tester.runAsync(db.sourcesDao.all))!.single;
    expect(source.kind, SourceKind.xtream);
    expect(source.name, 'Living room');
    expect(source.liveFormat, LiveFormat.m3u8);
    expect(await countOf(tester, db, ContentKind.live), 12);
    await drainNetworkTimers(tester);
    await disposeApp(tester, db);
  });

  testWidgets('expired account: the editor shows the date, nothing saved', (
    tester,
  ) async {
    final panel = await startPanel(tester);
    panel.auth = FakeAuthMode.expired;
    final db = openAppTestDb();
    await pumpApp(tester, db: db, runner: inlineRunner(), fakePages: true);
    await tapKey(tester, 'onboarding-add-source');
    await settleRoute(tester);
    await tapKey(tester, 'type-xtream');
    await typeInto(tester, 'field-server', panel.baseUrl);
    await typeInto(tester, 'field-username', _user);
    await typeInto(tester, 'field-password', _pass);
    await tapKey(tester, 'save');
    final error = find.byKey(const ValueKey('editor-error'));
    await pumpUntil(
      tester,
      () => error.evaluate().isNotEmpty,
      reason: 'the error',
    );
    final message = tester
        .widgetList<Text>(
          find.descendant(of: error, matching: find.byType(Text)),
        )
        .map((t) => t.data)
        .join();
    expect(message, startsWith('This subscription expired on '));
    expect(message, isNot(contains(_pass)));
    expect(find.byType(ImportProgressScreen), findsNothing);
    expect(find.byType(SourceEditorScreen), findsOneWidget);
    expect((await tester.runAsync(db.sourcesDao.all))!, isEmpty);

    // Fixing the account and trying again works.
    panel.auth = FakeAuthMode.good;
    await tapKey(tester, 'save');
    await pumpUntil(
      tester,
      () => find.byType(HomeShell).evaluate().isNotEmpty,
      reason: 'the home shell',
    );
    await drainNetworkTimers(tester);
    await disposeApp(tester, db);
  });

  testWidgets('a failing import offers Retry and Edit; Edit keeps the source', (
    tester,
  ) async {
    final panel = await startPanel(tester);
    final db = openAppTestDb();
    await pumpApp(
      tester,
      db: db,
      caps: tvCaps,
      runner: inlineRunner(),
      fakePages: true,
    );
    await tapKey(tester, 'onboarding-add-source');
    await settleRoute(tester);
    await tapKey(tester, 'type-xtream');
    await typeInto(tester, 'field-server', panel.baseUrl);
    await typeInto(tester, 'field-username', _user);
    await typeInto(tester, 'field-password', _pass);
    // Banned between the check and the import.
    final container = _container(tester);
    final sub = container.listen(sourcesProvider, (_, next) {
      if ((next.value ?? const []).isNotEmpty) panel.auth = FakeAuthMode.banned;
    });
    addTearDown(sub.close);
    await tapKey(tester, 'save');
    await pumpUntil(
      tester,
      () => find.byKey(const ValueKey('import-retry')).evaluate().isNotEmpty,
      reason: 'the import failure',
    );
    expect(find.text(enL10n.errorBanned), findsOneWidget);
    // Onboarding stays underneath while the first source is not imported.
    expect(container.read(onboardingHoldProvider), isTrue);
    expectFocus('import-retry');

    // Back (or Edit) returns to the editor with the reason.
    await back(tester);
    expect(find.byType(ImportProgressScreen), findsNothing);
    expect(find.byType(SourceEditorScreen), findsOneWidget);
    expect(find.text(enL10n.errorBanned), findsOneWidget);
    final saved = (await tester.runAsync(db.sourcesDao.all))!;
    expect(saved, hasLength(1));

    // Leaving the editor releases onboarding: the shell takes over.
    await back(tester);
    expect(container.read(onboardingHoldProvider), isFalse);
    expect(find.byType(HomeShell), findsOneWidget);
    await drainNetworkTimers(tester);
    await disposeApp(tester, db);
  });
}
