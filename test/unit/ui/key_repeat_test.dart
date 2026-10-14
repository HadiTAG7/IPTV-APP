import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/tv/key_repeat.dart';

const _down = LogicalKeyboardKey.arrowDown;
const _up = LogicalKeyboardKey.arrowUp;

KeyEvent _keyDown(LogicalKeyboardKey k) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.arrowDown,
  logicalKey: k,
  timeStamp: Duration.zero,
);

KeyEvent _repeat(LogicalKeyboardKey k) => KeyRepeatEvent(
  physicalKey: PhysicalKeyboardKey.arrowDown,
  logicalKey: k,
  timeStamp: Duration.zero,
);

KeyEvent _keyUp(LogicalKeyboardKey k) => KeyUpEvent(
  physicalKey: PhysicalKeyboardKey.arrowDown,
  logicalKey: k,
  timeStamp: Duration.zero,
);

void main() {
  late FakeClock clock;
  late KeyRepeatThrottle throttle;

  setUp(() {
    clock = FakeClock(DateTime.utc(2026, 10, 14, 20));
    throttle = KeyRepeatThrottle(clock: clock);
  });

  int repeatAfter(int ms, [LogicalKeyboardKey key = _down]) {
    clock.advance(Duration(milliseconds: ms));
    return throttle.stepFor(_repeat(key));
  }

  test('key-down always moves one item', () {
    expect(throttle.stepFor(_keyDown(_down)), 1);
    expect(throttle.isRepeating, isFalse);
    expect(throttle.stepFor(_keyDown(_down)), 1);
  });

  test('repeats closer than 100 ms are dropped', () {
    throttle.stepFor(_keyDown(_down));
    expect(repeatAfter(40), 0);
    expect(repeatAfter(40), 0);
    expect(repeatAfter(40), 1, reason: '120 ms since the last move');
    expect(repeatAfter(99), 0);
    expect(repeatAfter(1), 1);
    expect(throttle.isRepeating, isTrue);
  });

  test('a steady 20/s repeat yields 10 moves per second', () {
    throttle.stepFor(_keyDown(_down));
    var moves = 0;
    for (var i = 0; i < 19; i++) {
      if (repeatAfter(50) > 0) moves++;
    }
    // 950 ms of repeats, all before the 1 s jump threshold.
    expect(moves, 9);
  });

  test('after 1 s held, moves become jumps of 5', () {
    throttle.stepFor(_keyDown(_down));
    expect(repeatAfter(400), 1);
    expect(repeatAfter(400), 1);
    expect(repeatAfter(199), 1);
    expect(repeatAfter(1), 0, reason: 'still throttled');
    expect(repeatAfter(100), 5);
    expect(repeatAfter(150), 5);
  });

  test('custom jump size and timings', () {
    final t = KeyRepeatThrottle(
      clock: clock,
      minInterval: const Duration(milliseconds: 200),
      jumpAfter: const Duration(milliseconds: 500),
      jumpSize: 10,
    );
    t.stepFor(_keyDown(_down));
    clock.advance(const Duration(milliseconds: 150));
    expect(t.stepFor(_repeat(_down)), 0);
    clock.advance(const Duration(milliseconds: 100));
    expect(t.stepFor(_repeat(_down)), 1);
    clock.advance(const Duration(milliseconds: 300));
    expect(t.stepFor(_repeat(_down)), 10);
  });

  test('key-up resets; a new press starts slow', () {
    throttle.stepFor(_keyDown(_down));
    repeatAfter(1200);
    expect(throttle.stepFor(_keyUp(_down)), 0);
    expect(throttle.isRepeating, isFalse);
    throttle.stepFor(_keyDown(_down));
    expect(repeatAfter(150), 1);
  });

  test('switching keys restarts the hold timer', () {
    throttle.stepFor(_keyDown(_down));
    repeatAfter(1100);
    // Repeat for a key that never sent key-down counts as a fresh press.
    expect(repeatAfter(10, _up), 1);
    expect(repeatAfter(150, _up), 1);
  });

  test('the same event object gets the same answer', () {
    throttle.stepFor(_keyDown(_down));
    clock.advance(const Duration(milliseconds: 150));
    final e = _repeat(_down);
    expect(throttle.stepFor(e), 1);
    expect(throttle.stepFor(e), 1, reason: 'memoised, not re-throttled');
    final e2 = _repeat(_down);
    expect(throttle.stepFor(e2), 0);
  });

  test('non-arrow keys pass through', () {
    final e = KeyRepeatEvent(
      physicalKey: PhysicalKeyboardKey.enter,
      logicalKey: LogicalKeyboardKey.enter,
      timeStamp: Duration.zero,
    );
    expect(throttle.stepFor(e), 1);
    expect(throttle.isRepeating, isFalse);
  });

  test('reset forgets the held key', () {
    throttle.stepFor(_keyDown(_down));
    repeatAfter(150);
    expect(throttle.isRepeating, isTrue);
    throttle.reset();
    expect(throttle.isRepeating, isFalse);
  });

  test('arrowDirection maps only arrows', () {
    expect(arrowDirection(LogicalKeyboardKey.arrowUp), TraversalDirection.up);
    expect(
      arrowDirection(LogicalKeyboardKey.arrowDown),
      TraversalDirection.down,
    );
    expect(
      arrowDirection(LogicalKeyboardKey.arrowLeft),
      TraversalDirection.left,
    );
    expect(
      arrowDirection(LogicalKeyboardKey.arrowRight),
      TraversalDirection.right,
    );
    expect(arrowDirection(LogicalKeyboardKey.select), isNull);
  });
}
