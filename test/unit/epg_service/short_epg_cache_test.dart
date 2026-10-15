import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/epg/epg_models.dart';
import 'package:iptv_player/epg/short_epg_cache.dart';
import 'package:iptv_player/sources/models.dart';

final _now = DateTime.utc(2026, 1, 10, 12);

EpgProgramme _prog(String title, DateTime start, Duration length) =>
    EpgProgramme(
      channelId: 'ch',
      start: start,
      stop: start.add(length),
      title: title,
    );

/// A loader that counts calls and returns [result].
class _Loader {
  _Loader(this.result);

  List<EpgProgramme> result;
  int calls = 0;

  Future<List<EpgProgramme>> call() async {
    calls++;
    return result;
  }
}

void main() {
  late FakeClock clock;
  late ShortEpgCache cache;

  setUp(() {
    clock = FakeClock(_now);
    cache = ShortEpgCache(clock: clock);
  });

  final listing = [
    _prog(
      'Now',
      _now.subtract(const Duration(minutes: 10)),
      const Duration(hours: 1),
    ),
    _prog(
      'Next',
      _now.add(const Duration(minutes: 50)),
      const Duration(hours: 1),
    ),
  ];

  test('reuses a listing for 15 minutes', () async {
    final loader = _Loader(listing);

    expect(await cache.get(1, 'a', loader.call), listing);
    clock.advance(const Duration(minutes: 14, seconds: 59));
    expect(await cache.get(1, 'a', loader.call), listing);
    expect(loader.calls, 1);
    expect(cache.peek(1, 'a'), listing);

    clock.advance(const Duration(seconds: 1));
    expect(cache.peek(1, 'a'), isNull);
    await cache.get(1, 'a', loader.call);
    expect(loader.calls, 2);
  });

  test('keys are per source and channel', () async {
    final loader = _Loader(listing);
    await cache.get(1, 'a', loader.call);
    await cache.get(1, 'b', loader.call);
    await cache.get(2, 'a', loader.call);
    await cache.get(1, 'a', loader.call);
    expect(loader.calls, 3);
    expect(cache.length, 3);
  });

  test('concurrent requests share one load', () async {
    final gate = Completer<List<EpgProgramme>>();
    var calls = 0;
    Future<List<EpgProgramme>> loader() {
      calls++;
      return gate.future;
    }

    final a = cache.get(1, 'a', loader);
    final b = cache.get(1, 'a', loader);
    gate.complete(listing);

    expect(await a, listing);
    expect(await b, listing);
    expect(calls, 1);
  });

  test(
    'programmes that ended are left out; a listing that ended reloads',
    () async {
      // "Now" ends 10 minutes in, well inside the 15-minute TTL.
      final loader = _Loader([
        _prog(
          'Now',
          _now.subtract(const Duration(minutes: 50)),
          const Duration(hours: 1),
        ),
        _prog(
          'Next',
          _now.add(const Duration(minutes: 10)),
          const Duration(hours: 1),
        ),
      ]);
      await cache.get(1, 'a', loader.call);

      clock.advance(const Duration(minutes: 12));
      expect(
        [for (final p in await cache.get(1, 'a', loader.call)) p.title],
        ['Next'],
      );
      expect(loader.calls, 1);

      // Both ended (within the TTL of a later reload): load again.
      loader.result = [_prog('Short', clock.now(), const Duration(minutes: 5))];
      cache.invalidate(1, 'a');
      await cache.get(1, 'a', loader.call);
      clock.advance(const Duration(minutes: 6));
      expect(cache.peek(1, 'a'), isNull);
      await cache.get(1, 'a', loader.call);
      expect(loader.calls, 3);
    },
  );

  test('an empty listing is cached like any other', () async {
    final loader = _Loader(const []);
    expect(await cache.get(1, 'a', loader.call), isEmpty);
    expect(await cache.get(1, 'a', loader.call), isEmpty);
    expect(loader.calls, 1);
  });

  test('a failing load yields an empty list, retried after a minute', () async {
    var calls = 0;
    Future<List<EpgProgramme>> failing() async {
      calls++;
      throw const NetworkFailure('HTTP 503 from http://example.com');
    }

    expect(await cache.get(1, 'a', failing), isEmpty);
    clock.advance(const Duration(seconds: 59));
    expect(await cache.get(1, 'a', failing), isEmpty);
    expect(calls, 1);

    clock.advance(const Duration(seconds: 1));
    expect(await cache.get(1, 'a', _Loader(listing).call), listing);
  });

  test('errors are rethrown and not cached', () async {
    Future<List<EpgProgramme>> broken() async => throw StateError('bug');

    await expectLater(cache.get(1, 'a', broken), throwsStateError);
    final loader = _Loader(listing);
    expect(await cache.get(1, 'a', loader.call), listing);
    expect(loader.calls, 1);
  });

  test('invalidate and clear', () async {
    final loader = _Loader(listing);
    await cache.get(1, 'a', loader.call);
    await cache.get(1, 'b', loader.call);
    await cache.get(2, 'a', loader.call);

    cache.invalidate(1, 'a');
    expect(cache.peek(1, 'a'), isNull);
    expect(cache.peek(1, 'b'), isNotNull);

    cache.invalidate(1);
    expect(cache.peek(1, 'b'), isNull);
    expect(cache.peek(2, 'a'), isNotNull);

    cache.clear();
    expect(cache.length, 0);
  });

  test(
    'a load running across an invalidate is returned but not cached',
    () async {
      final gate = Completer<List<EpgProgramme>>();
      final pending = cache.get(1, 'a', () => gate.future);
      cache.invalidate(1);
      gate.complete(listing);

      expect(await pending, listing);
      expect(cache.peek(1, 'a'), isNull);
    },
  );

  test('keeps the most recently used channels', () async {
    cache = ShortEpgCache(clock: clock, maxEntries: 2);
    final loader = _Loader(listing);
    await cache.get(1, 'a', loader.call);
    await cache.get(1, 'b', loader.call);
    cache.peek(1, 'a'); // Now 'b' is the least recently used.
    await cache.get(1, 'c', loader.call);

    expect(cache.length, 2);
    expect(cache.peek(1, 'b'), isNull);
    expect(cache.peek(1, 'a'), isNotNull);
    expect(cache.peek(1, 'c'), isNotNull);
  });
}
