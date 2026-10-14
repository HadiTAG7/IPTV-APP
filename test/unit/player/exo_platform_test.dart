import 'dart:async';
import 'dart:ui' show Size;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/engine/engine_policy.dart';
import 'package:iptv_player/player/engine/exo_engine.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/player/session/playback_controller.dart';
import 'package:iptv_player/player/session/progress_saver.dart';
import 'package:iptv_player/player/session/reconnect_watchdog.dart';
import 'package:iptv_player/sources/models.dart';
// Comes with video_player (pinned in pubspec.lock); only tests fake it.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'fake_async_clock.dart';

/// ExoPlayer's `C.TIME_UNSET` (Long.MIN_VALUE + 1).
const timeUnset = -9223372036854775807;

/// Plays the part of video_player_android 2.12.2 on top of ExoPlayer, so a
/// real [VideoPlayerController] runs its own clamping and completion logic.
///
/// The initialized event carries `Duration(milliseconds: getDuration())`
/// exactly like the plugin (C.TIME_UNSET wraps to +1 ms), `isPlaying` events
/// follow ExoPlayer's onIsPlayingChanged, and the position advances in fake
/// time while playing.
class FakeExoPlatform extends VideoPlayerPlatform {
  FakeExoPlatform(this.async, {required this.durationMs});

  final FakeAsync async;

  /// What `ExoPlayer.getDuration()` returns.
  final int durationMs;
  final calls = <String>[];

  /// While true the clock stands still although ExoPlayer still plays.
  bool frozen = false;

  final _events = <int, StreamController<VideoEvent>>{};
  int _id = 0;
  bool _playing = false;
  Duration _base = Duration.zero;
  Duration? _since;

  Duration get position {
    final since = _since;
    if (since == null || frozen) return _base;
    return _base + (async.elapsed - since);
  }

  void _add(VideoEvent e) {
    final c = _events[_id];
    if (c != null && !c.isClosed) c.add(e);
  }

  void _setPlaying(bool playing) {
    if (_playing == playing) return;
    _playing = playing;
    if (playing) {
      _since = async.elapsed;
    } else {
      _base = position;
      _since = null;
    }
    _add(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: playing,
      ),
    );
  }

  /// STATE_ENDED: the plugin sends `completed`, then isPlaying goes false.
  void end() {
    _add(VideoEvent(eventType: VideoEventType.completed));
    _setPlaying(false);
  }

  /// STATE_BUFFERING while playing.
  void startBuffering() {
    _add(VideoEvent(eventType: VideoEventType.bufferingStart));
    _setPlaying(false);
  }

  /// STATE_READY again; isPlaying follows separately ([playingAgain]).
  void bufferingDone() =>
      _add(VideoEvent(eventType: VideoEventType.bufferingEnd));

  void playingAgain() => _setPlaying(true);

  /// The position jumps (e.g. a poll that overshoots the end).
  void jumpTo(Duration p) {
    _base = p;
    if (_since != null) _since = async.elapsed;
  }

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    calls.add('create');
    // Without onCancel, cancel() returns a root-zone future that never
    // completes under fake_async, which would stall controller.dispose().
    _events[++_id] = StreamController<VideoEvent>(onCancel: () async {});
    _playing = false;
    _base = Duration.zero;
    _since = null;
    return _id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    scheduleMicrotask(() {
      _add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: Duration(milliseconds: durationMs),
          size: const Size(1920, 1080),
          rotationCorrection: 0,
        ),
      );
    });
    return _events[playerId]!.stream;
  }

  @override
  Future<void> play(int playerId) async {
    calls.add('play');
    _setPlaying(true);
  }

  @override
  Future<void> pause(int playerId) async {
    calls.add('pause');
    _setPlaying(false);
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    calls.add('seekTo ${position.inMilliseconds}');
    jumpTo(position);
  }

  @override
  Future<Duration> getPosition(int playerId) async => position;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool preventsDisplaySleep,
  ) async {}

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose');
    // Not awaited: close() after a cancel also returns a root-zone future.
    unawaited(_events.remove(playerId)?.close());
  }
}

const liveTs = StreamRequest(
  url: 'http://127.0.0.1:8080/live/user/pass/101.ts',
  kind: PlayableKind.live,
);
const catchUp = StreamRequest(
  url: 'http://example.com/timeshift/user/pass/60/2026-01-01:20-00/101.ts',
  kind: PlayableKind.movie,
  startAt: Duration(minutes: 10),
);
const movie = StreamRequest(
  url: 'http://example.com/movie/user/pass/9.mp4',
  kind: PlayableKind.movie,
);

const sec = Duration(seconds: 1);

/// An [ExoEngine] on the default (real) controller factory.
class EngineRig {
  EngineRig(this.async, {int durationMs = timeUnset})
    : platform = FakeExoPlatform(async, durationMs: durationMs) {
    VideoPlayerPlatform.instance = platform;
    engine.events.listen(events.add);
  }

  final FakeAsync async;
  final FakeExoPlatform platform;
  final engine = ExoEngine();
  final events = <EngineEvent>[];

  Iterable<EndedEvent> get ended => events.whereType<EndedEvent>();

  void open(StreamRequest r) {
    unawaited(engine.open(r));
    async.flushMicrotasks();
  }

  void dispose() {
    unawaited(engine.dispose());
    async.flushMicrotasks();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final original = VideoPlayerPlatform.instance;
  tearDown(() => VideoPlayerPlatform.instance = original);

  test('C.TIME_UNSET reaches Dart as a 1 ms duration', () {
    expect(Duration(milliseconds: timeUnset), const Duration(milliseconds: 1));
  });

  group('ExoEngine on a stream of unknown length', () {
    test('live TS never ends and follows the raw position', () {
      fakeAsync((async) {
        final rig = EngineRig(async)..open(liveTs);
        async.elapse(const Duration(seconds: 30));
        // What video_player itself makes of the stream:
        final v = rig.engine.controller!.value;
        expect(v.duration, const Duration(milliseconds: 1));
        expect(v.position, const Duration(milliseconds: 1));
        expect(v.isCompleted, isTrue);
        expect(v.isPlaying, isTrue);

        expect(rig.events, [isA<FirstFrameEvent>()]);
        final s = rig.engine.state.value;
        expect(s.duration, Duration.zero);
        expect(s.playing, isTrue);
        expect(s.position, greaterThanOrEqualTo(const Duration(seconds: 29)));
        rig.dispose();
      });
    });

    test('VOD without a length: no seek, not ended, not finished', () {
      fakeAsync((async) {
        final rig = EngineRig(async)..open(catchUp);
        async.elapse(const Duration(seconds: 5));
        expect(rig.events, [isA<FirstFrameEvent>()]);
        final s = rig.engine.state.value;
        expect(s.duration, Duration.zero);
        expect(s.position, const Duration(seconds: 5));
        expect(ProgressSaver.isFinished(s.position, s.duration), isFalse);
        // A seek would be clamped to the fake 1 ms anyway.
        expect(
          rig.platform.calls.where((c) => c.startsWith('seekTo')),
          isEmpty,
        );
        rig.dispose();
      });
    });

    test('a real end is reported once', () {
      fakeAsync((async) {
        final rig = EngineRig(async)..open(catchUp);
        async.elapse(const Duration(seconds: 5));
        rig.platform.end();
        async.elapse(const Duration(seconds: 3));
        expect(rig.ended, hasLength(1));
        expect(rig.engine.state.value.playing, isFalse);
        rig.dispose();
      });
    });

    test('rebuffering, even with a lagging isPlaying, is not an end', () {
      fakeAsync((async) {
        final rig = EngineRig(async)..open(liveTs);
        // Polls run every 500 ms from t = 0.
        async.elapse(const Duration(milliseconds: 10100));
        rig.platform.startBuffering();
        async.elapse(const Duration(milliseconds: 2300));
        expect(rig.engine.state.value.buffering, isTrue);
        // READY but not yet playing: looks like an end for one poll (12.5 s).
        rig.platform.bufferingDone();
        async.elapse(const Duration(milliseconds: 400));
        expect(rig.engine.controller!.value.isCompleted, isTrue);
        rig.platform.playingAgain();
        async.elapse(const Duration(seconds: 5));
        expect(rig.ended, isEmpty);
        expect(rig.engine.state.value.playing, isTrue);
        rig.dispose();
      });
    });

    test('pause and resume neither end nor restart the stream', () {
      fakeAsync((async) {
        final rig = EngineRig(async)..open(catchUp);
        async.elapse(const Duration(seconds: 5));
        unawaited(rig.engine.pause());
        async.elapse(const Duration(seconds: 5));
        expect(rig.ended, isEmpty);
        expect(rig.engine.state.value.playing, isFalse);
        unawaited(rig.engine.play());
        async.elapse(const Duration(seconds: 2));
        // video_player seeks to 0 when position == duration (1 ms == 1 ms).
        expect(
          rig.platform.calls.where((c) => c.startsWith('seekTo')),
          isEmpty,
        );
        expect(rig.engine.state.value.position, const Duration(seconds: 7));
        expect(rig.ended, isEmpty);
        rig.dispose();
      });
    });
  });

  test('known length: overshooting the end while playing is not the end', () {
    fakeAsync((async) {
      final rig = EngineRig(async, durationMs: 90 * 60 * 1000)..open(movie);
      async.elapse(sec);
      rig.platform.jumpTo(const Duration(minutes: 90, milliseconds: 50));
      async.elapse(sec);
      final v = rig.engine.controller!.value;
      expect(v.isCompleted && v.isPlaying, isTrue);
      expect(rig.ended, isEmpty);
      rig.platform.end();
      async.elapse(sec);
      expect(rig.ended, hasLength(1));
      expect(rig.engine.state.value.duration, const Duration(minutes: 90));
      rig.dispose();
    });
  });

  group('PlaybackController with ExoEngine on live TS', () {
    PlaybackController controllerFor(FakeAsync async) => PlaybackController(
      factory: (_) => ExoEngine(),
      policyInput: () =>
          const EnginePolicyInput(platform: TargetPlatformKind.android),
      clock: FakeAsyncClock(async),
    );

    test('a healthy channel keeps playing without reconnecting', () {
      fakeAsync((async) {
        final platform = FakeExoPlatform(async, durationMs: timeUnset);
        VideoPlayerPlatform.instance = platform;
        final c = controllerFor(async);
        final statuses = <ReconnectStatus>[];
        c.reconnectStatus.addListener(
          () => statuses.add(c.reconnectStatus.value),
        );
        unawaited(c.play(liveTs, itemKey: 'ch1'));
        async.elapse(const Duration(minutes: 6));
        expect(c.phase, PlaybackPhase.playing);
        expect(c.engineKind, EngineKind.exo);
        expect(statuses, isEmpty);
        expect(platform.calls.where((x) => x == 'create'), hasLength(1));
        c.dispose();
        async.flushMicrotasks();
      });
    });

    test('a frozen picture is still caught as stalled', () {
      fakeAsync((async) {
        final platform = FakeExoPlatform(async, durationMs: timeUnset);
        VideoPlayerPlatform.instance = platform;
        final c = controllerFor(async);
        final statuses = <ReconnectStatus>[];
        c.reconnectStatus.addListener(
          () => statuses.add(c.reconnectStatus.value),
        );
        unawaited(c.play(liveTs, itemKey: 'ch1'));
        async.elapse(const Duration(seconds: 20));
        expect(statuses, isEmpty);
        platform.frozen = true;
        async.elapse(const Duration(seconds: 17));
        expect(
          statuses.first,
          isA<ReconnectWaiting>().having(
            (s) => s.reason,
            'reason',
            ReconnectReason.stalled,
          ),
        );
        c.dispose();
        async.flushMicrotasks();
      });
    });

    test('a live stream that really ends is reconnected', () {
      fakeAsync((async) {
        final platform = FakeExoPlatform(async, durationMs: timeUnset);
        VideoPlayerPlatform.instance = platform;
        final c = controllerFor(async);
        final statuses = <ReconnectStatus>[];
        c.reconnectStatus.addListener(
          () => statuses.add(c.reconnectStatus.value),
        );
        unawaited(c.play(liveTs, itemKey: 'ch1'));
        async.elapse(const Duration(seconds: 10));
        platform.end();
        async.elapse(const Duration(seconds: 3));
        expect(
          statuses.first,
          isA<ReconnectWaiting>().having(
            (s) => s.reason,
            'reason',
            ReconnectReason.ended,
          ),
        );
        expect(platform.calls, containsAllInOrder(['dispose', 'create']));
        expect(platform.calls.where((x) => x == 'create'), hasLength(2));
        expect(c.phase, PlaybackPhase.playing);
        c.dispose();
        async.flushMicrotasks();
      });
    });
  });
}
