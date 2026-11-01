import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart' show PlatformException;
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

/// A secure storage whose writes (and reads, with [readHangs]) never
/// return, like the Windows store retrying a file it cannot write.
class HangingVault extends MemoryVault {
  HangingVault({this.readHangs = false});
  final bool readHangs;
  @override
  Future<String?> read() =>
      readHangs ? Completer<String?>().future : super.read();
  @override
  Future<void> write(String? value) => Completer<void>().future;
}

/// A secure storage that reads but rejects every write, like a locked
/// Linux keyring.
class ReadOnlyVault extends MemoryVault {
  @override
  Future<void> write(String? value) async =>
      throw PlatformException(code: 'Libsecret error', message: 'locked');
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
  int refreshes = 0;
  void check() {
    if (cloud.offline) throw const AccountException('NETWORK_ERROR');
  }

  @override
  Future<AccountSession> refresh(AccountSession session) async {
    check();
    refreshes++;
    return AccountSession(
      uid: session.uid,
      email: session.email,
      idToken: 'token-$refreshes',
      refreshToken: session.refreshToken,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
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
      expect((await store.apply(target)).imports, isEmpty);
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

  /// A sign-in saved by an earlier run, expired when [expired].
  String savedSession({bool expired = false}) => jsonEncode(
    AccountSession(
      uid: 'owner',
      email: 'owner@example.test',
      idToken: 'token',
      refreshToken: 'refresh',
      expiresAt: DateTime.now().add(
        expired ? const Duration(minutes: -5) : const Duration(hours: 1),
      ),
    ).toJson(),
  );

  test('a sign-in the secure storage lost asks to sign in again, also after '
      'the sign-in expired and the app restarted', () async {
    final vault = MemoryVault();
    a.dispose();
    a = AccountController(db: phone, api: FakeApi(cloud), vault: vault);
    await a.start();
    expect(a.view.error, isNull, reason: 'never signed in');
    await login(a);
    a.dispose();
    // Android resets an entry it can no longer decrypt: it reads as empty.
    vault.value = null;
    a = AccountController(db: phone, api: FakeApi(cloud), vault: vault);
    await a.start();
    expect(a.view.email, isNull);
    expect(a.view.error, 'SESSION_EXPIRED');
    // A failed attempt does not hide that the device needs a sign-in.
    await expectLater(
      a.authenticate('other@example.test', 'password'),
      throwsA(isA<AccountException>()),
    );
    expect(a.view.error, 'SESSION_EXPIRED');
    await login(a);
    expect(a.view.error, isNull);
    a.dispose();
    a = AccountController(db: phone, api: FakeApi(cloud), vault: vault);
    await a.start();
    expect(a.view.email, 'owner@example.test');
    expect(a.view.error, isNull);
    await a.signOut();
    a.dispose();
    a = AccountController(db: phone, api: FakeApi(cloud), vault: vault);
    await a.start();
    expect(a.view.error, isNull, reason: 'signed out on purpose');
  });

  test(
    'a sign-in saved by v0.1.7 is restored, and asks again once lost',
    () async {
      final vault = MemoryVault()..value = savedSession();
      await phone.settingsDao.setString(AccountController.bindingKey, 'owner');
      a.dispose();
      a = AccountController(db: phone, api: FakeApi(cloud), vault: vault);
      await a.start();
      expect(a.view.email, 'owner@example.test');
      // The account's email, which v0.1.7 did not keep, names the owner.
      expect(a.view.owner, 'owner@example.test');
      a.dispose();
      vault.value = null;
      a = AccountController(db: phone, api: FakeApi(cloud), vault: vault);
      await a.start();
      expect(a.view.error, 'SESSION_EXPIRED');
      expect(a.view.owner, 'owner@example.test');
    },
  );

  test('a secure storage that stops answering cannot freeze sign-in, sync '
      'or sign-out', () async {
    const limit = Duration(milliseconds: 200);
    a.dispose();
    a = AccountController(
      db: phone,
      api: FakeApi(cloud),
      vault: HangingVault(),
      vaultTimeout: limit,
    );
    await a.start();
    // The sign-in it cannot save syncs from memory.
    await a
        .authenticate('owner@example.test', 'sample-password')
        .timeout(const Duration(seconds: 2));
    expect(a.view.email, 'owner@example.test');
    expect(a.view.busy, isFalse);
    // A saved sign-in whose refreshed token cannot be saved keeps syncing.
    await seed(phone);
    await phone.settingsDao.setString(AccountController.bindingKey, 'owner');
    a.dispose();
    final api = FakeApi(cloud);
    a = AccountController(
      db: phone,
      api: api,
      vault: HangingVault()..value = savedSession(expired: true),
      vaultTimeout: limit,
    );
    await a.start();
    await a.sync(force: true);
    expect(a.view.busy, isFalse);
    expect(a.view.error, isNull);
    expect(api.refreshes, 1);
    expect(cloud.data.values.where((r) => r['type'] == 'source'), hasLength(1));
    await a.signOut().timeout(const Duration(seconds: 2));
    expect(a.view.email, isNull);
    // A read that never returns explains the sign-in form, and signing in
    // does not wait for it forever.
    a.dispose();
    a = AccountController(
      db: phone,
      api: FakeApi(cloud),
      vault: HangingVault(readHangs: true),
      vaultTimeout: limit,
    );
    await a.start();
    expect(a.view.error, 'SESSION_STORAGE');
    await a
        .authenticate('owner@example.test', 'sample-password')
        .timeout(const Duration(seconds: 2));
    expect(a.view.email, 'owner@example.test');
  });

  test('a secure storage that rejects writes still signs out, also after a '
      'restart, and syncs on a refreshed token it cannot save', () async {
    await seed(phone);
    await phone.settingsDao.setString(AccountController.bindingKey, 'owner');
    final vault = ReadOnlyVault()..value = savedSession(expired: true);
    final api = FakeApi(cloud);
    a.dispose();
    a = AccountController(db: phone, api: api, vault: vault);
    await a.start();
    for (var i = 0; i < 3; i++) {
      await a.sync(force: true);
    }
    expect(a.view.error, isNull);
    expect(api.refreshes, 1);
    expect(cloud.data.values.where((r) => r['type'] == 'source'), hasLength(1));
    await a.signOut();
    expect(a.view.email, isNull);
    expect(a.view.error, isNull);
    final reads = cloud.reads;
    await a.sync(force: true);
    expect(cloud.reads, reads);
    // The stored sign-in could not be deleted, yet the device stays signed
    // out.
    expect(vault.value, isNotNull);
    a.dispose();
    a = AccountController(db: phone, api: api, vault: vault);
    await a.start();
    expect(a.view.email, isNull);
    expect(a.view.error, isNull);
  });

  test('a subscription moved and a list renamed after their first upload '
      'merge when another device links', () async {
    final id = await phone.sourcesDao.create(
      const SourceConfig(
        kind: SourceKind.xtream,
        name: 'Sports',
        url: 'https://old-dns.example',
        username: 'sample',
        password: 'private-password',
      ),
    );
    await phone.favoritesDao.setFavorite(id, ContentKind.live, 'one', true);
    final list = await phone.channelListsDao.createList(
      id,
      'Sports',
      channels: ['one'],
    );
    await login(a);
    final old = (await phone.sourcesDao.configFor(id))!;
    await phone.sourcesDao.updateConfig(
      id,
      old.copyWith(url: 'https://new-dns.example'),
    );
    await phone.channelListsDao.renameList(list, 'Football');
    await a.sync();
    // The TV already holds the subscription at its new address, and a
    // list of that name.
    final tid = await tv.sourcesDao.create(
      const SourceConfig(
        kind: SourceKind.xtream,
        name: 'Sports',
        url: 'https://new-dns.example',
        username: 'sample',
        password: 'private-password',
      ),
    );
    await tv.favoritesDao.setFavorite(tid, ContentKind.live, 'two', true);
    await tv.channelListsDao.createList(tid, 'Football', channels: ['two']);
    await login(b);
    await a.sync();
    expect((await tv.sourcesDao.all()).single.id, tid);
    expect(
      (await tv.favoritesDao.favoriteKeys(tid, ContentKind.live)).toSet(),
      {'one', 'two'},
    );
    expect(await describeLists(tv, tid), ['Football=one,two']);
    expect((await phone.sourcesDao.all()).single.id, id);
    expect(await describeLists(phone, id), ['Football=one,two']);
  });

  test('the same playlist file from a Windows and an Android device merges '
      'at first link', () async {
    final temp = await Directory.systemTemp.createTemp('iptv-sync-test-');
    try {
      const playlist =
          '#EXTM3U\n#EXTINF:-1,Sample\nhttps://provider.example/live.ts\n';
      final pc = File('${temp.path}/pc.m3u')..writeAsStringSync(playlist);
      final box = File('${temp.path}/tv.m3u')..writeAsStringSync(playlist);
      final pid = await phone.sourcesDao.create(
        SourceConfig(kind: SourceKind.m3uFile, url: pc.path, name: 'Home'),
      );
      final tid = await tv.sourcesDao.create(
        SourceConfig(kind: SourceKind.m3uFile, url: box.path, name: 'Home'),
      );
      await tv.favoritesDao.setFavorite(tid, ContentKind.live, 'tv', true);
      // The ID the Windows build derives from its own gzip header.
      await phone.settingsDao.setJson('account_sync_ids_v1', {
        'source:$pid': syncId([
          'm3uFile',
          base64Encode(gzip.encode(utf8.encode(playlist))..[9] = 10),
          null,
        ]),
      });
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
        local: LocalSyncStore(
          tv,
          directory: () async => Directory('${temp.path}/tv'),
        ),
      );
      await login(a);
      await login(b);
      await a.sync();
      expect(await phone.sourcesDao.all(), hasLength(1));
      expect((await tv.sourcesDao.all()).single.id, tid);
      expect((await tv.sourcesDao.configFor(tid))!.url, box.path);
      expect(await phone.favoritesDao.favoriteKeys(pid, ContentKind.live), [
        'tv',
      ]);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('first sign-in keeps a subscription deleted elsewhere while this '
      'device has its own lists, favourites or progress in it', () async {
    final id = await seed(phone);
    await phone.favoritesDao.setFavorite(id, ContentKind.live, 'shared', true);
    await login(a);
    await phone.sourcesDao.deleteSource(id);
    await a.sync();
    // An upgraded TV that never signed in, with data of its own.
    final tid = await seed(tv);
    await tv.favoritesDao.setFavorite(tid, ContentKind.live, 'shared', true);
    await tv.favoritesDao.setFavorite(tid, ContentKind.live, 'tv-only', true);
    await tv.channelListsDao.createList(tid, 'Kids', channels: ['cartoons']);
    await tv.progressDao.saveProgress(
      tid,
      PlayableKind.movie,
      'film',
      900000,
      7200000,
    );
    await login(b);
    expect(b.view.error, isNull);
    expect((await tv.sourcesDao.all()).single.id, tid);
    expect((await tv.sourcesDao.configFor(tid))!.password, 'private-password');
    // What was deleted with it elsewhere stays deleted.
    expect(await tv.favoritesDao.favoriteKeys(tid, ContentKind.live), [
      'tv-only',
    ]);
    expect(await describeLists(tv, tid), ['Kids=cartoons']);
    expect(
      await tv.progressDao.progressFor(tid, PlayableKind.movie, 'film'),
      isNotNull,
    );
    await a.sync();
    final back = (await phone.sourcesDao.all()).single.id;
    expect(await describeLists(phone, back), ['Kids=cartoons']);
  });

  test('first sign-in still removes a subscription deleted elsewhere when '
      'this device has nothing of its own in it', () async {
    final id = await seed(phone);
    await phone.favoritesDao.setFavorite(id, ContentKind.live, 'shared', true);
    await login(a);
    await phone.sourcesDao.deleteSource(id);
    await a.sync();
    final tid = await seed(tv);
    await tv.favoritesDao.setFavorite(tid, ContentKind.live, 'shared', true);
    await tv.recentDao.markRecent(tid, 'shared');
    await login(b);
    expect(b.view.error, isNull);
    expect(await tv.sourcesDao.all(), isEmpty);
  });

  test('a guide offset received from the account downloads the guides '
      'again', () async {
    final refreshed = <int>{};
    b.dispose();
    b = AccountController(
      db: tv,
      api: FakeApi(cloud),
      vault: MemoryVault(),
      onGuideOffset: refreshed.addAll,
    );
    final id = await seed(phone);
    await login(a);
    await login(b);
    final tid = (await tv.sourcesDao.all()).single.id;
    final guide = await tv.epgDao.addEpgSource(
      tid,
      'https://provider.example/xmltv.php',
      EpgOrigin.xtream,
    );
    await (tv.update(tv.epgSources)..where((e) => e.id.equals(guide))).write(
      const EpgSourcesCompanion(
        etag: Value('"v1"'),
        lastModified: Value('Sat, 31 Oct 2026 00:00:00 GMT'),
        lastFetchAt: Value(1793404800),
      ),
    );
    final old = (await phone.sourcesDao.configFor(id))!;
    await phone.sourcesDao.updateConfig(id, old.copyWith(epgOffsetMin: 60));
    await a.sync();
    await b.sync();
    expect((await tv.sourcesDao.byId(tid))!.epgOffsetMin, 60);
    final row = await (tv.select(
      tv.epgSources,
    )..where((e) => e.id.equals(guide))).getSingle();
    expect(row.etag, isNull);
    expect(row.lastModified, isNull);
    expect(row.lastFetchAt, isNull);
    expect(refreshed, {tid});
  });

  test('an unfocused window keeps syncing, and hiding it uploads playback '
      'at once', () async {
    final id = await startPlayback(const Duration(hours: 1));
    await login(b);
    final tid = (await tv.sourcesDao.all()).single.id;
    a.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await tv.favoritesDao.setFavorite(tid, ContentKind.live, 'news', true);
    await b.sync();
    // The 30 s poll.
    await a.sync();
    expect(await phone.favoritesDao.favoriteKeys(id, ContentKind.live), [
      'news',
    ]);
    await checkpoint(id, 600000);
    await a.sync();
    expect(uploadedPosition(), isNull, reason: 'batched while watching');
    a.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await until(() => uploadedPosition() == 600000);
  });

  test('returning to the app checks the account revision instead of '
      'reading the whole account', () async {
    await startPlayback(const Duration(hours: 1));
    final reads = cloud.reads;
    for (var i = 0; i < 3; i++) {
      // Focus moving to another window and back.
      a.didChangeAppLifecycleState(AppLifecycleState.inactive);
      a.didChangeAppLifecycleState(AppLifecycleState.resumed);
      // Backgrounded and back.
      a.didChangeAppLifecycleState(AppLifecycleState.hidden);
      a.didChangeAppLifecycleState(AppLifecycleState.paused);
      a.didChangeAppLifecycleState(AppLifecycleState.hidden);
      a.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await a.sync();
    }
    expect(cloud.reads, reads);
    expect(a.view.error, isNull);
  });

  test('a favourite whose upload failed during playback goes with the next '
      'poll', () async {
    final id = await startPlayback(const Duration(hours: 1));
    cloud.offline = true;
    await phone.favoritesDao.setFavorite(id, ContentKind.live, 'fav', true);
    await until(() => a.view.error == 'NETWORK_ERROR');
    // A progress checkpoint while the connection is still down.
    await checkpoint(id, 10000);
    cloud.offline = false;
    await a.sync();
    expect(cloud.data.values.any((r) => r['key'] == 'fav'), isTrue);
  });

  test(
    'unchanged polls neither export this device nor read the account',
    () async {
      final local = CountingStore(phone);
      a.dispose();
      a = AccountController(
        db: phone,
        api: FakeApi(cloud),
        vault: MemoryVault(),
        local: local,
      );
      final id = await seed(phone);
      await login(a);
      await a.start();
      final exports = local.exports;
      final reads = cloud.reads;
      for (var i = 0; i < 3; i++) {
        await a.sync();
      }
      expect(local.exports, exports);
      expect(cloud.reads, reads);
      // A change is still seen.
      await phone.favoritesDao.setFavorite(id, ContentKind.live, 'one', true);
      await until(() => cloud.data.values.any((r) => r['key'] == 'one'));
    },
  );

  test('a secure storage that rejects writes still signs in and syncs, and '
      'asks for a sign-in after a restart', () async {
    final id = await seed(phone);
    final vault = ReadOnlyVault();
    a.dispose();
    a = AccountController(db: phone, api: FakeApi(cloud), vault: vault);
    await a.start();
    await login(a);
    expect(a.view.email, 'owner@example.test');
    expect(a.view.error, isNull);
    expect(cloud.data.values.where((r) => r['type'] == 'source'), hasLength(1));
    await phone.favoritesDao.setFavorite(id, ContentKind.live, 'one', true);
    await a.sync();
    expect(cloud.data.values.any((r) => r['key'] == 'one'), isTrue);
    a.dispose();
    a = AccountController(db: phone, api: FakeApi(cloud), vault: vault);
    await a.start();
    expect(a.view.email, isNull);
    expect(a.view.error, 'SESSION_EXPIRED');
  });

  test('Create account on a device linked to another account is refused '
      'before the account is created', () async {
    await seed(phone);
    await login(a);
    await a.signOut();
    final api = CountingApi(cloud);
    a.dispose();
    a = AccountController(db: phone, api: api, vault: MemoryVault());
    await expectLater(
      a.authenticate('other@example.test', 'sample-password', create: true),
      throwsA(
        isA<AccountException>().having((e) => e.code, 'code', 'OTHER_ACCOUNT'),
      ),
    );
    expect(api.signUps, 0);
    expect(a.view.owner, 'owner@example.test');
  });

  test('a device moves to another account only on purpose, keeping its '
      'data, and the first account keeps its copy', () async {
    final other = Cloud();
    final api = AccountsApi({'owner': cloud, 'other': other});
    a.dispose();
    a = AccountController(db: phone, api: api, vault: MemoryVault());
    final id = await seed(phone);
    await phone.favoritesDao.setFavorite(id, ContentKind.live, 'one', true);
    await login(a);
    await a.signOut();
    // Made while signed out.
    await phone.favoritesDao.setFavorite(id, ContentKind.live, 'two', true);
    final first = jsonEncode(cloud.data);
    await expectLater(
      a.authenticate('other@example.test', 'sample-password'),
      throwsA(
        isA<AccountException>().having((e) => e.code, 'code', 'OTHER_ACCOUNT'),
      ),
    );
    expect(a.view.owner, 'owner@example.test');
    await a.release();
    expect(a.view.linked, isFalse);
    expect(a.view.owner, isNull);
    await a.authenticate('other@example.test', 'sample-password');
    expect(a.view.email, 'other@example.test');
    expect(a.view.owner, 'other@example.test');
    expect(a.view.error, isNull);
    expect(await phone.sourcesDao.all(), hasLength(1));
    expect(await phone.favoritesDao.favoriteKeys(id, ContentKind.live), [
      'one',
      'two',
    ]);
    expect(
      other.data.values.where((r) => r['type'] == 'favorite'),
      hasLength(2),
    );
    expect(jsonEncode(cloud.data), first);
    // Back to the first account, also on purpose: a first sign-in again,
    // which deletes nothing there.
    await phone.favoritesDao.setFavorite(id, ContentKind.live, 'one', false);
    await a.sync();
    await a.signOut();
    await a.release();
    await login(a);
    expect(a.view.error, isNull);
    expect(cloud.deleted, isEmpty);
    expect(
      (await phone.favoritesDao.favoriteKeys(id, ContentKind.live)).toSet(),
      {'one', 'two'},
    );
  });

  test('a playlist replaced on one device while another renames it keeps '
      'both changes, and an account an older version left with chunks of '
      'another playlist is repaired', () async {
    final temp = await Directory.systemTemp.createTemp('iptv-sync-test-');
    try {
      LocalSyncStore store(AppDatabase db, String name) => LocalSyncStore(
        db,
        directory: () async => Directory('${temp.path}/$name'),
      );
      a.dispose();
      b.dispose();
      a = AccountController(
        db: phone,
        api: FakeApi(cloud),
        vault: MemoryVault(),
        local: store(phone, 'phone'),
      );
      b = AccountController(
        db: tv,
        api: FakeApi(cloud),
        vault: MemoryVault(),
        local: store(tv, 'tv'),
      );
      String playlist(String name) =>
          '#EXTM3U\n#EXTINF:-1,$name\nhttps://provider.example/$name.ts\n';
      final file = File('${temp.path}/list.m3u')
        ..writeAsStringSync(playlist('one'));
      final id = await phone.sourcesDao.create(
        SourceConfig(kind: SourceKind.m3uFile, url: file.path, name: 'File'),
      );
      await login(a);
      await login(b);
      final key = cloud.data.keys.singleWhere((k) => k.startsWith('source:'));
      final firstHash = cloud.data[key]!['fileHash'];
      final tid = (await tv.sourcesDao.all()).single.id;
      // The TV renames the playlist offline, while the phone replaces it.
      cloud.offline = true;
      final old = (await tv.sourcesDao.configFor(tid))!;
      await tv.sourcesDao.updateConfig(tid, old.copyWith(name: 'Renamed'));
      await b.sync();
      cloud.offline = false;
      final replaced = File('${temp.path}/replaced.m3u')
        ..writeAsStringSync(playlist('two'));
      await phone.sourcesDao.updateConfig(
        id,
        (await phone.sourcesDao.configFor(id))!.copyWith(url: replaced.path),
      );
      await a.sync();
      await b.sync();
      await a.sync();
      Future<String> held(AppDatabase db) async {
        final config = (await db.sourcesDao.configFor(
          (await db.sourcesDao.all()).single.id,
        ))!;
        return '${config.name}: ${File(config.url).readAsStringSync()}';
      }

      expect([a.view.error, b.view.error], [null, null]);
      expect(await held(tv), 'Renamed: ${playlist('two')}');
      expect(await held(phone), 'Renamed: ${playlist('two')}');
      // An older version renames it with the first playlist's hash, beside
      // the second one's chunks.
      FakeApi(cloud).commit({
        key: {...cloud.data[key]!, 'name': 'Older', 'fileHash': firstHash},
      });
      for (var i = 0; i < 2; i++) {
        await a.sync();
        await b.sync();
      }
      expect([a.view.error, b.view.error], [null, null]);
      expect(cloud.data[key]!['fileHash'], isNot(firstHash));
      expect(await held(tv), 'Older: ${playlist('two')}');
      expect(await held(phone), 'Older: ${playlist('two')}');
      // A device joining now receives it too.
      final pc = openTestDb();
      final c = AccountController(
        db: pc,
        api: FakeApi(cloud),
        vault: MemoryVault(),
        local: store(pc, 'pc'),
      );
      await login(c);
      expect(c.view.error, isNull);
      expect(await held(pc), 'Older: ${playlist('two')}');
      c.dispose();
      await pc.close();
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('a received channel removal keeps the order the other device '
      'made', () async {
    final id = await seed(phone);
    final lid = await phone.channelListsDao.createList(
      id,
      'Sports',
      channels: ['a', 'b', 'c', 'd'],
    );
    await login(a);
    await login(b);
    final tid = (await tv.sourcesDao.all()).single.id;
    final tlid = (await tv.channelListsDao.lists(tid)).single.id;
    // One upload: "d" moved to the top, then "a" removed.
    await phone.channelListsDao.moveChannel(lid, 'd', -3);
    await phone.channelListsDao.setChannel(lid, 'a', false);
    await a.sync();
    await b.sync();
    await b.sync();
    await a.sync();
    expect(await tv.channelListsDao.channelKeys(tlid), ['d', 'b', 'c']);
    expect(await phone.channelListsDao.channelKeys(lid), ['d', 'b', 'c']);
  });

  test('channels removed from one list on two devices both stay '
      'removed', () async {
    final id = await seed(phone);
    final lid = await phone.channelListsDao.createList(
      id,
      'Sports',
      channels: ['a', 'b', 'c', 'd'],
    );
    await login(a);
    await login(b);
    final tid = (await tv.sourcesDao.all()).single.id;
    final tlid = (await tv.channelListsDao.lists(tid)).single.id;
    cloud.offline = true;
    // Renumbers "b", "c" and "d" here.
    await phone.channelListsDao.setChannel(lid, 'a', false);
    await a.sync();
    expect(a.view.error, 'NETWORK_ERROR');
    cloud.offline = false;
    await tv.channelListsDao.setChannel(tlid, 'd', false);
    await b.sync();
    await a.sync();
    await b.sync();
    expect(await tv.channelListsDao.channelKeys(tlid), ['b', 'c']);
    expect(await phone.channelListsDao.channelKeys(lid), ['b', 'c']);
  });

  test("an account emptied on the server keeps every device's data, which "
      'goes back to the account', () async {
    final id = await seed(phone);
    await phone.favoritesDao.setFavorite(id, ContentKind.live, 'one', true);
    await phone.channelListsDao.createList(id, 'Kids', channels: ['cartoons']);
    await phone.progressDao.saveProgress(
      id,
      PlayableKind.movie,
      'film',
      900000,
      7200000,
    );
    await login(a);
    await login(b);
    final tid = (await tv.sourcesDao.all()).single.id;
    await tv.favoritesDao.setFavorite(tid, ContentKind.live, 'tv', true);
    await b.sync();
    final keys = cloud.data.keys.toSet();
    // Its documents deleted in the console: no tombstones are left.
    cloud
      ..data = {}
      ..deleted.clear()
      ..version = 0;
    await a.sync();
    await b.sync();
    await a.sync();
    expect([a.view.error, b.view.error], [null, null]);
    expect(cloud.data.keys.toSet(), keys);
    for (final (db, sid) in [(phone, id), (tv, tid)]) {
      expect(await db.sourcesDao.all(), hasLength(1));
      expect(
        (await db.favoritesDao.favoriteKeys(sid, ContentKind.live)).toSet(),
        {'one', 'tv'},
      );
      expect(await db.channelListsDao.lists(sid), hasLength(1));
      expect(
        await db.progressDao.progressFor(sid, PlayableKind.movie, 'film'),
        isNotNull,
      );
    }
  });

  test('records, fields and kinds a newer version adds survive the syncs '
      'of this version', () async {
    final id = await seed(phone);
    await phone.favoritesDao.setFavorite(id, ContentKind.live, 'one', true);
    await login(a);
    final key = cloud.data.keys.singleWhere((k) => k.startsWith('source:'));
    final sid = cloud.data[key]!['source']! as String;
    final added = <String, Map<String, Object?>>{
      'channelpref:$sid:bein1': {
        'type': 'channelpref',
        'source': sid,
        'aspect': 'fill',
      },
      'favorite:$sid:radio:fm1': {
        'type': 'favorite',
        'source': sid,
        'kind': 'radio',
        'key': 'fm1',
        'position': 0,
        'addedAt': 1,
      },
      'source:portal': {
        ...cloud.data[key]!,
        'source': 'portal',
        'kind': 'portal',
        'position': 1,
      },
      'favorite:portal:live:x': {
        'type': 'favorite',
        'source': 'portal',
        'kind': 'live',
        'key': 'x',
        'position': 0,
        'addedAt': 1,
      },
    };
    FakeApi(cloud).commit({
      ...added,
      key: {...cloud.data[key]!, 'catchupDays': 7},
    });
    await a.sync();
    expect(a.view.error, isNull);
    await phone.favoritesDao.setFavorite(id, ContentKind.live, 'two', true);
    final old = (await phone.sourcesDao.configFor(id))!;
    await phone.sourcesDao.updateConfig(id, old.copyWith(name: 'Renamed'));
    await a.sync();
    await a.sync();
    final vault = a.vault;
    a.dispose();
    a = AccountController(db: phone, api: FakeApi(cloud), vault: vault);
    await a.start();
    await a.sync(force: true);
    expect(a.view.error, isNull);
    expect(cloud.deleted, isEmpty);
    for (final e in added.entries) {
      expect(cloud.data[e.key], e.value, reason: e.key);
    }
    expect(cloud.data[key]!['catchupDays'], 7);
    expect(cloud.data[key]!['name'], 'Renamed');
    expect(cloud.data.values.any((r) => r['key'] == 'two'), isTrue);
    expect(await phone.sourcesDao.all(), hasLength(1));
  });

  group('changes to merge into the account', () {
    Map<String, Object?> item(String key, int position) => {
      'type': 'item',
      'list': 'l',
      'key': key,
      'position': position,
      'addedAt': 1,
    };
    Map<String, Object?> source(String name, String hash) => {
      'type': 'source',
      'source': 's',
      'name': name,
      'kind': 'm3uFile',
      'url': '',
      'fileParts': 1,
      'fileHash': hash,
    };
    Map<String, Object?> chunk(String data) => {
      'type': 'file',
      'source': 's',
      'part': 0,
      'data': data,
    };

    test('only a tombstone deletes: a record the account lost is sent '
        'again', () {
      final base = {'item:l:a': item('a', 0), 'item:l:b': item('b', 1)};
      final changes = pendingSyncChanges(base, {}, {'item:l:b'}, base);
      expect(changes, {'item:l:a': item('a', 0)});
    });

    test('a list entry deleted elsewhere is not revived by a renumbering '
        'here, but an entry added again is', () {
      final base = {'item:l:b': item('b', 1)};
      expect(
        pendingSyncChanges(base, {}, {'item:l:b'}, {'item:l:b': item('b', 0)}),
        isEmpty,
      );
      final again = {...item('b', 0), 'addedAt': 2};
      expect(pendingSyncChanges(base, {}, {'item:l:b'}, {'item:l:b': again}), {
        'item:l:b': again,
      });
    });

    test('a subscription renamed here keeps the playlist replaced '
        'elsewhere, with its chunks', () {
      final base = {'source:s': source('File', 'h1'), 'file:s:0': chunk('e1')};
      final remote = {
        'source:s': source('File', 'h2'),
        'file:s:0': chunk('e2'),
      };
      final local = {...base, 'source:s': source('Renamed', 'h1')};
      expect(pendingSyncChanges(base, remote, {}, local), {
        'source:s': source('Renamed', 'h2'),
      });
    });

    test('a playlist replaced on both sides keeps this one, with all of its '
        'chunks', () {
      final base = {
        'source:s': {...source('File', 'h1'), 'fileParts': 2},
        'file:s:0': chunk('e1'),
        'file:s:1': {...chunk('tail'), 'part': 1},
      };
      final remote = {
        ...base,
        'source:s': {...source('Theirs', 'h2'), 'fileParts': 2},
        'file:s:0': chunk('e2'),
      };
      final local = {
        ...base,
        'source:s': {...source('File', 'h3'), 'fileParts': 2},
        'file:s:1': {...chunk('e3'), 'part': 1},
      };
      expect(pendingSyncChanges(base, remote, {}, local), {
        'source:s': {...source('Theirs', 'h3'), 'fileParts': 2},
        'file:s:0': chunk('e1'),
        'file:s:1': {...chunk('e3'), 'part': 1},
      });
    });
  });
}

/// Counts the accounts created.
class CountingApi extends FakeApi {
  CountingApi(super.cloud);
  int signUps = 0;
  @override
  Future<AccountSession> signIn(
    String email,
    String password, {
    bool create = false,
  }) {
    if (create) signUps++;
    return super.signIn(email, password, create: create);
  }
}

/// Every account its own [Cloud], by the uid [FakeApi] signs in with.
class AccountsApi extends FakeApi {
  AccountsApi(this.clouds) : super(clouds['owner']!);
  final Map<String, Cloud> clouds;
  FakeApi _of(AccountSession session) => FakeApi(clouds[session.uid]!);
  @override
  Future<String?> revision(AccountSession session) =>
      _of(session).revision(session);
  @override
  Future<RemoteState> read(AccountSession session) =>
      _of(session).read(session);
  @override
  Future<String?> write(
    AccountSession session,
    RemoteState remote,
    Map<String, Map<String, Object?>?> changes,
  ) => _of(session).write(session, remote, changes);
}

/// Counts exports of this device's account data.
class CountingStore extends LocalSyncStore {
  CountingStore(super.db);
  int exports = 0;
  @override
  Future<SyncData> export() {
    exports++;
    return super.export();
  }
}
