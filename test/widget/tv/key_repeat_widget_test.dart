import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/theme/tokens.dart';
import 'package:iptv_player/tv/key_repeat.dart';
import 'package:iptv_player/tv/tv_focusable.dart';

import '../support/tv_harness.dart';

void main() {
  late List<FocusNode> rows;
  late FakeClock clock;

  setUp(() {
    rows = List.generate(60, (i) => FocusNode(debugLabel: 'row-$i'));
    clock = FakeClock(DateTime.utc(2026, 10, 14));
  });

  tearDown(() {
    for (final n in rows) {
      n.dispose();
    }
  });

  int focused() => rows.indexWhere((n) => n.hasPrimaryFocus);

  Widget list({KeyJumpCallback? onJump}) => KeyRepeatGuard(
    onJump: onJump,
    child: ListView.builder(
      itemExtent: TvLayout.channelExtent,
      itemCount: rows.length,
      itemBuilder: (context, i) => TvFocusable(
        focusNode: rows[i],
        autofocus: i == 0,
        onSelect: () {},
        child: Text('Row $i'),
      ),
    ),
  );

  Future<void> repeatAfter(WidgetTester tester, int ms) async {
    clock.advance(Duration(milliseconds: ms));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
  }

  for (final locale in testLocales) {
    group('held arrows (${locale.languageCode})', () {
      testWidgets('repeats are limited to about 10 per second', (tester) async {
        await pumpTv(tester, list(), locale: locale);
        KeyRepeatThrottle.instance = KeyRepeatThrottle(clock: clock);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(focused(), 1);

        // Android remotes repeat roughly every 50 ms: every other one passes.
        for (var i = 0; i < 8; i++) {
          await repeatAfter(tester, 50);
        }
        expect(focused(), 5);
        expect(KeyRepeatThrottle.instance.isRepeating, isTrue);

        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(KeyRepeatThrottle.instance.isRepeating, isFalse);
      });

      testWidgets('after 1 s held, focus jumps 5 rows per repeat', (
        tester,
      ) async {
        await pumpTv(tester, list(), locale: locale);
        KeyRepeatThrottle.instance = KeyRepeatThrottle(clock: clock);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await repeatAfter(tester, 500);
        expect(focused(), 2);
        await repeatAfter(tester, 500); // held 1.0 s
        expect(focused(), 7);
        await repeatAfter(tester, 150);
        expect(focused(), 12);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();

        // A new press starts slow again.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await repeatAfter(tester, 150);
        expect(focused(), 14);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      });

      testWidgets('lists can take over jumps with onJump', (tester) async {
        final jumps = <(TraversalDirection, int)>[];
        await pumpTv(
          tester,
          list(
            onJump: (direction, count) {
              jumps.add((direction, count));
              return true;
            },
          ),
          locale: locale,
        );
        KeyRepeatThrottle.instance = KeyRepeatThrottle(clock: clock);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        await repeatAfter(tester, 1000);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(jumps, [(TraversalDirection.down, 5)]);
        expect(focused(), 1, reason: 'the callback handled the jump');
      });
    });
  }
}
