// "Close the window and play here" waits for the window to stop and exit,
// with the page behind still usable. Opening something else meanwhile must
// not stack a second player (nor start a stream while the window still
// holds the connection).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/ui/player_screen.dart';

import 'support/fake_detached_windows.dart';
import 'support/player_harness.dart';

/// Closes like [DetachedWindows.close]: it completes once the viewer has
/// exited ([exited]); every caller waits for that same close.
class _SlowCloseWindows extends RecordingDetachedWindows {
  _SlowCloseWindows(super.rig, {super.initial});

  final exited = Completer<void>();
  final _closes = <int, Future<void>>{};

  @override
  Future<void> close(int viewerId, {Duration? wait}) {
    closed.add(viewerId);
    return _closes[viewerId] ??= () async {
      await exited.future;
      state = [
        for (final w in state)
          if (w.id != viewerId) w,
      ];
    }();
  }
}

int _players() =>
    find.byType(PlayerScreen, skipOffstage: false).evaluate().length;

void main() {
  testWidgets('opening again while the window closes does nothing; one '
      'player opens once it has exited', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedXtream(rig);
    final other = await seedLive(rig);
    final windows = _SlowCloseWindows(
      rig,
      initial: [
        DetachedViewer(
          id: 3,
          sourceId: id,
          channelKey: '502',
          title: 'Panel Sport',
          maxConnections: 1,
          status: ViewerStatus.playing,
        ),
      ],
    );
    await pumpPlayerApp(
      tester,
      rig,
      tv: false,
      platform: TargetPlatform.windows,
      overrides: [detachedWindowsProvider.overrideWith(() => windows)],
    );

    await openPlayerFor(tester, xtreamRequest(id, '501'));
    await tester.tap(find.text('Close the window and play here'));
    await settle(tester);
    // The viewer is still stopping and exiting: nothing shows yet.
    expect(_players(), 0);
    expect(find.byType(AlertDialog), findsNothing);

    // The user, seeing nothing happen, opens the channel again, and one of
    // another source.
    await openPlayerFor(tester, xtreamRequest(id, '501'));
    await openPlayerFor(tester, liveRequest(other));
    expect(find.byType(AlertDialog), findsNothing);
    expect(_players(), 0);
    expect(rig.openedUrls, isEmpty);
    expect(windows.closed, [3]);

    // The viewer exits: one player, playing the first choice.
    windows.exited.complete();
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(_players(), 1);
    expect(rig.openedUrls.single, endsWith('/501.ts'));

    // Back leaves it; nothing is left behind.
    await tester.binding.handlePopRoute();
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(_players(), 0);

    // Opening works again.
    await openPlayerFor(tester, liveRequest(other));
    expect(_players(), 1);
    await disposeRig(tester, rig);
  });

  testWidgets('cancelling the question lets the next open through', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedXtream(rig);
    final windows = _SlowCloseWindows(
      rig,
      initial: [
        DetachedViewer(
          id: 3,
          sourceId: id,
          channelKey: '502',
          title: 'Panel Sport',
          maxConnections: 1,
          status: ViewerStatus.playing,
        ),
      ],
    );
    await pumpPlayerApp(
      tester,
      rig,
      tv: false,
      platform: TargetPlatform.windows,
      overrides: [detachedWindowsProvider.overrideWith(() => windows)],
    );
    await openPlayerFor(tester, xtreamRequest(id, '501'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    await openPlayerFor(tester, xtreamRequest(id, '501'));
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(_players(), 0);
    await disposeRig(tester, rig);
  });
}
