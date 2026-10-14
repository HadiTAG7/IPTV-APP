import 'package:fake_async/fake_async.dart';
import 'package:iptv_player/core/time/clock.dart';

/// A [Clock] that follows a [FakeAsync] zone's elapsed time.
class FakeAsyncClock implements Clock {
  FakeAsyncClock(this.async, [DateTime? start])
    : start = start ?? DateTime.utc(2026, 1, 1);

  final FakeAsync async;
  final DateTime start;

  @override
  DateTime now() => start.add(async.elapsed);
}
