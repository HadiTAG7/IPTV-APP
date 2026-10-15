import 'dart:async';

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

  /// Holds [stop] until completed (then records `stopped`).
  Completer<void>? stopGate;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    calls.add('open');
    if (openError != null) throw openError!;
    opened = playable as Media;
    openedWithPlay = play;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    final gate = stopGate;
    if (gate == null) return;
    await gate.future;
    calls.add('stopped');
  }

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
  /// [props] answers libmpv property reads (`aid`, `sid`, `hwdec-current`).
  Rig({this.props = const {}}) {
    engine = MpvEngine.withPlayer(
      Player(platformPlayer: fake),
      readProperty: (name) async {
        reads.add(name);
        return props[name];
      },
    );
    engine.events.listen(events.add);
  }

  final Map<String, String> props;
  final reads = <String>[];
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

    test('an old TLS warning does not make a later hiccup fatal', () async {
      final rig = Rig();
      await rig.engine.open(live);
      rig.fake
        ..log('ffmpeg', 'error', 'tls: Error in the pull function.')
        ..log('ffmpeg', 'warn', 'http: HTTP error 403 Forbidden')
        ..error('Error while decoding frame!');
      await settle();
      final hiccup = rig.errors.single;
      expect(hiccup.fatal, isFalse);
      expect(hiccup.message, 'Error while decoding frame!');
      expect(hiccup.httpStatus, isNull);

      // The detail is kept for the fatal error it explains, then dropped.
      rig.fake.error('Failed to open https://example.com/live/a/b/5.ts.');
      await settle();
      final fatal = rig.errors.last;
      expect(fatal.fatal, isTrue);
      expect(fatal.message, contains('HTTP error 403'));
      expect(fatal.httpStatus, 403);
      rig.fake.error('Error while decoding frame!');
      await settle();
      expect(rig.errors.last.message, 'Error while decoding frame!');
      expect(rig.errors.last.httpStatus, isNull);
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

    test('without an explicit choice the selection is read from mpv', () async {
      // media_kit keeps track.audio/subtitle at 'auto' until setAudioTrack
      // is called, even though mpv picked a track through alang/slang.
      final rig = Rig(props: {'aid': '1', 'sid': 'no'});
      setTracks(rig.fake);
      rig.fake.state = rig.fake.state.copyWith(track: const Track());
      final audio = await rig.engine.audioTracks();
      expect(audio.map((t) => t.selected), [true, false]);
      final subs = await rig.engine.subtitleTracks();
      expect(subs.single.selected, isFalse);
      expect(rig.reads, containsAll(['aid', 'sid']));

      final stats = await rig.engine.stats();
      expect(stats['audio'], 'ac3');
      await rig.engine.dispose();
    });

    test('a subtitle chosen by slang is marked selected', () async {
      final rig = Rig(props: {'aid': 'no', 'sid': '1'});
      setTracks(rig.fake);
      rig.fake.state = rig.fake.state.copyWith(track: const Track());
      expect((await rig.engine.subtitleTracks()).single.selected, isTrue);
      expect(
        (await rig.engine.audioTracks()).where((t) => t.selected),
        isEmpty,
      );
      await rig.engine.dispose();
    });

    test('an explicit choice wins without asking mpv', () async {
      final rig = Rig(props: {'aid': '1'});
      setTracks(rig.fake);
      final audio = await rig.engine.audioTracks();
      expect(audio.map((t) => t.selected), [false, true]);
      expect(rig.reads, isNot(contains('aid')));
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

    test('stats report the hwdec mpv actually uses', () async {
      final rig = Rig(props: {'hwdec-current': 'mediacodec'});
      await rig.engine.open(live);
      expect((await rig.engine.stats())['hwdec'], 'mediacodec');
      await rig.engine.stop();
      expect((await rig.engine.stats())['hwdec'], 'auto-safe');
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

  group('shared core', () {
    late List<FakePlatformPlayer> players;
    late List<bool> lites;
    late MpvCore core;

    setUp(() {
      players = [];
      lites = [];
      core = MpvCore(
        createPlayer: ({required lite}) {
          lites.add(lite);
          final fake = FakePlatformPlayer();
          players.add(fake);
          return Player(platformPlayer: fake);
        },
        createVideo: (_, {required hardwareDecoding}) => null,
      );
    });

    test('engines borrow one player: stopped, never disposed', () async {
      final a = MpvEngine(core: core);
      expect(core.isLent, isTrue);
      await a.open(live);
      await a.dispose();
      expect(core.isLent, isFalse);
      final b = MpvEngine(core: core, lite: true);
      await b.open(movie);
      await b.dispose();
      expect(players, hasLength(1));
      expect(lites, [false]);
      expect(players.single.calls, ['open', 'stop', 'open', 'stop']);
    });

    test('the next engine opens only after the last one stopped', () async {
      final a = MpvEngine(core: core);
      await a.open(live);
      final fake = players.single..stopGate = Completer<void>();
      // Not awaited, like PlaybackController.dispose.
      unawaited(a.dispose());
      final b = MpvEngine(core: core);
      final opening = b.open(movie);
      await settle();
      expect(fake.calls, ['open', 'stop']);
      fake.stopGate!.complete();
      await opening;
      expect(fake.calls, ['open', 'stop', 'stopped', 'open']);
      expect(fake.opened!.uri, movie.url);
      await b.dispose();
    });

    test('a borrowed core resets tracks and applies hwdec changes', () {
      final first = core.lease(lite: false, hardwareDecoding: true);
      expect(first.shared, isTrue);
      expect(first.properties, isEmpty);
      unawaited(first.release());
      final same = core.lease(lite: false, hardwareDecoding: true);
      expect(same.properties, {'aid': 'auto', 'sid': 'auto'});
      unawaited(same.release());
      final software = core.lease(lite: false, hardwareDecoding: false);
      expect(software.properties, {
        'aid': 'auto',
        'sid': 'auto',
        'hwdec': 'no',
      });
      expect(identical(software.player, first.player), isTrue);
      unawaited(software.release());
    });

    test('while one engine holds it, another gets its own player', () async {
      final a = MpvEngine(core: core);
      final b = MpvEngine(core: core);
      expect(players, hasLength(2));
      await b.dispose();
      expect(players[1].calls, ['dispose']);
      await a.dispose();
      expect(players[0].calls, ['stop']);
      // The core is free again.
      final c = MpvEngine(core: core);
      expect(players, hasLength(2));
      await c.dispose();
    });
  });

  group('video configuration', () {
    test('Android: media_kit maps the flag to hwdec (no in emulators)', () {
      for (final hw in [true, false]) {
        final c = mpvVideoConfiguration(hardwareDecoding: hw, android: true);
        expect(c.hwdec, isNull);
        expect(c.enableHardwareAcceleration, hw);
      }
    });

    test('desktop: hwdec is explicit and rendering stays on the GPU', () {
      final hw = mpvVideoConfiguration(hardwareDecoding: true, android: false);
      expect(hw.hwdec, 'auto-safe');
      expect(hw.enableHardwareAcceleration, isTrue);
      final sw = mpvVideoConfiguration(hardwareDecoding: false, android: false);
      expect(sw.hwdec, 'no');
      expect(sw.enableHardwareAcceleration, isTrue);
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
