import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/player/session/connection_guard.dart';

import 'fake_async_clock.dart';

/// Records `stop`/`open` steps with their fake time.
class Recorder {
  Recorder(this.async);

  final FakeAsync async;
  final log = <String>[];

  Future<void> Function() stop(String tag, {Duration delay = Duration.zero}) =>
      () async {
        log.add('${async.elapsed.inMilliseconds} stop $tag');
        if (delay > Duration.zero) await Future<void>.delayed(delay);
      };

  Future<void> Function() open(String tag, {Duration delay = Duration.zero}) =>
      () async {
        log.add('${async.elapsed.inMilliseconds} open $tag');
        if (delay > Duration.zero) await Future<void>.delayed(delay);
      };
}

ConnectionGuard guardFor(FakeAsync async) =>
    ConnectionGuard(clock: FakeAsyncClock(async));

void main() {
  test('stop runs before open, with a 150 ms gap on 1-connection panels', () {
    fakeAsync((async) {
      final r = Recorder(async);
      final guard = guardFor(async);
      bool? result;
      unawaited(
        guard
            .switchTo(stop: r.stop('a'), open: r.open('a'), maxConnections: 1)
            .then((v) => result = v),
      );
      async.flushMicrotasks();
      expect(r.log, ['0 stop a']);
      async.elapse(const Duration(milliseconds: 149));
      expect(r.log, ['0 stop a']);
      async.elapse(const Duration(milliseconds: 1));
      expect(r.log, ['0 stop a', '150 open a']);
      expect(result, isTrue);
    });
  });

  test('no gap when the panel allows more connections or is unknown', () {
    fakeAsync((async) {
      final r = Recorder(async);
      final guard = guardFor(async);
      unawaited(
        guard.switchTo(stop: r.stop('a'), open: r.open('a'), maxConnections: 2),
      );
      async.flushMicrotasks();
      unawaited(guard.switchTo(stop: r.stop('b'), open: r.open('b')));
      async.flushMicrotasks();
      expect(r.log, ['0 stop a', '0 open a', '0 stop b', '0 open b']);
    });
  });

  test('switches are serialized: next stop waits for the running open', () {
    fakeAsync((async) {
      final r = Recorder(async);
      final guard = guardFor(async);
      unawaited(
        guard.switchTo(
          stop: r.stop('a'),
          open: r.open('a', delay: const Duration(milliseconds: 500)),
          maxConnections: 1,
        ),
      );
      async.elapse(const Duration(milliseconds: 200));
      unawaited(
        guard.switchTo(stop: r.stop('b'), open: r.open('b'), maxConnections: 1),
      );
      async.elapse(const Duration(seconds: 1));
      expect(r.log, ['0 stop a', '150 open a', '650 stop b', '800 open b']);
    });
  });

  test('latest request wins: superseded switches never open', () {
    fakeAsync((async) {
      final r = Recorder(async);
      final guard = guardFor(async);
      final results = <String, bool>{};
      for (final tag in ['a', 'b', 'c', 'd']) {
        unawaited(
          guard
              .switchTo(stop: r.stop(tag), open: r.open(tag), maxConnections: 1)
              .then((v) => results[tag] = v),
        );
      }
      async.elapse(const Duration(seconds: 1));
      expect(r.log, ['0 stop d', '150 open d']);
      expect(results, {'a': false, 'b': false, 'c': false, 'd': true});
    });
  });

  test('a switch superseded during the gap does not open', () {
    fakeAsync((async) {
      final r = Recorder(async);
      final guard = guardFor(async);
      unawaited(
        guard.switchTo(stop: r.stop('a'), open: r.open('a'), maxConnections: 1),
      );
      async.elapse(const Duration(milliseconds: 100));
      unawaited(
        guard.switchTo(stop: r.stop('b'), open: r.open('b'), maxConnections: 1),
      );
      async.elapse(const Duration(seconds: 1));
      expect(r.log, ['0 stop a', '150 stop b', '300 open b']);
    });
  });

  test('never more than one open in flight across 20 rapid zaps', () {
    fakeAsync((async) {
      final guard = guardFor(async);
      var connections = 0;
      var maxConnections = 0;
      var opens = 0;
      for (var i = 0; i < 20; i++) {
        unawaited(
          guard.switchTo(
            stop: () async => connections = 0,
            open: () async {
              opens++;
              connections++;
              if (connections > maxConnections) maxConnections = connections;
              await Future<void>.delayed(const Duration(milliseconds: 80));
            },
            maxConnections: 1,
          ),
        );
        async.elapse(const Duration(milliseconds: 60));
      }
      async.elapse(const Duration(seconds: 2));
      expect(maxConnections, 1);
      expect(opens, lessThan(20));
    });
  });

  group('held-connection 4xx', () {
    ErrorEvent http(int status) =>
        ErrorEvent('HTTP $status', httpStatus: status);

    test('retries after 1 s then 2 s, then gives the error back', () {
      fakeAsync((async) {
        final r = Recorder(async);
        final guard = guardFor(async);
        unawaited(
          guard.switchTo(
            stop: r.stop('a'),
            open: r.open('a'),
            maxConnections: 1,
          ),
        );
        async.elapse(const Duration(milliseconds: 500));
        expect(r.log, ['0 stop a', '150 open a']);

        expect(guard.handleError(http(403)), isTrue);
        expect(guard.retryPending, isTrue);
        async.elapse(const Duration(milliseconds: 999));
        expect(r.log.length, 2);
        async.elapse(const Duration(milliseconds: 1));
        async.elapse(const Duration(milliseconds: 150));
        expect(r.log.sublist(2), ['1500 stop a', '1650 open a']);

        expect(guard.handleError(http(401)), isTrue);
        async.elapse(const Duration(seconds: 2, milliseconds: 150));
        expect(r.log.sublist(4), ['3650 stop a', '3800 open a']);

        expect(guard.handleError(http(403)), isFalse);
        async.elapse(const Duration(seconds: 5));
        expect(r.log.length, 6);
      });
    });

    test('duplicate errors while a retry is pending are absorbed once', () {
      fakeAsync((async) {
        final r = Recorder(async);
        final guard = guardFor(async);
        unawaited(guard.switchTo(stop: r.stop('a'), open: r.open('a')));
        async.flushMicrotasks();
        expect(guard.handleError(http(403)), isTrue);
        expect(guard.handleError(http(403)), isTrue);
        async.elapse(const Duration(seconds: 3));
        expect(r.log, ['0 stop a', '0 open a', '1000 stop a', '1000 open a']);
      });
    });

    test('only within 3 s of the open', () {
      fakeAsync((async) {
        final r = Recorder(async);
        final guard = guardFor(async);
        unawaited(guard.switchTo(stop: r.stop('a'), open: r.open('a')));
        async.elapse(const Duration(seconds: 3, milliseconds: 1));
        expect(guard.handleError(http(403)), isFalse);
      });
    });

    test('multi or unknown connections: ignores 5xx, 404, unknown status '
        'and non-fatal errors', () {
      fakeAsync((async) {
        final r = Recorder(async);
        final guard = guardFor(async);
        unawaited(guard.switchTo(stop: r.stop('a'), open: r.open('a')));
        async.flushMicrotasks();
        expect(guard.handleError(http(500)), isFalse);
        expect(guard.handleError(http(404)), isFalse);
        expect(guard.handleError(http(410)), isFalse);
        expect(guard.handleError(const ErrorEvent('Source error')), isFalse);
        expect(
          guard.handleError(
            const ErrorEvent('HTTP 403', httpStatus: 403, fatal: false),
          ),
          isFalse,
        );
        expect(guard.handleError(http(429)), isTrue);
      });
    });

    test('single-connection panels: unknown status and 404 may be held', () {
      fakeAsync((async) {
        final r = Recorder(async);
        final guard = guardFor(async);
        unawaited(
          guard.switchTo(
            stop: r.stop('a'),
            open: r.open('a'),
            maxConnections: 1,
          ),
        );
        async.elapse(const Duration(milliseconds: 150));
        // ExoPlayer reports only "Source error", without the status.
        expect(guard.handleError(const ErrorEvent('Source error')), isTrue);
        async.elapse(const Duration(milliseconds: 1150));
        expect(r.log, ['0 stop a', '150 open a', '1150 stop a', '1300 open a']);
        expect(guard.handleError(http(404)), isTrue);
        async.elapse(const Duration(milliseconds: 2150));
        expect(r.log.last, '3450 open a');
        // Budget spent: the caller's fallback takes over.
        expect(guard.handleError(const ErrorEvent('Source error')), isFalse);
        expect(guard.handleError(http(500)), isFalse);
        expect(
          guard.handleError(const ErrorEvent('glitch', fatal: false)),
          isFalse,
        );
      });
    });

    test('single-connection: 5xx is never a held connection', () {
      fakeAsync((async) {
        final r = Recorder(async);
        final guard = guardFor(async);
        unawaited(
          guard.switchTo(
            stop: r.stop('a'),
            open: r.open('a'),
            maxConnections: 1,
          ),
        );
        async.elapse(const Duration(milliseconds: 150));
        expect(guard.handleError(http(503)), isFalse);
        expect(guard.handleError(http(410)), isTrue);
      });
    });

    test('a new zap cancels a pending retry and resets the budget', () {
      fakeAsync((async) {
        final r = Recorder(async);
        final guard = guardFor(async);
        unawaited(guard.switchTo(stop: r.stop('a'), open: r.open('a')));
        async.flushMicrotasks();
        expect(guard.handleError(http(403)), isTrue);
        unawaited(guard.switchTo(stop: r.stop('b'), open: r.open('b')));
        async.elapse(const Duration(seconds: 5));
        expect(r.log, ['0 stop a', '0 open a', '0 stop b', '0 open b']);
        expect(guard.retryPending, isFalse);

        unawaited(guard.switchTo(stop: r.stop('c'), open: r.open('c')));
        async.flushMicrotasks();
        expect(guard.handleError(http(403)), isTrue);
      });
    });

    test('no retry before any switch', () {
      fakeAsync((async) {
        expect(guardFor(async).handleError(http(403)), isFalse);
      });
    });
  });

  test('stop() supersedes pending switches and runs after the current one', () {
    fakeAsync((async) {
      final r = Recorder(async);
      final guard = guardFor(async);
      unawaited(
        guard.switchTo(
          stop: r.stop('a'),
          open: r.open('a', delay: const Duration(milliseconds: 300)),
        ),
      );
      async.flushMicrotasks();
      unawaited(guard.switchTo(stop: r.stop('b'), open: r.open('b')));
      var stopped = false;
      unawaited(guard.stop(r.stop('final')).then((_) => stopped = true));
      async.elapse(const Duration(milliseconds: 100));
      expect(stopped, isFalse);
      async.elapse(const Duration(seconds: 1));
      expect(stopped, isTrue);
      expect(r.log, ['0 stop a', '0 open a', '300 stop final']);
      expect(guard.handleError(http403), isFalse);
    });
  });

  test('cancel() drops queued switches without stopping', () {
    fakeAsync((async) {
      final r = Recorder(async);
      final guard = guardFor(async);
      unawaited(
        guard.switchTo(
          stop: r.stop('a', delay: const Duration(milliseconds: 100)),
          open: r.open('a'),
        ),
      );
      async.flushMicrotasks();
      guard.cancel();
      async.elapse(const Duration(seconds: 1));
      expect(r.log, ['0 stop a']);
    });
  });

  test('a throwing step does not wedge the queue', () {
    fakeAsync((async) {
      final r = Recorder(async);
      final guard = guardFor(async);
      bool? first;
      unawaited(
        guard
            .switchTo(
              stop: () async => throw StateError('stop failed'),
              open: () async => throw StateError('open failed'),
            )
            .then((v) => first = v),
      );
      async.flushMicrotasks();
      expect(first, isTrue);
      unawaited(guard.switchTo(stop: r.stop('b'), open: r.open('b')));
      async.flushMicrotasks();
      expect(r.log, ['0 stop b', '0 open b']);
    });
  });

  test('a hung open is abandoned after the step timeout', () {
    fakeAsync((async) {
      final r = Recorder(async);
      final guard = guardFor(async);
      unawaited(
        guard.switchTo(stop: r.stop('a'), open: () => Completer<void>().future),
      );
      async.flushMicrotasks();
      unawaited(guard.switchTo(stop: r.stop('b'), open: r.open('b')));
      async.elapse(const Duration(seconds: 9));
      expect(r.log, ['0 stop a']);
      async.elapse(const Duration(seconds: 1));
      expect(r.log, ['0 stop a', '10000 stop b', '10000 open b']);
    });
  });
}

const http403 = ErrorEvent('HTTP 403', httpStatus: 403);
