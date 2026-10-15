// Actions on live channels shared by Live, Favorites and Search.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../player/engine/engine_policy.dart';
import '../../player/engine/player_engine.dart';
import '../../player/player_providers.dart';
import '../../player/ui/play_request.dart';
import '../../player/ui/player_route.dart';
import '../../sources/models.dart';

/// Choices of a channel's options sheet.
enum LiveChannelAction { favorite, otherPlayer }

/// Choices of a category's options sheet.
enum LiveCategoryAction { hide, showHidden }

/// Records that a live channel was played: it moves to the top of the
/// Recent list (and becomes the channel the Live list opens on).
///
/// The same action the player runs for every channel it tunes
/// ([onChannelPlayedProvider]), so a channel opened here and the channels
/// zapped to in the player all reach Recent. Never throws. For code that
/// has a [Ref] instead of a [WidgetRef], read this provider:
/// `ref.read(markChannelPlayedProvider)(sourceId, key)`.
final markChannelPlayedProvider =
    Provider<Future<void> Function(int sourceId, String key)>(
      (ref) => ref.watch(onChannelPlayedProvider),
    );

/// Records that the channel [key] of [sourceId] was played; see
/// [markChannelPlayedProvider]. The player calls it on every zap.
Future<void> markChannelPlayed(WidgetRef ref, int sourceId, String key) =>
    ref.read(markChannelPlayedProvider)(sourceId, key);

/// Opens the fullscreen player for a request and completes when it closes.
typedef PlayerLauncher = Future<void> Function(
  BuildContext context,
  PlayRequest request,
);

/// How the Live, Favorites and Search screens open the player: [openPlayer]
/// by default. Tests replace it to record requests without a real player.
final playerLauncherProvider = Provider<PlayerLauncher>((ref) => openPlayer);

/// Lets one player at a time be opened from the Live, Favorites and Search
/// screens: a second OK pressed while the first one is still opening (a
/// database read, then the route push) would open a second player.
class PlayGate {
  bool _busy = false;

  /// Whether a player is opening or open.
  bool get busy => _busy;

  /// Runs [open] (everything from the press to the player closing) unless
  /// another run is in progress; then the call is ignored.
  Future<void> run(Future<void> Function() open) async {
    if (_busy) return;
    _busy = true;
    try {
      await open();
    } finally {
      _busy = false;
    }
  }
}

/// The [PlayGate] of the app (one per provider container).
final playGateProvider = Provider<PlayGate>((ref) => PlayGate());

/// Marks the channel of [request] as played and opens the fullscreen
/// player at once (the Recent write is not awaited: it is queued before
/// anything the player writes). Completes when the player is closed.
///
/// Callers wrap the whole action, from the key press on, in
/// [playGateProvider]'s [PlayGate.run].
Future<void> playLiveChannel(
  BuildContext context,
  WidgetRef ref,
  PlayRequest request,
) {
  unawaited(markChannelPlayed(ref, request.sourceId, request.item.key));
  return ref.read(playerLauncherProvider)(context, request);
}

/// Adds or removes a favourite (`ContentKind.live` for channels).
Future<void> setFavorite(
  WidgetRef ref,
  int sourceId,
  ContentKind kind,
  String key,
  bool favorite,
) => ref.read(favoritesDaoProvider).setFavorite(sourceId, kind, key, favorite);

/// Hides or shows a live category in the category list.
Future<void> setLiveCategoryHidden(
  WidgetRef ref,
  int sourceId,
  String categoryKey,
  bool hidden,
) => ref
    .read(catalogDaoProvider)
    .setCategoryHidden(sourceId, ContentKind.live, categoryKey, hidden);

/// The engine a channel would play with now (per-channel choice, then the
/// source and app settings, then the platform default).
Future<EngineKind> currentLiveEngine(
  WidgetRef ref,
  int sourceId,
  String channelKey,
) async => const EnginePolicy().pick(
  PlayableKind.live,
  await _policyInput(ref, sourceId, channelKey),
);

/// The other player for a channel, or null where only one engine exists
/// (desktop).
Future<EngineKind?> otherLiveEngine(
  WidgetRef ref,
  int sourceId,
  String channelKey,
) async {
  final input = await _policyInput(ref, sourceId, channelKey);
  const policy = EnginePolicy();
  return policy.fallbackFor(policy.pick(PlayableKind.live, input), input);
}

/// Whether "Play with the other player" applies on this platform.
bool hasOtherLiveEngine(WidgetRef ref) =>
    const EnginePolicy().fallbackFor(
      EngineKind.exo,
      EnginePolicyInput(
        platform: targetPlatformKindOf(ref.read(targetPlatformProvider)),
      ),
    ) !=
    null;

Future<EnginePolicyInput> _policyInput(
  WidgetRef ref,
  int sourceId,
  String channelKey,
) async {
  final prefs = await ref.read(prefsDaoProvider).prefsFor(sourceId, channelKey);
  final sources = ref.read(sourcesProvider).value ?? const <SourceRow>[];
  final source = sources.where((s) => s.id == sourceId).firstOrNull;
  return EnginePolicyInput(
    platform: targetPlatformKindOf(ref.read(targetPlatformProvider)),
    isAmlogic: ref.read(deviceCapsProvider).isAmlogic,
    sourceLiveOverride:
        source?.engineLive ?? ref.read(settingsProvider).liveEngine.kind,
    channelPref: prefs.engine,
  );
}

/// Saves the other engine as this channel's choice and plays it with
/// [request]. Does nothing where only one engine exists.
Future<void> playWithOtherEngine(
  BuildContext context,
  WidgetRef ref,
  PlayRequest request,
) async {
  final key = request.item.key;
  final other = await otherLiveEngine(ref, request.sourceId, key);
  if (other == null) return;
  await ref.read(prefsDaoProvider).setEngine(request.sourceId, key, other);
  if (!context.mounted) return;
  await playLiveChannel(context, ref, request);
}
