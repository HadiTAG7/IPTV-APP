// Moving to another category while the panel's first list is still being
// read must not pull focus into that list (and then lose it).
// All data is synthetic (127.0.0.1 URLs, made-up names).
import 'package:drift/drift.dart' show QueryExecutor;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/live/live_models.dart';
import 'package:iptv_player/player/ui/channel_panel.dart';
import 'package:iptv_player/player/ui/play_request.dart';
import 'package:iptv_player/sources/models.dart';

import 'support/player_harness.dart';

String _url(String key) => 'http://127.0.0.1:9/live/$key.ts';

/// Slows the channel list's category count and position reads (what a
/// large catalog costs on a TV box).
class _SlowLists extends QueryCounter {
  Duration delay = Duration.zero;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (delay > Duration.zero &&
        (statement.contains('COUNT(*) AS n FROM category_items') ||
            statement.contains('MIN(position) AS p FROM category_items'))) {
      await Future<void>.delayed(delay);
    }
    return super.runSelect(executor, statement, args);
  }
}

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
    CategoryData(kind: ContentKind.live, key: 'sports', name: 'Sports'),
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
    for (var i = 1; i <= 3; i++)
      ChannelData(
        key: 'sp$i',
        name: 'Sport $i',
        num: 200 + i,
        url: _url('sp$i'),
        categoryKeys: const ['sports'],
      ),
  ]);
  await db.catalogDao.commitGeneration(id, gen);
  return id;
}

bool _categoryFocused(String id) => focusedIn(ValueKey('live-category-$id'));

void main() {
  testWidgets('Down to another category while the first list loads keeps '
      'focus on that category', (tester) async {
    final slow = _SlowLists();
    final rig = PlayerRig(queries: slow)..autoPlay();
    final id = await _seed(rig);
    await pumpPlayerApp(tester, rig);
    await openPlayerFor(
      tester,
      PlayRequest(
        sourceId: id,
        item: PlayableRef(
          kind: PlayableKind.live,
          key: 'ch2',
          url: _url('ch2'),
        ),
        categoryKey: 'news',
        list: const LiveList.category('news'),
      ),
    );
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);

    slow.delay = const Duration(milliseconds: 80);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    // Wait until focus has parked on News while its rows are read.
    for (var i = 0; i < 20 && !_categoryFocused('cat:news'); i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    final panel = tester.state<ChannelPanelState>(find.byType(ChannelPanel));
    expect(_categoryFocused('cat:news'), isTrue);
    expect(panel.channelList!.hasRows, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 16));
    expect(_categoryFocused('cat:sports'), isTrue);

    final trace = <String?>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (trace.isEmpty || trace.last != focusLabel) trace.add(focusLabel);
    }
    expect(panel.selected, const LiveList.category('sports'));
    // Focus never left the Sports entry.
    expect(trace, ['cat:sports'], reason: 'focus went $trace');
    expect(_categoryFocused('cat:sports'), isTrue);
    await disposeRig(tester, rig);
  });
}
