@Timeout(Duration(seconds: 60))
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:iptv_player/app/home_shell.dart' show describeSourceError;
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/core/secure/secret_store.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/sources/source_repository.dart';

import '../../support/fake_panel.dart';
import '../../support/real_http.dart';
import '../../unit/db/db_test_utils.dart';

const _user = 'tvUser';
const _pass = 'S3cret-Pw!';

void main() {
  useRealHttp();

  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));
  late FakePanel panel;
  late AppDatabase db;
  late SourceRepository repo;
  late RingLog log;

  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });

  setUp(() async {
    panel = await FakePanel.start(
      username: _user,
      password: _pass,
      mediaDir: null,
      liveCount: 5,
      vodCount: 2,
      seriesCount: 1,
    );
    db = openTestDb();
    log = RingLog();
    repo = SourceRepository(db, DbSecretStore(db), log: log);
  });

  tearDown(() async {
    await panel.close();
    await db.close();
  });

  SourceConfig xtream({String password = _pass}) => SourceConfig(
    kind: SourceKind.xtream,
    url: panel.baseUrl,
    username: _user,
    password: password,
  );

  /// The message in both languages; neither ever shows the password.
  (String, String) messages(VerifyResult result) {
    expect(result, isA<VerifyError>());
    final error = result as VerifyError;
    final pair = (
      describeSourceError(en, error),
      describeSourceError(ar, error),
    );
    for (final m in [pair.$1, pair.$2, error.message, '$error']) {
      expect(m, isNot(contains(_pass)));
    }
    return pair;
  }

  test('a good login verifies', () async {
    final result = await repo.verify(xtream());
    expect(result, isA<VerifyOk>());
    expect((result as VerifyOk).account.status, AccountStatus.active);
  });

  test('expired shows the expiry date', () async {
    panel.auth = FakeAuthMode.expired;
    final result = await repo.verify(xtream());
    final error = result as VerifyError;
    expect(error.reason, VerifyErrorReason.expired);
    final date = error.expiresAt!;
    final (enText, arText) = messages(result);
    expect(enText, en.errorExpired(date.toLocal()));
    expect(enText, startsWith('This subscription expired on '));
    expect(enText, contains('${date.toLocal().year}'));
    expect(arText, ar.errorExpired(date.toLocal()));
    expect(arText, startsWith('انتهى هذا الاشتراك بتاريخ'));
  });

  test('banned and disabled', () async {
    panel.auth = FakeAuthMode.banned;
    expect(messages(await repo.verify(xtream())), (
      en.errorBanned,
      ar.errorBanned,
    ));
    panel.auth = FakeAuthMode.disabled;
    expect(messages(await repo.verify(xtream())), (
      en.errorDisabled,
      ar.errorDisabled,
    ));
  });

  test('auth 0 with HTTP 200, an empty array and a wrong password', () async {
    for (final mode in [
      FakeAuthMode.auth0WithHttp200,
      FakeAuthMode.emptyArray,
    ]) {
      panel.auth = mode;
      expect(messages(await repo.verify(xtream())), (
        en.errorAuthFailed,
        ar.errorAuthFailed,
      ), reason: '$mode');
    }
    panel.auth = FakeAuthMode.good;
    const wrong = 'Wrong-Pw-123';
    final result = await repo.verify(xtream(password: wrong));
    final (enText, arText) = messages(result);
    expect(enText, en.errorAuthFailed);
    expect(arText, ar.errorAuthFailed);
    expect('$result', isNot(contains(wrong)));
    expect(log.dump(), isNot(contains(wrong)));
  });

  test('an M3U get.php link: offered as Xtream, and checked as M3U', () async {
    final url = panel.m3uUrl(output: 'm3u8');
    final link = repo.detectXtreamLink(url)!;
    expect(link.base, panel.baseUrl);
    expect(link.username, _user);
    expect(link.password, _pass);
    expect(link.liveFormat, LiveFormat.m3u8);
    expect('$link', isNot(contains(_pass)));

    final ok = await repo.verify(
      SourceConfig(kind: SourceKind.m3uUrl, url: url),
    );
    expect(ok, isA<VerifyOk>());

    // The converted source logs in too.
    expect(await repo.verify(link.toSourceConfig()), isA<VerifyOk>());

    // An expired panel refuses get.php with 403: a login failure.
    panel.auth = FakeAuthMode.expired;
    final refused = await repo.verify(
      SourceConfig(kind: SourceKind.m3uUrl, url: url),
    );
    final (enText, arText) = messages(refused);
    expect(enText, en.errorAuthFailed);
    expect(arText, ar.errorAuthFailed);
  });

  test('unreachable, invalid and not-a-playlist', () async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    expect(
      messages(
        await repo.verify(
          SourceConfig(
            kind: SourceKind.m3uUrl,
            url: 'http://127.0.0.1:$port/list.m3u',
          ),
        ),
      ),
      (en.errorUnreachable, ar.errorUnreachable),
    );
    expect(
      messages(
        await repo.verify(
          const SourceConfig(kind: SourceKind.m3uUrl, url: 'example.com/a'),
        ),
      ),
      (en.errorInvalidUrl, ar.errorInvalidUrl),
    );
    expect(
      messages(
        await repo.verify(
          SourceConfig(kind: SourceKind.m3uUrl, url: panel.plainEpgUrl),
        ),
      ),
      (en.errorNotM3u, ar.errorNotM3u),
    );
  });
}
