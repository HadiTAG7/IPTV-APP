import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../sources/models.dart';
import '../app_db.dart';

/// Cache for lazily fetched movie and series details (24 h TTL).
class DetailCacheDao extends DatabaseAccessor<AppDatabase> {
  DetailCacheDao(super.attachedDatabase);

  static const ttl = Duration(hours: 24);

  /// Cached JSON text, or null when missing or older than [maxAge].
  /// [allowStale] returns old entries too (offline fallback).
  Future<String?> getJson(
    int sourceId,
    ContentKind kind,
    String key, {
    Duration maxAge = ttl,
    bool allowStale = false,
  }) async {
    final r =
        await (select(db.detailCache)..where(
              (c) =>
                  c.sourceId.equals(sourceId) &
                  c.kind.equalsValue(kind) &
                  c.key.equals(key),
            ))
            .getSingleOrNull();
    if (r == null) return null;
    final age = db.clock.now().difference(fromEpochSec(r.fetchedAt));
    return allowStale || age <= maxAge ? r.json : null;
  }

  Future<void> putJson(
    int sourceId,
    ContentKind kind,
    String key,
    String json,
  ) => into(db.detailCache).insertOnConflictUpdate(
    DetailCacheCompanion.insert(
      sourceId: sourceId,
      kind: kind,
      key: key,
      json: json,
      fetchedAt: toEpochSec(db.clock.now()),
    ),
  );

  Future<MovieDetail?> movieDetail(
    int sourceId,
    String key, {
    Duration maxAge = ttl,
    bool allowStale = false,
  }) async => _decode(
    await getJson(
      sourceId,
      ContentKind.movie,
      key,
      maxAge: maxAge,
      allowStale: allowStale,
    ),
    movieDetailFromJson,
  );

  Future<void> putMovieDetail(int sourceId, MovieDetail detail) => putJson(
    sourceId,
    ContentKind.movie,
    detail.key,
    jsonEncode(movieDetailToJson(detail)),
  );

  Future<SeriesDetail?> seriesDetail(
    int sourceId,
    String key, {
    Duration maxAge = ttl,
    bool allowStale = false,
  }) async => _decode(
    await getJson(
      sourceId,
      ContentKind.series,
      key,
      maxAge: maxAge,
      allowStale: allowStale,
    ),
    seriesDetailFromJson,
  );

  Future<void> putSeriesDetail(int sourceId, SeriesDetail detail) => putJson(
    sourceId,
    ContentKind.series,
    detail.key,
    jsonEncode(seriesDetailToJson(detail)),
  );

  Future<void> invalidate(int sourceId, ContentKind kind, String key) =>
      (delete(db.detailCache)..where(
            (c) =>
                c.sourceId.equals(sourceId) &
                c.kind.equalsValue(kind) &
                c.key.equals(key),
          ))
          .go();

  /// Deletes entries older than [maxAge]; returns how many.
  Future<int> purgeExpired({Duration maxAge = ttl}) {
    final cutoff = toEpochSec(db.clock.now().subtract(maxAge));
    return (delete(
      db.detailCache,
    )..where((c) => c.fetchedAt.isSmallerThanValue(cutoff))).go();
  }
}

T? _decode<T>(String? json, T Function(Map<String, Object?>) fromJson) {
  if (json == null) return null;
  try {
    final decoded = jsonDecode(json);
    return decoded is Map<String, Object?> ? fromJson(decoded) : null;
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}
