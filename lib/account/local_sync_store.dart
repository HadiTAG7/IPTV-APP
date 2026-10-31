import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../app/settings.dart';
import '../core/db/app_db.dart';
import '../sources/models.dart';
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

  Future<void> _load() async {
    if (_loaded) return;
    final json = await db.settingsDao.getJson(_idsKey);
    if (json is Map) _ids = Map<String, String>.from(json);
    _loaded = true;
  }

  String _id(String key, Object identity) =>
      _ids.putIfAbsent(key, () => syncId(identity));

  Future<SyncData> export() => db.transaction(() async {
    await _load();
    final result = <String, Map<String, Object?>>{};
    final sources = <int, String>{};
    for (final row in await db.sourcesDao.all()) {
      final config = (await db.sourcesDao.configFor(row.id))!;
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
      ]);
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
    for (final row in await db.select(db.channelLists).get()) {
      final sid = sources[row.sourceId];
      if (sid == null) continue;
      final lid = _id('list:${row.id}', [sid, row.name.toLowerCase()]);
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
    return result;
  });

  /// Applies only changed rows in one local transaction. Remote IDs never
  /// become database IDs. File sources are reconstructed in app-private storage.
  Future<Set<int>> apply(SyncData target) async {
    final current = await export();
    final changed = syncChanges(current, target);
    final needImport = <int>{};
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
            if (sid != null) await db.sourcesDao.deleteSource(sid);
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
        var url = r['url'] as String;
        if (kind == SourceKind.m3uFile) {
          final count = r['fileParts'] as int;
          if (count < 1 || count > 200) {
            throw const AccountException('INVALID_PLAYLIST');
          }
          final encoded = List.generate(
            count,
            (i) => target['file:$cloudId:$i']?['data'] as String? ?? '',
          ).join();
          if (syncId(encoded) != r['fileHash']) {
            throw const AccountException('INVALID_PLAYLIST');
          }
          final folder = await directory();
          final file = File('${folder.path}/cloud-${syncId(cloudId)}.m3u');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(
            gzip.decode(base64Decode(encoded)),
            flush: true,
          );
          url = file.path;
        }
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
          final old = await db.sourcesDao.configFor(id);
          await db.sourcesDao.updateConfig(id, config);
          if (old?.url != config.url ||
              old?.username != config.username ||
              old?.password != config.password ||
              current[e.key]?['fileHash'] != r['fileHash']) {
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
    return needImport;
  }
}
