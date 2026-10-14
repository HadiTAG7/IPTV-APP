import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Reads `test/fixtures/xtream/<name>`.
String xtreamFixture(String name) =>
    File('test/fixtures/xtream/$name').readAsStringSync();

/// One canned HTTP response.
class FakeReply {
  FakeReply(
    this.body, {
    this.status = 200,
    this.delay = Duration.zero,
    this.chunkSize,
    this.chunkDelay = Duration.zero,
    this.contentType = 'application/json',
  });

  FakeReply.json(
    Object? json, {
    int status = 200,
    Duration delay = Duration.zero,
    int? chunkSize,
    Duration chunkDelay = Duration.zero,
  }) : this(
         utf8.encode(jsonEncode(json)),
         status: status,
         delay: delay,
         chunkSize: chunkSize,
         chunkDelay: chunkDelay,
       );

  FakeReply.text(
    String text, {
    int status = 200,
    Duration delay = Duration.zero,
    int? chunkSize,
    Duration chunkDelay = Duration.zero,
    String contentType = 'text/html',
  }) : this(
         utf8.encode(text),
         status: status,
         delay: delay,
         chunkSize: chunkSize,
         chunkDelay: chunkDelay,
         contentType: contentType,
       );

  FakeReply.fixture(
    String name, {
    Duration delay = Duration.zero,
    int? chunkSize,
    Duration chunkDelay = Duration.zero,
  }) : this(
         utf8.encode(xtreamFixture(name)),
         delay: delay,
         chunkSize: chunkSize,
         chunkDelay: chunkDelay,
       );

  final List<int> body;
  final int status;

  /// Wait before the response headers.
  final Duration delay;

  /// Body split into chunks of this many bytes (whole body when null).
  final int? chunkSize;

  /// Wait before every chunk after the first.
  final Duration chunkDelay;
  final String contentType;
}

/// Computes a reply for a request; may throw a [DioException].
typedef FakeRoute = FutureOr<FakeReply> Function(RequestOptions request);

/// dio [HttpClientAdapter] that serves canned replies keyed by the
/// `action` query parameter (`''` is the login call without an action).
///
/// Delays honour dio cancellation so timed-out requests end promptly.
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter([Map<String, Object>? routes]) : routes = {...?routes};

  /// Values are [FakeReply] or [FakeRoute].
  final Map<String, Object> routes;
  final requests = <RequestOptions>[];
  var cancelledCount = 0;

  static String actionOf(RequestOptions r) =>
      r.uri.queryParameters['action'] ?? '';

  /// `action` or `action?k=v&k2=v2` (credentials omitted) per request.
  List<String> get calls => [for (final r in requests) _describe(r)];

  static String _describe(RequestOptions r) {
    final params = [
      for (final e in r.uri.queryParameters.entries)
        if (e.key != 'action' && e.key != 'username' && e.key != 'password')
          '${e.key}=${e.value}',
    ];
    return params.isEmpty ? actionOf(r) : '${actionOf(r)}?${params.join('&')}';
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    var cancelled = false;
    unawaited(
      cancelFuture?.then((_) {
        cancelled = true;
        cancelledCount++;
      }),
    );
    final route = routes[actionOf(options)];
    final FakeReply reply;
    if (route == null) {
      reply = FakeReply.text('<html>404 Not Found</html>', status: 404);
    } else if (route is FakeReply) {
      reply = route;
    } else {
      reply = await (route as FakeRoute)(options);
    }
    if (reply.delay > Duration.zero) {
      await _sleep(reply.delay, cancelFuture);
    }
    if (cancelled) {
      throw DioException.requestCancelled(
        requestOptions: options,
        reason: 'cancelled',
      );
    }
    return ResponseBody(
      _chunks(reply, cancelFuture, () => cancelled),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [reply.contentType],
      },
    );
  }

  Stream<Uint8List> _chunks(
    FakeReply reply,
    Future<void>? cancelFuture,
    bool Function() isCancelled,
  ) async* {
    final body = Uint8List.fromList(reply.body);
    final size = reply.chunkSize ?? (body.isEmpty ? 1 : body.length);
    for (var i = 0; i < body.length; i += size) {
      if (i > 0 && reply.chunkDelay > Duration.zero) {
        await _sleep(reply.chunkDelay, cancelFuture);
      }
      if (isCancelled()) return;
      final end = i + size > body.length ? body.length : i + size;
      yield Uint8List.sublistView(body, i, end);
    }
  }

  static Future<void> _sleep(Duration d, Future<void>? cancelFuture) {
    final done = Completer<void>();
    final timer = Timer(d, () {
      if (!done.isCompleted) done.complete();
    });
    unawaited(
      cancelFuture?.then((_) {
        timer.cancel();
        if (!done.isCompleted) done.complete();
      }),
    );
    return done.future;
  }

  @override
  void close({bool force = false}) {}
}

/// A [Dio] wired to [adapter] with no timeouts of its own.
Dio fakeDio(FakeHttpAdapter adapter) => Dio()..httpClientAdapter = adapter;
