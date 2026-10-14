import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/secure/secret_store.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/sources/models.dart';

import 'db_test_utils.dart';

void main() {
  late FakeClock clock;
  late AppDatabase db;

  setUp(() {
    clock = FakeClock(testEpoch);
    db = openTestDb(clock: clock);
  });

  tearDown(() => db.close());

  group('sources', () {
    test('create, list in order, reorder and update', () async {
      final sources = db.sourcesDao;
      final a = await addSource(db, name: 'A');
      final b = await sources.create(
        const SourceConfig(
          kind: SourceKind.xtream,
          url: 'http://127.0.0.1:8080',
          name: 'B',
          username: 'demo',
          password: 'ignored',
          userAgent: 'TestAgent/1.0',
          liveFormat: LiveFormat.m3u8,
          epgOffsetMin: 60,
        ),
      );
      final c = await addSource(db, name: 'C', kind: SourceKind.m3uFile);
      expect((await sources.all()).map((s) => s.id), [a, b, c]);
      expect((await sources.all()).map((s) => s.sortIndex), [0, 1, 2]);

      final row = (await sources.byId(b))!;
      expect(row.kind, SourceKind.xtream);
      expect(row.username, 'demo');
      expect(row.liveFormat, LiveFormat.m3u8);
      expect(row.epgOffsetMin, 60);
      expect(row.accountStatus, AccountStatus.unknown);
      expect(row.generation, 0);
      expect(row.hasCatalog, isFalse);

      await sources.reorder([c, a, b]);
      expect((await sources.all()).map((s) => s.name), ['C', 'A', 'B']);

      await sources.updateConfig(
        b,
        row.toConfig().copyWith(name: 'B2', referer: 'http://example.com/'),
      );
      final updated = (await sources.byId(b))!;
      expect(updated.name, 'B2');
      expect(updated.referer, 'http://example.com/');
      expect(updated.username, 'demo');
      expect(await sources.byId(999), isNull);
    });

    test('active source: set, fall back, cleared on delete', () async {
      final sources = db.sourcesDao;
      expect(await sources.activeSource(), isNull);
      final a = await addSource(db, name: 'A');
      final b = await addSource(db, name: 'B');
      expect(await sources.activeSourceId(), isNull);
      expect((await sources.activeSource())?.id, a);
      await sources.setActive(b);
      expect(await sources.activeSourceId(), b);
      expect(await db.settingsDao.getInt(SettingKeys.activeSourceId), b);
      expect((await sources.activeSource())?.id, b);
      expect(() => sources.setActive(12345), throwsStateError);

      await sources.deleteSource(b);
      expect(await sources.activeSourceId(), isNull);
      expect((await sources.activeSource())?.id, a);
    });

    test('watchActiveSourceId and watchAll emit', () async {
      final ids = <int?>[];
      final lists = <int>[];
      final s1 = db.sourcesDao.watchActiveSourceId().listen(ids.add);
      final s2 = db.sourcesDao.watchAll().listen((l) => lists.add(l.length));
      await pumpEventQueue();
      final a = await addSource(db);
      await db.sourcesDao.setActive(a);
      await pumpEventQueue();
      await s1.cancel();
      await s2.cancel();
      expect(ids.first, isNull);
      expect(ids.last, a);
      expect(lists.last, 1);
    });

    test('account, engines and timestamps', () async {
      final sources = db.sourcesDao;
      final id = await addSource(db, kind: SourceKind.xtream);
      await sources.updateAccount(
        id,
        AccountInfo(
          status: AccountStatus.expired,
          expiresAt: DateTime.utc(2026, 3, 1),
          maxConnections: 1,
          allowedFormats: const ['m3u8', 'ts'],
        ),
      );
      await sources.setEngines(id, live: EngineKind.exo, vod: null);
      await sources.markSynced(id);
      clock.advance(const Duration(hours: 1));
      await sources.markEpgFetched(id);
      final row = (await sources.byId(id))!;
      expect(row.accountStatus, AccountStatus.expired);
      expect(row.expiresAt, DateTime.utc(2026, 3, 1));
      expect(row.maxConnections, 1);
      expect(row.allowedFormats, ['m3u8', 'ts']);
      expect(row.engineLive, EngineKind.exo);
      expect(row.engineVod, isNull);
      expect(row.lastSyncAt, testEpoch);
      expect(row.lastEpgAt, testEpoch.add(const Duration(hours: 1)));
      expect(await sources.generationOf(id), 0);
    });

    test('configFor joins the password from the secret store', () async {
      final id = await addSource(db, kind: SourceKind.xtream);
      final secrets = DbSecretStore(db);
      await secrets.write(id, SecretNames.password, 'pw-123');
      final config = (await db.sourcesDao.configFor(id, secrets))!;
      expect(config.id, id);
      expect(config.password, 'pw-123');
      expect(config.kind, SourceKind.xtream);
      expect(await db.sourcesDao.configFor(777, secrets), isNull);
    });
  });

  group('settings', () {
    test('typed round trips', () async {
      final s = db.settingsDao;
      expect(await s.getJson('missing'), isNull);
      await s.setString('locale', 'ar');
      await s.setInt('count', 42);
      await s.setBool('lite', true);
      await s.setJson('map', {
        'a': [1, 2],
        'b': 'x',
      });
      expect(await s.getString('locale'), 'ar');
      expect(await s.getInt('count'), 42);
      expect(await s.getBool('lite'), isTrue);
      expect(await s.getJson('map'), {
        'a': [1, 2],
        'b': 'x',
      });

      // Wrong types read as null.
      expect(await s.getInt('locale'), isNull);
      expect(await s.getBool('count'), isNull);
      expect(await s.getString('count'), isNull);

      await s.setJson('d', 3.0);
      expect(await s.getInt('d'), 3);
      await s.setJson('f', 3.5);
      expect(await s.getInt('f'), isNull);

      await s.setString('locale', null);
      expect(await s.getString('locale'), isNull);
      await s.remove('count');
      expect(await s.getInt('count'), isNull);
    });

    test('unreadable JSON reads as null', () async {
      await db
          .into(db.settings)
          .insert(SettingsCompanion.insert(key: 'broken', json: '{oops'));
      expect(await db.settingsDao.getJson('broken'), isNull);
    });

    test('watch emits distinct values', () async {
      final seen = <bool?>[];
      final sub = db.settingsDao.watchBool('lite').listen(seen.add);
      await pumpEventQueue();
      await db.settingsDao.setBool('lite', true);
      await pumpEventQueue();
      await db.settingsDao.setString('other', 'x');
      await pumpEventQueue();
      await db.settingsDao.setBool('lite', false);
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [null, true, false]);
    });
  });

  group('secrets', () {
    Future<void> exercise(SecretStore store, int a, int b) async {
      expect(await store.read(a, SecretNames.password), isNull);
      await store.write(a, SecretNames.password, 'one');
      await store.write(a, SecretNames.password, 'two');
      await store.write(a, SecretNames.url, 'http://127.0.0.1/get.php?x=1');
      await store.write(b, SecretNames.password, 'other');
      expect(await store.read(a, SecretNames.password), 'two');
      expect(
        await store.read(a, SecretNames.url),
        'http://127.0.0.1/get.php?x=1',
      );
      await store.deleteAll(a);
      expect(await store.read(a, SecretNames.password), isNull);
      expect(await store.read(a, SecretNames.url), isNull);
      expect(await store.read(b, SecretNames.password), 'other');
    }

    test('database store', () async {
      final a = await addSource(db);
      final b = await addSource(db);
      await exercise(DbSecretStore(db), a, b);
    });

    test('in-memory store', () async {
      await exercise(InMemorySecretStore(), 1, 2);
    });

    test('database secrets go away with their source', () async {
      final a = await addSource(db);
      final store = DbSecretStore(db);
      await store.write(a, SecretNames.password, 'pw');
      await db.sourcesDao.deleteSource(a);
      expect(await store.read(a, SecretNames.password), isNull);
      expect(await countRows(db, 'secrets'), 0);
    });

    test('database secrets need an existing source', () async {
      await expectLater(
        DbSecretStore(db).write(404, SecretNames.password, 'pw'),
        throwsA(anything),
      );
    });
  });
}
