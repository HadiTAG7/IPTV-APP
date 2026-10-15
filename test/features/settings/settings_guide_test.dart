import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/secure/secret_store.dart';
import 'package:iptv_player/epg/epg_progress.dart';
import 'package:iptv_player/features/settings/settings_dialogs.dart';
import 'package:iptv_player/features/settings/settings_screen.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/sources/models.dart';

import '../../support/text_entry.dart';
import 'settings_harness.dart';

const _xtreamUrl =
    'http://127.0.0.1:9/xmltv.php?username=alice&password=s3cret';
const _playlistUrl = 'http://127.0.0.1:9/guide.xml.gz';
const _manualUrl = 'http://127.0.0.1:9/manual.xml';
final _fetchedAt = DateTime.utc(2026, 10, 14, 9, 30);

/// Guide sources seeded by [_seedGuides].
late int _xtreamId;
late int _playlistId;
late int _manualId;

Future<void> _seedGuides(AppDatabase db, int sourceId) async {
  final epg = db.epgDao;
  _xtreamId = await epg.addEpgSource(sourceId, _xtreamUrl, EpgOrigin.xtream);
  _playlistId = await epg.addEpgSource(
    sourceId,
    _playlistUrl,
    EpgOrigin.m3uHeader,
    priority: 1,
  );
  _manualId = await epg.addEpgSource(
    sourceId,
    _manualUrl,
    EpgOrigin.manual,
    priority: 2,
  );
  await epg.recordFetch(
    _playlistId,
    at: _fetchedAt,
    status: EpgSourceStatus(EpgStatusKind.ok, null, _fetchedAt).encode(),
    programmeCount: 1234,
  );
  // A failed attempt: status only, no import time.
  await (db.update(db.epgSources)..where((e) => e.id.equals(_manualId))).write(
    EpgSourcesCompanion(
      status: Value(
        EpgSourceStatus(EpgStatusKind.error, 'HTTP 404', _fetchedAt).encode(),
      ),
    ),
  );
}

Key _rowKey(int id) => ValueKey('settings-epg-$id');
Key _deleteKey(int id) => ValueKey('settings-epg-$id-delete');

/// Every text drawn on screen.
Iterable<String> _drawnText(WidgetTester tester) =>
    tester.allWidgets.whereType<RichText>().map((w) => w.text.toPlainText());

Finder _rowText(Key row, String text) =>
    find.descendant(of: find.byKey(row), matching: find.textContaining(text));

void main() {
  for (final rtl in [false, true]) {
    final lang = rtl ? 'ar' : 'en';
    final AppLocalizations l10n = rtl ? ar : en;
    final locale = Locale(lang);

    testWidgets('$lang TV: guide URLs show origin, status and counts', (
      tester,
    ) async {
      final h = await pumpSettingsApp(
        tester,
        locale: locale,
        seed: _seedGuides,
      );
      await openSettingsTv(tester);
      expect(find.text(l10n.settings_guideFor('Home')), findsOneWidget);

      // Remote order: player rows, then the guide URLs, then Add.
      await moveTo(tester, const ValueKey('settings-aspect'));
      for (final id in [_xtreamId, _playlistId, _manualId]) {
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(focusedIn(_rowKey(id)), isTrue, reason: focusDescription());
      }
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('settings-epgAdd')), isTrue);

      // Xtream: masked URL, never loaded yet.
      expect(
        _rowText(_rowKey(_xtreamId), 'xmltv.php?username=***&password=***'),
        findsOneWidget,
      );
      expect(
        _rowText(_rowKey(_xtreamId), l10n.settings_epgOriginXtream),
        findsOneWidget,
      );
      expect(
        _rowText(_rowKey(_xtreamId), l10n.settings_epgStatusNever),
        findsOneWidget,
      );
      // Playlist guide: loaded, programme count and import time.
      final playlist = _rowKey(_playlistId);
      expect(_rowText(playlist, _playlistUrl), findsOneWidget);
      expect(_rowText(playlist, l10n.settings_epgOriginPlaylist), findsOne);
      expect(_rowText(playlist, l10n.settings_epgStatusOk), findsOneWidget);
      expect(
        _rowText(playlist, l10n.settings_programmeCount(1234)),
        findsOneWidget,
      );
      expect(
        _rowText(playlist, l10n.settings_epgLastImport(_fetchedAt.toLocal())),
        findsOneWidget,
      );
      // Manual guide: failed, with the reason; the only one with Delete.
      final manual = _rowKey(_manualId);
      expect(_rowText(manual, l10n.settings_epgOriginManual), findsOneWidget);
      expect(_rowText(manual, l10n.settings_epgStatusFailed), findsOneWidget);
      expect(_rowText(manual, 'HTTP 404'), findsOneWidget);
      expect(find.byKey(_deleteKey(_manualId)), findsOneWidget);
      expect(find.byKey(_deleteKey(_xtreamId)), findsNothing);
      expect(find.byKey(_deleteKey(_playlistId)), findsNothing);
      // URLs read left to right in both languages.
      final url = tester.widget<Text>(
        find.descendant(
          of: find.byKey(playlist),
          matching: find.text(_playlistUrl),
        ),
      );
      expect(url.textDirection, TextDirection.ltr);
      // ...but they line up with the other text on the start side.
      expect(url.textAlign, rtl ? TextAlign.right : TextAlign.left);
      expect(_drawnText(tester).any((t) => t.contains('password=***')), isTrue);

      // The credentials of the Xtream guide are never drawn.
      for (final text in _drawnText(tester)) {
        expect(text, isNot(contains('s3cret')));
        expect(text, isNot(contains('alice')));
      }
      await h.dispose(tester);
    });

    testWidgets('$lang TV: deleting a manual guide URL asks first', (
      tester,
    ) async {
      final h = await pumpSettingsApp(
        tester,
        locale: locale,
        seed: _seedGuides,
      );
      await openSettingsTv(tester);

      // Automatic guides have nothing on their end side.
      await moveTo(tester, _rowKey(_xtreamId));
      await press(tester, toEnd(rtl));
      expect(focusedIn(_rowKey(_xtreamId)), isTrue);

      await moveTo(tester, _rowKey(_manualId));
      await press(tester, toEnd(rtl));
      expect(focusedIn(_deleteKey(_manualId)), isTrue);
      final rowX = tester.getCenter(find.byKey(_rowKey(_manualId))).dx;
      final deleteX = tester.getCenter(find.byKey(_deleteKey(_manualId))).dx;
      expect(rtl ? deleteX < rowX : deleteX > rowX, isTrue);

      // Back on the confirmation keeps the guide.
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text(l10n.settings_deleteEpgUrlBody), findsOneWidget);
      expect(focusedIn(const ValueKey('confirm-ok')), isTrue);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(await h.db.epgDao.epgSourceById(_manualId), isNotNull);
      expect(focusedIn(_deleteKey(_manualId)), isTrue);
      expect(h.refreshCalls, isEmpty);

      // OK deletes it; focus moves to Add instead of the top of the page.
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, LogicalKeyboardKey.select);
      expect(await h.db.epgDao.epgSourceById(_manualId), isNull);
      expect(find.byKey(_rowKey(_manualId)), findsNothing);
      expect(focusedIn(const ValueKey('settings-epgAdd')), isTrue);
      expect((await h.db.epgDao.epgSources(h.sourceId)).map((r) => r.id), [
        _xtreamId,
        _playlistId,
      ]);
      // The channels it covered move to the remaining guides at once.
      expect(h.refreshCalls, [(sourceId: h.sourceId, force: false)]);
      await h.dispose(tester);
    });

    testWidgets('$lang TV: the guide offset steps by 30 minutes within '
        '-12:00..+14:00', (tester) async {
      final h = await pumpSettingsApp(tester, locale: locale);
      await openSettingsTv(tester);
      await moveTo(tester, const ValueKey('settings-epgOffset'));
      expect(
        _rowText(
          const ValueKey('settings-epgOffset'),
          l10n.settings_epgOffsetNone,
        ),
        findsOneWidget,
      );
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(EpgOffsetDialog), findsOneWidget);
      expect(focusedIn(const ValueKey('offset-stepper')), isTrue);
      String shown() =>
          tester.widget<Text>(find.byKey(const ValueKey('offset-value'))).data!;
      expect(shown(), '0:00');

      // The arrow toward the end side adds (mirrored in Arabic).
      await press(tester, toEnd(rtl));
      expect(shown(), '+0:30');
      await press(tester, toStart(rtl));
      await press(tester, toStart(rtl));
      expect(shown(), '-0:30');
      final laterX = tester
          .getCenter(find.byKey(const ValueKey('offset-later')))
          .dx;
      final earlierX = tester
          .getCenter(find.byKey(const ValueKey('offset-earlier')))
          .dx;
      expect(rtl ? laterX < earlierX : laterX > earlierX, isTrue);

      // Bounded at +14:00 and -12:00.
      for (var i = 0; i < 32; i++) {
        await press(tester, toEnd(rtl));
      }
      expect(shown(), '+14:00');
      for (var i = 0; i < 60; i++) {
        await press(tester, toStart(rtl));
      }
      expect(shown(), '-12:00');
      expect(focusedIn(const ValueKey('offset-stepper')), isTrue);

      // Down goes to Save, not to the nearer Cancel; OK stores the offset.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(
        focusedIn(const ValueKey('offset-save')),
        isTrue,
        reason: focusDescription(),
      );
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(EpgOffsetDialog), findsNothing);
      expect((await h.source()).epgOffsetMin, -12 * 60);
      // A changed offset re-imports every guide.
      expect(h.refreshCalls, [(sourceId: h.sourceId, force: true)]);
      final value = tester.widget<Text>(
        _rowText(const ValueKey('settings-epgOffset'), '-12:00'),
      );
      expect(value.textDirection, TextDirection.ltr);
      expect(focusedIn(const ValueKey('settings-epgOffset')), isTrue);

      // Back discards a change.
      await press(tester, LogicalKeyboardKey.select);
      expect(shown(), '-12:00');
      await press(tester, toEnd(rtl));
      expect(shown(), '-11:30');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect((await h.source()).epgOffsetMin, -12 * 60);
      expect(h.refreshCalls, hasLength(1));
      await h.dispose(tester);
    });

    testWidgets('$lang TV: OK on the guide offset saves it; Cancel stays '
        'one step from Save', (tester) async {
      final h = await pumpSettingsApp(tester, locale: locale);
      await openSettingsTv(tester);
      const row = ValueKey('settings-epgOffset');
      await moveTo(tester, row);
      await press(tester, LogicalKeyboardKey.select);
      String shown() =>
          tester.widget<Text>(find.byKey(const ValueKey('offset-value'))).data!;
      await press(tester, toEnd(rtl));
      await press(tester, toEnd(rtl));
      expect(shown(), '+1:00');
      // OK on the value saves it.
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(EpgOffsetDialog), findsNothing);
      expect((await h.source()).epgOffsetMin, 60);
      expect(h.refreshCalls, [(sourceId: h.sourceId, force: true)]);
      expect(focusedIn(row), isTrue, reason: focusDescription());

      // Cancel is next to Save and discards the change.
      await press(tester, LogicalKeyboardKey.select);
      expect(shown(), '+1:00');
      await press(tester, toEnd(rtl));
      expect(shown(), '+1:30');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('offset-save')), isTrue);
      await press(tester, toStart(rtl));
      expect(focusedIn(const ValueKey('offset-cancel')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedIn(const ValueKey('offset-stepper')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('offset-save')), isTrue);
      await press(tester, toStart(rtl));
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(EpgOffsetDialog), findsNothing);
      expect((await h.source()).epgOffsetMin, 60);
      expect(h.refreshCalls, hasLength(1));
      expect(focusedIn(row), isTrue);
      await h.dispose(tester);
    });

    testWidgets('$lang TV: Down from the guide URL goes to Add', (
      tester,
    ) async {
      final h = await pumpSettingsApp(tester, locale: locale);
      await openSettingsTv(tester);
      await moveTo(tester, const ValueKey('settings-epgAdd'));
      await press(tester, LogicalKeyboardKey.select);
      expect(focusedIn(const ValueKey('epg-url-field')), isTrue);
      await typeText(
        tester,
        find.byKey(const ValueKey('epg-url-field')),
        'https://example.com/guide.xml',
      );
      await settle(tester);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(
        focusedIn(const ValueKey('epg-url-add')),
        isTrue,
        reason: focusDescription(),
      );
      // Cancel is one step toward the start; Up returns to the field.
      await press(tester, toStart(rtl));
      expect(focusedIn(const ValueKey('epg-url-cancel')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedIn(const ValueKey('epg-url-field')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('epg-url-add')), isTrue);

      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(AddEpgUrlDialog), findsNothing);
      final rows = await h.db.epgDao.epgSources(h.sourceId);
      expect(rows.map((r) => r.url), ['https://example.com/guide.xml']);
      expect(h.refreshCalls, [(sourceId: h.sourceId, force: false)]);
      expect(focusedIn(const ValueKey('settings-epgAdd')), isTrue);
      await h.dispose(tester);
    });
  }

  testWidgets('TV: OK switches a guide URL off and on', (tester) async {
    final h = await pumpSettingsApp(tester, seed: _seedGuides);
    await openSettingsTv(tester);
    final row = _rowKey(_playlistId);
    await moveTo(tester, row);

    await press(tester, LogicalKeyboardKey.select);
    expect((await h.db.epgDao.epgSourceById(_playlistId))!.enabled, isFalse);
    expect(_rowText(row, en.commonOff), findsOneWidget);
    // The channels this guide covered move to the other guides at once.
    expect(h.refreshCalls, [(sourceId: h.sourceId, force: false)]);
    expect(focusedIn(row), isTrue);

    await press(tester, LogicalKeyboardKey.select);
    expect((await h.db.epgDao.epgSourceById(_playlistId))!.enabled, isTrue);
    expect(_rowText(row, en.settings_epgStatusOk), findsOneWidget);
    // Switching a guide on fetches what it is missing.
    expect(h.refreshCalls, [
      (sourceId: h.sourceId, force: false),
      (sourceId: h.sourceId, force: false),
    ]);
    expect(focusedIn(row), isTrue);
    await h.dispose(tester);
  });

  testWidgets('TV: adding a guide URL checks it and saves it as manual', (
    tester,
  ) async {
    final h = await pumpSettingsApp(tester, seed: _seedGuides);
    await openSettingsTv(tester);
    await moveTo(tester, const ValueKey('settings-epgAdd'));
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byType(AddEpgUrlDialog), findsOneWidget);
    // The field has focus.
    expect(focusedIn(const ValueKey('epg-url-field')), isTrue);

    final field = find.byKey(const ValueKey('epg-url-field'));
    final add = find.byKey(const ValueKey('epg-url-add'));
    await typeText(tester, field, 'not a url');
    await tester.tap(add);
    await settle(tester);
    expect(find.text(en.errorInvalidUrl), findsOneWidget);

    // A URL that is already listed.
    await typeText(tester, field, _playlistUrl);
    await settle(tester);
    expect(find.text(en.errorInvalidUrl), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text(en.settings_epgUrlExists), findsOneWidget);
    expect(await h.db.epgDao.epgSources(h.sourceId), hasLength(3));

    // A new one, with credentials.
    const typed = 'http://127.0.0.1:9/epg.xml?username=bob&password=pw123';
    await typeText(tester, field, typed);
    await tester.tap(add);
    await settle(tester);
    expect(find.byType(AddEpgUrlDialog), findsNothing);

    final rows = await h.db.epgDao.epgSources(h.sourceId);
    expect(rows, hasLength(4));
    final added = rows.last;
    expect(added.origin, EpgOrigin.manual);
    expect(added.enabled, isTrue);
    expect(added.priority, greaterThan(2));
    expect(added.url, 'http://127.0.0.1:9/epg.xml?username=***&password=***');
    expect(await h.db.epgDao.epgSourceUrl(added.id), typed);
    expect(h.refreshCalls, [(sourceId: h.sourceId, force: false)]);

    expect(find.byKey(_rowKey(added.id)), findsOneWidget);
    expect(find.byKey(_deleteKey(added.id)), findsOneWidget);
    expect(focusedIn(const ValueKey('settings-epgAdd')), isTrue);
    for (final text in _drawnText(tester)) {
      expect(text, isNot(contains('pw123')));
    }
    // The secret is stored for the fetcher only.
    expect(
      await DbSecretStore(h.db).read(h.sourceId, SecretNames.epgUrl(added.id)),
      typed,
    );
    await h.dispose(tester);
  });

  testWidgets('TV: Cancel adds nothing', (tester) async {
    final h = await pumpSettingsApp(tester);
    await openSettingsTv(tester);
    await moveTo(tester, const ValueKey('settings-epgAdd'));
    expect(find.byKey(const ValueKey('settings-epg-empty')), findsOneWidget);
    expect(find.text(en.settings_epgNoUrls), findsOneWidget);
    await press(tester, LogicalKeyboardKey.select);
    await typeText(
      tester,
      find.byKey(const ValueKey('epg-url-field')),
      'https://example.com/a.xml',
    );
    await tester.tap(find.byKey(const ValueKey('epg-url-cancel')));
    await settle(tester);
    expect(find.byType(AddEpgUrlDialog), findsNothing);
    expect(await h.db.epgDao.epgSources(h.sourceId), isEmpty);
    expect(h.refreshCalls, isEmpty);
    await h.dispose(tester);
  });

  testWidgets('TV: Refresh guide asks the guide service for a full refresh', (
    tester,
  ) async {
    final pending = Completer<void>();
    final calls = <({int sourceId, bool force})>[];
    final h = await pumpSettingsApp(
      tester,
      seed: (db, id) => db.sourcesDao.markEpgFetched(id, _fetchedAt),
      refresh: (id, {required force}) {
        calls.add((sourceId: id, force: force));
        return pending.future;
      },
    );
    await openSettingsTv(tester);
    const row = ValueKey('settings-epgRefresh');
    expect(
      _rowText(row, en.guideUpdated(_fetchedAt.toLocal())),
      findsOneWidget,
    );
    await moveTo(tester, row);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls, [(sourceId: h.sourceId, force: true)]);
    expect(find.text(en.guideUpdating), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(row),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    // A second OK while it runs does nothing.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(calls, hasLength(1));
    expect(focusedIn(row), isTrue);

    pending.complete();
    await settle(tester);
    expect(
      find.descendant(
        of: find.byKey(row),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    await h.dispose(tester);
  });

  testWidgets('phone: Refresh guide keeps key focus while it runs', (
    tester,
  ) async {
    final pending = Completer<void>();
    final calls = <RefreshCall>[];
    final h = await pumpSettingsApp(
      tester,
      tv: false,
      refresh: (id, {required force}) {
        calls.add((sourceId: id, force: force));
        return pending.future;
      },
    );
    await openSettingsPhone(tester);
    const row = ValueKey('settings-epgRefresh');
    Finder spinner() => find.descendant(
      of: find.byKey(row),
      matching: find.byType(CircularProgressIndicator),
    );
    await moveTo(tester, row);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls, [(sourceId: h.sourceId, force: true)]);
    expect(spinner(), findsOneWidget);
    expect(focusedIn(row), isTrue, reason: focusDescription());
    // A second OK while it runs does nothing.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(calls, hasLength(1));
    expect(focusedIn(row), isTrue, reason: focusDescription());

    pending.complete();
    await settle(tester);
    expect(spinner(), findsNothing);
    expect(focusedIn(row), isTrue, reason: focusDescription());
    await h.dispose(tester);
  });

  testWidgets('a failing guide refresh is logged, not thrown', (tester) async {
    final h = await pumpSettingsApp(
      tester,
      refresh: (id, {required force}) async => throw StateError(
        'offline: http://127.0.0.1:9/xmltv.php?username=alice&password=s3cret',
      ),
    );
    await openSettingsTv(tester);
    await moveTo(tester, const ValueKey('settings-epgRefresh'));
    await press(tester, LogicalKeyboardKey.select);
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('settings-epgRefresh')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    final lines = h.log.lines;
    expect(
      lines.where((l) => l.contains('Guide refresh failed')),
      hasLength(1),
    );
    expect(lines.any((l) => l.contains('offline')), isTrue);
    for (final line in lines) {
      expect(line, isNot(contains('s3cret')));
      expect(line, isNot(contains('alice')));
    }
    await h.dispose(tester);
  });

  testWidgets('phone: guide URLs are list tiles; taps toggle and delete', (
    tester,
  ) async {
    final h = await pumpSettingsApp(tester, tv: false, seed: _seedGuides);
    await openSettingsPhone(tester);
    final row = _rowKey(_manualId);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-epgInterval')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.descendant(of: find.byKey(row), matching: find.byType(ListTile)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(row));
    await settle(tester);
    expect((await h.db.epgDao.epgSourceById(_manualId))!.enabled, isFalse);
    await tester.tap(
      find.descendant(of: find.byKey(row), matching: find.byType(Switch)),
    );
    await settle(tester);
    expect((await h.db.epgDao.epgSourceById(_manualId))!.enabled, isTrue);

    await tester.tap(find.byKey(_deleteKey(_manualId)));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-ok')));
    await settle(tester);
    expect(await h.db.epgDao.epgSourceById(_manualId), isNull);
    expect(find.byKey(row), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('the Add guide URL dialog keeps working after Settings is '
      'gone', (tester) async {
    final h = await pumpSettingsApp(tester, tv: false);
    // A large phone in landscape gets the rail, with a Settings tab.
    tester.view.physicalSize = const Size(915, 412) * 2;
    await settle(tester);
    await tester.tap(find.byKey(settingsRail));
    await settle(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-epgAdd')),
      100,
      scrollable: find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('settings-epgAdd')));
    await settle(tester);
    expect(find.byType(AddEpgUrlDialog), findsOneWidget);

    // Portrait: the phone shell has no Settings tab, so the page is gone
    // while the dialog stays.
    tester.view.physicalSize = const Size(412, 915) * 2;
    await settle(tester);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(AddEpgUrlDialog), findsOneWidget);

    await typeText(
      tester,
      find.byKey(const ValueKey('epg-url-field')),
      'https://example.com/a.xml',
    );
    await tester.tap(find.byKey(const ValueKey('epg-url-add')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(AddEpgUrlDialog), findsNothing);
    final rows = await h.db.epgDao.epgSources(h.sourceId);
    expect(rows.map((r) => r.url), ['https://example.com/a.xml']);
    expect(rows.single.origin, EpgOrigin.manual);
    expect(h.refreshCalls, [(sourceId: h.sourceId, force: false)]);
    await h.dispose(tester);
  });

  testWidgets('TV: a running guide refresh only busies its own source', (
    tester,
  ) async {
    final pending = Completer<void>();
    final calls = <RefreshCall>[];
    late int homeId;
    late int otherId;
    final h = await pumpSettingsApp(
      tester,
      seed: (db, id) async {
        homeId = id;
        otherId = await db.sourcesDao.create(
          const SourceConfig(
            kind: SourceKind.m3uUrl,
            url: 'http://127.0.0.1:9/other.m3u',
            name: 'Other',
          ),
        );
        await db.sourcesDao.markSynced(otherId, DateTime.now());
      },
      refresh: (id, {required force}) {
        calls.add((sourceId: id, force: force));
        return id == homeId ? pending.future : Future<void>.value();
      },
    );
    await openSettingsTv(tester);
    expect(find.text(en.settings_guideFor('Home')), findsOneWidget);
    const row = ValueKey('settings-epgRefresh');
    Finder spinner() => find.descendant(
      of: find.byKey(row),
      matching: find.byType(CircularProgressIndicator),
    );
    await moveTo(tester, row);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls, [(sourceId: homeId, force: true)]);
    expect(spinner(), findsOneWidget);

    // Another source becomes active while Home's refresh runs.
    await h
        .container(tester)
        .read(activeSourceIdProvider.notifier)
        .select(otherId);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(en.settings_guideFor('Other')), findsOneWidget);
    expect(spinner(), findsNothing);
    expect(focusedIn(row), isTrue, reason: focusDescription());
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(calls, [
      (sourceId: homeId, force: true),
      (sourceId: otherId, force: true),
    ]);

    // Back on Home, its refresh is still running.
    await h
        .container(tester)
        .read(activeSourceIdProvider.notifier)
        .select(homeId);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(spinner(), findsOneWidget);
    pending.complete();
    await settle(tester);
    expect(spinner(), findsNothing);
    await h.dispose(tester);
  });
}
