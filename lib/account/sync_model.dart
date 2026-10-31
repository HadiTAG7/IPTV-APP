import 'dart:convert';

import 'package:crypto/crypto.dart';

typedef SyncData = Map<String, Map<String, Object?>>;

String syncId(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

bool syncEqual(Object? a, Object? b) =>
    jsonEncode(_canonical(a)) == jsonEncode(_canonical(b));

/// Missing keys are explicit deletions. Records, rather than whole device
/// snapshots, are merged, so an offline favourite never erases another list.
Map<String, Map<String, Object?>?> syncChanges(
  SyncData before,
  SyncData after,
) => {
  for (final key in {...before.keys, ...after.keys})
    if (!syncEqual(before[key], after[key])) key: after[key],
};

SyncData mergeSyncData(
  SyncData remote,
  Map<String, Map<String, Object?>?> changes,
) {
  final merged = SyncData.of(remote);
  for (final entry in changes.entries) {
    final next = entry.value;
    if (next == null) {
      merged.remove(entry.key);
    } else {
      // A stale offline playback checkpoint must not rewind newer viewing.
      final old = merged[entry.key];
      if (next['type'] == 'progress' &&
          old != null &&
          (old['updatedAt'] as int) > (next['updatedAt'] as int)) {
        continue;
      }
      merged[entry.key] = next;
    }
  }
  return merged;
}

SyncData decodeSyncData(Object? value) => value is Map
    ? {
        for (final e in value.entries)
          e.key as String: Map<String, Object?>.from(e.value as Map),
      }
    : {};

/// First-link reconciliation: the account owns existing choices. New local
/// entries append in their local order, rather than colliding with position 0
/// in a cloud list and unexpectedly rearranging that list.
Map<String, Map<String, Object?>?> initialSyncChanges(
  SyncData remote,
  Set<String> deleted,
  SyncData local,
) {
  final changes = syncChanges({}, local)
    ..removeWhere(
      (key, value) =>
          deleted.contains(key) ||
          (remote.containsKey(key) && value?['type'] != 'progress'),
    );
  String? group(Map<String, Object?> row) => switch (row['type']) {
    'source' => 'sources',
    'list' => jsonEncode(['lists', row['source']]),
    'item' => jsonEncode(['items', row['list']]),
    'favorite' => jsonEncode(['favorites', row['source'], row['kind']]),
    _ => null,
  };
  final maxima = <String, int>{};
  for (final row in remote.values) {
    final g = group(row);
    if (g == null) continue;
    final position = row['position'] as int;
    if (position > (maxima[g] ?? -1)) maxima[g] = position;
  }
  final additions =
      changes.entries
          .where((e) => e.value != null && group(e.value!) != null)
          .toList()
        ..sort((a, b) {
          final compared = (a.value!['position'] as int).compareTo(
            b.value!['position'] as int,
          );
          return compared == 0 ? a.key.compareTo(b.key) : compared;
        });
  for (final entry in additions) {
    final g = group(entry.value!)!;
    final position = (maxima[g] ?? -1) + 1;
    maxima[g] = position;
    changes[entry.key] = {...entry.value!, 'position': position};
  }
  return changes;
}
