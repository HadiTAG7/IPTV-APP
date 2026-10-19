import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/db/queries/player_ui_queries.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/core/platform/device_caps.dart';
import 'package:iptv_player/player/engine/engine_policy.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/player/player_providers.dart';
import 'package:iptv_player/player/session/playback_controller.dart';
import 'package:iptv_player/player/ui/player_format.dart';
import 'package:iptv_player/player/ui/seek_accumulator.dart';
import 'package:iptv_player/sources/models.dart';

import 'support/player_harness.dart';

const _movie = StreamRequest(
  url: 'http://127.0.0.1:9/movie/m1.mp4',
  kind: PlayableKind.movie,
);

/// Waits for real async work (drift, engine fakes) to settle.
Future<void> _idle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('PlayerItemKey', () {
    test('round-trips, including keys with separators', () {
      const keys = [
        PlayerItemKey(3, PlayableKind.live, '1001'),
        PlayerItemKey(12, PlayableKind.movie, 'http://h/a|b'),
        PlayerItemKey(1, PlayableKind.episode, ''),
      ];
      for (final k in keys) {
        expect(PlayerItemKey.tryDecode(k.encode()), k);
      }
      for (final bad in [null, '', 'x|live|1', '1|tv|1', '1live']) {
        expect(PlayerItemKey.tryDecode(bad), isNull, reason: bad);
      }
    });

    test('prefs keys keep titles apart from channels', () {
      expect(const PlayerItemKey(1, PlayableKind.live, '7').prefsKey, '7');
      expect(
        const PlayerItemKey(1, PlayableKind.movie, '7').prefsKey,
        'movie:7',
      );
      expect(
        const PlayerItemKey(1, PlayableKind.episode, '7').prefsKey,
        'episode:7',
      );
    });
  });

  group('enginePolicyInputFor', () {
    test('device, Settings and source overrides', () {
      final input = enginePolicyInputFor(
        caps: const DeviceCaps(hardware: 'amlogic s905x'),
        platform: TargetPlatform.android,
        settings: const AppSettings(liveEngine: EngineSetting.mpv),
        isWeb: false,
      );
      expect(input.platform, TargetPlatformKind.android);
      expect(input.isAmlogic, isTrue);
      expect(input.sourceLiveOverride, EngineKind.mpv);
      expect(input.sourceVodOverride, isNull);

      final withSource = enginePolicyInputFor(
        caps: const DeviceCaps(),
        platform: TargetPlatform.windows,
        settings: const AppSettings(liveEngine: EngineSetting.mpv),
        source: const SourceRow(
          id: 1,
          name: 's',
          kind: SourceKind.xtream,
          url: 'http://h',
          engineLive: EngineKind.exo,
          engineVod: EngineKind.exo,
        ),
        isWeb: false,
      );
      expect(withSource.platform, TargetPlatformKind.windows);
      expect(withSource.sourceLiveOverride, EngineKind.exo);
      expect(withSource.sourceVodOverride, EngineKind.exo);
    });
  });

  group('WakelockHolds', () {
    test('on with the first holder, off only after the last', () {
      final calls = <bool>[];
      final holds = WakelockHolds(calls.add);
      final a = holds.holder();
      final b = holds.holder();
      a(false);
      expect(calls, isEmpty);
      a(true);
      b(true);
      a(true);
      expect(calls, [true]);
      a(false);
      expect(calls, [true]);
      expect(holds.isOn, isTrue);
      b(false);
      b(false);
      expect(calls, [true, false]);
      expect(holds.isOn, isFalse);
      b(true);
      expect(calls, [true, false, true]);
    });
  });

  group('playbackControllerProvider', () {
    late PlayerRig rig;
    late ProviderContainer container;

    setUp(() {
      rig = PlayerRig()..autoPlay(duration: const Duration(minutes: 90));
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(rig.db),
          ringLogProvider.overrideWithValue(RingLog()),
          targetPlatformProvider.overrideWithValue(TargetPlatform.android),
          engineFactoryBuilderProvider.overrideWithValue(
            (_) => rig.engines.call,
          ),
          playerWakelockProvider.overrideWithValue(rig.wakelock.add),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await rig.db.close();
    });

    test('saves VOD progress and learned engines; disposes with its '
        'last listener', () async {
      final id = await seedVod(rig);
      final sub = container.listen(playbackControllerProvider, (_, _) {});
      final c = sub.read();
      final key = PlayerItemKey(id, PlayableKind.movie, 'm1').encode();
      await c.play(_movie, itemKey: key);
      await _idle();
      expect(c.phase, PlaybackPhase.playing);
      expect(rig.engine.kind, EngineKind.mpv);
      expect(rig.wakelock, [true]);

      rig.engine.setState(position: const Duration(minutes: 3));
      await c.switchEngine();
      await _idle();
      final prefs = await rig.db.prefsDao.prefsFor(id, 'movie:m1');
      expect(prefs.engine, EngineKind.exo);

      await c.stop();
      await _idle();
      final saved = await rig.db.progressDao.progressFor(
        id,
        PlayableKind.movie,
        'm1',
      );
      expect(saved?.position, const Duration(minutes: 3));

      sub.close();
      await _idle();
      expect(rig.engines.created.every((e) => e.disposed), isTrue);
      expect(rig.wakelock.last, isFalse);
    });

    test('a source engine override reaches the policy', () async {
      final id = await seedLive(rig);
      await rig.db.sourcesDao.setEngines(id, live: EngineKind.mpv, vod: null);
      final sources = container.listen(sourcesProvider, (_, _) {});
      await container.read(sourcesProvider.future);
      final sub = container.listen(playbackControllerProvider, (_, _) {});
      await sub.read().play(
        const StreamRequest(
          url: 'http://127.0.0.1:9/live/ch1.ts',
          kind: PlayableKind.live,
        ),
        itemKey: PlayerItemKey(id, PlayableKind.live, 'ch1').encode(),
      );
      await _idle();
      expect(rig.engine.kind, EngineKind.mpv);
      sub.close();
      sources.close();
    });

    test('the default source loader resolves through the adapter', () async {
      final id = await seedXtream(rig);
      final source = await container.read(playerSourceLoaderProvider)(id);
      addTearDown(source.close);
      expect(source.isXtream, isTrue);
      expect(source.maxConnections, 1);
      expect(source.secrets, containsAll(['viewer7', 'Secret-Pass-9']));
      final r = source.adapter.resolve(
        const PlayableRef(kind: PlayableKind.live, key: '501', ext: 'm3u8'),
      );
      expect(r.url, 'http://127.0.0.1:9/live/viewer7/Secret-Pass-9/501.m3u8');
      expect(r.isHls, isTrue);
      expect(source.redactText(r.url), isNot(contains('Secret-Pass-9')));
    });
  });

  group('zap queries', () {
    late PlayerRig rig;
    setUp(() => rig = PlayerRig());
    tearDown(() => rig.db.close());

    test('category, all channels and explicit keys', () async {
      final id = await seedLive(rig, count: 3);
      expect(await rig.db.zapCountInCategory(id, 'news'), (
        total: 3,
        numbered: 3,
      ));
      expect(await rig.db.zapRangeInCategory(id, 'news', 1, 5), [
        (key: 'ch2', num: 102),
        (key: 'ch3', num: 103),
      ]);
      expect(await rig.db.zapIndexInCategory(id, 'news', 'ch3'), 2);
      expect(await rig.db.zapIndexInCategory(id, 'news', 'gone'), isNull);
      expect(await rig.db.zapNumberInCategory(id, 'news', 102), (
        (key: 'ch2', num: 102),
        1,
      ));
      expect(await rig.db.zapNumberInCategory(id, 'news', 999), isNull);
      expect(await rig.db.zapCountInCategory(id, 'none'), (
        total: 0,
        numbered: 0,
      ));
      expect(await rig.db.zapRangeInCategory(id, 'none', 0, 10), isEmpty);
      expect(
        (await rig.db.zapRangeAll(id, 0, 10, numbered: 3)).map((e) => e.key),
        ['ch1', 'ch2', 'ch3'],
      );
      expect(
        await rig.db.zapEntriesForKeys(id, ['ch3', 'gone', 'ch1', 'ch3']),
        [(key: 'ch3', num: 103), (key: 'ch1', num: 101)],
      );
    });

    test('all channels: numbered by number, then unnumbered by name, read '
        'in windows', () async {
      final db = rig.db;
      final id = await db.sourcesDao.create(
        const SourceConfig(
          kind: SourceKind.m3uUrl,
          url: 'http://127.0.0.1:9/list.m3u',
          name: 'Home',
        ),
      );
      final gen = await db.catalogDao.beginGeneration(id);
      await db.catalogDao.upsertChannels(id, gen, const [
        ChannelData(key: 'z', name: 'Zulu'),
        ChannelData(key: 'b', name: 'Bravo', num: 7),
        ChannelData(key: 'a', name: 'Alpha'),
        ChannelData(key: 'c2', name: 'Charlie', num: 3),
        ChannelData(key: 'c1', name: 'Charlie', num: 3),
        ChannelData(key: 'd', name: 'Delta', num: 1),
      ]);
      await db.catalogDao.commitGeneration(id, gen);
      const order = ['d', 'c1', 'c2', 'b', 'a', 'z'];
      final count = await db.zapCountAll(id);
      expect(count, (total: 6, numbered: 4));
      final all = [
        for (var i = 0; i < 6; i += 2)
          ...await db.zapRangeAll(id, i, 2, numbered: count.numbered),
      ];
      expect(all.map((e) => e.key), order);
      for (final (i, key) in order.indexed) {
        expect(await db.zapIndexAll(id, key), i, reason: key);
      }
      expect(await db.zapIndexAll(id, 'gone'), isNull);
      expect(await db.zapNumberAll(id, 3), ((key: 'c1', num: 3), 1));
      expect(await db.zapNumberAll(id, 7), ((key: 'b', num: 7), 3));
      expect(await db.zapNumberAll(id, 2), isNull);
    });
  });

  group('helpers', () {
    test('hideUrlPaths keeps scheme, host, port and extension only', () {
      expect(
        hideUrlPaths('http://h:8080/user/pass/123.ts'),
        'http://h:8080/***.ts',
      );
      expect(
        hideUrlPaths('HTTP 403 for http://h/u/p/1 (x)'),
        'HTTP 403 for http://h/*** (x)',
      );
      expect(
        hideUrlPaths('see https://h.example/a/b.m3u8?token=abc.'),
        'see https://h.example/***.m3u8.',
      );
      expect(
        hideUrlPaths('"http://u:p@h/x/y.mkv", next (rtmp://h/live/key)'),
        '"http://h/***.mkv", next (rtmp://h/***)',
      );
      expect(
        hideUrlPaths('http://h:9 and http://h/'),
        'http://h:9 and http://h/',
      );
      expect(hideUrlPaths('no address here'), 'no address here');
    });

    test('formatPosition', () {
      expect(formatPosition(Duration.zero), '0:00');
      expect(formatPosition(const Duration(minutes: 42, seconds: 10)), '42:10');
      expect(
        formatPosition(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
      expect(formatPosition(const Duration(seconds: -5)), '-0:05');
    });

    test('SeekAccumulator clamps and commits once', () {
      final commits = <Duration>[];
      fakeAsync((async) {
        final seek = SeekAccumulator(onCommit: commits.add);
        seek.step(
          const Duration(seconds: -10),
          current: const Duration(seconds: 5),
          duration: const Duration(minutes: 1),
        );
        expect(seek.target, Duration.zero);
        seek.step(
          const Duration(minutes: 5),
          current: Duration.zero,
          duration: const Duration(minutes: 1),
        );
        expect(seek.target, const Duration(minutes: 1));
        async.elapse(const Duration(milliseconds: 599));
        expect(commits, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(commits, [const Duration(minutes: 1)]);
        seek.step(
          const Duration(seconds: 10),
          current: Duration.zero,
          duration: Duration.zero,
        );
        seek.cancel();
        async.elapse(const Duration(seconds: 1));
        expect(commits, hasLength(1));
        seek.dispose();
      });
    });
  });
}
