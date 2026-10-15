@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/secure/secret_store.dart';
import 'package:iptv_player/features/lan_input/providers.dart';
import 'package:iptv_player/features/sources/import_progress_screen.dart';
import 'package:iptv_player/features/sources/providers.dart';
import 'package:iptv_player/features/sources/source_editor_screen.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/sources/source_repository.dart';
import 'package:iptv_player/sources/sync/sync_progress.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../support/fake_panel.dart';
import '../../support/real_http.dart';
import 'support.dart';

const _down = LogicalKeyboardKey.arrowDown;
const _up = LogicalKeyboardKey.arrowUp;

void main() {
  useRealHttp();

  late Directory temp;
  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    temp = Directory.systemTemp.createTempSync('editor_test');
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  /// Opens the editor from onboarding.
  Future<void> openEditor(WidgetTester tester) async {
    await tapKey(tester, 'onboarding-add-source');
    await settleRoute(tester);
    expect(find.byType(SourceEditorScreen), findsOneWidget);
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

    testWidgets('TV $name: the editor is reachable with the remote only', (
      tester,
    ) async {
      final db = openAppTestDb();
      await pumpAppWith(
        tester,
        db: db,
        caps: tvCaps,
        settings: AppSettings(
          locale: rtl ? AppLocaleSetting.ar : AppLocaleSetting.en,
        ),
      );
      await pressN(tester, _down, 2);
      await press(tester, LogicalKeyboardKey.select);
      await settleRoute(tester);
      expect(find.text(l10n.settingsAddSource), findsOneWidget);
      expectFocus('type-m3uUrl');

      // The type row: mirrored arrows, dead ends at both edges.
      final urlX = tester.getCenter(find.byKey(const ValueKey('type-m3uUrl')));
      final xtX = tester.getCenter(find.byKey(const ValueKey('type-xtream')));
      expect(rtl ? urlX.dx > xtX.dx : urlX.dx < xtX.dx, isTrue);
      await press(tester, toStart);
      expectFocus('type-m3uUrl');
      await press(tester, toEnd);
      expectFocus('type-m3uFile');
      await press(tester, toEnd);
      expectFocus('type-xtream');
      await press(tester, toEnd);
      expectFocus('type-xtream');
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byKey(const ValueKey('field-server')), findsOneWidget);

      // Down through every control of the Xtream form.
      const order = [
        'field-name',
        'field-server',
        'field-username',
        'field-password',
        'toggle-password',
        'type-on-phone',
        'advanced',
        'save',
      ];
      for (final key in order) {
        await press(tester, _down);
        expectFocus(key);
      }
      await press(tester, _down);
      expectFocus('save');
      // And back up.
      for (final key in order.reversed.skip(1)) {
        await press(tester, _up);
        expectFocus(key);
      }
      await press(tester, _up);
      expect(focusedKey(), startsWith('type-'));

      // TvTextField: typed text keeps Left/Right inside the field until
      // the caret reaches the end; Up/Down always leave a one-line field.
      await press(tester, _down);
      expectFocus('field-name');
      await typeText(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('field-name')),
          matching: find.byType(EditableText),
        ),
        'Salon',
      );
      await settle(tester);
      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const ValueKey('field-name')),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.textEditingValue.selection.baseOffset, 5);
      // Toward the start moves the caret, not the focus.
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expectFocus('field-name');
      expect(editable.textEditingValue.selection.baseOffset, 4);
      // Nothing beside the field: the edge keeps focus in it.
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expectFocus('field-name');
      await press(tester, _down);
      expectFocus('field-server');
      await press(tester, _up);
      expectFocus('field-name');

      // The reveal toggle with OK.
      await pressN(tester, _down, 4);
      expectFocus('toggle-password');
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text(l10n.fieldHidePassword), findsOneWidget);
      expectFocus('toggle-password');

      // Advanced options open below with OK and are walked the same way.
      await pressN(tester, _down, 2);
      expectFocus('advanced');
      await press(tester, LogicalKeyboardKey.select);
      expectFocus('advanced');
      // Down lands on the nearest User-Agent chip; the row is walked with
      // mirrored arrows and ends at Default on the start side.
      await press(tester, _down);
      expect(focusedKey(), startsWith('ua-'));
      await pressN(tester, toStart, 6);
      expectFocus('ua-Default');
      await press(tester, toEnd);
      expectFocus('ua-VLC');
      await press(tester, toStart);
      expectFocus('ua-Default');
      // Down from the chip rows reaches the fields, then the formats.
      var guard = 0;
      while (focusedKey() != 'field-referer' && guard++ < 4) {
        await press(tester, _down);
      }
      expectFocus('field-referer');
      await press(tester, _down);
      expectFocus('field-epg');
      await press(tester, _down);
      expect(focusedKey(), startsWith('format-'));
      await press(tester, _down);
      expectFocus('save');

      // Back leaves the editor for onboarding.
      await back(tester);
      expect(find.byType(SourceEditorScreen), findsNothing);
      expectFocus('onboarding-add-source');
      await disposeApp(tester, db);
    });

    testWidgets('phone $name: validation errors and focus on the first', (
      tester,
    ) async {
      final db = openAppTestDb();
      await pumpAppWith(
        tester,
        db: db,
        settings: AppSettings(
          locale: rtl ? AppLocaleSetting.ar : AppLocaleSetting.en,
        ),
      );
      await openEditor(tester);

      // M3U link: required, then invalid.
      await tapKey(tester, 'save');
      expect(find.text(l10n.fieldRequired), findsOneWidget);
      expectFocus('field-url');
      await typeInto(tester, 'field-url', 'example.com/list.m3u');
      expect(find.text(l10n.errorInvalidUrl), findsOneWidget);
      await typeInto(tester, 'field-url', 'http://example.com/list.m3u');
      expect(find.text(l10n.errorInvalidUrl), findsNothing);

      // Xtream: three required fields; focus on the server.
      await tapKey(tester, 'type-xtream');
      await tapKey(tester, 'save');
      expect(find.text(l10n.fieldRequired), findsNWidgets(3));
      expectFocus('field-server');
      await typeInto(tester, 'field-server', 'bad host');
      expect(find.text(l10n.errorInvalidUrl), findsOneWidget);
      expect(find.text(l10n.fieldRequired), findsNWidgets(2));

      // M3U file: a file is required.
      await tapKey(tester, 'type-m3uFile');
      expect(find.text(l10n.fieldNoFileChosen), findsOneWidget);
      await tapKey(tester, 'save');
      expect(find.text(l10n.fieldRequired), findsOneWidget);

      // An invalid advanced field opens Advanced options.
      await tapKey(tester, 'type-m3uUrl');
      await tapKey(tester, 'advanced');
      await typeInto(tester, 'field-referer', 'not a url');
      await tapKey(tester, 'advanced');
      expect(find.byKey(const ValueKey('field-referer')), findsNothing);
      await tapKey(tester, 'save');
      expect(find.byKey(const ValueKey('field-referer')), findsOneWidget);
      expectFocus('field-referer');
      expect((await tester.runAsync(db.sourcesDao.all))!, isEmpty);
      await disposeApp(tester, db);
    });
  }

  testWidgets('Type on your phone fills the Xtream fields', (tester) async {
    final db = openAppTestDb();
    final servers = <LanInputServer>[];
    await pumpAppWith(
      tester,
      db: db,
      caps: tvCaps,
      overrides: [
        lanServerStarterProvider.overrideWithValue((form) async {
          final server = await LanInputServer.start(
            form: form,
            address: InternetAddress.loopbackIPv4,
            uploadDir: temp.path,
            lifetime: const Duration(minutes: 1),
          );
          servers.add(server);
          return server;
        }),
      ],
    );
    await openEditor(tester);
    // With the remote: name, playlist URL, then Type on your phone.
    expectFocus('type-m3uUrl');
    await pressN(tester, _down, 3);
    expectFocus('type-on-phone');
    await press(tester, LogicalKeyboardKey.select);
    await pumpUntil(
      tester,
      () => find.byType(PrettyQrView).evaluate().isNotEmpty,
      reason: 'the QR code',
    );
    final server = servers.single;
    expect(find.textContaining(server.url), findsOneWidget);
    expect(find.text(enL10n.lanWaitingForInput), findsOneWidget);
    expectFocus('lan-close');

    // The phone posts the form.
    Future<int>? posted;
    await tester.runAsync(() async {
      posted = () async {
        final client = HttpClient();
        try {
          final request = await client.postUrl(
            Uri.parse(
              '${server.url.split('/?').first}/submit?t=${server.token}',
            ),
          );
          request.headers.contentType = ContentType(
            'application',
            'x-www-form-urlencoded',
          );
          request.write(
            Uri(
              queryParameters: {
                'kind': 'xtream',
                'server': 'http://panel.example:8080',
                'username': 'phoneUser',
                'password': 'phone Pw',
              },
            ).query,
          );
          final response = await request.close();
          await response.drain<void>();
          return response.statusCode;
        } finally {
          client.close(force: true);
        }
      }();
    });
    await pumpUntil(
      tester,
      () => find.byKey(const ValueKey('lan-dialog')).evaluate().isEmpty,
      reason: 'the dialog to close',
    );
    await settleRoute(tester);
    expect(await tester.runAsync(() => posted!), HttpStatus.ok);
    expect(fieldText(tester, 'field-server'), 'http://panel.example:8080');
    expect(fieldText(tester, 'field-username'), 'phoneUser');
    expect(fieldText(tester, 'field-password'), 'phone Pw');
    expect(find.text(enL10n.sourcesReceivedFromPhone), findsOneWidget);
    expect(server.status, LanInputStatus.received);
    // Focus returns to the button that opened the dialog.
    expectFocus('type-on-phone');
    await drainNetworkTimers(tester);
    await disposeApp(tester, db);
  });

  testWidgets('the phone code expires; New code starts a fresh one', (
    tester,
  ) async {
    final db = openAppTestDb();
    final servers = <LanInputServer>[];
    await pumpAppWith(
      tester,
      db: db,
      caps: tvCaps,
      overrides: [
        lanServerStarterProvider.overrideWithValue((form) async {
          final server = await LanInputServer.start(
            form: form,
            address: InternetAddress.loopbackIPv4,
            uploadDir: temp.path,
          );
          servers.add(server);
          return server;
        }),
      ],
    );
    await openEditor(tester);
    await tapKey(tester, 'type-on-phone');
    await pumpUntil(
      tester,
      () => find.byType(PrettyQrView).evaluate().isNotEmpty,
      reason: 'the QR code',
    );
    // Ten minutes later.
    await tester.pump(const Duration(minutes: 10, seconds: 1));
    await pumpUntil(
      tester,
      () => find.text(enL10n.lanCodeExpired).evaluate().isNotEmpty,
      reason: 'expiry',
    );
    expect(find.byType(PrettyQrView), findsNothing);
    expect(servers.single.status, LanInputStatus.expired);
    expectFocus('lan-close');
    await tapKey(tester, 'lan-new-code');
    await pumpUntil(
      tester,
      () => find.byType(PrettyQrView).evaluate().isNotEmpty,
      reason: 'a new QR code',
    );
    expect(servers, hasLength(2));
    expect(find.textContaining(servers.last.url), findsOneWidget);
    // Close stops the server.
    await tapKey(tester, 'lan-close');
    await pumpUntil(
      tester,
      () => servers.last.status == LanInputStatus.closed,
      reason: 'the server to stop',
    );
    await settleRoute(tester);
    expect(find.byKey(const ValueKey('lan-dialog')), findsNothing);
    await disposeApp(tester, db);
  });

  testWidgets('no local network: the dialog says so', (tester) async {
    final db = openAppTestDb();
    await pumpAppWith(
      tester,
      db: db,
      overrides: [
        lanServerStarterProvider.overrideWithValue(
          (form) async => throw const LanNoNetworkException(),
        ),
      ],
    );
    await openEditor(tester);
    await tapKey(tester, 'type-on-phone');
    expect(find.text(enL10n.lanNoNetwork), findsOneWidget);
    expect(find.byKey(const ValueKey('lan-new-code')), findsOneWidget);
    await tapKey(tester, 'lan-close');
    await settleRoute(tester);
    expect(find.byType(SourceEditorScreen), findsOneWidget);
    await disposeApp(tester, db);
  });

  testWidgets('an M3U file is picked, copied and imported', (tester) async {
    final db = openAppTestDb();
    final playlist = File('${temp.path}/My Channels.m3u')
      ..writeAsStringSync(
        '#EXTM3U\n'
        '#EXTINF:-1 group-title="News",News One\nhttp://127.0.0.1:9/1.ts\n'
        '#EXTINF:-1 group-title="News",News Two\nhttp://127.0.0.1:9/2.ts\n'
        '#EXTINF:-1 group-title="Kids",Cartoons\nhttp://127.0.0.1:9/3.ts\n',
      );
    final support = Directory('${temp.path}/support')..createSync();
    await pumpAppWith(
      tester,
      db: db,
      runner: inlineRunner(),
      overrides: [
        playlistPickerProvider.overrideWithValue(
          () async =>
              PickedPlaylist(name: 'My Channels.m3u', path: playlist.path),
        ),
        sourceRepositoryProvider.overrideWith(
          (ref) => SourceRepository(
            db,
            DbSecretStore(db),
            appSupportDir: () async => support.path,
            log: ref.watch(ringLogProvider),
          ),
        ),
      ],
    );
    await openEditor(tester);
    await tapKey(tester, 'type-m3uFile');
    await tapKey(tester, 'pick-file');
    expect(find.text('My Channels.m3u'), findsOneWidget);
    await tapKey(tester, 'save');
    await pumpUntil(
      tester,
      () => find.byType(HomeShell).evaluate().isNotEmpty,
      reason: 'the home shell',
    );
    final source = (await tester.runAsync(db.sourcesDao.all))!.single;
    expect(source.kind, SourceKind.m3uFile);
    expect(source.name, 'My Channels');
    // The playlist was copied into the app's folder.
    expect(source.url, startsWith(support.path));
    expect(File(source.url).readAsStringSync(), playlist.readAsStringSync());
    final live = await tester.runAsync(
      () => db.catalogDao.totalCount(source.id, ContentKind.live),
    );
    expect(live, 3);
    await disposeApp(tester, db);
  });

  testWidgets('TV without a file picker: Choose file points to the phone '
      'upload; other picker failures still say the file was not read', (
    tester,
  ) async {
    final db = openAppTestDb();
    Object failure = PlatformException(
      code: noFilePickerCode,
      message: "Can't find a valid activity to handle the request.",
    );
    await pumpAppWith(
      tester,
      db: db,
      caps: tvCaps,
      overrides: [
        playlistPickerProvider.overrideWithValue(() async => throw failure),
      ],
    );
    await pressN(tester, _down, 2);
    await press(tester, LogicalKeyboardKey.select);
    await settleRoute(tester);
    expectFocus('type-m3uUrl');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expectFocus('type-m3uFile');
    await press(tester, LogicalKeyboardKey.select);
    await pressN(tester, _down, 2);
    expectFocus('pick-file');

    await press(tester, LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text(enL10n.sourcesNoFilePicker), findsOneWidget);
    expect(find.text(enL10n.errorFileRead), findsNothing);
    expectFocus('type-on-phone');

    failure = PlatformException(code: 'unknown_path');
    await press(tester, _up);
    expectFocus('pick-file');
    await press(tester, LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text(enL10n.errorFileRead), findsOneWidget);
    expect(find.text(enL10n.sourcesNoFilePicker), findsNothing);
    await disposeApp(tester, db);
  });

  testWidgets('import progress counts and can be cancelled', (tester) async {
    final panel = (await tester.runAsync(
      () => FakePanel.start(mediaDir: null, liveCount: 3, vodCount: 0),
    ))!;
    addTearDown(() => tester.runAsync(panel.close));
    final runner = ManualSyncRunner();
    final db = openAppTestDb();
    await pumpAppWith(tester, db: db, caps: tvCaps, runner: runner);
    await openEditor(tester);
    await tapKey(tester, 'type-xtream');
    await typeInto(tester, 'field-server', panel.baseUrl);
    await typeInto(tester, 'field-username', panel.username);
    await typeInto(tester, 'field-password', panel.password);
    await tapKey(tester, 'save');
    await pumpUntil(
      tester,
      () => find.byType(ImportProgressScreen).evaluate().isNotEmpty,
      reason: 'the progress screen',
    );
    await settleRoute(tester);
    expect(find.text(enL10n.importTitle), findsWidgets);
    expect(find.text(enL10n.importLiveCount(5)), findsOneWidget);
    expect(find.text(enL10n.importMoviesCount(0)), findsOneWidget);
    expectFocus('import-cancel');
    expect(runner.tasks.single.config.password, panel.password);

    // Cancel with the remote; the runner reports the cancellation.
    await press(tester, LogicalKeyboardKey.select);
    await settleRoute(tester);
    expect(find.byType(ImportProgressScreen), findsNothing);
    expect(find.text(enL10n.sourcesImportCancelled), findsOneWidget);
    // Still in the editor, now editing the saved source.
    final saved = (await tester.runAsync(db.sourcesDao.all))!;
    expect(saved, hasLength(1));
    expect(containerOf(tester).read(onboardingHoldProvider), isTrue);
    expect(
      containerOf(tester).read(syncStatusProvider(saved.single.id)),
      isA<SyncFailed>(),
    );

    // Saving again updates the same source (no duplicate) and finishes.
    await tapKey(tester, 'save');
    await pumpUntil(
      tester,
      () => find.byType(ImportProgressScreen).evaluate().isNotEmpty,
      reason: 'the progress screen again',
    );
    await settleRoute(tester);
    runner.finish(
      SyncProgress(
        sourceId: saved.single.id,
        phase: SyncPhase.done,
        channels: 5,
      ),
    );
    await settleRoute(tester);
    expect(find.byType(HomeShell), findsOneWidget);
    expect((await tester.runAsync(db.sourcesDao.all))!, hasLength(1));
    expect(containerOf(tester).read(activeSourceIdProvider), saved.single.id);
    await drainNetworkTimers(tester);
    await disposeApp(tester, db);
  });

  testWidgets('editing an Xtream source keeps the saved password', (
    tester,
  ) async {
    final panel = (await tester.runAsync(
      () => FakePanel.start(
        username: 'editUser',
        password: 'Edit-Pw-1',
        mediaDir: null,
        liveCount: 4,
        vodCount: 0,
        seriesCount: 0,
      ),
    ))!;
    addTearDown(() => tester.runAsync(panel.close));
    final db = openAppTestDb();
    final id = (await tester.runAsync(
      () => db.sourcesDao.create(
        SourceConfig(
          kind: SourceKind.xtream,
          url: panel.baseUrl,
          name: 'Old name',
          username: 'editUser',
          password: 'Edit-Pw-1',
          userAgent: 'VLC/3.0.21 LibVLC/3.0.21',
        ),
      ),
    ))!;
    await tester.runAsync(
      () => db.epgDao.addEpgSource(
        id,
        'http://guide.example/xmltv.php?username=a&password=b',
        EpgOrigin.manual,
      ),
    );
    await pumpAppWith(
      tester,
      db: db,
      runner: inlineRunner(),
      pages: (tab) => tab == HomeTab.live
          ? Builder(
              builder: (context) => TextButton(
                key: const ValueKey('edit-it'),
                onPressed: () => openSourceEditor(context, sourceId: id),
                child: const Text('edit'),
              ),
            )
          : FakeTabPage(tab),
    );
    await tapKey(tester, 'edit-it');
    await pumpUntil(
      tester,
      () => find.byKey(const ValueKey('field-name')).evaluate().isNotEmpty,
      reason: 'the loaded editor',
    );
    await settleRoute(tester);
    expect(find.text(enL10n.settingsEditSource), findsOneWidget);
    expect(fieldText(tester, 'field-name'), 'Old name');
    expect(fieldText(tester, 'field-server'), panel.baseUrl);
    expect(fieldText(tester, 'field-username'), 'editUser');
    // The saved password is never shown; leaving it empty keeps it.
    expect(fieldText(tester, 'field-password'), isEmpty);
    expect(find.text(enL10n.sourcesKeepPassword), findsOneWidget);
    // Advanced options open with the saved values (guide URL masked).
    expect(find.byKey(const ValueKey('field-epg')), findsOneWidget);
    expect(fieldText(tester, 'field-epg'), isNot(contains('b')));
    expect(fieldText(tester, 'field-epg'), contains('***'));

    await typeInto(tester, 'field-name', 'New name');
    await tapKey(tester, 'save');
    await pumpUntil(
      tester,
      () =>
          find.byType(SourceEditorScreen).evaluate().isEmpty &&
          find.byType(ImportProgressScreen).evaluate().isEmpty,
      reason: 'back home',
    );
    final row = (await tester.runAsync(() => db.sourcesDao.byId(id)))!;
    expect(row.name, 'New name');
    expect(row.userAgent, 'VLC/3.0.21 LibVLC/3.0.21');
    final config = (await tester.runAsync(() => db.sourcesDao.configFor(id)))!;
    expect(config.password, 'Edit-Pw-1');
    final guides = (await tester.runAsync(() => db.epgDao.epgSources(id)))!;
    final manual = guides.where((g) => g.origin == EpgOrigin.manual).single;
    expect(
      await tester.runAsync(() => db.epgDao.epgSourceUrl(manual.id)),
      'http://guide.example/xmltv.php?username=a&password=b',
    );
    expect(
      await tester.runAsync(
        () => db.catalogDao.totalCount(id, ContentKind.live),
      ),
      4,
    );
    await drainNetworkTimers(tester);
    await disposeApp(tester, db);
  });
}
