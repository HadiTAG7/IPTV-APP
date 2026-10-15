import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/form_factor.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/platform/device_caps.dart';
import 'package:iptv_player/player/engine/engine_factory.dart';
import 'package:iptv_player/player/engine/mpv_engine.dart';
import 'package:iptv_player/player/engine/player_engine.dart';

void main() {
  group('AppSettings JSON', () {
    test('defaults', () {
      const s = AppSettings();
      expect(s.locale, AppLocaleSetting.auto);
      expect(s.formFactor, FormFactorOverride.auto);
      expect(s.lite, LiteSetting.auto);
      expect(s.liveEngine, EngineSetting.auto);
      expect(s.vodEngine, EngineSetting.auto);
      expect(s.exoView, ExoViewType.texture);
      expect(s.hwdec, isTrue);
      expect(s.preferredAudioLang, 'ar');
      expect(s.preferredSubLang, 'ar');
      expect(s.defaultAspect, AspectMode.fit);
      expect(s.epgRefreshHours, 12);
    });

    test('round-trips every field through JSON text', () {
      const s = AppSettings(
        locale: AppLocaleSetting.en,
        formFactor: FormFactorOverride.tv,
        lite: LiteSetting.on,
        liveEngine: EngineSetting.mpv,
        vodEngine: EngineSetting.exo,
        exoView: ExoViewType.platform,
        hwdec: false,
        preferredAudioLang: 'en',
        preferredSubLang: 'fr',
        defaultAspect: AspectMode.ratio16x9,
        epgRefreshHours: 6,
      );
      final decoded = AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(decoded, s);
      expect(decoded.hashCode, s.hashCode);
      expect(AppSettings.fromJson(const AppSettings().toJson()), isNot(s));
    });

    test('missing, unknown and mistyped keys fall back per field', () {
      final s = AppSettings.fromJson({
        'locale': 'ar',
        'formFactor': 'watch', // unknown enum name
        'lite': 42, // wrong type
        'liveEngine': 'exo',
        'hwdec': 'false',
        'preferredAudioLang': '  EN ',
        'preferredSubLang': 'not a language',
        'defaultAspect': null,
        'epgRefreshHours': 1000, // clamped
        'futureFeature': {'nested': true}, // ignored
      });
      expect(s.locale, AppLocaleSetting.ar);
      expect(s.formFactor, FormFactorOverride.auto);
      expect(s.lite, LiteSetting.auto);
      expect(s.liveEngine, EngineSetting.exo);
      expect(s.vodEngine, EngineSetting.auto);
      expect(s.hwdec, isFalse);
      expect(s.preferredAudioLang, 'en');
      expect(s.preferredSubLang, 'ar');
      expect(s.defaultAspect, AspectMode.fit);
      expect(s.epgRefreshHours, AppSettings.maxEpgRefreshHours);
      expect(AppSettings.fromJson({'epgRefreshHours': 0}).epgRefreshHours, 1);
      expect(AppSettings.fromJson({'epgRefreshHours': 3.4}).epgRefreshHours, 3);
    });

    test('non-map JSON gives defaults', () {
      for (final json in <Object?>[null, 'x', 3, <Object?>[], true]) {
        expect(AppSettings.fromJson(json), const AppSettings());
      }
    });

    test('enum helpers', () {
      expect(AppLocaleSetting.auto.locale, isNull);
      expect(AppLocaleSetting.ar.locale?.languageCode, 'ar');
      expect(EngineSetting.auto.kind, isNull);
      expect(EngineSetting.mpv.kind, EngineKind.mpv);
      expect(ExoViewType.platform.viewType, VideoViewType.platformView);
      expect(preferredLanguagesFor('ar'), ['ara', 'ar', 'en']);
      expect(preferredLanguagesFor('en'), ['eng', 'en', 'ar']);
      expect(preferredLanguagesFor('de'), ['de', 'en']);
      final options = const AppSettings(
        hwdec: false,
        exoView: ExoViewType.platform,
      ).engineOptions(lite: true);
      expect(options.lite, isTrue);
      expect(options.hardwareDecoding, isFalse);
      expect(options.exoViewType, VideoViewType.platformView);
    });

    test('audio and subtitle languages reach mpv separately', () {
      final options = const AppSettings(
        preferredAudioLang: 'en',
        preferredSubLang: 'ar',
      ).engineOptions(lite: false);
      expect(options.preferredLanguages, ['eng', 'en', 'ar']);
      expect(options.subtitleLanguages, ['ara', 'ar', 'en']);
      expect(
        mpvLanguageProperties(
          options.preferredLanguages,
          options.subtitleLanguages,
        ),
        {'alang': 'eng,en,ar', 'slang': 'ara,ar,en'},
      );
      // Without a separate list both follow the audio order.
      expect(mpvLanguageProperties(const ['ara', 'ar'], null), {
        'alang': 'ara,ar',
        'slang': 'ara,ar',
      });
      expect(const EngineOptions().subtitleLanguages, isNull);
    });
  });

  test('effectiveLite: override wins, auto follows the device', () {
    const small = DeviceCaps(totalRamMb: 1536);
    const big = DeviceCaps(totalRamMb: 4096);
    expect(effectiveLite(small, const AppSettings()), isTrue);
    expect(effectiveLite(big, const AppSettings()), isFalse);
    expect(effectiveLite(big, const AppSettings(lite: LiteSetting.on)), isTrue);
    expect(
      effectiveLite(small, const AppSettings(lite: LiteSetting.off)),
      isFalse,
    );
  });

  group('SettingsController', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          initialSettingsProvider.overrideWithValue(
            const AppSettings(locale: AppLocaleSetting.ar),
          ),
          deviceCapsProvider.overrideWithValue(
            const DeviceCaps(totalRamMb: 1024),
          ),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('starts from the bootstrap value and persists each change', () async {
      expect(container.read(settingsProvider).locale, AppLocaleSetting.ar);
      final controller = container.read(settingsProvider.notifier);
      await controller.setLocale(AppLocaleSetting.en);
      await controller.setHwdec(false);
      await controller.setEpgRefreshHours(500);
      expect(container.read(settingsProvider).locale, AppLocaleSetting.en);
      expect(
        container.read(settingsProvider).epgRefreshHours,
        AppSettings.maxEpgRefreshHours,
      );

      final saved = await loadAppSettings(db.settingsDao);
      expect(saved, container.read(settingsProvider));
      expect(saved.hwdec, isFalse);
      expect(
        await db.settingsDao.getJson(kAppSettingsKey),
        isA<Map<String, Object?>>(),
      );
    });

    test('rapid changes are saved in order', () async {
      final controller = container.read(settingsProvider.notifier);
      for (final aspect in AspectMode.values) {
        unawaited(controller.setDefaultAspect(aspect));
      }
      await controller.flush();
      final saved = await loadAppSettings(db.settingsDao);
      expect(saved.defaultAspect, AspectMode.values.last);
    });

    test('lite mode and engine options follow settings', () async {
      expect(container.read(liteModeProvider), isTrue);
      await container.read(settingsProvider.notifier).setLite(LiteSetting.off);
      expect(container.read(liteModeProvider), isFalse);
      expect(container.read(engineOptionsProvider).lite, isFalse);
    });

    test('loadAppSettings tolerates a corrupt row', () async {
      await db.customStatement(
        "INSERT INTO settings (key, json) VALUES ('app_settings', '{oops')",
      );
      expect(await loadAppSettings(db.settingsDao), const AppSettings());
    });
  });
}
