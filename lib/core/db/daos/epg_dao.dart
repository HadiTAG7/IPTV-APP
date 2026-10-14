import 'package:drift/drift.dart';

import '../../../epg/epg_models.dart';
import '../../../sources/models.dart';
import '../app_db.dart';
import 'query_utils.dart';

/// Guide sources, guide data and the channel → guide map.
class EpgDao extends DatabaseAccessor<AppDatabase> {
  EpgDao(super.attachedDatabase);

  /// How far ahead [nowNext] looks for the next programme.
  static const nextHorizon = Duration(hours: 24);

  // -------------------------------------------------------------------------
  // epg_sources.

  /// Adds a guide URL for [sourceId], or returns the id of the existing entry
  /// with the same URL (its settings are kept).
  Future<int> addEpgSource(
    int sourceId,
    String url,
    EpgOrigin origin, {
    int priority = 0,
    bool enabled = true,
  }) async {
    final row = await into(db.epgSources).insertReturning(
      EpgSourcesCompanion.insert(
        sourceId: sourceId,
        url: url,
        origin: origin,
        priority: Value(priority),
        enabled: Value(enabled),
      ),
      onConflict: DoUpdate(
        (_) => EpgSourcesCompanion(url: Value(url)),
        target: [db.epgSources.sourceId, db.epgSources.url],
      ),
    );
    return row.id;
  }

  SimpleSelectStatement<$EpgSourcesTable, EpgSourceRecord> _sourcesOf(
    int sourceId,
    bool enabledOnly,
  ) => select(db.epgSources)
    ..where(
      (e) =>
          e.sourceId.equals(sourceId) &
          (enabledOnly ? e.enabled.equals(true) : const Constant(true)),
    )
    ..orderBy([
      (e) => OrderingTerm.asc(e.priority),
      (e) => OrderingTerm.asc(e.id),
    ]);

  /// Guide sources of a source in priority order.
  Future<List<EpgSourceRow>> epgSources(
    int sourceId, {
    bool enabledOnly = false,
  }) async => [
    for (final r in await _sourcesOf(sourceId, enabledOnly).get()) r.toRow(),
  ];

  Stream<List<EpgSourceRow>> watchEpgSources(int sourceId) => _sourcesOf(
    sourceId,
    false,
  ).watch().map((rows) => [for (final r in rows) r.toRow()]);

  Future<EpgSourceRow?> epgSourceById(int id) async => (await (select(
    db.epgSources,
  )..where((e) => e.id.equals(id))).getSingleOrNull())?.toRow();

  Future<void> setEpgSourceEnabled(int id, bool enabled) =>
      _writeSource(id, EpgSourcesCompanion(enabled: Value(enabled)));

  Future<void> setEpgSourcePriority(int id, int priority) =>
      _writeSource(id, EpgSourcesCompanion(priority: Value(priority)));

  /// Records a download attempt. Null arguments leave fields unchanged,
  /// except [at] which defaults to now.
  Future<void> recordFetch(
    int id, {
    DateTime? at,
    String? etag,
    String? lastModified,
    String? status,
    int? programmeCount,
  }) => _writeSource(
    id,
    EpgSourcesCompanion(
      lastFetchAt: Value(toEpochSec(at ?? db.clock.now())),
      etag: etag == null ? const Value.absent() : Value(etag),
      lastModified: lastModified == null
          ? const Value.absent()
          : Value(lastModified),
      status: status == null ? const Value.absent() : Value(status),
      programmeCount: programmeCount == null
          ? const Value.absent()
          : Value(programmeCount),
    ),
  );

  /// Deletes a guide source with its channels, programmes and map entries.
  Future<void> deleteEpgSource(int id) =>
      (delete(db.epgSources)..where((e) => e.id.equals(id))).go();

  Future<void> _writeSource(int id, EpgSourcesCompanion values) =>
      (update(db.epgSources)..where((e) => e.id.equals(id))).write(values);

  // -------------------------------------------------------------------------
  // Guide channels and programmes.

  Future<void> upsertEpgChannels(int epgSourceId, List<EpgChannel> channels) =>
      batch((b) {
        b.insertAllOnConflictUpdate(db.epgChannels, [
          for (final c in channels) epgChannelCompanion(epgSourceId, c),
        ]);
      });

  Future<List<EpgChannelRow>> epgChannels(int epgSourceId) async {
    final rows =
        await (select(db.epgChannels)
              ..where((c) => c.epgSourceId.equals(epgSourceId))
              ..orderBy([(c) => OrderingTerm.asc(c.xmltvId)]))
            .get();
    return [for (final r in rows) r.toRow()];
  }

  /// Inserts one batch (a few thousand rows) in one short transaction.
  /// Same (channel, start) replaces the earlier row.
  Future<void> insertProgrammes(
    int epgSourceId,
    List<EpgProgramme> programmes,
  ) async {
    if (programmes.isEmpty) return;
    await batch((b) {
      b.insertAll(db.programmes, [
        for (final p in programmes) programmeCompanion(epgSourceId, p),
      ], mode: InsertMode.insertOrReplace);
    });
  }

  /// Removes all programmes of one guide source (before a full re-import).
  Future<int> deleteProgrammesOf(int epgSourceId) => (delete(
    db.programmes,
  )..where((p) => p.epgSourceId.equals(epgSourceId))).go();

  /// Removes programmes that ended at or before [before]; returns how many.
  Future<int> pruneProgrammes(DateTime before) => (delete(
    db.programmes,
  )..where((p) => p.stopUtc.isSmallerOrEqualValue(toEpochSec(before)))).go();

  Future<int> programmeCount(int epgSourceId) async {
    final count = db.programmes.xmltvId.count();
    return (selectOnly(db.programmes)
          ..addColumns([count])
          ..where(db.programmes.epgSourceId.equals(epgSourceId)))
        .map((r) => r.read(count)!)
        .getSingle();
  }

  // -------------------------------------------------------------------------
  // channel_epg_map.

  /// Replaces the automatic links of a source with [links]
  /// (channelKey → link). Manual links are kept and always win.
  Future<void> replaceChannelMap(int sourceId, Map<String, EpgLink> links) =>
      transaction(() async {
        await (delete(db.channelEpgMap)..where(
              (m) =>
                  m.sourceId.equals(sourceId) &
                  m.matchKind.equalsValue(EpgMatchKind.manual).not(),
            ))
            .go();
        await batch((b) {
          b.insertAll(db.channelEpgMap, [
            for (final MapEntry(key: channelKey, value: link) in links.entries)
              ChannelEpgMapCompanion.insert(
                sourceId: sourceId,
                channelKey: channelKey,
                epgSourceId: link.epgSourceId,
                xmltvId: link.xmltvId,
                matchKind: link.kind,
              ),
          ], mode: InsertMode.insertOrIgnore);
        });
      });

  /// Links a channel to a guide channel by hand ("Assign guide channel").
  Future<void> setManualLink(
    int sourceId,
    String channelKey,
    int epgSourceId,
    String xmltvId,
  ) => into(db.channelEpgMap).insertOnConflictUpdate(
    ChannelEpgMapCompanion.insert(
      sourceId: sourceId,
      channelKey: channelKey,
      epgSourceId: epgSourceId,
      xmltvId: xmltvId,
      matchKind: EpgMatchKind.manual,
    ),
  );

  /// Removes the link of a channel (manual or automatic).
  Future<void> clearLink(int sourceId, String channelKey) =>
      (delete(db.channelEpgMap)..where(
            (m) =>
                m.sourceId.equals(sourceId) & m.channelKey.equals(channelKey),
          ))
          .go();

  Future<EpgLink?> linkFor(int sourceId, String channelKey) async {
    final r =
        await (select(db.channelEpgMap)..where(
              (m) =>
                  m.sourceId.equals(sourceId) & m.channelKey.equals(channelKey),
            ))
            .getSingleOrNull();
    return r == null ? null : _link(r);
  }

  /// All links of a source, by channel key.
  Future<Map<String, EpgLink>> linksFor(int sourceId) async {
    final rows = await (select(
      db.channelEpgMap,
    )..where((m) => m.sourceId.equals(sourceId))).get();
    return {for (final r in rows) r.channelKey: _link(r)};
  }

  /// Guide channel ids some channel is linked to; the importer keeps only
  /// these programmes.
  Future<Set<String>> linkedXmltvIds(int epgSourceId) async {
    final q = selectOnly(db.channelEpgMap, distinct: true)
      ..addColumns([db.channelEpgMap.xmltvId])
      ..where(db.channelEpgMap.epgSourceId.equals(epgSourceId));
    return {
      for (final id
          in await q.map((r) => r.read(db.channelEpgMap.xmltvId)!).get())
        id,
    };
  }

  EpgLink _link(ChannelEpgMapRecord r) =>
      (epgSourceId: r.epgSourceId, xmltvId: r.xmltvId, kind: r.matchKind);

  // -------------------------------------------------------------------------
  // Reads for lists, OSD and guide.

  /// Current and next programme for each of [channelKeys] in one query.
  ///
  /// "Now" is the latest programme with `start <= now < stop`; "next" is the
  /// earliest one starting after [now] (within [nextHorizon]). Channels
  /// without guide data are absent from the result. Disabled guide sources
  /// are ignored.
  Future<Map<String, NowNext>> nowNext(
    int sourceId,
    List<String> channelKeys,
    DateTime now,
  ) async {
    final result = <String, NowNext>{};
    final t = toEpochSec(now);
    final horizon = toEpochSec(now.add(nextHorizon));
    for (final keys in chunked(channelKeys.toSet().toList())) {
      final rows = await customSelect(
        'SELECT * FROM ('
        'SELECT m.channel_key AS ck, p.*, '
        'CASE WHEN p.start_utc <= ?2 THEN 0 ELSE 1 END AS slot, '
        'ROW_NUMBER() OVER (PARTITION BY m.channel_key, p.start_utc <= ?2 '
        'ORDER BY CASE WHEN p.start_utc <= ?2 THEN -p.start_utc '
        'ELSE p.start_utc END) AS rn '
        'FROM channel_epg_map m '
        'JOIN epg_sources es ON es.id = m.epg_source_id AND es.enabled = 1 '
        'JOIN programmes p ON p.epg_source_id = m.epg_source_id '
        'AND p.xmltv_id = m.xmltv_id '
        'WHERE m.source_id = ?1 AND m.channel_key IN (${sqlParams(keys.length, 4)}) '
        'AND p.stop_utc > ?2 AND p.start_utc < ?3'
        ') WHERE rn = 1',
        variables: [
          Variable.withInt(sourceId),
          Variable.withInt(t),
          Variable.withInt(horizon),
          for (final k in keys) Variable.withString(k),
        ],
        readsFrom: {db.channelEpgMap, db.epgSources, db.programmes},
      ).get();
      for (final r in rows) {
        final key = r.read<String>('ck');
        final programme = db.programmes.map(r.data).toProgramme();
        final current = result[key] ?? (now: null, next: null);
        result[key] = r.read<int>('slot') == 0
            ? (now: programme, next: current.next)
            : (now: current.now, next: programme);
      }
    }
    return result;
  }

  /// Programmes overlapping `[from, to)` per channel key, ordered by start.
  /// Channels without guide data are absent.
  Future<Map<String, List<EpgProgramme>>> programmesForChannels(
    int sourceId,
    List<String> channelKeys,
    DateTime from,
    DateTime to,
  ) async {
    final result = <String, List<EpgProgramme>>{};
    for (final keys in chunked(channelKeys.toSet().toList())) {
      final rows = await customSelect(
        'SELECT m.channel_key AS ck, p.* FROM channel_epg_map m '
        'JOIN epg_sources es ON es.id = m.epg_source_id AND es.enabled = 1 '
        'JOIN programmes p ON p.epg_source_id = m.epg_source_id '
        'AND p.xmltv_id = m.xmltv_id '
        'WHERE m.source_id = ?1 AND m.channel_key IN (${sqlParams(keys.length, 4)}) '
        'AND p.stop_utc > ?2 AND p.start_utc < ?3 '
        'ORDER BY m.channel_key, p.start_utc',
        variables: [
          Variable.withInt(sourceId),
          Variable.withInt(toEpochSec(from)),
          Variable.withInt(toEpochSec(to)),
          for (final k in keys) Variable.withString(k),
        ],
        readsFrom: {db.channelEpgMap, db.epgSources, db.programmes},
      ).get();
      for (final r in rows) {
        (result[r.read<String>('ck')] ??= []).add(
          db.programmes.map(r.data).toProgramme(),
        );
      }
    }
    return result;
  }
}
