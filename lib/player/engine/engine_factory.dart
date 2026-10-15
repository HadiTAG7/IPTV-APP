import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart' show VideoViewType;

import 'exo_engine.dart';
import 'mpv_engine.dart';
import 'player_engine.dart';

export 'package:video_player/video_player.dart' show VideoViewType;

/// Creates a fresh engine of [kind]. The playback controller owns the result.
typedef EngineFactory = PlayerEngine Function(EngineKind kind);

/// User settings that shape new engines.
@immutable
class EngineOptions {
  const EngineOptions({
    this.lite = false,
    this.hardwareDecoding = true,
    this.exoViewType = VideoViewType.textureView,
    this.preferredLanguages = kDefaultPreferredLanguages,
    this.subtitleLanguages,
  });

  /// Low-RAM mode: smaller mpv cache.
  final bool lite;

  /// mpv hardware decoding (`auto-safe`) or software only.
  final bool hardwareDecoding;

  /// Texture (default) or platform view for ExoPlayer.
  final VideoViewType exoViewType;

  /// Audio/subtitle language order for mpv, e.g. `['ara', 'ar', 'en']`.
  final List<String> preferredLanguages;

  /// Subtitle language order for mpv when it differs from the audio one;
  /// null uses [preferredLanguages].
  final List<String>? subtitleLanguages;
}

/// The production factory: ExoPlayer via `video_player`, mpv via media_kit.
///
/// mpv engines need `MediaKit.ensureInitialized()` first (done in bootstrap)
/// and borrow the app's one libmpv core ([MpvCore.shared]).
EngineFactory defaultEngineFactory([
  EngineOptions options = const EngineOptions(),
]) {
  return (kind) => switch (kind) {
    EngineKind.exo => ExoEngine(viewType: options.exoViewType),
    EngineKind.mpv => MpvEngine(
      lite: options.lite,
      hardwareDecoding: options.hardwareDecoding,
      preferredLanguages: options.preferredLanguages,
      subtitleLanguages: options.subtitleLanguages,
    ),
  };
}
