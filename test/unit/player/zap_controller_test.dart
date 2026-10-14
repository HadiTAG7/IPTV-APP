import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/session/zap_controller.dart';

class Ch {
  const Ch(this.name, this.number);

  final String name;
  final int number;

  @override
  String toString() => name;
}

const channels = [
  Ch('Alpha', 101),
  Ch('Bravo', 102),
  Ch('Charlie', 105),
  Ch('Delta', 7),
  Ch('Echo', 1500),
];

const ms350 = Duration(milliseconds: 350);
const ms1500 = Duration(milliseconds: 1500);

void main() {
  late List<Ch> tuned;

  ZapController<Ch> make({int initial = 0, bool numbered = true}) {
    tuned = [];
    return ZapController<Ch>(
      items: channels,
      initialIndex: initial,
      numberOf: numbered ? (c) => c.number : null,
      onTune: tuned.add,
    );
  }

  group('next/previous', () {
    test('banner moves at once; open fires after 350 ms', () {
      fakeAsync((async) {
        final z = make();
        z.next();
        expect(z.preview.value.item, channels[1]);
        expect(z.preview.value.pending, isTrue);
        async.elapse(const Duration(milliseconds: 349));
        expect(tuned, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(tuned, [channels[1]]);
        expect(z.current, channels[1]);
        expect(z.currentIndex, 1);
        expect(z.preview.value.pending, isFalse);
        z.dispose();
      });
    });

    test('held key: only the final channel opens', () {
      fakeAsync((async) {
        final z = make();
        final banner = <String>[];
        z.preview.addListener(() => banner.add('${z.preview.value.item}'));
        for (var i = 0; i < 3; i++) {
          z.next();
          async.elapse(const Duration(milliseconds: 100));
        }
        expect(tuned, isEmpty);
        expect(banner, ['Bravo', 'Charlie', 'Delta']);
        async.elapse(ms350);
        expect(tuned, [channels[3]]);
        z.dispose();
      });
    });

    test('wraps around in both directions', () {
      fakeAsync((async) {
        final z = make(initial: 4);
        z.next();
        async.elapse(ms350);
        expect(tuned, [channels[0]]);
        z.previous();
        async.elapse(ms350);
        expect(tuned.last, channels[4]);
        z.dispose();
      });
    });

    test('returning to the playing channel does not reopen it', () {
      fakeAsync((async) {
        final z = make(initial: 2);
        z.next();
        z.previous();
        async.elapse(ms350);
        expect(tuned, isEmpty);
        expect(z.preview.value.item, channels[2]);
        expect(z.preview.value.pending, isFalse);
        z.dispose();
      });
    });

    test('empty list is a no-op; no current item starts at the edges', () {
      fakeAsync((async) {
        final empty = ZapController<Ch>(onTune: (_) => fail('no tune'));
        empty.next();
        async.elapse(ms350);
        empty.dispose();

        final z = make(initial: -1);
        expect(z.preview.value.item, isNull);
        z.previous();
        async.elapse(ms350);
        expect(tuned, [channels.last]);
        z.dispose();
      });
    });
  });

  group('number entry', () {
    test('digits tune after 1.5 s', () {
      fakeAsync((async) {
        final z = make();
        z.digit(1);
        z.digit(0);
        z.digit(5);
        expect(z.preview.value.digits, '105');
        expect(z.preview.value.item, channels[2]);
        async.elapse(const Duration(milliseconds: 1499));
        expect(tuned, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(tuned, [channels[2]]);
        expect(z.preview.value.digits, isEmpty);
        z.dispose();
      });
    });

    test('each digit restarts the timeout', () {
      fakeAsync((async) {
        final z = make();
        z.digit(1);
        async.elapse(const Duration(milliseconds: 1400));
        z.digit(0);
        async.elapse(const Duration(milliseconds: 1400));
        z.digit(2);
        async.elapse(const Duration(milliseconds: 1400));
        expect(tuned, isEmpty);
        async.elapse(const Duration(milliseconds: 100));
        expect(tuned, [channels[1]]);
        z.dispose();
      });
    });

    test('commit() tunes immediately', () {
      fakeAsync((async) {
        final z = make();
        z.digit(7);
        z.commit();
        expect(tuned, [channels[3]]);
        async.elapse(ms1500);
        expect(tuned, [channels[3]]);
        z.dispose();
      });
    });

    test('unknown number keeps the current channel', () {
      fakeAsync((async) {
        final z = make();
        z.digit(9);
        z.digit(9);
        expect(z.preview.value.item, channels[0]);
        async.elapse(ms1500);
        expect(tuned, isEmpty);
        expect(z.preview.value.digits, isEmpty);
        expect(z.preview.value.item, channels[0]);
        z.dispose();
      });
    });

    test('positions are used when items have no numbers', () {
      fakeAsync((async) {
        final z = make(numbered: false);
        z.digit(3);
        z.commit();
        expect(tuned, [channels[2]]);
        z.digit(6);
        z.commit();
        expect(tuned, [channels[2]]);
        z.dispose();
      });
    });

    test('max digits commits at once', () {
      fakeAsync((async) {
        final z = make();
        for (final d in [0, 1, 5, 0, 0]) {
          z.digit(d);
        }
        // "01500" = 1500.
        expect(tuned, [channels[4]]);
        z.dispose();
      });
    });

    test('a leading 0 followed by digits is a number, not a recall', () {
      fakeAsync((async) {
        final z = make(initial: 1);
        z.digit(0);
        z.digit(7);
        z.commit();
        expect(tuned, [channels[3]]);
        z.dispose();
      });
    });

    test('cancelNumber drops the buffer', () {
      fakeAsync((async) {
        final z = make();
        z.digit(1);
        z.cancelNumber();
        expect(z.preview.value.digits, isEmpty);
        async.elapse(ms1500);
        expect(tuned, isEmpty);
        z.dispose();
      });
    });

    test('a digit cancels a pending zap', () {
      fakeAsync((async) {
        final z = make();
        z.next();
        z.digit(7);
        async.elapse(ms1500);
        expect(tuned, [channels[3]]);
        z.dispose();
      });
    });
  });

  group('recall', () {
    test('lone 0 returns to the previous channel and toggles', () {
      fakeAsync((async) {
        final z = make();
        z.digit(7);
        z.commit();
        expect(z.previousChannel, channels[0]);

        z.digit(0);
        expect(tuned.length, 1);
        async.elapse(ms1500);
        expect(tuned, [channels[3], channels[0]]);

        z.digit(0);
        z.commit();
        expect(tuned, [channels[3], channels[0], channels[3]]);
        z.dispose();
      });
    });

    test('no previous channel: nothing happens', () {
      fakeAsync((async) {
        final z = make();
        z.digit(0);
        z.commit();
        expect(tuned, isEmpty);
        z.dispose();
      });
    });

    test('channels opened from the list count for recall', () {
      fakeAsync((async) {
        final z = make();
        z.markTuned(channels[4]);
        expect(tuned, isEmpty);
        z.recall();
        expect(tuned, [channels[0]]);
        z.dispose();
      });
    });
  });

  test('setItems keeps the current channel and cancels pending work', () {
    fakeAsync((async) {
      final z = make(initial: 1);
      z.next();
      z.setItems([channels[3], channels[1]]);
      async.elapse(ms350);
      expect(tuned, isEmpty);
      expect(z.currentIndex, 1);
      z.next();
      async.elapse(ms350);
      expect(tuned, [channels[3]]);

      z.setItems(channels, current: channels[4]);
      expect(z.current, channels[4]);
      expect(z.currentIndex, 4);
      expect(z.items, hasLength(channels.length));
      z.dispose();
    });
  });

  test('dispose cancels timers', () {
    fakeAsync((async) {
      final z = make();
      z.next();
      z.digit(1);
      z.dispose();
      async.elapse(const Duration(seconds: 5));
      expect(tuned, isEmpty);
      expect(async.pendingTimers, isEmpty);
    });
  });
}
