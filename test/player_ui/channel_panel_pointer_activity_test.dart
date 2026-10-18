// The channel panel's auto-hide timer must count trackpad scrolling and
// pointer hovering as activity. All data is synthetic.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/live/live_models.dart';
import 'package:iptv_player/player/ui/play_request.dart';
import 'package:iptv_player/sources/models.dart';

import 'support/player_harness.dart';

const _panel = ValueKey('channel-panel');

String _url(String key) => 'http://127.0.0.1:9/live/$key.ts';

Future<int> _seed(PlayerRig rig, {int news = 200}) async {
  final db = rig.db;
  final id = await db.sourcesDao.create(
    const SourceConfig(
      kind: SourceKind.m3uUrl,
      url: 'http://127.0.0.1:9/list.m3u',
      name: 'Home',
    ),
  );
  final gen = await db.catalogDao.beginGeneration(id);
  await db.catalogDao.upsertCategories(id, gen, const [
    CategoryData(kind: ContentKind.live, key: 'news', name: 'News'),
  ]);
  await db.catalogDao.upsertChannels(id, gen, [
    for (var i = 1; i <= news; i++)
      ChannelData(
        key: 'ch$i',
        name: 'Channel $i',
        num: 100 + i,
        url: _url('ch$i'),
        categoryKeys: const ['news'],
      ),
  ]);
  await db.catalogDao.commitGeneration(id, gen);
  return id;
}

PlayRequest _request(int sourceId, String key) => PlayRequest(
  sourceId: sourceId,
  item: PlayableRef(kind: PlayableKind.live, key: key, url: _url(key)),
  categoryKey: 'news',
  list: const LiveList.category('news'),
);

double _scrollOf(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find
                .descendant(
                  of: find.byKey(_panel),
                  matching: find.byType(ListView),
                )
                .last,
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position
    .pixels;

void main() {
  testWidgets('Windows: trackpad scrolling the channels keeps the panel up', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final id = await _seed(rig);
    await pumpPlayerApp(
      tester,
      rig,
      tv: false,
      platform: TargetPlatform.windows,
    );
    await openPlayerFor(tester, _request(id, 'ch1'));
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(_panel), findsOneWidget);

    final channels = find
        .descendant(of: find.byKey(_panel), matching: find.byType(ListView))
        .last;
    final at = tester.getCenter(channels);
    final pad = await tester.startGesture(at, kind: PointerDeviceKind.trackpad);
    // Two-finger scrolling for 16 s: 30 px every 500 ms.
    var scrolled = 0.0;
    for (var i = 1; i <= 32; i++) {
      await pad.panZoomUpdate(at, pan: Offset(0, -30.0 * i));
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byKey(_panel).evaluate().isNotEmpty) {
        scrolled = _scrollOf(tester);
      } else {
        fail(
          'panel closed after ${i * 500} ms of trackpad scrolling '
          '(list scrolled $scrolled px so far)',
        );
      }
    }
    await pad.panZoomEnd();
    await disposeRig(tester, rig);
  });

  testWidgets('Android: moving a mouse over the panel keeps it up', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final id = await _seed(rig);
    await pumpPlayerApp(tester, rig);
    await openPlayerFor(tester, _request(id, 'ch1'));
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(_panel), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(200, 100));
    for (var i = 1; i <= 32; i++) {
      await mouse.moveTo(Offset(200, 100.0 + (i % 2) * 40));
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byKey(_panel), findsOneWidget);
    await disposeRig(tester, rig);
  });
}
