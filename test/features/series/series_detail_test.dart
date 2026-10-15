import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/features/series/providers.dart';
import 'package:iptv_player/features/series/series_detail_screen.dart';
import 'package:iptv_player/features/vod_common/vod_widgets.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/widgets/states.dart';

import '../movies/vod_harness.dart';

const _play = ValueKey('vod-play');
const _startOver = ValueKey('vod-start-over');
const _favorite = ValueKey('vod-favorite');

Key _season(int n) => ValueKey('vod-season-$n');
Key _episode(String key) => ValueKey('vod-ep-$key');

/// Season 1: e11, e12, e13; season 2: e21, e22.
List<EpisodeData> _episodes(String seriesKey) => [
  for (final (season, count) in [(1, 3), (2, 2)])
    for (var n = 1; n <= count; n++)
      EpisodeData(
        seriesKey: seriesKey,
        key: 'e$season$n',
        season: season,
        number: n,
        title: 'Chapter $season.$n',
        ext: 'mp4',
        durationSec: 45 * 60,
      ),
];

const _detail = SeriesDetail(
  key: 's1',
  plot: 'Two friends open a bakery.',
  genre: 'Comedy',
  seasons: [
    SeasonInfo(number: 1, name: 'Season 1'),
    SeasonInfo(number: 2, name: 'The Return'),
  ],
);

SeriesDetail _fetched(String key) => SeriesDetail(
  key: key,
  plot: _detail.plot,
  genre: _detail.genre,
  seasons: _detail.seasons,
  episodes: _episodes(key),
);

void main() {
  late FakeClock clock;

  setUp(() => clock = FakeClock(testEpoch));

  Future<(AppDatabase, int)> seed({bool xtream = true}) async {
    final db = openVodDb(clock);
    final id = xtream ? await addXtreamSource(db) : await addM3uSource(db);
    await seedCatalog(
      db,
      id,
      categories: const [
        CategoryData(kind: ContentKind.series, key: 'shows', name: 'Shows'),
      ],
      series: const [
        SeriesData(
          key: 's1',
          name: 'Bakery Days',
          year: 2021,
          rating: 6.5,
          categoryKeys: ['shows'],
        ),
      ],
      // M3U playlists bring their episodes with the catalog.
      episodes: xtream ? const [] : _episodes('s1'),
    );
    return (db, id);
  }

  /// Opens Series on TV and OK on the first poster of All.
  Future<void> openFromGrid(WidgetTester tester, {required bool rtl}) async {
    await openTabFromRail(tester, 3, rtl: rtl);
    await press(tester, toEnd(rtl));
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byType(SeriesDetailScreen), findsOneWidget);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester, frames: 16);
  }

  for (final rtl in [false, true]) {
    final lang = rtl ? 'ar' : 'en';

    testWidgets('$lang TV: fetch, store, then seasons and episodes by D-pad', (
      tester,
    ) async {
      final (db, id) = await seed();
      final adapter = FakeVodAdapter(onSeries: (key) async => _fetched(key));
      final player = PlayRecorder();
      await pumpVodApp(
        tester,
        db: db,
        rtl: rtl,
        adapter: adapter,
        player: player,
      );
      final l10n = rtl ? arL10n : enL10n;

      await openFromGrid(tester, rtl: rtl);
      expect(adapter.seriesCalls, ['s1']);
      expect(find.text('Bakery Days'), findsWidgets);
      expect(find.text('Two friends open a bakery.'), findsOneWidget);
      expect(find.text('Comedy'), findsOneWidget);

      // The fetched episodes were stored and the header cached.
      final stored = await db.catalogDao.episodesForSeries(id, 's1');
      expect(stored.map((e) => e.key), ['e11', 'e12', 'e13', 'e21', 'e22']);
      expect(await db.detailCacheDao.seriesDetail(id, 's1'), isNotNull);

      // Generic season names are localised; custom ones are kept.
      expect(find.text(l10n.vodSeasonN(1)), findsOneWidget);
      expect(find.text('The Return'), findsOneWidget);

      // The primary button has focus and plays the first episode.
      expect(focusedIn(_play), isTrue, reason: describeFocus());
      expect(find.text(l10n.vod_playEpisode(1, 1)), findsOneWidget);

      // Seasons on the start side, episodes on the end side.
      final seasonX = tester.getCenter(find.byKey(_season(1))).dx;
      final episodeX = tester.getCenter(find.byKey(_episode('e11'))).dx;
      expect(rtl ? seasonX > episodeX : seasonX < episodeX, isTrue);

      // Down from the header enters the episode list.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(_episode('e11')), isTrue, reason: describeFocus());
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(_episode('e12')), isTrue);

      // Toward the start: the selected season.
      await press(tester, toStart(rtl));
      expect(focusedIn(_season(1)), isTrue, reason: describeFocus());
      // Focusing season 2 shows its episodes.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(_season(2)), isTrue);
      expect(find.byKey(_episode('e21')), findsOneWidget);
      expect(find.byKey(_episode('e11')), findsNothing);

      // Toward the end: season 2's first episode; OK plays it.
      await press(tester, toEnd(rtl));
      expect(focusedIn(_episode('e21')), isTrue, reason: describeFocus());
      await press(tester, LogicalKeyboardKey.select);
      final request = player.last;
      expect(request.sourceId, id);
      expect(request.item.kind, PlayableKind.episode);
      expect(request.item.key, 'e21');
      expect(request.item.ext, 'mp4');
      expect(request.seriesKey, 's1');
      expect(request.startAt, isNull);

      // Up from the top of a pane reaches the header buttons.
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedIn(_play), isTrue, reason: describeFocus());
      await press(tester, toEnd(rtl));
      expect(focusedIn(_favorite), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(
        await db.favoritesDao.isFavorite(id, ContentKind.series, 's1'),
        isTrue,
      );
      expect(focusedIn(_favorite), isTrue);

      // Closing and opening again uses the cache and the stored episodes,
      // and remembers season 2.
      await back(tester);
      await press(tester, LogicalKeyboardKey.select);
      expect(adapter.seriesCalls, ['s1']);
      expect(find.byKey(_episode('e21')), findsOneWidget);
      expect(find.byKey(_episode('e11')), findsNothing);
      expect(await loadLastSeason(db.settingsDao, id, 's1'), 2);

      await disposeVodApp(tester, db);
    });
  }

  testWidgets('progress: resume button, bars and the episode menu', (
    tester,
  ) async {
    final (db, id) = await seed(xtream: false);
    final progress = db.progressDao;
    await progress.saveProgress(
      id,
      PlayableKind.episode,
      'e11',
      45 * 60 * 1000,
      45 * 60 * 1000,
    );
    clock.advance(const Duration(minutes: 1));
    await progress.saveProgress(
      id,
      PlayableKind.episode,
      'e12',
      (12 * 60 + 5) * 1000,
      45 * 60 * 1000,
    );
    final player = PlayRecorder();
    // M3U: episodes come from the playlist; the adapter is never asked.
    await pumpVodApp(tester, db: db, player: player);

    // The series' continue card opens the page.
    await openTabFromRail(tester, 3, rtl: false);
    await press(tester, toEnd(false));
    expect(focusedIn(const ValueKey('vod-cw-episode-e12')), isTrue);
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byType(SeriesDetailScreen), findsOneWidget);

    expect(focusedIn(_play), isTrue);
    expect(find.text(enL10n.vod_resumeEpisode(1, 2)), findsOneWidget);
    expect(find.byKey(_startOver), findsOneWidget);
    // Watched mark on e11, a progress bar on e12.
    expect(
      find.descendant(
        of: find.byKey(_episode('e11')),
        matching: find.text(enL10n.vodWatched),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(_episode('e12')),
        matching: find.byType(ProgressLine),
      ),
      findsOneWidget,
    );

    await press(tester, LogicalKeyboardKey.select);
    expect(player.last.item.key, 'e12');
    expect(player.last.startAt, const Duration(minutes: 12, seconds: 5));
    expect(player.last.seriesKey, 's1');

    // OK on a started episode resumes it; Menu offers Start over.
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedIn(_episode('e12')), isTrue, reason: describeFocus());
    await press(tester, LogicalKeyboardKey.contextMenu);
    expect(
      focusedIn(const ValueKey('vod-option-resume')),
      isTrue,
      reason: describeFocus(),
    );
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(
      focusedIn(const ValueKey('vod-option-start-over')),
      isTrue,
      reason: describeFocus(),
    );
    await press(tester, LogicalKeyboardKey.select);
    await settle(tester);
    expect(player.last.item.key, 'e12');
    expect(player.last.startAt, Duration.zero);
    expect(focusedIn(_episode('e12')), isTrue, reason: describeFocus());

    // When the last watched episode is finished, Play offers the next one.
    await progress.saveProgress(
      id,
      PlayableKind.episode,
      'e12',
      45 * 60 * 1000,
      45 * 60 * 1000,
    );
    await settle(tester);
    expect(find.text(enL10n.vod_playEpisode(1, 3)), findsOneWidget);
    expect(find.byKey(_startOver), findsNothing);

    await disposeVodApp(tester, db);
  });

  testWidgets('stored episodes show while a refresh is fetched', (
    tester,
  ) async {
    final (db, id) = await seed();
    await db.catalogDao.saveFetchedEpisodes(id, 's1', _episodes('s1'));
    final pending = Completer<SeriesDetail>();
    final adapter = FakeVodAdapter(onSeries: (_) => pending.future);
    await pumpVodApp(tester, db: db, adapter: adapter);

    await openFromGrid(tester, rtl: false);
    expect(find.byKey(_episode('e11')), findsOneWidget);
    expect(adapter.seriesCalls, ['s1']);

    pending.completeError(const TimeoutFailure('timed out'));
    await settle(tester);
    // The failure is a note; the stored episodes stay.
    expect(find.byKey(const ValueKey('vod-details-failed')), findsOneWidget);
    expect(find.byKey(_episode('e11')), findsOneWidget);

    await disposeVodApp(tester, db);
  });

  testWidgets('a failed first fetch shows an error with Retry', (tester) async {
    final (db, _) = await seed();
    var fail = true;
    final adapter = FakeVodAdapter(
      onSeries: (key) async {
        if (fail) throw const NetworkFailure('HTTP 503');
        return _fetched(key);
      },
    );
    await pumpVodApp(tester, db: db, adapter: adapter);
    await openFromGrid(tester, rtl: false);
    expect(find.byType(ErrorView), findsOneWidget);
    expect(focusedIn(_play), isTrue);

    fail = false;
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.select);
    await settle(tester);
    expect(adapter.seriesCalls, hasLength(2));
    expect(find.byKey(_episode('e11')), findsOneWidget);

    await disposeVodApp(tester, db);
  });

  for (final rtl in [false, true]) {
    testWidgets('${rtl ? 'ar' : 'en'} phone: chips, episodes and play', (
      tester,
    ) async {
      final (db, id) = await seed(xtream: false);
      final player = PlayRecorder();
      await pumpVodApp(tester, db: db, tv: false, rtl: rtl, player: player);
      final l10n = rtl ? arL10n : enL10n;
      await tester.tap(find.byKey(const ValueKey('nav-series')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('vod-grid-0')));
      await settle(tester);

      expect(find.byType(SeriesDetailScreen), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.text(l10n.vodSeasonN(1)), findsOneWidget);
      expect(find.byKey(_episode('e13')), findsOneWidget);

      await tester.tap(find.byKey(_season(2)));
      await settle(tester);
      expect(find.byKey(_episode('e22')), findsOneWidget);
      expect(find.byKey(_episode('e11')), findsNothing);
      expect(await loadLastSeason(db.settingsDao, id, 's1'), 2);

      await tester.tap(find.byKey(_episode('e22')));
      await settle(tester);
      expect(player.last.item.key, 'e22');
      expect(player.last.seriesKey, 's1');

      await tester.tap(find.byType(BackButton));
      await settle(tester, frames: 16);
      expect(find.byType(SeriesDetailScreen), findsNothing);

      await disposeVodApp(tester, db);
    });
  }

  /// A long show: [seasons] seasons of three episodes (`e<season>_<n>`).
  Future<(AppDatabase, int)> seedLongShow({int seasons = 15}) async {
    final db = openVodDb(clock);
    final id = await addM3uSource(db);
    await seedCatalog(
      db,
      id,
      categories: const [
        CategoryData(kind: ContentKind.series, key: 'shows', name: 'Shows'),
      ],
      series: const [
        SeriesData(key: 's1', name: 'Long Show', categoryKeys: ['shows']),
      ],
      episodes: [
        for (var season = 1; season <= seasons; season++)
          for (var n = 1; n <= 3; n++)
            EpisodeData(
              seriesKey: 's1',
              key: 'e${season}_$n',
              season: season,
              number: n,
              title: 'S$season E$n',
              ext: 'mp4',
            ),
      ],
    );
    return (db, id);
  }

  for (final rtl in [false, true]) {
    testWidgets('${rtl ? 'ar' : 'en'} TV: a far season stays selected and '
        'is saved once focus rests', (tester) async {
      final (db, id) = await seedLongShow();
      // Watching season 14.
      await db.progressDao.saveProgress(
        id,
        PlayableKind.episode,
        'e14_2',
        10 * 60 * 1000,
        45 * 60 * 1000,
      );
      await pumpVodApp(tester, db: db, rtl: rtl);
      await openTabFromRail(tester, 3, rtl: rtl);
      await press(tester, toEnd(rtl)); // the continue card
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(SeriesDetailScreen), findsOneWidget);

      // The page opens on season 14, and the Seasons pane shows it.
      expect(find.byKey(_episode('e14_1')), findsOneWidget);
      expect(find.byKey(_season(14)), findsOneWidget);
      expect(find.byKey(_season(1)), findsNothing);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(_episode('e14_1')), isTrue, reason: describeFocus());
      // Toward the start lands on season 14 itself.
      await press(tester, toStart(rtl));
      expect(focusedIn(_season(14)), isTrue, reason: describeFocus());
      expect(find.byKey(_episode('e14_1')), findsOneWidget);
      await settle(tester, frames: 16);
      expect(await loadLastSeason(db.settingsDao, id, 's1'), isNull);

      // Passing seasons quickly saves only where focus rests.
      for (var i = 0; i < 3; i++) {
        await press(tester, LogicalKeyboardKey.arrowUp, frames: 1);
      }
      expect(focusedIn(_season(11)), isTrue, reason: describeFocus());
      expect(find.byKey(_episode('e11_1')), findsOneWidget);
      expect(await loadLastSeason(db.settingsDao, id, 's1'), isNull);
      await tester.pump(SeriesDetailScreen.rememberDelay);
      await settle(tester);
      expect(await loadLastSeason(db.settingsDao, id, 's1'), 11);

      // Next time the page opens on season 11, ready for the D-pad.
      await tester.binding.handlePopRoute();
      await settle(tester, frames: 16);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(SeriesDetailScreen), findsOneWidget);
      expect(find.byKey(_episode('e11_1')), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, toStart(rtl));
      expect(focusedIn(_season(11)), isTrue, reason: describeFocus());

      await disposeVodApp(tester, db);
    });
  }

  testWidgets('a season passed just before closing is still remembered', (
    tester,
  ) async {
    final (db, id) = await seedLongShow(seasons: 3);
    await pumpVodApp(tester, db: db);
    await openFromGrid(tester, rtl: false);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedIn(_season(1)), isTrue, reason: describeFocus());
    await press(tester, LogicalKeyboardKey.arrowDown, frames: 1);
    expect(focusedIn(_season(2)), isTrue);
    await back(tester);
    expect(find.byType(SeriesDetailScreen), findsNothing);
    expect(await loadLastSeason(db.settingsDao, id, 's1'), 2);
    await disposeVodApp(tester, db);
  });

  testWidgets('TV: a refresh that adds an episode above keeps focus', (
    tester,
  ) async {
    final (db, id) = await seed();
    List<EpisodeData> from(int first) => [
      for (var n = first; n <= 6; n++)
        EpisodeData(
          seriesKey: 's1',
          key: 'e$n',
          season: 1,
          number: n,
          title: 'Part $n',
          ext: 'mp4',
        ),
    ];
    await db.catalogDao.saveFetchedEpisodes(id, 's1', from(2));
    final pending = Completer<SeriesDetail>();
    final adapter = FakeVodAdapter(onSeries: (_) => pending.future);
    await pumpVodApp(tester, db: db, adapter: adapter);
    await openFromGrid(tester, rtl: false);
    await pressN(tester, LogicalKeyboardKey.arrowDown, 3);
    expect(focusedIn(_episode('e4')), isTrue, reason: describeFocus());

    pending.complete(SeriesDetail(key: 's1', episodes: from(1)));
    await settle(tester);
    expect(find.byKey(_episode('e1')), findsOneWidget);
    expect(focusedIn(_episode('e4')), isTrue, reason: describeFocus());
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedIn(_episode('e5')), isTrue, reason: describeFocus());

    await disposeVodApp(tester, db);
  });

  for (final rtl in [false, true]) {
    testWidgets('${rtl ? 'ar' : 'en'} phone: details arriving keep the '
        'scroll position', (tester) async {
      final (db, id) = await seed();
      final episodes = [
        for (var n = 1; n <= 20; n++)
          EpisodeData(
            seriesKey: 's1',
            key: 'p$n',
            season: 1,
            number: n,
            title: 'Part $n',
            ext: 'mp4',
          ),
      ];
      await db.catalogDao.saveFetchedEpisodes(id, 's1', episodes);
      final pending = Completer<SeriesDetail>();
      final adapter = FakeVodAdapter(onSeries: (_) => pending.future);
      await pumpVodApp(tester, db: db, tv: false, rtl: rtl, adapter: adapter);
      await tester.tap(find.byKey(const ValueKey('nav-series')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('vod-grid-0')));
      await settle(tester);
      expect(find.byType(SeriesDetailScreen), findsOneWidget);

      ScrollPosition position() => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(SeriesDetailScreen),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      final before = position()..jumpTo(600);
      await settle(tester);

      pending.complete(
        SeriesDetail(
          key: 's1',
          plot: 'A long plot.',
          backdrop: 'http://127.0.0.1:9/backdrop.jpg',
          episodes: episodes,
        ),
      );
      await settle(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('vod-detail-backdrop')),
          matching: find.byType(VodImage),
        ),
        findsOneWidget,
      );
      expect(identical(position(), before), isTrue);
      expect(position().pixels, 600);

      await disposeVodApp(tester, db);
    });
  }

  testWidgets('desktop: the page has a Back button for the mouse', (
    tester,
  ) async {
    final (db, _) = await seed(xtream: false);
    await pumpVodApp(tester, db: db, desktop: true);
    await tester.tap(find.byKey(const ValueKey('rail-series')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('vod-grid-0')));
    await settle(tester);
    expect(find.byType(SeriesDetailScreen), findsOneWidget);
    expect(find.byKey(_season(2)), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await settle(tester, frames: 16);
    expect(find.byType(SeriesDetailScreen), findsNothing);
    await disposeVodApp(tester, db);
  });

  test('remembered seasons are capped, newest kept', () async {
    final db = openVodDb(clock);
    addTearDown(db.close);
    final settings = db.settingsDao;
    for (var i = 0; i < kMaxRememberedSeasons + 5; i++) {
      await saveLastSeason(settings, 1, 's$i', 2);
    }
    expect(await loadLastSeason(settings, 1, 's0'), isNull);
    expect(await loadLastSeason(settings, 1, 's5'), 2);
    await saveLastSeason(settings, 1, 's5', 3);
    expect(await loadLastSeason(settings, 1, 's5'), 3);
    expect(await loadLastSeason(settings, 2, 's5'), isNull);
    final all = await settings.getJson(kLastSeasonsKey) as Map;
    expect(all.length, kMaxRememberedSeasons);
    expect(all.keys.last, '1|s5');
  });
}
