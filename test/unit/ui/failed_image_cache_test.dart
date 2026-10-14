import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/widgets/logo_image.dart';

const _url = 'http://127.0.0.1:9/logos/demo.png';

NetworkImageLoadException _http(int status) =>
    NetworkImageLoadException(statusCode: status, uri: Uri.parse(_url));

void main() {
  late FakeClock clock;

  setUp(() {
    clock = FakeClock(DateTime.utc(2026, 10, 1, 20));
    FailedImageCache.clear();
    FailedImageCache.clock = clock;
  });

  tearDown(() {
    FailedImageCache.clear();
    FailedImageCache.clock = const SystemClock();
  });

  test('a transient failure expires, so logos return with the network', () {
    FailedImageCache.add(_url, error: Exception('Failed host lookup'));
    expect(FailedImageCache.contains(_url), isTrue);
    clock.advance(FailedImageCache.transientTtl - const Duration(seconds: 1));
    expect(FailedImageCache.contains(_url), isTrue);
    clock.advance(const Duration(seconds: 1));
    expect(FailedImageCache.contains(_url), isFalse);
    expect(FailedImageCache.length, 0, reason: 'expired entry is dropped');
  });

  test('without an error the failure counts as transient', () {
    FailedImageCache.add(_url);
    clock.advance(FailedImageCache.transientTtl);
    expect(FailedImageCache.contains(_url), isFalse);
  });

  test('a definitive failure is kept longer, but not forever', () {
    FailedImageCache.add(_url, error: _http(404));
    clock.advance(FailedImageCache.transientTtl * 2);
    expect(FailedImageCache.contains(_url), isTrue);
    clock.advance(FailedImageCache.definitiveTtl);
    expect(FailedImageCache.contains(_url), isFalse);
  });

  test('which errors are definitive', () {
    for (final status in [400, 401, 403, 404, 410]) {
      expect(FailedImageCache.isDefinitive(_http(status)), isTrue);
    }
    for (final status in [408, 429, 500, 502, 503]) {
      expect(FailedImageCache.isDefinitive(_http(status)), isFalse);
    }
    expect(FailedImageCache.isDefinitive(null), isFalse);
    expect(FailedImageCache.isDefinitive(Exception('timeout')), isFalse);
    expect(FailedImageCache.isDefinitive(StateError('bad data')), isFalse);
  });

  test('clearTransient keeps definitive failures', () {
    const other = 'http://127.0.0.1:9/logos/other.png';
    FailedImageCache.add(_url, error: _http(404));
    FailedImageCache.add(other, error: _http(503));
    FailedImageCache.clearTransient();
    expect(FailedImageCache.contains(_url), isTrue);
    expect(FailedImageCache.contains(other), isFalse);
  });

  test('a repeated failure restarts its timer', () {
    FailedImageCache.add(_url);
    clock.advance(FailedImageCache.transientTtl ~/ 2);
    FailedImageCache.add(_url);
    clock.advance(FailedImageCache.transientTtl ~/ 2);
    expect(FailedImageCache.contains(_url), isTrue);
  });

  test('is capped at maxEntries, oldest first', () {
    for (var i = 0; i <= FailedImageCache.maxEntries; i++) {
      FailedImageCache.add('http://127.0.0.1:9/$i.png');
    }
    expect(FailedImageCache.length, FailedImageCache.maxEntries);
    expect(FailedImageCache.contains('http://127.0.0.1:9/0.png'), isFalse);
    expect(FailedImageCache.contains('http://127.0.0.1:9/1.png'), isTrue);
  });
}
