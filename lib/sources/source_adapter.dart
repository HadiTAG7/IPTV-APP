import 'models.dart';

/// One implementation per source type (M3U URL/file, Xtream).
///
/// Adapters are pure: they never touch the database. The sync service consumes
/// [fetchCatalog] and persists the batches. Implementations must throw only
/// [SourceFailure] subclasses and must never include credentials in messages.
abstract interface class SourceAdapter {
  SourceCapabilities get caps;

  /// Checks that the source is reachable and the login is valid.
  Future<AccountInfo> verify();

  /// Streams the catalog. Order: live categories + channels, then movies, then
  /// series. Emits [PhaseDoneBatch] after each family. Batches are bounded
  /// (a few thousand items) so memory stays flat on low-RAM TV boxes.
  Stream<SyncBatch> fetchCatalog([SyncScope scope = SyncScope.all]);

  /// Lazy series details (seasons + episodes). M3U adapters return what the
  /// playlist already contained, or throw [ParseFailure] if unknown.
  Future<SeriesDetail> seriesDetail(String seriesKey);

  /// Lazy movie details, or null when the source has none.
  Future<MovieDetail?> movieDetail(String movieKey);

  /// Pure URL + headers resolution. Never performs I/O.
  StreamRequest resolve(PlayableRef ref, {Duration? startAt});

  /// Guide URLs known for this source (may grow after a sync via
  /// [EpgHintBatch]).
  List<EpgSourceSpec> epgSpecs();

  /// Cancels in-flight requests.
  void close();
}
