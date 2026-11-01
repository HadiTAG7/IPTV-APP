import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/account/account_controller.dart';
import 'package:iptv_player/account/firebase_api.dart';
import 'package:iptv_player/account/local_sync_store.dart';
import 'package:iptv_player/account/sync_model.dart';
import 'package:iptv_player/app/settings.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/secure/secret_store.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/sources/source_repository.dart';

import '../unit/db/db_test_utils.dart';

class MemoryVault implements SessionVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? value) async => this.value = value;
}

class DelayedVault extends MemoryVault {
  final restored = Completer<String?>();
  @override
  Future<String?> read() => restored.future;
}

/// A keystore that cannot decrypt its entry (Windows DPAPI after a profile
/// migration, a lost Android TV key).
class BrokenVault extends MemoryVault {
  @override
  Future<String?> read() async => throw const FileSystemException('locked');
}

class Cloud {
  SyncData data = {};
  final deleted = <String>{};
  int version = 0;
  bool offline = false;
  int reads = 0;
  Future<void> Function()? duringWrite;

  /// Commits only this many changes, in order, then drops the connection,
  /// like an upload cut off between its batched commits.
  int? cutAfter;
}

/// A device whose zlib writes another gzip header, as Windows does (OS byte
/// 10, where Android and Linux write 3).
class WindowsZlibStore extends LocalSyncStore {
  WindowsZlibStore(super.db);
  @override
  Future<SyncData> export() async {
    final data = await super.export();
    for (final r in data.values.toList()) {
      if (r['type'] != 'source' || r['fileHash'] == null) continue;
      final sid = r['source'] as String;
      final encoded = [
        for (var i = 0; i < (r['fileParts'] as int); i++)
          data['file:$sid:$i']!['data'] as String,
      ].join();
      final bytes = base64Decode(encoded)..[9] = 10;
      final patched = base64Encode(bytes);
      for (var i = 0; i < (r['fileParts'] as int); i++) {
        data['file:$sid:$i'] = {
          ...data['file:$sid:$i']!,
          'data': patched.substring(
            i * 350000,
            ((i + 1) * 350000).clamp(0, patched.length),
          ),
        };
      }
      data['source:$sid'] = {...r, 'fileHash': syncId(patched)};
    }
    return data;
  }
}

class FakeApi extends FirebaseAccountApi {
  FakeApi(this.cloud) : super(projectId: 'test', apiKey: 'test');
  final Cloud cloud;
  void check() {
    if (cloud.offline) throw const AccountException('NETWORK_ERROR');
  }

  String? get version => cloud.version == 0 ? null : '${cloud.version}';
  @override
  Future<AccountSession> signIn(
    String email,
    String password, {
    bool create = false,
  }) async => AccountSession(
    uid: email.startsWith('other') ? 'other' : 'owner',
    email: email,
    idToken: 'token',
    refreshToken: 'refresh',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );
  @override
  Future<String?> revision(AccountSession session) async {
    check();
    return version;
  }

  @override
  Future<RemoteState> read(AccountSession session) async {
    check();
    cloud.reads++;
    return RemoteState(
      decodeSyncData(jsonDecode(jsonEncode(cloud.data))),
      version,
      deletedKeys: Set.of(cloud.deleted),
    );
  }

  @override
  Future<String?> write(
    AccountSession session,
    RemoteState remote,
    Map<String, Map<String, Object?>?> changes,
  ) async {
    check();
    final hook = cloud.duringWrite;
    cloud.duringWrite = null;
    await hook?.call();
    if (remote.version != version) throw const AccountException('CONFLICT');
    final cut = cloud.cutAfter;
    if (cut != null) {
      commit(Map.fromEntries(changes.entries.take(cut)));
      throw const AccountException('NETWORK_ERROR');
    }
    if (changes.isNotEmpty) commit(changes);
    return version;
  }

  void commit(Map<String, Map<String, Object?>?> changes) {
    for (final entry in changes.entries) {
      if (entry.value == null) {
        cloud.deleted.add(entry.key);
      } else {
        cloud.deleted.remove(entry.key);
      }
    }
    cloud.data = mergeSyncData(cloud.data, changes);
    cloud.version++;
  }
}

/// Polls [done] until it holds, for work a controller starts on its own.
Future<void> until(bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase phone;
  late AppDatabase tv;
  late Cloud cloud;
  late AccountController a;
  late AccountController b;
  setUp(() {
    phone = openTestDb();
    tv = openTestDb();
    cloud = Cloud();
    a = AccountController(db: phone, api: FakeApi(cloud), vault: MemoryVault());
    b = AccountController(db: tv, api: FakeApi(cloud), vault: MemoryVault());
  });
  tearDown(() async {
    a.dispose();
    b.dispose();
    await phone.close();
    await tv.close();
  });
  Future<int> seed(AppDatabase db) => db.sourcesDao.create(
    const SourceConfig(
      kind: SourceKind.xtream,
      name: 'Sports',
      url: 'https://provider.example',
      username: 'sample',
      password: 'private-password',
    ),
  );
  Future<void> login(AccountController c) =>
      c.authenticate('owner@example.test', 'sample-password');

  test('subscriptions, credentials, lists, order, favourites and progress cross local IDs', () async {
    final id = await seed(phone);
    await phone.favoritesDao.setFavorite(id, ContentKind.live, 'one', true);
    await phone.favoritesDao.setFavorite(id, ContentKind.live, 'two', true);
    await phone.favoritesDao.reorder(id, ContentKind.live, ['two', 'one']);
    await phone.channelListsDao.createList(
      id,
      'My sports',
      channels: ['two', 'one'],
    );
    await phone.progressDao.saveProgress(
      id,
      PlayableKind.movie,
      'film',
      900000,
      7200000,
    );
    // Force the second device to allocate different database IDs.
    final discarded = await seed(tv);
    await tv.sourcesDao.deleteSource(discarded);
    await login(a);
    await login(b);
    expect(a.view.error, isNull);
    expect(b.view.error, isNull);
    final imported = (await tv.sourcesDao.all()).single;
    expect(imported.id, isNot(id));
    final config = await tv.sourcesDao.configFor(imported.id);
    expect(config!.password, 'private-password');
    expect(config.username, 'sample');
    expect(await tv.favoritesDao.favoriteKeys(imported.id, ContentKind.live), [
      'two',
      'one',
    ]);
    final list = (await tv.channelListsDao.lists(imported.id)).single;
    expect(await tv.channelListsDao.channelKeys(list.id), ['two', 'one']);
    expect(
      (await tv.progressDao.progressFor(
        imported.id,
        PlayableKind.movie,
        'film',
      ))!.position.inMilliseconds,
      900000,
    );
  });

  test(
    'offline edits merge with other device edits, and deletions do not return',
    () async {
      final id = await seed(phone);
      await phone.favoritesDao.setFavorite(
        id,
        ContentKind.live,
        'remove',
        true,
      );
      await login(a);
      await login(b);
      final tid = (await tv.sourcesDao.all()).single.id;
      cloud.offline = true;
      await phone.favoritesDao.setFavorite(
        id,
        ContentKind.live,
        'offline',
        true,
      );
      await a.sync();
      expect(a.view.error, 'NETWORK_ERROR');
      cloud.offline = false;
      await tv.favoritesDao.setFavorite(tid, ContentKind.live, 'remote', true);
      await tv.favoritesDao.setFavorite(tid, ContentKind.live, 'remove', false);
      await b.sync();
      await a.sync();
      await b.sync();
      expect(
        (await phone.favoritesDao.favoriteKeys(id, ContentKind.live)).toSet(),
        {'offline', 'remote'},
      );
      expect(
        (await tv.favoritesDao.favoriteKeys(tid, ContentKind.live)).toSet(),
        {'offline', 'remote'},
      );
    },
  );

  test(
    'edits made while a request is in flight remain queued for next sync',
    () async {
      final id = await seed(phone);
      await login(a);
      await phone.favoritesDao.setFavorite(id, ContentKind.live, 'first', true);
      cloud.duringWrite = () =>
          phone.favoritesDao.setFavorite(id, ContentKind.live, 'late', true);
      await a.sync();
      expect(await phone.favoritesDao.favoriteKeys(id, ContentKind.live), [
        'first',
        'late',
      ]);
      await a.sync();
      await login(b);
      final tid = (await tv.sourcesDao.all()).single.id;
      expect(await tv.favoritesDao.favoriteKeys(tid, ContentKind.live), [
        'first',
        'late',
      ]);
    },
  );

  test(
    'competing cloud write retries without losing either favourite',
    () async {
      final id = await seed(phone);
      await login(a);
      await login(b);
      final tid = (await tv.sourcesDao.all()).single.id;
      await phone.favoritesDao.setFavorite(id, ContentKind.live, 'phone', true);
      await tv.favoritesDao.setFavorite(tid, ContentKind.live, 'tv', true);
      cloud.duringWrite = () => b.sync(force: true);
      await a.sync();
      await b.sync();
      expect(a.view.error, isNull);
      expect(
        (await phone.favoritesDao.favoriteKeys(id, ContentKind.live)).toSet(),
        {'phone', 'tv'},
      );
    },
  );

  test(
    'source and list renames keep cloud identity and deletion propagates',
    () async {
      final id = await seed(phone);
      final lid = await phone.channelListsDao.createList(
        id,
        'Old',
        channels: ['one'],
      );
      await login(a);
      await login(b);
      await phone.channelListsDao.renameList(lid, 'New');
      final old = (await phone.sourcesDao.configFor(id))!;
      await phone.sourcesDao.updateConfig(id, old.copyWith(name: 'Renamed'));
      await a.sync();
      await b.sync();
      final tid = (await tv.sourcesDao.all()).single.id;
      expect((await tv.sourcesDao.all()).single.name, 'Renamed');
      expect((await tv.channelListsDao.lists(tid)).single.name, 'New');
      await phone.sourcesDao.deleteSource(id);
      await a.sync();
      await b.sync();
      expect(await tv.sourcesDao.all(), isEmpty);
      expect(await tv.select(tv.channelListItems).get(), isEmpty);
    },
  );

  test('another account cannot receive this device data', () async {
    await seed(phone);
    await login(a);
    await a.signOut();
    final before = jsonEncode(cloud.data);
    await expectLater(
      a.authenticate('other@example.test', 'password'),
      throwsA(
        isA<AccountException>().having((e) => e.code, 'code', 'OTHER_ACCOUNT'),
      ),
    );
    expect(jsonEncode(cloud.data), before);
    expect(a.view.email, isNull);
  });

  test(
    'device settings stay local and shared language follows account',
    () async {
      await seed(phone);
      await phone.settingsDao.setJson(
        kAppSettingsKey,
        const AppSettings(
          locale: AppLocaleSetting.ar,
          hwdec: false,
          lite: LiteSetting.on,
        ).toJson(),
      );
      await tv.settingsDao.setJson(
        kAppSettingsKey,
        const AppSettings(hwdec: true, lite: LiteSetting.off).toJson(),
      );
      await login(a);
      await login(b);
      final settings = await loadAppSettings(tv.settingsDao);
      expect(settings.locale, AppLocaleSetting.ar);
      expect(settings.hwdec, true);
      expect(settings.lite, LiteSetting.off);
    },
  );

  test('a configured second device adopts cloud order and cannot revive deleted favourites', () async {
    final id = await seed(phone);
    final firstList = await phone.channelListsDao.createList(
      id,
      'Sports',
      channels: ['two', 'one'],
    );
    await phone.favoritesDao.setFavorite(id, ContentKind.live, 'removed', true);
    await login(a);
    await phone.favoritesDao.setFavorite(
      id,
      ContentKind.live,
      'removed',
      false,
    );
    await a.sync();
    final tid = await seed(tv);
    final old = (await tv.sourcesDao.configFor(tid))!;
    await tv.sourcesDao.updateConfig(tid, old.copyWith(password: 'outdated'));
    await tv.channelListsDao.createList(
      tid,
      'Sports',
      channels: ['local-only', 'one', 'two'],
    );
    await tv.favoritesDao.setFavorite(tid, ContentKind.live, 'removed', true);
    await login(b);
    await a.sync();
    expect((await tv.sourcesDao.configFor(tid))!.password, 'private-password');
    final list = (await tv.channelListsDao.lists(tid)).single;
    expect(await tv.channelListsDao.channelKeys(list.id), [
      'two',
      'one',
      'local-only',
    ]);
    expect(await phone.channelListsDao.channelKeys(firstList), [
      'two',
      'one',
      'local-only',
    ]);
    expect(await tv.favoritesDao.favoriteKeys(tid, ContentKind.live), isEmpty);
  });

  test('older offline progress cannot rewind newer watch position', () {
    final newer = <String, Object?>{
      'type': 'progress',
      'updatedAt': 20,
      'positionMs': 1000,
    };
    final older = <String, Object?>{
      'type': 'progress',
      'updatedAt': 10,
      'positionMs': 500,
    };
    expect(mergeSyncData({'p': newer}, {'p': older})['p'], newer);
  });

  test('automatic DB observation uploads edits and a restart retains offline changes', () async {
    final id = await seed(phone);
    await login(a);
    await a.start();
    await phone.favoritesDao.setFavorite(
      id,
      ContentKind.live,
      'automatic',
      true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    await a.sync();
    expect(cloud.data.values.any((r) => r['key'] == 'automatic'), true);
    cloud.offline = true;
    await phone.favoritesDao.setFavorite(id, ContentKind.live, 'restart', true);
    await a.sync();
    final vault = a.vault;
    a.dispose();
    cloud.offline = false;
    a = AccountController(db: phone, api: FakeApi(cloud), vault: vault);
    await a.start();
    expect(a.view.error, isNull);
    expect(cloud.data.values.any((r) => r['key'] == 'restart'), true);
  });

  test('unchanged polls read only the account revision', () async {
    await seed(phone);
    await login(a);
    final reads = cloud.reads;
    await a.sync();
    await a.sync();
    expect(cloud.reads, reads);
  });

  test(
    'sign-in waits for secure session restoration before replacing it',
    () async {
      a.dispose();
      final vault = DelayedVault();
      a = AccountController(db: phone, api: FakeApi(cloud), vault: vault);
      final restoring = a.start();
      final signing = a.authenticate('owner-new@example.test', 'password');
      final old = await FakeApi(cloud)
          .signIn('owner-old@example.test', 'password');
      vault.restored.complete(jsonEncode(old.toJson()));
      await restoring;
      await signing;
      expect(a.view.email, 'owner-new@example.test');
      expect(a.view.error, isNull);
    },
  );

  test(
    'an explicit cloud password removal cannot revive a stale local secret',
    () async {
      final id = await seed(phone);
      final local = LocalSyncStore(phone);
      final snapshot = await local.export();
      final key = snapshot.keys.singleWhere((k) => k.startsWith('source:'));
      snapshot[key] = {...snapshot[key]!, 'password': null};
      await local.apply(snapshot);
      expect((await phone.sourcesDao.configFor(id))!.password, isNull);
      expect(syncChanges(snapshot, await local.export()), isEmpty);
    },
  );

  test(
    'local file playlists transfer as verified chunks rather than device paths',
    () async {
      final temp = await Directory.systemTemp.createTemp('iptv-sync-test-');
      try {
        final file = File('${temp.path}/original.m3u');
        await file.writeAsString(
          '#EXTM3U\n#EXTINF:-1,Sample\nhttps://provider.example/live.ts\n',
        );
        await phone.sourcesDao.create(
          SourceConfig(kind: SourceKind.m3uFile, url: file.path, name: 'File'),
        );
        final source = LocalSyncStore(phone);
        final dest = LocalSyncStore(
          tv,
          directory: () async => Directory('${temp.path}/tv'),
        );
        final exported = await source.export();
        expect(jsonEncode(exported), isNot(contains(file.path)));
        await dest.apply(exported);
        final imported = (await tv.sourcesDao.configFor(
          (await tv.sourcesDao.all()).single.id,
        ))!;
        expect(
          await File(imported.url).readAsString(),
          await file.readAsString(),
        );
        expect(syncChanges(exported, await dest.export()), isEmpty);
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  Future<void> setCreatedAt(AppDatabase db, int list, int createdAt) =>
      (db.update(db.channelLists)..where((l) => l.id.equals(list))).write(
        ChannelListsCompanion(createdAt: Value(createdAt)),
      );

  Future<List<String>> describeLists(AppDatabase db, int source) async => [
    for (final l in await db.channelListsDao.lists(source))
      '${l.name}=${(await db.channelListsDao.channelKeys(l.id)).join(',')}',
  ];

  test(
    'a list both devices made before linking settles instead of re-uploading',
    () async {
      final id = await seed(phone);
      await phone.channelListsDao.createList(id, 'Sports', channels: ['one']);
      await login(a);
      final tid = await seed(tv);
      final list = await tv.channelListsDao.createList(
        tid,
        'Sports',
        channels: ['two'],
      );
      // Made on another day than the phone's list.
      await setCreatedAt(tv, list, 1);
      await login(b);
      await a.sync();
      await b.sync();
      final settled = cloud.version;
      for (var i = 0; i < 5; i++) {
        await a.sync();
        await b.sync();
      }
      expect(cloud.version, settled);
      expect(a.view.error, isNull);
      expect(b.view.error, isNull);
    },
  );

  test('applying the account copy round-trips every record type', () async {
    final temp = await Directory.systemTemp.createTemp('iptv-sync-test-');
    try {
      final file = File('${temp.path}/original.m3u')
        ..writeAsStringSync(
          '#EXTM3U\n#EXTINF:-1,Sample\nhttps://provider.example/live.ts\n',
        );
      final id = await seed(phone);
      await phone.sourcesDao.create(
        SourceConfig(kind: SourceKind.m3uFile, url: file.path, name: 'File'),
      );
      await phone.favoritesDao.setFavorite(id, ContentKind.live, 'one', true);
      await phone.channelListsDao.createList(
        id,
        'Sports',
        channels: ['one', 'two'],
      );
      await phone.progressDao.saveProgress(
        id,
        PlayableKind.episode,
        'episode',
        60000,
        2400000,
        seriesKey: 'series',
      );
      await phone.recentDao.markRecent(id, 'one');
      await phone.settingsDao.setJson(
        kAppSettingsKey,
        const AppSettings(locale: AppLocaleSetting.ar).toJson(),
      );
      final target = await LocalSyncStore(phone).export();
      expect(
        {for (final r in target.values) r['type']},
        {
          'source',
          'file',
          'favorite',
          'list',
          'item',
          'progress',
          'recent',
          'preferences',
        },
      );
      // The TV already holds the subscription and its own "Sports" list.
      final tid = await seed(tv);
      final list = await tv.channelListsDao.createList(
        tid,
        'Sports',
        channels: ['two'],
      );
      await setCreatedAt(tv, list, 1);
      final store = LocalSyncStore(
        tv,
        directory: () async => Directory('${temp.path}/tv'),
      );
      await store.apply(target);
      expect(syncChanges(target, await store.export()), isEmpty);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test(
    'renaming a list and reusing its old name keeps two lists everywhere',
    () async {
      final id = await seed(phone);
      final sports = await phone.channelListsDao.createList(
        id,
        'Sports',
        channels: ['one'],
      );
      await login(a);
      await login(b);
      await phone.channelListsDao.renameList(sports, 'News');
      await phone.channelListsDao.createList(id, 'Sports', channels: ['two']);
      await a.sync();
      await b.sync();
      await a.sync();
      final tid = (await tv.sourcesDao.all()).single.id;
      expect(await describeLists(tv, tid), ['News=one', 'Sports=two']);
      expect(await describeLists(phone, id), ['News=one', 'Sports=two']);
    },
  );

  test(
    'a source moved to a new address and the old address added again stay two',
    () async {
      final id = await seed(phone);
      await login(a);
      await login(b);
      final old = (await phone.sourcesDao.configFor(id))!;
      await phone.sourcesDao.updateConfig(
        id,
        old.copyWith(url: 'https://new-dns.example'),
      );
      await seed(phone);
      await a.sync();
      await b.sync();
      expect(
        [
          for (final s in await tv.sourcesDao.all())
            (await tv.sourcesDao.configFor(s.id))!.url,
        ],
        ['https://new-dns.example', 'https://provider.example'],
      );
    },
  );

  test(
    'the same subscription added twice keeps its own favourites and deletion',
    () async {
      final home = await seed(phone);
      final bedroom = await phone.sourcesDao.create(
        const SourceConfig(
          kind: SourceKind.xtream,
          name: 'Bedroom',
          url: 'https://provider.example',
          username: 'sample',
          password: 'private-password',
        ),
      );
      await phone.favoritesDao.setFavorite(home, ContentKind.live, 'a', true);
      await phone.favoritesDao.setFavorite(home, ContentKind.live, 'b', true);
      await phone.favoritesDao.setFavorite(
        bedroom,
        ContentKind.live,
        'c',
        true,
      );
      await login(a);
      await login(b);
      expect(await phone.favoritesDao.favoriteKeys(home, ContentKind.live), [
        'a',
        'b',
      ]);
      expect(await phone.favoritesDao.favoriteKeys(bedroom, ContentKind.live), [
        'c',
      ]);
      final copies = await tv.sourcesDao.all();
      expect([for (final s in copies) s.name], ['Sports', 'Bedroom']);
      await tv.sourcesDao.deleteSource(copies.last.id);
      await b.sync();
      await a.sync();
      await a.sync();
      await b.sync();
      expect(
        [for (final s in await phone.sourcesDao.all()) s.name],
        ['Sports'],
      );
      expect([for (final s in await tv.sourcesDao.all()) s.name], ['Sports']);
    },
  );

  test(
    'two sources an earlier version gave one cloud ID get their own',
    () async {
      final first = await seed(phone);
      final second = await seed(phone);
      final shared = syncId(['xtream', 'https://provider.example', 'sample']);
      await phone.settingsDao.setJson('account_sync_ids_v1', {
        'source:$first': shared,
        'source:$second': shared,
      });
      final exported = await LocalSyncStore(phone).export();
      final records = [
        for (final r in exported.values)
          if (r['type'] == 'source') r,
      ];
      expect(records, hasLength(2));
      // The older row keeps the identity other devices already know.
      expect(exported['source:$shared']!['position'], 0);
    },
  );

  test('a playlist from a device with another gzip encoder settles, '
      'also after a restart', () async {
    final temp = await Directory.systemTemp.createTemp('iptv-sync-test-');
    try {
      final imported = <int>[];
      LocalSyncStore tvStore() => LocalSyncStore(
        tv,
        directory: () async => Directory('${temp.path}/tv'),
      );
      a.dispose();
      b.dispose();
      a = AccountController(
        db: phone,
        api: FakeApi(cloud),
        vault: MemoryVault(),
        local: WindowsZlibStore(phone),
      );
      b = AccountController(
        db: tv,
        api: FakeApi(cloud),
        vault: MemoryVault(),
        local: tvStore(),
        onImported: imported.addAll,
      );
      final file = File('${temp.path}/original.m3u')
        ..writeAsStringSync(
          '#EXTM3U\n#EXTINF:-1,Sample\nhttps://provider.example/live.ts\n',
        );
      await phone.sourcesDao.create(
        SourceConfig(kind: SourceKind.m3uFile, url: file.path, name: 'File'),
      );
      await login(a);
      await login(b);
      await a.sync();
      await b.sync();
      final settled = cloud.version;
      imported.clear();
      for (var i = 0; i < 3; i++) {
        await a.sync();
        await b.sync();
      }
      expect(cloud.version, settled);
      expect(imported, isEmpty);
      final vault = b.vault;
      b.dispose();
      b = AccountController(
        db: tv,
        api: FakeApi(cloud),
        vault: vault,
        local: tvStore(),
        onImported: imported.addAll,
      );
      await b.start();
      await a.sync();
      await b.sync();
      expect(b.view.error, isNull);
      expect(cloud.version, settled);
      expect(imported, isEmpty);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('the same playlist in another gzip encoding keeps the local copy and '
      'catalogue', () async {
    final temp = await Directory.systemTemp.createTemp('iptv-sync-test-');
    try {
      final file = File('${temp.path}/original.m3u')
        ..writeAsStringSync(
          '#EXTM3U\n#EXTINF:-1,Sample\nhttps://provider.example/live.ts\n',
        );
      final id = await phone.sourcesDao.create(
        SourceConfig(kind: SourceKind.m3uFile, url: file.path, name: 'File'),
      );
      final store = LocalSyncStore(phone, directory: () async => temp);
      final local = await store.export();
      // What an older Windows device uploads for the same playlist.
      final target = await WindowsZlibStore(phone).export();
      expect(syncChanges(local, target), isNotEmpty);
      expect(await store.apply(target), isEmpty);
      expect((await phone.sourcesDao.configFor(id))!.url, file.path);
      expect(syncChanges(target, await store.export()), isEmpty);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test(
    'a rolled-back apply gives no cloud ID to a later local source',
    () async {
      await seed(phone);
      final target = await LocalSyncStore(phone).export();
      final sports = target.keys.singleWhere((k) => k.startsWith('source:'));
      // A playlist whose chunks never arrived makes the apply roll back after
      // it created the phone's subscription here.
      target['source:incomplete'] = {
        ...target[sports]!,
        'source': 'incomplete',
        'kind': SourceKind.m3uFile.name,
        'url': '',
        'fileParts': 2,
        'fileHash': syncId('missing'),
      };
      final store = LocalSyncStore(tv);
      await expectLater(
        store.apply(target),
        throwsA(
          isA<AccountException>().having(
            (e) => e.code,
            'code',
            'INVALID_PLAYLIST',
          ),
        ),
      );
      expect(await tv.sourcesDao.all(), isEmpty);
      await tv.sourcesDao.create(
        const SourceConfig(
          kind: SourceKind.xtream,
          name: 'News',
          url: 'https://other-provider.example',
          username: 'tv-user',
          password: 'tv-secret',
        ),
      );
      final exported = await store.export();
      expect(exported, isNot(contains(sports)));
      expect(
        exported.values.singleWhere((r) => r['type'] == 'source')['name'],
        'News',
      );
    },
  );

  test('an upload cut off between commits never publishes a playlist '
      'without its chunks', () async {
    final temp = await Directory.systemTemp.createTemp('iptv-sync-test-');
    try {
      b.dispose();
      b = AccountController(
        db: tv,
        api: FakeApi(cloud),
        vault: MemoryVault(),
        local: LocalSyncStore(
          tv,
          directory: () async => Directory('${temp.path}/tv'),
        ),
      );
      final id = await seed(phone);
      await login(a);
      await login(b);
      // Synthetic channels that do not compress away: two chunks.
      final random = Random(7);
      final lines = StringBuffer('#EXTM3U\n');
      for (var i = 0; i < 8000; i++) {
        final path = base64Url.encode([
          for (var j = 0; j < 48; j++) random.nextInt(256),
        ]);
        lines.write('#EXTINF:-1,Channel $i\nhttp://127.0.0.1:9/$path.ts\n');
      }
      final file = File('${temp.path}/big.m3u')
        ..writeAsStringSync(lines.toString());
      await phone.sourcesDao.create(
        SourceConfig(kind: SourceKind.m3uFile, url: file.path, name: 'Big'),
      );
      await phone.favoritesDao.setFavorite(id, ContentKind.live, 'one', true);
      cloud.cutAfter = 1;
      await a.sync();
      cloud.cutAfter = null;
      expect(a.view.error, 'NETWORK_ERROR');
      expect(cloud.data.keys.where((k) => k.startsWith('file:')), hasLength(1));
      expect(
        cloud.data.values.where(
          (r) => r['type'] == 'source' && r['name'] == 'Big',
        ),
        isEmpty,
      );
      // The TV syncs while the phone is away.
      await b.sync();
      expect(b.view.error, isNull);
      await a.sync();
      await b.sync();
      final copy = (await tv.sourcesDao.all()).singleWhere(
        (s) => s.name == 'Big',
      );
      expect(
        await File((await tv.sourcesDao.configFor(copy.id))!.url)
            .readAsString(),
        lines.toString(),
      );
      expect(
        cloud.data.values.where((r) => r['type'] == 'file').length,
        greaterThan(1),
      );
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('a subscription deleted on one device while edited on the other is '
      'deleted everywhere', () async {
    final id = await seed(phone);
    await phone.favoritesDao.setFavorite(id, ContentKind.live, 'fav', true);
    await phone.channelListsDao.createList(id, 'Mine', channels: ['one']);
    await login(a);
    await login(b);
    final tid = (await tv.sourcesDao.all()).single.id;
    // The TV edits the subscription before it hears of the deletion.
    final old = (await tv.sourcesDao.configFor(tid))!;
    await tv.sourcesDao.updateConfig(tid, old.copyWith(name: 'Renamed'));
    await phone.sourcesDao.deleteSource(id);
    await a.sync();
    await b.sync();
    await a.sync();
    expect(await phone.sourcesDao.all(), isEmpty);
    expect(await tv.sourcesDao.all(), isEmpty);
  });

  test('local edits commit on the last synced state without a read', () async {
    final id = await seed(phone);
    await login(a);
    await login(b);
    final reads = cloud.reads;
    await phone.favoritesDao.setFavorite(id, ContentKind.live, 'one', true);
    await a.sync();
    expect(cloud.reads, reads);
    expect(cloud.data.values.any((r) => r['key'] == 'one'), true);
    // An edit from another device in between turns the commit into a
    // conflict, then a read and merge that keeps both.
    final tid = (await tv.sourcesDao.all()).single.id;
    await tv.favoritesDao.setFavorite(tid, ContentKind.live, 'tv', true);
    await b.sync();
    await phone.favoritesDao.setFavorite(id, ContentKind.live, 'phone', true);
    final before = cloud.reads;
    await a.sync();
    expect(a.view.error, isNull);
    expect(cloud.reads, before + 1);
    expect(
      (await phone.favoritesDao.favoriteKeys(id, ContentKind.live)).toSet(),
      {'one', 'tv', 'phone'},
    );
  });

  int? uploadedPosition() =>
      cloud.data.values.firstWhere(
            (r) => r['type'] == 'progress',
            orElse: () => const {},
          )['positionMs']
          as int?;

  Future<int> startPlayback(Duration delay) async {
    final id = await seed(phone);
    a.dispose();
    a = AccountController(
      db: phone,
      api: FakeApi(cloud),
      vault: MemoryVault(),
      playbackDelay: delay,
    );
    await login(a);
    await a.start();
    return id;
  }

  Future<void> checkpoint(int id, int positionMs) async {
    await phone.progressDao.saveProgress(
      id,
      PlayableKind.movie,
      'film',
      positionMs,
      7200000,
    );
    // Lets the table update reach the controller.
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'playback checkpoints upload as one batch, without reading the account',
    () async {
      final id = await startPlayback(const Duration(milliseconds: 500));
      final version = cloud.version;
      final reads = cloud.reads;
      for (var i = 1; i <= 3; i++) {
        // A 10 s checkpoint during playback, then the 30 s poll.
        await checkpoint(id, i * 10000);
        await a.sync();
      }
      expect(cloud.version, version);
      await until(() => uploadedPosition() == 30000);
      expect(cloud.version, version + 1);
      expect(cloud.reads, reads);
    },
  );

  test(
    'backgrounding the app uploads waiting playback progress at once',
    () async {
      final id = await startPlayback(const Duration(hours: 1));
      await checkpoint(id, 10000);
      await a.sync();
      expect(uploadedPosition(), isNull);
      a.didChangeAppLifecycleState(AppLifecycleState.paused);
      await until(() => uploadedPosition() == 10000);
    },
  );

  test(
    'a received playlist lives in the import folder and goes with its source',
    () async {
      final temp = await Directory.systemTemp.createTemp('iptv-sync-test-');
      try {
        final support = '${temp.path}/tv';
        b.dispose();
        b = AccountController(
          db: tv,
          api: FakeApi(cloud),
          vault: MemoryVault(),
          local: LocalSyncStore(tv, directory: () async => Directory(support)),
        );
        final file = File('${temp.path}/original.m3u')
          ..writeAsStringSync(
            '#EXTM3U\n#EXTINF:-1,Sample\nhttps://provider.example/live.ts\n',
          );
        final id = await phone.sourcesDao.create(
          SourceConfig(kind: SourceKind.m3uFile, url: file.path, name: 'File'),
        );
        await login(a);
        await login(b);
        final copy = (await tv.sourcesDao.all()).single;
        final first = (await tv.sourcesDao.configFor(copy.id))!.url;
        expect(
          File(first).parent.path,
          '$support${Platform.pathSeparator}${SourceRepository.importDirName}',
        );
        // A replaced playlist leaves no stale copy behind.
        file.writeAsStringSync(
          '#EXTM3U\n#EXTINF:-1,Other channel\nhttps://provider.example/other.ts\n',
        );
        await a.sync();
        await b.sync();
        final second = (await tv.sourcesDao.configFor(copy.id))!.url;
        expect(second, isNot(first));
        expect(File(first).existsSync(), isFalse);
        expect(await File(second).readAsString(), file.readAsStringSync());
        // Deleting the source on the TV removes its copy, as for an import.
        await SourceRepository(
          tv,
          DbSecretStore(tv),
          appSupportDir: () async => support,
        ).delete(copy.id);
        expect(File(second).existsSync(), isFalse);
        expect(await phone.sourcesDao.configFor(id), isNotNull);
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'signing in keeps an imported playlist file and its catalogue',
    () async {
      final temp = await Directory.systemTemp.createTemp('iptv-sync-test-');
      try {
        final imports = Directory('${temp.path}/sources')..createSync();
        final copy = File('${imports.path}/copy.m3u')
          ..writeAsStringSync(
            '#EXTM3U\n#EXTINF:-1,Sample\nhttps://provider.example/live.ts\n',
          );
        // A deleted source left a gap in the order, so sign-in renumbers it.
        final gone = await seed(phone);
        final id = await phone.sourcesDao.create(
          SourceConfig(kind: SourceKind.m3uFile, url: copy.path, name: 'File'),
        );
        await phone.sourcesDao.deleteSource(gone);
        final imported = <int>[];
        a.dispose();
        a = AccountController(
          db: phone,
          api: FakeApi(cloud),
          vault: MemoryVault(),
          local: LocalSyncStore(phone, directory: () async => temp),
          onImported: imported.addAll,
        );
        await login(a);
        expect(a.view.error, isNull);
        expect((await phone.sourcesDao.configFor(id))!.url, copy.path);
        expect(imported, isEmpty);
        expect(
          [
            for (final f in temp.listSync(recursive: true))
              if (f is File) f.path,
          ],
          [copy.path],
        );
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  test('an unreadable secure session explains the sign-in form', () async {
    a.dispose();
    a = AccountController(db: phone, api: FakeApi(cloud), vault: BrokenVault());
    await a.start();
    expect(a.view.email, isNull);
    expect(a.view.error, 'SESSION_STORAGE');
  });

  test('a failed sign-in leaves no error in the shared account view', () async {
    await seed(phone);
    await login(a);
    await a.signOut();
    await expectLater(
      a.authenticate('other@example.test', 'password'),
      throwsA(isA<AccountException>()),
    );
    expect(a.view.error, isNull);
    expect(a.view.busy, isFalse);
  });
}
