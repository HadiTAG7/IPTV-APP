import 'package:drift/drift.dart';

import '../app_db.dart';

/// Recently watched live channels per source (newest first, capped).
class RecentDao extends DatabaseAccessor<AppDatabase> {
  RecentDao(super.attachedDatabase);

  /// Entries kept per source.
  static const maxEntries = 50;

  /// Moves [channelKey] to the top and trims the list to [maxEntries].
  Future<void> markRecent(int sourceId, String channelKey) =>
      transaction(() async {
        // Delete + insert gives the newest row the highest rowid, which breaks
        // ties between marks within the same second.
        await (delete(db.recentChannels)..where(
              (r) => r.sourceId.equals(sourceId) & r.key.equals(channelKey),
            ))
            .go();
        await into(db.recentChannels).insert(
          RecentChannelsCompanion.insert(
            sourceId: sourceId,
            key: channelKey,
            lastWatchedAt: toEpochSec(db.clock.now()),
          ),
        );
        await customUpdate(
          'DELETE FROM recent_channels WHERE source_id = ?1 AND rowid NOT IN ('
          'SELECT rowid FROM recent_channels WHERE source_id = ?1 '
          'ORDER BY last_watched_at DESC, rowid DESC LIMIT ?2)',
          variables: [Variable.withInt(sourceId), Variable.withInt(maxEntries)],
          updates: {db.recentChannels},
          updateKind: UpdateKind.delete,
        );
      });

  SimpleSelectStatement<$RecentChannelsTable, RecentChannelRecord> _ordered(
    int sourceId,
    int limit,
  ) => select(db.recentChannels)
    ..where((r) => r.sourceId.equals(sourceId))
    ..orderBy([
      (r) => OrderingTerm.desc(r.lastWatchedAt),
      (r) => OrderingTerm.desc(r.rowId),
    ])
    ..limit(limit);

  /// Recent channel keys, newest first (also a zapping list).
  Future<List<String>> recentChannelKeys(
    int sourceId, {
    int limit = maxEntries,
  }) async => [for (final r in await _ordered(sourceId, limit).get()) r.key];

  Stream<List<String>> watchRecentChannelKeys(
    int sourceId, {
    int limit = maxEntries,
  }) => _ordered(
    sourceId,
    limit,
  ).watch().map((rows) => [for (final r in rows) r.key]);

  /// Recent channels, newest first; channels gone from the catalog are
  /// skipped.
  Future<List<ChannelRow>> recentChannels(
    int sourceId, {
    int limit = maxEntries,
  }) async {
    final rows = await customSelect(
      'SELECT c.* FROM recent_channels r JOIN channels c '
      'ON c.source_id = r.source_id AND c."key" = r."key" '
      'WHERE r.source_id = ?1 '
      'ORDER BY r.last_watched_at DESC, r.rowid DESC LIMIT ?2',
      variables: [Variable.withInt(sourceId), Variable.withInt(limit)],
      readsFrom: {db.recentChannels, db.channels},
    ).get();
    return [for (final r in rows) db.channels.map(r.data).toRow()];
  }

  Future<void> clear(int sourceId) => (delete(
    db.recentChannels,
  )..where((r) => r.sourceId.equals(sourceId))).go();
}
