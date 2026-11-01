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

/// Records that stand for one moment, and the field that says when: of two
/// copies, the newer wins, whichever device uploads last.
const _moments = {'progress': 'updatedAt', 'recent': 'lastWatchedAt'};

/// Whether [next] is an older moment than [old] (see [_moments]).
bool _older(Map<String, Object?> next, Map<String, Object?>? old) {
  final field = _moments[next['type']];
  if (field == null || old == null) return false;
  return ((old[field] as int?) ?? 0) > ((next[field] as int?) ?? 0);
}

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
      // A stale offline playback checkpoint must not rewind newer viewing,
      // nor an older zap reorder the recent channels.
      if (_older(next, merged[entry.key])) continue;
      merged[entry.key] = next;
    }
  }
  return merged;
}

/// The record types this version holds, and their fields. Types and fields
/// a newer version adds are kept as received, never deleted or stripped
/// (see `LocalSyncStore.export`).
const syncFields = <String, Set<String>>{
  'source': {
    'type',
    'source',
    'name',
    'kind',
    'url',
    'username',
    'password',
    'userAgent',
    'referer',
    'liveFormat',
    'epgOffsetMin',
    'position',
    'fileParts',
    'fileHash',
  },
  'file': {'type', 'source', 'part', 'data'},
  'favorite': {'type', 'source', 'kind', 'key', 'position', 'addedAt'},
  'list': {'type', 'source', 'list', 'name', 'position', 'createdAt'},
  'item': {'type', 'list', 'key', 'position', 'addedAt'},
  'progress': {
    'type',
    'source',
    'kind',
    'key',
    'seriesKey',
    'positionMs',
    'durationMs',
    'updatedAt',
    'finished',
  },
  'recent': {'type', 'source', 'key', 'lastWatchedAt'},
  'preferences': {'type', 'locale', 'preferredAudioLang', 'preferredSubLang'},
};

/// Fields of a source record that name its playlist file and chunks.
const _playlistFields = {'kind', 'url', 'fileParts', 'fileHash'};

/// This device's changes since [baseline], the account as last synced, to
/// merge into the account as now read: [remote], with tombstones [deleted].
///
/// * Only a tombstone deletes: a record the account lost without one (its
///   documents deleted in the console, an older backup restored) is
///   uploaded again instead of being deleted here.
/// * A record deleted elsewhere wins over an edit made here before this
///   device heard of it: reviving a source or list alone would drop its
///   contents, and a list entry or favourite that only moved (a removal
///   here renumbers the rest) is no re-add.
/// * Positions follow the account's order as now read, changed only as
///   this device changed its own (see [_place]): a removal here renumbers
///   the entries after it, which is no move, and the order the account
///   has, maybe made on another device meanwhile, stays.
/// * A record changed both here and elsewhere keeps the fields each side
///   changed, this device's where both did. A playlist file's fields name
///   its chunks, so they come from one side together, and a playlist
///   replaced here goes with all of its chunks.
Map<String, Map<String, Object?>?> pendingSyncChanges(
  SyncData baseline,
  SyncData remote,
  Set<String> deleted,
  SyncData local,
) {
  final changes = syncChanges(baseline, local);
  for (final e in local.entries) {
    if (baseline.containsKey(e.key) &&
        !remote.containsKey(e.key) &&
        !deleted.contains(e.key)) {
      changes[e.key] = e.value;
    }
  }
  changes.removeWhere((key, r) {
    final base = baseline[key];
    if (r == null || base == null || !deleted.contains(key)) return false;
    return switch (r['type']) {
      'source' || 'list' => true,
      'item' ||
      'favorite' => syncEqual({...r, 'position': 0}, {...base, 'position': 0}),
      _ => false,
    };
  });
  for (final e in changes.entries.toList()) {
    final mine = e.value;
    final base = baseline[e.key];
    final theirs = remote[e.key];
    if (mine == null ||
        base == null ||
        theirs == null ||
        syncEqual(base, theirs)) {
      continue;
    }
    final merged = changes[e.key] = _mergeRecord(base, mine, theirs);
    if (merged['type'] != 'source' ||
        merged['fileHash'] == null ||
        syncEqual(merged['fileHash'], theirs['fileHash'])) {
      continue;
    }
    // Chunks equal to the last synced ones are no change here, yet the
    // account now holds the other playlist's.
    for (final c in local.entries) {
      if (c.value['type'] == 'file' && c.value['source'] == merged['source']) {
        changes[c.key] = c.value;
      }
    }
  }
  _place(baseline, remote, local, changes);
  return changes;
}

/// Gives the entries of each ordered group with an entry in [changes] the
/// positions of the account's order as now read ([remote]), changed as
/// this device changed its own since [baseline]:
///
/// * The entries placed here (added, sent again, or the fewest that moved
///   to make the order here, see [_moved]) go, in their order here, where
///   the most of the others keep their order here to them: after the
///   entry before them here, unless the account moved that one away, and
///   last when appended or moved to the end.
/// * The other entries keep the account's order and positions, so the
///   positions a removal here closed are no move and an order made on
///   another device meanwhile stays. Only the entries after a placed one
///   are renumbered, as far as it needs room.
///
/// Positions never tie anew: devices break ties in different ways.
void _place(
  SyncData baseline,
  SyncData remote,
  SyncData local,
  Map<String, Map<String, Object?>?> changes,
) {
  final groups = {
    for (final r in changes.values)
      if (r != null) ?_positionGroup(r),
  };
  if (groups.isEmpty) return;
  Map<String, List<String>> ordered(SyncData data) {
    final result = <String, List<String>>{};
    for (final e in data.entries) {
      final group = _positionGroup(e.value);
      if (groups.contains(group)) (result[group!] ??= []).add(e.key);
    }
    return {for (final e in result.entries) e.key: _inOrder(data, e.value)};
  }

  final bases = ordered(baseline);
  final mines = ordered(local);
  final theirs = ordered(remote);
  final removed = {
    for (final e in changes.entries)
      if (e.value == null) e.key,
  };
  for (final group in groups) {
    final mine = mines[group] ?? const [];
    // Of the entries the account still has: one deleted elsewhere neither
    // moved here nor keeps the others in their order.
    final moved = _moved([...?bases[group]?.where(remote.containsKey)], mine);
    final placed = {
      for (final key in mine)
        if (moved.contains(key) ||
            changes[key] != null &&
                (!baseline.containsKey(key) || !remote.containsKey(key)))
          key,
    };
    final order = [
      for (final key in theirs[group] ?? const <String>[])
        if (!placed.contains(key) && !removed.contains(key)) key,
    ];
    final here = {for (final (i, key) in mine.indexed) key: i};
    final last = mine.lastIndexWhere(
      (key) => !placed.contains(key) && remote.containsKey(key),
    );
    // The entry here before the next placed one, in [order] already.
    String? previous;
    for (final (i, key) in mine.indexed) {
      if (!placed.contains(key)) {
        if (remote.containsKey(key)) previous = key;
        continue;
      }
      // Nothing the account has follows it here: appended, or moved to the
      // end, it goes after what other devices appended meanwhile.
      if (i > last) {
        order.add(key);
        previous = key;
        continue;
      }
      // Where the most of the entries here before it come before it, and
      // of those after it after it: right after [previous] if that is such
      // a place (first if none), else the first one.
      var score = order.where((k) => (here[k] ?? -1) > i).length;
      var best = score;
      var at = 0;
      var after = previous == null ? (0, score) : null;
      for (final (s, k) in order.indexed) {
        final j = here[k];
        if (j != null) score += j < i ? 1 : -1;
        if (score > best) {
          best = score;
          at = s + 1;
        }
        if (k == previous) after = (s + 1, score);
      }
      if (after != null && after.$2 == best) at = after.$1;
      order.insert(at, key);
      previous = key;
    }
    // An entry keeps the account's position while that still comes after
    // the one before it (or ties as the account has them already).
    int? at;
    var held = false;
    for (final key in order) {
      final account = remote[key];
      final position = account?['position'] as int?;
      if (position != null &&
          !placed.contains(key) &&
          (at == null || position > at || position == at && held)) {
        at = position;
        held = true;
      } else {
        at = (at ?? -1) + 1;
        held = false;
      }
      final row = {...(changes[key] ?? account)!, 'position': at};
      if (syncEqual(row, account)) {
        changes.remove(key);
      } else {
        changes[key] = row;
      }
    }
  }
}

/// [keys] of [data] in their order: by position, then by key.
List<String> _inOrder(SyncData data, Iterable<String> keys) =>
    [...keys]..sort((a, b) {
      final compared = (data[a]!['position'] as int).compareTo(
        data[b]!['position'] as int,
      );
      return compared == 0 ? a.compareTo(b) : compared;
    });

/// The fewest entries of [mine] that moved to turn [base], the order last
/// synced, into it: all of both but a longest run in their order there.
Set<String> _moved(List<String> base, List<String> mine) {
  final rank = {for (final (i, key) in base.indexed) key: i};
  final ranks = [for (final key in mine) ?rank[key]];
  // Patience sorting: ends[n] ends the run of n + 1 found that ends at the
  // lowest rank, and before[i] precedes ranks[i] in its run.
  final ends = <int>[];
  final before = List.filled(ranks.length, -1);
  for (final (i, r) in ranks.indexed) {
    var low = 0;
    var high = ends.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (ranks[ends[mid]] < r) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low > 0) before[i] = ends[low - 1];
    if (low == ends.length) {
      ends.add(i);
    } else {
      ends[low] = i;
    }
  }
  final stay = <int>{};
  for (var i = ends.isEmpty ? -1 : ends.last; i >= 0; i = before[i]) {
    stay.add(ranks[i]);
  }
  return {
    for (final r in ranks)
      if (!stay.contains(r)) base[r],
  };
}

/// The ordered group of [row]: its position counts among the group's.
/// None without a position.
String? _positionGroup(Map<String, Object?> row) => switch (row['type']) {
  _ when row['position'] is! int => null,
  'source' => 'sources',
  'list' => jsonEncode(['lists', row['source']]),
  'item' => jsonEncode(['items', row['list']]),
  'favorite' => jsonEncode(['favorites', row['source'], row['kind']]),
  _ => null,
};

/// [mine] and [theirs], both changed since [base], field by field.
Map<String, Object?> _mergeRecord(
  Map<String, Object?> base,
  Map<String, Object?> mine,
  Map<String, Object?> theirs,
) {
  // A moment goes whole (the newer wins in mergeSyncData), and a playlist
  // chunk goes with its source record.
  if (_moments.containsKey(mine['type']) || mine['type'] == 'file') {
    return mine;
  }
  bool changed(String field) => !syncEqual(base[field], mine[field]);
  final playlist = mine['type'] == 'source' && _playlistFields.any(changed);
  final merged = Map.of(theirs);
  for (final field in {...base.keys, ...mine.keys}) {
    final ours = mine['type'] == 'source' && _playlistFields.contains(field)
        ? playlist
        : changed(field);
    if (!ours) continue;
    if (mine.containsKey(field)) {
      merged[field] = mine[field];
    } else {
      merged.remove(field);
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
///
/// A device moved to the account on purpose ([keepLocal]) keeps all it
/// holds instead: see [_keepLocal].
Map<String, Map<String, Object?>?> initialSyncChanges(
  SyncData remote,
  Set<String> deleted,
  SyncData local, {
  bool keepLocal = false,
}) {
  if (keepLocal) return _keepLocal(remote, local);
  final changes = syncChanges({}, local)
    ..removeWhere(
      (key, value) =>
          deleted.contains(key) ||
          (remote.containsKey(key) && !_moments.containsKey(value?['type'])),
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
  _append(changes, remote.values, {
    for (final e in changes.entries)
      if (e.value != null) e.key: e.value!,
  });
  return changes;
}

/// The first link of a device moved to the account on purpose: what it
/// holds stays as it is and goes to the account, as the confirmation says.
/// Its copies win over the account's (but for an older moment, see
/// [mergeSyncData]) and over the account's tombstones, which then delete
/// only what this device does not hold; the account's other entries follow
/// this device's own in each ordered group. The account's language
/// settings stay, as at any first sign-in, so its other devices keep their
/// language: the confirmation names only the data that replaces the
/// account's. So do the fields of a record a newer version added, of which
/// this device has no copy.
Map<String, Map<String, Object?>?> _keepLocal(SyncData remote, SyncData local) {
  final copies = {
    for (final MapEntry(:key, :value) in local.entries)
      key: {
        if (remote[key] case final theirs?)
          for (final f in theirs.entries)
            if (syncFields[value['type']]?.contains(f.key) == false)
              f.key: f.value,
        ...value,
      },
  };
  final changes = syncChanges(remote, copies)
    ..removeWhere(
      (key, value) =>
          value == null ||
          value['type'] == 'preferences' && remote.containsKey(key),
    );
  final groups = {for (final row in local.values) ?_positionGroup(row)};
  final moved = <String, Map<String, Object?>?>{};
  _append(moved, local.values, {
    for (final e in remote.entries)
      if (!local.containsKey(e.key) && groups.contains(_positionGroup(e.value)))
        e.key: e.value,
  });
  moved.removeWhere((key, value) => syncEqual(value, remote[key]));
  return changes..addAll(moved);
}

/// Puts [rows] into [changes] after the entries of [after] in each ordered
/// group, in their order.
void _append(
  Map<String, Map<String, Object?>?> changes,
  Iterable<Map<String, Object?>> after,
  SyncData rows,
) {
  final maxima = <String, int>{};
  for (final row in after) {
    final g = _positionGroup(row);
    if (g == null) continue;
    final position = row['position'] as int;
    if (position > (maxima[g] ?? -1)) maxima[g] = position;
  }
  final additions =
      rows.entries.where((e) => _positionGroup(e.value) != null).toList()
        ..sort((a, b) {
          final compared = (a.value['position'] as int).compareTo(
            b.value['position'] as int,
          );
          return compared == 0 ? a.key.compareTo(b.key) : compared;
        });
  for (final entry in additions) {
    final g = _positionGroup(entry.value)!;
    final position = (maxima[g] ?? -1) + 1;
    maxima[g] = position;
    changes[entry.key] = {...entry.value, 'position': position};
  }
}
