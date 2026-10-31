@Tags(['network'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/account/account_controller.dart';
import 'package:iptv_player/account/firebase_api.dart';
import 'package:iptv_player/account/firebase_config.dart';
import 'package:iptv_player/account/sync_model.dart';
import 'package:iptv_player/sources/models.dart';

import '../support/real_http.dart';
import '../unit/db/db_test_utils.dart';

class _Vault implements SessionVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? value) async => this.value = value;
}

void main() {
  useRealHttp();
  test(
    'live Firebase: login, token refresh, two-device sync, conflict and account isolation',
    () async {
      final api = FirebaseAccountApi(
        projectId: FirebaseConfig.projectId,
        apiKey: FirebaseConfig.apiKey,
      );
      final unique = DateTime.now().microsecondsSinceEpoch;
      final password = base64UrlEncode(
        List.generate(32, (_) => Random.secure().nextInt(256)),
      );
      final email = 'iptv-qa-$unique@example.test';
      final sessions = <AccountSession>[];
      final phone = openTestDb();
      final tv = openTestDb();
      final a = AccountController(db: phone, api: api, vault: _Vault());
      final b = AccountController(db: tv, api: api, vault: _Vault());
      try {
        final owner = await api.signIn(email, password, create: true);
        sessions.add(owner);
        final stranger = await api.signIn(
          'iptv-qa-other-$unique@example.test',
          password,
          create: true,
        );
        sessions.add(stranger);
        await File('${Directory.systemTemp.path}/iptv-firebase-qa-users.json')
            .writeAsString(
              jsonEncode({
                'project': FirebaseConfig.projectId,
                'uids': sessions.map((s) => s.uid).toList(),
              }),
            );
        final refreshed = await api.refresh(owner);
        expect(refreshed.uid, owner.uid);
        final source = await phone.sourcesDao.create(
          const SourceConfig(
            kind: SourceKind.xtream,
            name: 'Synthetic QA',
            url: 'https://synthetic.example.test',
            username: 'qa',
            password: 'synthetic-only',
          ),
        );
        await phone.channelListsDao.createList(
          source,
          'QA list',
          channels: ['two', 'one'],
        );
        await phone.favoritesDao.setFavorite(
          source,
          ContentKind.live,
          'one',
          true,
        );
        await phone.progressDao.saveProgress(
          source,
          PlayableKind.movie,
          'film',
          50000,
          1000000,
        );
        await a.authenticate(email, password);
        expect(a.view.error, isNull);
        await b.authenticate(email, password);
        expect(b.view.error, isNull);
        final remoteSource = (await tv.sourcesDao.all()).single.id;
        expect(
          (await tv.sourcesDao.configFor(remoteSource))!.password,
          'synthetic-only',
        );
        expect(
          await tv.channelListsDao.channelKeys(
            (await tv.channelListsDao.lists(remoteSource)).single.id,
          ),
          ['two', 'one'],
        );
        await tv.favoritesDao.setFavorite(
          remoteSource,
          ContentKind.live,
          'two',
          true,
        );
        await b.sync();
        await a.sync();
        expect(a.view.error, isNull);
        expect(b.view.error, isNull);
        expect(
          (await phone.favoritesDao.favoriteKeys(
            source,
            ContentKind.live,
          )).toSet(),
          {'one', 'two'},
        );
        final old = await api.read(owner);
        await api.write(owner, old, {
          'qa-probe': {'type': 'probe', 'value': 1},
        });
        await expectLater(
          api.write(owner, old, {
            'qa-probe': {'type': 'probe', 'value': 2},
          }),
          throwsA(
            isA<AccountException>().having((e) => e.code, 'code', 'CONFLICT'),
          ),
        );
        final forged = AccountSession(
          uid: owner.uid,
          email: stranger.email,
          idToken: stranger.idToken,
          refreshToken: stranger.refreshToken,
          expiresAt: stranger.expiresAt,
        );
        await expectLater(
          api.read(forged),
          throwsA(
            isA<AccountException>().having(
              (e) => e.code,
              'code',
              'PERMISSION_DENIED',
            ),
          ),
        );
        final anonymous = AccountSession(
          uid: owner.uid,
          email: '',
          idToken: '',
          refreshToken: '',
          expiresAt: owner.expiresAt,
        );
        await expectLater(
          api.read(anonymous),
          throwsA(isA<AccountException>()),
        );
        final current = await api.read(owner);
        expect(current.data.values.any((r) => r['type'] == 'favorite'), true);
        expect(syncChanges(current.data, current.data), isEmpty);
      } finally {
        a.dispose();
        b.dispose();
        await phone.close();
        await tv.close();
        for (final session in sessions) {
          await api.dio.post(
            'https://identitytoolkit.googleapis.com/v1/accounts:delete',
            queryParameters: {'key': FirebaseConfig.apiKey},
            data: {'idToken': session.idToken},
          );
        }
        api.dio.close();
      }
    },
    skip: Platform.environment['IPTV_FIREBASE_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
