// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_db.dart';

// ignore_for_file: type=lint
class $SourcesTable extends Sources
    with TableInfo<$SourcesTable, SourceRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SourcesTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SourceKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<SourceKind>($SourcesTable.$converterkind);
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> userAgent = GeneratedColumn<String>(
    'user_agent',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> referer = GeneratedColumn<String>(
    'referer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<LiveFormat, String> liveFormat =
      GeneratedColumn<String>(
        'live_format',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('ts'),
      ).withConverter<LiveFormat>($SourcesTable.$converterliveFormat);
  @override
  late final GeneratedColumn<int> epgOffsetMin = GeneratedColumn<int>(
    'epg_offset_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<EngineKind?, String> engineLive =
      GeneratedColumn<String>(
        'engine_live',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<EngineKind?>($SourcesTable.$converterengineLiven);
  @override
  late final GeneratedColumnWithTypeConverter<EngineKind?, String> engineVod =
      GeneratedColumn<String>(
        'engine_vod',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<EngineKind?>($SourcesTable.$converterengineVodn);
  @override
  late final GeneratedColumnWithTypeConverter<AccountStatus, String>
  accountStatus = GeneratedColumn<String>(
    'account_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown'),
  ).withConverter<AccountStatus>($SourcesTable.$converteraccountStatus);
  @override
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> maxConnections = GeneratedColumn<int>(
    'max_connections',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> allowedFormatsJson =
      GeneratedColumn<String>(
        'allowed_formats_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  late final GeneratedColumn<int> generation = GeneratedColumn<int>(
    'generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumn<int> openGeneration = GeneratedColumn<int>(
    'open_generation',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> lastGeneration = GeneratedColumn<int>(
    'last_generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumn<int> lastSyncAt = GeneratedColumn<int>(
    'last_sync_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> lastEpgAt = GeneratedColumn<int>(
    'last_epg_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> sortIndex = GeneratedColumn<int>(
    'sort_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    kind,
    url,
    username,
    userAgent,
    referer,
    liveFormat,
    epgOffsetMin,
    engineLive,
    engineVod,
    accountStatus,
    expiresAt,
    maxConnections,
    allowedFormatsJson,
    generation,
    openGeneration,
    lastGeneration,
    lastSyncAt,
    lastEpgAt,
    sortIndex,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sources';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SourceRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SourceRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      kind: $SourcesTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      ),
      userAgent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_agent'],
      ),
      referer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}referer'],
      ),
      liveFormat: $SourcesTable.$converterliveFormat.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}live_format'],
        )!,
      ),
      epgOffsetMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}epg_offset_min'],
      )!,
      engineLive: $SourcesTable.$converterengineLiven.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}engine_live'],
        ),
      ),
      engineVod: $SourcesTable.$converterengineVodn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}engine_vod'],
        ),
      ),
      accountStatus: $SourcesTable.$converteraccountStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}account_status'],
        )!,
      ),
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at'],
      ),
      maxConnections: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_connections'],
      ),
      allowedFormatsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}allowed_formats_json'],
      ),
      generation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generation'],
      )!,
      openGeneration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}open_generation'],
      ),
      lastGeneration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_generation'],
      )!,
      lastSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_sync_at'],
      ),
      lastEpgAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_epg_at'],
      ),
      sortIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_index'],
      )!,
    );
  }

  @override
  $SourcesTable createAlias(String alias) {
    return $SourcesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SourceKind, String, String> $converterkind =
      const EnumNameConverter<SourceKind>(SourceKind.values);
  static JsonTypeConverter2<LiveFormat, String, String> $converterliveFormat =
      const EnumNameConverter<LiveFormat>(LiveFormat.values);
  static JsonTypeConverter2<EngineKind, String, String> $converterengineLive =
      const EnumNameConverter<EngineKind>(EngineKind.values);
  static JsonTypeConverter2<EngineKind?, String?, String?>
  $converterengineLiven = JsonTypeConverter2.asNullable($converterengineLive);
  static JsonTypeConverter2<EngineKind, String, String> $converterengineVod =
      const EnumNameConverter<EngineKind>(EngineKind.values);
  static JsonTypeConverter2<EngineKind?, String?, String?>
  $converterengineVodn = JsonTypeConverter2.asNullable($converterengineVod);
  static JsonTypeConverter2<AccountStatus, String, String>
  $converteraccountStatus = const EnumNameConverter<AccountStatus>(
    AccountStatus.values,
  );
}

class SourceRecord extends DataClass implements Insertable<SourceRecord> {
  final int id;
  final String name;
  final SourceKind kind;

  /// Playlist URL, app-private file path or Xtream base URL, with any
  /// credentials masked (the full URL is then in [Secrets]).
  final String url;
  final String? username;
  final String? userAgent;
  final String? referer;
  final LiveFormat liveFormat;
  final int epgOffsetMin;
  final EngineKind? engineLive;
  final EngineKind? engineVod;
  final AccountStatus accountStatus;
  final int? expiresAt;
  final int? maxConnections;
  final String? allowedFormatsJson;

  /// Last committed catalog generation (0 = never synced).
  final int generation;

  /// Generation a sync is writing, or null. Only this one accepts writes.
  final int? openGeneration;

  /// Highest generation ever handed out; numbers are never reused, so a
  /// stale or aborted writer can never match a later sync.
  final int lastGeneration;
  final int? lastSyncAt;
  final int? lastEpgAt;
  final int sortIndex;
  const SourceRecord({
    required this.id,
    required this.name,
    required this.kind,
    required this.url,
    this.username,
    this.userAgent,
    this.referer,
    required this.liveFormat,
    required this.epgOffsetMin,
    this.engineLive,
    this.engineVod,
    required this.accountStatus,
    this.expiresAt,
    this.maxConnections,
    this.allowedFormatsJson,
    required this.generation,
    this.openGeneration,
    required this.lastGeneration,
    this.lastSyncAt,
    this.lastEpgAt,
    required this.sortIndex,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    {
      map['kind'] = Variable<String>($SourcesTable.$converterkind.toSql(kind));
    }
    map['url'] = Variable<String>(url);
    if (!nullToAbsent || username != null) {
      map['username'] = Variable<String>(username);
    }
    if (!nullToAbsent || userAgent != null) {
      map['user_agent'] = Variable<String>(userAgent);
    }
    if (!nullToAbsent || referer != null) {
      map['referer'] = Variable<String>(referer);
    }
    {
      map['live_format'] = Variable<String>(
        $SourcesTable.$converterliveFormat.toSql(liveFormat),
      );
    }
    map['epg_offset_min'] = Variable<int>(epgOffsetMin);
    if (!nullToAbsent || engineLive != null) {
      map['engine_live'] = Variable<String>(
        $SourcesTable.$converterengineLiven.toSql(engineLive),
      );
    }
    if (!nullToAbsent || engineVod != null) {
      map['engine_vod'] = Variable<String>(
        $SourcesTable.$converterengineVodn.toSql(engineVod),
      );
    }
    {
      map['account_status'] = Variable<String>(
        $SourcesTable.$converteraccountStatus.toSql(accountStatus),
      );
    }
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<int>(expiresAt);
    }
    if (!nullToAbsent || maxConnections != null) {
      map['max_connections'] = Variable<int>(maxConnections);
    }
    if (!nullToAbsent || allowedFormatsJson != null) {
      map['allowed_formats_json'] = Variable<String>(allowedFormatsJson);
    }
    map['generation'] = Variable<int>(generation);
    if (!nullToAbsent || openGeneration != null) {
      map['open_generation'] = Variable<int>(openGeneration);
    }
    map['last_generation'] = Variable<int>(lastGeneration);
    if (!nullToAbsent || lastSyncAt != null) {
      map['last_sync_at'] = Variable<int>(lastSyncAt);
    }
    if (!nullToAbsent || lastEpgAt != null) {
      map['last_epg_at'] = Variable<int>(lastEpgAt);
    }
    map['sort_index'] = Variable<int>(sortIndex);
    return map;
  }

  SourcesCompanion toCompanion(bool nullToAbsent) {
    return SourcesCompanion(
      id: Value(id),
      name: Value(name),
      kind: Value(kind),
      url: Value(url),
      username: username == null && nullToAbsent
          ? const Value.absent()
          : Value(username),
      userAgent: userAgent == null && nullToAbsent
          ? const Value.absent()
          : Value(userAgent),
      referer: referer == null && nullToAbsent
          ? const Value.absent()
          : Value(referer),
      liveFormat: Value(liveFormat),
      epgOffsetMin: Value(epgOffsetMin),
      engineLive: engineLive == null && nullToAbsent
          ? const Value.absent()
          : Value(engineLive),
      engineVod: engineVod == null && nullToAbsent
          ? const Value.absent()
          : Value(engineVod),
      accountStatus: Value(accountStatus),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      maxConnections: maxConnections == null && nullToAbsent
          ? const Value.absent()
          : Value(maxConnections),
      allowedFormatsJson: allowedFormatsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(allowedFormatsJson),
      generation: Value(generation),
      openGeneration: openGeneration == null && nullToAbsent
          ? const Value.absent()
          : Value(openGeneration),
      lastGeneration: Value(lastGeneration),
      lastSyncAt: lastSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncAt),
      lastEpgAt: lastEpgAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastEpgAt),
      sortIndex: Value(sortIndex),
    );
  }

  factory SourceRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SourceRecord(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      kind: $SourcesTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      url: serializer.fromJson<String>(json['url']),
      username: serializer.fromJson<String?>(json['username']),
      userAgent: serializer.fromJson<String?>(json['userAgent']),
      referer: serializer.fromJson<String?>(json['referer']),
      liveFormat: $SourcesTable.$converterliveFormat.fromJson(
        serializer.fromJson<String>(json['liveFormat']),
      ),
      epgOffsetMin: serializer.fromJson<int>(json['epgOffsetMin']),
      engineLive: $SourcesTable.$converterengineLiven.fromJson(
        serializer.fromJson<String?>(json['engineLive']),
      ),
      engineVod: $SourcesTable.$converterengineVodn.fromJson(
        serializer.fromJson<String?>(json['engineVod']),
      ),
      accountStatus: $SourcesTable.$converteraccountStatus.fromJson(
        serializer.fromJson<String>(json['accountStatus']),
      ),
      expiresAt: serializer.fromJson<int?>(json['expiresAt']),
      maxConnections: serializer.fromJson<int?>(json['maxConnections']),
      allowedFormatsJson: serializer.fromJson<String?>(
        json['allowedFormatsJson'],
      ),
      generation: serializer.fromJson<int>(json['generation']),
      openGeneration: serializer.fromJson<int?>(json['openGeneration']),
      lastGeneration: serializer.fromJson<int>(json['lastGeneration']),
      lastSyncAt: serializer.fromJson<int?>(json['lastSyncAt']),
      lastEpgAt: serializer.fromJson<int?>(json['lastEpgAt']),
      sortIndex: serializer.fromJson<int>(json['sortIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String>(
        $SourcesTable.$converterkind.toJson(kind),
      ),
      'url': serializer.toJson<String>(url),
      'username': serializer.toJson<String?>(username),
      'userAgent': serializer.toJson<String?>(userAgent),
      'referer': serializer.toJson<String?>(referer),
      'liveFormat': serializer.toJson<String>(
        $SourcesTable.$converterliveFormat.toJson(liveFormat),
      ),
      'epgOffsetMin': serializer.toJson<int>(epgOffsetMin),
      'engineLive': serializer.toJson<String?>(
        $SourcesTable.$converterengineLiven.toJson(engineLive),
      ),
      'engineVod': serializer.toJson<String?>(
        $SourcesTable.$converterengineVodn.toJson(engineVod),
      ),
      'accountStatus': serializer.toJson<String>(
        $SourcesTable.$converteraccountStatus.toJson(accountStatus),
      ),
      'expiresAt': serializer.toJson<int?>(expiresAt),
      'maxConnections': serializer.toJson<int?>(maxConnections),
      'allowedFormatsJson': serializer.toJson<String?>(allowedFormatsJson),
      'generation': serializer.toJson<int>(generation),
      'openGeneration': serializer.toJson<int?>(openGeneration),
      'lastGeneration': serializer.toJson<int>(lastGeneration),
      'lastSyncAt': serializer.toJson<int?>(lastSyncAt),
      'lastEpgAt': serializer.toJson<int?>(lastEpgAt),
      'sortIndex': serializer.toJson<int>(sortIndex),
    };
  }

  SourceRecord copyWith({
    int? id,
    String? name,
    SourceKind? kind,
    String? url,
    Value<String?> username = const Value.absent(),
    Value<String?> userAgent = const Value.absent(),
    Value<String?> referer = const Value.absent(),
    LiveFormat? liveFormat,
    int? epgOffsetMin,
    Value<EngineKind?> engineLive = const Value.absent(),
    Value<EngineKind?> engineVod = const Value.absent(),
    AccountStatus? accountStatus,
    Value<int?> expiresAt = const Value.absent(),
    Value<int?> maxConnections = const Value.absent(),
    Value<String?> allowedFormatsJson = const Value.absent(),
    int? generation,
    Value<int?> openGeneration = const Value.absent(),
    int? lastGeneration,
    Value<int?> lastSyncAt = const Value.absent(),
    Value<int?> lastEpgAt = const Value.absent(),
    int? sortIndex,
  }) => SourceRecord(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    url: url ?? this.url,
    username: username.present ? username.value : this.username,
    userAgent: userAgent.present ? userAgent.value : this.userAgent,
    referer: referer.present ? referer.value : this.referer,
    liveFormat: liveFormat ?? this.liveFormat,
    epgOffsetMin: epgOffsetMin ?? this.epgOffsetMin,
    engineLive: engineLive.present ? engineLive.value : this.engineLive,
    engineVod: engineVod.present ? engineVod.value : this.engineVod,
    accountStatus: accountStatus ?? this.accountStatus,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    maxConnections: maxConnections.present
        ? maxConnections.value
        : this.maxConnections,
    allowedFormatsJson: allowedFormatsJson.present
        ? allowedFormatsJson.value
        : this.allowedFormatsJson,
    generation: generation ?? this.generation,
    openGeneration: openGeneration.present
        ? openGeneration.value
        : this.openGeneration,
    lastGeneration: lastGeneration ?? this.lastGeneration,
    lastSyncAt: lastSyncAt.present ? lastSyncAt.value : this.lastSyncAt,
    lastEpgAt: lastEpgAt.present ? lastEpgAt.value : this.lastEpgAt,
    sortIndex: sortIndex ?? this.sortIndex,
  );
  SourceRecord copyWithCompanion(SourcesCompanion data) {
    return SourceRecord(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      url: data.url.present ? data.url.value : this.url,
      username: data.username.present ? data.username.value : this.username,
      userAgent: data.userAgent.present ? data.userAgent.value : this.userAgent,
      referer: data.referer.present ? data.referer.value : this.referer,
      liveFormat: data.liveFormat.present
          ? data.liveFormat.value
          : this.liveFormat,
      epgOffsetMin: data.epgOffsetMin.present
          ? data.epgOffsetMin.value
          : this.epgOffsetMin,
      engineLive: data.engineLive.present
          ? data.engineLive.value
          : this.engineLive,
      engineVod: data.engineVod.present ? data.engineVod.value : this.engineVod,
      accountStatus: data.accountStatus.present
          ? data.accountStatus.value
          : this.accountStatus,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      maxConnections: data.maxConnections.present
          ? data.maxConnections.value
          : this.maxConnections,
      allowedFormatsJson: data.allowedFormatsJson.present
          ? data.allowedFormatsJson.value
          : this.allowedFormatsJson,
      generation: data.generation.present
          ? data.generation.value
          : this.generation,
      openGeneration: data.openGeneration.present
          ? data.openGeneration.value
          : this.openGeneration,
      lastGeneration: data.lastGeneration.present
          ? data.lastGeneration.value
          : this.lastGeneration,
      lastSyncAt: data.lastSyncAt.present
          ? data.lastSyncAt.value
          : this.lastSyncAt,
      lastEpgAt: data.lastEpgAt.present ? data.lastEpgAt.value : this.lastEpgAt,
      sortIndex: data.sortIndex.present ? data.sortIndex.value : this.sortIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SourceRecord(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('url: $url, ')
          ..write('username: $username, ')
          ..write('userAgent: $userAgent, ')
          ..write('referer: $referer, ')
          ..write('liveFormat: $liveFormat, ')
          ..write('epgOffsetMin: $epgOffsetMin, ')
          ..write('engineLive: $engineLive, ')
          ..write('engineVod: $engineVod, ')
          ..write('accountStatus: $accountStatus, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('maxConnections: $maxConnections, ')
          ..write('allowedFormatsJson: $allowedFormatsJson, ')
          ..write('generation: $generation, ')
          ..write('openGeneration: $openGeneration, ')
          ..write('lastGeneration: $lastGeneration, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('lastEpgAt: $lastEpgAt, ')
          ..write('sortIndex: $sortIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    kind,
    url,
    username,
    userAgent,
    referer,
    liveFormat,
    epgOffsetMin,
    engineLive,
    engineVod,
    accountStatus,
    expiresAt,
    maxConnections,
    allowedFormatsJson,
    generation,
    openGeneration,
    lastGeneration,
    lastSyncAt,
    lastEpgAt,
    sortIndex,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceRecord &&
          other.id == this.id &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.url == this.url &&
          other.username == this.username &&
          other.userAgent == this.userAgent &&
          other.referer == this.referer &&
          other.liveFormat == this.liveFormat &&
          other.epgOffsetMin == this.epgOffsetMin &&
          other.engineLive == this.engineLive &&
          other.engineVod == this.engineVod &&
          other.accountStatus == this.accountStatus &&
          other.expiresAt == this.expiresAt &&
          other.maxConnections == this.maxConnections &&
          other.allowedFormatsJson == this.allowedFormatsJson &&
          other.generation == this.generation &&
          other.openGeneration == this.openGeneration &&
          other.lastGeneration == this.lastGeneration &&
          other.lastSyncAt == this.lastSyncAt &&
          other.lastEpgAt == this.lastEpgAt &&
          other.sortIndex == this.sortIndex);
}

class SourcesCompanion extends UpdateCompanion<SourceRecord> {
  final Value<int> id;
  final Value<String> name;
  final Value<SourceKind> kind;
  final Value<String> url;
  final Value<String?> username;
  final Value<String?> userAgent;
  final Value<String?> referer;
  final Value<LiveFormat> liveFormat;
  final Value<int> epgOffsetMin;
  final Value<EngineKind?> engineLive;
  final Value<EngineKind?> engineVod;
  final Value<AccountStatus> accountStatus;
  final Value<int?> expiresAt;
  final Value<int?> maxConnections;
  final Value<String?> allowedFormatsJson;
  final Value<int> generation;
  final Value<int?> openGeneration;
  final Value<int> lastGeneration;
  final Value<int?> lastSyncAt;
  final Value<int?> lastEpgAt;
  final Value<int> sortIndex;
  const SourcesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.url = const Value.absent(),
    this.username = const Value.absent(),
    this.userAgent = const Value.absent(),
    this.referer = const Value.absent(),
    this.liveFormat = const Value.absent(),
    this.epgOffsetMin = const Value.absent(),
    this.engineLive = const Value.absent(),
    this.engineVod = const Value.absent(),
    this.accountStatus = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.maxConnections = const Value.absent(),
    this.allowedFormatsJson = const Value.absent(),
    this.generation = const Value.absent(),
    this.openGeneration = const Value.absent(),
    this.lastGeneration = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.lastEpgAt = const Value.absent(),
    this.sortIndex = const Value.absent(),
  });
  SourcesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required SourceKind kind,
    required String url,
    this.username = const Value.absent(),
    this.userAgent = const Value.absent(),
    this.referer = const Value.absent(),
    this.liveFormat = const Value.absent(),
    this.epgOffsetMin = const Value.absent(),
    this.engineLive = const Value.absent(),
    this.engineVod = const Value.absent(),
    this.accountStatus = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.maxConnections = const Value.absent(),
    this.allowedFormatsJson = const Value.absent(),
    this.generation = const Value.absent(),
    this.openGeneration = const Value.absent(),
    this.lastGeneration = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.lastEpgAt = const Value.absent(),
    this.sortIndex = const Value.absent(),
  }) : name = Value(name),
       kind = Value(kind),
       url = Value(url);
  static Insertable<SourceRecord> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<String>? url,
    Expression<String>? username,
    Expression<String>? userAgent,
    Expression<String>? referer,
    Expression<String>? liveFormat,
    Expression<int>? epgOffsetMin,
    Expression<String>? engineLive,
    Expression<String>? engineVod,
    Expression<String>? accountStatus,
    Expression<int>? expiresAt,
    Expression<int>? maxConnections,
    Expression<String>? allowedFormatsJson,
    Expression<int>? generation,
    Expression<int>? openGeneration,
    Expression<int>? lastGeneration,
    Expression<int>? lastSyncAt,
    Expression<int>? lastEpgAt,
    Expression<int>? sortIndex,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (url != null) 'url': url,
      if (username != null) 'username': username,
      if (userAgent != null) 'user_agent': userAgent,
      if (referer != null) 'referer': referer,
      if (liveFormat != null) 'live_format': liveFormat,
      if (epgOffsetMin != null) 'epg_offset_min': epgOffsetMin,
      if (engineLive != null) 'engine_live': engineLive,
      if (engineVod != null) 'engine_vod': engineVod,
      if (accountStatus != null) 'account_status': accountStatus,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (maxConnections != null) 'max_connections': maxConnections,
      if (allowedFormatsJson != null)
        'allowed_formats_json': allowedFormatsJson,
      if (generation != null) 'generation': generation,
      if (openGeneration != null) 'open_generation': openGeneration,
      if (lastGeneration != null) 'last_generation': lastGeneration,
      if (lastSyncAt != null) 'last_sync_at': lastSyncAt,
      if (lastEpgAt != null) 'last_epg_at': lastEpgAt,
      if (sortIndex != null) 'sort_index': sortIndex,
    });
  }

  SourcesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<SourceKind>? kind,
    Value<String>? url,
    Value<String?>? username,
    Value<String?>? userAgent,
    Value<String?>? referer,
    Value<LiveFormat>? liveFormat,
    Value<int>? epgOffsetMin,
    Value<EngineKind?>? engineLive,
    Value<EngineKind?>? engineVod,
    Value<AccountStatus>? accountStatus,
    Value<int?>? expiresAt,
    Value<int?>? maxConnections,
    Value<String?>? allowedFormatsJson,
    Value<int>? generation,
    Value<int?>? openGeneration,
    Value<int>? lastGeneration,
    Value<int?>? lastSyncAt,
    Value<int?>? lastEpgAt,
    Value<int>? sortIndex,
  }) {
    return SourcesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      url: url ?? this.url,
      username: username ?? this.username,
      userAgent: userAgent ?? this.userAgent,
      referer: referer ?? this.referer,
      liveFormat: liveFormat ?? this.liveFormat,
      epgOffsetMin: epgOffsetMin ?? this.epgOffsetMin,
      engineLive: engineLive ?? this.engineLive,
      engineVod: engineVod ?? this.engineVod,
      accountStatus: accountStatus ?? this.accountStatus,
      expiresAt: expiresAt ?? this.expiresAt,
      maxConnections: maxConnections ?? this.maxConnections,
      allowedFormatsJson: allowedFormatsJson ?? this.allowedFormatsJson,
      generation: generation ?? this.generation,
      openGeneration: openGeneration ?? this.openGeneration,
      lastGeneration: lastGeneration ?? this.lastGeneration,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastEpgAt: lastEpgAt ?? this.lastEpgAt,
      sortIndex: sortIndex ?? this.sortIndex,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $SourcesTable.$converterkind.toSql(kind.value),
      );
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (userAgent.present) {
      map['user_agent'] = Variable<String>(userAgent.value);
    }
    if (referer.present) {
      map['referer'] = Variable<String>(referer.value);
    }
    if (liveFormat.present) {
      map['live_format'] = Variable<String>(
        $SourcesTable.$converterliveFormat.toSql(liveFormat.value),
      );
    }
    if (epgOffsetMin.present) {
      map['epg_offset_min'] = Variable<int>(epgOffsetMin.value);
    }
    if (engineLive.present) {
      map['engine_live'] = Variable<String>(
        $SourcesTable.$converterengineLiven.toSql(engineLive.value),
      );
    }
    if (engineVod.present) {
      map['engine_vod'] = Variable<String>(
        $SourcesTable.$converterengineVodn.toSql(engineVod.value),
      );
    }
    if (accountStatus.present) {
      map['account_status'] = Variable<String>(
        $SourcesTable.$converteraccountStatus.toSql(accountStatus.value),
      );
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
    }
    if (maxConnections.present) {
      map['max_connections'] = Variable<int>(maxConnections.value);
    }
    if (allowedFormatsJson.present) {
      map['allowed_formats_json'] = Variable<String>(allowedFormatsJson.value);
    }
    if (generation.present) {
      map['generation'] = Variable<int>(generation.value);
    }
    if (openGeneration.present) {
      map['open_generation'] = Variable<int>(openGeneration.value);
    }
    if (lastGeneration.present) {
      map['last_generation'] = Variable<int>(lastGeneration.value);
    }
    if (lastSyncAt.present) {
      map['last_sync_at'] = Variable<int>(lastSyncAt.value);
    }
    if (lastEpgAt.present) {
      map['last_epg_at'] = Variable<int>(lastEpgAt.value);
    }
    if (sortIndex.present) {
      map['sort_index'] = Variable<int>(sortIndex.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SourcesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('url: $url, ')
          ..write('username: $username, ')
          ..write('userAgent: $userAgent, ')
          ..write('referer: $referer, ')
          ..write('liveFormat: $liveFormat, ')
          ..write('epgOffsetMin: $epgOffsetMin, ')
          ..write('engineLive: $engineLive, ')
          ..write('engineVod: $engineVod, ')
          ..write('accountStatus: $accountStatus, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('maxConnections: $maxConnections, ')
          ..write('allowedFormatsJson: $allowedFormatsJson, ')
          ..write('generation: $generation, ')
          ..write('openGeneration: $openGeneration, ')
          ..write('lastGeneration: $lastGeneration, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('lastEpgAt: $lastEpgAt, ')
          ..write('sortIndex: $sortIndex')
          ..write(')'))
        .toString();
  }
}

class $SecretsTable extends Secrets
    with TableInfo<$SecretsTable, SecretRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SecretsTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sources (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [sourceId, name, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'secrets';
  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, name};
  @override
  SecretRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SecretRecord(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SecretsTable createAlias(String alias) {
    return $SecretsTable(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
}

class SecretRecord extends DataClass implements Insertable<SecretRecord> {
  final int sourceId;
  final String name;
  final String value;
  const SecretRecord({
    required this.sourceId,
    required this.name,
    required this.value,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<int>(sourceId);
    map['name'] = Variable<String>(name);
    map['value'] = Variable<String>(value);
    return map;
  }

  SecretsCompanion toCompanion(bool nullToAbsent) {
    return SecretsCompanion(
      sourceId: Value(sourceId),
      name: Value(name),
      value: Value(value),
    );
  }

  factory SecretRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SecretRecord(
      sourceId: serializer.fromJson<int>(json['sourceId']),
      name: serializer.fromJson<String>(json['name']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<int>(sourceId),
      'name': serializer.toJson<String>(name),
      'value': serializer.toJson<String>(value),
    };
  }

  SecretRecord copyWith({int? sourceId, String? name, String? value}) =>
      SecretRecord(
        sourceId: sourceId ?? this.sourceId,
        name: name ?? this.name,
        value: value ?? this.value,
      );
  SecretRecord copyWithCompanion(SecretsCompanion data) {
    return SecretRecord(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      name: data.name.present ? data.name.value : this.name,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SecretRecord(')
          ..write('sourceId: $sourceId, ')
          ..write('name: $name, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sourceId, name, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SecretRecord &&
          other.sourceId == this.sourceId &&
          other.name == this.name &&
          other.value == this.value);
}

class SecretsCompanion extends UpdateCompanion<SecretRecord> {
  final Value<int> sourceId;
  final Value<String> name;
  final Value<String> value;
  const SecretsCompanion({
    this.sourceId = const Value.absent(),
    this.name = const Value.absent(),
    this.value = const Value.absent(),
  });
  SecretsCompanion.insert({
    required int sourceId,
    required String name,
    required String value,
  }) : sourceId = Value(sourceId),
       name = Value(name),
       value = Value(value);
  static Insertable<SecretRecord> custom({
    Expression<int>? sourceId,
    Expression<String>? name,
    Expression<String>? value,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (name != null) 'name': name,
      if (value != null) 'value': value,
    });
  }

  SecretsCompanion copyWith({
    Value<int>? sourceId,
    Value<String>? name,
    Value<String>? value,
  }) {
    return SecretsCompanion(
      sourceId: sourceId ?? this.sourceId,
      name: name ?? this.name,
      value: value ?? this.value,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SecretsCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('name: $name, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, CategoryRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sources (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<ContentKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ContentKind>($CategoriesTable.$converterkind);
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> nameNorm = GeneratedColumn<String>(
    'name_norm',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> sortIndex = GeneratedColumn<int>(
    'sort_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumn<int> itemCount = GeneratedColumn<int>(
    'item_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumn<bool> hidden = GeneratedColumn<bool>(
    'hidden',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("hidden" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumn<int> generation = GeneratedColumn<int>(
    'generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> firstGen = GeneratedColumn<int>(
    'first_gen',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    kind,
    key,
    name,
    nameNorm,
    sortIndex,
    itemCount,
    hidden,
    generation,
    firstGen,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, kind, key};
  @override
  CategoryRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoryRecord(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_id'],
      )!,
      kind: $CategoriesTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameNorm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_norm'],
      )!,
      sortIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_index'],
      )!,
      itemCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}item_count'],
      )!,
      hidden: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}hidden'],
      )!,
      generation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generation'],
      )!,
      firstGen: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_gen'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ContentKind, String, String> $converterkind =
      const EnumNameConverter<ContentKind>(ContentKind.values);
}

class CategoryRecord extends DataClass implements Insertable<CategoryRecord> {
  final int sourceId;
  final ContentKind kind;
  final String key;
  final String name;
  final String nameNorm;
  final int sortIndex;

  /// Items in the committed generation; refreshed on commit.
  final int itemCount;

  /// User choice; kept across syncs while the category exists.
  final bool hidden;
  final int generation;

  /// Generation in which the row first appeared (abort removes only these).
  final int firstGen;
  const CategoryRecord({
    required this.sourceId,
    required this.kind,
    required this.key,
    required this.name,
    required this.nameNorm,
    required this.sortIndex,
    required this.itemCount,
    required this.hidden,
    required this.generation,
    required this.firstGen,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<int>(sourceId);
    {
      map['kind'] = Variable<String>(
        $CategoriesTable.$converterkind.toSql(kind),
      );
    }
    map['key'] = Variable<String>(key);
    map['name'] = Variable<String>(name);
    map['name_norm'] = Variable<String>(nameNorm);
    map['sort_index'] = Variable<int>(sortIndex);
    map['item_count'] = Variable<int>(itemCount);
    map['hidden'] = Variable<bool>(hidden);
    map['generation'] = Variable<int>(generation);
    map['first_gen'] = Variable<int>(firstGen);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      sourceId: Value(sourceId),
      kind: Value(kind),
      key: Value(key),
      name: Value(name),
      nameNorm: Value(nameNorm),
      sortIndex: Value(sortIndex),
      itemCount: Value(itemCount),
      hidden: Value(hidden),
      generation: Value(generation),
      firstGen: Value(firstGen),
    );
  }

  factory CategoryRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoryRecord(
      sourceId: serializer.fromJson<int>(json['sourceId']),
      kind: $CategoriesTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      key: serializer.fromJson<String>(json['key']),
      name: serializer.fromJson<String>(json['name']),
      nameNorm: serializer.fromJson<String>(json['nameNorm']),
      sortIndex: serializer.fromJson<int>(json['sortIndex']),
      itemCount: serializer.fromJson<int>(json['itemCount']),
      hidden: serializer.fromJson<bool>(json['hidden']),
      generation: serializer.fromJson<int>(json['generation']),
      firstGen: serializer.fromJson<int>(json['firstGen']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<int>(sourceId),
      'kind': serializer.toJson<String>(
        $CategoriesTable.$converterkind.toJson(kind),
      ),
      'key': serializer.toJson<String>(key),
      'name': serializer.toJson<String>(name),
      'nameNorm': serializer.toJson<String>(nameNorm),
      'sortIndex': serializer.toJson<int>(sortIndex),
      'itemCount': serializer.toJson<int>(itemCount),
      'hidden': serializer.toJson<bool>(hidden),
      'generation': serializer.toJson<int>(generation),
      'firstGen': serializer.toJson<int>(firstGen),
    };
  }

  CategoryRecord copyWith({
    int? sourceId,
    ContentKind? kind,
    String? key,
    String? name,
    String? nameNorm,
    int? sortIndex,
    int? itemCount,
    bool? hidden,
    int? generation,
    int? firstGen,
  }) => CategoryRecord(
    sourceId: sourceId ?? this.sourceId,
    kind: kind ?? this.kind,
    key: key ?? this.key,
    name: name ?? this.name,
    nameNorm: nameNorm ?? this.nameNorm,
    sortIndex: sortIndex ?? this.sortIndex,
    itemCount: itemCount ?? this.itemCount,
    hidden: hidden ?? this.hidden,
    generation: generation ?? this.generation,
    firstGen: firstGen ?? this.firstGen,
  );
  CategoryRecord copyWithCompanion(CategoriesCompanion data) {
    return CategoryRecord(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      kind: data.kind.present ? data.kind.value : this.kind,
      key: data.key.present ? data.key.value : this.key,
      name: data.name.present ? data.name.value : this.name,
      nameNorm: data.nameNorm.present ? data.nameNorm.value : this.nameNorm,
      sortIndex: data.sortIndex.present ? data.sortIndex.value : this.sortIndex,
      itemCount: data.itemCount.present ? data.itemCount.value : this.itemCount,
      hidden: data.hidden.present ? data.hidden.value : this.hidden,
      generation: data.generation.present
          ? data.generation.value
          : this.generation,
      firstGen: data.firstGen.present ? data.firstGen.value : this.firstGen,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryRecord(')
          ..write('sourceId: $sourceId, ')
          ..write('kind: $kind, ')
          ..write('key: $key, ')
          ..write('name: $name, ')
          ..write('nameNorm: $nameNorm, ')
          ..write('sortIndex: $sortIndex, ')
          ..write('itemCount: $itemCount, ')
          ..write('hidden: $hidden, ')
          ..write('generation: $generation, ')
          ..write('firstGen: $firstGen')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sourceId,
    kind,
    key,
    name,
    nameNorm,
    sortIndex,
    itemCount,
    hidden,
    generation,
    firstGen,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryRecord &&
          other.sourceId == this.sourceId &&
          other.kind == this.kind &&
          other.key == this.key &&
          other.name == this.name &&
          other.nameNorm == this.nameNorm &&
          other.sortIndex == this.sortIndex &&
          other.itemCount == this.itemCount &&
          other.hidden == this.hidden &&
          other.generation == this.generation &&
          other.firstGen == this.firstGen);
}

class CategoriesCompanion extends UpdateCompanion<CategoryRecord> {
  final Value<int> sourceId;
  final Value<ContentKind> kind;
  final Value<String> key;
  final Value<String> name;
  final Value<String> nameNorm;
  final Value<int> sortIndex;
  final Value<int> itemCount;
  final Value<bool> hidden;
  final Value<int> generation;
  final Value<int> firstGen;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.sourceId = const Value.absent(),
    this.kind = const Value.absent(),
    this.key = const Value.absent(),
    this.name = const Value.absent(),
    this.nameNorm = const Value.absent(),
    this.sortIndex = const Value.absent(),
    this.itemCount = const Value.absent(),
    this.hidden = const Value.absent(),
    this.generation = const Value.absent(),
    this.firstGen = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required int sourceId,
    required ContentKind kind,
    required String key,
    required String name,
    required String nameNorm,
    this.sortIndex = const Value.absent(),
    this.itemCount = const Value.absent(),
    this.hidden = const Value.absent(),
    required int generation,
    required int firstGen,
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId),
       kind = Value(kind),
       key = Value(key),
       name = Value(name),
       nameNorm = Value(nameNorm),
       generation = Value(generation),
       firstGen = Value(firstGen);
  static Insertable<CategoryRecord> custom({
    Expression<int>? sourceId,
    Expression<String>? kind,
    Expression<String>? key,
    Expression<String>? name,
    Expression<String>? nameNorm,
    Expression<int>? sortIndex,
    Expression<int>? itemCount,
    Expression<bool>? hidden,
    Expression<int>? generation,
    Expression<int>? firstGen,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (kind != null) 'kind': kind,
      if (key != null) 'key': key,
      if (name != null) 'name': name,
      if (nameNorm != null) 'name_norm': nameNorm,
      if (sortIndex != null) 'sort_index': sortIndex,
      if (itemCount != null) 'item_count': itemCount,
      if (hidden != null) 'hidden': hidden,
      if (generation != null) 'generation': generation,
      if (firstGen != null) 'first_gen': firstGen,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<int>? sourceId,
    Value<ContentKind>? kind,
    Value<String>? key,
    Value<String>? name,
    Value<String>? nameNorm,
    Value<int>? sortIndex,
    Value<int>? itemCount,
    Value<bool>? hidden,
    Value<int>? generation,
    Value<int>? firstGen,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      sourceId: sourceId ?? this.sourceId,
      kind: kind ?? this.kind,
      key: key ?? this.key,
      name: name ?? this.name,
      nameNorm: nameNorm ?? this.nameNorm,
      sortIndex: sortIndex ?? this.sortIndex,
      itemCount: itemCount ?? this.itemCount,
      hidden: hidden ?? this.hidden,
      generation: generation ?? this.generation,
      firstGen: firstGen ?? this.firstGen,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $CategoriesTable.$converterkind.toSql(kind.value),
      );
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameNorm.present) {
      map['name_norm'] = Variable<String>(nameNorm.value);
    }
    if (sortIndex.present) {
      map['sort_index'] = Variable<int>(sortIndex.value);
    }
    if (itemCount.present) {
      map['item_count'] = Variable<int>(itemCount.value);
    }
    if (hidden.present) {
      map['hidden'] = Variable<bool>(hidden.value);
    }
    if (generation.present) {
      map['generation'] = Variable<int>(generation.value);
    }
    if (firstGen.present) {
      map['first_gen'] = Variable<int>(firstGen.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('kind: $kind, ')
          ..write('key: $key, ')
          ..write('name: $name, ')
          ..write('nameNorm: $nameNorm, ')
          ..write('sortIndex: $sortIndex, ')
          ..write('itemCount: $itemCount, ')
          ..write('hidden: $hidden, ')
          ..write('generation: $generation, ')
          ..write('firstGen: $firstGen, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CategoryItemsTable extends CategoryItems
    with TableInfo<$CategoryItemsTable, CategoryItemRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoryItemsTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sources (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<int> generation = GeneratedColumn<int>(
    'generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ContentKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ContentKind>($CategoryItemsTable.$converterkind);
  @override
  late final GeneratedColumn<String> categoryKey = GeneratedColumn<String>(
    'category_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> itemKey = GeneratedColumn<String>(
    'item_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    generation,
    kind,
    categoryKey,
    position,
    itemKey,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'category_items';
  @override
  Set<GeneratedColumn> get $primaryKey => {
    sourceId,
    generation,
    kind,
    categoryKey,
    position,
  };
  @override
  CategoryItemRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoryItemRecord(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_id'],
      )!,
      generation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generation'],
      )!,
      kind: $CategoryItemsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      categoryKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_key'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      itemKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_key'],
      )!,
    );
  }

  @override
  $CategoryItemsTable createAlias(String alias) {
    return $CategoryItemsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ContentKind, String, String> $converterkind =
      const EnumNameConverter<ContentKind>(ContentKind.values);
  @override
  bool get withoutRowId => true;
}

class CategoryItemRecord extends DataClass
    implements Insertable<CategoryItemRecord> {
  final int sourceId;
  final int generation;
  final ContentKind kind;
  final String categoryKey;
  final int position;
  final String itemKey;
  const CategoryItemRecord({
    required this.sourceId,
    required this.generation,
    required this.kind,
    required this.categoryKey,
    required this.position,
    required this.itemKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<int>(sourceId);
    map['generation'] = Variable<int>(generation);
    {
      map['kind'] = Variable<String>(
        $CategoryItemsTable.$converterkind.toSql(kind),
      );
    }
    map['category_key'] = Variable<String>(categoryKey);
    map['position'] = Variable<int>(position);
    map['item_key'] = Variable<String>(itemKey);
    return map;
  }

  CategoryItemsCompanion toCompanion(bool nullToAbsent) {
    return CategoryItemsCompanion(
      sourceId: Value(sourceId),
      generation: Value(generation),
      kind: Value(kind),
      categoryKey: Value(categoryKey),
      position: Value(position),
      itemKey: Value(itemKey),
    );
  }

  factory CategoryItemRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoryItemRecord(
      sourceId: serializer.fromJson<int>(json['sourceId']),
      generation: serializer.fromJson<int>(json['generation']),
      kind: $CategoryItemsTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      categoryKey: serializer.fromJson<String>(json['categoryKey']),
      position: serializer.fromJson<int>(json['position']),
      itemKey: serializer.fromJson<String>(json['itemKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<int>(sourceId),
      'generation': serializer.toJson<int>(generation),
      'kind': serializer.toJson<String>(
        $CategoryItemsTable.$converterkind.toJson(kind),
      ),
      'categoryKey': serializer.toJson<String>(categoryKey),
      'position': serializer.toJson<int>(position),
      'itemKey': serializer.toJson<String>(itemKey),
    };
  }

  CategoryItemRecord copyWith({
    int? sourceId,
    int? generation,
    ContentKind? kind,
    String? categoryKey,
    int? position,
    String? itemKey,
  }) => CategoryItemRecord(
    sourceId: sourceId ?? this.sourceId,
    generation: generation ?? this.generation,
    kind: kind ?? this.kind,
    categoryKey: categoryKey ?? this.categoryKey,
    position: position ?? this.position,
    itemKey: itemKey ?? this.itemKey,
  );
  CategoryItemRecord copyWithCompanion(CategoryItemsCompanion data) {
    return CategoryItemRecord(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      generation: data.generation.present
          ? data.generation.value
          : this.generation,
      kind: data.kind.present ? data.kind.value : this.kind,
      categoryKey: data.categoryKey.present
          ? data.categoryKey.value
          : this.categoryKey,
      position: data.position.present ? data.position.value : this.position,
      itemKey: data.itemKey.present ? data.itemKey.value : this.itemKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryItemRecord(')
          ..write('sourceId: $sourceId, ')
          ..write('generation: $generation, ')
          ..write('kind: $kind, ')
          ..write('categoryKey: $categoryKey, ')
          ..write('position: $position, ')
          ..write('itemKey: $itemKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sourceId, generation, kind, categoryKey, position, itemKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryItemRecord &&
          other.sourceId == this.sourceId &&
          other.generation == this.generation &&
          other.kind == this.kind &&
          other.categoryKey == this.categoryKey &&
          other.position == this.position &&
          other.itemKey == this.itemKey);
}

class CategoryItemsCompanion extends UpdateCompanion<CategoryItemRecord> {
  final Value<int> sourceId;
  final Value<int> generation;
  final Value<ContentKind> kind;
  final Value<String> categoryKey;
  final Value<int> position;
  final Value<String> itemKey;
  const CategoryItemsCompanion({
    this.sourceId = const Value.absent(),
    this.generation = const Value.absent(),
    this.kind = const Value.absent(),
    this.categoryKey = const Value.absent(),
    this.position = const Value.absent(),
    this.itemKey = const Value.absent(),
  });
  CategoryItemsCompanion.insert({
    required int sourceId,
    required int generation,
    required ContentKind kind,
    required String categoryKey,
    required int position,
    required String itemKey,
  }) : sourceId = Value(sourceId),
       generation = Value(generation),
       kind = Value(kind),
       categoryKey = Value(categoryKey),
       position = Value(position),
       itemKey = Value(itemKey);
  static Insertable<CategoryItemRecord> custom({
    Expression<int>? sourceId,
    Expression<int>? generation,
    Expression<String>? kind,
    Expression<String>? categoryKey,
    Expression<int>? position,
    Expression<String>? itemKey,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (generation != null) 'generation': generation,
      if (kind != null) 'kind': kind,
      if (categoryKey != null) 'category_key': categoryKey,
      if (position != null) 'position': position,
      if (itemKey != null) 'item_key': itemKey,
    });
  }

  CategoryItemsCompanion copyWith({
    Value<int>? sourceId,
    Value<int>? generation,
    Value<ContentKind>? kind,
    Value<String>? categoryKey,
    Value<int>? position,
    Value<String>? itemKey,
  }) {
    return CategoryItemsCompanion(
      sourceId: sourceId ?? this.sourceId,
      generation: generation ?? this.generation,
      kind: kind ?? this.kind,
      categoryKey: categoryKey ?? this.categoryKey,
      position: position ?? this.position,
      itemKey: itemKey ?? this.itemKey,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (generation.present) {
      map['generation'] = Variable<int>(generation.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $CategoryItemsTable.$converterkind.toSql(kind.value),
      );
    }
    if (categoryKey.present) {
      map['category_key'] = Variable<String>(categoryKey.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (itemKey.present) {
      map['item_key'] = Variable<String>(itemKey.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoryItemsCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('generation: $generation, ')
          ..write('kind: $kind, ')
          ..write('categoryKey: $categoryKey, ')
          ..write('position: $position, ')
          ..write('itemKey: $itemKey')
          ..write(')'))
        .toString();
  }
}

class $ChannelsTable extends Channels
    with TableInfo<$ChannelsTable, ChannelRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChannelsTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sources (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> num = GeneratedColumn<int>(
    'num',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> nameNorm = GeneratedColumn<String>(
    'name_norm',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> logo = GeneratedColumn<String>(
    'logo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> tvgId = GeneratedColumn<String>(
    'tvg_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> tvgName = GeneratedColumn<String>(
    'tvg_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> headersJson = GeneratedColumn<String>(
    'headers_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<bool> isRadio = GeneratedColumn<bool>(
    'is_radio',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_radio" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumn<String> catchupMode = GeneratedColumn<String>(
    'catchup_mode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> catchupDays = GeneratedColumn<int>(
    'catchup_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumn<String> catchupSource = GeneratedColumn<String>(
    'catchup_source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> tvgShiftMin = GeneratedColumn<int>(
    'tvg_shift_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumn<int> generation = GeneratedColumn<int>(
    'generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> firstGen = GeneratedColumn<int>(
    'first_gen',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    key,
    num,
    name,
    nameNorm,
    logo,
    tvgId,
    tvgName,
    url,
    headersJson,
    isRadio,
    catchupMode,
    catchupDays,
    catchupSource,
    tvgShiftMin,
    generation,
    firstGen,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'channels';
  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, key};
  @override
  ChannelRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChannelRecord(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      num: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}num'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameNorm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_norm'],
      )!,
      logo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}logo'],
      ),
      tvgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tvg_id'],
      ),
      tvgName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tvg_name'],
      ),
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      ),
      headersJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}headers_json'],
      ),
      isRadio: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_radio'],
      )!,
      catchupMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}catchup_mode'],
      ),
      catchupDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}catchup_days'],
      )!,
      catchupSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}catchup_source'],
      ),
      tvgShiftMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tvg_shift_min'],
      )!,
      generation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generation'],
      )!,
      firstGen: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_gen'],
      )!,
    );
  }

  @override
  $ChannelsTable createAlias(String alias) {
    return $ChannelsTable(attachedDatabase, alias);
  }
}

class ChannelRecord extends DataClass implements Insertable<ChannelRecord> {
  final int sourceId;
  final String key;
  final int? num;
  final String name;
  final String nameNorm;
  final String? logo;
  final String? tvgId;
  final String? tvgName;

  /// M3U only; Xtream URLs are built at play time.
  final String? url;
  final String? headersJson;
  final bool isRadio;
  final String? catchupMode;
  final int catchupDays;
  final String? catchupSource;
  final int tvgShiftMin;
  final int generation;
  final int firstGen;
  const ChannelRecord({
    required this.sourceId,
    required this.key,
    this.num,
    required this.name,
    required this.nameNorm,
    this.logo,
    this.tvgId,
    this.tvgName,
    this.url,
    this.headersJson,
    required this.isRadio,
    this.catchupMode,
    required this.catchupDays,
    this.catchupSource,
    required this.tvgShiftMin,
    required this.generation,
    required this.firstGen,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<int>(sourceId);
    map['key'] = Variable<String>(key);
    if (!nullToAbsent || num != null) {
      map['num'] = Variable<int>(num);
    }
    map['name'] = Variable<String>(name);
    map['name_norm'] = Variable<String>(nameNorm);
    if (!nullToAbsent || logo != null) {
      map['logo'] = Variable<String>(logo);
    }
    if (!nullToAbsent || tvgId != null) {
      map['tvg_id'] = Variable<String>(tvgId);
    }
    if (!nullToAbsent || tvgName != null) {
      map['tvg_name'] = Variable<String>(tvgName);
    }
    if (!nullToAbsent || url != null) {
      map['url'] = Variable<String>(url);
    }
    if (!nullToAbsent || headersJson != null) {
      map['headers_json'] = Variable<String>(headersJson);
    }
    map['is_radio'] = Variable<bool>(isRadio);
    if (!nullToAbsent || catchupMode != null) {
      map['catchup_mode'] = Variable<String>(catchupMode);
    }
    map['catchup_days'] = Variable<int>(catchupDays);
    if (!nullToAbsent || catchupSource != null) {
      map['catchup_source'] = Variable<String>(catchupSource);
    }
    map['tvg_shift_min'] = Variable<int>(tvgShiftMin);
    map['generation'] = Variable<int>(generation);
    map['first_gen'] = Variable<int>(firstGen);
    return map;
  }

  ChannelsCompanion toCompanion(bool nullToAbsent) {
    return ChannelsCompanion(
      sourceId: Value(sourceId),
      key: Value(key),
      num: num == null && nullToAbsent ? const Value.absent() : Value(num),
      name: Value(name),
      nameNorm: Value(nameNorm),
      logo: logo == null && nullToAbsent ? const Value.absent() : Value(logo),
      tvgId: tvgId == null && nullToAbsent
          ? const Value.absent()
          : Value(tvgId),
      tvgName: tvgName == null && nullToAbsent
          ? const Value.absent()
          : Value(tvgName),
      url: url == null && nullToAbsent ? const Value.absent() : Value(url),
      headersJson: headersJson == null && nullToAbsent
          ? const Value.absent()
          : Value(headersJson),
      isRadio: Value(isRadio),
      catchupMode: catchupMode == null && nullToAbsent
          ? const Value.absent()
          : Value(catchupMode),
      catchupDays: Value(catchupDays),
      catchupSource: catchupSource == null && nullToAbsent
          ? const Value.absent()
          : Value(catchupSource),
      tvgShiftMin: Value(tvgShiftMin),
      generation: Value(generation),
      firstGen: Value(firstGen),
    );
  }

  factory ChannelRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChannelRecord(
      sourceId: serializer.fromJson<int>(json['sourceId']),
      key: serializer.fromJson<String>(json['key']),
      num: serializer.fromJson<int?>(json['num']),
      name: serializer.fromJson<String>(json['name']),
      nameNorm: serializer.fromJson<String>(json['nameNorm']),
      logo: serializer.fromJson<String?>(json['logo']),
      tvgId: serializer.fromJson<String?>(json['tvgId']),
      tvgName: serializer.fromJson<String?>(json['tvgName']),
      url: serializer.fromJson<String?>(json['url']),
      headersJson: serializer.fromJson<String?>(json['headersJson']),
      isRadio: serializer.fromJson<bool>(json['isRadio']),
      catchupMode: serializer.fromJson<String?>(json['catchupMode']),
      catchupDays: serializer.fromJson<int>(json['catchupDays']),
      catchupSource: serializer.fromJson<String?>(json['catchupSource']),
      tvgShiftMin: serializer.fromJson<int>(json['tvgShiftMin']),
      generation: serializer.fromJson<int>(json['generation']),
      firstGen: serializer.fromJson<int>(json['firstGen']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<int>(sourceId),
      'key': serializer.toJson<String>(key),
      'num': serializer.toJson<int?>(num),
      'name': serializer.toJson<String>(name),
      'nameNorm': serializer.toJson<String>(nameNorm),
      'logo': serializer.toJson<String?>(logo),
      'tvgId': serializer.toJson<String?>(tvgId),
      'tvgName': serializer.toJson<String?>(tvgName),
      'url': serializer.toJson<String?>(url),
      'headersJson': serializer.toJson<String?>(headersJson),
      'isRadio': serializer.toJson<bool>(isRadio),
      'catchupMode': serializer.toJson<String?>(catchupMode),
      'catchupDays': serializer.toJson<int>(catchupDays),
      'catchupSource': serializer.toJson<String?>(catchupSource),
      'tvgShiftMin': serializer.toJson<int>(tvgShiftMin),
      'generation': serializer.toJson<int>(generation),
      'firstGen': serializer.toJson<int>(firstGen),
    };
  }

  ChannelRecord copyWith({
    int? sourceId,
    String? key,
    Value<int?> num = const Value.absent(),
    String? name,
    String? nameNorm,
    Value<String?> logo = const Value.absent(),
    Value<String?> tvgId = const Value.absent(),
    Value<String?> tvgName = const Value.absent(),
    Value<String?> url = const Value.absent(),
    Value<String?> headersJson = const Value.absent(),
    bool? isRadio,
    Value<String?> catchupMode = const Value.absent(),
    int? catchupDays,
    Value<String?> catchupSource = const Value.absent(),
    int? tvgShiftMin,
    int? generation,
    int? firstGen,
  }) => ChannelRecord(
    sourceId: sourceId ?? this.sourceId,
    key: key ?? this.key,
    num: num.present ? num.value : this.num,
    name: name ?? this.name,
    nameNorm: nameNorm ?? this.nameNorm,
    logo: logo.present ? logo.value : this.logo,
    tvgId: tvgId.present ? tvgId.value : this.tvgId,
    tvgName: tvgName.present ? tvgName.value : this.tvgName,
    url: url.present ? url.value : this.url,
    headersJson: headersJson.present ? headersJson.value : this.headersJson,
    isRadio: isRadio ?? this.isRadio,
    catchupMode: catchupMode.present ? catchupMode.value : this.catchupMode,
    catchupDays: catchupDays ?? this.catchupDays,
    catchupSource: catchupSource.present
        ? catchupSource.value
        : this.catchupSource,
    tvgShiftMin: tvgShiftMin ?? this.tvgShiftMin,
    generation: generation ?? this.generation,
    firstGen: firstGen ?? this.firstGen,
  );
  ChannelRecord copyWithCompanion(ChannelsCompanion data) {
    return ChannelRecord(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      key: data.key.present ? data.key.value : this.key,
      num: data.num.present ? data.num.value : this.num,
      name: data.name.present ? data.name.value : this.name,
      nameNorm: data.nameNorm.present ? data.nameNorm.value : this.nameNorm,
      logo: data.logo.present ? data.logo.value : this.logo,
      tvgId: data.tvgId.present ? data.tvgId.value : this.tvgId,
      tvgName: data.tvgName.present ? data.tvgName.value : this.tvgName,
      url: data.url.present ? data.url.value : this.url,
      headersJson: data.headersJson.present
          ? data.headersJson.value
          : this.headersJson,
      isRadio: data.isRadio.present ? data.isRadio.value : this.isRadio,
      catchupMode: data.catchupMode.present
          ? data.catchupMode.value
          : this.catchupMode,
      catchupDays: data.catchupDays.present
          ? data.catchupDays.value
          : this.catchupDays,
      catchupSource: data.catchupSource.present
          ? data.catchupSource.value
          : this.catchupSource,
      tvgShiftMin: data.tvgShiftMin.present
          ? data.tvgShiftMin.value
          : this.tvgShiftMin,
      generation: data.generation.present
          ? data.generation.value
          : this.generation,
      firstGen: data.firstGen.present ? data.firstGen.value : this.firstGen,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChannelRecord(')
          ..write('sourceId: $sourceId, ')
          ..write('key: $key, ')
          ..write('num: $num, ')
          ..write('name: $name, ')
          ..write('nameNorm: $nameNorm, ')
          ..write('logo: $logo, ')
          ..write('tvgId: $tvgId, ')
          ..write('tvgName: $tvgName, ')
          ..write('url: $url, ')
          ..write('headersJson: $headersJson, ')
          ..write('isRadio: $isRadio, ')
          ..write('catchupMode: $catchupMode, ')
          ..write('catchupDays: $catchupDays, ')
          ..write('catchupSource: $catchupSource, ')
          ..write('tvgShiftMin: $tvgShiftMin, ')
          ..write('generation: $generation, ')
          ..write('firstGen: $firstGen')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sourceId,
    key,
    num,
    name,
    nameNorm,
    logo,
    tvgId,
    tvgName,
    url,
    headersJson,
    isRadio,
    catchupMode,
    catchupDays,
    catchupSource,
    tvgShiftMin,
    generation,
    firstGen,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChannelRecord &&
          other.sourceId == this.sourceId &&
          other.key == this.key &&
          other.num == this.num &&
          other.name == this.name &&
          other.nameNorm == this.nameNorm &&
          other.logo == this.logo &&
          other.tvgId == this.tvgId &&
          other.tvgName == this.tvgName &&
          other.url == this.url &&
          other.headersJson == this.headersJson &&
          other.isRadio == this.isRadio &&
          other.catchupMode == this.catchupMode &&
          other.catchupDays == this.catchupDays &&
          other.catchupSource == this.catchupSource &&
          other.tvgShiftMin == this.tvgShiftMin &&
          other.generation == this.generation &&
          other.firstGen == this.firstGen);
}

class ChannelsCompanion extends UpdateCompanion<ChannelRecord> {
  final Value<int> sourceId;
  final Value<String> key;
  final Value<int?> num;
  final Value<String> name;
  final Value<String> nameNorm;
  final Value<String?> logo;
  final Value<String?> tvgId;
  final Value<String?> tvgName;
  final Value<String?> url;
  final Value<String?> headersJson;
  final Value<bool> isRadio;
  final Value<String?> catchupMode;
  final Value<int> catchupDays;
  final Value<String?> catchupSource;
  final Value<int> tvgShiftMin;
  final Value<int> generation;
  final Value<int> firstGen;
  final Value<int> rowid;
  const ChannelsCompanion({
    this.sourceId = const Value.absent(),
    this.key = const Value.absent(),
    this.num = const Value.absent(),
    this.name = const Value.absent(),
    this.nameNorm = const Value.absent(),
    this.logo = const Value.absent(),
    this.tvgId = const Value.absent(),
    this.tvgName = const Value.absent(),
    this.url = const Value.absent(),
    this.headersJson = const Value.absent(),
    this.isRadio = const Value.absent(),
    this.catchupMode = const Value.absent(),
    this.catchupDays = const Value.absent(),
    this.catchupSource = const Value.absent(),
    this.tvgShiftMin = const Value.absent(),
    this.generation = const Value.absent(),
    this.firstGen = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChannelsCompanion.insert({
    required int sourceId,
    required String key,
    this.num = const Value.absent(),
    required String name,
    required String nameNorm,
    this.logo = const Value.absent(),
    this.tvgId = const Value.absent(),
    this.tvgName = const Value.absent(),
    this.url = const Value.absent(),
    this.headersJson = const Value.absent(),
    this.isRadio = const Value.absent(),
    this.catchupMode = const Value.absent(),
    this.catchupDays = const Value.absent(),
    this.catchupSource = const Value.absent(),
    this.tvgShiftMin = const Value.absent(),
    required int generation,
    required int firstGen,
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId),
       key = Value(key),
       name = Value(name),
       nameNorm = Value(nameNorm),
       generation = Value(generation),
       firstGen = Value(firstGen);
  static Insertable<ChannelRecord> custom({
    Expression<int>? sourceId,
    Expression<String>? key,
    Expression<int>? num,
    Expression<String>? name,
    Expression<String>? nameNorm,
    Expression<String>? logo,
    Expression<String>? tvgId,
    Expression<String>? tvgName,
    Expression<String>? url,
    Expression<String>? headersJson,
    Expression<bool>? isRadio,
    Expression<String>? catchupMode,
    Expression<int>? catchupDays,
    Expression<String>? catchupSource,
    Expression<int>? tvgShiftMin,
    Expression<int>? generation,
    Expression<int>? firstGen,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (key != null) 'key': key,
      if (num != null) 'num': num,
      if (name != null) 'name': name,
      if (nameNorm != null) 'name_norm': nameNorm,
      if (logo != null) 'logo': logo,
      if (tvgId != null) 'tvg_id': tvgId,
      if (tvgName != null) 'tvg_name': tvgName,
      if (url != null) 'url': url,
      if (headersJson != null) 'headers_json': headersJson,
      if (isRadio != null) 'is_radio': isRadio,
      if (catchupMode != null) 'catchup_mode': catchupMode,
      if (catchupDays != null) 'catchup_days': catchupDays,
      if (catchupSource != null) 'catchup_source': catchupSource,
      if (tvgShiftMin != null) 'tvg_shift_min': tvgShiftMin,
      if (generation != null) 'generation': generation,
      if (firstGen != null) 'first_gen': firstGen,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChannelsCompanion copyWith({
    Value<int>? sourceId,
    Value<String>? key,
    Value<int?>? num,
    Value<String>? name,
    Value<String>? nameNorm,
    Value<String?>? logo,
    Value<String?>? tvgId,
    Value<String?>? tvgName,
    Value<String?>? url,
    Value<String?>? headersJson,
    Value<bool>? isRadio,
    Value<String?>? catchupMode,
    Value<int>? catchupDays,
    Value<String?>? catchupSource,
    Value<int>? tvgShiftMin,
    Value<int>? generation,
    Value<int>? firstGen,
    Value<int>? rowid,
  }) {
    return ChannelsCompanion(
      sourceId: sourceId ?? this.sourceId,
      key: key ?? this.key,
      num: num ?? this.num,
      name: name ?? this.name,
      nameNorm: nameNorm ?? this.nameNorm,
      logo: logo ?? this.logo,
      tvgId: tvgId ?? this.tvgId,
      tvgName: tvgName ?? this.tvgName,
      url: url ?? this.url,
      headersJson: headersJson ?? this.headersJson,
      isRadio: isRadio ?? this.isRadio,
      catchupMode: catchupMode ?? this.catchupMode,
      catchupDays: catchupDays ?? this.catchupDays,
      catchupSource: catchupSource ?? this.catchupSource,
      tvgShiftMin: tvgShiftMin ?? this.tvgShiftMin,
      generation: generation ?? this.generation,
      firstGen: firstGen ?? this.firstGen,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (num.present) {
      map['num'] = Variable<int>(num.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameNorm.present) {
      map['name_norm'] = Variable<String>(nameNorm.value);
    }
    if (logo.present) {
      map['logo'] = Variable<String>(logo.value);
    }
    if (tvgId.present) {
      map['tvg_id'] = Variable<String>(tvgId.value);
    }
    if (tvgName.present) {
      map['tvg_name'] = Variable<String>(tvgName.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (headersJson.present) {
      map['headers_json'] = Variable<String>(headersJson.value);
    }
    if (isRadio.present) {
      map['is_radio'] = Variable<bool>(isRadio.value);
    }
    if (catchupMode.present) {
      map['catchup_mode'] = Variable<String>(catchupMode.value);
    }
    if (catchupDays.present) {
      map['catchup_days'] = Variable<int>(catchupDays.value);
    }
    if (catchupSource.present) {
      map['catchup_source'] = Variable<String>(catchupSource.value);
    }
    if (tvgShiftMin.present) {
      map['tvg_shift_min'] = Variable<int>(tvgShiftMin.value);
    }
    if (generation.present) {
      map['generation'] = Variable<int>(generation.value);
    }
    if (firstGen.present) {
      map['first_gen'] = Variable<int>(firstGen.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChannelsCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('key: $key, ')
          ..write('num: $num, ')
          ..write('name: $name, ')
          ..write('nameNorm: $nameNorm, ')
          ..write('logo: $logo, ')
          ..write('tvgId: $tvgId, ')
          ..write('tvgName: $tvgName, ')
          ..write('url: $url, ')
          ..write('headersJson: $headersJson, ')
          ..write('isRadio: $isRadio, ')
          ..write('catchupMode: $catchupMode, ')
          ..write('catchupDays: $catchupDays, ')
          ..write('catchupSource: $catchupSource, ')
          ..write('tvgShiftMin: $tvgShiftMin, ')
          ..write('generation: $generation, ')
          ..write('firstGen: $firstGen, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MoviesTable extends Movies with TableInfo<$MoviesTable, MovieRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MoviesTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sources (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> nameNorm = GeneratedColumn<String>(
    'name_norm',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> poster = GeneratedColumn<String>(
    'poster',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<double> rating = GeneratedColumn<double>(
    'rating',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> ext = GeneratedColumn<String>(
    'ext',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> headersJson = GeneratedColumn<String>(
    'headers_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> generation = GeneratedColumn<int>(
    'generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> firstGen = GeneratedColumn<int>(
    'first_gen',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    key,
    name,
    nameNorm,
    poster,
    year,
    rating,
    ext,
    url,
    headersJson,
    addedAt,
    generation,
    firstGen,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'movies';
  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, key};
  @override
  MovieRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MovieRecord(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameNorm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_norm'],
      )!,
      poster: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poster'],
      ),
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      ),
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}rating'],
      ),
      ext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ext'],
      ),
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      ),
      headersJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}headers_json'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      ),
      generation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generation'],
      )!,
      firstGen: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_gen'],
      )!,
    );
  }

  @override
  $MoviesTable createAlias(String alias) {
    return $MoviesTable(attachedDatabase, alias);
  }
}

class MovieRecord extends DataClass implements Insertable<MovieRecord> {
  final int sourceId;
  final String key;
  final String name;
  final String nameNorm;
  final String? poster;
  final int? year;
  final double? rating;
  final String? ext;
  final String? url;
  final String? headersJson;
  final int? addedAt;
  final int generation;
  final int firstGen;
  const MovieRecord({
    required this.sourceId,
    required this.key,
    required this.name,
    required this.nameNorm,
    this.poster,
    this.year,
    this.rating,
    this.ext,
    this.url,
    this.headersJson,
    this.addedAt,
    required this.generation,
    required this.firstGen,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<int>(sourceId);
    map['key'] = Variable<String>(key);
    map['name'] = Variable<String>(name);
    map['name_norm'] = Variable<String>(nameNorm);
    if (!nullToAbsent || poster != null) {
      map['poster'] = Variable<String>(poster);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    if (!nullToAbsent || rating != null) {
      map['rating'] = Variable<double>(rating);
    }
    if (!nullToAbsent || ext != null) {
      map['ext'] = Variable<String>(ext);
    }
    if (!nullToAbsent || url != null) {
      map['url'] = Variable<String>(url);
    }
    if (!nullToAbsent || headersJson != null) {
      map['headers_json'] = Variable<String>(headersJson);
    }
    if (!nullToAbsent || addedAt != null) {
      map['added_at'] = Variable<int>(addedAt);
    }
    map['generation'] = Variable<int>(generation);
    map['first_gen'] = Variable<int>(firstGen);
    return map;
  }

  MoviesCompanion toCompanion(bool nullToAbsent) {
    return MoviesCompanion(
      sourceId: Value(sourceId),
      key: Value(key),
      name: Value(name),
      nameNorm: Value(nameNorm),
      poster: poster == null && nullToAbsent
          ? const Value.absent()
          : Value(poster),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      rating: rating == null && nullToAbsent
          ? const Value.absent()
          : Value(rating),
      ext: ext == null && nullToAbsent ? const Value.absent() : Value(ext),
      url: url == null && nullToAbsent ? const Value.absent() : Value(url),
      headersJson: headersJson == null && nullToAbsent
          ? const Value.absent()
          : Value(headersJson),
      addedAt: addedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(addedAt),
      generation: Value(generation),
      firstGen: Value(firstGen),
    );
  }

  factory MovieRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MovieRecord(
      sourceId: serializer.fromJson<int>(json['sourceId']),
      key: serializer.fromJson<String>(json['key']),
      name: serializer.fromJson<String>(json['name']),
      nameNorm: serializer.fromJson<String>(json['nameNorm']),
      poster: serializer.fromJson<String?>(json['poster']),
      year: serializer.fromJson<int?>(json['year']),
      rating: serializer.fromJson<double?>(json['rating']),
      ext: serializer.fromJson<String?>(json['ext']),
      url: serializer.fromJson<String?>(json['url']),
      headersJson: serializer.fromJson<String?>(json['headersJson']),
      addedAt: serializer.fromJson<int?>(json['addedAt']),
      generation: serializer.fromJson<int>(json['generation']),
      firstGen: serializer.fromJson<int>(json['firstGen']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<int>(sourceId),
      'key': serializer.toJson<String>(key),
      'name': serializer.toJson<String>(name),
      'nameNorm': serializer.toJson<String>(nameNorm),
      'poster': serializer.toJson<String?>(poster),
      'year': serializer.toJson<int?>(year),
      'rating': serializer.toJson<double?>(rating),
      'ext': serializer.toJson<String?>(ext),
      'url': serializer.toJson<String?>(url),
      'headersJson': serializer.toJson<String?>(headersJson),
      'addedAt': serializer.toJson<int?>(addedAt),
      'generation': serializer.toJson<int>(generation),
      'firstGen': serializer.toJson<int>(firstGen),
    };
  }

  MovieRecord copyWith({
    int? sourceId,
    String? key,
    String? name,
    String? nameNorm,
    Value<String?> poster = const Value.absent(),
    Value<int?> year = const Value.absent(),
    Value<double?> rating = const Value.absent(),
    Value<String?> ext = const Value.absent(),
    Value<String?> url = const Value.absent(),
    Value<String?> headersJson = const Value.absent(),
    Value<int?> addedAt = const Value.absent(),
    int? generation,
    int? firstGen,
  }) => MovieRecord(
    sourceId: sourceId ?? this.sourceId,
    key: key ?? this.key,
    name: name ?? this.name,
    nameNorm: nameNorm ?? this.nameNorm,
    poster: poster.present ? poster.value : this.poster,
    year: year.present ? year.value : this.year,
    rating: rating.present ? rating.value : this.rating,
    ext: ext.present ? ext.value : this.ext,
    url: url.present ? url.value : this.url,
    headersJson: headersJson.present ? headersJson.value : this.headersJson,
    addedAt: addedAt.present ? addedAt.value : this.addedAt,
    generation: generation ?? this.generation,
    firstGen: firstGen ?? this.firstGen,
  );
  MovieRecord copyWithCompanion(MoviesCompanion data) {
    return MovieRecord(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      key: data.key.present ? data.key.value : this.key,
      name: data.name.present ? data.name.value : this.name,
      nameNorm: data.nameNorm.present ? data.nameNorm.value : this.nameNorm,
      poster: data.poster.present ? data.poster.value : this.poster,
      year: data.year.present ? data.year.value : this.year,
      rating: data.rating.present ? data.rating.value : this.rating,
      ext: data.ext.present ? data.ext.value : this.ext,
      url: data.url.present ? data.url.value : this.url,
      headersJson: data.headersJson.present
          ? data.headersJson.value
          : this.headersJson,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      generation: data.generation.present
          ? data.generation.value
          : this.generation,
      firstGen: data.firstGen.present ? data.firstGen.value : this.firstGen,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MovieRecord(')
          ..write('sourceId: $sourceId, ')
          ..write('key: $key, ')
          ..write('name: $name, ')
          ..write('nameNorm: $nameNorm, ')
          ..write('poster: $poster, ')
          ..write('year: $year, ')
          ..write('rating: $rating, ')
          ..write('ext: $ext, ')
          ..write('url: $url, ')
          ..write('headersJson: $headersJson, ')
          ..write('addedAt: $addedAt, ')
          ..write('generation: $generation, ')
          ..write('firstGen: $firstGen')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sourceId,
    key,
    name,
    nameNorm,
    poster,
    year,
    rating,
    ext,
    url,
    headersJson,
    addedAt,
    generation,
    firstGen,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MovieRecord &&
          other.sourceId == this.sourceId &&
          other.key == this.key &&
          other.name == this.name &&
          other.nameNorm == this.nameNorm &&
          other.poster == this.poster &&
          other.year == this.year &&
          other.rating == this.rating &&
          other.ext == this.ext &&
          other.url == this.url &&
          other.headersJson == this.headersJson &&
          other.addedAt == this.addedAt &&
          other.generation == this.generation &&
          other.firstGen == this.firstGen);
}

class MoviesCompanion extends UpdateCompanion<MovieRecord> {
  final Value<int> sourceId;
  final Value<String> key;
  final Value<String> name;
  final Value<String> nameNorm;
  final Value<String?> poster;
  final Value<int?> year;
  final Value<double?> rating;
  final Value<String?> ext;
  final Value<String?> url;
  final Value<String?> headersJson;
  final Value<int?> addedAt;
  final Value<int> generation;
  final Value<int> firstGen;
  final Value<int> rowid;
  const MoviesCompanion({
    this.sourceId = const Value.absent(),
    this.key = const Value.absent(),
    this.name = const Value.absent(),
    this.nameNorm = const Value.absent(),
    this.poster = const Value.absent(),
    this.year = const Value.absent(),
    this.rating = const Value.absent(),
    this.ext = const Value.absent(),
    this.url = const Value.absent(),
    this.headersJson = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.generation = const Value.absent(),
    this.firstGen = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MoviesCompanion.insert({
    required int sourceId,
    required String key,
    required String name,
    required String nameNorm,
    this.poster = const Value.absent(),
    this.year = const Value.absent(),
    this.rating = const Value.absent(),
    this.ext = const Value.absent(),
    this.url = const Value.absent(),
    this.headersJson = const Value.absent(),
    this.addedAt = const Value.absent(),
    required int generation,
    required int firstGen,
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId),
       key = Value(key),
       name = Value(name),
       nameNorm = Value(nameNorm),
       generation = Value(generation),
       firstGen = Value(firstGen);
  static Insertable<MovieRecord> custom({
    Expression<int>? sourceId,
    Expression<String>? key,
    Expression<String>? name,
    Expression<String>? nameNorm,
    Expression<String>? poster,
    Expression<int>? year,
    Expression<double>? rating,
    Expression<String>? ext,
    Expression<String>? url,
    Expression<String>? headersJson,
    Expression<int>? addedAt,
    Expression<int>? generation,
    Expression<int>? firstGen,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (key != null) 'key': key,
      if (name != null) 'name': name,
      if (nameNorm != null) 'name_norm': nameNorm,
      if (poster != null) 'poster': poster,
      if (year != null) 'year': year,
      if (rating != null) 'rating': rating,
      if (ext != null) 'ext': ext,
      if (url != null) 'url': url,
      if (headersJson != null) 'headers_json': headersJson,
      if (addedAt != null) 'added_at': addedAt,
      if (generation != null) 'generation': generation,
      if (firstGen != null) 'first_gen': firstGen,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MoviesCompanion copyWith({
    Value<int>? sourceId,
    Value<String>? key,
    Value<String>? name,
    Value<String>? nameNorm,
    Value<String?>? poster,
    Value<int?>? year,
    Value<double?>? rating,
    Value<String?>? ext,
    Value<String?>? url,
    Value<String?>? headersJson,
    Value<int?>? addedAt,
    Value<int>? generation,
    Value<int>? firstGen,
    Value<int>? rowid,
  }) {
    return MoviesCompanion(
      sourceId: sourceId ?? this.sourceId,
      key: key ?? this.key,
      name: name ?? this.name,
      nameNorm: nameNorm ?? this.nameNorm,
      poster: poster ?? this.poster,
      year: year ?? this.year,
      rating: rating ?? this.rating,
      ext: ext ?? this.ext,
      url: url ?? this.url,
      headersJson: headersJson ?? this.headersJson,
      addedAt: addedAt ?? this.addedAt,
      generation: generation ?? this.generation,
      firstGen: firstGen ?? this.firstGen,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameNorm.present) {
      map['name_norm'] = Variable<String>(nameNorm.value);
    }
    if (poster.present) {
      map['poster'] = Variable<String>(poster.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (rating.present) {
      map['rating'] = Variable<double>(rating.value);
    }
    if (ext.present) {
      map['ext'] = Variable<String>(ext.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (headersJson.present) {
      map['headers_json'] = Variable<String>(headersJson.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (generation.present) {
      map['generation'] = Variable<int>(generation.value);
    }
    if (firstGen.present) {
      map['first_gen'] = Variable<int>(firstGen.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MoviesCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('key: $key, ')
          ..write('name: $name, ')
          ..write('nameNorm: $nameNorm, ')
          ..write('poster: $poster, ')
          ..write('year: $year, ')
          ..write('rating: $rating, ')
          ..write('ext: $ext, ')
          ..write('url: $url, ')
          ..write('headersJson: $headersJson, ')
          ..write('addedAt: $addedAt, ')
          ..write('generation: $generation, ')
          ..write('firstGen: $firstGen, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SeriesTable extends Series with TableInfo<$SeriesTable, SeriesRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeriesTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sources (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> nameNorm = GeneratedColumn<String>(
    'name_norm',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> poster = GeneratedColumn<String>(
    'poster',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<double> rating = GeneratedColumn<double>(
    'rating',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> plot = GeneratedColumn<String>(
    'plot',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> generation = GeneratedColumn<int>(
    'generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> firstGen = GeneratedColumn<int>(
    'first_gen',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    key,
    name,
    nameNorm,
    poster,
    year,
    rating,
    plot,
    generation,
    firstGen,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'series';
  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, key};
  @override
  SeriesRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SeriesRecord(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameNorm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_norm'],
      )!,
      poster: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poster'],
      ),
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      ),
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}rating'],
      ),
      plot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plot'],
      ),
      generation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generation'],
      )!,
      firstGen: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_gen'],
      )!,
    );
  }

  @override
  $SeriesTable createAlias(String alias) {
    return $SeriesTable(attachedDatabase, alias);
  }
}

class SeriesRecord extends DataClass implements Insertable<SeriesRecord> {
  final int sourceId;
  final String key;
  final String name;
  final String nameNorm;
  final String? poster;
  final int? year;
  final double? rating;
  final String? plot;
  final int generation;
  final int firstGen;
  const SeriesRecord({
    required this.sourceId,
    required this.key,
    required this.name,
    required this.nameNorm,
    this.poster,
    this.year,
    this.rating,
    this.plot,
    required this.generation,
    required this.firstGen,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<int>(sourceId);
    map['key'] = Variable<String>(key);
    map['name'] = Variable<String>(name);
    map['name_norm'] = Variable<String>(nameNorm);
    if (!nullToAbsent || poster != null) {
      map['poster'] = Variable<String>(poster);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    if (!nullToAbsent || rating != null) {
      map['rating'] = Variable<double>(rating);
    }
    if (!nullToAbsent || plot != null) {
      map['plot'] = Variable<String>(plot);
    }
    map['generation'] = Variable<int>(generation);
    map['first_gen'] = Variable<int>(firstGen);
    return map;
  }

  SeriesCompanion toCompanion(bool nullToAbsent) {
    return SeriesCompanion(
      sourceId: Value(sourceId),
      key: Value(key),
      name: Value(name),
      nameNorm: Value(nameNorm),
      poster: poster == null && nullToAbsent
          ? const Value.absent()
          : Value(poster),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      rating: rating == null && nullToAbsent
          ? const Value.absent()
          : Value(rating),
      plot: plot == null && nullToAbsent ? const Value.absent() : Value(plot),
      generation: Value(generation),
      firstGen: Value(firstGen),
    );
  }

  factory SeriesRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SeriesRecord(
      sourceId: serializer.fromJson<int>(json['sourceId']),
      key: serializer.fromJson<String>(json['key']),
      name: serializer.fromJson<String>(json['name']),
      nameNorm: serializer.fromJson<String>(json['nameNorm']),
      poster: serializer.fromJson<String?>(json['poster']),
      year: serializer.fromJson<int?>(json['year']),
      rating: serializer.fromJson<double?>(json['rating']),
      plot: serializer.fromJson<String?>(json['plot']),
      generation: serializer.fromJson<int>(json['generation']),
      firstGen: serializer.fromJson<int>(json['firstGen']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<int>(sourceId),
      'key': serializer.toJson<String>(key),
      'name': serializer.toJson<String>(name),
      'nameNorm': serializer.toJson<String>(nameNorm),
      'poster': serializer.toJson<String?>(poster),
      'year': serializer.toJson<int?>(year),
      'rating': serializer.toJson<double?>(rating),
      'plot': serializer.toJson<String?>(plot),
      'generation': serializer.toJson<int>(generation),
      'firstGen': serializer.toJson<int>(firstGen),
    };
  }

  SeriesRecord copyWith({
    int? sourceId,
    String? key,
    String? name,
    String? nameNorm,
    Value<String?> poster = const Value.absent(),
    Value<int?> year = const Value.absent(),
    Value<double?> rating = const Value.absent(),
    Value<String?> plot = const Value.absent(),
    int? generation,
    int? firstGen,
  }) => SeriesRecord(
    sourceId: sourceId ?? this.sourceId,
    key: key ?? this.key,
    name: name ?? this.name,
    nameNorm: nameNorm ?? this.nameNorm,
    poster: poster.present ? poster.value : this.poster,
    year: year.present ? year.value : this.year,
    rating: rating.present ? rating.value : this.rating,
    plot: plot.present ? plot.value : this.plot,
    generation: generation ?? this.generation,
    firstGen: firstGen ?? this.firstGen,
  );
  SeriesRecord copyWithCompanion(SeriesCompanion data) {
    return SeriesRecord(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      key: data.key.present ? data.key.value : this.key,
      name: data.name.present ? data.name.value : this.name,
      nameNorm: data.nameNorm.present ? data.nameNorm.value : this.nameNorm,
      poster: data.poster.present ? data.poster.value : this.poster,
      year: data.year.present ? data.year.value : this.year,
      rating: data.rating.present ? data.rating.value : this.rating,
      plot: data.plot.present ? data.plot.value : this.plot,
      generation: data.generation.present
          ? data.generation.value
          : this.generation,
      firstGen: data.firstGen.present ? data.firstGen.value : this.firstGen,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SeriesRecord(')
          ..write('sourceId: $sourceId, ')
          ..write('key: $key, ')
          ..write('name: $name, ')
          ..write('nameNorm: $nameNorm, ')
          ..write('poster: $poster, ')
          ..write('year: $year, ')
          ..write('rating: $rating, ')
          ..write('plot: $plot, ')
          ..write('generation: $generation, ')
          ..write('firstGen: $firstGen')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sourceId,
    key,
    name,
    nameNorm,
    poster,
    year,
    rating,
    plot,
    generation,
    firstGen,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeriesRecord &&
          other.sourceId == this.sourceId &&
          other.key == this.key &&
          other.name == this.name &&
          other.nameNorm == this.nameNorm &&
          other.poster == this.poster &&
          other.year == this.year &&
          other.rating == this.rating &&
          other.plot == this.plot &&
          other.generation == this.generation &&
          other.firstGen == this.firstGen);
}

class SeriesCompanion extends UpdateCompanion<SeriesRecord> {
  final Value<int> sourceId;
  final Value<String> key;
  final Value<String> name;
  final Value<String> nameNorm;
  final Value<String?> poster;
  final Value<int?> year;
  final Value<double?> rating;
  final Value<String?> plot;
  final Value<int> generation;
  final Value<int> firstGen;
  final Value<int> rowid;
  const SeriesCompanion({
    this.sourceId = const Value.absent(),
    this.key = const Value.absent(),
    this.name = const Value.absent(),
    this.nameNorm = const Value.absent(),
    this.poster = const Value.absent(),
    this.year = const Value.absent(),
    this.rating = const Value.absent(),
    this.plot = const Value.absent(),
    this.generation = const Value.absent(),
    this.firstGen = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SeriesCompanion.insert({
    required int sourceId,
    required String key,
    required String name,
    required String nameNorm,
    this.poster = const Value.absent(),
    this.year = const Value.absent(),
    this.rating = const Value.absent(),
    this.plot = const Value.absent(),
    required int generation,
    required int firstGen,
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId),
       key = Value(key),
       name = Value(name),
       nameNorm = Value(nameNorm),
       generation = Value(generation),
       firstGen = Value(firstGen);
  static Insertable<SeriesRecord> custom({
    Expression<int>? sourceId,
    Expression<String>? key,
    Expression<String>? name,
    Expression<String>? nameNorm,
    Expression<String>? poster,
    Expression<int>? year,
    Expression<double>? rating,
    Expression<String>? plot,
    Expression<int>? generation,
    Expression<int>? firstGen,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (key != null) 'key': key,
      if (name != null) 'name': name,
      if (nameNorm != null) 'name_norm': nameNorm,
      if (poster != null) 'poster': poster,
      if (year != null) 'year': year,
      if (rating != null) 'rating': rating,
      if (plot != null) 'plot': plot,
      if (generation != null) 'generation': generation,
      if (firstGen != null) 'first_gen': firstGen,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SeriesCompanion copyWith({
    Value<int>? sourceId,
    Value<String>? key,
    Value<String>? name,
    Value<String>? nameNorm,
    Value<String?>? poster,
    Value<int?>? year,
    Value<double?>? rating,
    Value<String?>? plot,
    Value<int>? generation,
    Value<int>? firstGen,
    Value<int>? rowid,
  }) {
    return SeriesCompanion(
      sourceId: sourceId ?? this.sourceId,
      key: key ?? this.key,
      name: name ?? this.name,
      nameNorm: nameNorm ?? this.nameNorm,
      poster: poster ?? this.poster,
      year: year ?? this.year,
      rating: rating ?? this.rating,
      plot: plot ?? this.plot,
      generation: generation ?? this.generation,
      firstGen: firstGen ?? this.firstGen,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameNorm.present) {
      map['name_norm'] = Variable<String>(nameNorm.value);
    }
    if (poster.present) {
      map['poster'] = Variable<String>(poster.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (rating.present) {
      map['rating'] = Variable<double>(rating.value);
    }
    if (plot.present) {
      map['plot'] = Variable<String>(plot.value);
    }
    if (generation.present) {
      map['generation'] = Variable<int>(generation.value);
    }
    if (firstGen.present) {
      map['first_gen'] = Variable<int>(firstGen.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeriesCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('key: $key, ')
          ..write('name: $name, ')
          ..write('nameNorm: $nameNorm, ')
          ..write('poster: $poster, ')
          ..write('year: $year, ')
          ..write('rating: $rating, ')
          ..write('plot: $plot, ')
          ..write('generation: $generation, ')
          ..write('firstGen: $firstGen, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EpisodesTable extends Episodes
    with TableInfo<$EpisodesTable, EpisodeRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EpisodesTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sources (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> seriesKey = GeneratedColumn<String>(
    'series_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> season = GeneratedColumn<int>(
    'season',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> ext = GeneratedColumn<String>(
    'ext',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> headersJson = GeneratedColumn<String>(
    'headers_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> durationSec = GeneratedColumn<int>(
    'duration_sec',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> plot = GeneratedColumn<String>(
    'plot',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> still = GeneratedColumn<String>(
    'still',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> generation = GeneratedColumn<int>(
    'generation',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> firstGen = GeneratedColumn<int>(
    'first_gen',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    seriesKey,
    key,
    season,
    number,
    title,
    ext,
    url,
    headersJson,
    durationSec,
    plot,
    still,
    generation,
    firstGen,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'episodes';
  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, key};
  @override
  EpisodeRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EpisodeRecord(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_id'],
      )!,
      seriesKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_key'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      season: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      ext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ext'],
      ),
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      ),
      headersJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}headers_json'],
      ),
      durationSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_sec'],
      ),
      plot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plot'],
      ),
      still: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}still'],
      ),
      generation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generation'],
      ),
      firstGen: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_gen'],
      ),
    );
  }

  @override
  $EpisodesTable createAlias(String alias) {
    return $EpisodesTable(attachedDatabase, alias);
  }
}

class EpisodeRecord extends DataClass implements Insertable<EpisodeRecord> {
  final int sourceId;
  final String seriesKey;
  final String key;
  final int season;
  final int number;
  final String? title;
  final String? ext;
  final String? url;
  final String? headersJson;
  final int? durationSec;
  final String? plot;
  final String? still;
  final int? generation;
  final int? firstGen;
  const EpisodeRecord({
    required this.sourceId,
    required this.seriesKey,
    required this.key,
    required this.season,
    required this.number,
    this.title,
    this.ext,
    this.url,
    this.headersJson,
    this.durationSec,
    this.plot,
    this.still,
    this.generation,
    this.firstGen,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<int>(sourceId);
    map['series_key'] = Variable<String>(seriesKey);
    map['key'] = Variable<String>(key);
    map['season'] = Variable<int>(season);
    map['number'] = Variable<int>(number);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || ext != null) {
      map['ext'] = Variable<String>(ext);
    }
    if (!nullToAbsent || url != null) {
      map['url'] = Variable<String>(url);
    }
    if (!nullToAbsent || headersJson != null) {
      map['headers_json'] = Variable<String>(headersJson);
    }
    if (!nullToAbsent || durationSec != null) {
      map['duration_sec'] = Variable<int>(durationSec);
    }
    if (!nullToAbsent || plot != null) {
      map['plot'] = Variable<String>(plot);
    }
    if (!nullToAbsent || still != null) {
      map['still'] = Variable<String>(still);
    }
    if (!nullToAbsent || generation != null) {
      map['generation'] = Variable<int>(generation);
    }
    if (!nullToAbsent || firstGen != null) {
      map['first_gen'] = Variable<int>(firstGen);
    }
    return map;
  }

  EpisodesCompanion toCompanion(bool nullToAbsent) {
    return EpisodesCompanion(
      sourceId: Value(sourceId),
      seriesKey: Value(seriesKey),
      key: Value(key),
      season: Value(season),
      number: Value(number),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      ext: ext == null && nullToAbsent ? const Value.absent() : Value(ext),
      url: url == null && nullToAbsent ? const Value.absent() : Value(url),
      headersJson: headersJson == null && nullToAbsent
          ? const Value.absent()
          : Value(headersJson),
      durationSec: durationSec == null && nullToAbsent
          ? const Value.absent()
          : Value(durationSec),
      plot: plot == null && nullToAbsent ? const Value.absent() : Value(plot),
      still: still == null && nullToAbsent
          ? const Value.absent()
          : Value(still),
      generation: generation == null && nullToAbsent
          ? const Value.absent()
          : Value(generation),
      firstGen: firstGen == null && nullToAbsent
          ? const Value.absent()
          : Value(firstGen),
    );
  }

  factory EpisodeRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EpisodeRecord(
      sourceId: serializer.fromJson<int>(json['sourceId']),
      seriesKey: serializer.fromJson<String>(json['seriesKey']),
      key: serializer.fromJson<String>(json['key']),
      season: serializer.fromJson<int>(json['season']),
      number: serializer.fromJson<int>(json['number']),
      title: serializer.fromJson<String?>(json['title']),
      ext: serializer.fromJson<String?>(json['ext']),
      url: serializer.fromJson<String?>(json['url']),
      headersJson: serializer.fromJson<String?>(json['headersJson']),
      durationSec: serializer.fromJson<int?>(json['durationSec']),
      plot: serializer.fromJson<String?>(json['plot']),
      still: serializer.fromJson<String?>(json['still']),
      generation: serializer.fromJson<int?>(json['generation']),
      firstGen: serializer.fromJson<int?>(json['firstGen']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<int>(sourceId),
      'seriesKey': serializer.toJson<String>(seriesKey),
      'key': serializer.toJson<String>(key),
      'season': serializer.toJson<int>(season),
      'number': serializer.toJson<int>(number),
      'title': serializer.toJson<String?>(title),
      'ext': serializer.toJson<String?>(ext),
      'url': serializer.toJson<String?>(url),
      'headersJson': serializer.toJson<String?>(headersJson),
      'durationSec': serializer.toJson<int?>(durationSec),
      'plot': serializer.toJson<String?>(plot),
      'still': serializer.toJson<String?>(still),
      'generation': serializer.toJson<int?>(generation),
      'firstGen': serializer.toJson<int?>(firstGen),
    };
  }

  EpisodeRecord copyWith({
    int? sourceId,
    String? seriesKey,
    String? key,
    int? season,
    int? number,
    Value<String?> title = const Value.absent(),
    Value<String?> ext = const Value.absent(),
    Value<String?> url = const Value.absent(),
    Value<String?> headersJson = const Value.absent(),
    Value<int?> durationSec = const Value.absent(),
    Value<String?> plot = const Value.absent(),
    Value<String?> still = const Value.absent(),
    Value<int?> generation = const Value.absent(),
    Value<int?> firstGen = const Value.absent(),
  }) => EpisodeRecord(
    sourceId: sourceId ?? this.sourceId,
    seriesKey: seriesKey ?? this.seriesKey,
    key: key ?? this.key,
    season: season ?? this.season,
    number: number ?? this.number,
    title: title.present ? title.value : this.title,
    ext: ext.present ? ext.value : this.ext,
    url: url.present ? url.value : this.url,
    headersJson: headersJson.present ? headersJson.value : this.headersJson,
    durationSec: durationSec.present ? durationSec.value : this.durationSec,
    plot: plot.present ? plot.value : this.plot,
    still: still.present ? still.value : this.still,
    generation: generation.present ? generation.value : this.generation,
    firstGen: firstGen.present ? firstGen.value : this.firstGen,
  );
  EpisodeRecord copyWithCompanion(EpisodesCompanion data) {
    return EpisodeRecord(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      seriesKey: data.seriesKey.present ? data.seriesKey.value : this.seriesKey,
      key: data.key.present ? data.key.value : this.key,
      season: data.season.present ? data.season.value : this.season,
      number: data.number.present ? data.number.value : this.number,
      title: data.title.present ? data.title.value : this.title,
      ext: data.ext.present ? data.ext.value : this.ext,
      url: data.url.present ? data.url.value : this.url,
      headersJson: data.headersJson.present
          ? data.headersJson.value
          : this.headersJson,
      durationSec: data.durationSec.present
          ? data.durationSec.value
          : this.durationSec,
      plot: data.plot.present ? data.plot.value : this.plot,
      still: data.still.present ? data.still.value : this.still,
      generation: data.generation.present
          ? data.generation.value
          : this.generation,
      firstGen: data.firstGen.present ? data.firstGen.value : this.firstGen,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EpisodeRecord(')
          ..write('sourceId: $sourceId, ')
          ..write('seriesKey: $seriesKey, ')
          ..write('key: $key, ')
          ..write('season: $season, ')
          ..write('number: $number, ')
          ..write('title: $title, ')
          ..write('ext: $ext, ')
          ..write('url: $url, ')
          ..write('headersJson: $headersJson, ')
          ..write('durationSec: $durationSec, ')
          ..write('plot: $plot, ')
          ..write('still: $still, ')
          ..write('generation: $generation, ')
          ..write('firstGen: $firstGen')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sourceId,
    seriesKey,
    key,
    season,
    number,
    title,
    ext,
    url,
    headersJson,
    durationSec,
    plot,
    still,
    generation,
    firstGen,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EpisodeRecord &&
          other.sourceId == this.sourceId &&
          other.seriesKey == this.seriesKey &&
          other.key == this.key &&
          other.season == this.season &&
          other.number == this.number &&
          other.title == this.title &&
          other.ext == this.ext &&
          other.url == this.url &&
          other.headersJson == this.headersJson &&
          other.durationSec == this.durationSec &&
          other.plot == this.plot &&
          other.still == this.still &&
          other.generation == this.generation &&
          other.firstGen == this.firstGen);
}

class EpisodesCompanion extends UpdateCompanion<EpisodeRecord> {
  final Value<int> sourceId;
  final Value<String> seriesKey;
  final Value<String> key;
  final Value<int> season;
  final Value<int> number;
  final Value<String?> title;
  final Value<String?> ext;
  final Value<String?> url;
  final Value<String?> headersJson;
  final Value<int?> durationSec;
  final Value<String?> plot;
  final Value<String?> still;
  final Value<int?> generation;
  final Value<int?> firstGen;
  final Value<int> rowid;
  const EpisodesCompanion({
    this.sourceId = const Value.absent(),
    this.seriesKey = const Value.absent(),
    this.key = const Value.absent(),
    this.season = const Value.absent(),
    this.number = const Value.absent(),
    this.title = const Value.absent(),
    this.ext = const Value.absent(),
    this.url = const Value.absent(),
    this.headersJson = const Value.absent(),
    this.durationSec = const Value.absent(),
    this.plot = const Value.absent(),
    this.still = const Value.absent(),
    this.generation = const Value.absent(),
    this.firstGen = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EpisodesCompanion.insert({
    required int sourceId,
    required String seriesKey,
    required String key,
    required int season,
    required int number,
    this.title = const Value.absent(),
    this.ext = const Value.absent(),
    this.url = const Value.absent(),
    this.headersJson = const Value.absent(),
    this.durationSec = const Value.absent(),
    this.plot = const Value.absent(),
    this.still = const Value.absent(),
    this.generation = const Value.absent(),
    this.firstGen = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId),
       seriesKey = Value(seriesKey),
       key = Value(key),
       season = Value(season),
       number = Value(number);
  static Insertable<EpisodeRecord> custom({
    Expression<int>? sourceId,
    Expression<String>? seriesKey,
    Expression<String>? key,
    Expression<int>? season,
    Expression<int>? number,
    Expression<String>? title,
    Expression<String>? ext,
    Expression<String>? url,
    Expression<String>? headersJson,
    Expression<int>? durationSec,
    Expression<String>? plot,
    Expression<String>? still,
    Expression<int>? generation,
    Expression<int>? firstGen,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (seriesKey != null) 'series_key': seriesKey,
      if (key != null) 'key': key,
      if (season != null) 'season': season,
      if (number != null) 'number': number,
      if (title != null) 'title': title,
      if (ext != null) 'ext': ext,
      if (url != null) 'url': url,
      if (headersJson != null) 'headers_json': headersJson,
      if (durationSec != null) 'duration_sec': durationSec,
      if (plot != null) 'plot': plot,
      if (still != null) 'still': still,
      if (generation != null) 'generation': generation,
      if (firstGen != null) 'first_gen': firstGen,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EpisodesCompanion copyWith({
    Value<int>? sourceId,
    Value<String>? seriesKey,
    Value<String>? key,
    Value<int>? season,
    Value<int>? number,
    Value<String?>? title,
    Value<String?>? ext,
    Value<String?>? url,
    Value<String?>? headersJson,
    Value<int?>? durationSec,
    Value<String?>? plot,
    Value<String?>? still,
    Value<int?>? generation,
    Value<int?>? firstGen,
    Value<int>? rowid,
  }) {
    return EpisodesCompanion(
      sourceId: sourceId ?? this.sourceId,
      seriesKey: seriesKey ?? this.seriesKey,
      key: key ?? this.key,
      season: season ?? this.season,
      number: number ?? this.number,
      title: title ?? this.title,
      ext: ext ?? this.ext,
      url: url ?? this.url,
      headersJson: headersJson ?? this.headersJson,
      durationSec: durationSec ?? this.durationSec,
      plot: plot ?? this.plot,
      still: still ?? this.still,
      generation: generation ?? this.generation,
      firstGen: firstGen ?? this.firstGen,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (seriesKey.present) {
      map['series_key'] = Variable<String>(seriesKey.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (season.present) {
      map['season'] = Variable<int>(season.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (ext.present) {
      map['ext'] = Variable<String>(ext.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (headersJson.present) {
      map['headers_json'] = Variable<String>(headersJson.value);
    }
    if (durationSec.present) {
      map['duration_sec'] = Variable<int>(durationSec.value);
    }
    if (plot.present) {
      map['plot'] = Variable<String>(plot.value);
    }
    if (still.present) {
      map['still'] = Variable<String>(still.value);
    }
    if (generation.present) {
      map['generation'] = Variable<int>(generation.value);
    }
    if (firstGen.present) {
      map['first_gen'] = Variable<int>(firstGen.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EpisodesCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('seriesKey: $seriesKey, ')
          ..write('key: $key, ')
          ..write('season: $season, ')
          ..write('number: $number, ')
          ..write('title: $title, ')
          ..write('ext: $ext, ')
          ..write('url: $url, ')
          ..write('headersJson: $headersJson, ')
          ..write('durationSec: $durationSec, ')
          ..write('plot: $plot, ')
          ..write('still: $still, ')
          ..write('generation: $generation, ')
          ..write('firstGen: $firstGen, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DetailCacheTable extends DetailCache
    with TableInfo<$DetailCacheTable, DetailCacheRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DetailCacheTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sources (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<ContentKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ContentKind>($DetailCacheTable.$converterkind);
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [sourceId, kind, key, json, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'detail_cache';
  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, kind, key};
  @override
  DetailCacheRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DetailCacheRecord(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_id'],
      )!,
      kind: $DetailCacheTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $DetailCacheTable createAlias(String alias) {
    return $DetailCacheTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ContentKind, String, String> $converterkind =
      const EnumNameConverter<ContentKind>(ContentKind.values);
  @override
  bool get withoutRowId => true;
}

class DetailCacheRecord extends DataClass
    implements Insertable<DetailCacheRecord> {
  final int sourceId;
  final ContentKind kind;
  final String key;
  final String json;
  final int fetchedAt;
  const DetailCacheRecord({
    required this.sourceId,
    required this.kind,
    required this.key,
    required this.json,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<int>(sourceId);
    {
      map['kind'] = Variable<String>(
        $DetailCacheTable.$converterkind.toSql(kind),
      );
    }
    map['key'] = Variable<String>(key);
    map['json'] = Variable<String>(json);
    map['fetched_at'] = Variable<int>(fetchedAt);
    return map;
  }

  DetailCacheCompanion toCompanion(bool nullToAbsent) {
    return DetailCacheCompanion(
      sourceId: Value(sourceId),
      kind: Value(kind),
      key: Value(key),
      json: Value(json),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory DetailCacheRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DetailCacheRecord(
      sourceId: serializer.fromJson<int>(json['sourceId']),
      kind: $DetailCacheTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      key: serializer.fromJson<String>(json['key']),
      json: serializer.fromJson<String>(json['json']),
      fetchedAt: serializer.fromJson<int>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<int>(sourceId),
      'kind': serializer.toJson<String>(
        $DetailCacheTable.$converterkind.toJson(kind),
      ),
      'key': serializer.toJson<String>(key),
      'json': serializer.toJson<String>(json),
      'fetchedAt': serializer.toJson<int>(fetchedAt),
    };
  }

  DetailCacheRecord copyWith({
    int? sourceId,
    ContentKind? kind,
    String? key,
    String? json,
    int? fetchedAt,
  }) => DetailCacheRecord(
    sourceId: sourceId ?? this.sourceId,
    kind: kind ?? this.kind,
    key: key ?? this.key,
    json: json ?? this.json,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  DetailCacheRecord copyWithCompanion(DetailCacheCompanion data) {
    return DetailCacheRecord(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      kind: data.kind.present ? data.kind.value : this.kind,
      key: data.key.present ? data.key.value : this.key,
      json: data.json.present ? data.json.value : this.json,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DetailCacheRecord(')
          ..write('sourceId: $sourceId, ')
          ..write('kind: $kind, ')
          ..write('key: $key, ')
          ..write('json: $json, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sourceId, kind, key, json, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DetailCacheRecord &&
          other.sourceId == this.sourceId &&
          other.kind == this.kind &&
          other.key == this.key &&
          other.json == this.json &&
          other.fetchedAt == this.fetchedAt);
}

class DetailCacheCompanion extends UpdateCompanion<DetailCacheRecord> {
  final Value<int> sourceId;
  final Value<ContentKind> kind;
  final Value<String> key;
  final Value<String> json;
  final Value<int> fetchedAt;
  const DetailCacheCompanion({
    this.sourceId = const Value.absent(),
    this.kind = const Value.absent(),
    this.key = const Value.absent(),
    this.json = const Value.absent(),
    this.fetchedAt = const Value.absent(),
  });
  DetailCacheCompanion.insert({
    required int sourceId,
    required ContentKind kind,
    required String key,
    required String json,
    required int fetchedAt,
  }) : sourceId = Value(sourceId),
       kind = Value(kind),
       key = Value(key),
       json = Value(json),
       fetchedAt = Value(fetchedAt);
  static Insertable<DetailCacheRecord> custom({
    Expression<int>? sourceId,
    Expression<String>? kind,
    Expression<String>? key,
    Expression<String>? json,
    Expression<int>? fetchedAt,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (kind != null) 'kind': kind,
      if (key != null) 'key': key,
      if (json != null) 'json': json,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
    });
  }

  DetailCacheCompanion copyWith({
    Value<int>? sourceId,
    Value<ContentKind>? kind,
    Value<String>? key,
    Value<String>? json,
    Value<int>? fetchedAt,
  }) {
    return DetailCacheCompanion(
      sourceId: sourceId ?? this.sourceId,
      kind: kind ?? this.kind,
      key: key ?? this.key,
      json: json ?? this.json,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $DetailCacheTable.$converterkind.toSql(kind.value),
      );
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DetailCacheCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('kind: $kind, ')
          ..write('key: $key, ')
          ..write('json: $json, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }
}

class $EpgSourcesTable extends EpgSources
    with TableInfo<$EpgSourcesTable, EpgSourceRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EpgSourcesTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sources (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<EpgOrigin, String> origin =
      GeneratedColumn<String>(
        'origin',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<EpgOrigin>($EpgSourcesTable.$converterorigin);
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> lastModified = GeneratedColumn<String>(
    'last_modified',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> lastFetchAt = GeneratedColumn<int>(
    'last_fetch_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> programmeCount = GeneratedColumn<int>(
    'programme_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourceId,
    url,
    origin,
    enabled,
    priority,
    etag,
    lastModified,
    lastFetchAt,
    status,
    programmeCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'epg_sources';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EpgSourceRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EpgSourceRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_id'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      origin: $EpgSourcesTable.$converterorigin.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}origin'],
        )!,
      ),
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      ),
      lastModified: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_modified'],
      ),
      lastFetchAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_fetch_at'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
      programmeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}programme_count'],
      )!,
    );
  }

  @override
  $EpgSourcesTable createAlias(String alias) {
    return $EpgSourcesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<EpgOrigin, String, String> $converterorigin =
      const EnumNameConverter<EpgOrigin>(EpgOrigin.values);
}

class EpgSourceRecord extends DataClass implements Insertable<EpgSourceRecord> {
  final int id;
  final int sourceId;

  /// Guide URL with credentials masked (the full URL is then in [Secrets]).
  final String url;
  final EpgOrigin origin;
  final bool enabled;
  final int priority;
  final String? etag;
  final String? lastModified;
  final int? lastFetchAt;
  final String? status;
  final int programmeCount;
  const EpgSourceRecord({
    required this.id,
    required this.sourceId,
    required this.url,
    required this.origin,
    required this.enabled,
    required this.priority,
    this.etag,
    this.lastModified,
    this.lastFetchAt,
    this.status,
    required this.programmeCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['source_id'] = Variable<int>(sourceId);
    map['url'] = Variable<String>(url);
    {
      map['origin'] = Variable<String>(
        $EpgSourcesTable.$converterorigin.toSql(origin),
      );
    }
    map['enabled'] = Variable<bool>(enabled);
    map['priority'] = Variable<int>(priority);
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    if (!nullToAbsent || lastModified != null) {
      map['last_modified'] = Variable<String>(lastModified);
    }
    if (!nullToAbsent || lastFetchAt != null) {
      map['last_fetch_at'] = Variable<int>(lastFetchAt);
    }
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    map['programme_count'] = Variable<int>(programmeCount);
    return map;
  }

  EpgSourcesCompanion toCompanion(bool nullToAbsent) {
    return EpgSourcesCompanion(
      id: Value(id),
      sourceId: Value(sourceId),
      url: Value(url),
      origin: Value(origin),
      enabled: Value(enabled),
      priority: Value(priority),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
      lastModified: lastModified == null && nullToAbsent
          ? const Value.absent()
          : Value(lastModified),
      lastFetchAt: lastFetchAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastFetchAt),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
      programmeCount: Value(programmeCount),
    );
  }

  factory EpgSourceRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EpgSourceRecord(
      id: serializer.fromJson<int>(json['id']),
      sourceId: serializer.fromJson<int>(json['sourceId']),
      url: serializer.fromJson<String>(json['url']),
      origin: $EpgSourcesTable.$converterorigin.fromJson(
        serializer.fromJson<String>(json['origin']),
      ),
      enabled: serializer.fromJson<bool>(json['enabled']),
      priority: serializer.fromJson<int>(json['priority']),
      etag: serializer.fromJson<String?>(json['etag']),
      lastModified: serializer.fromJson<String?>(json['lastModified']),
      lastFetchAt: serializer.fromJson<int?>(json['lastFetchAt']),
      status: serializer.fromJson<String?>(json['status']),
      programmeCount: serializer.fromJson<int>(json['programmeCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sourceId': serializer.toJson<int>(sourceId),
      'url': serializer.toJson<String>(url),
      'origin': serializer.toJson<String>(
        $EpgSourcesTable.$converterorigin.toJson(origin),
      ),
      'enabled': serializer.toJson<bool>(enabled),
      'priority': serializer.toJson<int>(priority),
      'etag': serializer.toJson<String?>(etag),
      'lastModified': serializer.toJson<String?>(lastModified),
      'lastFetchAt': serializer.toJson<int?>(lastFetchAt),
      'status': serializer.toJson<String?>(status),
      'programmeCount': serializer.toJson<int>(programmeCount),
    };
  }

  EpgSourceRecord copyWith({
    int? id,
    int? sourceId,
    String? url,
    EpgOrigin? origin,
    bool? enabled,
    int? priority,
    Value<String?> etag = const Value.absent(),
    Value<String?> lastModified = const Value.absent(),
    Value<int?> lastFetchAt = const Value.absent(),
    Value<String?> status = const Value.absent(),
    int? programmeCount,
  }) => EpgSourceRecord(
    id: id ?? this.id,
    sourceId: sourceId ?? this.sourceId,
    url: url ?? this.url,
    origin: origin ?? this.origin,
    enabled: enabled ?? this.enabled,
    priority: priority ?? this.priority,
    etag: etag.present ? etag.value : this.etag,
    lastModified: lastModified.present ? lastModified.value : this.lastModified,
    lastFetchAt: lastFetchAt.present ? lastFetchAt.value : this.lastFetchAt,
    status: status.present ? status.value : this.status,
    programmeCount: programmeCount ?? this.programmeCount,
  );
  EpgSourceRecord copyWithCompanion(EpgSourcesCompanion data) {
    return EpgSourceRecord(
      id: data.id.present ? data.id.value : this.id,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      url: data.url.present ? data.url.value : this.url,
      origin: data.origin.present ? data.origin.value : this.origin,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      priority: data.priority.present ? data.priority.value : this.priority,
      etag: data.etag.present ? data.etag.value : this.etag,
      lastModified: data.lastModified.present
          ? data.lastModified.value
          : this.lastModified,
      lastFetchAt: data.lastFetchAt.present
          ? data.lastFetchAt.value
          : this.lastFetchAt,
      status: data.status.present ? data.status.value : this.status,
      programmeCount: data.programmeCount.present
          ? data.programmeCount.value
          : this.programmeCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EpgSourceRecord(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('url: $url, ')
          ..write('origin: $origin, ')
          ..write('enabled: $enabled, ')
          ..write('priority: $priority, ')
          ..write('etag: $etag, ')
          ..write('lastModified: $lastModified, ')
          ..write('lastFetchAt: $lastFetchAt, ')
          ..write('status: $status, ')
          ..write('programmeCount: $programmeCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sourceId,
    url,
    origin,
    enabled,
    priority,
    etag,
    lastModified,
    lastFetchAt,
    status,
    programmeCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EpgSourceRecord &&
          other.id == this.id &&
          other.sourceId == this.sourceId &&
          other.url == this.url &&
          other.origin == this.origin &&
          other.enabled == this.enabled &&
          other.priority == this.priority &&
          other.etag == this.etag &&
          other.lastModified == this.lastModified &&
          other.lastFetchAt == this.lastFetchAt &&
          other.status == this.status &&
          other.programmeCount == this.programmeCount);
}

class EpgSourcesCompanion extends UpdateCompanion<EpgSourceRecord> {
  final Value<int> id;
  final Value<int> sourceId;
  final Value<String> url;
  final Value<EpgOrigin> origin;
  final Value<bool> enabled;
  final Value<int> priority;
  final Value<String?> etag;
  final Value<String?> lastModified;
  final Value<int?> lastFetchAt;
  final Value<String?> status;
  final Value<int> programmeCount;
  const EpgSourcesCompanion({
    this.id = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.url = const Value.absent(),
    this.origin = const Value.absent(),
    this.enabled = const Value.absent(),
    this.priority = const Value.absent(),
    this.etag = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.lastFetchAt = const Value.absent(),
    this.status = const Value.absent(),
    this.programmeCount = const Value.absent(),
  });
  EpgSourcesCompanion.insert({
    this.id = const Value.absent(),
    required int sourceId,
    required String url,
    required EpgOrigin origin,
    this.enabled = const Value.absent(),
    this.priority = const Value.absent(),
    this.etag = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.lastFetchAt = const Value.absent(),
    this.status = const Value.absent(),
    this.programmeCount = const Value.absent(),
  }) : sourceId = Value(sourceId),
       url = Value(url),
       origin = Value(origin);
  static Insertable<EpgSourceRecord> custom({
    Expression<int>? id,
    Expression<int>? sourceId,
    Expression<String>? url,
    Expression<String>? origin,
    Expression<bool>? enabled,
    Expression<int>? priority,
    Expression<String>? etag,
    Expression<String>? lastModified,
    Expression<int>? lastFetchAt,
    Expression<String>? status,
    Expression<int>? programmeCount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceId != null) 'source_id': sourceId,
      if (url != null) 'url': url,
      if (origin != null) 'origin': origin,
      if (enabled != null) 'enabled': enabled,
      if (priority != null) 'priority': priority,
      if (etag != null) 'etag': etag,
      if (lastModified != null) 'last_modified': lastModified,
      if (lastFetchAt != null) 'last_fetch_at': lastFetchAt,
      if (status != null) 'status': status,
      if (programmeCount != null) 'programme_count': programmeCount,
    });
  }

  EpgSourcesCompanion copyWith({
    Value<int>? id,
    Value<int>? sourceId,
    Value<String>? url,
    Value<EpgOrigin>? origin,
    Value<bool>? enabled,
    Value<int>? priority,
    Value<String?>? etag,
    Value<String?>? lastModified,
    Value<int?>? lastFetchAt,
    Value<String?>? status,
    Value<int>? programmeCount,
  }) {
    return EpgSourcesCompanion(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      url: url ?? this.url,
      origin: origin ?? this.origin,
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
      lastFetchAt: lastFetchAt ?? this.lastFetchAt,
      status: status ?? this.status,
      programmeCount: programmeCount ?? this.programmeCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(
        $EpgSourcesTable.$converterorigin.toSql(origin.value),
      );
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (lastModified.present) {
      map['last_modified'] = Variable<String>(lastModified.value);
    }
    if (lastFetchAt.present) {
      map['last_fetch_at'] = Variable<int>(lastFetchAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (programmeCount.present) {
      map['programme_count'] = Variable<int>(programmeCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EpgSourcesCompanion(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('url: $url, ')
          ..write('origin: $origin, ')
          ..write('enabled: $enabled, ')
          ..write('priority: $priority, ')
          ..write('etag: $etag, ')
          ..write('lastModified: $lastModified, ')
          ..write('lastFetchAt: $lastFetchAt, ')
          ..write('status: $status, ')
          ..write('programmeCount: $programmeCount')
          ..write(')'))
        .toString();
  }
}

class $EpgChannelsTable extends EpgChannels
    with TableInfo<$EpgChannelsTable, EpgChannelRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EpgChannelsTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> epgSourceId = GeneratedColumn<int>(
    'epg_source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES epg_sources (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> xmltvId = GeneratedColumn<String>(
    'xmltv_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> displayNamesNorm = GeneratedColumn<String>(
    'display_names_norm',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    epgSourceId,
    xmltvId,
    displayName,
    displayNamesNorm,
    icon,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'epg_channels';
  @override
  Set<GeneratedColumn> get $primaryKey => {epgSourceId, xmltvId};
  @override
  EpgChannelRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EpgChannelRecord(
      epgSourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}epg_source_id'],
      )!,
      xmltvId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}xmltv_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
      displayNamesNorm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_names_norm'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      ),
    );
  }

  @override
  $EpgChannelsTable createAlias(String alias) {
    return $EpgChannelsTable(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
}

class EpgChannelRecord extends DataClass
    implements Insertable<EpgChannelRecord> {
  final int epgSourceId;
  final String xmltvId;

  /// First display name as published, for pickers.
  final String? displayName;

  /// `normalizeForEpg` of every display name, newline separated.
  final String displayNamesNorm;
  final String? icon;
  const EpgChannelRecord({
    required this.epgSourceId,
    required this.xmltvId,
    this.displayName,
    required this.displayNamesNorm,
    this.icon,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['epg_source_id'] = Variable<int>(epgSourceId);
    map['xmltv_id'] = Variable<String>(xmltvId);
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    map['display_names_norm'] = Variable<String>(displayNamesNorm);
    if (!nullToAbsent || icon != null) {
      map['icon'] = Variable<String>(icon);
    }
    return map;
  }

  EpgChannelsCompanion toCompanion(bool nullToAbsent) {
    return EpgChannelsCompanion(
      epgSourceId: Value(epgSourceId),
      xmltvId: Value(xmltvId),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      displayNamesNorm: Value(displayNamesNorm),
      icon: icon == null && nullToAbsent ? const Value.absent() : Value(icon),
    );
  }

  factory EpgChannelRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EpgChannelRecord(
      epgSourceId: serializer.fromJson<int>(json['epgSourceId']),
      xmltvId: serializer.fromJson<String>(json['xmltvId']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      displayNamesNorm: serializer.fromJson<String>(json['displayNamesNorm']),
      icon: serializer.fromJson<String?>(json['icon']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'epgSourceId': serializer.toJson<int>(epgSourceId),
      'xmltvId': serializer.toJson<String>(xmltvId),
      'displayName': serializer.toJson<String?>(displayName),
      'displayNamesNorm': serializer.toJson<String>(displayNamesNorm),
      'icon': serializer.toJson<String?>(icon),
    };
  }

  EpgChannelRecord copyWith({
    int? epgSourceId,
    String? xmltvId,
    Value<String?> displayName = const Value.absent(),
    String? displayNamesNorm,
    Value<String?> icon = const Value.absent(),
  }) => EpgChannelRecord(
    epgSourceId: epgSourceId ?? this.epgSourceId,
    xmltvId: xmltvId ?? this.xmltvId,
    displayName: displayName.present ? displayName.value : this.displayName,
    displayNamesNorm: displayNamesNorm ?? this.displayNamesNorm,
    icon: icon.present ? icon.value : this.icon,
  );
  EpgChannelRecord copyWithCompanion(EpgChannelsCompanion data) {
    return EpgChannelRecord(
      epgSourceId: data.epgSourceId.present
          ? data.epgSourceId.value
          : this.epgSourceId,
      xmltvId: data.xmltvId.present ? data.xmltvId.value : this.xmltvId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      displayNamesNorm: data.displayNamesNorm.present
          ? data.displayNamesNorm.value
          : this.displayNamesNorm,
      icon: data.icon.present ? data.icon.value : this.icon,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EpgChannelRecord(')
          ..write('epgSourceId: $epgSourceId, ')
          ..write('xmltvId: $xmltvId, ')
          ..write('displayName: $displayName, ')
          ..write('displayNamesNorm: $displayNamesNorm, ')
          ..write('icon: $icon')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(epgSourceId, xmltvId, displayName, displayNamesNorm, icon);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EpgChannelRecord &&
          other.epgSourceId == this.epgSourceId &&
          other.xmltvId == this.xmltvId &&
          other.displayName == this.displayName &&
          other.displayNamesNorm == this.displayNamesNorm &&
          other.icon == this.icon);
}

class EpgChannelsCompanion extends UpdateCompanion<EpgChannelRecord> {
  final Value<int> epgSourceId;
  final Value<String> xmltvId;
  final Value<String?> displayName;
  final Value<String> displayNamesNorm;
  final Value<String?> icon;
  const EpgChannelsCompanion({
    this.epgSourceId = const Value.absent(),
    this.xmltvId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.displayNamesNorm = const Value.absent(),
    this.icon = const Value.absent(),
  });
  EpgChannelsCompanion.insert({
    required int epgSourceId,
    required String xmltvId,
    this.displayName = const Value.absent(),
    required String displayNamesNorm,
    this.icon = const Value.absent(),
  }) : epgSourceId = Value(epgSourceId),
       xmltvId = Value(xmltvId),
       displayNamesNorm = Value(displayNamesNorm);
  static Insertable<EpgChannelRecord> custom({
    Expression<int>? epgSourceId,
    Expression<String>? xmltvId,
    Expression<String>? displayName,
    Expression<String>? displayNamesNorm,
    Expression<String>? icon,
  }) {
    return RawValuesInsertable({
      if (epgSourceId != null) 'epg_source_id': epgSourceId,
      if (xmltvId != null) 'xmltv_id': xmltvId,
      if (displayName != null) 'display_name': displayName,
      if (displayNamesNorm != null) 'display_names_norm': displayNamesNorm,
      if (icon != null) 'icon': icon,
    });
  }

  EpgChannelsCompanion copyWith({
    Value<int>? epgSourceId,
    Value<String>? xmltvId,
    Value<String?>? displayName,
    Value<String>? displayNamesNorm,
    Value<String?>? icon,
  }) {
    return EpgChannelsCompanion(
      epgSourceId: epgSourceId ?? this.epgSourceId,
      xmltvId: xmltvId ?? this.xmltvId,
      displayName: displayName ?? this.displayName,
      displayNamesNorm: displayNamesNorm ?? this.displayNamesNorm,
      icon: icon ?? this.icon,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (epgSourceId.present) {
      map['epg_source_id'] = Variable<int>(epgSourceId.value);
    }
    if (xmltvId.present) {
      map['xmltv_id'] = Variable<String>(xmltvId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (displayNamesNorm.present) {
      map['display_names_norm'] = Variable<String>(displayNamesNorm.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EpgChannelsCompanion(')
          ..write('epgSourceId: $epgSourceId, ')
          ..write('xmltvId: $xmltvId, ')
          ..write('displayName: $displayName, ')
          ..write('displayNamesNorm: $displayNamesNorm, ')
          ..write('icon: $icon')
          ..write(')'))
        .toString();
  }
}

class $ProgrammesTable extends Programmes
    with TableInfo<$ProgrammesTable, ProgrammeRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgrammesTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> epgSourceId = GeneratedColumn<int>(
    'epg_source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES epg_sources (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> xmltvId = GeneratedColumn<String>(
    'xmltv_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> startUtc = GeneratedColumn<int>(
    'start_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> stopUtc = GeneratedColumn<int>(
    'stop_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> subTitle = GeneratedColumn<String>(
    'sub_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> desc = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    epgSourceId,
    xmltvId,
    startUtc,
    stopUtc,
    title,
    subTitle,
    desc,
    category,
    icon,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'programmes';
  @override
  Set<GeneratedColumn> get $primaryKey => {epgSourceId, xmltvId, startUtc};
  @override
  ProgrammeRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProgrammeRecord(
      epgSourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}epg_source_id'],
      )!,
      xmltvId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}xmltv_id'],
      )!,
      startUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_utc'],
      )!,
      stopUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stop_utc'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      subTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sub_title'],
      ),
      desc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      ),
    );
  }

  @override
  $ProgrammesTable createAlias(String alias) {
    return $ProgrammesTable(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
}

class ProgrammeRecord extends DataClass implements Insertable<ProgrammeRecord> {
  final int epgSourceId;
  final String xmltvId;
  final int startUtc;
  final int stopUtc;
  final String title;
  final String? subTitle;
  final String? desc;
  final String? category;
  final String? icon;
  const ProgrammeRecord({
    required this.epgSourceId,
    required this.xmltvId,
    required this.startUtc,
    required this.stopUtc,
    required this.title,
    this.subTitle,
    this.desc,
    this.category,
    this.icon,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['epg_source_id'] = Variable<int>(epgSourceId);
    map['xmltv_id'] = Variable<String>(xmltvId);
    map['start_utc'] = Variable<int>(startUtc);
    map['stop_utc'] = Variable<int>(stopUtc);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || subTitle != null) {
      map['sub_title'] = Variable<String>(subTitle);
    }
    if (!nullToAbsent || desc != null) {
      map['description'] = Variable<String>(desc);
    }
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    if (!nullToAbsent || icon != null) {
      map['icon'] = Variable<String>(icon);
    }
    return map;
  }

  ProgrammesCompanion toCompanion(bool nullToAbsent) {
    return ProgrammesCompanion(
      epgSourceId: Value(epgSourceId),
      xmltvId: Value(xmltvId),
      startUtc: Value(startUtc),
      stopUtc: Value(stopUtc),
      title: Value(title),
      subTitle: subTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(subTitle),
      desc: desc == null && nullToAbsent ? const Value.absent() : Value(desc),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      icon: icon == null && nullToAbsent ? const Value.absent() : Value(icon),
    );
  }

  factory ProgrammeRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProgrammeRecord(
      epgSourceId: serializer.fromJson<int>(json['epgSourceId']),
      xmltvId: serializer.fromJson<String>(json['xmltvId']),
      startUtc: serializer.fromJson<int>(json['startUtc']),
      stopUtc: serializer.fromJson<int>(json['stopUtc']),
      title: serializer.fromJson<String>(json['title']),
      subTitle: serializer.fromJson<String?>(json['subTitle']),
      desc: serializer.fromJson<String?>(json['desc']),
      category: serializer.fromJson<String?>(json['category']),
      icon: serializer.fromJson<String?>(json['icon']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'epgSourceId': serializer.toJson<int>(epgSourceId),
      'xmltvId': serializer.toJson<String>(xmltvId),
      'startUtc': serializer.toJson<int>(startUtc),
      'stopUtc': serializer.toJson<int>(stopUtc),
      'title': serializer.toJson<String>(title),
      'subTitle': serializer.toJson<String?>(subTitle),
      'desc': serializer.toJson<String?>(desc),
      'category': serializer.toJson<String?>(category),
      'icon': serializer.toJson<String?>(icon),
    };
  }

  ProgrammeRecord copyWith({
    int? epgSourceId,
    String? xmltvId,
    int? startUtc,
    int? stopUtc,
    String? title,
    Value<String?> subTitle = const Value.absent(),
    Value<String?> desc = const Value.absent(),
    Value<String?> category = const Value.absent(),
    Value<String?> icon = const Value.absent(),
  }) => ProgrammeRecord(
    epgSourceId: epgSourceId ?? this.epgSourceId,
    xmltvId: xmltvId ?? this.xmltvId,
    startUtc: startUtc ?? this.startUtc,
    stopUtc: stopUtc ?? this.stopUtc,
    title: title ?? this.title,
    subTitle: subTitle.present ? subTitle.value : this.subTitle,
    desc: desc.present ? desc.value : this.desc,
    category: category.present ? category.value : this.category,
    icon: icon.present ? icon.value : this.icon,
  );
  ProgrammeRecord copyWithCompanion(ProgrammesCompanion data) {
    return ProgrammeRecord(
      epgSourceId: data.epgSourceId.present
          ? data.epgSourceId.value
          : this.epgSourceId,
      xmltvId: data.xmltvId.present ? data.xmltvId.value : this.xmltvId,
      startUtc: data.startUtc.present ? data.startUtc.value : this.startUtc,
      stopUtc: data.stopUtc.present ? data.stopUtc.value : this.stopUtc,
      title: data.title.present ? data.title.value : this.title,
      subTitle: data.subTitle.present ? data.subTitle.value : this.subTitle,
      desc: data.desc.present ? data.desc.value : this.desc,
      category: data.category.present ? data.category.value : this.category,
      icon: data.icon.present ? data.icon.value : this.icon,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgrammeRecord(')
          ..write('epgSourceId: $epgSourceId, ')
          ..write('xmltvId: $xmltvId, ')
          ..write('startUtc: $startUtc, ')
          ..write('stopUtc: $stopUtc, ')
          ..write('title: $title, ')
          ..write('subTitle: $subTitle, ')
          ..write('desc: $desc, ')
          ..write('category: $category, ')
          ..write('icon: $icon')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    epgSourceId,
    xmltvId,
    startUtc,
    stopUtc,
    title,
    subTitle,
    desc,
    category,
    icon,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgrammeRecord &&
          other.epgSourceId == this.epgSourceId &&
          other.xmltvId == this.xmltvId &&
          other.startUtc == this.startUtc &&
          other.stopUtc == this.stopUtc &&
          other.title == this.title &&
          other.subTitle == this.subTitle &&
          other.desc == this.desc &&
          other.category == this.category &&
          other.icon == this.icon);
}

class ProgrammesCompanion extends UpdateCompanion<ProgrammeRecord> {
  final Value<int> epgSourceId;
  final Value<String> xmltvId;
  final Value<int> startUtc;
  final Value<int> stopUtc;
  final Value<String> title;
  final Value<String?> subTitle;
  final Value<String?> desc;
  final Value<String?> category;
  final Value<String?> icon;
  const ProgrammesCompanion({
    this.epgSourceId = const Value.absent(),
    this.xmltvId = const Value.absent(),
    this.startUtc = const Value.absent(),
    this.stopUtc = const Value.absent(),
    this.title = const Value.absent(),
    this.subTitle = const Value.absent(),
    this.desc = const Value.absent(),
    this.category = const Value.absent(),
    this.icon = const Value.absent(),
  });
  ProgrammesCompanion.insert({
    required int epgSourceId,
    required String xmltvId,
    required int startUtc,
    required int stopUtc,
    required String title,
    this.subTitle = const Value.absent(),
    this.desc = const Value.absent(),
    this.category = const Value.absent(),
    this.icon = const Value.absent(),
  }) : epgSourceId = Value(epgSourceId),
       xmltvId = Value(xmltvId),
       startUtc = Value(startUtc),
       stopUtc = Value(stopUtc),
       title = Value(title);
  static Insertable<ProgrammeRecord> custom({
    Expression<int>? epgSourceId,
    Expression<String>? xmltvId,
    Expression<int>? startUtc,
    Expression<int>? stopUtc,
    Expression<String>? title,
    Expression<String>? subTitle,
    Expression<String>? desc,
    Expression<String>? category,
    Expression<String>? icon,
  }) {
    return RawValuesInsertable({
      if (epgSourceId != null) 'epg_source_id': epgSourceId,
      if (xmltvId != null) 'xmltv_id': xmltvId,
      if (startUtc != null) 'start_utc': startUtc,
      if (stopUtc != null) 'stop_utc': stopUtc,
      if (title != null) 'title': title,
      if (subTitle != null) 'sub_title': subTitle,
      if (desc != null) 'description': desc,
      if (category != null) 'category': category,
      if (icon != null) 'icon': icon,
    });
  }

  ProgrammesCompanion copyWith({
    Value<int>? epgSourceId,
    Value<String>? xmltvId,
    Value<int>? startUtc,
    Value<int>? stopUtc,
    Value<String>? title,
    Value<String?>? subTitle,
    Value<String?>? desc,
    Value<String?>? category,
    Value<String?>? icon,
  }) {
    return ProgrammesCompanion(
      epgSourceId: epgSourceId ?? this.epgSourceId,
      xmltvId: xmltvId ?? this.xmltvId,
      startUtc: startUtc ?? this.startUtc,
      stopUtc: stopUtc ?? this.stopUtc,
      title: title ?? this.title,
      subTitle: subTitle ?? this.subTitle,
      desc: desc ?? this.desc,
      category: category ?? this.category,
      icon: icon ?? this.icon,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (epgSourceId.present) {
      map['epg_source_id'] = Variable<int>(epgSourceId.value);
    }
    if (xmltvId.present) {
      map['xmltv_id'] = Variable<String>(xmltvId.value);
    }
    if (startUtc.present) {
      map['start_utc'] = Variable<int>(startUtc.value);
    }
    if (stopUtc.present) {
      map['stop_utc'] = Variable<int>(stopUtc.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (subTitle.present) {
      map['sub_title'] = Variable<String>(subTitle.value);
    }
    if (desc.present) {
      map['description'] = Variable<String>(desc.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgrammesCompanion(')
          ..write('epgSourceId: $epgSourceId, ')
          ..write('xmltvId: $xmltvId, ')
          ..write('startUtc: $startUtc, ')
          ..write('stopUtc: $stopUtc, ')
          ..write('title: $title, ')
          ..write('subTitle: $subTitle, ')
          ..write('desc: $desc, ')
          ..write('category: $category, ')
          ..write('icon: $icon')
          ..write(')'))
        .toString();
  }
}

class $ChannelEpgMapTable extends ChannelEpgMap
    with TableInfo<$ChannelEpgMapTable, ChannelEpgMapRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChannelEpgMapTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sources (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> channelKey = GeneratedColumn<String>(
    'channel_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> epgSourceId = GeneratedColumn<int>(
    'epg_source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES epg_sources (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> xmltvId = GeneratedColumn<String>(
    'xmltv_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<EpgMatchKind, String> matchKind =
      GeneratedColumn<String>(
        'match_kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<EpgMatchKind>($ChannelEpgMapTable.$convertermatchKind);
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    channelKey,
    epgSourceId,
    xmltvId,
    matchKind,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'channel_epg_map';
  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, channelKey};
  @override
  ChannelEpgMapRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChannelEpgMapRecord(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_id'],
      )!,
      channelKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel_key'],
      )!,
      epgSourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}epg_source_id'],
      )!,
      xmltvId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}xmltv_id'],
      )!,
      matchKind: $ChannelEpgMapTable.$convertermatchKind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}match_kind'],
        )!,
      ),
    );
  }

  @override
  $ChannelEpgMapTable createAlias(String alias) {
    return $ChannelEpgMapTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<EpgMatchKind, String, String> $convertermatchKind =
      const EnumNameConverter<EpgMatchKind>(EpgMatchKind.values);
  @override
  bool get withoutRowId => true;
}

class ChannelEpgMapRecord extends DataClass
    implements Insertable<ChannelEpgMapRecord> {
  final int sourceId;
  final String channelKey;
  final int epgSourceId;
  final String xmltvId;
  final EpgMatchKind matchKind;
  const ChannelEpgMapRecord({
    required this.sourceId,
    required this.channelKey,
    required this.epgSourceId,
    required this.xmltvId,
    required this.matchKind,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<int>(sourceId);
    map['channel_key'] = Variable<String>(channelKey);
    map['epg_source_id'] = Variable<int>(epgSourceId);
    map['xmltv_id'] = Variable<String>(xmltvId);
    {
      map['match_kind'] = Variable<String>(
        $ChannelEpgMapTable.$convertermatchKind.toSql(matchKind),
      );
    }
    return map;
  }

  ChannelEpgMapCompanion toCompanion(bool nullToAbsent) {
    return ChannelEpgMapCompanion(
      sourceId: Value(sourceId),
      channelKey: Value(channelKey),
      epgSourceId: Value(epgSourceId),
      xmltvId: Value(xmltvId),
      matchKind: Value(matchKind),
    );
  }

  factory ChannelEpgMapRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChannelEpgMapRecord(
      sourceId: serializer.fromJson<int>(json['sourceId']),
      channelKey: serializer.fromJson<String>(json['channelKey']),
      epgSourceId: serializer.fromJson<int>(json['epgSourceId']),
      xmltvId: serializer.fromJson<String>(json['xmltvId']),
      matchKind: $ChannelEpgMapTable.$convertermatchKind.fromJson(
        serializer.fromJson<String>(json['matchKind']),
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<int>(sourceId),
      'channelKey': serializer.toJson<String>(channelKey),
      'epgSourceId': serializer.toJson<int>(epgSourceId),
      'xmltvId': serializer.toJson<String>(xmltvId),
      'matchKind': serializer.toJson<String>(
        $ChannelEpgMapTable.$convertermatchKind.toJson(matchKind),
      ),
    };
  }

  ChannelEpgMapRecord copyWith({
    int? sourceId,
    String? channelKey,
    int? epgSourceId,
    String? xmltvId,
    EpgMatchKind? matchKind,
  }) => ChannelEpgMapRecord(
    sourceId: sourceId ?? this.sourceId,
    channelKey: channelKey ?? this.channelKey,
    epgSourceId: epgSourceId ?? this.epgSourceId,
    xmltvId: xmltvId ?? this.xmltvId,
    matchKind: matchKind ?? this.matchKind,
  );
  ChannelEpgMapRecord copyWithCompanion(ChannelEpgMapCompanion data) {
    return ChannelEpgMapRecord(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      channelKey: data.channelKey.present
          ? data.channelKey.value
          : this.channelKey,
      epgSourceId: data.epgSourceId.present
          ? data.epgSourceId.value
          : this.epgSourceId,
      xmltvId: data.xmltvId.present ? data.xmltvId.value : this.xmltvId,
      matchKind: data.matchKind.present ? data.matchKind.value : this.matchKind,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChannelEpgMapRecord(')
          ..write('sourceId: $sourceId, ')
          ..write('channelKey: $channelKey, ')
          ..write('epgSourceId: $epgSourceId, ')
          ..write('xmltvId: $xmltvId, ')
          ..write('matchKind: $matchKind')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sourceId, channelKey, epgSourceId, xmltvId, matchKind);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChannelEpgMapRecord &&
          other.sourceId == this.sourceId &&
          other.channelKey == this.channelKey &&
          other.epgSourceId == this.epgSourceId &&
          other.xmltvId == this.xmltvId &&
          other.matchKind == this.matchKind);
}

class ChannelEpgMapCompanion extends UpdateCompanion<ChannelEpgMapRecord> {
  final Value<int> sourceId;
  final Value<String> channelKey;
  final Value<int> epgSourceId;
  final Value<String> xmltvId;
  final Value<EpgMatchKind> matchKind;
  const ChannelEpgMapCompanion({
    this.sourceId = const Value.absent(),
    this.channelKey = const Value.absent(),
    this.epgSourceId = const Value.absent(),
    this.xmltvId = const Value.absent(),
    this.matchKind = const Value.absent(),
  });
  ChannelEpgMapCompanion.insert({
    required int sourceId,
    required String channelKey,
    required int epgSourceId,
    required String xmltvId,
    required EpgMatchKind matchKind,
  }) : sourceId = Value(sourceId),
       channelKey = Value(channelKey),
       epgSourceId = Value(epgSourceId),
       xmltvId = Value(xmltvId),
       matchKind = Value(matchKind);
  static Insertable<ChannelEpgMapRecord> custom({
    Expression<int>? sourceId,
    Expression<String>? channelKey,
    Expression<int>? epgSourceId,
    Expression<String>? xmltvId,
    Expression<String>? matchKind,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (channelKey != null) 'channel_key': channelKey,
      if (epgSourceId != null) 'epg_source_id': epgSourceId,
      if (xmltvId != null) 'xmltv_id': xmltvId,
      if (matchKind != null) 'match_kind': matchKind,
    });
  }

  ChannelEpgMapCompanion copyWith({
    Value<int>? sourceId,
    Value<String>? channelKey,
    Value<int>? epgSourceId,
    Value<String>? xmltvId,
    Value<EpgMatchKind>? matchKind,
  }) {
    return ChannelEpgMapCompanion(
      sourceId: sourceId ?? this.sourceId,
      channelKey: channelKey ?? this.channelKey,
      epgSourceId: epgSourceId ?? this.epgSourceId,
      xmltvId: xmltvId ?? this.xmltvId,
      matchKind: matchKind ?? this.matchKind,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (channelKey.present) {
      map['channel_key'] = Variable<String>(channelKey.value);
    }
    if (epgSourceId.present) {
      map['epg_source_id'] = Variable<int>(epgSourceId.value);
    }
    if (xmltvId.present) {
      map['xmltv_id'] = Variable<String>(xmltvId.value);
    }
    if (matchKind.present) {
      map['match_kind'] = Variable<String>(
        $ChannelEpgMapTable.$convertermatchKind.toSql(matchKind.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChannelEpgMapCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('channelKey: $channelKey, ')
          ..write('epgSourceId: $epgSourceId, ')
          ..write('xmltvId: $xmltvId, ')
          ..write('matchKind: $matchKind')
          ..write(')'))
        .toString();
  }
}

class $ChannelPrefsTable extends ChannelPrefs
    with TableInfo<$ChannelPrefsTable, ChannelPrefRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChannelPrefsTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sources (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> channelKey = GeneratedColumn<String>(
    'channel_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<EngineKind?, String> engine =
      GeneratedColumn<String>(
        'engine',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<EngineKind?>($ChannelPrefsTable.$converterenginen);
  @override
  late final GeneratedColumnWithTypeConverter<AspectMode?, String> aspect =
      GeneratedColumn<String>(
        'aspect',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<AspectMode?>($ChannelPrefsTable.$converteraspectn);
  @override
  late final GeneratedColumn<String> audioLang = GeneratedColumn<String>(
    'audio_lang',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    channelKey,
    engine,
    aspect,
    audioLang,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'channel_prefs';
  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, channelKey};
  @override
  ChannelPrefRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChannelPrefRecord(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_id'],
      )!,
      channelKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel_key'],
      )!,
      engine: $ChannelPrefsTable.$converterenginen.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}engine'],
        ),
      ),
      aspect: $ChannelPrefsTable.$converteraspectn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}aspect'],
        ),
      ),
      audioLang: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_lang'],
      ),
    );
  }

  @override
  $ChannelPrefsTable createAlias(String alias) {
    return $ChannelPrefsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<EngineKind, String, String> $converterengine =
      const EnumNameConverter<EngineKind>(EngineKind.values);
  static JsonTypeConverter2<EngineKind?, String?, String?> $converterenginen =
      JsonTypeConverter2.asNullable($converterengine);
  static JsonTypeConverter2<AspectMode, String, String> $converteraspect =
      const EnumNameConverter<AspectMode>(AspectMode.values);
  static JsonTypeConverter2<AspectMode?, String?, String?> $converteraspectn =
      JsonTypeConverter2.asNullable($converteraspect);
  @override
  bool get withoutRowId => true;
}

class ChannelPrefRecord extends DataClass
    implements Insertable<ChannelPrefRecord> {
  final int sourceId;
  final String channelKey;
  final EngineKind? engine;
  final AspectMode? aspect;
  final String? audioLang;
  const ChannelPrefRecord({
    required this.sourceId,
    required this.channelKey,
    this.engine,
    this.aspect,
    this.audioLang,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<int>(sourceId);
    map['channel_key'] = Variable<String>(channelKey);
    if (!nullToAbsent || engine != null) {
      map['engine'] = Variable<String>(
        $ChannelPrefsTable.$converterenginen.toSql(engine),
      );
    }
    if (!nullToAbsent || aspect != null) {
      map['aspect'] = Variable<String>(
        $ChannelPrefsTable.$converteraspectn.toSql(aspect),
      );
    }
    if (!nullToAbsent || audioLang != null) {
      map['audio_lang'] = Variable<String>(audioLang);
    }
    return map;
  }

  ChannelPrefsCompanion toCompanion(bool nullToAbsent) {
    return ChannelPrefsCompanion(
      sourceId: Value(sourceId),
      channelKey: Value(channelKey),
      engine: engine == null && nullToAbsent
          ? const Value.absent()
          : Value(engine),
      aspect: aspect == null && nullToAbsent
          ? const Value.absent()
          : Value(aspect),
      audioLang: audioLang == null && nullToAbsent
          ? const Value.absent()
          : Value(audioLang),
    );
  }

  factory ChannelPrefRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChannelPrefRecord(
      sourceId: serializer.fromJson<int>(json['sourceId']),
      channelKey: serializer.fromJson<String>(json['channelKey']),
      engine: $ChannelPrefsTable.$converterenginen.fromJson(
        serializer.fromJson<String?>(json['engine']),
      ),
      aspect: $ChannelPrefsTable.$converteraspectn.fromJson(
        serializer.fromJson<String?>(json['aspect']),
      ),
      audioLang: serializer.fromJson<String?>(json['audioLang']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<int>(sourceId),
      'channelKey': serializer.toJson<String>(channelKey),
      'engine': serializer.toJson<String?>(
        $ChannelPrefsTable.$converterenginen.toJson(engine),
      ),
      'aspect': serializer.toJson<String?>(
        $ChannelPrefsTable.$converteraspectn.toJson(aspect),
      ),
      'audioLang': serializer.toJson<String?>(audioLang),
    };
  }

  ChannelPrefRecord copyWith({
    int? sourceId,
    String? channelKey,
    Value<EngineKind?> engine = const Value.absent(),
    Value<AspectMode?> aspect = const Value.absent(),
    Value<String?> audioLang = const Value.absent(),
  }) => ChannelPrefRecord(
    sourceId: sourceId ?? this.sourceId,
    channelKey: channelKey ?? this.channelKey,
    engine: engine.present ? engine.value : this.engine,
    aspect: aspect.present ? aspect.value : this.aspect,
    audioLang: audioLang.present ? audioLang.value : this.audioLang,
  );
  ChannelPrefRecord copyWithCompanion(ChannelPrefsCompanion data) {
    return ChannelPrefRecord(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      channelKey: data.channelKey.present
          ? data.channelKey.value
          : this.channelKey,
      engine: data.engine.present ? data.engine.value : this.engine,
      aspect: data.aspect.present ? data.aspect.value : this.aspect,
      audioLang: data.audioLang.present ? data.audioLang.value : this.audioLang,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChannelPrefRecord(')
          ..write('sourceId: $sourceId, ')
          ..write('channelKey: $channelKey, ')
          ..write('engine: $engine, ')
          ..write('aspect: $aspect, ')
          ..write('audioLang: $audioLang')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sourceId, channelKey, engine, aspect, audioLang);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChannelPrefRecord &&
          other.sourceId == this.sourceId &&
          other.channelKey == this.channelKey &&
          other.engine == this.engine &&
          other.aspect == this.aspect &&
          other.audioLang == this.audioLang);
}

class ChannelPrefsCompanion extends UpdateCompanion<ChannelPrefRecord> {
  final Value<int> sourceId;
  final Value<String> channelKey;
  final Value<EngineKind?> engine;
  final Value<AspectMode?> aspect;
  final Value<String?> audioLang;
  const ChannelPrefsCompanion({
    this.sourceId = const Value.absent(),
    this.channelKey = const Value.absent(),
    this.engine = const Value.absent(),
    this.aspect = const Value.absent(),
    this.audioLang = const Value.absent(),
  });
  ChannelPrefsCompanion.insert({
    required int sourceId,
    required String channelKey,
    this.engine = const Value.absent(),
    this.aspect = const Value.absent(),
    this.audioLang = const Value.absent(),
  }) : sourceId = Value(sourceId),
       channelKey = Value(channelKey);
  static Insertable<ChannelPrefRecord> custom({
    Expression<int>? sourceId,
    Expression<String>? channelKey,
    Expression<String>? engine,
    Expression<String>? aspect,
    Expression<String>? audioLang,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (channelKey != null) 'channel_key': channelKey,
      if (engine != null) 'engine': engine,
      if (aspect != null) 'aspect': aspect,
      if (audioLang != null) 'audio_lang': audioLang,
    });
  }

  ChannelPrefsCompanion copyWith({
    Value<int>? sourceId,
    Value<String>? channelKey,
    Value<EngineKind?>? engine,
    Value<AspectMode?>? aspect,
    Value<String?>? audioLang,
  }) {
    return ChannelPrefsCompanion(
      sourceId: sourceId ?? this.sourceId,
      channelKey: channelKey ?? this.channelKey,
      engine: engine ?? this.engine,
      aspect: aspect ?? this.aspect,
      audioLang: audioLang ?? this.audioLang,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (channelKey.present) {
      map['channel_key'] = Variable<String>(channelKey.value);
    }
    if (engine.present) {
      map['engine'] = Variable<String>(
        $ChannelPrefsTable.$converterenginen.toSql(engine.value),
      );
    }
    if (aspect.present) {
      map['aspect'] = Variable<String>(
        $ChannelPrefsTable.$converteraspectn.toSql(aspect.value),
      );
    }
    if (audioLang.present) {
      map['audio_lang'] = Variable<String>(audioLang.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChannelPrefsCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('channelKey: $channelKey, ')
          ..write('engine: $engine, ')
          ..write('aspect: $aspect, ')
          ..write('audioLang: $audioLang')
          ..write(')'))
        .toString();
  }
}

class $FavoritesTable extends Favorites
    with TableInfo<$FavoritesTable, FavoriteRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoritesTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sources (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<ContentKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ContentKind>($FavoritesTable.$converterkind);
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    kind,
    key,
    addedAt,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorites';
  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, kind, key};
  @override
  FavoriteRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoriteRecord(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_id'],
      )!,
      kind: $FavoritesTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $FavoritesTable createAlias(String alias) {
    return $FavoritesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ContentKind, String, String> $converterkind =
      const EnumNameConverter<ContentKind>(ContentKind.values);
}

class FavoriteRecord extends DataClass implements Insertable<FavoriteRecord> {
  final int sourceId;
  final ContentKind kind;
  final String key;
  final int addedAt;
  final int position;
  const FavoriteRecord({
    required this.sourceId,
    required this.kind,
    required this.key,
    required this.addedAt,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<int>(sourceId);
    {
      map['kind'] = Variable<String>(
        $FavoritesTable.$converterkind.toSql(kind),
      );
    }
    map['key'] = Variable<String>(key);
    map['added_at'] = Variable<int>(addedAt);
    map['position'] = Variable<int>(position);
    return map;
  }

  FavoritesCompanion toCompanion(bool nullToAbsent) {
    return FavoritesCompanion(
      sourceId: Value(sourceId),
      kind: Value(kind),
      key: Value(key),
      addedAt: Value(addedAt),
      position: Value(position),
    );
  }

  factory FavoriteRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoriteRecord(
      sourceId: serializer.fromJson<int>(json['sourceId']),
      kind: $FavoritesTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      key: serializer.fromJson<String>(json['key']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<int>(sourceId),
      'kind': serializer.toJson<String>(
        $FavoritesTable.$converterkind.toJson(kind),
      ),
      'key': serializer.toJson<String>(key),
      'addedAt': serializer.toJson<int>(addedAt),
      'position': serializer.toJson<int>(position),
    };
  }

  FavoriteRecord copyWith({
    int? sourceId,
    ContentKind? kind,
    String? key,
    int? addedAt,
    int? position,
  }) => FavoriteRecord(
    sourceId: sourceId ?? this.sourceId,
    kind: kind ?? this.kind,
    key: key ?? this.key,
    addedAt: addedAt ?? this.addedAt,
    position: position ?? this.position,
  );
  FavoriteRecord copyWithCompanion(FavoritesCompanion data) {
    return FavoriteRecord(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      kind: data.kind.present ? data.kind.value : this.kind,
      key: data.key.present ? data.key.value : this.key,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteRecord(')
          ..write('sourceId: $sourceId, ')
          ..write('kind: $kind, ')
          ..write('key: $key, ')
          ..write('addedAt: $addedAt, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sourceId, kind, key, addedAt, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteRecord &&
          other.sourceId == this.sourceId &&
          other.kind == this.kind &&
          other.key == this.key &&
          other.addedAt == this.addedAt &&
          other.position == this.position);
}

class FavoritesCompanion extends UpdateCompanion<FavoriteRecord> {
  final Value<int> sourceId;
  final Value<ContentKind> kind;
  final Value<String> key;
  final Value<int> addedAt;
  final Value<int> position;
  final Value<int> rowid;
  const FavoritesCompanion({
    this.sourceId = const Value.absent(),
    this.kind = const Value.absent(),
    this.key = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoritesCompanion.insert({
    required int sourceId,
    required ContentKind kind,
    required String key,
    required int addedAt,
    required int position,
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId),
       kind = Value(kind),
       key = Value(key),
       addedAt = Value(addedAt),
       position = Value(position);
  static Insertable<FavoriteRecord> custom({
    Expression<int>? sourceId,
    Expression<String>? kind,
    Expression<String>? key,
    Expression<int>? addedAt,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (kind != null) 'kind': kind,
      if (key != null) 'key': key,
      if (addedAt != null) 'added_at': addedAt,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoritesCompanion copyWith({
    Value<int>? sourceId,
    Value<ContentKind>? kind,
    Value<String>? key,
    Value<int>? addedAt,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return FavoritesCompanion(
      sourceId: sourceId ?? this.sourceId,
      kind: kind ?? this.kind,
      key: key ?? this.key,
      addedAt: addedAt ?? this.addedAt,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $FavoritesTable.$converterkind.toSql(kind.value),
      );
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoritesCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('kind: $kind, ')
          ..write('key: $key, ')
          ..write('addedAt: $addedAt, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChannelListsTable extends ChannelLists
    with TableInfo<$ChannelListsTable, ChannelListRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChannelListsTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sources (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourceId,
    name,
    position,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'channel_lists';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChannelListRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChannelListRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ChannelListsTable createAlias(String alias) {
    return $ChannelListsTable(attachedDatabase, alias);
  }
}

class ChannelListRecord extends DataClass
    implements Insertable<ChannelListRecord> {
  final int id;
  final int sourceId;

  /// Trimmed, never empty, unique per source (ignoring case).
  final String name;
  final int position;
  final int createdAt;
  const ChannelListRecord({
    required this.id,
    required this.sourceId,
    required this.name,
    required this.position,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['source_id'] = Variable<int>(sourceId);
    map['name'] = Variable<String>(name);
    map['position'] = Variable<int>(position);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ChannelListsCompanion toCompanion(bool nullToAbsent) {
    return ChannelListsCompanion(
      id: Value(id),
      sourceId: Value(sourceId),
      name: Value(name),
      position: Value(position),
      createdAt: Value(createdAt),
    );
  }

  factory ChannelListRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChannelListRecord(
      id: serializer.fromJson<int>(json['id']),
      sourceId: serializer.fromJson<int>(json['sourceId']),
      name: serializer.fromJson<String>(json['name']),
      position: serializer.fromJson<int>(json['position']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sourceId': serializer.toJson<int>(sourceId),
      'name': serializer.toJson<String>(name),
      'position': serializer.toJson<int>(position),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ChannelListRecord copyWith({
    int? id,
    int? sourceId,
    String? name,
    int? position,
    int? createdAt,
  }) => ChannelListRecord(
    id: id ?? this.id,
    sourceId: sourceId ?? this.sourceId,
    name: name ?? this.name,
    position: position ?? this.position,
    createdAt: createdAt ?? this.createdAt,
  );
  ChannelListRecord copyWithCompanion(ChannelListsCompanion data) {
    return ChannelListRecord(
      id: data.id.present ? data.id.value : this.id,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      name: data.name.present ? data.name.value : this.name,
      position: data.position.present ? data.position.value : this.position,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChannelListRecord(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('name: $name, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, sourceId, name, position, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChannelListRecord &&
          other.id == this.id &&
          other.sourceId == this.sourceId &&
          other.name == this.name &&
          other.position == this.position &&
          other.createdAt == this.createdAt);
}

class ChannelListsCompanion extends UpdateCompanion<ChannelListRecord> {
  final Value<int> id;
  final Value<int> sourceId;
  final Value<String> name;
  final Value<int> position;
  final Value<int> createdAt;
  const ChannelListsCompanion({
    this.id = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.name = const Value.absent(),
    this.position = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ChannelListsCompanion.insert({
    this.id = const Value.absent(),
    required int sourceId,
    required String name,
    required int position,
    required int createdAt,
  }) : sourceId = Value(sourceId),
       name = Value(name),
       position = Value(position),
       createdAt = Value(createdAt);
  static Insertable<ChannelListRecord> custom({
    Expression<int>? id,
    Expression<int>? sourceId,
    Expression<String>? name,
    Expression<int>? position,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceId != null) 'source_id': sourceId,
      if (name != null) 'name': name,
      if (position != null) 'position': position,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ChannelListsCompanion copyWith({
    Value<int>? id,
    Value<int>? sourceId,
    Value<String>? name,
    Value<int>? position,
    Value<int>? createdAt,
  }) {
    return ChannelListsCompanion(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      name: name ?? this.name,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChannelListsCompanion(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('name: $name, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ChannelListItemsTable extends ChannelListItems
    with TableInfo<$ChannelListItemsTable, ChannelListItemRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChannelListItemsTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> listId = GeneratedColumn<int>(
    'list_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES channel_lists (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [listId, key, position, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'channel_list_items';
  @override
  Set<GeneratedColumn> get $primaryKey => {listId, key};
  @override
  ChannelListItemRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChannelListItemRecord(
      listId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}list_id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $ChannelListItemsTable createAlias(String alias) {
    return $ChannelListItemsTable(attachedDatabase, alias);
  }
}

class ChannelListItemRecord extends DataClass
    implements Insertable<ChannelListItemRecord> {
  final int listId;
  final String key;

  /// Dense, from 0, per list.
  final int position;
  final int addedAt;
  const ChannelListItemRecord({
    required this.listId,
    required this.key,
    required this.position,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['list_id'] = Variable<int>(listId);
    map['key'] = Variable<String>(key);
    map['position'] = Variable<int>(position);
    map['added_at'] = Variable<int>(addedAt);
    return map;
  }

  ChannelListItemsCompanion toCompanion(bool nullToAbsent) {
    return ChannelListItemsCompanion(
      listId: Value(listId),
      key: Value(key),
      position: Value(position),
      addedAt: Value(addedAt),
    );
  }

  factory ChannelListItemRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChannelListItemRecord(
      listId: serializer.fromJson<int>(json['listId']),
      key: serializer.fromJson<String>(json['key']),
      position: serializer.fromJson<int>(json['position']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'listId': serializer.toJson<int>(listId),
      'key': serializer.toJson<String>(key),
      'position': serializer.toJson<int>(position),
      'addedAt': serializer.toJson<int>(addedAt),
    };
  }

  ChannelListItemRecord copyWith({
    int? listId,
    String? key,
    int? position,
    int? addedAt,
  }) => ChannelListItemRecord(
    listId: listId ?? this.listId,
    key: key ?? this.key,
    position: position ?? this.position,
    addedAt: addedAt ?? this.addedAt,
  );
  ChannelListItemRecord copyWithCompanion(ChannelListItemsCompanion data) {
    return ChannelListItemRecord(
      listId: data.listId.present ? data.listId.value : this.listId,
      key: data.key.present ? data.key.value : this.key,
      position: data.position.present ? data.position.value : this.position,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChannelListItemRecord(')
          ..write('listId: $listId, ')
          ..write('key: $key, ')
          ..write('position: $position, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(listId, key, position, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChannelListItemRecord &&
          other.listId == this.listId &&
          other.key == this.key &&
          other.position == this.position &&
          other.addedAt == this.addedAt);
}

class ChannelListItemsCompanion extends UpdateCompanion<ChannelListItemRecord> {
  final Value<int> listId;
  final Value<String> key;
  final Value<int> position;
  final Value<int> addedAt;
  final Value<int> rowid;
  const ChannelListItemsCompanion({
    this.listId = const Value.absent(),
    this.key = const Value.absent(),
    this.position = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChannelListItemsCompanion.insert({
    required int listId,
    required String key,
    required int position,
    required int addedAt,
    this.rowid = const Value.absent(),
  }) : listId = Value(listId),
       key = Value(key),
       position = Value(position),
       addedAt = Value(addedAt);
  static Insertable<ChannelListItemRecord> custom({
    Expression<int>? listId,
    Expression<String>? key,
    Expression<int>? position,
    Expression<int>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (listId != null) 'list_id': listId,
      if (key != null) 'key': key,
      if (position != null) 'position': position,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChannelListItemsCompanion copyWith({
    Value<int>? listId,
    Value<String>? key,
    Value<int>? position,
    Value<int>? addedAt,
    Value<int>? rowid,
  }) {
    return ChannelListItemsCompanion(
      listId: listId ?? this.listId,
      key: key ?? this.key,
      position: position ?? this.position,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (listId.present) {
      map['list_id'] = Variable<int>(listId.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChannelListItemsCompanion(')
          ..write('listId: $listId, ')
          ..write('key: $key, ')
          ..write('position: $position, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WatchProgressTable extends WatchProgress
    with TableInfo<$WatchProgressTable, WatchProgressRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchProgressTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sources (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<PlayableKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<PlayableKind>($WatchProgressTable.$converterkind);
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> seriesKey = GeneratedColumn<String>(
    'series_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
    'position_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<bool> finished = GeneratedColumn<bool>(
    'finished',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("finished" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    kind,
    key,
    seriesKey,
    positionMs,
    durationMs,
    updatedAt,
    finished,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watch_progress';
  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, kind, key};
  @override
  WatchProgressRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchProgressRecord(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_id'],
      )!,
      kind: $WatchProgressTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      seriesKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_key'],
      ),
      positionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_ms'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      finished: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}finished'],
      )!,
    );
  }

  @override
  $WatchProgressTable createAlias(String alias) {
    return $WatchProgressTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<PlayableKind, String, String> $converterkind =
      const EnumNameConverter<PlayableKind>(PlayableKind.values);
}

class WatchProgressRecord extends DataClass
    implements Insertable<WatchProgressRecord> {
  final int sourceId;

  /// [PlayableKind.movie] or [PlayableKind.episode].
  final PlayableKind kind;
  final String key;
  final String? seriesKey;
  final int positionMs;
  final int durationMs;
  final int updatedAt;
  final bool finished;
  const WatchProgressRecord({
    required this.sourceId,
    required this.kind,
    required this.key,
    this.seriesKey,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
    required this.finished,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<int>(sourceId);
    {
      map['kind'] = Variable<String>(
        $WatchProgressTable.$converterkind.toSql(kind),
      );
    }
    map['key'] = Variable<String>(key);
    if (!nullToAbsent || seriesKey != null) {
      map['series_key'] = Variable<String>(seriesKey);
    }
    map['position_ms'] = Variable<int>(positionMs);
    map['duration_ms'] = Variable<int>(durationMs);
    map['updated_at'] = Variable<int>(updatedAt);
    map['finished'] = Variable<bool>(finished);
    return map;
  }

  WatchProgressCompanion toCompanion(bool nullToAbsent) {
    return WatchProgressCompanion(
      sourceId: Value(sourceId),
      kind: Value(kind),
      key: Value(key),
      seriesKey: seriesKey == null && nullToAbsent
          ? const Value.absent()
          : Value(seriesKey),
      positionMs: Value(positionMs),
      durationMs: Value(durationMs),
      updatedAt: Value(updatedAt),
      finished: Value(finished),
    );
  }

  factory WatchProgressRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchProgressRecord(
      sourceId: serializer.fromJson<int>(json['sourceId']),
      kind: $WatchProgressTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      key: serializer.fromJson<String>(json['key']),
      seriesKey: serializer.fromJson<String?>(json['seriesKey']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      finished: serializer.fromJson<bool>(json['finished']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<int>(sourceId),
      'kind': serializer.toJson<String>(
        $WatchProgressTable.$converterkind.toJson(kind),
      ),
      'key': serializer.toJson<String>(key),
      'seriesKey': serializer.toJson<String?>(seriesKey),
      'positionMs': serializer.toJson<int>(positionMs),
      'durationMs': serializer.toJson<int>(durationMs),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'finished': serializer.toJson<bool>(finished),
    };
  }

  WatchProgressRecord copyWith({
    int? sourceId,
    PlayableKind? kind,
    String? key,
    Value<String?> seriesKey = const Value.absent(),
    int? positionMs,
    int? durationMs,
    int? updatedAt,
    bool? finished,
  }) => WatchProgressRecord(
    sourceId: sourceId ?? this.sourceId,
    kind: kind ?? this.kind,
    key: key ?? this.key,
    seriesKey: seriesKey.present ? seriesKey.value : this.seriesKey,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs ?? this.durationMs,
    updatedAt: updatedAt ?? this.updatedAt,
    finished: finished ?? this.finished,
  );
  WatchProgressRecord copyWithCompanion(WatchProgressCompanion data) {
    return WatchProgressRecord(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      kind: data.kind.present ? data.kind.value : this.kind,
      key: data.key.present ? data.key.value : this.key,
      seriesKey: data.seriesKey.present ? data.seriesKey.value : this.seriesKey,
      positionMs: data.positionMs.present
          ? data.positionMs.value
          : this.positionMs,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      finished: data.finished.present ? data.finished.value : this.finished,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchProgressRecord(')
          ..write('sourceId: $sourceId, ')
          ..write('kind: $kind, ')
          ..write('key: $key, ')
          ..write('seriesKey: $seriesKey, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('finished: $finished')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sourceId,
    kind,
    key,
    seriesKey,
    positionMs,
    durationMs,
    updatedAt,
    finished,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchProgressRecord &&
          other.sourceId == this.sourceId &&
          other.kind == this.kind &&
          other.key == this.key &&
          other.seriesKey == this.seriesKey &&
          other.positionMs == this.positionMs &&
          other.durationMs == this.durationMs &&
          other.updatedAt == this.updatedAt &&
          other.finished == this.finished);
}

class WatchProgressCompanion extends UpdateCompanion<WatchProgressRecord> {
  final Value<int> sourceId;
  final Value<PlayableKind> kind;
  final Value<String> key;
  final Value<String?> seriesKey;
  final Value<int> positionMs;
  final Value<int> durationMs;
  final Value<int> updatedAt;
  final Value<bool> finished;
  final Value<int> rowid;
  const WatchProgressCompanion({
    this.sourceId = const Value.absent(),
    this.kind = const Value.absent(),
    this.key = const Value.absent(),
    this.seriesKey = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.finished = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WatchProgressCompanion.insert({
    required int sourceId,
    required PlayableKind kind,
    required String key,
    this.seriesKey = const Value.absent(),
    required int positionMs,
    required int durationMs,
    required int updatedAt,
    this.finished = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId),
       kind = Value(kind),
       key = Value(key),
       positionMs = Value(positionMs),
       durationMs = Value(durationMs),
       updatedAt = Value(updatedAt);
  static Insertable<WatchProgressRecord> custom({
    Expression<int>? sourceId,
    Expression<String>? kind,
    Expression<String>? key,
    Expression<String>? seriesKey,
    Expression<int>? positionMs,
    Expression<int>? durationMs,
    Expression<int>? updatedAt,
    Expression<bool>? finished,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (kind != null) 'kind': kind,
      if (key != null) 'key': key,
      if (seriesKey != null) 'series_key': seriesKey,
      if (positionMs != null) 'position_ms': positionMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (finished != null) 'finished': finished,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WatchProgressCompanion copyWith({
    Value<int>? sourceId,
    Value<PlayableKind>? kind,
    Value<String>? key,
    Value<String?>? seriesKey,
    Value<int>? positionMs,
    Value<int>? durationMs,
    Value<int>? updatedAt,
    Value<bool>? finished,
    Value<int>? rowid,
  }) {
    return WatchProgressCompanion(
      sourceId: sourceId ?? this.sourceId,
      kind: kind ?? this.kind,
      key: key ?? this.key,
      seriesKey: seriesKey ?? this.seriesKey,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      updatedAt: updatedAt ?? this.updatedAt,
      finished: finished ?? this.finished,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $WatchProgressTable.$converterkind.toSql(kind.value),
      );
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (seriesKey.present) {
      map['series_key'] = Variable<String>(seriesKey.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (finished.present) {
      map['finished'] = Variable<bool>(finished.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchProgressCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('kind: $kind, ')
          ..write('key: $key, ')
          ..write('seriesKey: $seriesKey, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('finished: $finished, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecentChannelsTable extends RecentChannels
    with TableInfo<$RecentChannelsTable, RecentChannelRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecentChannelsTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sources (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> lastWatchedAt = GeneratedColumn<int>(
    'last_watched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [sourceId, key, lastWatchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recent_channels';
  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, key};
  @override
  RecentChannelRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecentChannelRecord(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      lastWatchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_watched_at'],
      )!,
    );
  }

  @override
  $RecentChannelsTable createAlias(String alias) {
    return $RecentChannelsTable(attachedDatabase, alias);
  }
}

class RecentChannelRecord extends DataClass
    implements Insertable<RecentChannelRecord> {
  final int sourceId;
  final String key;
  final int lastWatchedAt;
  const RecentChannelRecord({
    required this.sourceId,
    required this.key,
    required this.lastWatchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<int>(sourceId);
    map['key'] = Variable<String>(key);
    map['last_watched_at'] = Variable<int>(lastWatchedAt);
    return map;
  }

  RecentChannelsCompanion toCompanion(bool nullToAbsent) {
    return RecentChannelsCompanion(
      sourceId: Value(sourceId),
      key: Value(key),
      lastWatchedAt: Value(lastWatchedAt),
    );
  }

  factory RecentChannelRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecentChannelRecord(
      sourceId: serializer.fromJson<int>(json['sourceId']),
      key: serializer.fromJson<String>(json['key']),
      lastWatchedAt: serializer.fromJson<int>(json['lastWatchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<int>(sourceId),
      'key': serializer.toJson<String>(key),
      'lastWatchedAt': serializer.toJson<int>(lastWatchedAt),
    };
  }

  RecentChannelRecord copyWith({
    int? sourceId,
    String? key,
    int? lastWatchedAt,
  }) => RecentChannelRecord(
    sourceId: sourceId ?? this.sourceId,
    key: key ?? this.key,
    lastWatchedAt: lastWatchedAt ?? this.lastWatchedAt,
  );
  RecentChannelRecord copyWithCompanion(RecentChannelsCompanion data) {
    return RecentChannelRecord(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      key: data.key.present ? data.key.value : this.key,
      lastWatchedAt: data.lastWatchedAt.present
          ? data.lastWatchedAt.value
          : this.lastWatchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecentChannelRecord(')
          ..write('sourceId: $sourceId, ')
          ..write('key: $key, ')
          ..write('lastWatchedAt: $lastWatchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sourceId, key, lastWatchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecentChannelRecord &&
          other.sourceId == this.sourceId &&
          other.key == this.key &&
          other.lastWatchedAt == this.lastWatchedAt);
}

class RecentChannelsCompanion extends UpdateCompanion<RecentChannelRecord> {
  final Value<int> sourceId;
  final Value<String> key;
  final Value<int> lastWatchedAt;
  final Value<int> rowid;
  const RecentChannelsCompanion({
    this.sourceId = const Value.absent(),
    this.key = const Value.absent(),
    this.lastWatchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecentChannelsCompanion.insert({
    required int sourceId,
    required String key,
    required int lastWatchedAt,
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId),
       key = Value(key),
       lastWatchedAt = Value(lastWatchedAt);
  static Insertable<RecentChannelRecord> custom({
    Expression<int>? sourceId,
    Expression<String>? key,
    Expression<int>? lastWatchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (key != null) 'key': key,
      if (lastWatchedAt != null) 'last_watched_at': lastWatchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecentChannelsCompanion copyWith({
    Value<int>? sourceId,
    Value<String>? key,
    Value<int>? lastWatchedAt,
    Value<int>? rowid,
  }) {
    return RecentChannelsCompanion(
      sourceId: sourceId ?? this.sourceId,
      key: key ?? this.key,
      lastWatchedAt: lastWatchedAt ?? this.lastWatchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (lastWatchedAt.present) {
      map['last_watched_at'] = Variable<int>(lastWatchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecentChannelsCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('key: $key, ')
          ..write('lastWatchedAt: $lastWatchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRecord(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
}

class SettingRecord extends DataClass implements Insertable<SettingRecord> {
  final String key;
  final String json;
  const SettingRecord({required this.key, required this.json});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['json'] = Variable<String>(json);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), json: Value(json));
  }

  factory SettingRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRecord(
      key: serializer.fromJson<String>(json['key']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'json': serializer.toJson<String>(json),
    };
  }

  SettingRecord copyWith({String? key, String? json}) =>
      SettingRecord(key: key ?? this.key, json: json ?? this.json);
  SettingRecord copyWithCompanion(SettingsCompanion data) {
    return SettingRecord(
      key: data.key.present ? data.key.value : this.key,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRecord(')
          ..write('key: $key, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRecord &&
          other.key == this.key &&
          other.json == this.json);
}

class SettingsCompanion extends UpdateCompanion<SettingRecord> {
  final Value<String> key;
  final Value<String> json;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.json = const Value.absent(),
  });
  SettingsCompanion.insert({required String key, required String json})
    : key = Value(key),
      json = Value(json);
  static Insertable<SettingRecord> custom({
    Expression<String>? key,
    Expression<String>? json,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (json != null) 'json': json,
    });
  }

  SettingsCompanion copyWith({Value<String>? key, Value<String>? json}) {
    return SettingsCompanion(key: key ?? this.key, json: json ?? this.json);
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  late final $SourcesTable sources = $SourcesTable(this);
  late final $SecretsTable secrets = $SecretsTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $CategoryItemsTable categoryItems = $CategoryItemsTable(this);
  late final $ChannelsTable channels = $ChannelsTable(this);
  late final $MoviesTable movies = $MoviesTable(this);
  late final $SeriesTable series = $SeriesTable(this);
  late final $EpisodesTable episodes = $EpisodesTable(this);
  late final $DetailCacheTable detailCache = $DetailCacheTable(this);
  late final $EpgSourcesTable epgSources = $EpgSourcesTable(this);
  late final $EpgChannelsTable epgChannels = $EpgChannelsTable(this);
  late final $ProgrammesTable programmes = $ProgrammesTable(this);
  late final $ChannelEpgMapTable channelEpgMap = $ChannelEpgMapTable(this);
  late final $ChannelPrefsTable channelPrefs = $ChannelPrefsTable(this);
  late final $FavoritesTable favorites = $FavoritesTable(this);
  late final $ChannelListsTable channelLists = $ChannelListsTable(this);
  late final $ChannelListItemsTable channelListItems = $ChannelListItemsTable(
    this,
  );
  late final $WatchProgressTable watchProgress = $WatchProgressTable(this);
  late final $RecentChannelsTable recentChannels = $RecentChannelsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final Index categoryItemsItem = Index(
    'category_items_item',
    'CREATE INDEX category_items_item ON category_items (source_id, kind, item_key)',
  );
  late final Index channelsNum = Index(
    'channels_num',
    'CREATE INDEX channels_num ON channels (source_id, num, name_norm, "key")',
  );
  late final Index channelsTvgId = Index(
    'channels_tvg_id',
    'CREATE INDEX channels_tvg_id ON channels (tvg_id)',
  );
  late final Index moviesName = Index(
    'movies_name',
    'CREATE INDEX movies_name ON movies (source_id, name_norm, "key")',
  );
  late final Index seriesName = Index(
    'series_name',
    'CREATE INDEX series_name ON series (source_id, name_norm, "key")',
  );
  late final Index episodesSeries = Index(
    'episodes_series',
    'CREATE INDEX episodes_series ON episodes (source_id, series_key, season, number)',
  );
  late final Index epgSourcesUrl = Index(
    'epg_sources_url',
    'CREATE UNIQUE INDEX epg_sources_url ON epg_sources (source_id, url)',
  );
  late final Index channelEpgMapGuide = Index(
    'channel_epg_map_guide',
    'CREATE INDEX channel_epg_map_guide ON channel_epg_map (epg_source_id, xmltv_id)',
  );
  late final Index channelListsSource = Index(
    'channel_lists_source',
    'CREATE INDEX channel_lists_source ON channel_lists (source_id, position)',
  );
  late final Index watchProgressUpdated = Index(
    'watch_progress_updated',
    'CREATE INDEX watch_progress_updated ON watch_progress (source_id, updated_at)',
  );
  late final Index recentChannelsTime = Index(
    'recent_channels_time',
    'CREATE INDEX recent_channels_time ON recent_channels (source_id, last_watched_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sources,
    secrets,
    categories,
    categoryItems,
    channels,
    movies,
    series,
    episodes,
    detailCache,
    epgSources,
    epgChannels,
    programmes,
    channelEpgMap,
    channelPrefs,
    favorites,
    channelLists,
    channelListItems,
    watchProgress,
    recentChannels,
    settings,
    categoryItemsItem,
    channelsNum,
    channelsTvgId,
    moviesName,
    seriesName,
    episodesSeries,
    epgSourcesUrl,
    channelEpgMapGuide,
    channelListsSource,
    watchProgressUpdated,
    recentChannelsTime,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('secrets', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('categories', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('category_items', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('channels', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('movies', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('series', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('episodes', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('detail_cache', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('epg_sources', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'epg_sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('epg_channels', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'epg_sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('programmes', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('channel_epg_map', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'epg_sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('channel_epg_map', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('channel_prefs', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('favorites', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('channel_lists', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'channel_lists',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('channel_list_items', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('watch_progress', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('recent_channels', kind: UpdateKind.delete)],
    ),
  ]);
}
