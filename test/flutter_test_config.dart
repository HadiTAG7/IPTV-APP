import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/text/western_digits.dart';

/// Loads the bundled Tajawal font so widget and golden tests render real
/// Arabic and Latin glyphs instead of the Ahem test font boxes, and sets up
/// Western digits in Arabic dates as bootstrap does.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  useWesternDigits();
  await _loadTajawal();
  await testMain();
}

Future<void> _loadTajawal() async {
  final loader = FontLoader('Tajawal');
  for (final weight in const ['Regular', 'Medium', 'Bold']) {
    loader.addFont(rootBundle.load('assets/fonts/Tajawal-$weight.ttf'));
  }
  await loader.load();
}
