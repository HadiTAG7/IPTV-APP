import 'dart:async';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../core/db/app_db.dart';
import '../core/log/ring_log.dart';
import '../core/platform/device_caps.dart';
import '../tv/dpad_shortcuts.dart';
import '../widgets/logo_image.dart';
import 'app.dart';
import 'form_factor.dart';
import 'providers.dart';

/// Starts the app: error hooks into [RingLog], media_kit, the database,
/// device caps and saved settings, then [IptvApp] in a [ProviderScope].
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final log = RingLog.instance;
  installErrorHooks(log);

  try {
    MediaKit.ensureInitialized();
  } on Object catch (e, st) {
    // Missing native libraries must not stop the app; Exo still works.
    log.error('media_kit unavailable', e, st);
  }

  final db = AppDatabase.open();
  final caps = await DeviceCaps.load();
  log.info('Device: $caps');

  var settings = const AppSettings();
  try {
    settings = await loadAppSettings(db.settingsDao);
  } on Object catch (e, st) {
    log.error('Reading settings failed; using defaults', e, st);
  }

  final tv =
      resolveFormFactor(
        caps,
        settings.formFactor,
        Size.zero,
        defaultTargetPlatform,
      ) ==
      FormFactor.tv;
  applyFocusHighlightStrategy(tv: tv);
  _watchConnectivity(log);

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceCapsProvider.overrideWithValue(caps),
        initialSettingsProvider.overrideWithValue(settings),
        ringLogProvider.overrideWithValue(log),
      ],
      child: const IptvApp(),
    ),
  );
}

/// Sends framework and uncaught async errors to [log] (redacted there).
void installErrorHooks(RingLog log) {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    log.error(
      'Flutter: ${details.context ?? ''}',
      details.exception,
      details.stack,
    );
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    log.error('Uncaught', error, stack);
    return true;
  };
}

/// Retries failed logos once the network comes back.
void _watchConnectivity(RingLog log) {
  try {
    Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        FailedImageCache.clearTransient();
      }
    }, onError: (Object e) => log.warn('Connectivity: $e'));
  } on Object catch (e) {
    log.warn('Connectivity unavailable: $e');
  }
}
