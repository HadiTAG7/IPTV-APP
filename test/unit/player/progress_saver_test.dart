import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/player/session/progress_saver.dart';

const min = Duration(minutes: 1);
const sec = Duration(seconds: 1);

PlaybackState at(int seconds, {bool playing = true, int durationMin = 90}) =>
    PlaybackState(
      position: Duration(seconds: seconds),
      duration: Duration(minutes: durationMin),
      playing: playing,
      hasFirstFrame: true,
    );

void main() {
  late List<(Duration, Duration)> saved;

  ProgressSaver make() {
    saved = [];
    return ProgressSaver(save: (p, d) async => saved.add((p, d)));
  }

  test('saves every 10 s while playing', () {
    fakeAsync((async) {
      final saver = make()..start();
      for (var s = 1; s <= 35; s++) {
        saver.update(at(s));
        async.elapse(sec);
      }
      expect(saved.map((e) => e.$1.inSeconds), [10, 20, 30]);
      expect(saved.first.$2, const Duration(minutes: 90));
      saver.dispose();
    });
  });

  test('no periodic saves while paused', () {
    fakeAsync((async) {
      final saver = make()..start();
      saver.update(at(5));
      saver.update(at(5, playing: false));
      expect(saved.single.$1, const Duration(seconds: 5));
      async.elapse(const Duration(minutes: 2));
      expect(saved, hasLength(1));
      saver.dispose();
    });
  });

  test('pause transition saves; unchanged positions are not repeated', () {
    fakeAsync((async) {
      final saver = make()..start();
      saver.update(at(42));
      expect(saved, isEmpty);
      saver.update(at(42, playing: false));
      expect(saved.single.$1.inSeconds, 42);
      saver.update(at(42));
      saver.update(at(42, playing: false));
      expect(saved, hasLength(1));
      saver.dispose();
    });
  });

  test('stop flushes once and ignores later updates', () {
    fakeAsync((async) {
      final saver = make()..start();
      saver.update(at(61));
      unawaited(saver.stop());
      async.flushMicrotasks();
      expect(saved.single.$1.inSeconds, 61);
      saver.update(at(70));
      saver.update(at(70, playing: false));
      async.elapse(const Duration(seconds: 30));
      expect(saved, hasLength(1));
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('dispose saves the last position', () {
    fakeAsync((async) {
      final saver = make()..start();
      saver.update(at(12));
      saver.dispose();
      async.flushMicrotasks();
      expect(saved.single.$1.inSeconds, 12);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('flush (backgrounding) saves on demand', () async {
    final saver = make();
    saver.update(at(300));
    await saver.flush();
    expect(saved.single.$1, const Duration(minutes: 5));
  });

  test('zero positions (opening, reconnecting) never overwrite progress', () {
    fakeAsync((async) {
      final saver = make()..start();
      saver.update(at(600));
      saver.update(const PlaybackState(buffering: true));
      expect(saved.single.$1.inSeconds, 600);
      unawaited(saver.stop());
      async.flushMicrotasks();
      expect(saved, hasLength(1));
    });
  });

  test('nothing is saved before playback moved', () async {
    final saver = make();
    await saver.flush();
    saver.update(const PlaybackState(playing: true));
    await saver.flush();
    expect(saved, isEmpty);
  });

  test('a failing sink does not break saving', () {
    fakeAsync((async) {
      var calls = 0;
      final saver = ProgressSaver(
        save: (p, d) async {
          calls++;
          if (calls == 1) throw StateError('db locked');
        },
      )..start();
      saver.update(at(10));
      async.elapse(const Duration(seconds: 10));
      expect(calls, 1);
      async.elapse(const Duration(seconds: 10));
      expect(calls, 2);
      saver.dispose();
    });
  });

  group('isFinished', () {
    test('above 95%', () {
      const d = Duration(minutes: 100);
      expect(ProgressSaver.isFinished(const Duration(minutes: 94), d), isFalse);
      expect(ProgressSaver.isFinished(const Duration(minutes: 95), d), isTrue);
    });

    test('under 2 minutes left', () {
      const d = Duration(minutes: 30);
      expect(
        ProgressSaver.isFinished(const Duration(minutes: 27, seconds: 59), d),
        isFalse,
      );
      expect(
        ProgressSaver.isFinished(const Duration(minutes: 28, seconds: 1), d),
        isTrue,
      );
    });

    test('unknown duration or no progress is never finished', () {
      expect(ProgressSaver.isFinished(min, Duration.zero), isFalse);
      expect(
        ProgressSaver.isFinished(Duration.zero, const Duration(minutes: 1)),
        isFalse,
      );
    });

    test('shouldOfferResume', () {
      const d = Duration(minutes: 100);
      expect(
        ProgressSaver.shouldOfferResume(const Duration(seconds: 30), d),
        isFalse,
      );
      expect(
        ProgressSaver.shouldOfferResume(const Duration(seconds: 31), d),
        isTrue,
      );
      expect(
        ProgressSaver.shouldOfferResume(const Duration(minutes: 99), d),
        isFalse,
      );
      expect(
        ProgressSaver.shouldOfferResume(
          const Duration(minutes: 5),
          Duration.zero,
        ),
        isTrue,
      );
    });
  });
}
