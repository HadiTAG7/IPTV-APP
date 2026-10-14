/// Which engine plays what, and when to fall back to the other one.
///
/// Pure: no platform calls. Android runs ExoPlayer for live and mpv for VOD
/// (ExoPlayer on Amlogic boxes); desktop always runs mpv.
library;

import 'package:flutter/foundation.dart';

import '../../sources/models.dart';
import 'player_engine.dart';

/// Coarse platform buckets the policy cares about.
enum TargetPlatformKind { android, windows, linux, other }

/// Maps Flutter's [TargetPlatform] to a [TargetPlatformKind].
TargetPlatformKind targetPlatformKindOf(
  TargetPlatform platform, {
  bool isWeb = false,
}) {
  if (isWeb) return TargetPlatformKind.other;
  return switch (platform) {
    TargetPlatform.android => TargetPlatformKind.android,
    TargetPlatform.windows => TargetPlatformKind.windows,
    TargetPlatform.linux => TargetPlatformKind.linux,
    _ => TargetPlatformKind.other,
  };
}

/// Everything [EnginePolicy] needs to choose an engine.
@immutable
class EnginePolicyInput {
  const EnginePolicyInput({
    required this.platform,
    this.isAmlogic = false,
    this.sourceLiveOverride,
    this.sourceVodOverride,
    this.channelPref,
  });

  final TargetPlatformKind platform;

  /// Amlogic SoCs mis-decode some VOD in mpv's MediaCodec path.
  final bool isAmlogic;

  /// Per-source engine for live items.
  final EngineKind? sourceLiveOverride;

  /// Per-source engine for movies and episodes.
  final EngineKind? sourceVodOverride;

  /// Learned or manual per-channel choice; wins over everything else.
  final EngineKind? channelPref;

  EnginePolicyInput copyWith({EngineKind? channelPref}) => EnginePolicyInput(
    platform: platform,
    isAmlogic: isAmlogic,
    sourceLiveOverride: sourceLiveOverride,
    sourceVodOverride: sourceVodOverride,
    channelPref: channelPref ?? this.channelPref,
  );
}

/// The engine table from the design (section 10).
///
/// | Platform | Content | Default | Fallback |
/// |---|---|---|---|
/// | Android | live | exo | mpv |
/// | Android | movie/episode | mpv | exo |
/// | Android (Amlogic) | movie/episode | exo | mpv |
/// | Windows/Linux/other | all | mpv | none |
///
/// Precedence: channel preference > source override > table. Exo is never
/// returned off Android.
class EnginePolicy {
  const EnginePolicy();

  EngineKind pick(PlayableKind kind, EnginePolicyInput input) {
    if (input.platform != TargetPlatformKind.android) return EngineKind.mpv;
    final sourceOverride = kind == PlayableKind.live
        ? input.sourceLiveOverride
        : input.sourceVodOverride;
    return input.channelPref ?? sourceOverride ?? _table(kind, input);
  }

  /// The engine to try after [current] failed, or null when there is none.
  EngineKind? fallbackFor(EngineKind current, EnginePolicyInput input) {
    if (input.platform != TargetPlatformKind.android) return null;
    return switch (current) {
      EngineKind.exo => EngineKind.mpv,
      EngineKind.mpv => EngineKind.exo,
    };
  }

  EngineKind _table(PlayableKind kind, EnginePolicyInput input) {
    if (kind == PlayableKind.live || input.isAmlogic) return EngineKind.exo;
    return EngineKind.mpv;
  }
}

const _mediaExtensions = {
  'm3u8',
  'm3u',
  'ts',
  'mts',
  'm2ts',
  'mp4',
  'm4v',
  'mkv',
  'avi',
  'mov',
  'flv',
  'webm',
  'mpd',
  'ism',
  'mpg',
  'mpeg',
  'wmv',
  'ogv',
  'mp3',
  'aac',
  'm4a',
  'ogg',
  'opus',
  'flac',
  'wav',
  '3gp',
};

/// True when the URL path ends with a known media extension, so ExoPlayer can
/// infer the container. URLs such as `/play/123` or `stream.php?id=1` are not.
bool hasKnownMediaExtension(String url) {
  var path = url;
  final cut = path.indexOf(RegExp('[?#|]'));
  if (cut >= 0) path = path.substring(0, cut);
  final slash = path.lastIndexOf('/');
  final last = slash >= 0 ? path.substring(slash + 1) : path;
  final dot = last.lastIndexOf('.');
  if (dot < 0 || dot == last.length - 1) return false;
  return _mediaExtensions.contains(last.substring(dot + 1).toLowerCase());
}

final _httpStatusPatterns = [
  // ExoPlayer InvalidResponseCodeException.
  RegExp(r'response code:?\s*(\d{3})\b', caseSensitive: false),
  // ffmpeg: "HTTP error 403 Forbidden", "Server returned 404 Not Found".
  RegExp(r'http error (\d{3})\b', caseSensitive: false),
  RegExp(r'server returned (\d{3})\b', caseSensitive: false),
  RegExp(r'\bhttp(?:/\d(?:\.\d)?)? (\d{3})\b', caseSensitive: false),
  RegExp(r'\bstatus(?: code)?[:= ]+(\d{3})\b', caseSensitive: false),
];
final _ffmpegClass = RegExp(
  r'server returned ([45])xx\b',
  caseSensitive: false,
);

/// Extracts an HTTP error status (400-599) from an engine error message.
int? httpStatusFromMessage(String message) {
  for (final pattern in _httpStatusPatterns) {
    final match = pattern.firstMatch(message);
    if (match == null) continue;
    final code = int.parse(match[1]!);
    if (code >= 400 && code <= 599) return code;
  }
  final cls = _ffmpegClass.firstMatch(message);
  if (cls != null) return int.parse(cls[1]!) * 100;
  return null;
}

final _tlsPattern = RegExp(
  r'\b(tls|ssl|handshake|certificate|gnutls|mbedtls)\b',
  caseSensitive: false,
);

/// True when an error looks like a TLS failure (media_kit #1437 lacks
/// TLS 1.3 on some builds), which ExoPlayer usually handles.
bool looksLikeTlsError(String message) => _tlsPattern.hasMatch(message);
