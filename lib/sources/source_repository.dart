import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../core/db/app_db.dart';
import '../core/log/ring_log.dart';
import '../core/net/http.dart';
import '../core/net/redact.dart';
import '../core/secure/secret_store.dart';
import '../core/time/clock.dart';
import 'm3u/m3u_adapter.dart';
import 'models.dart';
import 'source_adapter.dart';
import 'xtream/xtream_adapter.dart';
import 'xtream/xtream_urls.dart';
import 'xtream_link.dart';

export 'xtream_link.dart' show XtreamLink;

/// A saved source as listed in source management (credentials masked).
typedef SourceView = SourceRow;

/// Builds the HTTP client for one source (its User-Agent and Referer).
typedef DioFactory = Dio Function({String? userAgent, String? referer});

/// Why checking or importing a source failed.
enum VerifyErrorReason {
  /// The address is not an `http(s)://host` URL.
  invalidUrl,

  /// Connection refused, DNS failure, HTTP error status...
  unreachable,
  timeout,

  /// Wrong username or password (Xtream `auth != 1`, HTTP 401/403).
  authFailed,

  /// The account expired ([VerifyError.expiresAt] when known).
  expired,
  banned,
  disabled,

  /// The body is not an M3U playlist, or the playlist has no entries.
  notM3u,

  /// A picked playlist file is missing or unreadable.
  fileUnreadable,
  unknown,
}

/// The outcome of [SourceRepository.verify].
sealed class VerifyResult {
  const VerifyResult();
}

/// The source answered and the account can be used.
final class VerifyOk extends VerifyResult {
  const VerifyOk(this.account);

  final AccountInfo account;
}

/// A typed, credential-free failure. Also used for failed syncs.
final class VerifyError extends VerifyResult implements Exception {
  const VerifyError(
    this.reason, {
    this.message = '',
    this.expiresAt,
    this.statusCode,
  });

  /// Maps an adapter error. [secrets] are masked in [message] on top of the
  /// usual URL credentials.
  factory VerifyError.fromError(
    Object error, {
    SourceKind? kind,
    Iterable<String> secrets = const [],
  }) {
    String safe(String m) => redact(m, secrets: secrets);
    final file = kind == SourceKind.m3uFile;
    return switch (error) {
      VerifyError() => error,
      AuthFailure(:final status, :final message) => switch (status) {
        AccountStatus.expired => VerifyError(
          VerifyErrorReason.expired,
          message: safe(message),
        ),
        AccountStatus.banned => VerifyError(
          VerifyErrorReason.banned,
          message: safe(message),
        ),
        AccountStatus.disabled => VerifyError(
          VerifyErrorReason.disabled,
          message: safe(message),
        ),
        _ => VerifyError(VerifyErrorReason.authFailed, message: safe(message)),
      },
      TimeoutFailure(:final message) => VerifyError(
        VerifyErrorReason.timeout,
        message: safe(message),
      ),
      NetworkFailure(:final message, :final statusCode) => VerifyError(
        file ? VerifyErrorReason.fileUnreadable : VerifyErrorReason.unreachable,
        message: safe(message),
        statusCode: statusCode,
      ),
      ParseFailure(:final message) => VerifyError(
        message.startsWith('Invalid server address')
            ? VerifyErrorReason.invalidUrl
            : kind == SourceKind.xtream
            ? VerifyErrorReason.unknown
            : VerifyErrorReason.notM3u,
        message: safe(message),
      ),
      CancelledFailure() => const VerifyError(
        VerifyErrorReason.unknown,
        message: 'cancelled',
      ),
      FileSystemException() => VerifyError(
        VerifyErrorReason.fileUnreadable,
        message: safe('$error'),
      ),
      _ => VerifyError(VerifyErrorReason.unknown, message: safe('$error')),
    };
  }

  final VerifyErrorReason reason;

  /// Technical detail for logs and Diagnostics; never contains credentials.
  final String message;

  /// Expiry date for [VerifyErrorReason.expired], when the panel sent one.
  final DateTime? expiresAt;

  /// HTTP status for [VerifyErrorReason.unreachable], when known.
  final int? statusCode;

  @override
  String toString() =>
      'VerifyError(${reason.name}'
      '${statusCode == null ? '' : ', HTTP $statusCode'}'
      '${message.isEmpty ? '' : ', $message'})';
}

/// The failure for an account [AccountInfo.status] that cannot be used
/// (expired, banned, disabled), or null for a usable one.
VerifyError? accountError(AccountInfo info) => switch (info.status) {
  AccountStatus.expired => VerifyError(
    VerifyErrorReason.expired,
    message: 'account expired',
    expiresAt: info.expiresAt,
  ),
  AccountStatus.banned => const VerifyError(
    VerifyErrorReason.banned,
    message: 'account banned',
  ),
  AccountStatus.disabled => const VerifyError(
    VerifyErrorReason.disabled,
    message: 'account disabled',
  ),
  AccountStatus.active || AccountStatus.unknown => null,
};

/// Builds the adapter for [config]. A top-level function so a background
/// sync isolate can call it (it captures nothing).
SourceAdapter createSourceAdapter(
  SourceConfig config, {
  bool lowMemory = false,
  DioFactory dioFactory = createDio,
  Clock clock = const SystemClock(),
  List<String> allowedFormats = const [],
}) {
  final dio = dioFactory(userAgent: config.userAgent, referer: config.referer);
  return switch (config.kind) {
    SourceKind.xtream => XtreamAdapter(
      config,
      dio: dio,
      lowMemory: lowMemory,
      allowedFormats: allowedFormats,
      clock: clock,
    ),
    SourceKind.m3uUrl || SourceKind.m3uFile => M3uAdapter(config, dio: dio),
  };
}

/// Every credential of [config] (at least 3 characters): the username and
/// password, and the user info, credential query values (`username`,
/// `password`, `token`...) and Xtream login of its URL.
Set<String> sourceSecrets(SourceConfig config) {
  final found = <String>{?config.username, ?config.password};
  final link = parseXtreamLink(config.url);
  if (link != null) found.addAll([link.username, link.password]);
  final uri = config.kind == SourceKind.m3uFile
      ? null
      : Uri.tryParse(config.url.trim());
  if (uri != null) {
    for (final part in uri.userInfo.split(':')) {
      found.add(_decode(part));
    }
    for (final MapEntry(:key, :value) in _queryPairs(uri.query)) {
      if (_credentialParams.contains(key.toLowerCase())) found.add(value);
    }
  }
  return {
    for (final s in found)
      if (s.trim().length >= 3) s,
  };
}

const _credentialParams = {
  'username',
  'user',
  'password',
  'pass',
  'pwd',
  'token',
  'auth',
  'key',
};

/// Query pairs, tolerant to malformed percent-encoding.
Iterable<MapEntry<String, String>> _queryPairs(String query) sync* {
  for (final pair in query.split('&')) {
    final eq = pair.indexOf('=');
    if (eq <= 0) continue;
    yield MapEntry(
      _decode(pair.substring(0, eq)),
      _decode(pair.substring(eq + 1)),
    );
  }
}

String _decode(String s) {
  try {
    return Uri.decodeQueryComponent(s);
  } on FormatException {
    return s;
  }
}

Future<String> _defaultAppSupportDir() async =>
    (await getApplicationSupportDirectory()).path;

/// Saved sources: listing, checking, adding, editing and deleting, plus
/// adapters for sync and playback.
///
/// Credentials never land in the `sources` table: the Xtream password and a
/// playlist URL that embeds credentials are kept in the [SecretStore], and
/// `sources.url` holds a masked copy for display ([SourcesDao] does this).
class SourceRepository {
  SourceRepository(
    this._db,
    this._secrets, {
    this._dioFactory = createDio,
    this._appSupportDir = _defaultAppSupportDir,
    this._lowMemory,
    this._clock = const SystemClock(),
    this.beforeDelete,
    RingLog? log,
  }) : _log = log ?? RingLog.instance;

  /// Folder (under the app-support directory) for imported playlist files.
  static const importDirName = 'sources';

  final AppDatabase _db;
  final SecretStore _secrets;
  final DioFactory _dioFactory;
  final Future<String> Function() _appSupportDir;
  final bool Function()? _lowMemory;
  final Clock _clock;
  final RingLog _log;

  /// Called with the source id before [delete] removes it. The sync service
  /// sets it to cancel a running sync of that source.
  Future<void> Function(int sourceId)? beforeDelete;

  /// Sources whose credentials were registered by [rememberSecretsOf].
  final _remembered = <int>{};

  SourcesDao get _sources => _db.sourcesDao;

  /// Whether adapters are built in low-memory (Lite) mode.
  bool get lowMemory => _lowMemory?.call() ?? false;

  Future<List<SourceView>> list() => _sources.all();

  Stream<List<SourceView>> watch() => _sources.watchAll();

  Future<SourceView?> byId(int id) => _sources.byId(id);

  /// Full configuration of a saved source, with its password and unmasked
  /// URL. Throws a [StateError] for an unknown id.
  Future<SourceConfig> configFor(int id) async {
    final config = await _sources.configFor(id, _secrets);
    if (config == null) throw StateError('Unknown source $id');
    _rememberSecrets(config);
    return config;
  }

  /// Registers the credentials of every saved source in [rows] with the
  /// log (once per source), so they are masked in Diagnostics even before
  /// the source is used in this run. Never throws.
  Future<void> rememberSecretsOf(Iterable<SourceView> rows) async {
    for (final row in rows) {
      if (!_remembered.add(row.id)) continue;
      try {
        await configFor(row.id);
      } on Object {
        _remembered.remove(row.id);
      }
    }
  }

  /// A fresh adapter for [config]; close it when done.
  SourceAdapter adapterFor(
    SourceConfig config, {
    List<String> allowedFormats = const [],
  }) {
    _rememberSecrets(config);
    return createSourceAdapter(
      config,
      lowMemory: lowMemory,
      dioFactory: _dioFactory,
      clock: _clock,
      allowedFormats: allowedFormats,
    );
  }

  /// An adapter for a saved source, seeded with its stored allowed formats
  /// (for playback-only use such as `resolve`).
  Future<SourceAdapter> adapterForSource(int id) async {
    final row = await _sources.byId(id);
    if (row == null) throw StateError('Unknown source $id');
    return adapterFor(await configFor(id), allowedFormats: row.allowedFormats);
  }

  /// Checks [draft] (reachable, valid login, really a playlist) without
  /// saving it.
  Future<VerifyResult> verify(SourceConfig draft) async {
    final config = normalize(draft);
    final invalid = _validate(config);
    if (invalid != null) return invalid;
    _rememberSecrets(config);
    final adapter = adapterFor(config);
    try {
      final info = await adapter.verify();
      return accountError(info) ?? VerifyOk(info);
    } on Object catch (e) {
      final error = VerifyError.fromError(
        e,
        kind: config.kind,
        secrets: _secretValues(config),
      );
      _log.warn('Verify failed: $error');
      return error;
    } finally {
      adapter.close();
    }
  }

  /// Saves [draft] and returns its id. Run [verify] first.
  Future<int> add(SourceConfig draft) async {
    final config = normalize(draft);
    _rememberSecrets(config);
    final id = await _sources.create(config, secrets: _secrets);
    _log.info('Source $id added (${config.kind.name})');
    return id;
  }

  /// Saves edits of source [id]. A null password keeps the saved one;
  /// start from [configFor] so the full URL is kept.
  Future<void> update(int id, SourceConfig config) async {
    final normalized = normalize(config);
    _rememberSecrets(normalized);
    await _sources.updateConfig(id, normalized, secrets: _secrets);
  }

  /// Deletes source [id] with its catalog, guide sources, favourites,
  /// progress, prefs and secrets (database cascades), and its imported
  /// playlist file.
  Future<void> delete(int id) async {
    await beforeDelete?.call(id);
    final row = await _sources.byId(id);
    await _sources.deleteSource(id, secrets: _secrets);
    if (row != null && row.kind == SourceKind.m3uFile) {
      await _deleteImportedFile(row.url);
    }
    _log.info('Source $id deleted');
  }

  /// Copies a picked playlist to `<appSupport>/sources/<uuid>.m3u` (content
  /// URIs and picked paths can expire) and returns the copy's path.
  Future<String> importM3uFile(String pickedPath) async {
    final dir = Directory(_join(await _appSupportDir(), importDirName));
    await dir.create(recursive: true);
    final target = File(_join(dir.path, '${_uuidV4()}.m3u'));
    await File(pickedPath).copy(target.path);
    return target.path;
  }

  /// Deletes a copy made by [importM3uFile] that no source uses any more
  /// (the playlist was replaced, or the source changed type). Paths outside
  /// the import folder are left alone. Never throws.
  Future<void> deleteImportedFile(String path) => _deleteImportedFile(path);

  /// Xtream credentials inside a pasted playlist URL, if any.
  XtreamLink? detectXtreamLink(String url) => parseXtreamLink(url);

  /// Trims fields, normalises the Xtream base and fills an empty name.
  SourceConfig normalize(SourceConfig c) {
    final url = switch (c.kind) {
      SourceKind.xtream => XtreamUrls.normalizeBase(c.url),
      SourceKind.m3uUrl || SourceKind.m3uFile => c.url.trim(),
    };
    final name = c.name.trim().isEmpty ? defaultName(c.kind, url) : c.name;
    return SourceConfig(
      id: c.id,
      kind: c.kind,
      url: url,
      name: name.trim(),
      username: _blankToNull(c.username),
      password: c.password,
      userAgent: _blankToNull(c.userAgent),
      referer: _blankToNull(c.referer),
      liveFormat: c.liveFormat,
      epgOffsetMin: c.epgOffsetMin,
    );
  }

  /// Host of a URL, or the file name of a playlist path.
  static String defaultName(SourceKind kind, String url) {
    if (kind == SourceKind.m3uFile) {
      final name = url.split(RegExp(r'[/\\]')).last;
      final dot = name.lastIndexOf('.');
      final base = dot > 0 ? name.substring(0, dot) : name;
      return base.isEmpty ? 'M3U' : base;
    }
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? (kind == SourceKind.xtream ? 'Xtream' : 'M3U') : host;
  }

  VerifyError? _validate(SourceConfig c) {
    switch (c.kind) {
      case SourceKind.xtream:
        if (XtreamUrls.parseBase(c.url) == null) {
          return const VerifyError(
            VerifyErrorReason.invalidUrl,
            message: 'Invalid server address',
          );
        }
        if ((c.username ?? '').isEmpty || (c.password ?? '').isEmpty) {
          return const VerifyError(
            VerifyErrorReason.authFailed,
            message: 'Missing username or password',
          );
        }
      case SourceKind.m3uUrl:
        final uri = Uri.tryParse(c.url);
        final scheme = uri?.scheme.toLowerCase();
        if (uri == null ||
            (scheme != 'http' && scheme != 'https') ||
            uri.host.isEmpty) {
          return const VerifyError(
            VerifyErrorReason.invalidUrl,
            message: 'Invalid playlist URL',
          );
        }
      case SourceKind.m3uFile:
        if (c.url.isEmpty || !File(c.url).existsSync()) {
          return const VerifyError(
            VerifyErrorReason.fileUnreadable,
            message: 'Playlist file not found',
          );
        }
    }
    return null;
  }

  Future<void> _deleteImportedFile(String path) async {
    try {
      final root = _join(await _appSupportDir(), importDirName);
      final file = File(path);
      if (file.parent.absolute.path == Directory(root).absolute.path &&
          file.existsSync()) {
        await file.delete();
      }
    } on Object catch (e) {
      _log.warn('Could not delete imported playlist: $e');
    }
  }

  List<String> _secretValues(SourceConfig c) => sourceSecrets(c).toList();

  /// Credentials are masked in every later log line, wherever they appear
  /// (for example in the short Xtream stream URLs of an M3U playlist,
  /// `http://host/user/pass/123`, which [redact] cannot recognise).
  void _rememberSecrets(SourceConfig c) =>
      sourceSecrets(c).forEach(_log.addSecret);

  static String? _blankToNull(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();

  static String _join(String dir, String name) =>
      '$dir${Platform.pathSeparator}$name';

  /// A random (version 4) UUID.
  static String _uuidV4() {
    final random = Random.secure();
    final b = [for (var i = 0; i < 16; i++) random.nextInt(256)];
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final hex = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
