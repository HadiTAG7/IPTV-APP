import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/net/http.dart';
import '../../core/net/redact.dart';
import '../../core/time/clock.dart';
import '../../epg/epg_models.dart';
import '../models.dart';
import 'coerce.dart';
import 'json_array_stream.dart';
import 'xtream_epg.dart';
import 'xtream_urls.dart';

/// Xtream Codes `player_api.php` client on top of dio.
///
/// Every error surfaces as a [SourceFailure] with credentials redacted. Large
/// lists are streamed object by object (see [jsonArrayStream]).
class XtreamClient {
  XtreamClient(this.urls, this.dio, {this.clock = const SystemClock()});

  final XtreamUrls urls;
  final Dio dio;
  final Clock clock;
  final _tokens = <CancelToken>{};
  var _closed = false;

  static final Converter<List<int>, Object?> _json = const Utf8Decoder(
    allowMalformed: true,
  ).fuse(const JsonDecoder());

  List<String> get _secrets => [urls.username, urls.password];

  /// Login check (`player_api.php` without an action).
  ///
  /// Throws [AuthFailure] for `[]`, `{}`, an empty body, a missing
  /// `user_info` or `auth != 1`, even with HTTP 200.
  Future<AccountInfo> authenticate() async =>
      parseAccountInfo(await _getJson(urls.playerApi()), now: clock.now());

  Future<List<Map<String, Object?>>> getLiveCategories() =>
      _getList('get_live_categories');

  Future<List<Map<String, Object?>>> getVodCategories() =>
      _getList('get_vod_categories');

  Future<List<Map<String, Object?>>> getSeriesCategories() =>
      _getList('get_series_categories');

  /// Streams `get_live_streams`, optionally for one category.
  ///
  /// With [idleTimeout], the request fails with [TimeoutFailure] (and is
  /// cancelled) when the headers or any next chunk take longer than that.
  Stream<Map<String, Object?>> getLiveStreams({
    String? categoryId,
    Duration? idleTimeout,
  }) => _stream('get_live_streams', categoryId, idleTimeout);

  Stream<Map<String, Object?>> getVodStreams({
    String? categoryId,
    Duration? idleTimeout,
  }) => _stream('get_vod_streams', categoryId, idleTimeout);

  /// Streams `get_series` (there is no `get_series_streams`).
  Stream<Map<String, Object?>> getSeries({
    String? categoryId,
    Duration? idleTimeout,
  }) => _stream('get_series', categoryId, idleTimeout);

  /// Raw `get_vod_info` (`info` + `movie_data`); `{}` when the panel has none.
  Future<Map<String, Object?>> getVodInfo(String vodId) async => asMap(
    await _getJson(
      urls.playerApi(action: 'get_vod_info', params: {'vod_id': vodId}),
    ),
  );

  /// Raw `get_series_info` (`seasons`, `info`, `episodes`).
  Future<Map<String, Object?>> getSeriesInfo(String seriesId) async => asMap(
    await _getJson(
      urls.playerApi(
        action: 'get_series_info',
        params: {'series_id': seriesId},
      ),
    ),
  );

  /// Now/next style listings for one stream.
  Future<List<EpgProgramme>> getShortEpg(String streamId, {int? limit}) async {
    final json = await _getJson(
      urls.playerApi(
        action: 'get_short_epg',
        params: {'stream_id': streamId, 'limit': ?limit?.toString()},
      ),
    );
    return parseShortEpg(json);
  }

  /// Cancels in-flight requests; later calls fail with [CancelledFailure].
  void close() {
    _closed = true;
    for (final token in _tokens.toList()) {
      _cancel(token);
    }
    _tokens.clear();
  }

  /// Maps a login response to [AccountInfo]. See [authenticate].
  static AccountInfo parseAccountInfo(Object? json, {required DateTime now}) {
    final user = asMap(asMap(json)['user_info']);
    if (user.isEmpty) {
      throw const AuthFailure('Login rejected: no account info');
    }
    final status = _status(asStr(user['status']));
    if (asInt(user['auth']) != 1) {
      throw AuthFailure(
        'Login rejected',
        status: status == AccountStatus.active ? AccountStatus.unknown : status,
      );
    }
    final expiresAt = asEpoch(user['exp_date']);
    final expired = expiresAt != null && expiresAt.isBefore(now.toUtc());
    return AccountInfo(
      status:
          expired &&
              (status == AccountStatus.active ||
                  status == AccountStatus.unknown)
          ? AccountStatus.expired
          : status,
      expiresAt: expiresAt,
      maxConnections: asInt(user['max_connections']),
      activeConnections: asInt(user['active_cons']),
      allowedFormats: [
        for (final f in asStrList(user['allowed_output_formats']))
          f.toLowerCase(),
      ],
      isTrial: asBool(user['is_trial']),
      serverTimezone: asStr(asMap(asMap(json)['server_info'])['timezone']),
    );
  }

  static AccountStatus _status(String? s) => switch (s?.toLowerCase()) {
    null || 'active' => AccountStatus.active,
    'expired' => AccountStatus.expired,
    'banned' => AccountStatus.banned,
    'disabled' => AccountStatus.disabled,
    _ => AccountStatus.unknown,
  };

  String _safe(Uri uri) => redact(uri.toString(), secrets: _secrets);

  static void _cancel(CancelToken token) {
    if (!token.isCancelled) token.cancel();
  }

  CancelToken _newToken() {
    if (_closed) throw const CancelledFailure();
    final token = CancelToken();
    _tokens.add(token);
    return token;
  }

  Future<List<Map<String, Object?>>> _getList(String action) async {
    final json = await _getJson(urls.playerApi(action: action));
    return [
      for (final e in asList(json))
        if (e is Map<String, Object?>) e,
    ];
  }

  Future<Object?> _getJson(Uri uri) async {
    final token = _newToken();
    try {
      final res = await dio.getUri<List<int>>(
        uri,
        options: Options(responseType: ResponseType.bytes),
        cancelToken: token,
      );
      return _decode(res.data ?? const []);
    } on FormatException {
      throw ParseFailure('Invalid JSON from ${_safe(uri)}');
    } catch (e) {
      throw mapDioError(e, secrets: _secrets);
    } finally {
      _tokens.remove(token);
    }
  }

  static Object? _decode(List<int> bytes) {
    var start = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      start = 3;
    }
    var blank = true;
    for (var i = start; i < bytes.length; i++) {
      final b = bytes[i];
      if (b != 0x20 && b != 0x0A && b != 0x0D && b != 0x09) {
        blank = false;
        break;
      }
    }
    if (blank) return null;
    return _json.convert(start == 0 ? bytes : bytes.sublist(start));
  }

  Stream<Map<String, Object?>> _stream(
    String action,
    String? categoryId,
    Duration? idleTimeout,
  ) async* {
    final uri = urls.playerApi(
      action: action,
      params: {'category_id': ?categoryId},
    );
    final token = _newToken();
    TimeoutFailure timedOut() {
      _cancel(token);
      return TimeoutFailure('Timed out: ${_safe(uri)}');
    }

    var finished = false;
    try {
      var pending = dio.getUri<ResponseBody>(
        uri,
        options: Options(responseType: ResponseType.stream),
        cancelToken: token,
      );
      if (idleTimeout != null) {
        pending = pending.timeout(
          idleTimeout,
          onTimeout: () => throw timedOut(),
        );
      }
      final body = (await pending).data;
      if (body == null) throw ParseFailure('Empty response from ${_safe(uri)}');
      Stream<List<int>> bytes = body.stream;
      if (idleTimeout != null) {
        bytes = bytes.timeout(
          idleTimeout,
          onTimeout: (sink) => sink
            ..addError(timedOut())
            ..close(),
        );
      }
      await for (final item in jsonArrayStream(bytes)) {
        yield item;
      }
      finished = true;
    } on SourceFailure {
      rethrow;
    } on FormatException {
      throw ParseFailure('Invalid JSON from ${_safe(uri)}');
    } catch (e) {
      throw mapDioError(e, secrets: _secrets);
    } finally {
      if (!finished) _cancel(token);
      _tokens.remove(token);
    }
  }
}
