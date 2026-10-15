import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/core/time/clock.dart';

void main() {
  final epoch = DateTime.utc(2026, 3, 1, 8, 30);

  test('keeps only the last lines', () {
    final log = RingLog(capacity: 3, clock: FakeClock(epoch));
    for (var i = 0; i < 5; i++) {
      log.info('line $i');
    }
    expect(log.length, 3);
    expect(log.lines.first, endsWith('INFO line 2'));
    expect(log.lines.last, '2026-03-01T08:30:00.000Z INFO line 4');
    expect(RingLog.defaultCapacity, 500);
  });

  test('redacts URLs with credentials and registered secrets', () {
    final log = RingLog(clock: FakeClock(epoch))..addSecret('hunter22');
    log.warn('GET http://h:8080/player_api.php?username=bob&password=hunter22');
    log.error('open http://h/live/bob/hunter22/1.ts failed');
    log.info('typed hunter22 in a form');
    final text = log.dump();
    expect(text, isNot(contains('hunter22')));
    expect(text, contains('password=***'));
    expect(text, contains('/live/***/***/1.ts'));
    expect(log.lines[2], endsWith('typed *** in a form'));
  });

  test('splits multi-line messages and stack traces', () {
    final log = RingLog(clock: FakeClock(epoch));
    log.error('boom', StateError('bad'), StackTrace.fromString('#0 a\n#1 b\n'));
    expect(log.lines, [
      '2026-03-01T08:30:00.000Z ERROR boom: Bad state: bad',
      '  #0 a',
      '  #1 b',
    ]);
  });

  test('dump of the last lines and clear', () {
    final log = RingLog(clock: FakeClock(epoch));
    log
      ..log('debug', 'a')
      ..log('Warn', 'b')
      ..log('info', 'c');
    expect(log.dump(last: 2).split('\n'), hasLength(2));
    expect(log.dump(last: 2), contains('WARN b'));
    expect(log.dump(last: 99).split('\n'), hasLength(3));
    log.clear();
    expect(log.lines, isEmpty);
    expect(log.dump(), '');
  });
}
