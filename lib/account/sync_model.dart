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
