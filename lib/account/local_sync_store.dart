import 'dart:convert';
import 'dart:io';
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
  final _files = <String, ({DateTime modified, int size, String encoded})>{};

  /// Playlist copies replaced or deleted by [apply], removed by [export] once
  /// no source uses them (a rolled-back apply still does).
  final _replaced = <String>{};
  final _random = Random();

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
      String? file;
      if (config.kind == SourceKind.m3uFile) {
        final input = File(config.url);
        final stat = await input.stat();
        if (stat.type != FileSystemEntityType.file) {
          throw const AccountException('PLAYLIST_FILE_MISSING');
        }
        if (stat.size > 32 * 1024 * 1024) {
          throw const AccountException('PLAYLIST_FILE_TOO_LARGE');
        }
        final cache = _files[config.url];
        file =
            cache != null &&
                cache.modified == stat.modified &&
                cache.size == stat.size
            ? cache.encoded
            : base64Encode(gzip.encode(await input.readAsBytes()));
        _files[config.url] = (
          modified: stat.modified,
          size: stat.size,
          encoded: file,
        );
      }
      final sid = _id('source:${row.id}', [
        config.kind.name,
        file ?? config.url,
        config.username,
      ], heldSources);
      sources[row.id] = sid;
      final parts = file == null ? 0 : (file.length / 350000).ceil();
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
        if (file != null) 'fileHash': syncId(file),
      };
      for (var i = 0; i < parts; i++) {
        result['file:$sid:$i'] = {
          'type': 'file',
          'source': sid,
          'part': i,
          'data': file!.substring(
            i * 350000,
            ((i + 1) * 350000).clamp(0, file.length),
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
  /// was synced, so a restart does not re-encode and re-upload them.
  Future<void> remember(SyncData data) async {
    await _load();
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
      try {
        final encoded = _encoded(data, r);
        if (encoded == null) continue;
        final input = File(config.url);
        final stat = await input.stat();
        if (_same(await input.readAsBytes(), _decode(encoded))) {
          _files[config.url] = (
            modified: stat.modified,
            size: stat.size,
            encoded: encoded,
          );
        }
      } on Object {
        // A changed, missing or damaged copy is encoded afresh by export.
      }
    }
  }

  /// The verified encoded playlist of file source [r], or null.
  static String? _encoded(SyncData data, Map<String, Object?> r) {
    final count = r['fileParts'] as int;
    if (count < 1 || count > 200) return null;
    final encoded = List.generate(
      count,
      (i) => data['file:${r['source']}:$i']?['data'] as String? ?? '',
    ).join();
    return syncId(encoded) == r['fileHash'] ? encoded : null;
  }

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
          'cloud-${syncId([cloudId, syncId(encoded)])}.m3u';
      await File(path).writeAsBytes(bytes, flush: true);
    }
    final stat = await File(path!).stat();
    _files[path] = (modified: stat.modified, size: stat.size, encoded: encoded);
    return path;
  }

  /// Applies only changed rows in one local transaction. Remote IDs never
  /// become database IDs. File sources are reconstructed in app-private storage.
  Future<Set<int>> apply(SyncData target) async {
    final current = await export();
    final changed = syncChanges(current, target);
    final needImport = <int>{};
    try {
      await _apply(target, current, changed, needImport);
    } on Object {
      // The rollback also removed rows created here: forget the cloud IDs
      // given to them, or a later local row would inherit one.
      _loaded = false;
      rethrow;
    }
    return needImport;
  }

  Future<void> _apply(
    SyncData target,
    SyncData current,
    Map<String, Map<String, Object?>?> changed,
    Set<int> needImport,
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
            if (lid != null) {
              await db.channelListsDao.setChannel(
                lid,
                old['key'] as String,
                false,
              );
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
          } else {
            final encoded = _encoded(target, r);
            if (encoded == null) {
              throw const AccountException('INVALID_PLAYLIST');
            }
            url = await _receive(encoded, oldFile, cloudId);
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
