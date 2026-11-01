import 'dart:convert';

import 'package:crypto/crypto.dart';

typedef SyncData = Map<String, Map<String, Object?>>;

String syncId(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

/// Whether two JSON values hold the same data, whatever their key order.
/// Compared in place: encoding every playlist chunk on each sync is costly.
bool syncEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (!b.containsKey(e.key) || !syncEqual(e.value, b[e.key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!syncEqual(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

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
///
/// A source or list deleted on another device still comes back when this
/// device holds favourites, lists, list entries or viewing progress of its
/// own in it: dropping it would delete those here, and the account holds no
/// copy of them. Its children deleted elsewhere stay deleted.
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
  void revive(String key) {
    final row = local[key];
    if (row == null || !deleted.contains(key) || changes.containsKey(key)) {
      return;
    }
    changes[key] = row;
    if (row['type'] == 'list') revive('source:${row['source']}');
    // A playlist file comes back with its chunks.
    if (row['type'] == 'source') {
      for (final e in local.entries) {
        if (e.value['type'] == 'file' && e.value['source'] == row['source']) {
          changes[e.key] = e.value;
        }
      }
    }
  }

  for (final e in local.entries) {
    if (remote.containsKey(e.key) || deleted.contains(e.key)) continue;
    switch (e.value['type']) {
      case 'favorite' || 'progress' || 'list':
        revive('source:${e.value['source']}');
      case 'item':
        revive('list:${e.value['list']}');
    }
  }
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
