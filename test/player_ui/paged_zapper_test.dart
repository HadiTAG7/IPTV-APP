import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/queries/player_ui_queries.dart';
import 'package:iptv_player/player/ui/paged_zapper.dart';

/// A [MemoryZapList] that records its reads and can hold number lookups.
class _RecordingList extends MemoryZapList {
  _RecordingList(super.entries);

  final ranges = <int>[];
  Completer<void>? holdLookups;
  Completer<void>? holdRanges;

  @override
  Future<List<ZapEntry>> range(int offset, int limit) async {
    ranges.add(offset);
    await holdRanges?.future;
    return super.range(offset, limit);
  }

  @override
  Future<(ZapEntry, int)?> findNumber(int number) async {
    await holdLookups?.future;
    return super.findNumber(number);
  }
}

List<ZapEntry> _entries(int n, {bool numbered = true}) => [
  for (var i = 1; i <= n; i++) (key: 'ch$i', num: numbered ? 100 + i : null),
];

void main() {
  late _RecordingList list;
  late List<String> tuned;

  PagedZapper make(int count, {bool numbered = true, int pageSize = 4}) {
    list = _RecordingList(_entries(count, numbered: numbered));
    tuned = [];
    return PagedZapper(
      list: list,
      onTune: (e) => tuned.add(e.key),
      pageSize: pageSize,
      maxPages: 3,
      readAhead: 1,
    );
  }

  void initAt(FakeAsync async, PagedZapper zap, String key) {
    unawaited(zap.init((key: key, num: null)));
    async.flushMicrotasks();
  }

  test('steps move the banner at once and tune the last target once', () {
    fakeAsync((async) {
      final zap = make(20);
      initAt(async, zap, 'ch2');
      expect(zap.currentIndex, 1);
      expect(zap.preview.value.item?.key, 'ch2');
      zap
        ..next()
        ..next();
      expect(zap.preview.value.item?.key, 'ch4');
      expect(zap.preview.value.pending, isTrue);
      async.elapse(const Duration(milliseconds: 349));
      expect(tuned, isEmpty);
      async.elapse(const Duration(milliseconds: 2));
      expect(tuned, ['ch4']);
      expect(zap.preview.value.pending, isFalse);

      // Wraps around both ways.
      for (var i = 0; i < 4; i++) {
        zap.previous();
        async.flushMicrotasks();
      }
      expect(zap.preview.value.item?.key, 'ch20');
      async.elapse(const Duration(milliseconds: 400));
      expect(tuned, ['ch4', 'ch20']);
      zap.next();
      async.elapse(const Duration(milliseconds: 400));
      expect(tuned.last, 'ch1');
    });
  });

  test('keeps at most maxPages pages and reads the target page on '
      'demand', () {
    fakeAsync((async) {
      final zap = make(40);
      initAt(async, zap, 'ch1');
      // Page 0, and page 9 for the wrap-around before the first channel.
      expect(list.ranges.toSet(), {0, 36});

      // Number 121 is far away (index 20, page 5).
      zap.digit(1);
      zap.digit(2);
      zap.digit(1);
      async.flushMicrotasks();
      expect(zap.preview.value.matched, isTrue);
      expect(zap.preview.value.item?.key, 'ch21');
      zap.commit();
      async.flushMicrotasks();
      expect(tuned, ['ch21']);
      expect(list.ranges, contains(20));

      // Walking on reads ahead; old pages are dropped and read again.
      list.ranges.clear();
      for (var i = 0; i < 8; i++) {
        zap.next();
        async.flushMicrotasks();
      }
      async.elapse(const Duration(milliseconds: 400));
      expect(tuned.last, 'ch29');
      expect(list.ranges, [24, 28]);
      list.ranges.clear();
      expect(zap.entryAt(0), isNull);
      zap.digit(1);
      zap.digit(0);
      zap.digit(1);
      async.elapse(const Duration(milliseconds: 1600));
      expect(tuned.last, 'ch1');
      expect(list.ranges, contains(0));
    });
  });

  test('a target whose page is not read yet fills in when it arrives', () {
    fakeAsync((async) {
      final zap = make(40);
      initAt(async, zap, 'ch1');
      // Reads are slow from now on: the page after the first one is still
      // being read when the banner gets there.
      list.holdRanges = Completer<void>();
      zap
        ..next()
        ..next()
        ..next()
        ..next();
      async.flushMicrotasks();
      expect(zap.preview.value.index, 4);
      expect(zap.preview.value.item, isNull);
      expect(zap.preview.value.pending, isTrue);
      list.holdRanges!.complete();
      list.holdRanges = null;
      async.flushMicrotasks();
      expect(zap.preview.value.item?.key, 'ch5');
      async.elapse(const Duration(milliseconds: 400));
      expect(tuned, ['ch5']);
    });
  });

  test('numbers: searching, matched, unknown; a lone 0 recalls', () {
    fakeAsync((async) {
      final zap = make(10);
      initAt(async, zap, 'ch1');
      list.holdLookups = Completer<void>();
      zap.digit(1);
      zap.digit(0);
      zap.digit(3);
      expect(zap.preview.value.digits, '103');
      expect(zap.preview.value.searching, isTrue);
      expect(zap.preview.value.matched, isFalse);
      list.holdLookups!.complete();
      list.holdLookups = null;
      async.flushMicrotasks();
      expect(zap.preview.value.searching, isFalse);
      expect(zap.preview.value.matched, isTrue);
      expect(zap.preview.value.item?.key, 'ch3');
      async.elapse(const Duration(milliseconds: 1499));
      expect(tuned, isEmpty);
      async.elapse(const Duration(milliseconds: 2));
      expect(tuned, ['ch3']);

      zap.digit(9);
      async.flushMicrotasks();
      expect(zap.preview.value.matched, isFalse);
      expect(zap.preview.value.item?.key, 'ch3');
      async.elapse(const Duration(seconds: 2));
      expect(tuned, ['ch3']);
      expect(zap.preview.value.digits, isEmpty);

      zap.digit(0);
      zap.commit();
      async.flushMicrotasks();
      expect(tuned, ['ch3', 'ch1']);
      zap.digit(0);
      async.elapse(const Duration(seconds: 2));
      expect(tuned, ['ch3', 'ch1', 'ch3']);
    });
  });

  test('without channel numbers, numbers are list positions', () {
    fakeAsync((async) {
      final zap = make(10, numbered: false);
      initAt(async, zap, 'ch1');
      expect(zap.hasNumbers, isFalse);
      zap.digit(7);
      async.flushMicrotasks();
      expect(zap.preview.value.item?.key, 'ch7');
      zap.commit();
      async.flushMicrotasks();
      expect(tuned, ['ch7']);
      zap.digit(1);
      zap.digit(1);
      async.elapse(const Duration(seconds: 2));
      expect(tuned, ['ch7']);
    });
  });

  test('cancelNumber also drops a commit whose lookup still runs', () {
    fakeAsync((async) {
      final zap = make(10);
      initAt(async, zap, 'ch1');
      list.holdLookups = Completer<void>();
      zap.digit(1);
      zap.digit(0);
      zap.digit(5);
      zap.commit();
      async.flushMicrotasks();
      expect(zap.preview.value.digits, '105');
      expect(zap.cancelNumber(), isTrue);
      expect(zap.preview.value.digits, isEmpty);
      list.holdLookups!.complete();
      async.elapse(const Duration(seconds: 2));
      expect(tuned, isEmpty);
      expect(zap.cancelNumber(), isFalse);
    });
  });

  test('close drops pending tunes, numbers and reads in flight', () {
    fakeAsync((async) {
      final zap = make(40);
      initAt(async, zap, 'ch1');
      zap.next();
      zap.close();
      async.elapse(const Duration(seconds: 1));
      expect(tuned, isEmpty);

      final other = make(40);
      initAt(async, other, 'ch1');
      list.holdLookups = Completer<void>();
      other
        ..digit(3)
        ..digit(9)
        ..commit();
      async.flushMicrotasks();
      other.close();
      list.holdLookups!.complete();
      async.elapse(const Duration(seconds: 2));
      expect(tuned, isEmpty);
      other
        ..next()
        ..digit(1);
      async.elapse(const Duration(seconds: 2));
      expect(tuned, isEmpty);
      other.dispose();
      zap.dispose();
    });
  });

  test('an empty list or a channel outside it', () {
    fakeAsync((async) {
      final empty = make(0);
      initAt(async, empty, 'ch1');
      empty.next();
      async.elapse(const Duration(seconds: 1));
      expect(tuned, isEmpty);

      final zap = make(5);
      initAt(async, zap, 'elsewhere');
      expect(zap.currentIndex, -1);
      expect(zap.preview.value.item?.key, 'elsewhere');
      zap.next();
      expect(zap.preview.value.item?.key, 'ch1');
      async.elapse(const Duration(milliseconds: 400));
      expect(tuned, ['ch1']);
      zap.digit(0);
      zap.commit();
      async.flushMicrotasks();
      expect(tuned, ['ch1', 'elsewhere']);
    });
  });
}
