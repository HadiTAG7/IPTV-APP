@Timeout(Duration(seconds: 60))
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/core/secure/secret_store.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/sources/m3u/m3u_adapter.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/sources/source_repository.dart';
import 'package:iptv_player/sources/xtream/xtream_adapter.dart';

import '../../support/fake_panel.dart';
import '../../support/real_http.dart';
import '../db/db_test_utils.dart';

const _user = 'demoUser';
const _pass = 'Pw-7x9Secret';

void main() {
  useRealHttp();

  late FakePanel panel;
  late AppDatabase db;
  late SourceRepository repo;
  late Directory support;
  late RingLog log;

  setUp(() async {
    panel = await FakePanel.start(
      username: _user,
      password: _pass,
      mediaDir: null,
      liveCount: 12,
      vodCount: 6,
      seriesCount: 3,
    );
    db = openTestDb();
    support = await Directory.systemTemp.createTemp('repo_test');
    log = RingLog();
    repo = SourceRepository(
      db,
      DbSecretStore(db),
      appSupportDir: () async => support.path,
      clock: FakeClock(DateTime.now().toUtc()),
      log: log,
    );
  });

  tearDown(() async {
    await panel.close();
    await db.close();
    if (support.existsSync()) await support.delete(recursive: true);
  });

  SourceConfig xtream({String? password, String? username, String? url}) =>
      SourceConfig(
        kind: SourceKind.xtream,
        url: url ?? panel.baseUrl,
        name: 'Panel',
        username: username ?? _user,
        password: password ?? _pass,
      );

  /// Every text column of the source's `sources` row, joined.
  Future<String> sourcesRowText(int id) async {
    final row = await db
        .customSelect(
          'SELECT * FROM sources WHERE id = ?',
          variables: [Variable.withInt(id)],
        )
        .getSingle();
    return row.data.values.join('|');
  }

  group('verify', () {
    test('a good Xtream login returns the account', () async {
      final result = await repo.verify(xtream());
      expect(result, isA<VerifyOk>());
      final account = (result as VerifyOk).account;
      expect(account.status, AccountStatus.active);
      expect(account.expiresAt!.isAfter(DateTime.now()), isTrue);
      expect(account.maxConnections, 1);
      expect(account.allowedFormats, containsAll(['ts', 'm3u8']));
    });

    test('expired, banned and disabled accounts are typed errors', () async {
      panel.auth = FakeAuthMode.expired;
      final result = await repo.verify(xtream());
      expect(result, isA<VerifyError>());
      var error = result as VerifyError;
      expect(error.reason, VerifyErrorReason.expired);
      expect(error.expiresAt!.isBefore(DateTime.now()), isTrue);

      panel.auth = FakeAuthMode.banned;
      error = await repo.verify(xtream()) as VerifyError;
      expect(error.reason, VerifyErrorReason.banned);

      panel.auth = FakeAuthMode.disabled;
      error = await repo.verify(xtream()) as VerifyError;
      expect(error.reason, VerifyErrorReason.disabled);
    });

    test('auth 0, an empty array and a wrong password fail auth', () async {
      for (final mode in [
        FakeAuthMode.auth0WithHttp200,
        FakeAuthMode.emptyArray,
      ]) {
        panel.auth = mode;
        final error = await repo.verify(xtream()) as VerifyError;
        expect(error.reason, VerifyErrorReason.authFailed, reason: '$mode');
      }
      panel.auth = FakeAuthMode.good;
      final error =
          await repo.verify(xtream(password: 'wrong-pw')) as VerifyError;
      expect(error.reason, VerifyErrorReason.authFailed);
      expect(error.message, isNot(contains('wrong-pw')));
      expect(log.dump(), isNot(contains('wrong-pw')));
    });

    test('invalid addresses never touch the network', () async {
      for (final url in ['http://', 'ftp://example.com', 'http://bad host']) {
        final error = await repo.verify(xtream(url: url)) as VerifyError;
        expect(error.reason, VerifyErrorReason.invalidUrl, reason: url);
      }
      for (final url in ['', 'example.com/list.m3u', 'ftp://h/x.m3u']) {
        final error = await repo.verify(
          SourceConfig(kind: SourceKind.m3uUrl, url: url),
        ) as VerifyError;
        expect(error.reason, VerifyErrorReason.invalidUrl, reason: url);
      }
      final missing = await repo.verify(xtream(username: '')) as VerifyError;
      expect(missing.reason, VerifyErrorReason.authFailed);
      expect(panel.stats.requestsWithPrefix('/'), 0);
    });

    test('an unreachable server', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      final error = await repo.verify(
        xtream(url: 'http://127.0.0.1:$port'),
      ) as VerifyError;
      expect(error.reason, VerifyErrorReason.unreachable);
      expect(error.message, isNot(contains(_pass)));
    });

    test('M3U: the panel get.php playlist verifies', () async {
      final result = await repo.verify(
        SourceConfig(kind: SourceKind.m3uUrl, url: panel.m3uUrl()),
      );
      expect(result, isA<VerifyOk>());
    });

    test('M3U: a JSON body is not a playlist; HTTP errors are typed', () async {
      var error = await repo.verify(
        SourceConfig(kind: SourceKind.m3uUrl, url: panel.playerApiUrl()),
      ) as VerifyError;
      expect(error.reason, VerifyErrorReason.notM3u);

      error = await repo.verify(
        SourceConfig(
          kind: SourceKind.m3uUrl,
          url: '${panel.baseUrl}/missing.m3u',
        ),
      ) as VerifyError;
      expect(error.reason, VerifyErrorReason.unreachable);
      expect(error.statusCode, 404);

      panel.auth = FakeAuthMode.banned; // get.php answers 403
      error = await repo.verify(
        SourceConfig(kind: SourceKind.m3uUrl, url: panel.m3uUrl()),
      ) as VerifyError;
      expect(error.reason, VerifyErrorReason.authFailed);
    });

    test('M3U file: missing and valid copies', () async {
      var error = await repo.verify(
        SourceConfig(kind: SourceKind.m3uFile, url: '${support.path}/nope.m3u'),
      ) as VerifyError;
      expect(error.reason, VerifyErrorReason.fileUnreadable);

      final picked = File('${support.path}/picked.m3u')
        ..writeAsStringSync(
          '#EXTM3U\n#EXTINF:-1 group-title="News",One\n'
          'http://127.0.0.1:9/one.ts\n',
        );
      final copy = await repo.importM3uFile(picked.path);
      expect(
        copy,
        matches(
          RegExp(
            '^${RegExp.escape(support.path)}/sources/'
            r'[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
            r'[0-9a-f]{12}\.m3u$',
          ),
        ),
      );
      expect(File(copy).readAsStringSync(), picked.readAsStringSync());
      final result = await repo.verify(
        SourceConfig(kind: SourceKind.m3uFile, url: copy),
      );
      expect(result, isA<VerifyOk>());

      File(copy).writeAsStringSync('<html>nope</html>');
      error = await repo.verify(
        SourceConfig(kind: SourceKind.m3uFile, url: copy),
      ) as VerifyError;
      expect(error.reason, VerifyErrorReason.notM3u);
    });
  });

  group('add', () {
    test('Xtream: the password lives only in the secret store', () async {
      final id = await repo.add(
        xtream(url: '  ${panel.baseUrl}/player_api.php?username=x  '),
      );
      final row = (await repo.byId(id))!;
      expect(row.kind, SourceKind.xtream);
      expect(row.url, panel.baseUrl);
      expect(row.username, _user);
      expect(await sourcesRowText(id), isNot(contains(_pass)));
      expect(await DbSecretStore(db).read(id, SecretNames.password), _pass);

      final config = await repo.configFor(id);
      expect(config.password, _pass);
      expect(config.url, panel.baseUrl);
      final adapter = repo.adapterFor(config);
      expect(adapter, isA<XtreamAdapter>());
      adapter.close();
      expect(() => repo.configFor(id + 99), throwsStateError);
    });

    test('M3U get.php URL: stored masked, full URL in secrets', () async {
      final url = panel.m3uUrl();
      final link = repo.detectXtreamLink(url)!;
      expect(link.base, panel.baseUrl);
      expect(link.username, _user);
      expect(link.password, _pass);
      expect(repo.detectXtreamLink('http://h/list.m3u'), isNull);

      final id = await repo.add(
        SourceConfig(kind: SourceKind.m3uUrl, url: url),
      );
      final row = (await repo.byId(id))!;
      expect(row.name, '127.0.0.1');
      expect(row.url, contains('password=***'));
      final text = await sourcesRowText(id);
      expect(text, isNot(contains(_pass)));
      expect(text, isNot(contains(_user)));
      expect(await DbSecretStore(db).read(id, SecretNames.url), url);
      expect((await repo.configFor(id)).url, url);
      final adapter = await repo.adapterForSource(id);
      expect(adapter, isA<M3uAdapter>());
      adapter.close();

      // Saving the masked URL unchanged keeps the secret one.
      await repo.update(id, row.toConfig().copyWith(name: 'Renamed'));
      expect((await repo.configFor(id)).url, url);
      expect((await repo.byId(id))!.name, 'Renamed');
    });

    test('a plain playlist URL has no secret', () async {
      final id = await repo.add(
        const SourceConfig(
          kind: SourceKind.m3uUrl,
          url: 'http://127.0.0.1:9/list.m3u',
          name: 'Plain',
          userAgent: '  ',
        ),
      );
      final row = (await repo.byId(id))!;
      expect(row.url, 'http://127.0.0.1:9/list.m3u');
      expect(row.userAgent, isNull);
      expect(await DbSecretStore(db).read(id, SecretNames.url), isNull);
      expect(await repo.list(), hasLength(1));
    });

    test('default names', () {
      expect(
        SourceRepository.defaultName(SourceKind.m3uFile, '/a/b/My List.m3u'),
        'My List',
      );
      expect(
        SourceRepository.defaultName(SourceKind.xtream, 'http://tv.example:80'),
        'tv.example',
      );
      expect(SourceRepository.defaultName(SourceKind.m3uUrl, ''), 'M3U');
    });
  });

  test('delete removes the source and everything that hangs off it', () async {
    final keep = await repo.add(xtream());
    final id = await repo.add(xtream());
    for (final sourceId in [keep, id]) {
      await syncCatalog(
        db,
        sourceId,
        categories: [category(ContentKind.live, 'news')],
        channels: [channel('c1'), channel('c2')],
        movies: [movie('m1')],
        seriesList: [series('s1')],
        episodes: [episode('s1', 'e1')],
      );
      await db.favoritesDao.toggleFavorite(sourceId, ContentKind.live, 'c1');
      await db.progressDao.saveProgress(
        sourceId,
        PlayableKind.movie,
        'm1',
        1000,
        9000,
      );
      await db.recentDao.markRecent(sourceId, 'c2');
      await db.prefsDao.setEngine(sourceId, 'c1', EngineKind.mpv);
      await db.epgDao.addEpgSource(
        sourceId,
        '${panel.baseUrl}/xmltv.php?username=$_user&password=$_pass',
        EpgOrigin.xtream,
      );
    }
    await db.sourcesDao.setActive(id);
    final picked = File('${support.path}/x.m3u')..writeAsStringSync('#EXTM3U');
    final fileId = await repo.add(
      SourceConfig(
        kind: SourceKind.m3uFile,
        url: await repo.importM3uFile(picked.path),
      ),
    );
    final copy = (await repo.configFor(fileId)).url;

    final deleted = <int>[];
    final hooked = SourceRepository(
      db,
      DbSecretStore(db),
      appSupportDir: () async => support.path,
      beforeDelete: (sourceId) async => deleted.add(sourceId),
    );
    await hooked.delete(id);
    await hooked.delete(fileId);
    expect(deleted, [id, fileId]);
    expect(File(copy).existsSync(), isFalse);
    expect(picked.existsSync(), isTrue);

    Future<int> count(String table) async =>
        (await db
                .customSelect(
                  'SELECT COUNT(*) AS n FROM $table WHERE source_id = ?',
                  variables: [Variable.withInt(id)],
                )
                .getSingle())
            .read<int>('n');
    for (final table in [
      'secrets',
      'categories',
      'category_items',
      'channels',
      'movies',
      'series',
      'episodes',
      'favorites',
      'watch_progress',
      'recent_channels',
      'channel_prefs',
      'epg_sources',
    ]) {
      expect(await count(table), 0, reason: table);
    }
    expect(await repo.byId(id), isNull);
    expect(await db.sourcesDao.activeSourceId(), isNull);
    // The other source is untouched.
    expect(await db.catalogDao.totalCount(keep, ContentKind.live), 2);
    expect(
      await db.favoritesDao.isFavorite(keep, ContentKind.live, 'c1'),
      isTrue,
    );
    expect(await DbSecretStore(db).read(keep, SecretNames.password), _pass);
    expect(await countRows(db, 'epg_sources'), 1);
  });
}
