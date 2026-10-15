import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/vod_common/paged_items.dart';
import 'package:iptv_player/features/vod_common/vod_format.dart';

void main() {
  group('PagedItems', () {
    /// A list of [count] ints read in pages; records each read offset.
    (PagedItems<int>, List<int>) paged(
      int count, {
      int pageSize = 10,
      int maxPages = 3,
      Duration latency = Duration.zero,
      bool Function(int offset)? fail,
    }) {
      final reads = <int>[];
      final items = PagedItems<int>(
        count: count,
        pageSize: pageSize,
        maxPages: maxPages,
        load: (offset, limit) async {
          reads.add(offset);
          if (latency > Duration.zero) await Future<void>.delayed(latency);
          if (fail?.call(offset) ?? false) throw StateError('db closed');
          return [for (var i = offset; i < offset + limit && i < count; i++) i];
        },
      );
      return (items, reads);
    }

    test('reads the first page at once and answers from memory', () {
      fakeAsync((async) {
        final (items, reads) = paged(25);
        var notified = 0;
        items.addListener(() => notified++);
        expect(reads, [0]);
        expect(items.itemAt(3), isNull);
        async.flushMicrotasks();
        expect(notified, 1);
        expect(items.itemAt(3), 3);
        expect(items.itemAt(9), 9);
        expect(items.loads, 1);
        // The last page is short.
        expect(items.itemAt(24), isNull);
        async.elapse(items.debounce);
        expect(reads, [0, 20]);
        expect(items.itemAt(24), 24);
        expect(items.itemAt(25), isNull);
        expect(items.itemAt(-1), isNull);
        items.dispose();
      });
    });

    test('fast scrolling reads only the pages asked for last', () {
      fakeAsync((async) {
        final (items, reads) = paged(1000, maxPages: 10);
        async.flushMicrotasks();
        // A held key flies over pages 1..20 within the debounce window.
        for (var page = 1; page <= 20; page++) {
          expect(items.itemAt(page * 10), isNull);
        }
        expect(items.isLoading, isTrue);
        async.elapse(items.debounce);
        expect(reads, [0, 200, 190, 180]);
        expect(items.loadedPages, {0, 18, 19, 20});
        expect(items.isLoading, isFalse);
        items.dispose();
      });
    });

    test('a page being read is not asked for again', () {
      fakeAsync((async) {
        final (items, reads) = paged(
          100,
          latency: const Duration(milliseconds: 500),
        );
        items.itemAt(1);
        items.itemAt(2);
        async.elapse(items.debounce);
        expect(reads, [0]);
        async.elapse(const Duration(seconds: 1));
        expect(items.itemAt(2), 2);
        items.dispose();
      });
    });

    test('keeps at most maxPages, dropping the least recently used', () {
      fakeAsync((async) {
        final (items, reads) = paged(100);
        async.flushMicrotasks();
        for (final page in [1, 2]) {
          items.itemAt(page * 10);
          async.elapse(items.debounce);
        }
        expect(items.loadedPages, {0, 1, 2});
        // Touch page 0 so page 1 is the oldest.
        expect(items.itemAt(0), 0);
        items.itemAt(30);
        async.elapse(items.debounce);
        expect(items.loadedPages, {0, 2, 3});
        expect(items.itemAt(10), isNull);
        async.elapse(items.debounce);
        expect(reads.last, 10);
        expect(items.loadedPages, {0, 3, 1});
        items.dispose();
      });
    });

    test('a failed read reports an error; retry reads again', () {
      fakeAsync((async) {
        var broken = true;
        final (items, reads) = paged(30, fail: (_) => broken);
        async.flushMicrotasks();
        expect(items.error, isA<StateError>());
        expect(items.isEmpty, isTrue);
        broken = false;
        items.retry();
        expect(items.error, isNull);
        async.elapse(items.debounce);
        expect(reads, [0, 0]);
        expect(items.itemAt(5), 5);
        items.dispose();
      });
    });

    test('a failed later page waits before it is read again', () {
      fakeAsync((async) {
        var broken = true;
        final (items, reads) = paged(100, fail: (o) => broken && o == 50);
        var notified = 0;
        items.addListener(() => notified++);
        async.flushMicrotasks();
        expect(items.itemAt(55), isNull);
        async.elapse(items.debounce);
        expect(reads, [0, 50]);
        expect(items.error, isA<StateError>());
        expect(items.isEmpty, isFalse);

        // Rebuilds keep asking for the item: no read until the backoff.
        final before = notified;
        for (var i = 0; i < 10; i++) {
          expect(items.itemAt(55), isNull);
          async.elapse(items.debounce);
        }
        expect(reads, [0, 50]);
        expect(items.itemAt(5), 5);
        async.elapse(items.retryBackoff - items.debounce * 10);
        // Listeners hear that the page may be asked for again.
        expect(notified, before + 1);
        expect(items.itemAt(55), isNull);
        async.elapse(items.debounce);
        expect(reads, [0, 50, 50]);

        // A second failure in a row waits twice as long.
        for (var i = 0; i < 30; i++) {
          items.itemAt(55);
          async.elapse(items.debounce);
        }
        expect(reads, [0, 50, 50]);
        async.elapse(items.retryBackoff * 2);
        items.itemAt(55);
        async.elapse(items.debounce);
        expect(reads, [0, 50, 50, 50]);
        expect(items.error, isNotNull);

        // Retry reads at once; the error clears once the page is read.
        broken = false;
        items.retry();
        expect(items.itemAt(55), isNull);
        async.elapse(items.debounce);
        expect(reads, [0, 50, 50, 50, 50]);
        expect(items.itemAt(55), 55);
        expect(items.error, isNull);
        items.dispose();
      });
    });

    test('the error stays until every failed page was read', () {
      fakeAsync((async) {
        var broken = true;
        final (items, _) = paged(100, fail: (o) => broken && o != 0);
        async.flushMicrotasks();
        items
          ..itemAt(15)
          ..itemAt(35);
        async.elapse(items.debounce);
        expect(items.error, isNotNull);
        broken = false;
        async.elapse(items.retryBackoff);
        items.itemAt(15);
        async.elapse(items.debounce);
        expect(items.itemAt(15), 15);
        // Page 3 is still missing.
        expect(items.error, isNotNull);
        items.itemAt(35);
        async.elapse(items.debounce);
        expect(items.itemAt(35), 35);
        expect(items.error, isNull);
        items.dispose();
      });
    });

    test('refresh re-reads the pages asked for and keeps items meanwhile', () {
      fakeAsync((async) {
        var version = 0;
        final reads = <int>[];
        final items = PagedItems<String>(
          count: 30,
          pageSize: 10,
          load: (offset, limit) async {
            reads.add(offset);
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return [
              for (var i = offset; i < offset + limit; i++) 'v$version:$i',
            ];
          },
        );
        async.elapse(const Duration(milliseconds: 20));
        items.itemAt(25);
        async.elapse(const Duration(milliseconds: 200));
        expect(items.itemAt(25), 'v0:25');
        version = 1;
        var notified = 0;
        items.addListener(() => notified++);
        unawaited(items.refresh());
        // Listeners hear of it, and ask for the pages they show.
        expect(notified, 1);
        // Old items stay until the new pages arrive.
        expect(items.itemAt(3), 'v0:3');
        async.elapse(const Duration(milliseconds: 20));
        expect(items.itemAt(3), 'v0:3');
        async.elapse(items.debounce);
        expect(items.itemAt(3), 'v1:3');
        expect(reads, [0, 20, 0]);
        // A page not asked for since is read when it is.
        expect(items.itemAt(25), 'v0:25');
        async.elapse(const Duration(milliseconds: 200));
        expect(items.itemAt(25), 'v1:25');
        expect(reads, [0, 20, 0, 20]);
        items.dispose();
      });
    });

    test('refresh reads only the pages on screen, debounced and at most '
        'maxConcurrent at once', () {
      fakeAsync((async) {
        var inFlight = 0;
        var maxInFlight = 0;
        final reads = <int>[];
        final items = PagedItems<int>(
          count: 1000,
          pageSize: 10,
          maxPages: 10,
          load: (offset, limit) async {
            reads.add(offset);
            maxInFlight = max(maxInFlight, ++inFlight);
            await Future<void>.delayed(const Duration(milliseconds: 30));
            inFlight--;
            return [for (var i = offset; i < offset + limit; i++) i];
          },
        );
        async.flushMicrotasks();
        // Ten pages in memory, the screen now shows page 9.
        for (var page = 1; page < 10; page++) {
          items.itemAt(page * 10);
          async.elapse(const Duration(milliseconds: 200));
        }
        expect(items.loadedPages, hasLength(10));
        reads.clear();
        maxInFlight = 0;
        // Three commits of one sync.
        for (var i = 0; i < 3; i++) {
          var done = false;
          unawaited(items.refresh().then((_) => done = true));
          items
            ..itemAt(90)
            ..itemAt(95);
          async.elapse(const Duration(milliseconds: 50));
          expect(reads, hasLength(i), reason: 'debounced');
          async.elapse(const Duration(milliseconds: 200));
          expect(done, isTrue);
        }
        expect(reads, [90, 90, 90]);
        expect(maxInFlight, 1);
        items.dispose();
      });
    });

    test('refresh with a new count resizes in place and completes once '
        'the pages are read', () {
      fakeAsync((async) {
        var count = 30;
        final items = PagedItems<int>(
          count: count,
          pageSize: 10,
          load: (offset, limit) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return [
              for (var i = offset; i < offset + limit && i < count; i++) i,
            ];
          },
        );
        async.elapse(const Duration(milliseconds: 20));
        items.itemAt(25);
        async.elapse(const Duration(milliseconds: 200));
        expect(items.loadedPages, {0, 2});

        // Fewer items: the page past the end goes, the rest is re-read.
        count = 15;
        var done = false;
        unawaited(items.refresh(count: count).then((_) => done = true));
        expect(items.count, 15);
        expect(items.loadedPages, {0});
        expect(items.itemAt(25), isNull);
        expect(items.itemAt(7), 7);
        async.flushMicrotasks();
        expect(done, isFalse);
        async.elapse(items.debounce);
        expect(done, isFalse);
        async.elapse(const Duration(milliseconds: 10));
        expect(done, isTrue);
        expect(items.indexWhereLoaded((i) => i == 7), 7);
        expect(items.indexWhereLoaded((i) => i == 25), isNull);

        // More items: nothing is dropped.
        count = 40;
        unawaited(items.refresh(count: count));
        expect(items.count, 40);
        async.elapse(const Duration(milliseconds: 10));
        items.itemAt(35);
        async.elapse(const Duration(milliseconds: 200));
        expect(items.itemAt(35), 35);
        items.dispose();
      });
    });

    test('refresh completes when nothing is asked for, and on dispose', () {
      fakeAsync((async) {
        final (items, reads) = paged(30, latency: const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 2));
        var done = 0;
        unawaited(items.refresh().then((_) => done++));
        async.elapse(items.debounce);
        expect(done, 1);
        expect(reads, [0]);
        items.itemAt(1);
        unawaited(items.refresh().then((_) => done++));
        items.itemAt(1);
        async.elapse(items.debounce);
        expect(done, 1);
        items.dispose();
        async.flushMicrotasks();
        expect(done, 2);
      });
    });

    test('nothing is read after dispose', () {
      fakeAsync((async) {
        final (items, reads) = paged(
          100,
          latency: const Duration(milliseconds: 50),
        );
        items.itemAt(50);
        items.dispose();
        async.elapse(const Duration(seconds: 1));
        expect(reads, [0]);
      });
    });

    test('an empty list reads nothing', () {
      fakeAsync((async) {
        final (items, reads) = paged(0);
        expect(items.itemAt(0), isNull);
        async.elapse(const Duration(seconds: 1));
        expect(reads, isEmpty);
        items.dispose();
      });
    });
  });

  group('formatting', () {
    test('positions', () {
      expect(formatPlayPosition(Duration.zero), '0:00');
      expect(formatPlayPosition(const Duration(seconds: 65)), '1:05');
      expect(
        formatPlayPosition(const Duration(minutes: 42, seconds: 10)),
        '42:10',
      );
      expect(
        formatPlayPosition(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
      expect(formatPlayPosition(const Duration(seconds: -5)), '0:00');
    });

    test('runtime, year and rating', () {
      expect(runtimeMinutes(null), isNull);
      expect(runtimeMinutes(0), isNull);
      expect(runtimeMinutes(20), 1);
      expect(runtimeMinutes(95 * 60 + 20), 95);
      expect(releaseYear(2001, '1999-01-01'), 2001);
      expect(releaseYear(null, '1999-05-01'), 1999);
      expect(releaseYear(0, ' 2010'), 2010);
      expect(releaseYear(null, 'n/a'), isNull);
      expect(formatRating(null), isNull);
      expect(formatRating(0), isNull);
      expect(formatRating(7.25), '7.3');
    });
  });
}
