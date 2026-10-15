// Progress events of a guide refresh and the outcome stored per guide source.
//
// Events hold only plain values, so they can cross isolates unchanged.
import '../sources/models.dart';

/// Progress of one `EpgService.refresh` run for a source.
///
/// A run emits, per enabled guide source in priority order, an
/// [EpgGuideStarted] followed by either [EpgGuideNotModified], or
/// [EpgChannelsParsed] / [EpgChannelsMatched] / [EpgProgrammesStored]
/// updates and then [EpgGuideFinished], or [EpgGuideFailed]. Every run ends
/// with exactly one terminal event ([isTerminal]): [EpgRefreshDone],
/// [EpgRefreshFailed] or [EpgRefreshCancelled]. Errors are reported as
/// events, never as stream errors.
sealed class EpgProgress {
  const EpgProgress(this.sourceId);

  final int sourceId;

  /// Whether this is the last event of the run.
  bool get isTerminal => false;
}

/// Download of one guide source begins.
final class EpgGuideStarted extends EpgProgress {
  const EpgGuideStarted(
    super.sourceId, {
    required this.epgSourceId,
    required this.url,
    required this.origin,
    required this.index,
    required this.total,
  });

  final int epgSourceId;

  /// Guide URL with credentials masked.
  final String url;
  final EpgOrigin origin;

  /// Position of this guide in the run (0-based) and the number of guides.
  final int index;
  final int total;
}

/// The server answered 304: the stored guide is still current and is kept.
final class EpgGuideNotModified extends EpgProgress {
  const EpgGuideNotModified(
    super.sourceId, {
    required this.epgSourceId,
    required this.matched,
  });

  final int epgSourceId;

  /// Playlist channels linked to this guide.
  final int matched;
}

/// Guide channels read so far from the current guide.
final class EpgChannelsParsed extends EpgProgress {
  const EpgChannelsParsed(
    super.sourceId, {
    required this.epgSourceId,
    required this.channels,
  });

  final int epgSourceId;
  final int channels;
}

/// Playlist channels linked to the current guide so far (automatic matches
/// plus manual links to it). Sent again when late `<channel>` elements change
/// the result.
final class EpgChannelsMatched extends EpgProgress {
  const EpgChannelsMatched(
    super.sourceId, {
    required this.epgSourceId,
    required this.matched,
  });

  final int epgSourceId;
  final int matched;
}

/// Programmes written so far for the current guide.
final class EpgProgrammesStored extends EpgProgress {
  const EpgProgrammesStored(
    super.sourceId, {
    required this.epgSourceId,
    required this.programmes,
  });

  final int epgSourceId;
  final int programmes;
}

/// One guide was imported.
final class EpgGuideFinished extends EpgProgress {
  const EpgGuideFinished(
    super.sourceId, {
    required this.epgSourceId,
    required this.channels,
    required this.matched,
    required this.programmes,
  });

  final int epgSourceId;

  /// Guide channels stored for matching and manual assignment.
  final int channels;

  /// Playlist channels linked to this guide.
  final int matched;

  /// Programmes kept for this guide.
  final int programmes;
}

/// One guide failed; the run goes on with the next one. Data stored by an
/// earlier import is kept unless the download broke off midway.
final class EpgGuideFailed extends EpgProgress {
  const EpgGuideFailed(
    super.sourceId, {
    required this.epgSourceId,
    required this.message,
  });

  final int epgSourceId;

  /// Redacted, never contains credentials.
  final String message;
}

/// The run finished. Some guides may have failed ([failed]).
final class EpgRefreshDone extends EpgProgress {
  const EpgRefreshDone(
    super.sourceId, {
    this.guides = 0,
    this.imported = 0,
    this.notModified = 0,
    this.failed = 0,
    this.matched = 0,
    this.programmes = 0,
  });

  /// Enabled guide sources processed; 0 when there was nothing to do (no
  /// enabled guide, or no live channels to link).
  final int guides;
  final int imported;
  final int notModified;
  final int failed;

  /// Playlist channels linked to a guide, manual links included.
  final int matched;

  /// Programmes stored for this source's enabled guides after the run.
  final int programmes;

  @override
  bool get isTerminal => true;
}

/// The run failed as a whole: unknown source, implausible device clock, a
/// database error, or every guide failed.
final class EpgRefreshFailed extends EpgProgress {
  const EpgRefreshFailed(super.sourceId, {required this.message});

  /// Redacted, never contains credentials.
  final String message;

  @override
  bool get isTerminal => true;
}

/// The run was cancelled with `EpgService.cancel`.
final class EpgRefreshCancelled extends EpgProgress {
  const EpgRefreshCancelled(super.sourceId);

  @override
  bool get isTerminal => true;
}

/// Outcome of the latest attempt for a guide source.
enum EpgStatusKind {
  /// Imported.
  ok,

  /// The server answered 304; the stored guide was kept.
  notModified,

  /// The attempt failed; see [EpgSourceStatus.message].
  error,

  /// The attempt was cancelled.
  cancelled,
}

/// The `epg_sources.status` column, written by `EpgService`.
///
/// Stored as `ok`, `notModified`, `cancelled` or `error: <message>` so the
/// UI can localise the kind and show the (redacted) message.
class EpgSourceStatus {
  const EpgSourceStatus(this.kind, [this.message]);

  static const ok = EpgSourceStatus(EpgStatusKind.ok);
  static const notModified = EpgSourceStatus(EpgStatusKind.notModified);
  static const cancelled = EpgSourceStatus(EpgStatusKind.cancelled);

  final EpgStatusKind kind;

  /// Redacted error text for [EpgStatusKind.error].
  final String? message;

  static const _errorPrefix = 'error:';

  /// Parses a stored status; null when there is none yet (never attempted).
  /// Unknown text is read as an error message.
  static EpgSourceStatus? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final kind in EpgStatusKind.values) {
      if (kind != EpgStatusKind.error && raw == kind.name) {
        return EpgSourceStatus(kind);
      }
    }
    final message = raw.startsWith(_errorPrefix)
        ? raw.substring(_errorPrefix.length).trim()
        : raw;
    return EpgSourceStatus(EpgStatusKind.error, message);
  }

  String encode() => kind == EpgStatusKind.error
      ? '$_errorPrefix ${message ?? ''}'.trimRight()
      : kind.name;

  @override
  bool operator ==(Object other) =>
      other is EpgSourceStatus &&
      other.kind == kind &&
      other.message == message;

  @override
  int get hashCode => Object.hash(kind, message);

  @override
  String toString() => encode();
}
