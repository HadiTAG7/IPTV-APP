import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled Tajawal font so widget and golden tests render real
/// Arabic and Latin glyphs instead of the Ahem test font boxes.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
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
