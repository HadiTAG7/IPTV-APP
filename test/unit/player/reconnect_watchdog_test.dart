import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/player/session/reconnect_watchdog.dart';

import 'fake_async_clock.dart';

const s1 = Duration(seconds: 1);

const playing = PlaybackState(
  playing: true,
  hasFirstFrame: true,
  position: Duration(seconds: 1),
);

class Harness {
  Harness(this.async, {int maxAttempts = 8}) {
    watchdog = ReconnectWatchdog(
      reconnect: (attempt) async {
        attempts.add(attempt);
        attemptTimes.add(async.elapsed);
      },
      onGiveUp: () => gaveUp++,
      clock: FakeAsyncClock(async),
      maxAttempts: maxAttempts,
    );
    watchdog.status.addListener(() => statuses.add(watchdog.status.value));
  }

  final FakeAsync async;
  late final ReconnectWatchdog watchdog;
  final attempts = <int>[];
  final attemptTimes = <Duration>[];
  final statuses = <ReconnectStatus>[];
  int gaveUp = 0;

  /// Healthy playback: position advances every second for [d].
  void playFor(Duration d) {
    var pos = watchdogPosition;
    for (var i = 0; i < d.inSeconds; i++) {
      pos += s1;
      watchdog.onState(playing.copyWith(position: pos));
      async.elapse(s1);
    }
    watchdogPosition = pos;
  }

  Duration watchdogPosition = Duration.zero;

  void fail() => watchdog.onEvent(const ErrorEvent('boom', httpStatus: null));
}

void main() {
  test('fatal error schedules attempt 1 after 1 s', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.watchdog.watch(isLive: true);
      h.watchdog.onState(playing);
      h.fail();
      expect(
        h.watchdog.status.value,
        const ReconnectWaiting(
          attempt: 1,
          maxAttempts: 8,
          delay: s1,
          reason: ReconnectReason.error,
        ),
      );
      async.elapse(const Duration(milliseconds: 999));
      expect(h.attempts, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(h.attempts, [1]);
      h.watchdog.dispose();
    });
  });

  test('non-fatal errors are ignored', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.watchdog.watch(isLive: true);
      h.watchdog.onEvent(const ErrorEvent('decoder hiccup', fatal: false));
      async.elapse(const Duration(seconds: 5));
      expect(h.attempts, isEmpty);
      expect(h.watchdog.status.value, ReconnectStatus.idle);
      h.watchdog.dispose();
    });
  });

  test('ended triggers on live only', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.watchdog.watch(isLive: false);
      h.watchdog.onEvent(const EndedEvent());
      async.elapse(const Duration(seconds: 3));
      expect(h.attempts, isEmpty);

      h.watchdog.watch(isLive: true);
      h.watchdog.onEvent(const EndedEvent());
      expect(
        (h.watchdog.status.value as ReconnectWaiting).reason,
        ReconnectReason.ended,
      );
      async.elapse(s1);
      expect(h.attempts, [1]);
      h.watchdog.dispose();
    });
  });

  test('buffering longer than 12 s triggers, 12 s does not', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.watchdog.watch(isLive: true);
      h.watchdog.onState(const PlaybackState(buffering: true));
      async.elapse(const Duration(seconds: 12));
      expect(h.watchdog.status.value, ReconnectStatus.idle);
      async.elapse(s1);
      final status = h.watchdog.status.value as ReconnectWaiting;
      expect(status.reason, ReconnectReason.buffering);
      expect(status.attempt, 1);
      h.watchdog.dispose();
    });
  });

  test('buffering that clears in time does not trigger', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.watchdog.watch(isLive: true);
      for (var i = 0; i < 5; i++) {
        h.watchdog.onState(const PlaybackState(buffering: true));
        async.elapse(const Duration(seconds: 10));
        h.watchdog.onState(playing.copyWith(position: Duration(seconds: i)));
        async.elapse(const Duration(seconds: 2));
      }
      expect(h.watchdog.status.value, ReconnectStatus.idle);
      h.watchdog.dispose();
    });
  });

  test('position frozen for more than 15 s while playing triggers', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.watchdog.watch(isLive: true);
      h.watchdog.onState(playing);
      async.elapse(const Duration(seconds: 15));
      expect(h.watchdog.status.value, ReconnectStatus.idle);
      async.elapse(s1);
      expect(
        (h.watchdog.status.value as ReconnectWaiting).reason,
        ReconnectReason.stalled,
      );
      h.watchdog.dispose();
    });
  });

  test('a paused (not playing) stream is never "stalled"', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.watchdog.watch(isLive: false);
      h.watchdog.onState(playing);
      h.watchdog.onState(playing.copyWith(playing: false));
      async.elapse(const Duration(minutes: 5));
      expect(h.watchdog.status.value, ReconnectStatus.idle);
      h.watchdog.dispose();
    });
  });

  test('backoff is 1,2,4,8,16,30,30,30 s then gives up', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.watchdog.watch(isLive: true);
      final delays = <Duration>[];
      for (var i = 1; i <= 8; i++) {
        h.fail();
        final status = h.watchdog.status.value as ReconnectWaiting;
        expect(status.attempt, i);
        expect(status.maxAttempts, 8);
        delays.add(status.delay);
        async.elapse(status.delay);
        expect(h.attempts.length, i);
      }
      expect(delays, kReconnectBackoff);
      expect(h.gaveUp, 0);

      h.fail();
      expect(h.watchdog.status.value, const ReconnectGaveUp(8));
      expect(h.gaveUp, 1);
      expect(h.watchdog.isWatching, isFalse);

      // Nothing more happens after giving up.
      h.fail();
      async.elapse(const Duration(minutes: 2));
      expect(h.attempts.length, 8);
      expect(h.gaveUp, 1);
      h.watchdog.dispose();
    });
  });

  test('triggers while an attempt is pending are coalesced', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.watchdog.watch(isLive: true);
      h.fail();
      h.fail();
      h.watchdog.onEvent(const EndedEvent());
      async.elapse(s1);
      expect(h.attempts, [1]);
      expect(h.watchdog.attempts, 1);
      h.watchdog.dispose();
    });
  });

  test('first frame after a reconnect returns to idle, counter kept', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.watchdog.watch(isLive: true);
      h.fail();
      async.elapse(s1);
      expect(h.watchdog.status.value, isA<ReconnectWaiting>());
      h.watchdog.onEvent(const FirstFrameEvent());
      expect(h.watchdog.status.value, ReconnectStatus.idle);
      expect(h.watchdog.attempts, 1);

      h.fail();
      expect((h.watchdog.status.value as ReconnectWaiting).attempt, 2);
      expect((h.watchdog.status.value as ReconnectWaiting).delay, s1 * 2);
      h.watchdog.dispose();
    });
  });

  test('60 s of stable playback resets the counter', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.watchdog.watch(isLive: true);
      for (var i = 0; i < 3; i++) {
        h.fail();
        async.elapse((h.watchdog.status.value as ReconnectWaiting).delay);
      }
      expect(h.watchdog.attempts, 3);
      h.watchdog.onEvent(const FirstFrameEvent());

      h.playFor(const Duration(seconds: 30));
      expect(h.watchdog.attempts, 3);
      h.playFor(const Duration(seconds: 31));
      expect(h.watchdog.attempts, 0);

      h.fail();
      final status = h.watchdog.status.value as ReconnectWaiting;
      expect(status.attempt, 1);
      expect(status.delay, s1);
      h.watchdog.dispose();
    });
  });

  test('unstable playback (buffering) does not reset the counter', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.watchdog.watch(isLive: true);
      h.fail();
      async.elapse(s1);
      for (var i = 0; i < 12; i++) {
        h.playFor(const Duration(seconds: 5));
        h.watchdog.onState(const PlaybackState(buffering: true));
        async.elapse(s1);
      }
      expect(h.watchdog.attempts, 1);
      h.watchdog.dispose();
    });
  });

  test('pause holds a pending attempt; resume runs it at once', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.watchdog.watch(isLive: true);
      h.fail();
      async.elapse(const Duration(milliseconds: 500));
      h.watchdog.pause();
      expect(h.watchdog.isPaused, isTrue);
      expect((h.watchdog.status.value as ReconnectWaiting).paused, isTrue);

      async.elapse(const Duration(minutes: 3));
      expect(h.attempts, isEmpty);

      h.watchdog.resume();
      expect(h.attempts, [1]);
      expect(
        h.attemptTimes.single,
        const Duration(minutes: 3, seconds: 0) +
            const Duration(milliseconds: 500),
      );
      expect((h.watchdog.status.value as ReconnectWaiting).paused, isFalse);
      h.watchdog.dispose();
    });
  });

  test('while paused, detectors are off and failures wait for resume', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.watchdog.watch(isLive: true);
      h.watchdog.pause();
      h.watchdog.onState(const PlaybackState(buffering: true));
      async.elapse(const Duration(seconds: 60));
      expect(h.watchdog.status.value, ReconnectStatus.idle);

      h.fail();
      final status = h.watchdog.status.value as ReconnectWaiting;
      expect(status.paused, isTrue);
      expect(status.attempt, 1);
      async.elapse(const Duration(seconds: 60));
      expect(h.attempts, isEmpty);

      h.watchdog.resume();
      expect(h.attempts, [1]);
      h.watchdog.dispose();
    });
  });

  test('buffering detection restarts after resume', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.watchdog.watch(isLive: true);
      h.watchdog.onState(const PlaybackState(buffering: true));
      async.elapse(const Duration(seconds: 10));
      h.watchdog.pause();
      async.elapse(const Duration(seconds: 30));
      h.watchdog.resume();
      async.elapse(const Duration(seconds: 12));
      expect(h.watchdog.status.value, ReconnectStatus.idle);
      async.elapse(s1);
      expect(
        (h.watchdog.status.value as ReconnectWaiting).reason,
        ReconnectReason.buffering,
      );
      h.watchdog.dispose();
    });
  });

  test('a frozen engine is caught again after a fruitless attempt', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.watchdog.watch(isLive: true);
      h.watchdog.onState(const PlaybackState(buffering: true));
      async.elapse(const Duration(seconds: 13));
      expect(h.watchdog.attempts, 1);
      async.elapse(s1);
      expect(h.attempts, [1]);
      // No new state ever arrives; the next attempt still comes.
      async.elapse(const Duration(seconds: 13));
      expect(h.watchdog.attempts, 2);
      h.watchdog.dispose();
    });
  });

  test('cancel clears pending attempts and stops monitoring', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.watchdog.watch(isLive: true);
      h.fail();
      h.watchdog.cancel();
      expect(h.watchdog.status.value, ReconnectStatus.idle);
      expect(h.watchdog.isWatching, isFalse);
      async.elapse(const Duration(minutes: 1));
      expect(h.attempts, isEmpty);

      h.watchdog.onState(const PlaybackState(buffering: true));
      h.fail();
      async.elapse(const Duration(minutes: 1));
      expect(h.attempts, isEmpty);
      expect(async.pendingTimers, isEmpty);
      h.watchdog.dispose();
    });
  });

  test('watch() resets attempts for a new item', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.watchdog.watch(isLive: true);
      h.fail();
      async.elapse(s1);
      h.fail();
      expect(h.watchdog.attempts, 2);
      h.watchdog.watch(isLive: true);
      expect(h.watchdog.attempts, 0);
      expect(h.watchdog.status.value, ReconnectStatus.idle);
      async.elapse(const Duration(seconds: 3));
      expect(h.attempts, [1]);
      h.watchdog.dispose();
    });
  });

  test('a throwing reconnect counts as a failure', () {
    fakeAsync((async) {
      var calls = 0;
      final watchdog = ReconnectWatchdog(
        reconnect: (_) async {
          calls++;
          throw StateError('engine gone');
        },
        clock: FakeAsyncClock(async),
        maxAttempts: 2,
      );
      watchdog.watch(isLive: true);
      watchdog.onEvent(const ErrorEvent('x'));
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(calls, 1);
      expect((watchdog.status.value as ReconnectWaiting).attempt, 2);
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(calls, 2);
      expect(watchdog.status.value, const ReconnectGaveUp(2));
      watchdog.dispose();
    });
  });

  test('status values compare by value', () {
    const a = ReconnectWaiting(
      attempt: 1,
      maxAttempts: 8,
      delay: s1,
      reason: ReconnectReason.error,
    );
    expect(a, a.copyWith());
    expect(a, isNot(a.copyWith(paused: true)));
    expect(const ReconnectGaveUp(3), const ReconnectGaveUp(3));
    expect(const ReconnectIdle(), ReconnectStatus.idle);
    expect(a.toString(), contains('1/8'));
  });
}
