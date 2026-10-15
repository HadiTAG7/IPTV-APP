// Geometry and painting of the guide grid: one CustomPaint per channel row
// plus the time header. Time runs away from the channel column: left to
// right in LTR, right to left in RTL.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../theme/tokens.dart';
import '../../widgets/bidi_text.dart';
import 'guide_model.dart';

/// Maps times of the visible window onto a strip [width] pixels wide.
@immutable
class GuideTimeScale {
  const GuideTimeScale({
    required this.viewStart,
    required this.width,
    required this.textDirection,
    this.span = GuideTimes.span,
  });

  final DateTime viewStart;
  final double width;
  final TextDirection textDirection;
  final Duration span;

  DateTime get viewEnd => viewStart.add(span);

  bool get rtl => textDirection == TextDirection.rtl;

  /// Horizontal position of [t] (outside `[0, width]` when out of view).
  double xFor(DateTime t) {
    final f = t.difference(viewStart).inMilliseconds / span.inMilliseconds;
    final x = f * width;
    return rtl ? width - x : x;
  }

  /// The time at horizontal position [x].
  DateTime timeAt(double x) {
    final along = rtl ? width - x : x;
    final ms = (along / width * span.inMilliseconds).round();
    return viewStart.add(Duration(milliseconds: ms));
  }

  /// Horizontal extent `(left, right)` of the visible part of [slot], or
  /// null when it is outside the window.
  (double, double)? extentOf(GuideSlot slot) {
    if (!slot.stop.isAfter(viewStart) || !slot.start.isBefore(viewEnd)) {
      return null;
    }
    final a = xFor(slot.start.isBefore(viewStart) ? viewStart : slot.start);
    final b = xFor(slot.stop.isAfter(viewEnd) ? viewEnd : slot.stop);
    return (math.min(a, b), math.max(a, b));
  }

  /// Index of the slot drawn at [x], or null.
  int? slotIndexAtX(List<GuideSlot> slots, double x) {
    if (x < 0 || x > width || slots.isEmpty) return null;
    final t = timeAt(x);
    final i = slotIndexAt(slots, t);
    return i >= 0 && slots[i].contains(t) ? i : null;
  }

  /// Indexes of the slots at least partly inside the window.
  List<int> visibleSlots(List<GuideSlot> slots) => [
    for (final (i, s) in slots.indexed)
      if (extentOf(s) != null) i,
  ];

  /// Half-hour boundaries inside the window (header labels).
  List<DateTime> ticks() {
    final ticks = <DateTime>[];
    for (
      var t = ceilToSlot(viewStart);
      t.isBefore(viewEnd);
      t = t.add(GuideTimes.slot)
    ) {
      ticks.add(t);
    }
    return ticks;
  }

  @override
  bool operator ==(Object other) =>
      other is GuideTimeScale &&
      other.viewStart == viewStart &&
      other.width == width &&
      other.textDirection == textDirection &&
      other.span == span;

  @override
  int get hashCode => Object.hash(viewStart, width, textDirection, span);
}

/// Colours and text styles of the grid.
@immutable
class GuideGridStyle {
  const GuideGridStyle({
    required this.title,
    required this.time,
    this.future = AppColors.surfaceHigh,
    this.current = AppColors.surfaceHighest,
    this.past = AppColors.surface,
    this.gap = AppColors.background,
    this.focused = AppColors.accent,
    this.onFocused = AppColors.onAccent,
    this.nowLine = AppColors.error,
    this.gapText = AppColors.textDisabled,
    this.pastText = AppColors.textSecondary,
  });

  factory GuideGridStyle.of(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GuideGridStyle(
      title: text.labelLarge ?? const TextStyle(fontSize: 14),
      time: text.labelSmall ?? const TextStyle(fontSize: 11),
    );
  }

  final TextStyle title;
  final TextStyle time;
  final Color future;
  final Color current;
  final Color past;
  final Color gap;
  final Color focused;
  final Color onFocused;
  final Color nowLine;
  final Color gapText;
  final Color pastText;

  @override
  bool operator ==(Object other) =>
      other is GuideGridStyle && other.title == title && other.time == time;

  @override
  int get hashCode => Object.hash(title, time);
}

/// Paints one channel row: a rounded block per programme or gap of the
/// visible window, the focused block in the accent colour (outlined when
/// the grid is not focused) and the "now" line.
class GuideRowPainter extends CustomPainter {
  GuideRowPainter({
    required this.slots,
    required this.viewStart,
    required this.now,
    required this.textDirection,
    required this.style,
    required this.timeFormat,
    required this.noInfoLabel,
    this.focusedIndex,
    this.gridFocused = false,
  });

  /// Null while the row's programmes are loading (nothing but the now line
  /// is drawn).
  final List<GuideSlot>? slots;
  final DateTime viewStart;
  final DateTime now;
  final TextDirection textDirection;
  final GuideGridStyle style;
  final DateFormat timeFormat;
  final String noInfoLabel;
  final int? focusedIndex;
  final bool gridFocused;

  static const _gapX = 2.0;
  static const _gapY = 3.0;
  static const _pad = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = GuideTimeScale(
      viewStart: viewStart,
      width: size.width,
      textDirection: textDirection,
    );
    final slots = this.slots;
    if (slots != null) {
      for (final i in scale.visibleSlots(slots)) {
        _paintSlot(canvas, size, scale, slots[i], focused: i == focusedIndex);
      }
    }
    final x = scale.xFor(now);
    if (x >= 0 && x <= size.width) {
      canvas.drawRect(
        Rect.fromLTWH(x - 1, 0, 2, size.height),
        Paint()..color = style.nowLine,
      );
    }
  }

  void _paintSlot(
    Canvas canvas,
    Size size,
    GuideTimeScale scale,
    GuideSlot slot, {
    required bool focused,
  }) {
    final (left, right) = scale.extentOf(slot)!;
    final rect = Rect.fromLTRB(
      left + _gapX / 2,
      _gapY,
      math.max(left + _gapX / 2, right - _gapX / 2),
      size.height - _gapY,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(Radii.sm),
    );
    final past = !slot.stop.isAfter(now);
    final filled = focused && gridFocused;
    final fill = filled
        ? style.focused
        : slot.isGap
        ? style.gap
        : slot.contains(now)
        ? style.current
        : past
        ? style.past
        : style.future;
    canvas.drawRRect(rrect, Paint()..color = fill);
    if (focused && !gridFocused) {
      canvas.drawRRect(
        rrect.deflate(1),
        Paint()
          ..color = style.focused
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    final textWidth = rect.width - 2 * _pad;
    if (textWidth < 12) return;
    final programme = slot.programme;
    final titleColor = filled
        ? style.onFocused
        : slot.isGap
        ? style.gapText
        : past
        ? style.pastText
        : style.title.color;
    final title = programme?.title ?? noInfoLabel;
    final titleTop = rect.top + _pad - 2;
    final titleHeight = _drawText(
      canvas,
      title,
      style.title.copyWith(color: titleColor),
      rect,
      titleTop,
      textWidth,
    );
    if (programme != null) {
      final time = timeFormat.format(programme.start.toLocal());
      _drawText(
        canvas,
        time,
        style.time.copyWith(color: filled ? style.onFocused : style.time.color),
        rect,
        titleTop + titleHeight + 2,
        textWidth,
      );
    }
  }

  /// Draws one line of [text] at the reading-start edge of [rect]; returns
  /// its height.
  double _drawText(
    Canvas canvas,
    String text,
    TextStyle textStyle,
    Rect rect,
    double top,
    double maxWidth,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: textDirectionFor(text),
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    final dx = textDirection == TextDirection.rtl
        ? rect.right - _pad - painter.width
        : rect.left + _pad;
    painter.paint(canvas, Offset(dx, top));
    final height = painter.height;
    painter.dispose();
    return height;
  }

  @override
  bool shouldRepaint(GuideRowPainter old) =>
      !identical(old.slots, slots) ||
      old.viewStart != viewStart ||
      old.now != now ||
      old.textDirection != textDirection ||
      old.style != style ||
      !identical(old.timeFormat, timeFormat) ||
      old.noInfoLabel != noInfoLabel ||
      old.focusedIndex != focusedIndex ||
      old.gridFocused != gridFocused;
}

/// Paints the time header: a label and a tick at every half hour of the
/// window, and a marker at "now".
class GuideHeaderPainter extends CustomPainter {
  GuideHeaderPainter({
    required this.viewStart,
    required this.now,
    required this.textDirection,
    required this.labelStyle,
    required this.timeFormat,
    this.tickColor = AppColors.outline,
    this.nowColor = AppColors.error,
  });

  final DateTime viewStart;
  final DateTime now;
  final TextDirection textDirection;
  final TextStyle labelStyle;
  final DateFormat timeFormat;
  final Color tickColor;
  final Color nowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = GuideTimeScale(
      viewStart: viewStart,
      width: size.width,
      textDirection: textDirection,
    );
    final tick = Paint()..color = tickColor;
    for (final t in scale.ticks()) {
      final x = scale.xFor(t);
      canvas.drawRect(Rect.fromLTWH(x - 0.5, size.height - 6, 1, 6), tick);
      final painter = TextPainter(
        text: TextSpan(text: timeFormat.format(t.toLocal()), style: labelStyle),
        textDirection: textDirection,
        maxLines: 1,
      )..layout();
      final dx = scale.rtl ? x - 4 - painter.width : x + 4;
      if (dx >= 0 && dx + painter.width <= size.width) {
        painter.paint(
          canvas,
          Offset(dx, (size.height - 6 - painter.height) / 2),
        );
      }
      painter.dispose();
    }
    final x = scale.xFor(now);
    if (x >= 0 && x <= size.width) {
      final path = Path()
        ..moveTo(x - 5, size.height - 6)
        ..lineTo(x + 5, size.height - 6)
        ..lineTo(x, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = nowColor);
    }
  }

  @override
  bool shouldRepaint(GuideHeaderPainter old) =>
      old.viewStart != viewStart ||
      old.now != now ||
      old.textDirection != textDirection ||
      old.labelStyle != labelStyle ||
      !identical(old.timeFormat, timeFormat);
}
