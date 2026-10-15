import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'engine_ab_test.dart';

/// `version+build` of the installed app (package_info_plus).
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.buildNumber.isEmpty
      ? info.version
      : '${info.version}+${info.buildNumber}';
}, name: 'appVersionProvider');

/// The public test streams of the engine A/B test.
final diagnosticsTestStreamsProvider = Provider<List<DiagnosticsTestStream>>(
  (ref) => kDiagnosticsTestStreams,
  name: 'diagnosticsTestStreamsProvider',
);

/// How long one engine may take to show the first frame of a test stream.
final diagnosticsTestTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 20),
  name: 'diagnosticsTestTimeoutProvider',
);
