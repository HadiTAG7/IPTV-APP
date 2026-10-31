// One HTTP implementation on Android/TV and Windows: no desktop Firebase SDK.
import 'dart:convert';

import 'package:dio/dio.dart';

import 'sync_model.dart';

class AccountException implements Exception {
  const AccountException(this.code);
  final String code;
  @override
  String toString() => 'AccountException($code)';
}

class AccountSession {
  const AccountSession({
    required this.uid,
    required this.email,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
  });
  final String uid;
  final String email;
  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => {
    'uid': uid,
    'email': email,
    'idToken': idToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  factory AccountSession.fromJson(Map<String, dynamic> json) => AccountSession(
    uid: json['uid'] as String,
    email: json['email'] as String,
    idToken: json['idToken'] as String,
    refreshToken: json['refreshToken'] as String,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );
}

class RemoteState {
  const RemoteState(this.data, this.version, {this.deletedKeys = const {}});
  final SyncData data;
  final String? version;
  final Set<String> deletedKeys;
}

class FirebaseAccountApi {
  FirebaseAccountApi({required this.projectId, required this.apiKey, Dio? dio})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 45),
              sendTimeout: const Duration(seconds: 45),
            ),
          );
  final String projectId;
  final String apiKey;
  final Dio dio;
  String get _root => 'projects/$projectId/databases/(default)/documents';
  String get _base => 'https://firestore.googleapis.com/v1/$_root';

  Future<Map<String, dynamic>> _request(
    String method,
    String url, {
    Object? data,
    Map<String, dynamic>? query,
    String? token,
    String? contentType,
  }) async {
    try {
      final response = await dio.request<Map<String, dynamic>>(
        url,
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          contentType: contentType,
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );
      return response.data ?? {};
    } on DioException catch (error) {
      // Never propagate request objects: they contain passwords/tokens/URLs.
      final body = error.response?.data;
      final detail = body is Map ? body['error'] : null;
      final code = detail is Map
          ? (detail['status'] ?? detail['message'])
                ?.toString()
                .split(' : ')
                .first
          : null;
      if (error.response?.statusCode == 404) {
        throw const AccountException('NOT_FOUND');
      }
      if (error.response?.statusCode == 409 ||
          error.response?.statusCode == 412 ||
          code == 'FAILED_PRECONDITION' ||
          code == 'ABORTED') {
        throw const AccountException('CONFLICT');
      }
      throw AccountException(code?.split(':').first ?? 'NETWORK_ERROR');
    }
  }

  Future<AccountSession> signIn(
    String email,
    String password, {
    bool create = false,
  }) async {
    final data = await _request(
      'POST',
      'https://identitytoolkit.googleapis.com/v1/accounts:${create ? 'signUp' : 'signInWithPassword'}',
      query: {'key': apiKey},
      data: {
        'email': email.trim(),
        'password': password,
        'returnSecureToken': true,
      },
    );
    return AccountSession(
      uid: data['localId'] as String,
      email: data['email'] as String,
      idToken: data['idToken'] as String,
      refreshToken: data['refreshToken'] as String,
      expiresAt: DateTime.now().add(
        Duration(seconds: int.parse(data['expiresIn'].toString())),
      ),
    );
  }

  Future<AccountSession> refresh(AccountSession session) async {
    final data = await _request(
      'POST',
      'https://securetoken.googleapis.com/v1/token',
      contentType: Headers.formUrlEncodedContentType,
      query: {'key': apiKey},
      data: {
        'grant_type': 'refresh_token',
        'refresh_token': session.refreshToken,
      },
    );
    return AccountSession(
      uid: data['user_id'] as String,
      email: session.email,
      idToken: data['id_token'] as String,
      refreshToken: data['refresh_token'] as String,
      expiresAt: DateTime.now().add(
        Duration(seconds: int.parse(data['expires_in'].toString())),
      ),
    );
  }

  Future<void> resetPassword(String email) async {
    await _request(
      'POST',
      'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode',
      query: {'key': apiKey},
      data: {'requestType': 'PASSWORD_RESET', 'email': email.trim()},
    );
  }

  Future<String?> revision(AccountSession session) async {
    try {
      final data = await _request(
        'GET',
        '$_base/users/${session.uid}/sync/state',
        token: session.idToken,
      );
      return data['updateTime'] as String?;
    } on AccountException catch (e) {
      if (e.code == 'NOT_FOUND') return null;
      rethrow;
    }
  }

  Future<RemoteState> read(AccountSession session) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      final before = await revision(session);
      final records = <String, Map<String, Object?>>{};
      final deleted = <String>{};
      String? page;
      do {
        final result = await _request(
          'GET',
          '$_base/users/${session.uid}/records',
          token: session.idToken,
          query: {'pageSize': 500, 'pageToken': ?page},
        );
        for (final doc in (result['documents'] as List? ?? const [])) {
          final fields = doc['fields'] as Map;
          final key = fields['key']['stringValue'] as String;
          if (fields['deleted']['booleanValue'] != true) {
            records[key] = Map<String, Object?>.from(
              jsonDecode(fields['json']['stringValue'] as String) as Map,
            );
          } else {
            deleted.add(key);
          }
        }
        page = result['nextPageToken'] as String?;
      } while (page != null && page.isNotEmpty);
      final after = await revision(session);
      if (before == after) {
        return RemoteState(records, after, deletedKeys: deleted);
      }
    }
    throw const AccountException('CONFLICT');
  }

  /// Every batch updates the revision with a precondition. A competing
  /// device causes a re-read/merge; no device can silently overwrite a read.
  Future<String?> write(
    AccountSession session,
    RemoteState remote,
    Map<String, Map<String, Object?>?> changes,
  ) async {
    var version = remote.version;
    final entries = changes.entries.toList();
    var offset = 0;
    while (offset < entries.length) {
      final writes = <Map<String, Object?>>[];
      var bytes = 0;
      while (offset < entries.length &&
          writes.length < 350 &&
          bytes < 5000000) {
        final e = entries[offset++];
        final payload = jsonEncode(e.value);
        if (utf8.encode(payload).length > 850000) {
          throw const AccountException('RECORD_TOO_LARGE');
        }
        bytes += utf8.encode(payload).length + 1000;
        writes.add({
          'update': {
            'name': '$_root/users/${session.uid}/records/${syncId(e.key)}',
            'fields': {
              'key': {'stringValue': e.key},
              'json': {'stringValue': payload},
              'deleted': {'booleanValue': e.value == null},
            },
          },
        });
      }
      writes.add({
        'update': {
          'name': '$_root/users/${session.uid}/sync/state',
          'fields': {
            'schema': {'integerValue': '1'},
          },
        },
        'updateTransforms': [
          {'fieldPath': 'changedAt', 'setToServerValue': 'REQUEST_TIME'},
        ],
        'currentDocument': version == null
            ? {'exists': false}
            : {'updateTime': version},
      });
      final result = await _request(
        'POST',
        '$_base:commit',
        token: session.idToken,
        data: {'writes': writes},
      );
      version = (result['writeResults'] as List).last['updateTime'] as String;
    }
    return version;
  }
}
