// Migration tests in the shape `drift_dev make-migrations` generates. The
// loops cover every snapshot in drift_schemas/iptv/, so after a schema bump
// re-running make-migrations (which refreshes generated/) is enough to test
// the new step.
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/sources/models.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('latest snapshot matches the current schema', () async {
    final latest = GeneratedHelper.versions.last;
    final schema = await verifier.schemaAt(latest);
    final db = AppDatabase(schema.newConnection());
    expect(db.schemaVersion, latest);
    await verifier.migrateAndValidate(db, latest);
    await db.close();
  });

  test('a fresh install creates the expected schema', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.validateDatabaseSchema();
    await db.close();
  });

  group('simple database migrations', () {
    // Verifies every schema upgrade with an empty database.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  group('v1 to v2', () {
    test(
      'keeps sources, channels and favourites; adds channel lists',
      () async {
        final schema = await verifier.schemaAt(1);
        final old = v1.DatabaseAtV1(schema.newConnection());
        final sourceId = await old
            .into(old.sources)
            .insert(
              v1.SourcesCompanion.insert(
                name: 'Home',
                kind: SourceKind.m3uUrl.name,
                url: 'http://127.0.0.1:9/list.m3u',
                generation: const Value(1),
                lastGeneration: const Value(1),
              ),
            );
        await old
            .into(old.channels)
            .insert(
              v1.ChannelsCompanion.insert(
                sourceId: sourceId,
                key: 'k1',
                name: 'Channel 1',
                nameNorm: 'channel 1',
                url: const Value('http://127.0.0.1:9/live/1.ts'),
                generation: 1,
                firstGen: 1,
              ),
            );
        for (final (i, key) in ['k1', 'gone'].indexed) {
          await old
              .into(old.favorites)
              .insert(
                v1.FavoritesCompanion.insert(
                  sourceId: sourceId,
                  kind: ContentKind.live.name,
                  key: key,
                  addedAt: 1700000000 + i,
                  position: i,
                ),
              );
        }
        await old.close();

        final db = AppDatabase(schema.newConnection());
        await verifier.migrateAndValidate(db, 2);
        final sources = await db.sourcesDao.all();
        expect(sources.map((s) => (s.id, s.name)), [(sourceId, 'Home')]);
        expect(await db.favoritesDao.favoriteKeys(sourceId, ContentKind.live), [
          'k1',
          'gone',
        ]);
        expect(
          (await db.catalogDao.channelByKey(sourceId, 'k1'))?.name,
          'Channel 1',
        );

        // The new tables work, foreign keys included.
        final dao = db.channelListsDao;
        expect(await dao.lists(sourceId), isEmpty);
        final sports = await dao.createList(sourceId, 'Sports');
        await dao.setChannel(sports, 'k1', true);
        final page = await dao.channelsPage(sports);
        expect(page.single.item?.name, 'Channel 1');
        await db.sourcesDao.deleteSource(sourceId);
        expect(await dao.listById(sports), isNull);
        expect(await dao.channelKeys(sports), isEmpty);
        await db.close();
      },
    );
  });
}
