// A split-screen tile whose stream is lost (the watchdog gives up) still
// counts against a one-connection subscription until its slow stop has
// run: no other tile opens a second stream meanwhile. Synthetic data only.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/session/connection_guard.dart';

import '../support/fake_engine.dart';
import 'support/fake_detached_windows.dart';
import 'support/multiview_harness.dart';
import 'support/player_harness.dart';

String? _channel(String url) => url.contains('/501.')
    ? '501'
    : url.contains('/502.')
    ? '502'
    : null;

class _Streams {
  _Streams(this.rig, {required this.stopDelay}) {
    rig.engines.onCreate = (e) => e.onOpen = (e, r) async {
      final channel = _channel(r.url);
      if (channel != null) {
        e.stopDelay = stopDelay;
        _opens('engine $channel', engine: e);
      }
      // Panel News plays at first; once lost, every reconnect hangs
      // buffering (the server accepts the connection, sends nothing).
      if (channel == '501' && newsLost) {
        e.setState(buffering: true, playing: false);
        return;
      }
      e.emitFirstFrame();
    };
  }

  final PlayerRig rig;
  final Duration stopDelay;
  bool newsLost = false;
  final opens = <String>[];
  final overlaps = <String>[];

  bool _holds(FakeEngine e) {
    final last = e.opened.lastOrNull;
    return e.streamOpen && last != null && _channel(last.url) != null;
  }

  void _opens(String what, {FakeEngine? engine}) {
    final open = [
      for (final e in rig.engines.created)
        if (!identical(e, engine) && _holds(e))
          'engine ${_channel(e.opened.last.url)}',
    ];
    if (open.isNotEmpty) overlaps.add('$what while ${open.join(', ')}');
    opens.add(what);
  }
}

void main() {
  testWidgets('a tile whose stream was lost (the watchdog gave up), its stop '
      'slow (6 s): Panel Sport in tile 2 never opens while it is open', (
    tester,
  ) async {
    final rig = PlayerRig();
    final streams = _Streams(rig, stopDelay: const Duration(seconds: 6));
    final xtream = await seedXtream(rig);
    final free = await seedFree(rig);
    await pumpPlayerApp(
      tester,
      rig,
      tv: false,
      platform: TargetPlatform.windows,
      overrides: [
        detachedWindowsProvider.overrideWith(() => ListingDetachedWindows(rig)),
      ],
    );
    await openSplit(tester, freeRequest(free, 'f1'));
    await press(tester, LogicalKeyboardKey.keyC);
    await openedPicker(tester);
    await pickChannel(tester, 'Panel News', sourceId: xtream);
    final news = engineFor(rig, '/501.');
    expect(news.streamOpen, isTrue);
    expect(streams.opens, ['engine 501']);

    // The stream stalls: buffering, no data. Every reconnect hangs too.
    streams.newsLost = true;
    news.setState(buffering: true, playing: false);
    var failedAt = -1;
    for (var s = 0; s < 600; s++) {
      rig.clock.advance(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      if (inSlot(
        0,
        find.byKey(const ValueKey('multiview-failure')),
      ).evaluate().isNotEmpty) {
        failedAt = s;
        break;
      }
    }
    expect(failedAt, greaterThan(0), reason: 'the tile never failed');

    await addChannel(tester, 1, 'Panel Sport', sourceId: xtream);
    await tester.pump(const Duration(seconds: 8));
    await settleSplit(tester);
    expect(streams.opens.last, 'engine 502');
    expect(streams.overlaps, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(ConnectionGuard.longestStop);
    await disposeRig(tester, rig);
  });
}
