// Opening a channel while a separate window uses the source's connection.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/ui/player_screen.dart';

import 'support/fake_detached_windows.dart';
import 'support/player_harness.dart';

DetachedViewer _window(
  int sourceId, {
  ViewerStatus status = ViewerStatus.playing,
  int? maxConnections = 1,
}) => DetachedViewer(
  id: 3,
  sourceId: sourceId,
  channelKey: '502',
  title: 'Panel Sport',
  maxConnections: maxConnections,
  status: status,
);

Future<RecordingDetachedWindows> _pump(
  WidgetTester tester,
  PlayerRig rig,
  List<DetachedViewer> initial, {
  Locale locale = en,
}) async {
  final windows = RecordingDetachedWindows(rig, initial: initial);
  await pumpPlayerApp(
    tester,
    rig,
    tv: false,
    locale: locale,
    platform: TargetPlatform.windows,
    overrides: [detachedWindowsProvider.overrideWith(() => windows)],
  );
  return windows;
}

void main() {
  forLocales((locale) {
    group('a one-connection source busy in a window '
        '(${locale.languageCode})', () {
      late AppLocalizations l10n;
      setUp(() async => l10n = await AppLocalizations.delegate.load(locale));

      testWidgets('play the channel in the window instead', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedXtream(rig);
        final windows = await _pump(tester, rig, [_window(id)], locale: locale);
        final request = xtreamRequest(id, '501');
        await openPlayerFor(tester, request);

        expect(find.byType(PlayerScreen), findsNothing);
        expect(find.text(l10n.detachInUseTitle('Panel Sport')), findsOneWidget);
        expect(find.text(l10n.detachInUseMessage), findsOneWidget);
        // The first choice has the remote's focus.
        expect(focusedIn(const ValueKey('player-choice-0')), isTrue);
        await tester.tap(find.text(l10n.detachPlayInWindow));
        await tester.pumpAndSettle();

        expect(windows.playedInWindow.single.$1, 3);
        expect(windows.playedInWindow.single.$2.item.key, '501');
        expect(find.byType(PlayerScreen), findsNothing);
        expect(rig.engines.created, isEmpty);
        expect(windows.closed, isEmpty);
        await disposeRig(tester, rig);
      });

      testWidgets('close the window and play here', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedXtream(rig);
        final windows = await _pump(tester, rig, [_window(id)], locale: locale);
        await openPlayerFor(tester, xtreamRequest(id, '501'));
        await tester.tap(find.text(l10n.detachCloseWindow));
        await settle(tester);

        expect(windows.closed, [3]);
        expect(find.byType(PlayerScreen), findsOneWidget);
        expect(rig.engine.lastRequest!.url, endsWith('/501.ts'));
        expect(windows.playedInWindow, isEmpty);
        await disposeRig(tester, rig);
      });

      testWidgets('cancel', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final id = await seedXtream(rig);
        final windows = await _pump(tester, rig, [_window(id)], locale: locale);
        await openPlayerFor(tester, xtreamRequest(id, '501'));
        await tester.tap(find.text(l10n.commonCancel));
        await tester.pumpAndSettle();

        expect(find.byType(PlayerScreen), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(windows.closed, isEmpty);
        expect(windows.playedInWindow, isEmpty);
        expect(rig.engines.created, isEmpty);
        await disposeRig(tester, rig);
      });
    });
  });

  testWidgets('a window that cannot switch says so', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedXtream(rig);
    final windows = await _pump(tester, rig, [_window(id)]);
    windows.playResult = false;
    await openPlayerFor(tester, xtreamRequest(id, '501'));
    await tester.tap(find.text('Play this channel in the window instead'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't play in the separate window."), findsOneWidget);
    expect(find.byType(PlayerScreen), findsNothing);
    await disposeRig(tester, rig);
  });

  group('no question', () {
    testWidgets('when the source has no known limit', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await _pump(tester, rig, [_window(id, maxConnections: null)]);
      await openPlayerFor(tester, liveRequest(id));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(rig.log.dump(), contains('no known limit'));
      await disposeRig(tester, rig);
    });

    testWidgets('when the window failed (it holds no connection)', (
      tester,
    ) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedXtream(rig);
      await _pump(tester, rig, [_window(id, status: ViewerStatus.failed)]);
      await openPlayerFor(tester, xtreamRequest(id, '501'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(PlayerScreen), findsOneWidget);
      await disposeRig(tester, rig);
    });

    testWidgets('when the window plays from another source', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedXtream(rig);
      await _pump(tester, rig, [_window(id + 100)]);
      await openPlayerFor(tester, xtreamRequest(id, '501'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(PlayerScreen), findsOneWidget);
      await disposeRig(tester, rig);
    });
  });
}
