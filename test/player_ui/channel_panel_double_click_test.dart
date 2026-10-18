// Double-clicking the OSD Channels button opens the panel on the list
// playing; the second click must not pick whatever is under the pointer.
// All data is synthetic.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/live/live_models.dart';
import 'package:iptv_player/player/ui/channel_panel.dart';
import 'package:iptv_player/player/ui/play_request.dart';
import 'package:iptv_player/sources/models.dart';

import 'support/player_harness.dart';

const _panel = ValueKey('channel-panel');
const _osd = ValueKey('player-osd');

String _url(String key) => 'http://127.0.0.1:9/live/$key.ts';

/// 30 categories cat0..cat29; 40 channels in cat0, three in the others.
Future<int> _seed(PlayerRig rig) async {
  final db = rig.db;
  final id = await db.sourcesDao.create(
    const SourceConfig(
      kind: SourceKind.m3uUrl,
      url: 'http://127.0.0.1:9/list.m3u',
      name: 'Home',
    ),
  );
  final gen = await db.catalogDao.beginGeneration(id);
  await db.catalogDao.upsertCategories(id, gen, [
    for (var c = 0; c < 30; c++)
      CategoryData(kind: ContentKind.live, key: 'cat$c', name: 'Group $c'),
  ]);
  await db.catalogDao.upsertChannels(id, gen, [
    for (var c = 0; c < 30; c++)
      for (var i = 1; i <= (c == 0 ? 40 : 3); i++)
        ChannelData(
          key: 'c${c}_$i',
          name: 'Channel $c-$i',
          num: c * 10 + i,
          url: _url('c${c}_$i'),
          categoryKeys: ['cat$c'],
        ),
  ]);
  await db.catalogDao.commitGeneration(id, gen);
  return id;
}

void main() {
  // Milliseconds between the two clicks: a quick and a usual double click.
  for (final gap in const [64, 120]) {
    forLocales((locale) {
      testWidgets('a double click on Channels ($gap ms apart) opens the '
          'playing category and plays nothing (${locale.languageCode})', (
        tester,
      ) async {
        final rig = PlayerRig()..autoPlay();
        final id = await _seed(rig);
        await pumpPlayerApp(
          tester,
          rig,
          tv: false,
          locale: locale,
          platform: TargetPlatform.windows,
        );
        await openPlayerFor(
          tester,
          PlayRequest(
            sourceId: id,
            item: PlayableRef(
              kind: PlayableKind.live,
              key: 'c0_1',
              url: _url('c0_1'),
            ),
            categoryKey: 'cat0',
            list: const LiveList.category('cat0'),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: const Offset(640, 360));
        await mouse.moveTo(const Offset(650, 360));
        await settle(tester);
        expect(find.byKey(_osd), findsOneWidget);

        final at = tester.getCenter(
          find.byKey(const ValueKey('player-osd-channels')),
        );
        await mouse.moveTo(at);
        await tester.pump();
        // A double click (button held 32 ms), frames every 16 ms.
        Future<void> frames(int ms) async {
          for (var t = 0; t < ms; t += 16) {
            await tester.pump(const Duration(milliseconds: 16));
          }
        }

        await mouse.down(at);
        await frames(32);
        await mouse.up();
        await frames(gap);
        await mouse.down(at);
        await frames(32);
        await mouse.up();
        await tester.pump(const Duration(milliseconds: 400));
        await settle(tester);

        expect(rig.openedUrls, [_url('c0_1')]);
        expect(find.byKey(_panel), findsOneWidget);
        expect(
          tester.state<ChannelPanelState>(find.byType(ChannelPanel)).selected,
          const LiveList.category('cat0'),
        );
        await disposeRig(tester, rig);
      });
    });
  }
}
