// Riverpod wiring of the fullscreen player (no code generation).
//
// One [PlaybackController] lives in [playbackControllerProvider] while a
// player screen watches it and is disposed (closing its engine and stream)
// once the screen is gone. Engines come from [playerEngineFactoryProvider]
// with the current Settings; tests override [engineFactoryBuilderProvider]
// with fake engines.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app/providers.dart';
import '../core/db/app_db.dart';
import '../core/log/ring_log.dart';
import '../core/net/redact.dart';
import '../core/platform/device_caps.dart';
import '../core/platform/window_fullscreen.dart';
import '../sources/models.dart';
import '../sources/source_adapter.dart';
import '../sources/source_repository.dart';
import 'engine/engine_factory.dart';
import 'engine/engine_policy.dart';
import 'session/playback_controller.dart';

/// Builds an [EngineFactory] for a set of [EngineOptions].
typedef EngineFactoryBuilder = EngineFactory Function(EngineOptions options);

/// How engines are built: ExoPlayer and mpv in the app, fakes in tests.
final engineFactoryBuilderProvider = Provider<EngineFactoryBuilder>(
  (ref) => defaultEngineFactory,
  name: 'engineFactoryBuilderProvider',
);

/// Engines with the current Settings (Lite cache size, hardware decoding,
/// ExoPlayer view type, preferred audio and subtitle languages).
final playerEngineFactoryProvider = Provider<EngineFactory>(
  (ref) =>
      ref.watch(engineFactoryBuilderProvider)(ref.watch(engineOptionsProvider)),
);

/// The item behind a [PlaybackController.itemKey]: the controller's
/// callbacks (learned engine, progress) only receive that string, so it
/// carries the source and the kind as well.
@immutable
class PlayerItemKey {
  const PlayerItemKey(this.sourceId, this.kind, this.key);

  final int sourceId;
  final PlayableKind kind;
  final String key;

  /// `<sourceId>|<kind>|<key>`; the key itself may contain `|`.
  String encode() => '$sourceId|${kind.name}|$key';

  static PlayerItemKey? tryDecode(String? value) {
    if (value == null) return null;
    final first = value.indexOf('|');
    if (first <= 0) return null;
    final second = value.indexOf('|', first + 1);
    if (second < 0) return null;
    final id = int.tryParse(value.substring(0, first));
    final kindName = value.substring(first + 1, second);
    final kind = PlayableKind.values.where((k) => k.name == kindName);
    if (id == null || kind.isEmpty) return null;
    return PlayerItemKey(id, kind.first, value.substring(second + 1));
  }

  /// Key of this item's row in `channel_prefs`: the channel key for live,
  /// `movie:<key>` / `episode:<key>` for titles (their keys may collide with
  /// channel keys, e.g. Xtream numeric ids).
  String get prefsKey => kind == PlayableKind.live ? key : '${kind.name}:$key';

  @override
  bool operator ==(Object other) =>
      other is PlayerItemKey &&
      other.sourceId == sourceId &&
      other.kind == kind &&
      other.key == key;

  @override
  int get hashCode => Object.hash(sourceId, kind, key);

  @override
  String toString() => 'PlayerItemKey(${encode()})';
}

/// Engine policy input: the device ([DeviceCaps.isAmlogic], platform), the
/// source's engine overrides (falling back to the Settings choice). The
/// per-channel preference is passed to `PlaybackController.play` instead.
EnginePolicyInput enginePolicyInputFor({
  required DeviceCaps caps,
  required TargetPlatform platform,
  required AppSettings settings,
  SourceRow? source,
  bool isWeb = kIsWeb,
}) => EnginePolicyInput(
  platform: targetPlatformKindOf(platform, isWeb: isWeb),
  isAmlogic: caps.isAmlogic,
  sourceLiveOverride: source?.engineLive ?? settings.liveEngine.kind,
  sourceVodOverride: source?.engineVod ?? settings.vodEngine.kind,
);

/// Called once per tuned live channel when it starts playing (Recent list).
typedef ChannelPlayedCallback = Future<void> Function(
  int sourceId,
  String channelKey,
);

/// Records a played live channel: it moves to the top of the Recent list
/// (and becomes the channel the Live list opens on). The player calls it
/// for every channel it tunes, zaps included; the Live, Favorites and
/// Search screens reach the same action through `markChannelPlayedProvider`.
///
/// Never throws; failures are logged without the key (M3U keys are URLs
/// that may hold credentials).
final onChannelPlayedProvider = Provider<ChannelPlayedCallback>((ref) {
  final recent = ref.watch(recentDaoProvider);
  final log = ref.watch(ringLogProvider);
  return (sourceId, key) async {
    try {
      await recent.markRecent(sourceId, key);
    } on Object catch (e) {
      log.warn('Saving the recent channel failed: ${e.runtimeType}');
    }
  };
}, name: 'onChannelPlayedProvider');

/// Keeps the screen on while something plays ([WakelockPlus]); failures
/// (no plugin, desktop without a session bus) are logged and ignored.
final playerWakelockProvider = Provider<ValueChanged<bool>>(
  (ref) => playerWakelock(ref.watch(ringLogProvider)),
  name: 'playerWakelockProvider',
);

/// Turns the screen wakelock on or off ([WakelockPlus]), logging failures
/// to [log]; detached windows use it too.
ValueChanged<bool> playerWakelock(RingLog log) => (on) {
  unawaited(
    Future<void>.sync(() => WakelockPlus.toggle(enable: on))
        .catchError((Object e) => log.warn('Wakelock: $e')),
  );
};

/// The desktop window the player makes truly fullscreen; null on Android
/// (and the web), where the player hides the system bars instead.
final playerWindowProvider = Provider<WindowFullscreen?>((ref) {
  if (kIsWeb) return null;
  return switch (ref.watch(targetPlatformProvider)) {
    TargetPlatform.windows => WindowFullscreen.windows(
      onError: ref.watch(ringLogProvider).warn,
    ),
    TargetPlatform.linux || TargetPlatform.macOS => const WindowFullscreen(),
    _ => null,
  };
}, name: 'playerWindowProvider');

/// Whether the desktop player opens fullscreen: yes until the user turns
/// fullscreen off with the player's fullscreen button, F, F11 or a double
/// click; then the last such choice, for the rest of the run. Escape
/// leaving fullscreen is not a choice (it is usually on the way out).
final playerOpensFullscreenProvider =
    NotifierProvider<PlayerOpensFullscreen, bool>(
      PlayerOpensFullscreen.new,
      name: 'playerOpensFullscreenProvider',
    );

class PlayerOpensFullscreen extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool fullscreen) {
    if (ref.mounted) state = fullscreen;
  }
}

/// Network availability for the player (true = online). While offline the
/// reconnect watchdog waits instead of burning attempts. Bootstrap provides
/// it from its connectivity listener; null (tests) means always online.
final playerOnlineProvider = Provider<Stream<bool>?>(
  (ref) => null,
  name: 'playerOnlineProvider',
);

/// The app's [PlaybackController]. It exists while a player screen watches
/// it; the last listener going away disposes it, which disposes its engine
/// and closes the connection.
///
/// * Engines come from [playerEngineFactoryProvider], read when each engine
///   is created so Settings changes apply to the next one.
/// * The policy input combines the device, the source's engine overrides
///   and the Settings ([enginePolicyInputFor]).
/// * Learned engine choices go to `channel_prefs` and VOD progress to
///   `watch_progress`; item keys are [PlayerItemKey]s.
final playbackControllerProvider = Provider.autoDispose<PlaybackController>((
  ref,
) {
  final db = ref.read(databaseProvider);
  final log = ref.read(ringLogProvider);
  late final PlaybackController controller;

  EnginePolicyInput policyInput() {
    final item = PlayerItemKey.tryDecode(controller.itemKey);
    final sources = ref.mounted
        ? ref.read(sourcesProvider).value ?? const <SourceView>[]
        : const <SourceView>[];
    return enginePolicyInputFor(
      caps: ref.read(deviceCapsProvider),
      platform: ref.read(targetPlatformProvider),
      settings: ref.read(settingsProvider),
      source: item == null
          ? null
          : sources.where((s) => s.id == item.sourceId).firstOrNull,
    );
  }

  final fallbackFactory = ref.read(playerEngineFactoryProvider);
  controller = PlaybackController(
    factory: (kind) => ref.mounted
        ? ref.read(playerEngineFactoryProvider)(kind)
        : fallbackFactory(kind),
    policyInput: policyInput,
    clock: ref.read(clockProvider),
    onWakelockChanged: ref.read(playerWakelockProvider),
    onEnginePreferenceLearned: (itemKey, kind) {
      final item = PlayerItemKey.tryDecode(itemKey);
      if (item == null) return;
      log.info('Player: ${kind.name} remembered for ${item.kind.name}');
      unawaited(
        db.prefsDao
            .setEngine(item.sourceId, item.prefsKey, kind)
            .catchError((Object e) => log.warn('Saving engine failed: $e')),
      );
    },
    onProgress: (itemKey, position, duration) async {
      final item = PlayerItemKey.tryDecode(itemKey);
      if (item == null || item.kind == PlayableKind.live) return;
      try {
        await db.progressDao.saveProgress(
          item.sourceId,
          item.kind,
          item.key,
          position.inMilliseconds,
          duration.inMilliseconds,
        );
      } on Object catch (e) {
        log.warn('Saving progress failed: $e');
      }
    },
  );
  ref.onDispose(controller.dispose);
  return controller;
}, name: 'playbackControllerProvider');

/// A source opened for playback: its row (account limits, kind), an adapter
/// for `resolve` and the credential strings to mask in reports.
class PlayerSource {
  PlayerSource({
    required this.row,
    required this.adapter,
    this.secrets = const {},
  });

  final SourceRow row;
  final SourceAdapter adapter;

  /// Usernames, passwords and URL tokens of the source (never shown).
  final Set<String> secrets;

  /// The account's connection limit (1 adds a gap when switching).
  int? get maxConnections => row.maxConnections;

  bool get isXtream => row.kind == SourceKind.xtream;

  /// [text] with URL credentials and this source's secrets masked.
  String redactText(String text) => redact(text, secrets: secrets);

  /// The stream of the live channel [ref]; [ext] (`ts` or `m3u8`) replaces
  /// its container (the player's "Try other format").
  StreamRequest resolveLive(PlayableRef ref, {String? ext}) => adapter.resolve(
    PlayableRef(
      kind: ref.kind,
      key: ref.key,
      url: ref.url,
      ext: ext ?? ref.ext,
      headers: ref.headers,
      title: ref.title,
    ),
  );

  void close() => adapter.close();
}

/// Loads a source for playback.
typedef PlayerSourceLoader = Future<PlayerSource> Function(int sourceId);

/// Opens saved sources through [SourceRepository] (credentials from the
/// secret store, adapters seeded with the panel's allowed formats).
final playerSourceLoaderProvider = Provider<PlayerSourceLoader>((ref) {
  final repo = ref.watch(sourceRepositoryProvider);
  return (sourceId) async {
    final row = await repo.byId(sourceId);
    if (row == null) throw StateError('Unknown source $sourceId');
    final config = await repo.configFor(sourceId);
    return PlayerSource(
      row: row,
      adapter: repo.adapterFor(config, allowedFormats: row.allowedFormats),
      secrets: sourceSecrets(config),
    );
  };
}, name: 'playerSourceLoaderProvider');
