import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/features/onboarding/onboarding_screen.dart';
import 'package:iptv_player/features/sources/source_editor_screen.dart';
import 'package:iptv_player/features/sources/sources_screen.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/sources/source_repository.dart';
import 'package:iptv_player/sources/sync/sync_progress.dart';
import 'package:iptv_player/tv/tv_focusable.dart';

import '../../unit/db/db_test_utils.dart'
    show category, channel, movie, series, syncCatalog;
import 'support.dart';

final _now = DateTime(2026, 10, 15, 12);

/// Three sources: an active Xtream panel with a catalog that expires in 3
/// days, a never-imported playlist and a banned panel.
Future<({int home, int backup, int banned})> _seed(AppDatabase db) async {
  final sources = db.sourcesDao;
  final home = await sources.create(
    const SourceConfig(
      kind: SourceKind.xtream,
      url: 'http://127.0.0.1:9',
      name: 'Home Panel',
      username: 'homeUser',
      password: 'homePw',
    ),
  );
  await syncCatalog(
    db,
    home,
    categories: [
      category(ContentKind.live, 'news'),
      category(ContentKind.movie, 'films'),
      category(ContentKind.series, 'shows'),
    ],
    channels: [channel('1'), channel('2'), channel('3')],
    movies: [movie('m1'), movie('m2')],
    seriesList: [series('s1')],
  );
  await sources.updateAccount(
    home,
    AccountInfo(expiresAt: _now.add(const Duration(days: 3, hours: 1))),
  );
  await sources.markSynced(home, _now.subtract(const Duration(hours: 2)));
  await sources.setActive(home);
  final backup = await sources.create(
    const SourceConfig(
      kind: SourceKind.m3uUrl,
      url: 'http://127.0.0.1:9/backup.m3u',
      name: 'Backup list',
    ),
  );
  final banned = await sources.create(
    const SourceConfig(
      kind: SourceKind.xtream,
      url: 'http://127.0.0.1:9',
      name: 'Old box',
      username: 'oldUser',
      password: 'oldPw',
    ),
  );
  await sources.updateAccount(
    banned,
    const AccountInfo(status: AccountStatus.banned),
  );
  return (home: home, backup: backup, banned: banned);
}

/// A Settings stand-in that opens Sources like the real one.
Widget _pages(HomeTab tab) => switch (tab) {
  HomeTab.sources => const SourcesScreen(),
  HomeTab.live => Consumer(
    builder: (context, ref, _) => Align(
      alignment: AlignmentDirectional.topStart,
      child: TvFocusable(
        key: const ValueKey('open-sources'),
        onSelect: () => pushHomePage(context, ref, HomeTab.sources),
        child: const SizedBox(width: 160, height: 48, child: Text('Sources')),
      ),
    ),
  ),
  _ => FakeTabPage(tab),
};

String _text(WidgetTester tester, String key) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Text),
        matchRoot: true,
      ),
    )
    .map((t) => t.data ?? '')
    .join('|');

void main() {
  Future<void> openOnTv(WidgetTester tester, {required bool rtl}) async {
    await press(
      tester,
      rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight,
    );
    expectFocus('open-sources');
    await press(tester, LogicalKeyboardKey.select);
    await settleRoute(tester);
    expect(find.byType(SourcesScreen), findsOneWidget);
  }

  for (final rtl in [false, true]) {
    final name = rtl ? 'ar' : 'en';
    final l10n = rtl ? arL10n : enL10n;
    final toEnd = rtl
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight;
    final toStart = rtl
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;

    testWidgets('TV $name: details of every source', (tester) async {
      final db = openAppTestDb();
      final ids = await _seed(db);
      await pumpAppWith(
        tester,
        db: db,
        caps: tvCaps,
        clock: FakeClock(_now),
        settings: AppSettings(
          locale: rtl ? AppLocaleSetting.ar : AppLocaleSetting.en,
        ),
        pages: _pages,
      );
      await openOnTv(tester, rtl: rtl);

      expect(find.text('Home Panel'), findsWidgets);
      expect(find.text('Backup list'), findsOneWidget);
      expect(find.byKey(ValueKey('source-${ids.home}-active')), findsOneWidget);
      expect(
        _text(tester, 'source-${ids.home}-counts'),
        [
          l10n.importLiveCount(3),
          l10n.importMoviesCount(2),
          l10n.importSeriesCount(1),
        ].join(' · '),
      );
      final account = _text(tester, 'source-${ids.home}-account');
      expect(account, contains(l10n.settingsExpiresSoon));
      expect(account, contains(l10n.settingsExpiresInDays(3)));
      expect(
        _text(tester, 'source-${ids.home}-synced'),
        startsWith(l10n.settingsLastUpdated(_now)),
      );
      expect(
        _text(tester, 'source-${ids.backup}-synced'),
        l10n.sourcesNeverImported,
      );
      expect(find.byKey(ValueKey('source-${ids.backup}-counts')), findsNothing);
      expect(_text(tester, 'source-${ids.banned}-account'), l10n.errorBanned);
      // Credentials are never shown.
      expect(find.textContaining('homePw'), findsNothing);
      expect(find.textContaining('oldPw'), findsNothing);
      await disposeApp(tester, db);
    });

    testWidgets('TV $name: remote walk, set active and delete', (tester) async {
      final db = openAppTestDb();
      final ids = await _seed(db);
      await pumpAppWith(
        tester,
        db: db,
        caps: tvCaps,
        clock: FakeClock(_now),
        settings: AppSettings(
          locale: rtl ? AppLocaleSetting.ar : AppLocaleSetting.en,
        ),
        pages: _pages,
      );
      await openOnTv(tester, rtl: rtl);
      // The active source's first action has the focus.
      expectFocus('source-${ids.home}-refresh');
      await press(tester, toEnd);
      expectFocus('source-${ids.home}-edit');
      await press(tester, toEnd);
      expectFocus('source-${ids.home}-delete');
      await press(tester, toEnd);
      expectFocus('source-${ids.home}-delete');
      await press(tester, toStart);
      await press(tester, toStart);
      expectFocus('source-${ids.home}-refresh');
      // Up reaches Add source; Down walks the cards.
      await press(tester, LogicalKeyboardKey.arrowUp);
      expectFocus('sources-add');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedKey(), startsWith('source-${ids.home}-'));
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedKey(), startsWith('source-${ids.backup}-'));
      await pressN(tester, toStart, 4);
      expectFocus('source-${ids.backup}-activate');

      // Set active: the badge moves, focus stays on the card.
      await press(tester, LogicalKeyboardKey.select);
      expect(containerOf(tester).read(activeSourceIdProvider), ids.backup);
      expect(
        find.byKey(ValueKey('source-${ids.backup}-active')),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('source-${ids.home}-active')), findsNothing);
      expect(
        find.byKey(ValueKey('source-${ids.backup}-activate')),
        findsNothing,
      );
      expectFocus('source-${ids.backup}-refresh');
      expect(await db.sourcesDao.activeSourceId(), ids.backup);

      // Delete the banned one: Cancel is focused first and keeps it.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedKey(), startsWith('source-${ids.banned}-'));
      await pressN(tester, toEnd, 4);
      expectFocus('source-${ids.banned}-delete');
      await press(tester, LogicalKeyboardKey.select);
      expect(
        find.text(l10n.settingsDeleteSourceConfirm('Old box')),
        findsOneWidget,
      );
      expectFocus('delete-cancel');
      await press(tester, LogicalKeyboardKey.select);
      await settleRoute(tester);
      expect(find.text('Old box'), findsOneWidget);
      expectFocus('source-${ids.banned}-delete');

      await press(tester, LogicalKeyboardKey.select);
      expectFocus('delete-cancel');
      await press(tester, toEnd);
      expectFocus('delete-confirm');
      await press(tester, LogicalKeyboardKey.select);
      await settleRoute(tester);
      expect(find.text('Old box'), findsNothing);
      expect(await db.sourcesDao.byId(ids.banned), isNull);
      // Focus lands on the active source's card.
      expectFocus('source-${ids.backup}-refresh');

      // Back returns to the page that opened Sources.
      await back(tester);
      expect(find.byType(SourcesScreen), findsNothing);
      expectFocus('open-sources');
      await disposeApp(tester, db);
    });
  }

  testWidgets('refresh shows progress, cancels, and reports failures', (
    tester,
  ) async {
    final db = openAppTestDb();
    final ids = await _seed(db);
    final runner = ManualSyncRunner();
    await pumpAppWith(
      tester,
      db: db,
      clock: FakeClock(_now),
      runner: runner,
      pages: _pages,
    );
    await tapKey(tester, 'nav-more');
    await tapKey(tester, 'more-sources');
    await settleRoute(tester);
    expect(find.byType(SourcesScreen), findsOneWidget);
    final l10n = enL10n;

    await tapKey(tester, 'source-${ids.backup}-refresh');
    expect(runner.tasks.single.sourceId, ids.backup);
    expect(
      _text(tester, 'source-${ids.backup}-progress'),
      contains(l10n.importLiveCount(5)),
    );
    expect(_text(tester, 'source-${ids.backup}-refresh'), l10n.importCancel);
    // Cancel.
    await tapKey(tester, 'source-${ids.backup}-refresh');
    await settle(tester);
    expect(find.byKey(ValueKey('source-${ids.backup}-progress')), findsNothing);
    expect(find.byKey(ValueKey('source-${ids.backup}-error')), findsNothing);
    expect(_text(tester, 'source-${ids.backup}-refresh'), l10n.settingsRefresh);

    // A failure shows the reason.
    await tapKey(tester, 'source-${ids.backup}-refresh');
    runner.finish(
      SyncProgress(
        sourceId: ids.backup,
        phase: SyncPhase.failed,
        error: const VerifyError(VerifyErrorReason.notM3u),
      ),
    );
    await settle(tester);
    expect(
      _text(tester, 'source-${ids.backup}-error'),
      '${l10n.importFailed}: ${l10n.errorNotM3u}',
    );

    // Edit opens the editor for that source.
    await tapKey(tester, 'source-${ids.backup}-edit');
    await settleRoute(tester);
    expect(find.byType(SourceEditorScreen), findsOneWidget);
    expect(fieldText(tester, 'field-name'), 'Backup list');
    expect(fieldText(tester, 'field-url'), 'http://127.0.0.1:9/backup.m3u');
    await back(tester);
    expect(find.byType(SourcesScreen), findsOneWidget);

    // Add opens an empty editor.
    await tapKey(tester, 'sources-add');
    await settleRoute(tester);
    expect(find.text(l10n.settingsAddSource), findsWidgets);
    expect(fieldText(tester, 'field-name'), isEmpty);
    await back(tester);
    await disposeApp(tester, db);
  });

  testWidgets('deleting the last source returns to onboarding', (tester) async {
    final db = openAppTestDb();
    await db.sourcesDao.create(
      const SourceConfig(
        kind: SourceKind.m3uUrl,
        url: 'http://127.0.0.1:9/only.m3u',
        name: 'Only one',
      ),
    );
    await pumpAppWith(tester, db: db, pages: _pages);
    await tapKey(tester, 'nav-more');
    await tapKey(tester, 'more-sources');
    await settleRoute(tester);
    final id = (await db.sourcesDao.all()).single.id;
    await tapKey(tester, 'source-$id-delete');
    await tapKey(tester, 'delete-confirm');
    await settleRoute(tester);
    expect(find.byType(SourcesScreen), findsNothing);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(await db.sourcesDao.all(), isEmpty);
    await disposeApp(tester, db);
  });

  test('the expiry warning starts 7 days ahead', () {
    expect(kExpiryWarningDays, 7);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(l10n.settingsExpiresInDays(6), 'Expires in 6 days');
  });
}
