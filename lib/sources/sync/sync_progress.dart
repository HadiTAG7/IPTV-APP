import 'package:flutter/foundation.dart';

import '../source_repository.dart';

/// Where a catalog sync is.
enum SyncPhase {
  /// Checking the login / playlist.
  verifying,

  /// Fetching and writing live categories and channels.
  live,
  movies,
  series,

  /// Making the new catalog visible (generation swap) and saving guide URLs.
  saving,
  done,
  failed,
  cancelled;

  bool get isTerminal => this == done || this == failed || this == cancelled;
}

/// A snapshot of one sync: counts written so far and the current phase.
///
/// Plain data (no closures), so it can cross isolates.
@immutable
class SyncProgress {
  const SyncProgress({
    required this.sourceId,
    this.phase = SyncPhase.verifying,
    this.categories = 0,
    this.channels = 0,
    this.movies = 0,
    this.series = 0,
    this.episodes = 0,
    this.error,
  });

  final int sourceId;
  final SyncPhase phase;
  final int categories;
  final int channels;
  final int movies;
  final int series;

  /// Episodes stored during the sync (M3U; Xtream loads them per series).
  final int episodes;

  /// Why the sync failed ([SyncPhase.failed] only).
  final VerifyError? error;

  bool get isDone => phase == SyncPhase.done;
  bool get isFailed => phase == SyncPhase.failed;
  bool get isCancelled => phase == SyncPhase.cancelled;
  bool get isTerminal => phase.isTerminal;

  /// Channels, movies, series and episodes written so far.
  int get items => channels + movies + series + episodes;

  SyncProgress copyWith({
    SyncPhase? phase,
    int? categories,
    int? channels,
    int? movies,
    int? series,
    int? episodes,
    VerifyError? error,
  }) => SyncProgress(
    sourceId: sourceId,
    phase: phase ?? this.phase,
    categories: categories ?? this.categories,
    channels: channels ?? this.channels,
    movies: movies ?? this.movies,
    series: series ?? this.series,
    episodes: episodes ?? this.episodes,
    error: error ?? this.error,
  );

  @override
  bool operator ==(Object other) =>
      other is SyncProgress &&
      other.sourceId == sourceId &&
      other.phase == phase &&
      other.categories == categories &&
      other.channels == channels &&
      other.movies == movies &&
      other.series == series &&
      other.episodes == episodes &&
      other.error == error;

  @override
  int get hashCode => Object.hash(
    sourceId,
    phase,
    categories,
    channels,
    movies,
    series,
    episodes,
    error,
  );

  @override
  String toString() =>
      'SyncProgress(#$sourceId ${phase.name}: $channels channels, '
      '$movies movies, $series series, $episodes episodes'
      '${error == null ? '' : ', $error'})';
}

/// Sync state of one source, for the UI.
@immutable
sealed class SyncStatus {
  const SyncStatus();

  bool get isRunning => this is SyncRunning;
}

/// No sync has run for this source since the app started.
final class SyncIdle extends SyncStatus {
  const SyncIdle();

  @override
  bool operator ==(Object other) => other is SyncIdle;

  @override
  int get hashCode => 0;
}

final class SyncRunning extends SyncStatus {
  const SyncRunning(this.progress);

  final SyncProgress progress;

  @override
  bool operator ==(Object other) =>
      other is SyncRunning && other.progress == progress;

  @override
  int get hashCode => progress.hashCode;
}

/// The last sync committed a new catalog.
final class SyncDone extends SyncStatus {
  const SyncDone(this.progress, {required this.finishedAt});

  final SyncProgress progress;
  final DateTime finishedAt;

  @override
  bool operator ==(Object other) =>
      other is SyncDone &&
      other.progress == progress &&
      other.finishedAt == finishedAt;

  @override
  int get hashCode => Object.hash(progress, finishedAt);
}

/// The last sync failed or was cancelled; the previous catalog is intact.
final class SyncFailed extends SyncStatus {
  const SyncFailed(this.progress);

  final SyncProgress progress;

  bool get cancelled => progress.isCancelled;

  /// Null when [cancelled].
  VerifyError? get error => progress.error;

  @override
  bool operator ==(Object other) =>
      other is SyncFailed && other.progress == progress;

  @override
  int get hashCode => progress.hashCode;
}
