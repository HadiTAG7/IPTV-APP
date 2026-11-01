import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../app/settings.dart';
import '../core/db/app_db.dart';
import '../core/secure/secret_store.dart';
import '../sources/models.dart';
import '../sources/source_repository.dart';
import 'firebase_api.dart';
import 'sync_model.dart';

/// A playlist file as the account holds it, for a file of [size] bytes
/// last modified at [modified].
typedef _Playlist = ({
  DateTime modified,
  int size,
  String encoded,
  String hash,
});

/// Account records this version cannot hold, and the fields it does not
/// know of the records it holds.
typedef _Foreign = ({SyncData records, SyncData fields});

/// Maps device-local integer IDs to stable cloud IDs without migrating the
/// catalogue database. Only account data is exported, never the catalogue.
class LocalSyncStore {
  LocalSyncStore(this.db, {Future<Directory> Function()? directory})
    : directory = directory ?? getApplicationSupportDirectory;
  final AppDatabase db;
  final Future<Directory> Function() directory;
  static const _idsKey = 'account_sync_ids_v1';
  Map<String, String> _ids = {};
  bool _loaded = false;
  final _files = <String, _Playlist>{};

  /// Playlist copies replaced or deleted by [apply], removed by [export] once
  /// no source uses them (a rolled-back apply still does).
  final _replaced = <String>{};
  final _random = Random();

  /// What the account last synced holds that this version cannot hold here
  /// (see [_foreignOf]). [export] returns it as received, so it never looks
  /// deleted or changed on this device.
  _Foreign _foreign = (records: {}, fields: {});

  Future<void> _load() async {
    if (_loaded) return;
    final json = await db.settingsDao.getJson(_idsKey);
    _ids = json is Map ? Map<String, String>.from(json) : {};
    _loaded = true;
  }

  /// Cloud IDs that rows of [kind] hold, each once: two rows that an older
  /// version gave one ID (the same subscription added twice) keep it on the
  /// older row, and the other row gets an ID of its own.
  Set<String> _held(String kind, Iterable<int> ids) {
    final held = <String>{};
    for (final id in ids.toList()..sort()) {
      final cloudId = _ids['$kind:$id'];
      if (cloudId != null && !held.add(cloudId)) _ids.remove('$kind:$id');
    }
    return held;
  }

  /// A new row's ID derives from its content, so the same subscription or
  /// list on two devices merges at first link, but it never takes an ID
  /// another row here holds: a list renamed and its old name reused, or a
  /// source whose URL changed and the old URL added again.
  String _id(String key, Object identity, Set<String> held) {
    final cached = _ids[key];
    if (cached != null) return cached;
    var id = syncId(identity);
    while (held.contains(id)) {
      id = syncId([identity, _random.nextInt(1 << 32)]);
    }
    held.add(id);
    return _ids[key] = id;
  }

  Future<SyncData> export() => db.transaction(() async {
    await _load();
    final result = <String, Map<String, Object?>>{};
    final sources = <int, String>{};
    final rows = await db.sourcesDao.all();
    final heldSources = _held('source', [for (final row in rows) row.id]);
    final paths = <String>{};
    for (final row in rows) {
      final config = (await db.sourcesDao.configFor(row.id))!;
      paths.add(config.url);
      _Playlist? file;
      if (config.kind == SourceKind.m3uFile) {
        final stat = await File(config.url).stat();
        if (stat.type != FileSystemEntityType.file) {
          throw const AccountException('PLAYLIST_FILE_MISSING');
        }
        if (stat.size > 32 * 1024 * 1024) {
          throw const AccountException('PLAYLIST_FILE_TOO_LARGE');
        }
        file = _files[config.url];
        if (file == null ||
            file.modified != stat.modified ||
            file.size != stat.size) {
          final encoded = await _encodeFile(config.url);
          file = _files[config.url] = (
            modified: stat.modified,
            size: stat.size,
            encoded: encoded.encoded,
            hash: encoded.hash,
          );
        }
      }
      final sid = _id('source:${row.id}', [
        config.kind.name,
        file?.encoded ?? config.url,
        config.username,
      ], heldSources);
      sources[row.id] = sid;
      final encoded = file?.encoded;
      final parts = encoded == null ? 0 : (encoded.length / 350000).ceil();
      result['source:$sid'] = {
        'type': 'source',
        'source': sid,
        'name': config.name,
        'kind': config.kind.name,
        'url': file == null ? config.url : '',
        'username': config.username,
        'password': config.password,
        'userAgent': config.userAgent,
        'referer': config.referer,
        'liveFormat': config.liveFormat.name,
        'epgOffsetMin': config.epgOffsetMin,
        'position': row.sortIndex,
        'fileParts': parts,
        'fileHash': ?file?.hash,
      };
      for (var i = 0; i < parts; i++) {
        result['file:$sid:$i'] = {
          'type': 'file',
          'source': sid,
          'part': i,
          'data': encoded!.substring(
            i * 350000,
            ((i + 1) * 350000).clamp(0, encoded.length),
          ),
        };
      }
    }
    for (final row in await db.select(db.favorites).get()) {
      final sid = sources[row.sourceId];
      if (sid == null) continue;
      result['favorite:$sid:${row.kind.name}:${row.key}'] = {
        'type': 'favorite',
        'source': sid,
        'kind': row.kind.name,
        'key': row.key,
        'position': row.position,
        'addedAt': row.addedAt,
      };
    }
    final lists = <int, String>{};
    final listRows = await db.select(db.channelLists).get();
    final heldLists = _held('list', [for (final row in listRows) row.id]);
    for (final row in listRows) {
      final sid = sources[row.sourceId];
      if (sid == null) continue;
      final lid = _id('list:${row.id}', [
        sid,
        row.name.toLowerCase(),
      ], heldLists);
      lists[row.id] = lid;
      result['list:$lid'] = {
        'type': 'list',
        'source': sid,
        'list': lid,
        'name': row.name,
        'position': row.position,
        'createdAt': row.createdAt,
      };
    }
    for (final row in await db.select(db.channelListItems).get()) {
      final lid = lists[row.listId];
      if (lid == null) continue;
      result['item:$lid:${row.key}'] = {
        'type': 'item',
        'list': lid,
        'key': row.key,
        'position': row.position,
        'addedAt': row.addedAt,
      };
    }
    for (final row in await db.select(db.watchProgress).get()) {
      final sid = sources[row.sourceId];
      if (sid == null) continue;
      result['progress:$sid:${row.kind.name}:${row.key}'] = {
        'type': 'progress',
        'source': sid,
        'kind': row.kind.name,
        'key': row.key,
        'seriesKey': row.seriesKey,
        'positionMs': row.positionMs,
        'durationMs': row.durationMs,
        'updatedAt': row.updatedAt,
        'finished': row.finished,
      };
    }
    for (final row in await db.select(db.recentChannels).get()) {
      final sid = sources[row.sourceId];
      if (sid == null) continue;
      result['recent:$sid:${row.key}'] = {
        'type': 'recent',
        'source': sid,
        'key': row.key,
        'lastWatchedAt': row.lastWatchedAt,
      };
    }
    final settings = await loadAppSettings(db.settingsDao);
    result['preferences'] = {
      'type': 'preferences',
      'locale': settings.locale.name,
      'preferredAudioLang': settings.preferredAudioLang,
      'preferredSubLang': settings.preferredSubLang,
    };
    for (final e in _foreign.records.entries) {
      result[e.key] = e.value;
    }
    for (final e in _foreign.fields.entries) {
      final held = result[e.key];
      if (held != null) result[e.key] = {...e.value, ...held};
    }
    if (!syncEqual(await db.settingsDao.getJson(_idsKey), _ids)) {
      await db.settingsDao.setJson(_idsKey, _ids);
    }
    await _removeReplaced(paths);
    return result;
  });

  Future<void> _removeReplaced(Set<String> inUse) async {
    if (_replaced.isEmpty) return;
    final root = (await directory()).path;
    final support = Directory(root).absolute.path;
    final imports = Directory(_importDir(root)).absolute.path;
    for (final path in _replaced.toList()) {
      _replaced.remove(path);
      final file = File(path);
      final folder = file.parent.absolute.path;
      // Only copies this app made: imports, and older received playlists.
      final ours =
          folder == imports ||
          (folder == support &&
              file.uri.pathSegments.last.startsWith('cloud-'));
      if (!ours || inUse.contains(path)) continue;
      try {
        await file.delete();
      } on FileSystemException {
        // Already gone.
      }
    }
  }

  /// Keeps the account's encoding of playlist files unchanged since [data]
  /// was synced, so a restart does not re-encode and re-upload them, and
  /// what of [data] this version cannot hold.
  Future<void> remember(SyncData data) async {
    await _load();
    _foreign = _foreignOf(data);
    final local = {
      for (final e in _ids.entries)
        if (e.key.startsWith('source:'))
          e.value: int.parse(e.key.substring('source:'.length)),
    };
    for (final r in data.values) {
      if (r['type'] != 'source' || r['fileHash'] == null) continue;
      final id = local[r['source']];
      final config = id == null ? null : await db.sourcesDao.configFor(id);
      if (config == null ||
          config.kind != SourceKind.m3uFile ||
          _files.containsKey(config.url)) {
        continue;
      }
      final parts = _parts(data, r);
      if (parts == null) continue;
      try {
        final stat = await File(config.url).stat();
        final hash = r['fileHash']! as String;
        final encoded = await _matching(parts, hash, config.url);
        if (encoded != null) {
          _files[config.url] = (
            modified: stat.modified,
            size: stat.size,
            encoded: encoded,
            hash: hash,
          );
        }
      } on Object {
        // A changed, missing or damaged copy is encoded afresh by export.
      }
    }
  }

  /// First link: a source or list here that matches an account record by
  /// what it is now takes that record's ID, so the account copy applies
  /// instead of a second copy being uploaded. Its own ID comes from what it
  /// was at its first export, which matches nothing once a subscription
  /// moved to a new address or a list was renamed since, or when another
  /// platform's gzip encoded the same playlist file differently.
  Future<void> link(SyncData remote) => db.transaction(() async {
    await _load();
    final before = Map.of(_ids);
    final rows = await db.sourcesDao.all();
    final open = _unheld(
      remote,
      'source',
      _held('source', [for (final row in rows) row.id]),
    );
    final sources = <int, String?>{};
    for (final row in rows) {
      var sid = _ids['source:${row.id}'];
      if (sid == null || !remote.containsKey('source:$sid')) {
        final config = (await db.sourcesDao.configFor(row.id))!;
        for (final r in open) {
          if (r['kind'] == config.kind.name &&
              r['username'] == config.username &&
              await _sameSource(remote, r, config)) {
            open.remove(r);
            sid = _ids['source:${row.id}'] = r['source']! as String;
            break;
          }
        }
      }
      sources[row.id] = sid;
    }
    final listRows = await db.select(db.channelLists).get();
    final openLists = _unheld(
      remote,
      'list',
      _held('list', [for (final row in listRows) row.id]),
    );
    for (final row in listRows) {
      final lid = _ids['list:${row.id}'];
      if (lid != null && remote.containsKey('list:$lid')) continue;
      final name = row.name.toLowerCase();
      final match = openLists
          .where(
            (r) =>
                r['source'] == sources[row.sourceId] &&
                (r['name']! as String).toLowerCase() == name,
          )
          .firstOrNull;
      if (match == null) continue;
      openLists.remove(match);
      _ids['list:${row.id}'] = match['list']! as String;
    }
    if (!syncEqual(before, _ids)) await db.settingsDao.setJson(_idsKey, _ids);
  });

  /// What of [data] this version cannot hold here: records of types a newer
  /// version added, or with a kind or format it added, with everything in
  /// their sources and lists; and of the other records, the fields a newer
  /// version added. Kept as received, a newer device's data survives the
  /// syncs of an older one.
  static _Foreign _foreignOf(SyncData data) {
    bool known(Object? name, List<Enum> values) =>
        values.any((v) => v.name == name);
    final records = <String, Map<String, Object?>>{};
    final sources = <Object?>{};
    final lists = <Object?>{};
    for (final e in data.entries) {
      final r = e.value;
      final held = switch (r['type']) {
        'source' =>
          known(r['kind'], SourceKind.values) &&
              known(r['liveFormat'], LiveFormat.values),
        'favorite' => known(r['kind'], ContentKind.values),
        'progress' => known(r['kind'], PlayableKind.values),
        final type => syncFields.containsKey(type),
      };
      if (held) continue;
      records[e.key] = r;
      if (r['type'] == 'source') sources.add(r['source'] ?? e.key);
    }
    if (sources.isNotEmpty) {
      for (final e in data.entries) {
        if (e.value['type'] == 'list' && sources.contains(e.value['source'])) {
          lists.add(e.value['list'] ?? e.key);
        }
      }
      for (final e in data.entries) {
        final r = e.value;
        if (r['type'] == 'item'
            ? lists.contains(r['list'])
            : sources.contains(r['source'])) {
          records[e.key] = r;
        }
      }
    }
    final fields = <String, Map<String, Object?>>{};
    for (final e in data.entries) {
      if (records.containsKey(e.key)) continue;
      final names = syncFields[e.value['type']]!;
      final added = {
        for (final f in e.value.entries)
          if (!names.contains(f.key)) f.key: f.value,
      };
      if (added.isNotEmpty) fields[e.key] = added;
    }
    return (records: records, fields: fields);
  }

  /// [data] without what [foreign] names.
  static SyncData _holdable(SyncData data, _Foreign foreign) => {
    for (final e in data.entries)
      if (!foreign.records.containsKey(e.key))
        e.key: foreign.fields.containsKey(e.key)
            ? {
                for (final f in e.value.entries)
                  if (!foreign.fields[e.key]!.containsKey(f.key))
                    f.key: f.value,
              }
            : e.value,
  };

  /// Account records of [type] whose ID no row here holds, in their order.
  static List<Map<String, Object?>> _unheld(
    SyncData remote,
    String type,
    Set<String> held,
  ) => [
    for (final r in remote.values)
      if (r['type'] == type && !held.contains(r[type])) r,
  ]..sort((a, b) => (a['position']! as int).compareTo(b['position']! as int));

  /// Whether account source [r] is the subscription or playlist [config].
  Future<bool> _sameSource(
    SyncData remote,
    Map<String, Object?> r,
    SourceConfig config,
  ) async {
    if (config.kind != SourceKind.m3uFile) return r['url'] == config.url;
    if (_files[config.url]?.hash == r['fileHash']) return true;
    final parts = _parts(remote, r);
    if (parts == null) return false;
    try {
      final hash = r['fileHash']! as String;
      return await _matching(parts, hash, config.url) != null;
    } on Object {
      return false;
    }
  }

  /// The encoded chunks of file source [r], or null.
  static List<String>? _parts(SyncData data, Map<String, Object?> r) {
    final count = r['fileParts'] as int;
    if (count < 1 || count > 200) return null;
    return List.generate(
      count,
      (i) => data['file:${r['source']}:$i']?['data'] as String? ?? '',
    );
  }

  /// The verified encoded playlist of file source [r], or null.
  static String? _encoded(SyncData data, Map<String, Object?> r) {
    final encoded = _parts(data, r)?.join();
    return encoded != null && syncId(encoded) == r['fileHash'] ? encoded : null;
  }

  /// The playlist file at [path] as the account holds it, and its hash.
  /// Off the UI isolate: a playlist may be 32 MB.
  static Future<({String encoded, String hash})> _encodeFile(String path) =>
      Isolate.run(() {
        final encoded = base64Encode(gzip.encode(File(path).readAsBytesSync()));
        return (encoded: encoded, hash: syncId(encoded));
      });

  /// The playlist [parts] joined, when they hash to [hash] and hold the
  /// file at [path], or null. Off the UI isolate, like [_encodeFile].
  static Future<String?> _matching(
    List<String> parts,
    String hash,
    String path,
  ) => Isolate.run(() {
    final encoded = parts.join();
    if (syncId(encoded) != hash) return null;
    return _same(File(path).readAsBytesSync(), _decode(encoded))
        ? encoded
        : null;
  });

  /// The folder [SourceRepository] imports playlists into and cleans up.
  static String _importDir(String root) =>
      '$root${Platform.pathSeparator}${SourceRepository.importDirName}';

  static List<int> _decode(String encoded) =>
      gzip.decode(base64Decode(encoded));

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Stores received playlist [encoded] for source [cloudId] unless
  /// [current] already holds the same playlist, and returns its path. gzip
  /// output differs between platforms (Windows and Android write other
  /// bytes), so the received encoding is what export sends back: one
  /// re-encoded locally would make the devices re-upload and re-import it
  /// in turn. New copies go to the import folder, so deleting or replacing
  /// the source removes them.
  Future<String> _receive(
    String encoded,
    String hash,
    String? current,
    String cloudId,
  ) async {
    final bytes = _decode(encoded);
    var path = current;
    var same = false;
    if (path != null) {
      try {
        same = _same(await File(path).readAsBytes(), bytes);
      } on FileSystemException {
        same = false;
      }
    }
    if (!same) {
      final folder = Directory(_importDir((await directory()).path));
      await folder.create(recursive: true);
      path =
          '${folder.path}${Platform.pathSeparator}'
          'cloud-${syncId([cloudId, hash])}.m3u';
      await File(path).writeAsBytes(bytes, flush: true);
    }
    final stat = await File(path!).stat();
    _files[path] = (
      modified: stat.modified,
      size: stat.size,
      encoded: encoded,
      hash: hash,
    );
    return path;
  }

  /// Applies only changed rows in one local transaction. Remote IDs never
  /// become database IDs. File sources are reconstructed in app-private storage.
  /// Returns the sources whose catalogue needs an import, and those whose
  /// guide offset changed: their guides need a forced refresh.
  Future<({Set<int> imports, Set<int> guides})> apply(SyncData target) async {
    final foreign = _foreignOf(target);
    final exported = await export();
    final current = _holdable(exported, _foreignOf(exported));
    final held = _holdable(target, foreign);
    // What this version cannot hold is neither applied nor deleted here.
    final changed = syncChanges(current, held)
      ..removeWhere((key, _) => foreign.records.containsKey(key));
    final needImport = <int>{};
    final guides = <int>{};
    try {
      await _apply(held, current, changed, needImport, guides);
    } on Object {
      // The rollback also removed rows created here: forget the cloud IDs
      // given to them, or a later local row would inherit one.
      _loaded = false;
      rethrow;
    }
    _foreign = foreign;
    return (imports: needImport, guides: guides);
  }

  Future<void> _apply(
    SyncData target,
    SyncData current,
    Map<String, Map<String, Object?>?> changed,
    Set<int> needImport,
    Set<int> guides,
  ) async {
    await db.transaction(() async {
      final sources = <String, int>{};
      final lists = <String, int>{};
      for (final row in await db.sourcesDao.all()) {
        sources[_ids['source:${row.id}']!] = row.id;
      }
      for (final row in await db.select(db.channelLists).get()) {
        lists[_ids['list:${row.id}']!] = row.id;
      }
      // Delete children first, preserving unrelated local catalogue/cache data.
      for (final entry in changed.entries.where((e) => e.value == null)) {
        final old = current[entry.key]!;
        final sid = sources[old['source']];
        final lid = lists[old['list']];
        switch (old['type']) {
          case 'favorite':
            if (sid != null) {
              await db.favoritesDao.setFavorite(
                sid,
                ContentKind.values.byName(old['kind'] as String),
                old['key'] as String,
                false,
              );
            }
          case 'item':
            // Without closing the gap as a removal here does: the other
            // entries keep the positions the account gives them.
            if (lid != null) {
              await (db.delete(db.channelListItems)..where(
                    (i) =>
                        i.listId.equals(lid) &
                        i.key.equals(old['key'] as String),
                  ))
                  .go();
            }
          case 'progress':
            if (sid != null) {
              await db.progressDao.clearProgress(
                sid,
                PlayableKind.values.byName(old['kind'] as String),
                old['key'] as String,
              );
            }
          case 'recent':
            if (sid != null) {
              await (db.delete(db.recentChannels)..where(
                    (r) =>
                        r.sourceId.equals(sid) &
                        r.key.equals(old['key'] as String),
                  ))
                  .go();
            }
          case 'list':
            if (lid != null) await db.channelListsDao.deleteList(lid);
          case 'source':
            if (sid != null) {
              final config = await db.sourcesDao.configFor(sid);
              await db.sourcesDao.deleteSource(sid);
              if (config?.kind == SourceKind.m3uFile) {
                _replaced.add(config!.url);
              }
            }
        }
      }
      for (final e in target.entries.where(
        (e) => e.value['type'] == 'source',
      )) {
        final r = e.value;
        final cloudId = r['source'] as String;
        var id = sources[cloudId];
        if (id != null && !changed.containsKey(e.key)) continue;
        final kind = SourceKind.values.byName(r['kind'] as String);
        final old = id == null ? null : await db.sourcesDao.configFor(id);
        final oldFile = old?.kind == SourceKind.m3uFile ? old!.url : null;
        var url = r['url'] as String;
        if (kind == SourceKind.m3uFile) {
          if (oldFile != null && current[e.key]?['fileHash'] == r['fileHash']) {
            // The same playlist: keep the local copy and its catalogue.
            url = oldFile;
          } else if (_encoded(target, r) case final encoded?) {
            url = await _receive(
              encoded,
              r['fileHash']! as String,
              oldFile,
              cloudId,
            );
          } else if (oldFile != null) {
            // Chunks that do not match their record (merged so by an older
            // version): the local copy stays, and the next upload sends it
            // with its own chunks, which repairs the account.
            url = oldFile;
          } else {
            throw const AccountException('INVALID_PLAYLIST');
          }
        }
        if (oldFile != null && oldFile != url) _replaced.add(oldFile);
        final config = SourceConfig(
          kind: kind,
          url: url,
          name: r['name'] as String,
          username: r['username'] as String?,
          password: r['password'] as String?,
          userAgent: r['userAgent'] as String?,
          referer: r['referer'] as String?,
          liveFormat: LiveFormat.values.byName(r['liveFormat'] as String),
          epgOffsetMin: r['epgOffsetMin'] as int,
        );
        if (id == null) {
          id = await db.sourcesDao.create(config);
          sources[cloudId] = id;
          _ids['source:$id'] = cloudId;
          needImport.add(id);
        } else {
          await db.sourcesDao.updateConfig(id, config);
          // A cloud replacement carries an explicit null, whereas the
          // editor's null means "keep the existing password".
          if (config.password == null) {
            await DbSecretStore(db).delete(id, SecretNames.password);
          }
          // A changed playlist file always arrives under a new path.
          if (old?.url != config.url ||
              old?.username != config.username ||
              old?.password != config.password) {
            needImport.add(id);
          }
          // Offsets apply at import (see `setSourceEpgOffset`): the guides
          // download again in full instead of keeping the old shift.
          if (old?.epgOffsetMin != config.epgOffsetMin) {
            await db.epgDao.forgetGuideVersions(id);
            guides.add(id);
          }
        }
        await (db.update(db.sources)..where((s) => s.id.equals(id!))).write(
          SourcesCompanion(sortIndex: Value(r['position'] as int)),
        );
      }
      for (final e in target.entries.where((e) => e.value['type'] == 'list')) {
        final r = e.value;
        final sid = sources[r['source']];
        if (sid == null) continue;
        final cloudId = r['list'] as String;
        var id = lists[cloudId];
        if (id == null) {
          id = await db
              .into(db.channelLists)
              .insert(
                ChannelListsCompanion.insert(
                  sourceId: sid,
                  name: r['name'] as String,
                  position: r['position'] as int,
                  createdAt: r['createdAt'] as int,
                ),
              );
          lists[cloudId] = id;
          _ids['list:$id'] = cloudId;
        } else if (changed.containsKey(e.key)) {
          await (db.update(
            db.channelLists,
          )..where((l) => l.id.equals(id!))).write(
            ChannelListsCompanion(
              name: Value(r['name'] as String),
              position: Value(r['position'] as int),
              createdAt: Value(r['createdAt'] as int),
            ),
          );
        }
      }
      for (final r in changed.values.whereType<Map<String, Object?>>()) {
        final sid = sources[r['source']];
        final lid = lists[r['list']];
        switch (r['type']) {
          case 'favorite':
            if (sid != null) {
              await db
                  .into(db.favorites)
                  .insertOnConflictUpdate(
                    FavoritesCompanion.insert(
                      sourceId: sid,
                      kind: ContentKind.values.byName(r['kind'] as String),
                      key: r['key'] as String,
                      addedAt: r['addedAt'] as int,
                      position: r['position'] as int,
                    ),
                  );
            }
          case 'item':
            if (lid != null) {
              await db
                  .into(db.channelListItems)
                  .insertOnConflictUpdate(
                    ChannelListItemsCompanion.insert(
                      listId: lid,
                      key: r['key'] as String,
                      position: r['position'] as int,
                      addedAt: r['addedAt'] as int,
                    ),
                  );
            }
          case 'progress':
            if (sid != null) {
              await db
                  .into(db.watchProgress)
                  .insertOnConflictUpdate(
                    WatchProgressCompanion.insert(
                      sourceId: sid,
                      kind: PlayableKind.values.byName(r['kind'] as String),
                      key: r['key'] as String,
                      seriesKey: Value(r['seriesKey'] as String?),
                      positionMs: r['positionMs'] as int,
                      durationMs: r['durationMs'] as int,
                      updatedAt: r['updatedAt'] as int,
                      finished: Value(r['finished'] as bool),
                    ),
                  );
            }
          case 'recent':
            if (sid != null) {
              await db
                  .into(db.recentChannels)
                  .insertOnConflictUpdate(
                    RecentChannelsCompanion.insert(
                      sourceId: sid,
                      key: r['key'] as String,
                      lastWatchedAt: r['lastWatchedAt'] as int,
                    ),
                  );
            }
          case 'preferences':
            final old = await loadAppSettings(db.settingsDao);
            final shared = AppSettings.fromJson(r);
            await db.settingsDao.setJson(
              kAppSettingsKey,
              old
                  .copyWith(
                    locale: shared.locale,
                    preferredAudioLang: shared.preferredAudioLang,
                    preferredSubLang: shared.preferredSubLang,
                  )
                  .toJson(),
            );
        }
      }
      await db.settingsDao.setJson(_idsKey, _ids);
    });
  }
}
