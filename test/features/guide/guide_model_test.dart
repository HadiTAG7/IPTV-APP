import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/epg/epg_models.dart';
import 'package:iptv_player/features/guide/guide_model.dart';

/// Local wall-clock time on the test day, as UTC.
DateTime at(int hour, [int minute = 0, int day = 15]) =>
    DateTime(2026, 10, day, hour, minute).toUtc();

EpgProgramme prog(String title, DateTime start, DateTime stop) =>
    EpgProgramme(channelId: 'x', start: start, stop: stop, title: title);

void main() {
  group('time helpers', () {
    test('floorToSlot and ceilToSlot use local half hours', () {
      expect(floorToSlot(at(18, 47)), at(18, 30));
      expect(floorToSlot(at(18, 30)), at(18, 30));
      expect(floorToSlot(at(18, 29)), at(18));
      expect(ceilToSlot(at(18, 47)), at(19));
      expect(ceilToSlot(at(19)), at(19));
      expect(floorToSlot(at(18, 47)).isUtc, isTrue);
    });

    test('the browsable window at now', () {
      final w = GuideWindow(at(18, 47));
      expect(w.minTime, at(17, 30)); // an hour back, on a slot boundary
      expect(w.maxTime, at(18, 47).add(GuideTimes.ahead));
      expect(w.clampView(at(12)), w.minTime);
      expect(w.clampView(at(20)), at(20));
      expect(
        w.clampView(at(18, 47).add(const Duration(days: 9))),
        w.lastViewStart,
      );
      expect(w.lastViewStart.add(GuideTimes.span).isAfter(w.maxTime), isFalse);
    });

    test('movesForward mirrors left and right in RTL', () {
      const ltr = TextDirection.ltr;
      const rtl = TextDirection.rtl;
      expect(movesForward(TraversalDirection.right, ltr), isTrue);
      expect(movesForward(TraversalDirection.left, ltr), isFalse);
      expect(movesForward(TraversalDirection.right, rtl), isFalse);
      expect(movesForward(TraversalDirection.left, rtl), isTrue);
      expect(movesForward(TraversalDirection.up, ltr), isNull);
      expect(movesForward(TraversalDirection.down, rtl), isNull);
    });
  });

  group('buildSlots', () {
    test('fills gaps, clips to the range and to overlaps', () {
      final slots = buildSlots(
        [
          prog('Early', at(16), at(18)), // clipped to the range start
          prog('A', at(18), at(19)),
          prog('Overlap', at(18, 45), at(19, 30)), // starts at 19:00
          prog('Inside', at(19, 5), at(19, 20)), // fully covered: dropped
          prog('B', at(20), at(21)),
          prog('Late', at(23), at(23, 30)), // after the range: dropped
        ],
        at(17),
        at(22),
      );
      expect(
        [for (final s in slots) (s.programme?.title, s.start, s.stop)],
        [
          ('Early', at(17), at(18)),
          ('A', at(18), at(19)),
          ('Overlap', at(19), at(19, 30)),
          (null, at(19, 30), at(20)),
          ('B', at(20), at(21)),
          (null, at(21), at(22)),
        ],
      );
      // The programme keeps its published times.
      expect(slots.first.programme!.start, at(16));
    });

    test('no programmes is one gap', () {
      final slots = buildSlots(const [], at(17), at(22));
      expect(slots, [GuideSlot(at(17), at(22))]);
      expect(slots.single.isGap, isTrue);
    });

    test('slotIndexAt finds the slot holding a time', () {
      final slots = buildSlots(
        [prog('A', at(18), at(19)), prog('B', at(19), at(20))],
        at(17),
        at(21),
      );
      expect(slotIndexAt(slots, at(16)), 0);
      expect(slotIndexAt(slots, at(17, 59)), 0);
      expect(slotIndexAt(slots, at(18)), 1);
      expect(slotIndexAt(slots, at(19)), 2);
      expect(slotIndexAt(slots, at(20, 30)), 3);
      expect(slotIndexAt(slots, at(23)), 3);
      expect(slotIndexAt(const [], at(18)), -1);
    });
  });

  group('navigation', () {
    final w = GuideWindow(at(18, 47));
    final hourly = w.slotsFor([
      for (var h = 15; h < 24; h++) prog('H$h', at(h), at(h + 1)),
    ]);
    final halves = w.slotsFor([
      for (var m = 0; m < 12; m++)
        prog(
          'M$m',
          at(17).add(Duration(minutes: 30 * m)),
          at(17).add(Duration(minutes: 30 * (m + 1))),
        ),
    ]);
    String titleAt(List<GuideSlot> slots, GuidePosition p) =>
        slots[slotIndexAt(slots, p.anchor)].programme?.title ?? '-';

    test('starts at now on the given row', () {
      final p = GuidePosition.at(w, row: 3);
      expect(p.row, 3);
      expect(p.anchor, at(18, 47));
      expect(p.viewStart, at(18, 30));
      expect(p.viewEnd, at(21));
      expect(titleAt(hourly, p), 'H18');
    });

    test('rows move inside the list and keep the time', () {
      final p = GuidePosition.at(w);
      expect(moveRows(p, -1, 10), isNull);
      final down = moveRows(p, 1, 10)!;
      expect(down.row, 1);
      expect(down.anchor, p.anchor);
      expect(down.viewStart, p.viewStart);
      expect(moveRows(down, 50, 10)!.row, 9);
      expect(moveRows(p.copyWith(row: 9), 1, 10), isNull);
      expect(moveRows(p, 1, 0), isNull);
    });

    test('forward and back step through programmes', () {
      var p = GuidePosition.at(w);
      // H18 is on air; next is H19, starting inside the window.
      p = moveSlot(p, hourly, w, forward: true)!;
      expect(titleAt(hourly, p), 'H19');
      expect(p.anchor, at(19));
      expect(p.viewStart, at(18, 30));
      // Down to the half-hour row keeps 19:00.
      expect(titleAt(halves, p.copyWith(row: 1)), 'M4');
      // Back to H18: still half visible (18:30-19:00), no scroll; the anchor
      // is its first visible moment.
      p = moveSlot(p, hourly, w, forward: false)!;
      expect(titleAt(hourly, p), 'H18');
      expect(p.anchor, at(18, 30));
      expect(p.viewStart, at(18, 30));
      // H17 (clipped to 17:30) is not visible: scroll back just enough.
      p = moveSlot(p, hourly, w, forward: false)!;
      expect(titleAt(hourly, p), 'H17');
      expect(p.viewStart, at(17, 30));
      expect(p.anchor, at(17, 30));
      // Nothing before the browsable past.
      expect(moveSlot(p, hourly, w, forward: false), isNull);
    });

    test('the window follows forward in half-hour steps', () {
      var p = GuidePosition.at(w);
      for (var i = 0; i < 2; i++) {
        p = moveSlot(p, hourly, w, forward: true)!;
      }
      expect(titleAt(hourly, p), 'H20');
      expect(p.viewStart, at(18, 30)); // 20:00-21:00 fully visible
      p = moveSlot(p, hourly, w, forward: true)!;
      expect(titleAt(hourly, p), 'H21');
      // 21:00 is the window end: scroll until 30 minutes of it show.
      expect(p.viewStart, at(19));
      expect(p.anchor, at(21));
      expect(p.anchor.isBefore(p.viewEnd), isTrue);
    });

    test('the last slot of a row ends the move', () {
      var p = GuidePosition.at(w);
      GuidePosition? next = p;
      var steps = 0;
      while ((next = moveSlot(p, hourly, w, forward: true)) != null) {
        p = next!;
        steps++;
      }
      // H19..H23, then the gap to the end of the guide window; each step
      // scrolls only until 30 minutes of the new slot show.
      expect(steps, 6);
      expect(hourly[slotIndexAt(hourly, p.anchor)].isGap, isTrue);
      expect(p.anchor, at(0, 0, 16));
      expect(p.viewStart, at(22));
    });

    test('viewFor leaves a window that shows enough alone', () {
      final slot = GuideSlot(
        at(20, 50),
        at(21, 20),
        prog('x', at(20, 50), at(21, 20)),
      );
      expect(viewFor(slot, at(18, 30), w), at(19)); // 10 min -> scroll
      expect(viewFor(slot, at(19), w), at(19));
      final short = GuideSlot(at(20, 50), at(20, 58));
      expect(viewFor(short, at(18, 30), w), at(18, 30)); // all 8 min visible
      final cut = GuideSlot(at(20, 55), at(21, 5));
      expect(viewFor(cut, at(18, 30), w), at(19)); // half of it hidden
    });

    test('shiftView moves the window and keeps the anchor inside', () {
      final p = GuidePosition.at(w);
      final later = shiftView(p, 4, w);
      expect(later.viewStart, at(20, 30));
      expect(later.anchor, at(20, 30));
      final back = shiftView(later, -10, w);
      expect(back.viewStart, w.minTime);
      expect(back.anchor.isBefore(back.viewEnd), isTrue);
      expect(back.anchor, at(19, 59));
    });

    test('clampPosition keeps an old position valid as time passes', () {
      final p = GuidePosition(
        row: 2,
        anchor: at(17, 40),
        viewStart: at(17, 30),
      );
      final later = GuideWindow(at(19, 10)); // minTime 18:00
      final kept = clampPosition(p, later);
      expect(kept.row, 2);
      expect(kept.viewStart, at(18));
      expect(kept.anchor, at(18));
      final current = GuidePosition.at(later);
      expect(clampPosition(current, later), same(current));
    });
  });
}
