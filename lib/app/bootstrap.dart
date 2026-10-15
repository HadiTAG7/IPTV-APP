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
import '../core/text/western_digits.dart';
import '../features/help/licenses.dart';
import '../player/player_providers.dart';
import '../tv/dpad_shortcuts.dart';
import '../widgets/logo_image.dart';
import 'app.dart';
import 'form_factor.dart';
import 'providers.dart';
import 'wiring.dart';

/// Starts the app: error hooks into [RingLog], Western digits in Arabic,
/// the bundled font licence, media_kit, the database, device caps and saved
/// settings, then [IptvApp] in a [ProviderScope] (with [appWiring]).
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final log = RingLog.instance;
  installErrorHooks(log);
  setUpAppGlobals();

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
  final online = StreamController<bool>.broadcast();
  _watchConnectivity(log, online);

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceCapsProvider.overrideWithValue(caps),
        initialSettingsProvider.overrideWithValue(settings),
        ringLogProvider.overrideWithValue(log),
        playerOnlineProvider.overrideWithValue(online.stream),
        ...appWiring(),
      ],
      child: const IptvApp(),
    ),
  );
}

/// Process-wide setup: Western digits in Arabic dates ([useWesternDigits])
/// and the bundled font's licence on the licences page
/// ([registerFontLicenses]). Safe to call more than once.
void setUpAppGlobals() {
  useWesternDigits();
  registerFontLicenses();
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

/// Retries failed logos once the network comes back, and tells [online]
/// (the player's reconnect watchdog waits while offline).
void _watchConnectivity(RingLog log, StreamController<bool> online) {
  try {
    Connectivity().onConnectivityChanged.listen((results) {
      if (results.isEmpty) return; // Unknown: keep the last state.
      final up = results.any((r) => r != ConnectivityResult.none);
      if (up) FailedImageCache.clearTransient();
      online.add(up);
    }, onError: (Object e) => log.warn('Connectivity: $e'));
  } on Object catch (e) {
    log.warn('Connectivity unavailable: $e');
  }
}
