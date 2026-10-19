// The dialog openPlayer shows while the subscription's only connection is
// still closing (the last player's stream): a double click on the channel,
// or OK pressed again, does not cancel it; Back does. Desktop, a
// one-connection Xtream subscription. Synthetic data only.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/player/connection_budget.dart';
import 'package:iptv_player/player/ui/player_route.dart';
import 'package:iptv_player/player/ui/player_screen.dart';

import 'support/player_harness.dart';

const _wait = ValueKey('player-wait-stops');
const _message = ValueKey('player-wait-stops-message');
const _cancel = ValueKey('player-wait-stops-cancel');

/// Panel Sport, slow to open, is left with Escape while it still opens: its
/// stream keeps the connection for seconds (mpv's dispose stops it once the
/// open is done). Then a list of two channels shows again; returns the spot
/// of Panel News's row.
Future<Offset> _leftSlowSport(WidgetTester tester, PlayerRig rig) async {
  var slow = true;
  rig.engines.onCreate = (e) {
    e.disposeDelay = const Duration(seconds: 8);
    e.onOpen = (e, r) async {
      if (r.url.contains('/502.') && slow) {
        slow = false;
        await Future<void>.delayed(const Duration(seconds: 9));
      }
      e.emitFirstFrame();
    };
  };
  final xtream = await seedXtream(rig);
  await pumpPlayerApp(tester, rig, tv: false, platform: TargetPlatform.windows);
  final container = ProviderScope.containerOf(
    tester.element(find.byKey(launcherKey)),
  );
  container.listen(sourcesProvider, (_, _) {}, fireImmediately: true);
  for (var i = 0; i < 100; i++) {
    if (container.read(sourcesProvider).hasValue) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  // A channel list that opens the player on a click, like Live.
  final navigator = Navigator.of(tester.element(find.byKey(launcherKey)));
  unawaited(
    navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          body: ListView(
            children: [
              ListTile(
                key: const ValueKey('row-502'),
                title: const Text('Panel Sport'),
                onTap: () => unawaited(
                  openPlayer(context, xtreamRequest(xtream, '502')),
                ),
              ),
              ListTile(
                key: const ValueKey('row-501'),
                title: const Text('Panel News'),
                onTap: () => unawaited(
                  openPlayer(context, xtreamRequest(xtream, '501')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await settle(tester);

  await tester.tap(find.byKey(const ValueKey('row-502')));
  await settle(tester);
  expect(find.byType(PlayerScreen), findsOneWidget);
  await tester.pump(const Duration(seconds: 1));
  // Escape (the first may only leave window fullscreen).
  for (var i = 0; i < 3; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    if (find.byType(PlayerScreen).evaluate().isEmpty) break;
  }
  expect(find.byType(PlayerScreen), findsNothing);
  await tester.pump(const Duration(milliseconds: 500));
  return tester.getCenter(find.byKey(const ValueKey('row-501')));
}

/// Pumps until Panel Sport's stream has long stopped (12 s).
Future<void> _waitOut(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  await settle(tester);
}

int _newsOpens(PlayerRig rig) =>
    rig.openedUrls.where((u) => u.contains('/501.')).length;

Future<void> _end(WidgetTester tester, PlayerRig rig) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 10));
  await rig.db.close();
}

void main() {
  for (final double in [true, false]) {
    testWidgets('a ${double ? 'double' : 'single'} click on another channel '
        'waits for the stream still closing, then plays it', (tester) async {
      final rig = PlayerRig();
      final row = await _leftSlowSport(tester, rig);

      await tester.tapAt(row);
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byKey(_wait), findsOneWidget);
      // The second click of the double click lands beside the dialog.
      if (double) await tester.tapAt(row);
      await settle(tester);
      expect(find.byKey(_wait), findsOneWidget);
      expect(_newsOpens(rig), 0);

      await _waitOut(tester);
      expect(find.byKey(_wait), findsNothing);
      expect(_newsOpens(rig), 1, reason: 'Panel News never opened');
      expect(find.byType(PlayerScreen), findsOneWidget);
      await _end(tester, rig);
    });
  }

  testWidgets('OK (Enter) pressed again while it waits does not cancel; '
      'the channel plays once the stream has closed', (tester) async {
    final rig = PlayerRig();
    final row = await _leftSlowSport(tester, rig);

    await tester.tapAt(row);
    await settle(tester);
    expect(find.byKey(_wait), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(find.byKey(_wait), findsOneWidget);

    await _waitOut(tester);
    expect(_newsOpens(rig), 1, reason: 'Panel News never opened');
    expect(find.byType(PlayerScreen), findsOneWidget);
    await _end(tester, rig);
  });

  testWidgets('Back (Escape) cancels the wait: nothing opens', (tester) async {
    final rig = PlayerRig();
    final row = await _leftSlowSport(tester, rig);

    await tester.tapAt(row);
    await settle(tester);
    expect(find.byKey(_wait), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byKey(_wait), findsNothing);

    await _waitOut(tester);
    expect(_newsOpens(rig), 0);
    expect(find.byType(PlayerScreen), findsNothing);
    await _end(tester, rig);
  });

  testWidgets('the arrows reach Cancel, and OK on it cancels', (tester) async {
    final rig = PlayerRig();
    final row = await _leftSlowSport(tester, rig);

    await tester.tapAt(row);
    await settle(tester);
    expect(find.byKey(_wait), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await settle(tester);
    final cancel = Focus.of(
      tester.element(
        find.descendant(
          of: find.byKey(const ValueKey('player-wait-stops-cancel')),
          matching: find.byType(Text),
        ),
      ),
    );
    expect(cancel.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(find.byKey(_wait), findsNothing);

    await _waitOut(tester);
    expect(_newsOpens(rig), 0);
    await _end(tester, rig);
  });

  for (final locale in [en, ar]) {
    for (final arrow in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowUp,
    ]) {
      testWidgets('${locale.languageCode} TV: ${arrow.debugName} on the '
          'message reaches Cancel, and Up does not leave it', (tester) async {
        final rig = PlayerRig()..autoPlay();
        final xtream = await seedXtream(rig);
        await pumpPlayerApp(tester, rig, tv: true, locale: locale);
        final container = ProviderScope.containerOf(
          tester.element(find.byKey(launcherKey)),
        );
        container.listen(sourcesProvider, (_, _) {}, fireImmediately: true);
        for (var i = 0; i < 100; i++) {
          if (container.read(sourcesProvider).hasValue) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        // A stream of the subscription still stopping.
        final stopped = Completer<void>();
        container
            .read(connectionDrainsProvider.notifier)
            .add(xtream, stopped.future);
        unawaited(
          openPlayer(
            tester.element(find.byKey(launcherKey)),
            xtreamRequest(xtream, '501'),
          ),
        );
        await settle(tester);
        expect(focusedIn(_message), isTrue);

        await press(tester, arrow);
        expect(focusedIn(_cancel), isTrue);
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(focusedIn(_cancel), isTrue);

        stopped.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 10));
        await rig.db.close();
      });
    }
  }
}
