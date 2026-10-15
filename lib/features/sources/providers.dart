// Providers of the source management feature (editor, import, list).
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../sources/models.dart';
import '../../sources/source_repository.dart';

/// A playlist file picked on the device.
class PickedPlaylist {
  const PickedPlaylist({
    required this.name,
    this.path,
    this.openRead,
    this.isTemporary = false,
  });

  /// File name for display (and the default source name).
  final String name;

  /// Local path, when the picker gave one.
  final String? path;

  /// Reads the file when there is no [path] (content URIs).
  final Stream<List<int>> Function()? openRead;

  /// A temporary copy the editor deletes once imported (phone uploads).
  final bool isTemporary;
}

/// Opens the system file picker; null when the user cancels.
typedef PlaylistPicker = Future<PickedPlaylist?> Function();

/// The picker used by the source editor (tests override it).
final playlistPickerProvider = Provider<PlaylistPicker>(
  (ref) => pickPlaylistFile,
);

/// `PlatformException.code` of [pickPlaylistFile] when the device has no
/// system file picker: Fire TV and most Android TV builds lack the document
/// picker that `file_picker` opens.
const noFilePickerCode = 'explorer_not_found';

/// [PlaylistPicker] backed by `file_picker`. Any file type is allowed:
/// Android has no reliable MIME type for `.m3u`, and playlists are often
/// saved as `.txt`.
Future<PickedPlaylist?> pickPlaylistFile() async {
  final file = await FilePicker.pickFile();
  if (file == null) return null;
  return PickedPlaylist(
    name: file.name,
    path: file.path,
    openRead: file.readAsByteStream,
  );
}

/// Committed item counts of one source.
class SourceCounts {
  const SourceCounts({this.live = 0, this.movies = 0, this.series = 0});

  final int live;
  final int movies;
  final int series;

  @override
  bool operator ==(Object other) =>
      other is SourceCounts &&
      other.live == live &&
      other.movies == movies &&
      other.series == series;

  @override
  int get hashCode => Object.hash(live, movies, series);
}

/// Item counts of a source, keyed by its id and committed generation so a
/// finished sync (new generation) counts again.
final sourceCountsProvider = FutureProvider.autoDispose
    .family<SourceCounts, ({int id, int generation, DateTime? syncedAt})>((
      ref,
      key,
    ) async {
      if (key.generation == 0) return const SourceCounts();
      final catalog = ref.watch(catalogDaoProvider);
      return SourceCounts(
        live: await catalog.totalCount(key.id, ContentKind.live),
        movies: await catalog.totalCount(key.id, ContentKind.movie),
        series: await catalog.totalCount(key.id, ContentKind.series),
      );
    });

/// The counts key of [source].
({int id, int generation, DateTime? syncedAt}) countsKeyOf(SourceView s) =>
    (id: s.id, generation: s.generation, syncedAt: s.lastSyncAt);
