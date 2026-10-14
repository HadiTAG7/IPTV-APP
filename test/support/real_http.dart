import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Restores real sockets for tests that talk to a local server.
///
/// `flutter_test_config.dart` initialises the test binding for every test
/// file, and the binding replaces [HttpClient] with a mock that answers 400.
void useRealHttp() {
  HttpOverrides? previous;
  setUpAll(() {
    previous = HttpOverrides.current;
    HttpOverrides.global = null;
  });
  tearDownAll(() => HttpOverrides.global = previous);
}
