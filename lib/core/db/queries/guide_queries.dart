import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../../../sources/models.dart';
import '../app_db.dart';

/// Reads the guide screens need beyond [EpgDao].
extension GuideQueries on AppDatabase {
  /// Whether some channel of [sourceId] is linked to a guide channel with
  /// stored programmes on an enabled guide source.
  Future<bool> hasGuideData(int sourceId) async =>
      _hasGuideData(sourceId).map(_readHas).getSingle();

  /// [hasGuideData], emitted again after every change to the guide tables
  /// (imports, links, guide sources).
  Stream<bool> watchHasGuideData(int sourceId) =>
      _hasGuideData(sourceId).watchSingle().map(_readHas);

  /// Keys of the favourite channels of [sourceId] that are in its
  /// committed catalog, in favourite order (favourites of vanished channels
  /// are left out); emitted again when the list changes.
  Stream<List<String>> watchAvailableFavoriteChannelKeys(int sourceId) =>
      customSelect(
            'SELECT f."key" AS k FROM favorites f '
            'JOIN channels c ON c.source_id = f.source_id AND c."key" = f."key" '
            'WHERE f.source_id = ?1 AND f.kind = ?2 '
            'AND c.first_gen <= (SELECT generation FROM sources WHERE id = ?1) '
            'ORDER BY f.position, f."key"',
            variables: [
              Variable.withInt(sourceId),
              Variable.withString(ContentKind.live.name),
            ],
            readsFrom: {favorites, channels, sources},
          )
          .watch()
          .map((rows) => [for (final r in rows) r.read<String>('k')])
          .distinct(listEquals);

  Selectable<QueryRow> _hasGuideData(int sourceId) => customSelect(
    'SELECT EXISTS (SELECT 1 FROM channel_epg_map m '
    'JOIN epg_sources es ON es.id = m.epg_source_id AND es.enabled = 1 '
    'JOIN programmes p ON p.epg_source_id = m.epg_source_id '
    'AND p.xmltv_id = m.xmltv_id '
    'WHERE m.source_id = ?1) AS has',
    variables: [Variable.withInt(sourceId)],
    readsFrom: {channelEpgMap, epgSources, programmes},
  );
}

bool _readHas(QueryRow row) => row.read<int>('has') != 0;
