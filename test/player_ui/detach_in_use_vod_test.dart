// A movie or an episode opened while a separate window holds the only
// connection of a one-connection account: it asks first (close the window
// and play here, or cancel) instead of opening a second connection. A
// window plays live channels only, so it is not offered to play there.
// Synthetic data only.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/player/connection_budget.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/ui/play_request.dart';
import 'package:iptv_player/player/ui/player_screen.dart';
import 'package:iptv_player/sources/models.dart';

import 'support/fake_detached_windows.dart';
import 'support/player_harness.dart';

/// A movie of [seedXtream]'s account (the adapter builds its URL).
PlayRequest _movie(int sourceId) => PlayRequest(
  sourceId: sourceId,
  item: const PlayableRef(
    kind: PlayableKind.movie,
    key: '901',
    ext: 'mp4',
    title: 'Panel Movie',
  ),
);

/// An episode of [seedXtream]'s account.
PlayRequest _episode(int sourceId) => PlayRequest(
  sourceId: sourceId,
  item: const PlayableRef(
    kind: PlayableKind.episode,
    key: '7001',
    ext: 'mkv',
    title: 'Panel Episode',
  ),
  seriesKey: '70',
);

Future<(RecordingDetachedWindows, ProviderContainer)> _pump(
  WidgetTester tester,
  PlayerRig rig,
  int sourceId,
) async {
  final windows = RecordingDetachedWindows(
    rig,
    initial: [
      DetachedViewer(
        id: 3,
        sourceId: sourceId,
        channelKey: '502',
        title: 'Panel Sport',
        maxConnections: 1,
        status: ViewerStatus.playing,
      ),
    ],
  );
  await pumpPlayerApp(
    tester,
    rig,
    tv: false,
    platform: TargetPlatform.windows,
    overrides: [detachedWindowsProvider.overrideWith(() => windows)],
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byKey(launcherKey)),
  );
  // The window holds the account's only connection.
  expect(connectionFits(container, sourceId), isFalse);
  return (windows, container);
}

void main() {
  late AppLocalizations l10n;
  setUp(() async => l10n = await AppLocalizations.delegate.load(en));

  for (final (name, make) in [('movie', _movie), ('episode', _episode)]) {
    group('a $name on a one-connection source busy in a window', () {
      testWidgets('asks first; opens nothing meanwhile', (tester) async {
        final rig = PlayerRig()..autoPlay(duration: const Duration(hours: 1));
        final id = await seedXtream(rig);
        final (windows, _) = await _pump(tester, rig, id);
        await openPlayerFor(tester, make(id));

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(l10n.detachInUseTitle('Panel Sport')), findsOneWidget);
        expect(find.text(l10n.detachInUseMessageVod), findsOneWidget);
        expect(find.text(l10n.detachCloseWindow), findsOneWidget);
        expect(find.text(l10n.commonCancel), findsOneWidget);
        // The window plays live channels only.
        expect(find.text(l10n.detachPlayInWindow), findsNothing);
        expect(find.byType(PlayerScreen), findsNothing);
        expect(rig.openedUrls, isEmpty);

        await tester.tap(find.text(l10n.commonCancel));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerScreen), findsNothing);
        expect(windows.closed, isEmpty);
        expect(rig.openedUrls, isEmpty);
        await disposeRig(tester, rig);
      });

      testWidgets('close the window and play here', (tester) async {
        final rig = PlayerRig()..autoPlay(duration: const Duration(hours: 1));
        final id = await seedXtream(rig);
        final (windows, container) = await _pump(tester, rig, id);
        await openPlayerFor(tester, make(id));
        await tester.tap(find.text(l10n.detachCloseWindow));
        await settle(tester);

        expect(windows.closed, [3]);
        expect(container.read(detachedWindowsProvider), isEmpty);
        expect(find.byType(PlayerScreen), findsOneWidget);
        expect(rig.openedUrls, hasLength(1));
        expect(windows.playedInWindow, isEmpty);
        await disposeRig(tester, rig);
      });
    });
  }
}
