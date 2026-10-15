// The guide grid's time model: programme slots per row and the focus
// position (row, anchor time, visible window). Pure Dart, no widgets.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show TextDirection, TraversalDirection;

import '../../epg/epg_models.dart';

/// Grid timing.
abstract final class GuideTimes {
  /// Header step; the visible window always starts on a slot boundary.
  static const slot = Duration(minutes: 30);

  /// Width of the visible window.
  static const span = Duration(minutes: 150);

  /// How far before now the grid can be browsed.
  static const past = Duration(hours: 1);

  /// How far after now the grid can be browsed (the guide keeps 3 days).
  static const ahead = Duration(days: 3);

  /// How far after the visible window programmes are loaded.
  static const loadAhead = Duration(hours: 12);
}

DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

/// The start of the half hour (in local time) holding [t], as UTC.
DateTime floorToSlot(DateTime t) {
  final l = t.toLocal();
  return DateTime(
    l.year,
    l.month,
    l.day,
    l.hour,
    l.minute - l.minute % GuideTimes.slot.inMinutes,
  ).toUtc();
}

/// [t] when it is on a half hour boundary, else the next boundary.
DateTime ceilToSlot(DateTime t) {
  final floor = floorToSlot(t);
  return floor.isAtSameMomentAs(t) ? floor : floor.add(GuideTimes.slot);
}

/// One block of a guide row: a programme, or a gap without programme info.
///
/// [start] and [stop] are the drawn extent (clipped to the grid's range and
/// to the previous programme); [programme] keeps the published times.
@immutable
class GuideSlot {
  const GuideSlot(this.start, this.stop, [this.programme]);

  final DateTime start;
  final DateTime stop;
  final EpgProgramme? programme;

  bool get isGap => programme == null;

  Duration get duration => stop.difference(start);

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(stop);

  @override
  bool operator ==(Object other) =>
      other is GuideSlot &&
      other.start == start &&
      other.stop == stop &&
      identical(other.programme, programme);

  @override
  int get hashCode => Object.hash(start, stop, programme);

  @override
  String toString() =>
      'GuideSlot(${programme?.title ?? '-'} ${start.toIso8601String()} '
      '- ${stop.toIso8601String()})';
}

/// Lays [programmes] (ordered by start) out on `[from, to)`, filling holes
/// with gap slots. Programmes outside the range are dropped; one that
/// starts before the previous one ended is clipped to start after it.
List<GuideSlot> buildSlots(
  List<EpgProgramme> programmes,
  DateTime from,
  DateTime to,
) {
  final slots = <GuideSlot>[];
  var cursor = from;
  for (final p in programmes) {
    if (!p.stop.isAfter(cursor) || !p.start.isBefore(to)) continue;
    final start = _later(p.start, cursor);
    if (start.isAfter(cursor)) slots.add(GuideSlot(cursor, start));
    final stop = _earlier(p.stop, to);
    slots.add(GuideSlot(start, stop, p));
    cursor = stop;
  }
  if (cursor.isBefore(to)) slots.add(GuideSlot(cursor, to));
  return slots;
}

/// Index of the slot holding [t]: the last one starting at or before it
/// (0 before the first slot), or -1 when [slots] is empty.
int slotIndexAt(List<GuideSlot> slots, DateTime t) {
  if (slots.isEmpty) return -1;
  var lo = 0;
  var hi = slots.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (slots[mid].start.isAfter(t)) {
      hi = mid - 1;
    } else {
      lo = mid;
    }
  }
  return lo;
}

/// The browsable time range at [now].
@immutable
class GuideWindow {
  GuideWindow(this.now)
    : minTime = floorToSlot(now.subtract(GuideTimes.past)),
      maxTime = now.add(GuideTimes.ahead);

  final DateTime now;

  /// Earliest time shown (a slot boundary).
  final DateTime minTime;

  /// Latest time shown.
  final DateTime maxTime;

  /// Latest start of the visible window.
  DateTime get lastViewStart =>
      _later(floorToSlot(maxTime.subtract(GuideTimes.span)), minTime);

  /// [viewStart] moved inside the browsable range.
  DateTime clampView(DateTime viewStart) =>
      _earlier(_later(viewStart, minTime), lastViewStart);

  /// Slots of a row with [programmes] over the whole browsable range.
  List<GuideSlot> slotsFor(List<EpgProgramme> programmes) =>
      buildSlots(programmes, minTime, maxTime);

  @override
  bool operator ==(Object other) => other is GuideWindow && other.now == now;

  @override
  int get hashCode => now.hashCode;
}

/// Focus position in the grid: a row, the time the focus is at (moving up
/// or down keeps it) and the start of the visible window.
@immutable
class GuidePosition {
  const GuidePosition({
    required this.row,
    required this.anchor,
    required this.viewStart,
  });

  /// The window showing [now], focus on [row] at [now].
  factory GuidePosition.at(GuideWindow window, {int row = 0}) => GuidePosition(
    row: row,
    anchor: window.now,
    viewStart: window.clampView(floorToSlot(window.now)),
  );

  final int row;
  final DateTime anchor;
  final DateTime viewStart;

  DateTime get viewEnd => viewStart.add(GuideTimes.span);

  GuidePosition copyWith({int? row, DateTime? anchor, DateTime? viewStart}) =>
      GuidePosition(
        row: row ?? this.row,
        anchor: anchor ?? this.anchor,
        viewStart: viewStart ?? this.viewStart,
      );

  @override
  bool operator ==(Object other) =>
      other is GuidePosition &&
      other.row == row &&
      other.anchor == anchor &&
      other.viewStart == viewStart;

  @override
  int get hashCode => Object.hash(row, anchor, viewStart);

  @override
  String toString() =>
      'GuidePosition(row $row, at ${anchor.toIso8601String()}, '
      'view ${viewStart.toIso8601String()})';
}

/// [p] moved by [delta] rows inside `[0, rowCount)`, keeping the anchor and
/// the window; null when the row would not change.
GuidePosition? moveRows(GuidePosition p, int delta, int rowCount) {
  if (rowCount <= 0) return null;
  final row = (p.row + delta).clamp(0, rowCount - 1);
  return row == p.row ? null : p.copyWith(row: row);
}

/// [p] moved to the next ([forward]) or previous slot of its row; null at
/// the end of the row. The window scrolls, in half-hour steps and as little
/// as possible, until at least 30 minutes of that slot (or all of a shorter
/// one) are visible; the anchor becomes the slot's first visible moment.
GuidePosition? moveSlot(
  GuidePosition p,
  List<GuideSlot> slots,
  GuideWindow window, {
  required bool forward,
}) {
  if (slots.isEmpty) return null;
  final i = slotIndexAt(slots, p.anchor);
  final j = forward ? i + 1 : i - 1;
  if (j < 0 || j >= slots.length) return null;
  final target = slots[j];
  if (!target.stop.isAfter(window.minTime) ||
      !target.start.isBefore(window.maxTime)) {
    return null;
  }
  final view = viewFor(target, p.viewStart, window);
  return GuidePosition(
    row: p.row,
    anchor: _later(target.start, view),
    viewStart: view,
  );
}

/// The window start that shows enough of [slot], starting from
/// [viewStart] (unchanged when it already does).
DateTime viewFor(GuideSlot slot, DateTime viewStart, GuideWindow window) {
  final need = slot.duration < GuideTimes.slot
      ? slot.duration
      : GuideTimes.slot;
  final viewEnd = viewStart.add(GuideTimes.span);
  final visible = _earlier(
    slot.stop,
    viewEnd,
  ).difference(_later(slot.start, viewStart));
  if (visible >= need) return viewStart;
  final next = slot.start.isBefore(viewStart)
      ? floorToSlot(slot.stop.subtract(need))
      : ceilToSlot(slot.start.add(need).subtract(GuideTimes.span));
  return window.clampView(next);
}

/// [p] with the window moved by [steps] half hours (touch drags); the
/// anchor stays inside the new window.
GuidePosition shiftView(GuidePosition p, int steps, GuideWindow window) {
  final view = window.clampView(p.viewStart.add(GuideTimes.slot * steps));
  final end = view.add(GuideTimes.span);
  var anchor = p.anchor;
  if (anchor.isBefore(view)) {
    anchor = view;
  } else if (!anchor.isBefore(end)) {
    anchor = end.subtract(const Duration(minutes: 1));
  }
  return GuidePosition(row: p.row, anchor: anchor, viewStart: view);
}

/// [p] kept valid at a new [window] (the clock moved on).
GuidePosition clampPosition(GuidePosition p, GuideWindow window) {
  final view = window.clampView(p.viewStart);
  if (view == p.viewStart && !p.anchor.isBefore(view)) return p;
  return shiftView(p.copyWith(viewStart: view), 0, window);
}

/// Whether a horizontal arrow moves forward in time: time runs from the
/// reading start, so Right is later in LTR and earlier in RTL. Null for
/// Up and Down.
bool? movesForward(TraversalDirection direction, TextDirection text) =>
    switch (direction) {
      TraversalDirection.right => text == TextDirection.ltr,
      TraversalDirection.left => text == TextDirection.rtl,
      TraversalDirection.up || TraversalDirection.down => null,
    };
