import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_db.dart';

/// Well-known setting keys owned by the data layer.
abstract final class SettingKeys {
  /// Int id of the source the UI shows.
  static const activeSourceId = 'activeSourceId';
}

/// Key/value settings stored as JSON text.
class SettingsDao extends DatabaseAccessor<AppDatabase> {
  SettingsDao(super.attachedDatabase);

  SimpleSelectStatement<$SettingsTable, SettingRecord> _byKey(String key) =>
      select(db.settings)..where((s) => s.key.equals(key));

  /// Decoded JSON value, or null when missing or unreadable.
  Future<Object?> getJson(String key) async =>
      _decode((await _byKey(key).getSingleOrNull())?.json);

  /// Stores [value] as JSON; null removes the key.
  Future<void> setJson(String key, Object? value) async {
    if (value == null) return remove(key);
    await into(db.settings).insertOnConflictUpdate(
      SettingsCompanion.insert(key: key, json: jsonEncode(value)),
    );
  }

  Stream<Object?> watchJson(String key) =>
      _byKey(key)
          .watchSingleOrNull()
          .map((r) => r?.json)
          .distinct()
          .map(_decode);

  Future<void> remove(String key) =>
      (delete(db.settings)..where((s) => s.key.equals(key))).go();

  Future<String?> getString(String key) async => _asString(await getJson(key));

  Future<int?> getInt(String key) async => _asInt(await getJson(key));

  Future<bool?> getBool(String key) async => _asBool(await getJson(key));

  Future<void> setString(String key, String? value) => setJson(key, value);

  Future<void> setInt(String key, int? value) => setJson(key, value);

  Future<void> setBool(String key, bool? value) => setJson(key, value);

  Stream<String?> watchString(String key) => watchJson(key).map(_asString);

  Stream<int?> watchInt(String key) => watchJson(key).map(_asInt);

  Stream<bool?> watchBool(String key) => watchJson(key).map(_asBool);
}

Object? _decode(String? json) {
  if (json == null) return null;
  try {
    return jsonDecode(json);
  } on FormatException {
    return null;
  }
}

String? _asString(Object? v) => v is String ? v : null;

int? _asInt(Object? v) => switch (v) {
  final int i => i,
  final double d when d == d.truncateToDouble() => d.toInt(),
  _ => null,
};

bool? _asBool(Object? v) => v is bool ? v : null;
