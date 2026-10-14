import 'package:dio/dio.dart';

import '../../sources/models.dart';
import 'redact.dart';

/// App default User-Agent. Some panels block library defaults (`Dart/x`,
/// `libmpv`), so every request sends a browser-like or app UA.
const kDefaultUserAgent = 'IPTVPlayer/1.0 (Linux; Android) ExoPlayerLib/2.19.1';

/// Common User-Agent presets offered in the source editor.
const kUserAgentPresets = <String, String>{
  'Default': kDefaultUserAgent,
  'VLC': 'VLC/3.0.21 LibVLC/3.0.21',
  'Kodi': 'Kodi/21.2 (Linux; Android 12) Android/12 Sys_CPU/armv8l',
  'Chrome': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
  'Smarters': 'IPTVSmartersPro',
};

/// Builds a [Dio] client with IPTV-friendly defaults.
///
/// [secrets] are redacted from any error message produced by [mapDioError].
Dio createDio({
  String? userAgent,
  String? referer,
  Duration connectTimeout = const Duration(seconds: 15),
  Duration receiveTimeout = const Duration(seconds: 120),
}) {
  return Dio(
    BaseOptions(
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: const Duration(seconds: 15),
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (s) => s != null && s >= 200 && s < 300,
      headers: {
        'User-Agent': (userAgent == null || userAgent.isEmpty)
            ? kDefaultUserAgent
            : userAgent,
        if (referer != null && referer.isNotEmpty) 'Referer': referer,
        'Accept': '*/*',
      },
    ),
  );
}

/// Converts a dio error into a credential-free [SourceFailure].
SourceFailure mapDioError(Object error, {Iterable<String> secrets = const []}) {
  if (error is SourceFailure) return error;
  if (error is DioException) {
    final url = redact(error.requestOptions.uri.toString(), secrets: secrets);
    switch (error.type) {
      case DioExceptionType.cancel:
        return const CancelledFailure();
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return TimeoutFailure('Timed out: $url');
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        if (code == 401 || code == 403) {
          return AuthFailure('HTTP $code from $url');
        }
        return NetworkFailure('HTTP $code from $url', statusCode: code);
      case DioExceptionType.badCertificate:
        return NetworkFailure('Bad TLS certificate: $url');
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        final detail = redact(
          '${error.error ?? error.message}',
          secrets: secrets,
        );
        return NetworkFailure('Network error for $url: $detail');
    }
  }
  return NetworkFailure(redact('$error', secrets: secrets));
}
