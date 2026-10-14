import 'package:drift/drift.dart';

import '../../../player/engine/player_engine.dart';
import '../app_db.dart';

/// Per-channel player choices (engine, aspect ratio, audio language).
class PrefsDao extends DatabaseAccessor<AppDatabase> {
  PrefsDao(super.attachedDatabase);

  SimpleSelectStatement<$ChannelPrefsTable, ChannelPrefRecord> _byKey(
    int sourceId,
    String channelKey,
  ) => select(db.channelPrefs)
    ..where(
      (p) => p.sourceId.equals(sourceId) & p.channelKey.equals(channelKey),
    );

  /// Stored prefs, or [ChannelPrefsData.empty].
  Future<ChannelPrefsData> prefsFor(int sourceId, String channelKey) async {
    final r = await _byKey(sourceId, channelKey).getSingleOrNull();
    return r == null
        ? ChannelPrefsData.empty
        : ChannelPrefsData(
            engine: r.engine,
            aspect: r.aspect,
            audioLang: r.audioLang,
          );
  }

  /// Engine to use for this channel (learned or manual); null clears.
  Future<void> setEngine(int sourceId, String channelKey, EngineKind? engine) =>
      _upsert(
        sourceId,
        channelKey,
        ChannelPrefsCompanion(engine: Value(engine)),
      );

  Future<void> setAspect(int sourceId, String channelKey, AspectMode? aspect) =>
      _upsert(
        sourceId,
        channelKey,
        ChannelPrefsCompanion(aspect: Value(aspect)),
      );

  Future<void> setAudioLang(int sourceId, String channelKey, String? lang) =>
      _upsert(
        sourceId,
        channelKey,
        ChannelPrefsCompanion(audioLang: Value(lang)),
      );

  Future<void> clearPrefs(int sourceId, String channelKey) =>
      (delete(db.channelPrefs)..where(
            (p) =>
                p.sourceId.equals(sourceId) & p.channelKey.equals(channelKey),
          ))
          .go();

  Future<void> _upsert(
    int sourceId,
    String channelKey,
    ChannelPrefsCompanion values,
  ) => into(db.channelPrefs).insert(
    values.copyWith(sourceId: Value(sourceId), channelKey: Value(channelKey)),
    onConflict: DoUpdate((_) => values),
  );
}
