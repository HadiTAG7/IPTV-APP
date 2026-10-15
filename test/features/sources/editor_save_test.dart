// Test & save edge cases: a sync already running with the old settings,
// edits made while the check runs, imported playlist copies, and pages
// closed while their work is still running.
@Timeout(Duration(seconds: 120))
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/core/secure/secret_store.dart';
import 'package:iptv_player/features/lan_input/providers.dart';
import 'package:iptv_player/features/sources/import_progress_screen.dart';
import 'package:iptv_player/features/sources/providers.dart';
import 'package:iptv_player/features/sources/source_editor_screen.dart';
import 'package:iptv_player/features/sources/sources_screen.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/sources/source_repository.dart';
import 'package:iptv_player/sources/sync/sync_progress.dart';

import '../../support/fake_panel.dart';
import '../../support/real_http.dart';
import 'support.dart';

/// A repository whose [configFor] and [delete] can be held back.
class _GatedRepository extends SourceRepository {
  _GatedRepository(AppDatabase db)
    : super(db, DbSecretStore(db), log: RingLog());

  Completer<void>? configGate;
  Completer<void>? deleteGate;

  @override
  Future<SourceConfig> configFor(int id) async {
    final gate = configGate;
    if (gate != null) await gate.future;
    return super.configFor(id);
  }

  @override
  Future<void> delete(int id) async {
    final gate = deleteGate;
    if (gate == null) return super.delete(id);
    await gate.future;
    throw StateError('Deleting failed');
  }
}

/// Home pages with a button on Live that edits source [id].
Widget Function(HomeTab) _editPages(int id) =>
    (tab) => tab == HomeTab.live
    ? Builder(
        builder: (context) => TextButton(
          key: const ValueKey('edit-it'),
          onPressed: () => openSourceEditor(context, sourceId: id),
          child: const Text('edit'),
        ),
      )
    : FakeTabPage(tab);

String _playlist(String name) =>
    '#EXTM3U\n#EXTINF:-1 group-title="News",$name\nhttp://127.0.0.1:9/1.ts\n';

bool _home() =>
    find.byType(SourceEditorScreen).evaluate().isEmpty &&
    find.byType(ImportProgressScreen).evaluate().isEmpty &&
    find.byType(HomeShell).evaluate().isNotEmpty;

void main() {
  useRealHttp();

  late Directory temp;
  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    temp = Directory.systemTemp.createTempSync('editor_save_test');
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  Future<FakePanel> startPanel(
    WidgetTester tester, {
    String username = 'u1',
    String password = 'New-Pw-1',
  }) async {
    final panel = (await tester.runAsync(
      () => FakePanel.start(
        username: username,
        password: password,
        mediaDir: null,
        liveCount: 3,
        vodCount: 0,
        seriesCount: 0,
      ),
    ))!;
    addTearDown(() => tester.runAsync(panel.close));
    return panel;
  }

  Future<void> openEdit(WidgetTester tester) async {
    await tapKey(tester, 'edit-it');
    await pumpUntil(
      tester,
      () => find.byKey(const ValueKey('field-name')).evaluate().isNotEmpty,
      reason: 'the loaded editor',
    );
    await settleRoute(tester);
  }

  testWidgets('Test & save restarts a sync running with the old settings', (
    tester,
  ) async {
    final panel = await startPanel(tester);
    final db = openAppTestDb();
    final id = (await tester.runAsync(
      () => db.sourcesDao.create(
        SourceConfig(
          kind: SourceKind.xtream,
          url: panel.baseUrl,
          name: 'Panel',
          username: 'u1',
          password: 'Old-Pw-0',
        ),
      ),
    ))!;
    final runner = ManualSyncRunner();
    await pumpAppWith(tester, db: db, runner: runner, pages: _editPages(id));
    // A sync is running with the old password (startup auto-sync, or
    // Refresh in Sources).
    final sync = containerOf(tester).read(syncServiceProvider)..sync(id);
    await pumpUntil(tester, () => runner.tasks.isNotEmpty, reason: 'a run');
    expect(runner.tasks.single.config.password, 'Old-Pw-0');

    // The user fixes the password and saves.
    await openEdit(tester);
    await typeInto(tester, 'field-password', 'New-Pw-1');
    await tapKey(tester, 'save');
    await pumpUntil(
      tester,
      () => find.byType(ImportProgressScreen).evaluate().isNotEmpty,
      reason: 'the progress screen',
    );
    await settleRoute(tester);
    // The old run was stopped; the import shown uses the saved settings.
    expect(runner.tasks, hasLength(2));
    expect(runner.tasks.last.config.password, 'New-Pw-1');
    expect(sync.isRunning(id), isTrue);
    expect(find.byKey(const ValueKey('import-cancel')), findsOneWidget);

    runner.finish(
      SyncProgress(sourceId: id, phase: SyncPhase.done, channels: 3),
    );
    await settleRoute(tester);
    expect(_home(), isTrue);
    expect(containerOf(tester).read(activeSourceIdProvider), id);
    await drainNetworkTimers(tester);
    await disposeApp(tester, db);
  });

  testWidgets('fields edited while the check runs are not saved', (
    tester,
  ) async {
    final panel = await startPanel(tester);
    final db = openAppTestDb();
    final runner = ManualSyncRunner();
    await pumpAppWith(tester, db: db, runner: runner);
    await tapKey(tester, 'onboarding-add-source');
    await settleRoute(tester);
    await tapKey(tester, 'type-xtream');
    await typeInto(tester, 'field-server', panel.baseUrl);
    await typeInto(tester, 'field-username', 'u1');
    await typeInto(tester, 'field-password', 'New-Pw-1');
    await tapKey(tester, 'advanced');
    await tapKey(tester, 'save');
    // The check needs the network: it is still running while the user
    // keeps typing and picks another live format.
    expect(find.text(enL10n.validating), findsOneWidget);
    await typeInto(tester, 'field-server', 'http://elsewhere.example:1');
    await typeInto(tester, 'field-password', 'Unchecked-1');
    await tapKey(tester, 'format-m3u8');
    await pumpUntil(
      tester,
      () => find.byType(ImportProgressScreen).evaluate().isNotEmpty,
      reason: 'the progress screen',
    );
    await settleRoute(tester);
    // What was checked is what was saved and imported.
    final task = runner.tasks.single;
    expect(task.config.url, panel.baseUrl);
    expect(task.config.password, 'New-Pw-1');
    expect(task.config.liveFormat, LiveFormat.ts);
    final saved = (await tester.runAsync(
      () => db.sourcesDao.configFor(task.sourceId),
    ))!;
    expect(saved.url, panel.baseUrl);
    expect(saved.password, 'New-Pw-1');
    expect(saved.liveFormat, LiveFormat.ts);

    runner.finish(
      SyncProgress(sourceId: task.sourceId, phase: SyncPhase.done, channels: 3),
    );
    await settleRoute(tester);
    expect(_home(), isTrue);
    await drainNetworkTimers(tester);
    await disposeApp(tester, db);
  });

  testWidgets('replaced and abandoned playlist copies are deleted', (
    tester,
  ) async {
    final panel = await startPanel(tester);
    final db = openAppTestDb();
    final support = Directory('${temp.path}/support')..createSync();
    final imports = Directory(
      '${support.path}/${SourceRepository.importDirName}',
    );
    SourceRepository repo({required RingLog log}) => SourceRepository(
      db,
      DbSecretStore(db),
      appSupportDir: () async => support.path,
      log: log,
    );
    final first = File('${temp.path}/first.m3u')
      ..writeAsStringSync(_playlist('One'));
    final second = File('${temp.path}/second.m3u')
      ..writeAsStringSync(_playlist('Two'));
    final seed = repo(log: RingLog());
    final firstCopy = (await tester.runAsync(
      () => seed.importM3uFile(first.path),
    ))!;
    final id = (await tester.runAsync(
      () => seed.add(
        SourceConfig(kind: SourceKind.m3uFile, url: firstCopy, name: 'Mine'),
      ),
    ))!;
    await pumpAppWith(
      tester,
      db: db,
      runner: inlineRunner(),
      pages: _editPages(id),
      overrides: [
        playlistPickerProvider.overrideWithValue(
          () async => PickedPlaylist(name: 'second.m3u', path: second.path),
        ),
        sourceRepositoryProvider.overrideWith(
          (ref) => repo(log: ref.watch(ringLogProvider)),
        ),
      ],
    );

    // A new file replaces the saved one: the old copy goes.
    await openEdit(tester);
    await tapKey(tester, 'pick-file');
    await tapKey(tester, 'save');
    await pumpUntil(tester, _home, reason: 'back home');
    final secondCopy = (await tester.runAsync(() => db.sourcesDao.byId(id)))!
        .url;
    expect(secondCopy, isNot(firstCopy));
    expect(File(firstCopy).existsSync(), isFalse);
    expect(File(secondCopy).readAsStringSync(), second.readAsStringSync());
    expect(imports.listSync().map((f) => f.path), [secondCopy]);

    // The source becomes an Xtream login: its playlist copy goes too.
    await openEdit(tester);
    await tapKey(tester, 'type-xtream');
    await typeInto(tester, 'field-server', panel.baseUrl);
    await typeInto(tester, 'field-username', 'u1');
    await typeInto(tester, 'field-password', 'New-Pw-1');
    await tapKey(tester, 'save');
    await pumpUntil(tester, _home, reason: 'back home again');
    final row = (await tester.runAsync(() => db.sourcesDao.byId(id)))!;
    expect(row.kind, SourceKind.xtream);
    expect(imports.listSync(), isEmpty);
    await drainNetworkTimers(tester);
    await disposeApp(tester, db);
  });

  group('pages closed while their work runs', () {
    testWidgets('the editor closed while loading', (tester) async {
      final db = openAppTestDb();
      final id = await db.sourcesDao.create(
        const SourceConfig(
          kind: SourceKind.m3uUrl,
          url: 'http://127.0.0.1:9/list.m3u',
          name: 'List',
        ),
      );
      final repo = _GatedRepository(db);
      await pumpAppWith(
        tester,
        db: db,
        pages: _editPages(id),
        overrides: [sourceRepositoryProvider.overrideWithValue(repo)],
      );
      final gate = repo.configGate = Completer<void>();
      await tapKey(tester, 'edit-it');
      expect(find.byType(SourceEditorScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(SourceEditorScreen), findsNothing);
      gate.complete();
      repo.configGate = null;
      await settle(tester);
      expect(tester.takeException(), isNull);
      await disposeApp(tester, db);
    });

    testWidgets('the phone dialog closed while its page starts', (
      tester,
    ) async {
      final db = openAppTestDb();
      final starting = Completer<LanInputServer>();
      await pumpAppWith(
        tester,
        db: db,
        overrides: [
          lanServerStarterProvider.overrideWithValue((form) => starting.future),
        ],
      );
      await tapKey(tester, 'onboarding-add-source');
      await settleRoute(tester);
      await tapKey(tester, 'type-on-phone');
      expect(find.byKey(const ValueKey('lan-dialog')), findsOneWidget);
      await tapKey(tester, 'lan-close');
      await settleRoute(tester);
      expect(find.byKey(const ValueKey('lan-dialog')), findsNothing);
      starting.completeError(StateError('bind failed'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(SourceEditorScreen), findsOneWidget);
      await disposeApp(tester, db);
    });

    testWidgets('Sources closed while a delete fails', (tester) async {
      final db = openAppTestDb();
      final id = await db.sourcesDao.create(
        const SourceConfig(
          kind: SourceKind.m3uUrl,
          url: 'http://127.0.0.1:9/one.m3u',
          name: 'One',
        ),
      );
      await db.sourcesDao.create(
        const SourceConfig(
          kind: SourceKind.m3uUrl,
          url: 'http://127.0.0.1:9/two.m3u',
          name: 'Two',
        ),
      );
      final repo = _GatedRepository(db);
      await pumpAppWith(
        tester,
        db: db,
        pages: (tab) =>
            tab == HomeTab.sources ? const SourcesScreen() : FakeTabPage(tab),
        overrides: [sourceRepositoryProvider.overrideWithValue(repo)],
      );
      await tapKey(tester, 'nav-more');
      await tapKey(tester, 'more-sources');
      await settleRoute(tester);
      expect(find.byType(SourcesScreen), findsOneWidget);
      final gate = repo.deleteGate = Completer<void>();
      await tapKey(tester, 'source-$id-delete');
      await tapKey(tester, 'delete-confirm');
      await settleRoute(tester);
      await back(tester);
      expect(find.byType(SourcesScreen), findsNothing);
      gate.complete();
      await settle(tester);
      expect(tester.takeException(), isNull);
      await disposeApp(tester, db);
    });
  });
}
