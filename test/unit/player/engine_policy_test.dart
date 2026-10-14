import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/engine/engine_policy.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/sources/models.dart';

const policy = EnginePolicy();
const android = EnginePolicyInput(platform: TargetPlatformKind.android);
const amlogic = EnginePolicyInput(
  platform: TargetPlatformKind.android,
  isAmlogic: true,
);

void main() {
  group('default table', () {
    test('Android: live exo, VOD mpv', () {
      expect(policy.pick(PlayableKind.live, android), EngineKind.exo);
      expect(policy.pick(PlayableKind.movie, android), EngineKind.mpv);
      expect(policy.pick(PlayableKind.episode, android), EngineKind.mpv);
    });

    test('Android Amlogic: everything on exo', () {
      expect(policy.pick(PlayableKind.live, amlogic), EngineKind.exo);
      expect(policy.pick(PlayableKind.movie, amlogic), EngineKind.exo);
      expect(policy.pick(PlayableKind.episode, amlogic), EngineKind.exo);
    });

    for (final platform in [
      TargetPlatformKind.windows,
      TargetPlatformKind.linux,
      TargetPlatformKind.other,
    ]) {
      test('$platform: mpv for all kinds, no fallback', () {
        final input = EnginePolicyInput(platform: platform);
        for (final kind in PlayableKind.values) {
          expect(policy.pick(kind, input), EngineKind.mpv);
        }
        expect(policy.fallbackFor(EngineKind.mpv, input), isNull);
        expect(policy.fallbackFor(EngineKind.exo, input), isNull);
      });
    }
  });

  group('fallbacks on Android', () {
    test('exo <-> mpv', () {
      for (final input in [android, amlogic]) {
        expect(policy.fallbackFor(EngineKind.exo, input), EngineKind.mpv);
        expect(policy.fallbackFor(EngineKind.mpv, input), EngineKind.exo);
      }
    });
  });

  group('precedence', () {
    test('source overrides beat the table, per content family', () {
      const input = EnginePolicyInput(
        platform: TargetPlatformKind.android,
        sourceLiveOverride: EngineKind.mpv,
        sourceVodOverride: EngineKind.exo,
      );
      expect(policy.pick(PlayableKind.live, input), EngineKind.mpv);
      expect(policy.pick(PlayableKind.movie, input), EngineKind.exo);
      expect(policy.pick(PlayableKind.episode, input), EngineKind.exo);
    });

    test('channel preference beats source override', () {
      const input = EnginePolicyInput(
        platform: TargetPlatformKind.android,
        sourceLiveOverride: EngineKind.exo,
        channelPref: EngineKind.mpv,
      );
      expect(policy.pick(PlayableKind.live, input), EngineKind.mpv);
    });

    test('copyWith sets the channel preference only', () {
      final input = amlogic.copyWith(channelPref: EngineKind.mpv);
      expect(input.isAmlogic, isTrue);
      expect(input.platform, TargetPlatformKind.android);
      expect(input.channelPref, EngineKind.mpv);
      expect(input.copyWith().channelPref, EngineKind.mpv);
    });
  });

  test('exhaustive: matches the spec and never picks exo off Android', () {
    final prefs = <EngineKind?>[null, ...EngineKind.values];
    var cases = 0;
    for (final platform in TargetPlatformKind.values) {
      for (final isAmlogic in [false, true]) {
        for (final live in prefs) {
          for (final vod in prefs) {
            for (final channel in prefs) {
              final input = EnginePolicyInput(
                platform: platform,
                isAmlogic: isAmlogic,
                sourceLiveOverride: live,
                sourceVodOverride: vod,
                channelPref: channel,
              );
              for (final kind in PlayableKind.values) {
                cases++;
                final picked = policy.pick(kind, input);
                final EngineKind expected;
                if (platform != TargetPlatformKind.android) {
                  expected = EngineKind.mpv;
                } else {
                  final table = kind == PlayableKind.live || isAmlogic
                      ? EngineKind.exo
                      : EngineKind.mpv;
                  final override = kind == PlayableKind.live ? live : vod;
                  expected = channel ?? override ?? table;
                }
                expect(picked, expected, reason: '$platform $kind');
                if (platform != TargetPlatformKind.android) {
                  expect(picked, isNot(EngineKind.exo));
                }
                final fallback = policy.fallbackFor(picked, input);
                if (platform == TargetPlatformKind.android) {
                  expect(fallback, isNot(picked));
                  expect(fallback, isNotNull);
                } else {
                  expect(fallback, isNull);
                }
              }
            }
          }
        }
      }
    }
    expect(cases, 4 * 2 * 3 * 3 * 3 * 3);
  });

  test('targetPlatformKindOf', () {
    expect(
      targetPlatformKindOf(TargetPlatform.android),
      TargetPlatformKind.android,
    );
    expect(
      targetPlatformKindOf(TargetPlatform.windows),
      TargetPlatformKind.windows,
    );
    expect(
      targetPlatformKindOf(TargetPlatform.linux),
      TargetPlatformKind.linux,
    );
    expect(
      targetPlatformKindOf(TargetPlatform.macOS),
      TargetPlatformKind.other,
    );
    expect(targetPlatformKindOf(TargetPlatform.iOS), TargetPlatformKind.other);
    expect(
      targetPlatformKindOf(TargetPlatform.android, isWeb: true),
      TargetPlatformKind.other,
    );
  });

  group('hasKnownMediaExtension', () {
    test('known containers', () {
      for (final url in [
        'http://127.0.0.1:8080/live/u/p/1.ts',
        'http://example.com/a/b/index.m3u8?token=abc',
        'https://example.com/movie/9.MKV',
        'http://example.com/v.mp4#t=10',
        'http://example.com/stream.mpd',
        'http://example.com/clip.ts|User-Agent=Foo',
      ]) {
        expect(hasKnownMediaExtension(url), isTrue, reason: url);
      }
    });

    test('extension-less or script URLs', () {
      for (final url in [
        'http://127.0.0.1:8080/play/12345',
        'http://example.com/stream.php?id=5',
        'http://example.com/live/channel.',
        'http://example.com/',
        'http://example.com/hls.m3u8x',
        'http://example.com/dir.ts/play',
      ]) {
        expect(hasKnownMediaExtension(url), isFalse, reason: url);
      }
    });
  });

  group('httpStatusFromMessage', () {
    test('ExoPlayer and ffmpeg formats', () {
      expect(
        httpStatusFromMessage(
          'InvalidResponseCodeException: Response code: 403',
        ),
        403,
      );
      expect(httpStatusFromMessage('http: HTTP error 401 Unauthorized'), 401);
      expect(httpStatusFromMessage('Server returned 404 Not Found'), 404);
      expect(
        httpStatusFromMessage('Server returned 4XX Client Error, but not one'),
        400,
      );
      expect(httpStatusFromMessage('Server returned 5XX Server Error'), 500);
      expect(httpStatusFromMessage('HTTP 458 from server'), 458);
      expect(httpStatusFromMessage('HTTP/1.1 509 Bandwidth'), 509);
      expect(httpStatusFromMessage('status code: 429'), 429);
    });

    test('ignores URLs, ports and non-error codes', () {
      expect(
        httpStatusFromMessage('Failed to open http://127.0.0.1:8080/x.ts'),
        isNull,
      );
      expect(httpStatusFromMessage('HTTP 200 OK'), isNull);
      expect(httpStatusFromMessage('Source error'), isNull);
    });
  });

  test('looksLikeTlsError', () {
    expect(looksLikeTlsError('tls: handshake failed'), isTrue);
    expect(looksLikeTlsError('SSL routines: wrong version'), isTrue);
    expect(looksLikeTlsError('Certificate verification failed'), isTrue);
    expect(looksLikeTlsError('Failed to open https://example.com/a'), isFalse);
    expect(looksLikeTlsError('HTTP error 403 Forbidden'), isFalse);
  });
}
