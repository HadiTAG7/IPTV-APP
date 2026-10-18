// On the TV canvas the channel panel shows typical Xtream channel names in
// full, so the HD/FHD/4K variants of a channel can be told apart. Synthetic
// names and URLs; the Tajawal font is loaded by flutter_test_config.dart.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/live/live_models.dart';
import 'package:iptv_player/player/ui/play_request.dart';
import 'package:iptv_player/sources/models.dart';

import 'support/player_harness.dart';

const _panel = ValueKey('channel-panel');

const _names = [
  'beIN SPORTS 1 HD',
  'beIN SPORTS 1 FHD',
  'beIN SPORTS 1 4K',
  'AR: MBC DRAMA HD',
  'SSC SPORTS 1 HD',
  'قناة الجزيرة الإخبارية',
];

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
    CategoryData(kind: ContentKind.live, key: 'g1', name: 'AR | MBC Group HD'),
  ]);
  await db.catalogDao.upsertChannels(id, gen, [
    for (var i = 0; i < _names.length; i++)
      ChannelData(
        key: 'c$i',
        name: _names[i],
        num: 1001 + i,
        url: _url('c$i'),
        categoryKeys: const ['g1'],
      ),
  ]);
  await db.catalogDao.commitGeneration(id, gen);
  return id;
}

void main() {
  testWidgets('TV: the panel shows typical channel names in full', (
    tester,
  ) async {
    final rig = PlayerRig()..autoPlay();
    final id = await _seed(rig);
    await pumpPlayerApp(tester, rig);
    await openPlayerFor(
      tester,
      PlayRequest(
        sourceId: id,
        item: PlayableRef(kind: PlayableKind.live, key: 'c0', url: _url('c0')),
        categoryKey: 'g1',
        list: const LiveList.category('g1'),
      ),
    );
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(_panel), findsOneWidget);

    final cut = <String>[];
    for (final name in [..._names, 'AR | MBC Group HD']) {
      final text = find.descendant(
        of: find.byKey(_panel),
        matching: find.text(name),
      );
      expect(text, findsOneWidget, reason: name);
      final p = tester.renderObject<RenderParagraph>(text);
      final full = TextPainter(
        text: TextSpan(text: name, style: p.text.style),
        textDirection: TextDirection.ltr,
        textScaler: p.textScaler,
      )..layout();
      // ignore: avoid_print
      print(
        '$name: needs ${full.width.toStringAsFixed(1)} px, '
        'has ${p.size.width.toStringAsFixed(1)} px, '
        'cut=${p.didExceedMaxLines}',
      );
      if (p.didExceedMaxLines) cut.add(name);
      full.dispose();
    }
    expect(cut, isEmpty);
    await disposeRig(tester, rig);
  });
}
