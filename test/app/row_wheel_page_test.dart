// On desktop the vertical wheel over a long row inside a vertical page
// scrolls the page first.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/scroll_behavior.dart';

void main() {
  testWidgets('the vertical wheel over a long row inside a vertical page '
      'scrolls the page', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final page = ScrollController();
    final row = ScrollController();
    addTearDown(page.dispose);
    addTearDown(row.dispose);
    // Like the Search page: a 50-poster row inside a vertical list.
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: ListView(
            controller: page,
            children: [
              const SizedBox(height: 100, child: Text('channels')),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  controller: row,
                  scrollDirection: Axis.horizontal,
                  itemCount: 50,
                  itemExtent: 112,
                  itemBuilder: (_, i) => Text('movie $i'),
                ),
              ),
              for (var i = 0; i < 30; i++)
                SizedBox(height: 80, child: Text('row $i')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    // Three 60 px wheel notches down with the pointer resting on the row.
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(const Offset(200, 200)));
    for (var i = 0; i < 3; i++) {
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 60)));
      await tester.pump();
    }
    expect(row.offset, 0, reason: 'the row slid sideways instead');
    expect(page.offset, 180);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
