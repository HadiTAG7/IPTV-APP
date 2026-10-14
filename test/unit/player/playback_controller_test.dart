import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/engine/engine_policy.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/player/session/playback_controller.dart';
import 'package:iptv_player/player/session/reconnect_watchdog.dart';
import 'package:iptv_player/sources/models.dart';

import '../../support/fake_engine.dart';
import 'fake_async_clock.dart';

const liveTs = StreamRequest(
  url: 'http://127.0.0.1:8080/live/user/pass/101.ts',
  kind: PlayableKind.live,
);
const liveNoExt = StreamRequest(
  url: 'http://127.0.0.1:8080/play/101',
  kind: PlayableKind.live,
);
const liveTs2 = StreamRequest(
  url: 'http://127.0.0.1:8080/live/user/pass/102.ts',
  kind: PlayableKind.live,
);
const movie = StreamRequest(
  url: 'http://example.com/movie/user/pass/9.mkv',
  kind: PlayableKind.movie,
);

const ms = Duration(milliseconds: 1);
const sec = Duration(seconds: 1);

/// Wires a controller to fake engines inside a fake_async zone.
class Rig {
  Rig(
    this.async, {
    this.platform = TargetPlatformKind.android,
    this.isAmlogic = false,
  }) {
    controller = PlaybackController(
      factory: engines.call,
      policyInput: () =>
          EnginePolicyInput(platform: platform, isAmlogic: isAmlogic),
      clock: FakeAsyncClock(async),
      onEnginePreferenceLearned: (key, kind) => learned.add((key, kind)),
      onProgress: (key, pos, dur) async => progress.add((key, pos, dur)),
      onWakelockChanged: wakelock.add,
    );
    controller.reconnectStatus.addListener(
      () => statuses.add(controller.reconnectStatus.value),
    );
  }

  final FakeAsync async;
  final TargetPlatformKind platform;
  final bool isAmlogic;
  final engines = FakeEngineFactory();
  late final PlaybackController controller;
  final learned = <(String, EngineKind)>[];
  final progress = <(String, Duration, Duration)>[];
  final wakelock = <bool>[];
  final statuses = <ReconnectStatus>[];

  List<String> get log => engines.log;

  FakeEngine get engine => engines.last;

  FakeEngine of(EngineKind kind) =>
      engines.created.lastWhere((e) => e.kind == kind);

  void play(
    StreamRequest r, {
    String? key,
    int? maxConnections,
    EngineKind? pref,
  }) {
    unawaited(
      controller.play(
        r,
        itemKey: key,
        maxConnections: maxConnections,
        channelPref: pref,
      ),
    );
    async.flushMicrotasks();
  }

  /// Every engine of [kind] shows a first frame when opened.
  void playsOn(EngineKind kind) {
    final previous = engines.onCreate;
    engines.onCreate = (e) {
      previous?.call(e);
      if (e.kind == kind) e.onOpen = (e, _) => e.emitFirstFrame();
    };
  }

  /// Every engine of [kind] fails to open.
  void failsOn(EngineKind kind, [String message = 'Source error']) {
    final previous = engines.onCreate;
    engines.onCreate = (e) {
      previous?.call(e);
      if (e.kind == kind) e.onOpen = (e, _) => e.emitError(message);
    };
  }
}

void main() {
  group('opening', () {
    test('Android live opens on exo after stop and a 150 ms gap', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.exo);
        final c = rig.controller;
        rig.play(liveTs, key: 'ch1', maxConnections: 1);
        expect(c.phase, PlaybackPhase.opening);
        expect(rig.log, isEmpty);
        async.elapse(const Duration(milliseconds: 150));
        expect(rig.log, ['exo.create', 'exo.open ${liveTs.url}']);
        expect(c.engineKind, EngineKind.exo);
        expect(c.phase, PlaybackPhase.playing);
        expect(c.request?.url, liveTs.url);
        expect(c.itemKey, 'ch1');
        expect(c.timeToFirstFrame, Duration.zero);
        expect(c.state.value.hasFirstFrame, isTrue);
        c.dispose();
      });
    });

    test('zapping reuses the engine: stop, gap, open', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.exo);
        rig.play(liveTs, maxConnections: 1);
        async.elapse(sec);
        rig.play(liveTs2, maxConnections: 1);
        async.flushMicrotasks();
        expect(rig.log.last, 'exo.stop');
        async.elapse(const Duration(milliseconds: 149));
        expect(rig.log.last, 'exo.stop');
        async.elapse(ms);
        expect(rig.log, [
          'exo.create',
          'exo.open ${liveTs.url}',
          'exo.stop',
          'exo.open ${liveTs2.url}',
        ]);
        expect(rig.engines.created, hasLength(1));
        rig.controller.dispose();
      });
    });

    test('rapid zapping only opens the last channel', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.exo);
        rig.play(liveTs, maxConnections: 1);
        async.elapse(sec);
        rig.log.clear();
        for (var i = 0; i < 10; i++) {
          rig.play(
            StreamRequest(
              url: 'http://127.0.0.1:8080/live/u/p/$i.ts',
              kind: PlayableKind.live,
            ),
            maxConnections: 1,
          );
        }
        async.elapse(sec);
        expect(rig.log.where((l) => l.contains('open')), [
          'exo.open http://127.0.0.1:8080/live/u/p/9.ts',
        ]);
        expect(rig.log.first, 'exo.stop');
        rig.controller.dispose();
      });
    });

    test('VOD on Android picks mpv; Amlogic picks exo', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.mpv);
        rig.play(movie);
        expect(rig.controller.engineKind, EngineKind.mpv);
        rig.controller.dispose();

        final aml = Rig(async, isAmlogic: true)..playsOn(EngineKind.exo);
        aml.play(movie);
        expect(aml.controller.engineKind, EngineKind.exo);
        aml.controller.dispose();
      });
    });

    test('channel preference passed to play() wins', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.mpv);
        rig.play(liveTs, key: 'ch1', pref: EngineKind.mpv);
        expect(rig.controller.engineKind, EngineKind.mpv);
        rig.controller.dispose();
      });
    });

    test('desktop always uses mpv', () {
      fakeAsync((async) {
        final rig = Rig(async, platform: TargetPlatformKind.windows)
          ..playsOn(EngineKind.mpv);
        rig.play(liveTs, pref: EngineKind.exo);
        expect(rig.controller.engineKind, EngineKind.mpv);
        rig.controller.dispose();
      });
    });

    test('state and events mirror the current engine', () {
      fakeAsync((async) {
        final rig = Rig(async);
        final events = <EngineEvent>[];
        rig.controller.events.listen(events.add);
        rig.play(liveTs);
        rig.engine.setState(position: const Duration(seconds: 3));
        expect(rig.controller.state.value.position, const Duration(seconds: 3));
        rig.engine.emitFirstFrame();
        async.flushMicrotasks();
        expect(events, [isA<FirstFrameEvent>()]);
        expect(rig.wakelock, [true]);
        rig.controller.dispose();
        expect(rig.wakelock, [true, false]);
      });
    });

    test('buildView delegates to the engine (black box before play)', () {
      fakeAsync((async) {
        final rig = Rig(async);
        final before = rig.controller.buildView();
        expect(before, isA<ColoredBox>());
        rig.play(liveTs);
        final view = rig.controller.buildView(aspect: AspectMode.ratio4x3);
        expect(view.key, const ValueKey('fake-exo-ratio4x3'));
        rig.controller.dispose();
      });
    });
  });

  group('fallbacks', () {
    test('exo error on an extension-less URL: HLS retry, then mpv', () {
      fakeAsync((async) {
        final rig = Rig(async)
          ..failsOn(EngineKind.exo)
          ..playsOn(EngineKind.mpv);
        rig.play(liveNoExt, key: 'ch9');
        async.elapse(sec);
        expect(rig.log, [
          'exo.create',
          'exo.open ${liveNoExt.url}',
          'exo.stop',
          'exo.open ${liveNoExt.url}',
          'exo.stop',
          'exo.dispose',
          'mpv.create',
          'mpv.open ${liveNoExt.url}',
        ]);
        final exo = rig.of(EngineKind.exo);
        expect(exo.opened.map((r) => r.isHls), [false, true]);
        expect(rig.controller.engineKind, EngineKind.mpv);
        expect(rig.controller.phase, PlaybackPhase.playing);
        expect(rig.engines.maxAlive, 1);
        // Automatic fallbacks are not saved as preferences.
        expect(rig.learned, isEmpty);
        rig.controller.dispose();
      });
    });

    test('exo error on a .ts URL goes straight to mpv', () {
      fakeAsync((async) {
        final rig = Rig(async)
          ..failsOn(EngineKind.exo)
          ..playsOn(EngineKind.mpv);
        rig.play(liveTs);
        async.elapse(sec);
        expect(rig.of(EngineKind.exo).count('open'), 1);
        expect(rig.controller.engineKind, EngineKind.mpv);
        rig.controller.dispose();
      });
    });

    test('an HLS request is never retried with the HLS hint', () {
      fakeAsync((async) {
        final rig = Rig(async)
          ..failsOn(EngineKind.exo)
          ..playsOn(EngineKind.mpv);
        rig.play(
          const StreamRequest(
            url: 'http://127.0.0.1/play/1',
            kind: PlayableKind.live,
            isHls: true,
          ),
        );
        async.elapse(sec);
        expect(rig.of(EngineKind.exo).count('open'), 1);
        expect(rig.controller.engineKind, EngineKind.mpv);
        rig.controller.dispose();
      });
    });

    test('mpv open error falls back to exo on Android', () {
      fakeAsync((async) {
        final rig = Rig(async)
          ..failsOn(EngineKind.mpv, 'Failed to open http://example.com/x')
          ..playsOn(EngineKind.exo);
        rig.play(movie);
        async.elapse(sec);
        expect(rig.controller.engineKind, EngineKind.exo);
        expect(rig.controller.phase, PlaybackPhase.playing);
        rig.controller.dispose();
      });
    });

    test('both engines fail: failed with the last message', () {
      fakeAsync((async) {
        final rig = Rig(async)
          ..failsOn(EngineKind.exo, 'exo says no')
          ..failsOn(EngineKind.mpv, 'mpv says no');
        rig.play(liveTs);
        async.elapse(sec);
        final c = rig.controller;
        expect(c.phase, PlaybackPhase.failed);
        expect(c.errorMessage, 'mpv says no');
        expect(rig.log.last, 'mpv.stop');
        expect(rig.engines.created, hasLength(2));
        // No reconnect loop after failing.
        async.elapse(const Duration(minutes: 5));
        expect(rig.engines.created, hasLength(2));
        expect(c.reconnectStatus.value, ReconnectStatus.idle);
        c.dispose();
      });
    });

    test('desktop: mpv failure fails without ever touching exo', () {
      fakeAsync((async) {
        final rig = Rig(async, platform: TargetPlatformKind.linux)
          ..failsOn(EngineKind.mpv, 'tls: handshake failed');
        rig.play(liveTs);
        async.elapse(sec);
        expect(rig.controller.phase, PlaybackPhase.failed);
        expect(rig.engines.created.map((e) => e.kind), [EngineKind.mpv]);
        rig.controller.dispose();
      });
    });

    test('mpv TLS error after playing switches to exo on Android', () {
      fakeAsync((async) {
        final rig = Rig(async)
          ..playsOn(EngineKind.mpv)
          ..playsOn(EngineKind.exo);
        rig.play(movie, key: 'm1');
        rig.engine.setState(position: const Duration(minutes: 7));
        rig.engine.emitError('tls: The TLS connection was non-properly closed');
        async.elapse(sec);
        expect(rig.controller.engineKind, EngineKind.exo);
        expect(
          rig.of(EngineKind.exo).lastRequest?.startAt,
          const Duration(minutes: 7),
        );
        expect(rig.statuses, isEmpty);
        rig.controller.dispose();
      });
    });

    test('non-fatal errors are ignored', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.exo);
        rig.play(liveTs);
        rig.engine.emitError('decoder glitch', fatal: false);
        async.elapse(const Duration(seconds: 5));
        expect(rig.controller.phase, PlaybackPhase.playing);
        expect(rig.engines.created, hasLength(1));
        expect(rig.statuses, isEmpty);
        rig.controller.dispose();
      });
    });
  });

  group('silent audio on exo', () {
    test('tracks present but none selected: reopen in mpv, learn it', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.mpv);
        rig.engines.onCreate = (e) {
          if (e.kind == EngineKind.exo) {
            e.audio = const [
              TrackInfo(id: '0', language: 'ar', codec: 'ac-3'),
              TrackInfo(id: '1', language: 'en', codec: 'mp2'),
            ];
            e.onOpen = (e, _) => e.emitFirstFrame();
          } else {
            e.onOpen = (e, _) => e.emitFirstFrame();
          }
        };
        rig.play(liveTs, key: 'ch-ac3');
        async.elapse(const Duration(milliseconds: 1999));
        expect(rig.controller.engineKind, EngineKind.exo);
        async.elapse(ms);
        async.flushMicrotasks();
        expect(rig.of(EngineKind.exo).calls, contains('audioTracks'));
        expect(rig.learned, [('ch-ac3', EngineKind.mpv)]);
        expect(rig.controller.engineKind, EngineKind.mpv);
        expect(rig.of(EngineKind.exo).disposed, isTrue);
        expect(rig.engines.maxAlive, 1);
        rig.controller.dispose();
      });
    });

    test('a selected track means audio works: stay on exo', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.engines.onCreate = (e) {
          e.audio = const [TrackInfo(id: '0', selected: true)];
          e.onOpen = (e, _) => e.emitFirstFrame();
        };
        rig.play(liveTs, key: 'ok');
        async.elapse(const Duration(seconds: 5));
        expect(rig.controller.engineKind, EngineKind.exo);
        expect(rig.learned, isEmpty);
        rig.controller.dispose();
      });
    });

    test('no audio tracks at all (radio-less video): stay on exo', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.exo);
        rig.play(liveTs);
        async.elapse(const Duration(seconds: 5));
        expect(rig.controller.engineKind, EngineKind.exo);
        rig.controller.dispose();
      });
    });

    test('zapping away before 2 s cancels the check', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.engines.onCreate = (e) {
          e.audio = const [TrackInfo(id: '0')];
          e.onOpen = (e, _) => e.emitFirstFrame();
        };
        rig.play(liveTs, key: 'a');
        async.elapse(sec);
        unawaited(rig.controller.stop());
        async.elapse(const Duration(seconds: 5));
        expect(rig.learned, isEmpty);
        expect(rig.of(EngineKind.exo).calls, isNot(contains('audioTracks')));
        rig.controller.dispose();
      });
    });

    test('if mpv then fails, exo comes back instead of an error', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.engines.onCreate = (e) {
          if (e.kind == EngineKind.exo) {
            e.audio = const [TrackInfo(id: '0')];
            e.onOpen = (e, _) => e.emitFirstFrame();
          } else {
            e.onOpen = (e, _) => e.emitError('Failed to open');
          }
        };
        rig.play(liveTs, key: 'x');
        async.elapse(const Duration(seconds: 3));
        expect(rig.controller.engineKind, EngineKind.exo);
        expect(rig.controller.phase, PlaybackPhase.playing);
        // Checked once per item: no ping-pong.
        async.elapse(const Duration(seconds: 10));
        expect(rig.engines.created.map((e) => e.kind), [
          EngineKind.exo,
          EngineKind.mpv,
          EngineKind.exo,
        ]);
        rig.controller.dispose();
      });
    });
  });

  group('manual switch', () {
    test('toggles engines, learns the choice, keeps one instance', () {
      fakeAsync((async) {
        final rig = Rig(async)
          ..playsOn(EngineKind.exo)
          ..playsOn(EngineKind.mpv);
        rig.play(liveTs, key: 'ch1');
        unawaited(rig.controller.switchEngine());
        async.elapse(sec);
        expect(rig.controller.engineKind, EngineKind.mpv);
        unawaited(rig.controller.switchEngine());
        async.elapse(sec);
        expect(rig.controller.engineKind, EngineKind.exo);
        expect(rig.learned, [('ch1', EngineKind.mpv), ('ch1', EngineKind.exo)]);
        expect(rig.engines.maxAlive, 1);
        expect(rig.engines.alive, 1);
        expect(rig.log.where((l) => l.endsWith('dispose')), [
          'exo.dispose',
          'mpv.dispose',
        ]);
        rig.controller.dispose();
      });
    });

    test('VOD switch resumes at the current position', () {
      fakeAsync((async) {
        final rig = Rig(async)
          ..playsOn(EngineKind.exo)
          ..playsOn(EngineKind.mpv);
        rig.play(movie, key: 'm1');
        rig.engine.setState(position: const Duration(minutes: 12));
        unawaited(rig.controller.switchEngine());
        async.elapse(sec);
        expect(
          rig.of(EngineKind.exo).lastRequest?.startAt,
          const Duration(minutes: 12),
        );
        rig.controller.dispose();
      });
    });

    test('no-op on desktop', () {
      fakeAsync((async) {
        final rig = Rig(async, platform: TargetPlatformKind.windows)
          ..playsOn(EngineKind.mpv);
        rig.play(liveTs, key: 'ch1');
        unawaited(rig.controller.switchEngine());
        async.elapse(sec);
        expect(rig.engines.created, hasLength(1));
        expect(rig.learned, isEmpty);
        rig.controller.dispose();
      });
    });
  });

  group('reconnecting', () {
    test('error after playing: watchdog reopens the same engine', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.exo);
        rig.play(liveTs, maxConnections: 1);
        async.elapse(sec);
        rig.log.clear();
        rig.engine.emitError('Source error');
        async.flushMicrotasks();
        expect(
          rig.controller.reconnectStatus.value,
          const ReconnectWaiting(
            attempt: 1,
            maxAttempts: 8,
            delay: sec,
            reason: ReconnectReason.error,
          ),
        );
        async.elapse(sec);
        expect(rig.log, ['exo.stop']);
        async.elapse(const Duration(milliseconds: 150));
        expect(rig.log, ['exo.stop', 'exo.open ${liveTs.url}']);
        expect(rig.controller.reconnectStatus.value, ReconnectStatus.idle);
        expect(rig.controller.phase, PlaybackPhase.playing);
        rig.controller.dispose();
      });
    });

    test('live ended triggers a reconnect', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.exo);
        rig.play(liveTs);
        rig.engine.emitEnded();
        async.flushMicrotasks();
        expect(rig.controller.reconnectStatus.value, isA<ReconnectWaiting>());
        async.elapse(sec);
        expect(rig.engine.count('open'), 2);
        rig.controller.dispose();
      });
    });

    test('gives up after 8 attempts and fails', () {
      fakeAsync((async) {
        final rig = Rig(async);
        var opens = 0;
        rig.engines.onCreate = (e) => e.onOpen = (e, _) {
          opens++;
          if (opens == 1) {
            e.emitFirstFrame();
          } else {
            e.emitError('Source error');
          }
        };
        rig.play(liveTs);
        rig.engine.emitError('Source error');
        async.elapse(const Duration(minutes: 3));
        expect(opens, 9);
        expect(rig.controller.reconnectStatus.value, const ReconnectGaveUp(8));
        expect(rig.controller.phase, PlaybackPhase.failed);
        expect(rig.controller.errorMessage, contains('gave up'));
        expect(rig.engines.created, hasLength(1));
        rig.controller.dispose();
      });
    });

    test('VOD reconnect resumes from the last position', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.mpv);
        rig.play(movie, key: 'm1');
        rig.engine.setState(position: const Duration(minutes: 33));
        rig.engine.emitError('Source error');
        async.elapse(const Duration(seconds: 2));
        expect(rig.engine.lastRequest?.startAt, const Duration(minutes: 33));
        rig.controller.dispose();
      });
    });

    test('offline holds reconnecting until the network returns', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.exo);
        rig.play(liveTs);
        rig.controller.setOnline(false);
        rig.engine.emitError('Source error');
        async.elapse(const Duration(minutes: 2));
        expect(rig.engine.count('open'), 1);
        expect(
          (rig.controller.reconnectStatus.value as ReconnectWaiting).paused,
          isTrue,
        );
        rig.controller.setOnline(true);
        async.flushMicrotasks();
        expect(rig.engine.count('open'), 2);
        rig.controller.dispose();
      });
    });
  });

  group('held connection (HTTP 4xx right after a zap)', () {
    test('retried after 1 s without counting as a failure', () {
      fakeAsync((async) {
        final rig = Rig(async);
        var opens = 0;
        rig.engines.onCreate = (e) => e.onOpen = (e, _) {
          opens++;
          if (opens == 1) {
            e.emitError('HTTP 403', httpStatus: 403);
          } else {
            e.emitFirstFrame();
          }
        };
        rig.play(liveTs, maxConnections: 1);
        async.elapse(const Duration(milliseconds: 150));
        expect(opens, 1);
        async.elapse(sec);
        expect(opens, 1);
        async.elapse(const Duration(milliseconds: 150));
        expect(opens, 2);
        expect(rig.controller.phase, PlaybackPhase.playing);
        expect(rig.controller.engineKind, EngineKind.exo);
        expect(rig.engines.created, hasLength(1));
        expect(rig.statuses, isEmpty);
        rig.controller.dispose();
      });
    });

    test('after two retries the normal fallback takes over', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.mpv);
        rig.engines.onCreate = (e) {
          e.onOpen = e.kind == EngineKind.exo
              ? (e, _) => e.emitError('HTTP 403', httpStatus: 403)
              : (e, _) => e.emitFirstFrame();
        };
        rig.play(liveTs);
        async.elapse(const Duration(seconds: 5));
        expect(rig.of(EngineKind.exo).count('open'), 3);
        expect(rig.controller.engineKind, EngineKind.mpv);
        rig.controller.dispose();
      });
    });
  });

  group('VOD', () {
    test('progress saved every 10 s and on stop, keyed by item', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.mpv);
        rig.play(movie, key: 'movie-9');
        for (var s = 1; s <= 25; s++) {
          rig.engine.setState(
            position: Duration(seconds: s),
            duration: const Duration(minutes: 90),
          );
          async.elapse(sec);
        }
        expect(rig.progress.map((p) => p.$2.inSeconds), [10, 20]);
        expect(rig.progress.first.$1, 'movie-9');
        expect(rig.progress.first.$3, const Duration(minutes: 90));
        unawaited(rig.controller.stop());
        async.flushMicrotasks();
        expect(rig.progress.last.$2.inSeconds, 25);
        expect(rig.controller.phase, PlaybackPhase.idle);
        expect(rig.engine.calls.last, 'stop');
        expect(rig.engine.disposed, isFalse);
        rig.controller.dispose();
      });
    });

    test('pause saves progress', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.mpv);
        rig.play(movie, key: 'm');
        rig.engine.setState(position: const Duration(seconds: 77));
        unawaited(rig.controller.togglePlayPause());
        async.flushMicrotasks();
        expect(rig.engine.calls, contains('pause'));
        expect(rig.progress.single.$2, const Duration(seconds: 77));
        unawaited(rig.controller.togglePlayPause());
        async.flushMicrotasks();
        expect(rig.engine.calls.last, 'play');
        rig.controller.dispose();
      });
    });

    test('ended: phase ended, final progress saved, no reconnect', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.mpv);
        rig.play(movie, key: 'm');
        rig.engine.setState(
          position: const Duration(minutes: 90),
          duration: const Duration(minutes: 90),
        );
        rig.engine.emitEnded();
        async.flushMicrotasks();
        expect(rig.controller.phase, PlaybackPhase.ended);
        expect(rig.progress.last.$2, const Duration(minutes: 90));
        async.elapse(const Duration(minutes: 1));
        expect(rig.engine.count('open'), 1);
        rig.controller.dispose();
      });
    });

    test('seeking back after the end resumes monitoring', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.mpv);
        rig.play(movie, key: 'm');
        rig.engine.emitEnded();
        async.flushMicrotasks();
        expect(rig.controller.phase, PlaybackPhase.ended);
        unawaited(rig.controller.seek(const Duration(minutes: 10)));
        async.flushMicrotasks();
        expect(rig.controller.phase, PlaybackPhase.playing);
        rig.engine.emitError('Source error');
        async.elapse(sec);
        expect(rig.engine.count('open'), 2);
        rig.controller.dispose();
      });
    });

    test('live items never report progress', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.exo);
        rig.play(liveTs, key: 'ch');
        rig.engine.setState(position: const Duration(seconds: 30));
        async.elapse(const Duration(seconds: 30));
        unawaited(rig.controller.stop());
        async.flushMicrotasks();
        expect(rig.progress, isEmpty);
        rig.controller.dispose();
      });
    });

    test('seek and tracks pass through to the engine', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.mpv);
        rig.engines.onCreate = (e) {
          e.audio = const [TrackInfo(id: 'a1', language: 'ar')];
          e.subtitles = const [TrackInfo(id: 's1', language: 'en')];
          e.onOpen = (e, _) => e.emitFirstFrame();
        };
        rig.play(movie);
        final c = rig.controller;
        unawaited(c.seek(const Duration(seconds: 90)));
        unawaited(c.selectAudio('a1'));
        unawaited(c.selectSubtitle(null));
        List<TrackInfo>? audio;
        List<TrackInfo>? subs;
        Map<String, String>? stats;
        unawaited(c.audioTracks().then((v) => audio = v));
        unawaited(c.subtitleTracks().then((v) => subs = v));
        unawaited(c.stats().then((v) => stats = v));
        async.flushMicrotasks();
        expect(rig.engine.calls, containsAll(['seek 90000', 'selectAudio a1']));
        expect(rig.engine.selectedSubtitle, isNull);
        expect(audio?.single.id, 'a1');
        expect(subs?.single.id, 's1');
        expect(stats, containsPair('engine', 'mpv'));
        expect(stats, containsPair('ttff', '0 ms'));
        expect(stats, containsPair('reconnects', '0'));
        c.dispose();
      });
    });
  });

  group('app lifecycle', () {
    test('live: background stops the stream, foreground reopens', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.exo);
        rig.play(liveTs);
        async.elapse(sec);
        unawaited(rig.controller.onBackground());
        async.flushMicrotasks();
        expect(rig.log.last, 'exo.stop');
        expect(rig.wakelock.last, isFalse);
        // No reconnecting while in the background.
        async.elapse(const Duration(minutes: 1));
        expect(rig.engine.count('open'), 1);

        unawaited(rig.controller.onForeground());
        async.flushMicrotasks();
        expect(rig.engine.count('open'), 2);
        expect(rig.controller.phase, PlaybackPhase.playing);
        rig.controller.dispose();
      });
    });

    test('VOD: background pauses and saves, foreground resumes', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.mpv);
        rig.play(movie, key: 'm');
        rig.engine.setState(position: const Duration(seconds: 45));
        unawaited(rig.controller.onBackground());
        async.flushMicrotasks();
        expect(rig.engine.calls.last, 'pause');
        expect(rig.engine.calls, isNot(contains('stop')));
        expect(rig.progress.single.$2, const Duration(seconds: 45));

        unawaited(rig.controller.onForeground());
        async.flushMicrotasks();
        expect(rig.engine.calls.last, 'play');
        expect(rig.engine.count('open'), 1);
        rig.controller.dispose();
      });
    });

    test('paused VOD stays paused on return', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.mpv);
        rig.play(movie, key: 'm');
        unawaited(rig.controller.pause());
        async.flushMicrotasks();
        unawaited(rig.controller.onBackground());
        async.flushMicrotasks();
        unawaited(rig.controller.onForeground());
        async.flushMicrotasks();
        expect(rig.engine.calls.where((c) => c == 'play'), isEmpty);
        rig.controller.dispose();
      });
    });

    test('lifecycle calls without a session are no-ops', () {
      fakeAsync((async) {
        final rig = Rig(async);
        unawaited(rig.controller.onBackground());
        unawaited(rig.controller.onForeground());
        async.flushMicrotasks();
        expect(rig.engines.created, isEmpty);
        rig.controller.dispose();
      });
    });
  });

  group('retry and teardown', () {
    test('retry() replays the failed item from the start', () {
      fakeAsync((async) {
        final rig = Rig(async)
          ..failsOn(EngineKind.exo)
          ..failsOn(EngineKind.mpv);
        rig.play(liveTs, key: 'ch1');
        async.elapse(sec);
        expect(rig.controller.phase, PlaybackPhase.failed);
        rig.engines.onCreate = (e) => e.onOpen = (e, _) => e.emitFirstFrame();
        unawaited(rig.controller.retry());
        async.elapse(sec);
        expect(rig.controller.phase, PlaybackPhase.playing);
        expect(rig.controller.errorMessage, isNull);
        expect(rig.controller.itemKey, 'ch1');
        expect(rig.engines.maxAlive, 1);
        rig.controller.dispose();
      });
    });

    test('notifies listeners on phase and engine changes', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.exo);
        var notified = 0;
        rig.controller.addListener(() => notified++);
        rig.play(liveTs);
        expect(notified, greaterThanOrEqualTo(3));
        rig.controller.dispose();
      });
    });

    test('dispose disposes the engine and ignores later calls', () {
      fakeAsync((async) {
        final rig = Rig(async)..playsOn(EngineKind.exo);
        rig.play(liveTs);
        rig.controller.dispose();
        async.flushMicrotasks();
        expect(rig.engine.disposed, isTrue);
        expect(rig.engines.alive, 0);
        unawaited(rig.controller.play(liveTs2));
        unawaited(rig.controller.stop());
        async.elapse(sec);
        expect(rig.engines.created, hasLength(1));
        expect(async.pendingTimers, isEmpty);
      });
    });
  });
}
