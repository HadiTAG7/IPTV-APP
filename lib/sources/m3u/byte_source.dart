/// Where playlist bytes come from: an HTTP download or a local file copy.
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/net/http.dart';
import '../models.dart';

/// A re-openable stream of playlist bytes.
abstract interface class ByteSource {
  /// Starts a new read from the beginning. Errors are [SourceFailure]s.
  ///
  /// Cancelling the subscription releases the connection or file handle, so
  /// callers may stop early (e.g. after sniffing the first bytes).
  Stream<List<int>> open();

  /// Aborts reads in progress; they fail with [CancelledFailure].
  void cancel();
}

/// Streams a playlist over HTTP with dio (`ResponseType.stream`).
class HttpByteSource implements ByteSource {
  HttpByteSource(
    this.dio,
    this.url, {
    this.headers = const {},
    CancelToken? cancelToken,
    this.secrets = const [],
  }) : _parent = cancelToken;

  final Dio dio;
  final String url;

  /// Extra request headers (e.g. the source's User-Agent and Referer).
  final Map<String, String> headers;

  /// Values redacted from error messages besides the usual URL credentials.
  final Iterable<String> secrets;

  final CancelToken? _parent;
  final _active = <CancelToken>{};

  @override
  Stream<List<int>> open() async* {
    final token = CancelToken();
    _active.add(token);
    final parent = _parent;
    if (parent != null) {
      if (parent.isCancelled) {
        token.cancel();
      } else {
        unawaited(parent.whenCancel.then((_) => _cancelToken(token)));
      }
    }
    var finished = false;
    try {
      final Response<ResponseBody> response;
      try {
        response = await dio.get<ResponseBody>(
          url,
          options: Options(responseType: ResponseType.stream, headers: headers),
          cancelToken: token,
        );
      } catch (e) {
        throw mapDioError(e, secrets: secrets);
      }
      final body = response.data;
      if (body == null) {
        finished = true;
        return;
      }
      try {
        await for (final chunk in body.stream) {
          yield chunk;
        }
      } catch (e) {
        if (token.isCancelled) throw const CancelledFailure();
        throw mapDioError(e, secrets: secrets);
      }
      finished = true;
    } finally {
      // Stopped early (listener cancelled or error): abort the download.
      if (!finished) _cancelToken(token);
      _active.remove(token);
    }
  }

  static void _cancelToken(CancelToken token) {
    if (!token.isCancelled) token.cancel();
  }

  @override
  void cancel() {
    for (final token in _active.toList()) {
      _cancelToken(token);
    }
  }
}

/// Reads a local playlist file (the app-private copy of a picked file).
class FileByteSource implements ByteSource {
  FileByteSource(this.path);

  final String path;
  int _generation = 0;

  @override
  Stream<List<int>> open() async* {
    final generation = _generation;
    try {
      await for (final chunk in File(path).openRead()) {
        if (generation != _generation) throw const CancelledFailure();
        yield chunk;
      }
    } on SourceFailure {
      rethrow;
    } catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  void cancel() => _generation++;
}

/// In-memory bytes, split into chunks; handy for tests and pasted text.
class MemoryByteSource implements ByteSource {
  MemoryByteSource(this.bytes, {this.chunkSize = 64 * 1024});

  final List<int> bytes;
  final int chunkSize;
  int _generation = 0;

  @override
  Stream<List<int>> open() async* {
    final generation = _generation;
    for (var i = 0; i < bytes.length; i += chunkSize) {
      if (generation != _generation) throw const CancelledFailure();
      final end = i + chunkSize < bytes.length ? i + chunkSize : bytes.length;
      yield bytes.sublist(i, end);
    }
  }

  @override
  void cancel() => _generation++;
}
