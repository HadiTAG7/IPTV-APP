import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/net/http.dart';
import 'package:iptv_player/player/engine/exo_engine.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:video_player/video_player.dart';

/// A `video_player` controller that never touches the platform.
class FakeVpc extends VideoPlayerController {
  FakeVpc(
    super.url, {
    required super.httpHeaders,
    required super.formatHint,
    required super.viewType,
  }) : super.networkUrl();

  final calls = <String>[];

  /// Completes initialize(); errors make it fail like ExoPlayer does.
  final init = Completer<void>();
  Duration reportedDuration = const Duration(minutes: 90);
  List<VideoAudioTrack> tracks = const [];
  bool disposed = false;

  void fail(String message) {
    value = VideoPlayerValue.erroneous(message);
    if (!init.isCompleted) {
      init.completeError(
        PlatformException(code: 'VideoError', message: message),
      );
    }
  }

  /// Finishes initialize(). A disposed controller only completes the future
  /// (a late platform reply), as setting its value would be illegal.
  void ready({Size size = const Size(1920, 1080)}) {
    if (!disposed) {
      value = value.copyWith(
        isInitialized: true,
        duration: reportedDuration,
        size: size,
      );
    }
    init.complete();
  }

  @override
  Future<void> initialize() {
    calls.add('initialize');
    return init.future;
  }

  @override
  Future<void> play() async {
    calls.add('play');
    // Like video_player: playing clears the completed flag.
    value = value.copyWith(isPlaying: true, isCompleted: false);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    calls.add('seekTo ${position.inSeconds}');
    value = value.copyWith(position: position);
  }

  @override
  Future<List<VideoAudioTrack>> getAudioTracks() async => tracks;

  @override
  Future<void> selectAudioTrack(String trackId) async {
    calls.add('selectAudioTrack $trackId');
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    disposed = true;
    await super.dispose();
  }
}

class Rig {
  Rig({VideoViewType viewType = VideoViewType.textureView}) {
    engine = ExoEngine(
      viewType: viewType,
      controllerFactory:
          (
            uri, {
            required httpHeaders,
            required formatHint,
            required viewType,
          }) {
            final c = FakeVpc(
              uri,
              httpHeaders: httpHeaders,
              formatHint: formatHint,
              viewType: viewType,
            );
            controllers.add(c);
            onCreate?.call(c);
            return c;
          },
    );
    engine.events.listen(events.add);
  }

  late final ExoEngine engine;
  final controllers = <FakeVpc>[];
  final events = <EngineEvent>[];
  void Function(FakeVpc c)? onCreate;

  FakeVpc get c => controllers.last;
}

const live = StreamRequest(
  url: 'http://127.0.0.1:8080/live/user/secret/1.ts',
  kind: PlayableKind.live,
  headers: {'Referer': 'http://example.com/'},
);
const movie = StreamRequest(
  url: 'http://example.com/movie/user/secret/9.mp4',
  kind: PlayableKind.movie,
  headers: {'user-agent': 'Custom/1.0'},
  startAt: Duration(minutes: 42),
);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('mapExoValue', () {
    const ready = VideoPlayerValue(
      duration: Duration(minutes: 90),
      isInitialized: true,
      size: Size(1280, 720),
      position: Duration(seconds: 5),
    );

    test('VOD passes duration, size, first frame from position', () {
      final s = mapExoValue(ready, isLive: false);
      expect(s.duration, const Duration(minutes: 90));
      expect(s.videoSize, const Size(1280, 720));
      expect(s.hasFirstFrame, isTrue);
      expect(s.buffering, isFalse);
    });

    test('live, zero, negative and absurd durations become zero', () {
      expect(mapExoValue(ready, isLive: true).duration, Duration.zero);
      for (final d in [
        Duration.zero,
        const Duration(milliseconds: -9223372036854),
        const Duration(days: 400),
      ]) {
        expect(
          mapExoValue(ready.copyWith(duration: d), isLive: false).duration,
          Duration.zero,
        );
      }
    });

    test('uninitialized is buffering, has no frame or size', () {
      final s = mapExoValue(
        const VideoPlayerValue(duration: Duration.zero),
        isLive: true,
      );
      expect(s.buffering, isTrue);
      expect(s.hasFirstFrame, isFalse);
      expect(s.videoSize, isNull);
    });

    test('initialized at 0 s counts as a frame only once playing', () {
      final v = ready.copyWith(position: Duration.zero);
      expect(mapExoValue(v, isLive: true).hasFirstFrame, isFalse);
      expect(
        mapExoValue(v.copyWith(isPlaying: true), isLive: true).hasFirstFrame,
        isTrue,
      );
    });

    test('errors are not buffering', () {
      expect(
        mapExoValue(
          const VideoPlayerValue.erroneous('x'),
          isLive: true,
        ).buffering,
        isFalse,
      );
    });
  });

  test('withDefaultUserAgent keeps a custom UA, adds the app one', () {
    expect(withDefaultUserAgent({'User-Agent': 'X'}), {'User-Agent': 'X'});
    expect(withDefaultUserAgent({'user-agent': 'X'}), {'user-agent': 'X'});
    expect(withDefaultUserAgent({'Referer': 'r'}), {
      'Referer': 'r',
      'User-Agent': kDefaultUserAgent,
    });
  });

  group('open', () {
    test('creates the controller with headers, hint and view type', () async {
      final rig = Rig(viewType: VideoViewType.platformView);
      await rig.engine.open(live.copyWith(isHls: true));
      final c = rig.c;
      expect(c.dataSource, live.url);
      expect(c.httpHeaders['Referer'], 'http://example.com/');
      expect(c.httpHeaders['User-Agent'], kDefaultUserAgent);
      expect(c.formatHint, VideoFormat.hls);
      expect(c.viewType, VideoViewType.platformView);
      expect(rig.engine.state.value.buffering, isTrue);
      await rig.engine.dispose();
    });

    test('no hint for non-HLS requests', () async {
      final rig = Rig();
      await rig.engine.open(live);
      expect(rig.c.formatHint, isNull);
      expect(rig.c.viewType, VideoViewType.textureView);
      await rig.engine.dispose();
    });

    test('open returns before initialize completes, then plays', () async {
      final rig = Rig();
      await rig.engine.open(live);
      expect(rig.c.calls, ['initialize']);
      rig.c.ready();
      await settle();
      expect(rig.c.calls, ['initialize', 'play']);
      final s = rig.engine.state.value;
      expect(s.playing, isTrue);
      expect(s.duration, Duration.zero, reason: 'live');
      expect(s.videoSize, const Size(1920, 1080));
      expect(s.hasFirstFrame, isTrue);
      expect(rig.events.whereType<FirstFrameEvent>(), hasLength(1));
      await rig.engine.dispose();
    });

    test('VOD seeks to startAt before playing', () async {
      final rig = Rig();
      await rig.engine.open(movie);
      expect(rig.c.httpHeaders, {'user-agent': 'Custom/1.0'});
      rig.c.ready();
      await settle();
      expect(rig.c.calls, ['initialize', 'seekTo 2520', 'play']);
      expect(rig.engine.state.value.duration, const Duration(minutes: 90));
      await rig.engine.dispose();
    });

    test('live ignores startAt', () async {
      final rig = Rig();
      await rig.engine.open(live.copyWith(startAt: const Duration(minutes: 1)));
      rig.c.ready();
      await settle();
      expect(rig.c.calls, ['initialize', 'play']);
      await rig.engine.dispose();
    });

    test(
      'first frame is emitted once even as the value keeps changing',
      () async {
        final rig = Rig();
        await rig.engine.open(movie);
        rig.c.ready();
        await settle();
        for (var i = 0; i < 5; i++) {
          await rig.c.seekTo(Duration(seconds: 100 + i));
        }
        await settle();
        expect(rig.events.whereType<FirstFrameEvent>(), hasLength(1));
        await rig.engine.dispose();
      },
    );

    test(
      'reopen disposes the old controller before creating the next',
      () async {
        final rig = Rig();
        final order = <String>[];
        rig.onCreate = (c) => order.add('create ${rig.controllers.length}');
        await rig.engine.open(live);
        final first = rig.c;
        first.ready();
        await settle();
        await rig.engine.open(
          live.copyWith(url: 'http://127.0.0.1/live/u/p/2.ts'),
        );
        expect(first.calls, ['initialize', 'play', 'pause', 'dispose']);
        expect(first.disposed, isTrue);
        expect(rig.controllers, hasLength(2));
        expect(order, ['create 1', 'create 2']);
        expect(rig.engine.controller, same(rig.c));
        await rig.engine.dispose();
      },
    );

    test('a stale initialize never plays after a newer open', () async {
      final rig = Rig();
      await rig.engine.open(live);
      final first = rig.c;
      await rig.engine.open(live.copyWith(url: 'http://127.0.0.1/2.ts'));
      first.ready();
      await settle();
      expect(first.calls, isNot(contains('play')));
      expect(rig.events, isEmpty);
      await rig.engine.dispose();
    });

    test('invalid URL reports an error instead of throwing', () async {
      final rig = Rig();
      await rig.engine.open(
        const StreamRequest(url: 'http://[::1', kind: PlayableKind.live),
      );
      await settle();
      expect(rig.controllers, isEmpty);
      expect(rig.events.single, isA<ErrorEvent>());
      await rig.engine.dispose();
    });
  });

  group('errors and end', () {
    test('initialize failure: one redacted error with HTTP status', () async {
      final rig = Rig();
      await rig.engine.open(live);
      rig.c.fail(
        'Source error: InvalidResponseCodeException: Response code: 403 '
        'for http://127.0.0.1:8080/live/user/secret/1.ts',
      );
      await settle();
      final errors = rig.events.whereType<ErrorEvent>().toList();
      expect(errors, hasLength(1));
      expect(errors.single.httpStatus, 403);
      expect(errors.single.fatal, isTrue);
      expect(errors.single.message, isNot(contains('secret')));
      expect(errors.single.message, contains('/live/***/***/1.ts'));
      expect(rig.engine.state.value.buffering, isFalse);
      expect(rig.c.calls, isNot(contains('play')));
      await rig.engine.dispose();
    });

    test('mid-stream error after playing', () async {
      final rig = Rig();
      await rig.engine.open(live);
      rig.c.ready();
      await settle();
      rig.c.value = const VideoPlayerValue.erroneous('Source error');
      await settle();
      expect(rig.events.last, isA<ErrorEvent>());
      expect(rig.engine.state.value.playing, isFalse);
      expect(rig.engine.state.value.hasFirstFrame, isTrue);
      await rig.engine.dispose();
    });

    test('isCompleted emits ended once; playing again re-arms it', () async {
      final rig = Rig();
      await rig.engine.open(movie);
      rig.c.ready();
      await settle();
      rig.c.value = rig.c.value.copyWith(isCompleted: true, isPlaying: false);
      rig.c.value = rig.c.value.copyWith(position: const Duration(minutes: 90));
      await settle();
      expect(rig.events.whereType<EndedEvent>(), hasLength(1));
      await rig.c.play();
      rig.c.value = rig.c.value.copyWith(isCompleted: true, isPlaying: false);
      await settle();
      expect(rig.events.whereType<EndedEvent>(), hasLength(2));
      await rig.engine.dispose();
    });

    test(
      'VOD at the end and stopped counts as ended without the flag',
      () async {
        final rig = Rig();
        await rig.engine.open(movie.copyWith(startAt: Duration.zero));
        rig.c.ready();
        await settle();
        rig.c.value = rig.c.value.copyWith(
          isPlaying: false,
          position: const Duration(minutes: 89, seconds: 59, milliseconds: 600),
        );
        await settle();
        expect(rig.events.whereType<EndedEvent>(), hasLength(1));
        await rig.engine.dispose();
      },
    );

    test(
      'paused mid-movie is not ended; live never uses the heuristic',
      () async {
        final rig = Rig();
        await rig.engine.open(movie);
        rig.c.ready();
        await settle();
        await rig.c.pause();
        await settle();
        expect(rig.events.whereType<EndedEvent>(), isEmpty);

        await rig.engine.open(live);
        rig.c.reportedDuration = const Duration(seconds: 1);
        rig.c.ready();
        await settle();
        rig.c.value = rig.c.value.copyWith(
          isPlaying: false,
          position: const Duration(seconds: 5),
        );
        await settle();
        expect(rig.events.whereType<EndedEvent>(), isEmpty);
        await rig.engine.dispose();
      },
    );
  });

  group('stop and dispose', () {
    test('stop pauses and disposes the controller; repeat is safe', () async {
      final rig = Rig();
      await rig.engine.open(live);
      final c = rig.c;
      c.ready();
      await settle();
      await rig.engine.stop();
      expect(c.calls.sublist(c.calls.length - 2), ['pause', 'dispose']);
      expect(rig.engine.controller, isNull);
      expect(rig.engine.state.value, PlaybackState.idle);
      await rig.engine.stop();
      await rig.engine.stop();
      expect(c.calls.where((x) => x == 'dispose'), hasLength(1));
      await rig.engine.dispose();
    });

    test('stop while initializing: no play afterwards', () async {
      final rig = Rig();
      await rig.engine.open(live);
      final c = rig.c;
      await rig.engine.stop();
      expect(c.disposed, isTrue);
      expect(c.calls, ['initialize', 'dispose']);
      await rig.engine.dispose();
    });

    test('controls are no-ops without a controller', () async {
      final rig = Rig();
      await rig.engine.play();
      await rig.engine.pause();
      await rig.engine.seek(const Duration(seconds: 3));
      expect(await rig.engine.audioTracks(), isEmpty);
      await rig.engine.selectAudio('1');
      await rig.engine.dispose();
    });

    test('dispose closes events and rejects later opens', () async {
      final rig = Rig();
      var done = false;
      rig.engine.events.listen(null, onDone: () => done = true);
      await rig.engine.open(live);
      await rig.engine.dispose();
      await rig.engine.dispose();
      expect(done, isTrue);
      expect(rig.c.disposed, isTrue);
      await expectLater(rig.engine.open(live), throwsStateError);
    });
  });

  group('tracks and stats', () {
    test('audio tracks map isSelected; subtitles are unsupported', () async {
      final rig = Rig();
      rig.onCreate = (c) => c.tracks = const [
        VideoAudioTrack(
          id: '0:1',
          isSelected: false,
          language: 'ar',
          label: 'Arabic',
          codec: 'ac-3',
        ),
        VideoAudioTrack(id: '0:2', isSelected: true, language: 'en'),
      ];
      await rig.engine.open(movie);
      expect(await rig.engine.audioTracks(), isEmpty, reason: 'not ready');
      rig.c.ready();
      await settle();
      final tracks = await rig.engine.audioTracks();
      expect(tracks.map((t) => t.id), ['0:1', '0:2']);
      expect(tracks.map((t) => t.selected), [false, true]);
      expect(tracks.first.displayName, 'Arabic · ar · ac-3');
      await rig.engine.selectAudio('0:1');
      expect(rig.c.calls.last, 'selectAudioTrack 0:1');
      expect(await rig.engine.subtitleTracks(), isEmpty);
      await rig.engine.selectSubtitle('x');

      final stats = await rig.engine.stats();
      expect(stats['engine'], 'ExoPlayer');
      expect(stats['resolution'], '1920x1080');
      expect(stats['view'], 'texture');
      expect(stats['format'], 'auto');
      await rig.engine.dispose();
    });

    test('live seeks are ignored', () async {
      final rig = Rig();
      await rig.engine.open(live);
      rig.c.ready();
      await settle();
      await rig.engine.seek(const Duration(seconds: 30));
      expect(rig.c.calls, isNot(contains('seekTo 30')));
      await rig.engine.dispose();
    });
  });

  group('view', () {
    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: SizedBox(width: 800, height: 600, child: child)),
      ),
    );

    testWidgets('black and empty before open', (tester) async {
      final rig = Rig();
      await pump(tester, rig.engine.buildView());
      expect(find.byType(VideoPlayer), findsNothing);
      expect(find.byType(ColoredBox), findsOneWidget);
      await rig.engine.dispose();
    });

    testWidgets('fit uses the video aspect ratio', (tester) async {
      final rig = Rig();
      await rig.engine.open(live);
      rig.c.ready(size: const Size(1280, 720));
      await tester.pump();
      await pump(tester, rig.engine.buildView());
      expect(find.byType(VideoPlayer), findsOneWidget);
      final ar = tester.widget<AspectRatio>(find.byType(AspectRatio));
      expect(ar.aspectRatio, closeTo(16 / 9, 1e-9));
      await rig.engine.stop();
      await tester.pump();
      expect(find.byType(VideoPlayer), findsNothing);
      await rig.engine.dispose();
    });

    for (final (mode, ratio) in [
      (AspectMode.ratio16x9, 16 / 9),
      (AspectMode.ratio4x3, 4 / 3),
    ]) {
      testWidgets('$mode forces $ratio', (tester) async {
        await pump(
          tester,
          exoSurface(
            const SizedBox(),
            aspect: mode,
            videoSize: const Size(720, 576),
          ),
        );
        final ar = tester.widget<AspectRatio>(find.byType(AspectRatio));
        expect(ar.aspectRatio, ratio);
      });
    }

    testWidgets('fill covers with a clipped FittedBox', (tester) async {
      await pump(
        tester,
        exoSurface(
          const SizedBox(),
          aspect: AspectMode.fill,
          videoSize: const Size(1920, 800),
        ),
      );
      final box = tester.widget<FittedBox>(find.byType(FittedBox));
      expect(box.fit, BoxFit.cover);
      expect(box.clipBehavior, Clip.hardEdge);
    });

    testWidgets('stretch fills the whole box', (tester) async {
      await pump(
        tester,
        exoSurface(
          const SizedBox(key: Key('video')),
          aspect: AspectMode.stretch,
          videoSize: const Size(720, 576),
        ),
      );
      expect(find.byType(AspectRatio), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('video'))),
        const Size(800, 600),
      );
    });

    testWidgets('unknown size falls back to 16:9', (tester) async {
      await pump(
        tester,
        exoSurface(
          const SizedBox(),
          aspect: AspectMode.fit,
          videoSize: Size.zero,
        ),
      );
      expect(
        tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
        16 / 9,
      );
    });
  });
}
