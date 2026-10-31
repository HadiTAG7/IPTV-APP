import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/account/account_controller.dart';
import 'package:iptv_player/account/firebase_api.dart';
import 'package:iptv_player/account/local_sync_store.dart';
import 'package:iptv_player/account/sync_model.dart';
import 'package:iptv_player/app/settings.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/sources/models.dart';

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

class Cloud {
  SyncData data = {};
  final deleted = <String>{};
  int version = 0;
  bool offline = false;
  int reads = 0;
  Future<void> Function()? duringWrite;
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
    if (changes.isNotEmpty) {
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
    return version;
  }
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
      channels: ['one', 'two', 'local-only'],
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
}
