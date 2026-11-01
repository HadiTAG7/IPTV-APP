// The REST client against a local server that stands in for the Google
// endpoints. No request leaves the machine; all data is synthetic.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/account/account_controller.dart';
import 'package:iptv_player/account/firebase_api.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/sources/models.dart';

import '../support/real_http.dart';
import '../unit/db/db_test_utils.dart';

typedef Handler = Future<void> Function(HttpRequest request);

class MemoryVault implements SessionVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? value) async => this.value = value;
}

/// Serves `/<google host>/<path>`; [FirebaseAccountApi.dio] is pointed at
/// it and refuses every other host.
class LocalGoogle {
  late final HttpServer server;
  final handlers = <String, Handler>{};

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final handler = handlers[request.uri.pathSegments.first];
      if (handler == null) {
        request.response.statusCode = 500;
        await request.response.close();
      } else {
        await handler(request);
      }
    });
  }

  void attach(FirebaseAccountApi api) {
    api.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final uri = Uri.parse(options.path);
          if (!uri.host.endsWith('.googleapis.com')) {
            return handler.reject(
              DioException(requestOptions: options, error: 'blocked'),
            );
          }
          options.path =
              'http://127.0.0.1:${server.port}/${uri.host}${uri.path}';
          handler.next(options);
        },
      ),
    );
  }
}

Future<void> reply(HttpRequest request, int status, Object body) async {
  await utf8.decoder.bind(request).join();
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await request.response.close();
}

void main() {
  useRealHttp();
  late LocalGoogle google;
  late FirebaseAccountApi api;
  late AppDatabase db;

  setUp(() async {
    google = LocalGoogle();
    await google.start();
    api = FirebaseAccountApi(projectId: 'synthetic', apiKey: 'synthetic-key');
    google.attach(api);
    db = openTestDb();
  });
  tearDown(() async {
    api.dio.close(force: true);
    await google.server.close(force: true);
    await db.close();
  });

  String session({required bool expired}) => jsonEncode(
    AccountSession(
      uid: 'owner',
      email: 'owner@example.test',
      idToken: 'old-id',
      refreshToken: 'old-refresh',
      expiresAt: DateTime.now().add(
        expired ? const Duration(minutes: -5) : const Duration(hours: 1),
      ),
    ).toJson(),
  );

  /// An empty account: no state document, no records, commits accepted
  /// for [token] only.
  void firestore({required String token}) {
    google.handlers['firestore.googleapis.com'] = (request) async {
      if (request.headers.value('authorization') != 'Bearer $token') {
        return reply(request, 401, {
          'error': {
            'code': 401,
            'message': 'Request had invalid authentication credentials.',
            'status': 'UNAUTHENTICATED',
          },
        });
      }
      if (request.method == 'POST') {
        return reply(request, 200, {
          'writeResults': [
            {'updateTime': '2026-11-01T00:00:00.000001Z'},
          ],
        });
      }
      if (request.uri.path.endsWith('/sync/state')) {
        return reply(request, 404, {
          'error': {'code': 404, 'status': 'NOT_FOUND'},
        });
      }
      return reply(request, 200, {});
    };
  }

  for (final body in [
    {
      'error': {
        'code': 400,
        'message': 'TOKEN_EXPIRED',
        'status': 'INVALID_ARGUMENT',
      },
    },
    {
      'error': {'code': 400, 'message': 'INVALID_REFRESH_TOKEN'},
    },
  ]) {
    test('a revoked sign-in (${(body['error']!)['message']}) asks to sign in '
        'again and keeps the device data', () async {
      await db.settingsDao.setString(AccountController.bindingKey, 'owner');
      final id = await db.sourcesDao.create(
        const SourceConfig(
          kind: SourceKind.m3uUrl,
          url: 'http://127.0.0.1:9/list.m3u',
          name: 'Home',
        ),
      );
      var refreshes = 0;
      google.handlers['securetoken.googleapis.com'] = (request) {
        refreshes++;
        return reply(request, 400, body);
      };
      final vault = MemoryVault()..value = session(expired: true);
      final c = AccountController(db: db, api: api, vault: vault);
      addTearDown(c.dispose);
      await c.start();
      expect(c.view.email, isNull);
      expect(c.view.error, 'SESSION_EXPIRED');
      expect(vault.value, isNull);
      // No retries with the dead token, and the device stays bound.
      await c.sync(force: true);
      expect(refreshes, 1);
      expect(
        await db.settingsDao.getString(AccountController.bindingKey),
        'owner',
      );
      expect(await db.sourcesDao.configFor(id), isNotNull);
    });
  }

  test('a refused ID token is refreshed once before sync goes on', () async {
    await db.settingsDao.setString(AccountController.bindingKey, 'owner');
    var refreshes = 0;
    google.handlers['securetoken.googleapis.com'] = (request) {
      refreshes++;
      return reply(request, 200, {
        'user_id': 'owner',
        'id_token': 'new-id',
        'refresh_token': 'new-refresh',
        'expires_in': '3600',
      });
    };
    firestore(token: 'new-id');
    final vault = MemoryVault()..value = session(expired: false);
    final c = AccountController(db: db, api: api, vault: vault);
    addTearDown(c.dispose);
    await c.start();
    expect(c.view.error, isNull);
    expect(c.view.email, 'owner@example.test');
    expect(refreshes, 1);
    expect(vault.value, contains('new-refresh'));
  });

  test('a token Firestore keeps refusing ends the sign-in', () async {
    await db.settingsDao.setString(AccountController.bindingKey, 'owner');
    google.handlers['securetoken.googleapis.com'] = (request) =>
        reply(request, 200, {
          'user_id': 'owner',
          'id_token': 'new-id',
          'refresh_token': 'new-refresh',
          'expires_in': '3600',
        });
    firestore(token: 'never-accepted');
    final vault = MemoryVault()..value = session(expired: false);
    final c = AccountController(db: db, api: api, vault: vault);
    addTearDown(c.dispose);
    await c.start();
    expect(c.view.error, 'SESSION_EXPIRED');
    expect(c.view.email, isNull);
    expect(vault.value, isNull);
  });

  test('auth replies keep their specific reason', () async {
    Future<String?> codeFor(Map<String, Object?> error) async {
      google.handlers['identitytoolkit.googleapis.com'] = (request) =>
          reply(request, 400, {'error': error});
      try {
        await api.signIn('owner@example.test', 'synthetic-pass');
      } on AccountException catch (e) {
        return e.code;
      }
      return null;
    }

    expect(
      await codeFor({
        'code': 400,
        'message':
            'TOO_MANY_ATTEMPTS_TRY_LATER : Access to this account has been '
            'temporarily disabled.',
      }),
      'TOO_MANY_ATTEMPTS_TRY_LATER',
    );
    expect(
      await codeFor({'code': 400, 'message': 'INVALID_LOGIN_CREDENTIALS'}),
      'INVALID_LOGIN_CREDENTIALS',
    );
    expect(
      await codeFor({
        'code': 400,
        'message': 'the stored version does not match the required version',
        'status': 'FAILED_PRECONDITION',
      }),
      'CONFLICT',
    );
    expect(
      await codeFor({
        'code': 403,
        'message': 'Missing or insufficient permissions.',
        'status': 'PERMISSION_DENIED',
      }),
      'PERMISSION_DENIED',
    );
  });
}
