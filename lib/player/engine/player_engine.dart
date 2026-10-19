import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../sources/models.dart';

/// Which backend plays a stream.
enum EngineKind {
  /// ExoPlayer / Media3 via `video_player` (Android only).
  exo,

  /// libmpv via `media_kit` (Android, Windows, Linux).
  mpv,
}

/// Snapshot of playback, published through [PlayerEngine.state].
@immutable
class PlaybackState {
  const PlaybackState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffering = false,
    this.playing = false,
    this.videoSize,
    this.hasFirstFrame = false,
  });

  static const idle = PlaybackState();

  final Duration position;

  /// Zero for live streams or before metadata is known.
  final Duration duration;
  final bool buffering;
  final bool playing;
  final Size? videoSize;
  final bool hasFirstFrame;

  PlaybackState copyWith({
    Duration? position,
    Duration? duration,
    bool? buffering,
    bool? playing,
    Size? videoSize,
    bool? hasFirstFrame,
  }) => PlaybackState(
    position: position ?? this.position,
    duration: duration ?? this.duration,
    buffering: buffering ?? this.buffering,
    playing: playing ?? this.playing,
    videoSize: videoSize ?? this.videoSize,
    hasFirstFrame: hasFirstFrame ?? this.hasFirstFrame,
  );

  @override
  bool operator ==(Object other) =>
      other is PlaybackState &&
      other.position == position &&
      other.duration == duration &&
      other.buffering == buffering &&
      other.playing == playing &&
      other.videoSize == videoSize &&
      other.hasFirstFrame == hasFirstFrame;

  @override
  int get hashCode => Object.hash(
    position,
    duration,
    buffering,
    playing,
    videoSize,
    hasFirstFrame,
  );
}

/// Discrete things that happen during playback.
sealed class EngineEvent {
  const EngineEvent();
}

class FirstFrameEvent extends EngineEvent {
  const FirstFrameEvent();
}

class EndedEvent extends EngineEvent {
  const EndedEvent();
}

class ErrorEvent extends EngineEvent {
  const ErrorEvent(this.message, {this.fatal = true, this.httpStatus});

  /// Redacted, human readable. Never contains credentials.
  final String message;
  final bool fatal;
  final int? httpStatus;
}

/// An audio or subtitle track.
@immutable
class TrackInfo {
  const TrackInfo({
    required this.id,
    this.language,
    this.label,
    this.codec,
    this.selected = false,
  });

  final String id;
  final String? language;
  final String? label;
  final String? codec;
  final bool selected;

  String get displayName {
    final parts = [?label, ?language, ?codec];
    return parts.isEmpty ? id : parts.join(' · ');
  }
}

/// Aspect ratio modes offered in the player OSD.
enum AspectMode { fit, fill, stretch, ratio16x9, ratio4x3 }

/// A playback backend. One instance is owned by the playback controller.
///
/// Contract:
/// * [open] stops whatever was playing and opens [StreamRequest]; it completes
///   when the stream is opening (not necessarily playing).
/// * [stop] must close the network connection (single-connection panels).
/// * Errors are reported on [events], never thrown from [open] for stream
///   problems (only for programming errors).
abstract class PlayerEngine {
  EngineKind get kind;

  Future<void> open(StreamRequest request);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();

  ValueListenable<PlaybackState> get state;
  Stream<EngineEvent> get events;

  Future<List<TrackInfo>> audioTracks();
  Future<void> selectAudio(String id);

  /// Empty on engines without subtitle support (Exo via video_player).
  Future<List<TrackInfo>> subtitleTracks();
  Future<void> selectSubtitle(String? id);

  /// Short technical summary for the stats overlay (codec, resolution...).
  Future<Map<String, String>> stats();

  /// Playback volume from 0 (silent) to 1 (full, the default). It lasts
  /// for this engine (also across [open]s); a new engine starts at full.
  Future<void> setVolume(double volume);

  /// Mutes or unmutes without changing [setVolume]'s level; a new engine
  /// starts unmuted.
  Future<void> setMuted(bool muted);

  Widget buildView({AspectMode aspect = AspectMode.fit});

  Future<void> dispose();
}
