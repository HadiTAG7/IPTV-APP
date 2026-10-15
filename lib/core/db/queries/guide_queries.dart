import 'package:drift/drift.dart';

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
