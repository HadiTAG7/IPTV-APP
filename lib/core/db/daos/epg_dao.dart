import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../epg/epg_models.dart';
import '../../../sources/models.dart';
import '../../net/redact.dart';
import '../../secure/secret_store.dart';
import '../app_db.dart';
import 'query_utils.dart';

/// Guide sources, guide data and the channel → guide map.
class EpgDao extends DatabaseAccessor<AppDatabase> {
  EpgDao(super.attachedDatabase);

  /// How far ahead [nowNext] looks for the next programme.
  static const nextHorizon = Duration(hours: 24);

  /// Guide channel ids per statement in the chunked programme deletes
  /// ([pruneGuide], the end of a guide import). The connection is shared
  /// with the UI (see `AppDatabase.open`), so each statement must be short.
  static const idChunk = 200;

  // -------------------------------------------------------------------------
  // epg_sources.

  /// Adds a guide URL for [sourceId], or returns the id of the existing entry
  /// with the same URL (its settings are kept).
  ///
  /// A URL with credentials (Xtream `xmltv.php?username=..&password=..`) is
  /// stored masked and in full in [secrets] (default: this database, in the
  /// same transaction); fetch with [epgSourceUrl].
  Future<int> addEpgSource(
    int sourceId,
    String url,
    EpgOrigin origin, {
    int priority = 0,
    bool enabled = true,
    SecretStore? secrets,
  }) {
    final store = secrets ?? DbSecretStore(db);
    final masked = redact(url);
    return transaction(() async {
      final row = await into(db.epgSources).insertReturning(
        EpgSourcesCompanion.insert(
          sourceId: sourceId,
          url: masked,
          origin: origin,
          priority: Value(priority),
          enabled: Value(enabled),
        ),
        onConflict: DoUpdate(
          (_) => EpgSourcesCompanion(url: Value(masked)),
          target: [db.epgSources.sourceId, db.epgSources.url],
        ),
      );
      final name = SecretNames.epgUrl(row.id);
      if (masked == url) {
        await store.delete(sourceId, name);
      } else {
        await store.write(sourceId, name, url);
      }
      return row.id;
    });
  }

  /// Full URL of a guide source (credentials included), or null.
  Future<String?> epgSourceUrl(int epgSourceId, [SecretStore? secrets]) async {
    final row = await epgSourceById(epgSourceId);
    if (row == null) return null;
    final store = secrets ?? DbSecretStore(db);
    return await store.read(row.sourceId, SecretNames.epgUrl(epgSourceId)) ??
        row.url;
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

  /// Deletes a guide source with its channels, programmes, map entries and
  /// saved URL.
  Future<void> deleteEpgSource(int id, {SecretStore? secrets}) =>
      transaction(() async {
        final row = await epgSourceById(id);
        if (row == null) return;
        await (delete(db.epgSources)..where((e) => e.id.equals(id))).go();
        await (secrets ?? DbSecretStore(db)).delete(
          row.sourceId,
          SecretNames.epgUrl(id),
        );
      });

  /// Forgets the validators and import time of every guide of [sourceId],
  /// so the next refresh downloads each one in full instead of skipping it
  /// or getting a 304 (after a change that applies at import, such as the
  /// source's guide offset).
  Future<void> forgetGuideVersions(int sourceId) =>
      (update(db.epgSources)..where((e) => e.sourceId.equals(sourceId))).write(
        const EpgSourcesCompanion(
          etag: Value(null),
          lastModified: Value(null),
          lastFetchAt: Value(null),
        ),
      );

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
  ///
  /// One statement over the whole table (there is no index on the stop
  /// time): prefer [pruneGuide] while the app is in use.
  Future<int> pruneProgrammes(DateTime before) => (delete(
    db.programmes,
  )..where((p) => p.stopUtc.isSmallerOrEqualValue(toEpochSec(before)))).go();

  /// Removes the programmes of guide [epgSourceId] that ended at or before
  /// [before]; returns how many. Each statement covers [idChunk] guide
  /// channels, a primary-key range each, so readers are never held up long.
  Future<int> pruneGuide(int epgSourceId, DateTime before) async {
    var removed = 0;
    for (final ids in chunked(await programmeIds(epgSourceId), idChunk)) {
      removed += await customUpdate(
        'DELETE FROM programmes WHERE epg_source_id = ?1 '
        'AND xmltv_id IN (SELECT value FROM json_each(?2)) '
        'AND stop_utc <= ?3',
        variables: [
          Variable.withInt(epgSourceId),
          Variable.withString(jsonEncode(ids)),
          Variable.withInt(toEpochSec(before)),
        ],
        updates: {db.programmes},
        updateKind: UpdateKind.delete,
      );
    }
    return removed;
  }

  /// Removes every programme of [ids] (at most [idChunk] or so) in guide
  /// [epgSourceId]; returns how many.
  Future<int> deleteProgrammesOfIds(int epgSourceId, List<String> ids) =>
      customUpdate(
        'DELETE FROM programmes WHERE epg_source_id = ?1 '
        'AND xmltv_id IN (SELECT value FROM json_each(?2))',
        variables: [
          Variable.withInt(epgSourceId),
          Variable.withString(jsonEncode(ids)),
        ],
        updates: {db.programmes},
        updateKind: UpdateKind.delete,
      );

  /// Guide channel ids (as stored) that have programmes in guide
  /// [epgSourceId], in id order. One index seek per id, so it does not read
  /// every programme of the guide.
  Future<List<String>> programmeIds(int epgSourceId) async {
    final rows = await customSelect(
      'WITH RECURSIVE ids(x) AS ('
      'SELECT (SELECT min(xmltv_id) FROM programmes WHERE epg_source_id = ?1) '
      'UNION ALL '
      'SELECT (SELECT min(xmltv_id) FROM programmes '
      'WHERE epg_source_id = ?1 AND xmltv_id > ids.x) '
      'FROM ids WHERE ids.x IS NOT NULL'
      ') SELECT x FROM ids WHERE x IS NOT NULL',
      variables: [Variable.withInt(epgSourceId)],
      readsFrom: {db.programmes},
    ).get();
    return [for (final r in rows) r.read<String>('x')];
  }

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
  /// earliest one starting after [now] (within [nextHorizon]). Each channel's
  /// `tvg-shift` is applied (see [programmesForChannels]). Channels without
  /// guide data are absent from the result. Disabled guide sources are
  /// ignored.
  Future<Map<String, NowNext>> nowNext(
    int sourceId,
    List<String> channelKeys,
    DateTime now,
  ) async {
    final result = <String, NowNext>{};
    final t = toEpochSec(now);
    final horizon = toEpochSec(now.add(nextHorizon));
    for (final keys in chunked(channelKeys.toSet().toList())) {
      // `q.t` and `q.h` are now and the horizon in the guide's own time.
      final rows = await customSelect(
        'SELECT * FROM ('
        'SELECT q.ck, q.sh, p.*, '
        'CASE WHEN p.start_utc <= q.t THEN 0 ELSE 1 END AS slot, '
        'ROW_NUMBER() OVER (PARTITION BY q.ck, p.start_utc <= q.t '
        'ORDER BY CASE WHEN p.start_utc <= q.t THEN -p.start_utc '
        'ELSE p.start_utc END) AS rn '
        'FROM (${_linkedChannelsSql(keys.length)}) q '
        'JOIN programmes p ON p.epg_source_id = q.esid '
        'AND p.xmltv_id = q.xid AND p.stop_utc > q.t AND p.start_utc < q.h'
        ') WHERE rn = 1',
        variables: [
          Variable.withInt(sourceId),
          Variable.withInt(t),
          Variable.withInt(horizon),
          for (final k in keys) Variable.withString(k),
        ],
        readsFrom: _guideTables,
      ).get();
      for (final r in rows) {
        final key = r.read<String>('ck');
        final programme = _programme(r);
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
  ///
  /// Programme times are stored as the guide publishes them; a channel's
  /// `tvg-shift` (`channels.tvgShiftMin`, which already falls back to the
  /// playlist header) is added here, so several playlist channels can share
  /// one guide id with different shifts. Importers must not apply it again.
  Future<Map<String, List<EpgProgramme>>> programmesForChannels(
    int sourceId,
    List<String> channelKeys,
    DateTime from,
    DateTime to,
  ) async {
    final result = <String, List<EpgProgramme>>{};
    for (final keys in chunked(channelKeys.toSet().toList())) {
      final rows = await customSelect(
        'SELECT q.ck, q.sh, p.* FROM (${_linkedChannelsSql(keys.length)}) q '
        'JOIN programmes p ON p.epg_source_id = q.esid '
        'AND p.xmltv_id = q.xid AND p.stop_utc > q.t AND p.start_utc < q.h '
        'ORDER BY q.ck, p.start_utc',
        variables: [
          Variable.withInt(sourceId),
          Variable.withInt(toEpochSec(from)),
          Variable.withInt(toEpochSec(to)),
          for (final k in keys) Variable.withString(k),
        ],
        readsFrom: _guideTables,
      ).get();
      for (final r in rows) {
        (result[r.read<String>('ck')] ??= []).add(_programme(r));
      }
    }
    return result;
  }

  Set<ResultSetImplementation<HasResultSet, Object?>> get _guideTables => {
    db.channelEpgMap,
    db.epgSources,
    db.programmes,
    db.channels,
  };

  /// Programme with its times moved by the channel shift `sh` (seconds).
  EpgProgramme _programme(QueryRow r) {
    final p = db.programmes.map(r.data);
    final shift = r.read<int>('sh');
    return (shift == 0
            ? p
            : p.copyWith(
                startUtc: p.startUtc + shift,
                stopUtc: p.stopUtc + shift,
              ))
        .toProgramme();
  }
}

/// Linked channels among `?4...` of source `?1` on enabled guide sources,
/// with their shift `sh` (seconds) and the times `?2`, `?3` moved into guide
/// time as `t`, `h`.
String _linkedChannelsSql(int keyCount) =>
    'SELECT m.channel_key AS ck, m.epg_source_id AS esid, m.xmltv_id AS xid, '
    'COALESCE(c.tvg_shift_min, 0) * 60 AS sh, '
    '?2 - COALESCE(c.tvg_shift_min, 0) * 60 AS t, '
    '?3 - COALESCE(c.tvg_shift_min, 0) * 60 AS h '
    'FROM channel_epg_map m '
    'JOIN epg_sources es ON es.id = m.epg_source_id AND es.enabled = 1 '
    'LEFT JOIN channels c ON c.source_id = m.source_id '
    'AND c."key" = m.channel_key '
    'WHERE m.source_id = ?1 '
    'AND m.channel_key IN (${sqlParams(keyCount, 4)})';
