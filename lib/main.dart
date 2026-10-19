import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app/bootstrap.dart';
import 'player/detach/viewer_app.dart';
import 'player/detach/viewer_protocol.dart';

Future<void> main(List<String> args) => startApp(args);

/// Runs the app ([bootstrap]), or a detached window's viewer ([runViewer])
/// when [args] start with the viewer flag (see [ViewerLaunchArgs]). A
/// viewer command line without a valid port and token ends the process
/// ([onInvalid]): it must never start a second full app on the database.
@visibleForTesting
Future<void> startApp(
  List<String> args, {
  Future<void> Function() app = bootstrap,
  Future<void> Function(ViewerLaunchArgs args) viewer = runViewer,
  Future<void> Function() onInvalid = _exitInvalid,
}) {
  if (!ViewerLaunchArgs.isViewer(args)) return app();
  final ViewerLaunchArgs parsed;
  try {
    parsed = ViewerLaunchArgs.parse(args);
  } on FormatException {
    return onInvalid();
  }
  return viewer(parsed);
}

Future<void> _exitInvalid() async => exit(64);
