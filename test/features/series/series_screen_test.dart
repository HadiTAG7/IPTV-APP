import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/features/series/series_detail_screen.dart';
import 'package:iptv_player/features/vod_common/vod_browser.dart';
import 'package:iptv_player/sources/models.dart';

import '../movies/vod_harness.dart';

const _all = ValueKey('vod-cat-all');
const _cw = ValueKey('vod-cat-cw');
const _drama = ValueKey('vod-cat-c:drama');
const _railSeries = ValueKey('rail-series');

Key _grid(int i) => ValueKey('vod-grid-$i');
Key _cwCard(String episodeKey) => ValueKey('vod-cw-episode-$episodeKey');

void main() {
  late FakeClock clock;

  setUp(() => clock = FakeClock(testEpoch));

  /// Three series; a.e2 was watched, then c.e1. Continue watching has one
  /// entry per series, newest first: c, then a.
  Future<(AppDatabase, int)> seed() async {
    final db = openVodDb(clock);
    final id = await addM3uSource(db);
    await seedCatalog(
      db,
      id,
      categories: const [
        CategoryData(kind: ContentKind.series, key: 'comedy', name: 'Comedy'),
        CategoryData(
          kind: ContentKind.series,
          key: 'drama',
          name: 'دراما',
          sortIndex: 1,
        ),
      ],
      series: [
        for (final k in ['a', 'b', 'c'])
          SeriesData(
            key: k,
            name: 'Show ${k.toUpperCase()}',
            categoryKeys: [k == 'c' ? 'drama' : 'comedy'],
          ),
      ],
      episodes: [
        for (final k in ['a', 'b', 'c'])
          for (var n = 1; n <= 2; n++)
            EpisodeData(
              seriesKey: k,
              key: '$k.e$n',
              season: 1,
              number: n,
              title: 'Part $n',
            ),
      ],
    );
    final progress = db.progressDao;
    await progress.saveProgress(
      id,
      PlayableKind.episode,
      'a.e2',
      10 * 60 * 1000,
      40 * 60 * 1000,
    );
    clock.advance(const Duration(minutes: 1));
    await progress.saveProgress(
      id,
      PlayableKind.episode,
      'c.e1',
      5 * 60 * 1000,
      40 * 60 * 1000,
    );
    return (db, id);
  }

  for (final rtl in [false, true]) {
    final lang = rtl ? 'ar' : 'en';

    testWidgets('$lang TV: series grid, continue row and crossing', (
      tester,
    ) async {
      final (db, _) = await seed();
      await pumpVodApp(tester, db: db, rtl: rtl);
      final l10n = rtl ? arL10n : enL10n;

      await openTabFromRail(tester, 3, rtl: rtl);
      expect(focusedIn(_all), isTrue, reason: describeFocus());
      expect(find.text(l10n.vod_allSeries), findsWidgets);

      // One card per series, newest first in reading order.
      final c = tester.getCenter(find.byKey(_cwCard('c.e1'))).dx;
      final a = tester.getCenter(find.byKey(_cwCard('a.e2'))).dx;
      expect(rtl ? c > a : c < a, isTrue);
      expect(find.byKey(_cwCard('b.e1')), findsNothing);

      await press(tester, toEnd(rtl));
      expect(focusedIn(_cwCard('c.e1')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(_grid(0)), isTrue, reason: describeFocus());
      await press(tester, toEnd(rtl));
      expect(focusedIn(_grid(1)), isTrue);
      await pressN(tester, toStart(rtl), 2);
      expect(focusedIn(_all), isTrue, reason: describeFocus());
      await press(tester, toStart(rtl));
      expect(focusedIn(_railSeries), isTrue, reason: describeFocus());

      // Continue watching as a category lists the same series.
      await press(tester, toEnd(rtl));
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(_cw), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(
        focusedIn(const ValueKey('vod-cwg-episode-c.e1')),
        isTrue,
        reason: describeFocus(),
      );

      // A category: OK opens the series page.
      await press(tester, toStart(rtl));
      await pressN(tester, LogicalKeyboardKey.arrowDown, 2);
      expect(focusedIn(_drama), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      final browser = tester.state<VodBrowserState>(find.byType(VodBrowser));
      expect(browser.selected, VodBrowserState.categoryId('drama'));
      expect(find.text('Show C'), findsWidgets);
      expect(find.text('Show A'), findsNothing);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(SeriesDetailScreen), findsOneWidget);
      // c.e1 is resumable.
      expect(find.text(l10n.vod_resumeEpisode(1, 1)), findsOneWidget);

      await disposeVodApp(tester, db);
    });
  }

  testWidgets('phone: a continue card opens its series', (tester) async {
    final (db, _) = await seed();
    await pumpVodApp(tester, db: db, tv: false);
    await tester.tap(find.byKey(const ValueKey('nav-series')));
    await settle(tester);

    final y0 = tester.getTopLeft(find.byKey(_grid(0))).dy;
    expect(tester.getTopLeft(find.byKey(_grid(2))).dy, y0);

    await tester.tap(find.byKey(_cwCard('a.e2')));
    await settle(tester);
    expect(find.byType(SeriesDetailScreen), findsOneWidget);
    expect(find.text('Show A'), findsWidgets);
    expect(find.text(enL10n.vod_resumeEpisode(1, 2)), findsOneWidget);

    await disposeVodApp(tester, db);
  });
}
