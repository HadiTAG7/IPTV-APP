import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/engine/mpv_engine.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:media_kit/media_kit.dart';

/// media_kit platform player without libmpv: records calls and lets tests
/// push values into the player streams.
class FakePlatformPlayer extends PlatformPlayer {
  FakePlatformPlayer() : super(configuration: const PlayerConfiguration());

  final calls = <String>[];
  Media? opened;
  bool? openedWithPlay;
  Object? openError;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    calls.add('open');
    if (openError != null) throw openError!;
    opened = playable as Media;
    openedWithPlay = play;
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> seek(Duration duration) async =>
      calls.add('seek ${duration.inSeconds}');

  @override
  Future<void> setAudioTrack(AudioTrack track) async =>
      calls.add('audio ${track.id}');

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async =>
      calls.add('subtitle ${track.id}');

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await super.dispose();
  }

  void position(Duration d) => positionController.add(d);
  void duration(Duration d) => durationController.add(d);
  void buffering(bool b) => bufferingController.add(b);
  void playing(bool p) => playingController.add(p);
  void completed(bool c) => completedController.add(c);
  void error(String e) => errorController.add(e);
  void size(int w, int h) {
    widthController.add(w);
    heightController.add(h);
  }

  void log(String prefix, String level, String text) =>
      logController.add(PlayerLog(prefix: prefix, level: level, text: text));
}

class Rig {
  Rig() {
    engine = MpvEngine.withPlayer(Player(platformPlayer: fake));
    engine.events.listen(events.add);
  }

  final fake = FakePlatformPlayer();
  late final MpvEngine engine;
  final events = <EngineEvent>[];

  List<ErrorEvent> get errors => events.whereType<ErrorEvent>().toList();
}

const live = StreamRequest(
  url: 'http://127.0.0.1:8080/live/user/secret/5.ts',
  kind: PlayableKind.live,
  headers: {'User-Agent': 'Custom/2.0', 'Referer': 'http://example.com/'},
  startAt: Duration(minutes: 3),
);
const movie = StreamRequest(
  url: 'http://example.com/movie/user/secret/9.mkv',
  kind: PlayableKind.movie,
  startAt: Duration(minutes: 42),
);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('open', () {
    test('passes URL, headers without UA, start only for VOD', () async {
      final rig = Rig();
      await rig.engine.open(live);
      final media = rig.fake.opened!;
      expect(media.uri, live.url);
      expect(media.httpHeaders, {'Referer': 'http://example.com/'});
      expect(media.start, isNull);
      expect(rig.fake.openedWithPlay, isTrue);
      expect(rig.engine.state.value.buffering, isTrue);

      await rig.engine.open(movie);
      expect(rig.fake.opened!.start, const Duration(minutes: 42));
      expect(rig.fake.opened!.httpHeaders, isEmpty);
      await rig.engine.dispose();
    });

    test('an open that throws becomes a fatal error event', () async {
      final rig = Rig();
      rig.fake.openError = StateError('player gone');
      await rig.engine.open(live);
      await settle();
      expect(rig.errors.single.fatal, isTrue);
      expect(rig.errors.single.message, contains('Failed to open'));
      await rig.engine.dispose();
    });
  });

  group('state mapping', () {
    test('streams update state; first frame on video size', () async {
      final rig = Rig();
      await rig.engine.open(movie);
      rig.fake
        ..duration(const Duration(minutes: 100))
        ..buffering(false)
        ..playing(true);
      await settle();
      var s = rig.engine.state.value;
      expect(s.duration, const Duration(minutes: 100));
      expect(s.playing, isTrue);
      expect(s.buffering, isFalse);
      expect(s.hasFirstFrame, isFalse);
      expect(rig.events, isEmpty);

      rig.fake.size(1920, 1080);
      await settle();
      s = rig.engine.state.value;
      expect(s.videoSize, const Size(1920, 1080));
      expect(s.hasFirstFrame, isTrue);
      expect(rig.events.single, isA<FirstFrameEvent>());

      rig.fake.position(const Duration(minutes: 42, seconds: 1));
      await settle();
      expect(rig.engine.state.value.position.inSeconds, 42 * 60 + 1);
      expect(rig.events.whereType<FirstFrameEvent>(), hasLength(1));
      await rig.engine.dispose();
    });

    test('audio-only streams get a first frame from position', () async {
      final rig = Rig();
      await rig.engine.open(live);
      rig.fake.position(const Duration(milliseconds: 40));
      await settle();
      expect(rig.events.single, isA<FirstFrameEvent>());
      await rig.engine.dispose();
    });

    test('live duration is always zero', () async {
      final rig = Rig();
      await rig.engine.open(live);
      rig.fake.duration(const Duration(seconds: 12));
      await settle();
      expect(rig.engine.state.value.duration, Duration.zero);
      await rig.engine.dispose();
    });

    test('completed emits ended once until it resets', () async {
      final rig = Rig();
      await rig.engine.open(movie);
      rig.fake
        ..playing(true)
        ..completed(true);
      await settle();
      expect(rig.events.whereType<EndedEvent>(), hasLength(1));
      expect(rig.engine.state.value.playing, isFalse);
      rig.fake.completed(false);
      await settle();
      rig.fake.completed(true);
      await settle();
      expect(rig.events.whereType<EndedEvent>(), hasLength(2));
      await rig.engine.dispose();
    });

    test('events before open and after stop are ignored', () async {
      final rig = Rig();
      rig.fake
        ..position(const Duration(seconds: 3))
        ..error('Failed to open x');
      await settle();
      expect(rig.events, isEmpty);

      await rig.engine.open(live);
      await rig.engine.stop();
      expect(rig.fake.calls.last, 'stop');
      expect(rig.engine.state.value, PlaybackState.idle);
      rig.fake
        ..size(640, 360)
        ..completed(true)
        ..error('Failed to open y');
      await settle();
      expect(rig.events, isEmpty);
      expect(rig.engine.state.value, PlaybackState.idle);
      await rig.engine.dispose();
    });
  });

  group('errors', () {
    test('open failure: fatal, redacted, HTTP status from the log', () async {
      final rig = Rig();
      await rig.engine.open(live);
      rig.fake
        ..log('ffmpeg', 'warn', 'http: HTTP error 403 Forbidden')
        ..error('Failed to open http://127.0.0.1:8080/live/user/secret/5.ts.');
      await settle();
      final e = rig.errors.single;
      expect(e.fatal, isTrue);
      expect(e.httpStatus, 403);
      expect(e.message, contains('HTTP error 403'));
      expect(e.message, isNot(contains('secret')));
      expect(rig.engine.state.value.buffering, isFalse);
      await rig.engine.dispose();
    });

    test('only the first fatal error per open is reported', () async {
      final rig = Rig();
      await rig.engine.open(live);
      rig.fake
        ..error('Failed to open a')
        ..error('Failed to recognize file format.');
      await settle();
      expect(rig.errors, hasLength(1));

      await rig.engine.open(live);
      rig.fake.error('Failed to open b');
      await settle();
      expect(rig.errors, hasLength(2));
      await rig.engine.dispose();
    });

    test('decoder and read hiccups are non-fatal', () async {
      final rig = Rig();
      await rig.engine.open(live);
      rig.fake
        ..error('Error while decoding frame!')
        ..error('tcp: ffurl_read returned 0xffffff99');
      await settle();
      expect(rig.errors.map((e) => e.fatal), [false, false]);
      await rig.engine.dispose();
    });

    test('TLS detail from the log is attached to the error', () async {
      final rig = Rig();
      await rig.engine.open(movie);
      rig.fake
        ..log('ffmpeg', 'error', 'tls: Error in the push function.')
        ..log('cplayer', 'info', 'irrelevant')
        ..error('Failed to open https://example.com/movie/a/b/1.mkv.');
      await settle();
      final e = rig.errors.single;
      expect(e.message, contains('tls: Error in the push function.'));
      expect(e.message, contains('/movie/***/***/1.mkv'));
      expect(e.httpStatus, isNull);
      await rig.engine.dispose();
    });

    test('log details do not leak into the next open', () async {
      final rig = Rig();
      await rig.engine.open(live);
      rig.fake.log('ffmpeg', 'warn', 'http: HTTP error 403 Forbidden');
      await settle();
      await rig.engine.open(live);
      rig.fake.error('Failed to open z');
      await settle();
      expect(rig.errors.single.httpStatus, isNull);
      await rig.engine.dispose();
    });
  });

  group('tracks', () {
    void setTracks(FakePlatformPlayer fake) {
      fake.state = fake.state.copyWith(
        tracks: const Tracks(
          video: [
            VideoTrack('auto', null, null),
            VideoTrack('no', null, null),
            VideoTrack('1', null, null, codec: 'h264'),
          ],
          audio: [
            AudioTrack('auto', null, null),
            AudioTrack('no', null, null),
            AudioTrack('1', 'Arabic', 'ara', codec: 'ac3'),
            AudioTrack('2', null, 'eng', codec: 'aac'),
          ],
          subtitle: [
            SubtitleTrack('auto', null, null),
            SubtitleTrack('no', null, null),
            SubtitleTrack('1', 'Arabic', 'ara', codec: 'subrip'),
          ],
        ),
        track: const Track(
          audio: AudioTrack('2', null, 'eng'),
          subtitle: SubtitleTrack('no', null, null),
        ),
      );
    }

    test('lists real tracks only, with the selected one marked', () async {
      final rig = Rig();
      setTracks(rig.fake);
      final audio = await rig.engine.audioTracks();
      expect(audio.map((t) => t.id), ['1', '2']);
      expect(audio.map((t) => t.selected), [false, true]);
      expect(audio.first.label, 'Arabic');
      expect(audio.first.language, 'ara');
      expect(audio.first.codec, 'ac3');
      final subs = await rig.engine.subtitleTracks();
      expect(subs.map((t) => t.id), ['1']);
      expect(subs.single.selected, isFalse);
      await rig.engine.dispose();
    });

    test('selecting tracks, and subtitles off', () async {
      final rig = Rig();
      setTracks(rig.fake);
      await rig.engine.selectAudio('1');
      await rig.engine.selectAudio('missing');
      await rig.engine.selectSubtitle('1');
      await rig.engine.selectSubtitle(null);
      expect(rig.fake.calls, ['audio 1', 'subtitle 1', 'subtitle no']);
      await rig.engine.dispose();
    });

    test('stats report engine, resolution and codecs', () async {
      final rig = Rig();
      setTracks(rig.fake);
      await rig.engine.open(live);
      rig.fake.size(1280, 720);
      await settle();
      final stats = await rig.engine.stats();
      expect(stats['engine'], 'mpv');
      expect(stats['resolution'], '1280x720');
      expect(stats['video'], 'h264');
      expect(stats['audio'], 'aac');
      expect(stats['hwdec'], 'auto-safe');
      expect(stats['cache'], '64 MB');
      await rig.engine.dispose();
    });
  });

  group('controls and lifecycle', () {
    test('play/pause/seek delegate; live seek is ignored', () async {
      final rig = Rig();
      await rig.engine.open(movie);
      await rig.engine.pause();
      await rig.engine.play();
      await rig.engine.seek(const Duration(seconds: 90));
      await rig.engine.open(live);
      await rig.engine.seek(const Duration(seconds: 5));
      expect(rig.fake.calls, ['open', 'pause', 'play', 'seek 90', 'open']);
      await rig.engine.dispose();
    });

    test('dispose disposes the player once and closes events', () async {
      final rig = Rig();
      var done = false;
      rig.engine.events.listen(null, onDone: () => done = true);
      await rig.engine.dispose();
      await rig.engine.dispose();
      await rig.engine.stop();
      await rig.engine.play();
      expect(rig.fake.calls.where((c) => c == 'dispose'), hasLength(1));
      expect(done, isTrue);
      expect(await rig.engine.audioTracks(), isEmpty);
      await expectLater(rig.engine.open(live), throwsStateError);
    });

    test('kind is mpv', () {
      expect(Rig().engine.kind, EngineKind.mpv);
    });
  });

  test('aspect modes map to Video fits', () {
    expect(mpvFit(AspectMode.fit), BoxFit.contain);
    expect(mpvFit(AspectMode.fill), BoxFit.cover);
    expect(mpvFit(AspectMode.stretch), BoxFit.fill);
    expect(mpvFit(AspectMode.ratio16x9), BoxFit.fill);
    expect(mpvFit(AspectMode.ratio4x3), BoxFit.fill);
  });

  testWidgets('without a video controller the view is black', (tester) async {
    final rig = Rig();
    await tester.pumpWidget(rig.engine.buildView());
    expect(find.byType(ColoredBox), findsOneWidget);
    // media_kit closes its streams on real timers.
    await tester.runAsync(rig.engine.dispose);
  });
}
