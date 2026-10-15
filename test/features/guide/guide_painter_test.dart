import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:iptv_player/features/guide/guide_grid.dart';
import 'package:iptv_player/features/guide/guide_model.dart';
import 'package:iptv_player/features/guide/guide_painter.dart';
import 'package:iptv_player/widgets/bidi_text.dart';

import 'support/guide_fixtures.dart';

const _style = GuideGridStyle(
  title: TextStyle(fontSize: 14),
  time: TextStyle(fontSize: 11),
);

String? _title(GuideSlot s) => s.programme?.title;

Finder _rowPaint(int row) => find.descendant(
  of: find.byKey(ValueKey('guide-row-$row')),
  matching: find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is GuideRowPainter,
  ),
);

void main() {
  final window = GuideWindow(guideNow);
  final view = guideViewStart; // 18:30 local
  final slots = window.slotsFor(programmesFor(1)); // hourly, 1.0 on air

  group('GuideTimeScale', () {
    for (final rtl in [false, true]) {
      final dir = rtl ? TextDirection.rtl : TextDirection.ltr;
      final scale = GuideTimeScale(
        viewStart: view,
        width: 500,
        textDirection: dir,
      );
      double x(double ltr) => rtl ? 500 - ltr : ltr;

      test('${dir.name}: times map onto the strip and back', () {
        expect(scale.xFor(view), x(0));
        expect(scale.xFor(view.add(GuideTimes.span)), x(500));
        expect(scale.xFor(view.add(GuideTimes.slot)), x(100));
        expect(scale.timeAt(x(100)), view.add(GuideTimes.slot));
        expect(scale.timeAt(x(250)), view.add(const Duration(minutes: 75)));
      });

      test('${dir.name}: visible window, extents and hits', () {
        // 18:30-21:00 shows Show 1.0 (clipped), 1.1 and 1.2.
        expect(
          [for (final i in scale.visibleSlots(slots)) _title(slots[i])],
          [progTitle(1, 0), progTitle(1, 1), progTitle(1, 2)],
        );
        final onAir = slots.indexWhere((s) => s.contains(guideNow));
        expect(_title(slots[onAir]), progTitle(1, 0));
        // Show 1.0 runs 18:00-19:00: only 18:30-19:00 is drawn.
        final (left, right) = scale.extentOf(slots[onAir])!;
        expect((left, right), rtl ? (400.0, 500.0) : (0.0, 100.0));
        // Hidden slots have no extent.
        expect(scale.extentOf(slots.first), isNull);
        // Hits: 19:15 is Show 1.1, outside the strip nothing.
        final at1915 = scale.xFor(view.add(const Duration(minutes: 45)));
        expect(_title(slots[scale.slotIndexAtX(slots, at1915)!]), 'Show 1.1');
        expect(scale.slotIndexAtX(slots, -1), isNull);
        expect(scale.slotIndexAtX(slots, 501), isNull);
        expect(scale.slotIndexAtX(const [], 10), isNull);
      });
    }

    test('half-hour ticks of the window', () {
      final scale = GuideTimeScale(
        viewStart: view,
        width: 500,
        textDirection: TextDirection.ltr,
      );
      expect(scale.ticks(), [
        for (var i = 0; i < 5; i++) view.add(GuideTimes.slot * i),
      ]);
    });
  });

  group('painters', () {
    late final DateFormat format;
    setUpAll(() async {
      await initializeDateFormatting('en');
      format = DateFormat.Hm('en');
    });

    void paintRow(GuideRowPainter painter) {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(520, 64));
      recorder.endRecording().dispose();
    }

    test('rows paint in both directions, focused or not, and loading', () {
      for (final dir in TextDirection.values) {
        for (final focused in [false, true]) {
          paintRow(
            GuideRowPainter(
              slots: slots,
              viewStart: view,
              now: guideNow,
              textDirection: dir,
              style: _style,
              timeFormat: format,
              noInfoLabel: 'No programme info',
              focusedIndex: 1,
              gridFocused: focused,
            ),
          );
        }
        paintRow(
          GuideRowPainter(
            slots: null,
            viewStart: view,
            now: guideNow,
            textDirection: dir,
            style: _style,
            timeFormat: format,
            noInfoLabel: 'No programme info',
          ),
        );
        final header = GuideHeaderPainter(
          viewStart: view,
          now: guideNow,
          textDirection: dir,
          labelStyle: const TextStyle(fontSize: 11),
          timeFormat: format,
        );
        final recorder = ui.PictureRecorder();
        header.paint(Canvas(recorder), const Size(520, 24));
        recorder.endRecording().dispose();
      }
    });

    test('rows repaint only when what they show changes', () {
      GuideRowPainter row({int? focused, DateTime? now, List<GuideSlot>? s}) =>
          GuideRowPainter(
            slots: s ?? slots,
            viewStart: view,
            now: now ?? guideNow,
            textDirection: TextDirection.ltr,
            style: _style,
            timeFormat: format,
            noInfoLabel: '-',
            focusedIndex: focused,
          );
      expect(row().shouldRepaint(row()), isFalse);
      expect(row(focused: 1).shouldRepaint(row()), isTrue);
      expect(
        row(now: guideNow.add(const Duration(minutes: 1))).shouldRepaint(row()),
        isTrue,
      );
      expect(row(s: [...slots]).shouldRepaint(row()), isTrue);
    });
  });

  group('in the grid (seeded guide, clock at 18:47)', () {
    for (final rtl in [false, true]) {
      final dir = rtl ? TextDirection.rtl : TextDirection.ltr;
      testWidgets('${dir.name}: rows paint the visible window; taps hit', (
        tester,
      ) async {
        final db = openGuideDb();
        await seedGuide(db);
        final player = PlayerLog();
        await pumpGuideApp(tester, db: db, player: player, rtl: rtl);
        await press(tester, LogicalKeyboardKey.arrowDown); // Guide tab

        // Row 0 shows Show 1.0..1.2 with Show 1.0 focused.
        final painter =
            tester.widget<CustomPaint>(_rowPaint(0)).painter!
                as GuideRowPainter;
        final width = tester.getSize(_rowPaint(0)).width;
        final scale = GuideTimeScale(
          viewStart: painter.viewStart,
          width: width,
          textDirection: dir,
        );
        expect(painter.viewStart, guideViewStart);
        expect(painter.now, guideNow);
        expect(painter.textDirection, dir);
        expect(
          [
            for (final i in scale.visibleSlots(painter.slots!))
              _title(painter.slots![i]),
          ],
          [progTitle(1, 0), progTitle(1, 1), progTitle(1, 2)],
        );
        expect(_title(painter.slots![painter.focusedIndex!]), progTitle(1, 0));
        expect(painter.gridFocused, isFalse); // focus is on the rail

        // Tap channel 2's 19:00-19:30 programme: it becomes the focus.
        Offset pointAt(int row, Duration fromView) {
          final rect = tester.getRect(_rowPaint(row));
          return Offset(
            rect.left + scale.xFor(guideViewStart.add(fromView)),
            rect.center.dy,
          );
        }

        await tester.tapAt(pointAt(1, const Duration(minutes: 40)));
        await settle(tester);
        final title = find.byKey(const ValueKey('guide-info-title'));
        expect(tester.widget<BidiText>(title).text, progTitle(2, 1));
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'guide-grid');
        // Tapping it again shows its details (it is not on air).
        await tester.tapAt(pointAt(1, const Duration(minutes: 40)));
        await settle(tester);
        expect(find.byKey(const ValueKey('guide-info')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('guide-info-close')));
        await settle(tester);

        // The programme on air plays on the second tap.
        await tester.tapAt(pointAt(0, const Duration(minutes: 10)));
        await settle(tester);
        expect(tester.widget<BidiText>(title).text, progTitle(1, 0));
        await tester.tapAt(pointAt(0, const Duration(minutes: 10)));
        await settle(tester);
        expect(player.requests.single.item.key, 'c1');

        // Dragging toward the reading start moves the window later.
        final grid = tester.state<GuideGridState>(find.byType(GuideGrid));
        final start = pointAt(2, const Duration(minutes: 100));
        await tester.dragFrom(start, Offset(rtl ? 150 : -150, 0));
        await settle(tester);
        expect(grid.position.viewStart.isAfter(guideViewStart), isTrue);
        await disposeApp(tester, db);
      });
    }
  });
}
