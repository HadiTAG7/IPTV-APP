// OK pressed while an Up/Down zap is still pending must open the channel
// panel on the channel actually playing, and nothing may tune behind it.
// All data is synthetic (127.0.0.1 URLs, made-up names).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/live/live_models.dart';
import 'package:iptv_player/player/ui/play_request.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/widgets/channel_tile.dart';

import 'support/player_harness.dart';

const _panel = ValueKey('channel-panel');

String _url(String key) => 'http://127.0.0.1:9/live/$key.ts';

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
  await db.catalogDao.upsertCategories(id, gen, const [
    CategoryData(kind: ContentKind.live, key: 'news', name: 'News'),
  ]);
  await db.catalogDao.upsertChannels(id, gen, [
    for (var i = 1; i <= 5; i++)
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

bool _rowFocused(int index) => focusedIn(ValueKey('channel-row-$index'));

ChannelTile _tile(WidgetTester tester, int index) =>
    tester.widget<ChannelTile>(find.byKey(ValueKey('channel-row-$index')));

void main() {
  testWidgets('OK during a pending zap: the panel opens on the channel '
      'playing and nothing tunes behind it', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final id = await _seed(rig);
    await pumpPlayerApp(tester, rig, locale: en);
    await openPlayerFor(tester, _request(id, 'ch2'));
    await tester.pump(const Duration(seconds: 5));
    expect(rig.openedUrls, [_url('ch2')]);

    // Up: the banner moves to Channel 3, the stream follows after 350 ms.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 100));
    // OK within the debounce opens the panel.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);

    expect(find.byKey(_panel), findsOneWidget);
    // Nothing was tuned behind the open panel.
    expect(rig.openedUrls, [_url('ch2')]);
    // Focus and the "playing" highlight are on the same row.
    // (Today: row 1 focused, row 2 selected.)
    expect(_rowFocused(1), isTrue);
    expect(_tile(tester, 1).selected, isTrue);
    await disposeRig(tester, rig);
  });
}
