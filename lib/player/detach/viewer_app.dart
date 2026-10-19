// The viewer process: a detached window playing one live channel.
//
// Started by the app with `--viewer` (see [ViewerLaunchArgs]); it needs no
// database, sync or settings: everything comes over the loopback
// connection to the app ([ViewerChannel]).
import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../../app/bootstrap.dart' show installErrorHooks, setUpAppGlobals;
import '../../core/log/ring_log.dart';
import '../../core/platform/window_controls.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../player_providers.dart' show playerWakelock;
import 'viewer_protocol.dart';
import 'viewer_screen.dart';

/// Runs the viewer: connects to the app, says hello with the token and
/// shows [ViewerScreen]. Ends the process when the app cannot be reached.
Future<void> runViewer(ViewerLaunchArgs args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final log = RingLog.instance;
  installErrorHooks(log);
  setUpAppGlobals();
  try {
    MediaKit.ensureInitialized();
  } on Object catch (e, st) {
    log.error('media_kit unavailable', e, st);
  }

  final ViewerChannel channel;
  try {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      args.port,
      timeout: const Duration(seconds: 10),
    );
    channel = SocketViewerChannel(
      socket,
      acceptFromViewer: false,
      onMalformed: (reason) => log.warn('Viewer: $reason ignored'),
    );
  } on Object catch (e) {
    log.warn('Viewer: the app cannot be reached (${e.runtimeType})');
    await exitViewerProcess();
    return;
  }
  channel.send(HelloMessage(token: args.token));

  final platform = defaultTargetPlatform;
  runApp(
    ViewerApp(
      locale: Locale(args.locale),
      home: ViewerScreen(
        channel: channel,
        window: WindowControls.native(platform: platform, onError: log.warn),
        exitProcess: exitViewerProcess,
        platform: platform,
        wakelock: playerWakelock(log),
        log: log,
      ),
    ),
  );
}

/// Ends the viewer process through the embedder (a clean shutdown), and
/// hard if that did not happen within a few seconds.
Future<void> exitViewerProcess() async {
  Timer(const Duration(seconds: 3), () => exit(0));
  try {
    await ServicesBinding.instance.exitApplication(AppExitType.required);
  } on Object catch (_) {
    exit(0);
  }
}

/// The viewer's app: the app's dark theme, Arabic (right to left) or
/// English as the app that opened it.
class ViewerApp extends StatelessWidget {
  const ViewerApp({super.key, required this.locale, required this.home});

  final Locale locale;
  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
    theme: AppTheme.dark(),
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: home,
  );
}
