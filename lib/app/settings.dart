import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/app_db.dart';
import '../core/platform/device_caps.dart';
import '../player/engine/engine_factory.dart';
import '../player/engine/mpv_engine.dart' show kDefaultPreferredLanguages;
import '../player/engine/player_engine.dart';
import 'form_factor.dart';
import 'providers.dart';

/// Settings key holding the JSON of [AppSettings].
const kAppSettingsKey = 'app_settings';

/// UI language choice. [auto] follows the device.
enum AppLocaleSetting {
  auto,
  ar,
  en;

  /// The forced locale, or null to follow the device.
  Locale? get locale => switch (this) {
    auto => null,
    ar => const Locale('ar'),
    en => const Locale('en'),
  };
}

/// Lite mode override. [auto] uses `DeviceCaps.lite`.
enum LiteSetting { auto, on, off }

/// Player engine choice per content type. [auto] uses the engine policy.
enum EngineSetting {
  auto,
  exo,
  mpv;

  /// The forced engine, or null for the policy default.
  EngineKind? get kind => switch (this) {
    auto => null,
    exo => EngineKind.exo,
    mpv => EngineKind.mpv,
  };
}

/// How ExoPlayer draws video on Android.
enum ExoViewType {
  texture,
  platform;

  VideoViewType get viewType => switch (this) {
    texture => VideoViewType.textureView,
    platform => VideoViewType.platformView,
  };
}

/// App-wide preferences, stored as one JSON object under [kAppSettingsKey].
///
/// [AppSettings.fromJson] tolerates missing, mistyped and unknown keys (and
/// unknown enum names), so older or newer app versions never lose the rest.
@immutable
class AppSettings {
  const AppSettings({
    this.locale = AppLocaleSetting.auto,
    this.formFactor = FormFactorOverride.auto,
    this.lite = LiteSetting.auto,
    this.liveEngine = EngineSetting.auto,
    this.vodEngine = EngineSetting.auto,
    this.exoView = ExoViewType.texture,
    this.hwdec = true,
    this.preferredAudioLang = 'ar',
    this.preferredSubLang = 'ar',
    this.defaultAspect = AspectMode.fit,
    this.epgRefreshHours = 12,
  });

  factory AppSettings.fromJson(Object? json) {
    const d = AppSettings();
    if (json is! Map) return d;
    T pick<T extends Enum>(List<T> values, String key, T fallback) {
      final raw = json[key];
      return values.where((v) => v.name == raw).firstOrNull ?? fallback;
    }

    return AppSettings(
      locale: pick(AppLocaleSetting.values, 'locale', d.locale),
      formFactor: pick(FormFactorOverride.values, 'formFactor', d.formFactor),
      lite: pick(LiteSetting.values, 'lite', d.lite),
      liveEngine: pick(EngineSetting.values, 'liveEngine', d.liveEngine),
      vodEngine: pick(EngineSetting.values, 'vodEngine', d.vodEngine),
      exoView: pick(ExoViewType.values, 'exoView', d.exoView),
      hwdec: _bool(json['hwdec']) ?? d.hwdec,
      preferredAudioLang:
          _lang(json['preferredAudioLang']) ?? d.preferredAudioLang,
      preferredSubLang: _lang(json['preferredSubLang']) ?? d.preferredSubLang,
      defaultAspect: pick(AspectMode.values, 'defaultAspect', d.defaultAspect),
      epgRefreshHours:
          _int(json['epgRefreshHours'])
              ?.clamp(minEpgRefreshHours, maxEpgRefreshHours) ??
          d.epgRefreshHours,
    );
  }

  static const minEpgRefreshHours = 1;
  static const maxEpgRefreshHours = 168;

  final AppLocaleSetting locale;
  final FormFactorOverride formFactor;
  final LiteSetting lite;
  final EngineSetting liveEngine;
  final EngineSetting vodEngine;
  final ExoViewType exoView;

  /// Hardware decoding for mpv.
  final bool hwdec;

  /// ISO 639-1 code, e.g. `ar`.
  final String preferredAudioLang;
  final String preferredSubLang;
  final AspectMode defaultAspect;

  /// How often the guide is refreshed in the background.
  final int epgRefreshHours;

  Map<String, Object?> toJson() => {
    'locale': locale.name,
    'formFactor': formFactor.name,
    'lite': lite.name,
    'liveEngine': liveEngine.name,
    'vodEngine': vodEngine.name,
    'exoView': exoView.name,
    'hwdec': hwdec,
    'preferredAudioLang': preferredAudioLang,
    'preferredSubLang': preferredSubLang,
    'defaultAspect': defaultAspect.name,
    'epgRefreshHours': epgRefreshHours,
  };

  AppSettings copyWith({
    AppLocaleSetting? locale,
    FormFactorOverride? formFactor,
    LiteSetting? lite,
    EngineSetting? liveEngine,
    EngineSetting? vodEngine,
    ExoViewType? exoView,
    bool? hwdec,
    String? preferredAudioLang,
    String? preferredSubLang,
    AspectMode? defaultAspect,
    int? epgRefreshHours,
  }) => AppSettings(
    locale: locale ?? this.locale,
    formFactor: formFactor ?? this.formFactor,
    lite: lite ?? this.lite,
    liveEngine: liveEngine ?? this.liveEngine,
    vodEngine: vodEngine ?? this.vodEngine,
    exoView: exoView ?? this.exoView,
    hwdec: hwdec ?? this.hwdec,
    preferredAudioLang: preferredAudioLang ?? this.preferredAudioLang,
    preferredSubLang: preferredSubLang ?? this.preferredSubLang,
    defaultAspect: defaultAspect ?? this.defaultAspect,
    epgRefreshHours: epgRefreshHours ?? this.epgRefreshHours,
  );

  /// Engine options for the player, given whether Lite mode is in effect.
  EngineOptions engineOptions({required bool lite}) => EngineOptions(
    lite: lite,
    hardwareDecoding: hwdec,
    exoViewType: exoView.viewType,
    preferredLanguages: preferredLanguagesFor(preferredAudioLang),
    subtitleLanguages: preferredLanguagesFor(preferredSubLang),
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.locale == locale &&
      other.formFactor == formFactor &&
      other.lite == lite &&
      other.liveEngine == liveEngine &&
      other.vodEngine == vodEngine &&
      other.exoView == exoView &&
      other.hwdec == hwdec &&
      other.preferredAudioLang == preferredAudioLang &&
      other.preferredSubLang == preferredSubLang &&
      other.defaultAspect == defaultAspect &&
      other.epgRefreshHours == epgRefreshHours;

  @override
  int get hashCode => Object.hash(
    locale,
    formFactor,
    lite,
    liveEngine,
    vodEngine,
    exoView,
    hwdec,
    preferredAudioLang,
    preferredSubLang,
    defaultAspect,
    epgRefreshHours,
  );

  @override
  String toString() => 'AppSettings(${toJson()})';
}

/// Whether Lite mode is in effect: the Settings override, else the device.
bool effectiveLite(DeviceCaps caps, AppSettings settings) =>
    switch (settings.lite) {
      LiteSetting.on => true,
      LiteSetting.off => false,
      LiteSetting.auto => caps.lite,
    };

const _iso639_2 = {'ar': 'ara', 'en': 'eng', 'fr': 'fre', 'tr': 'tur'};

/// mpv `alang`/`slang` list for a preferred ISO 639-1 code: the three-letter
/// code, the code itself, then English (or Arabic when English is preferred).
List<String> preferredLanguagesFor(String lang) {
  final code = lang.trim().toLowerCase();
  if (code.isEmpty) return kDefaultPreferredLanguages;
  final fallback = code == 'en' ? 'ar' : 'en';
  return [?_iso639_2[code], code, fallback];
}

/// Reads saved settings; defaults when missing or unreadable.
Future<AppSettings> loadAppSettings(SettingsDao dao) async =>
    AppSettings.fromJson(await dao.getJson(kAppSettingsKey));

/// Holds [AppSettings] and saves every change through [SettingsDao].
///
/// The first state comes from [initialSettingsProvider] (read from the
/// database at bootstrap). Writes are queued in order; [flush] waits for them.
class SettingsController extends Notifier<AppSettings> {
  Future<void> _pending = Future.value();

  @override
  AppSettings build() => ref.watch(initialSettingsProvider);

  /// Applies [change] and persists the result.
  Future<void> update(AppSettings Function(AppSettings current) change) {
    final next = change(state);
    if (next == state) return _pending;
    state = next;
    final dao = ref.read(settingsDaoProvider);
    final log = ref.read(ringLogProvider);
    final json = next.toJson();
    return _pending = _pending.then((_) async {
      try {
        await dao.setJson(kAppSettingsKey, json);
      } on Object catch (e, st) {
        log.error('Saving settings failed', e, st);
      }
    });
  }

  /// Completes when every queued write has finished.
  Future<void> flush() => _pending;

  Future<void> setLocale(AppLocaleSetting v) =>
      update((s) => s.copyWith(locale: v));

  Future<void> setFormFactor(FormFactorOverride v) =>
      update((s) => s.copyWith(formFactor: v));

  Future<void> setLite(LiteSetting v) => update((s) => s.copyWith(lite: v));

  Future<void> setLiveEngine(EngineSetting v) =>
      update((s) => s.copyWith(liveEngine: v));

  Future<void> setVodEngine(EngineSetting v) =>
      update((s) => s.copyWith(vodEngine: v));

  Future<void> setExoView(ExoViewType v) =>
      update((s) => s.copyWith(exoView: v));

  Future<void> setHwdec(bool v) => update((s) => s.copyWith(hwdec: v));

  Future<void> setPreferredAudioLang(String v) =>
      update((s) => s.copyWith(preferredAudioLang: v));

  Future<void> setPreferredSubLang(String v) =>
      update((s) => s.copyWith(preferredSubLang: v));

  Future<void> setDefaultAspect(AspectMode v) =>
      update((s) => s.copyWith(defaultAspect: v));

  Future<void> setEpgRefreshHours(int v) => update(
    (s) => s.copyWith(
      epgRefreshHours: v.clamp(
        AppSettings.minEpgRefreshHours,
        AppSettings.maxEpgRefreshHours,
      ),
    ),
  );
}

bool? _bool(Object? v) => switch (v) {
  final bool b => b,
  final num n => n != 0,
  'true' || '1' => true,
  'false' || '0' => false,
  _ => null,
};

int? _int(Object? v) => switch (v) {
  final int i => i,
  final double d when d.isFinite => d.round(),
  final String s => int.tryParse(s.trim()),
  _ => null,
};

String? _lang(Object? v) {
  if (v is! String) return null;
  final s = v.trim().toLowerCase();
  return RegExp(r'^[a-z]{2,3}$').hasMatch(s) ? s : null;
}
