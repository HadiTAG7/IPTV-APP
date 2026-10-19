// A one-connection subscription never has two streams open because of the
// split screen. A tile that gives up a stream still opening (its stop waits
// for the open) keeps the connection counted until the stream has stopped
// (ConnectionDrains), whatever gave it up: Delete, a channel of another
// source, 4 -> 2 tiles, leaving the split screen (then the player), or a
// separate window (then leaving and the player). What waits for it opens
// once it has stopped. Synthetic data only.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/player/connection_budget.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/multiview/multiview_screen.dart';
import 'package:iptv_player/player/ui/player_screen.dart';

import '../support/fake_engine.dart';
import 'support/fake_detached_windows.dart';
import 'support/multiview_harness.dart';
import 'support/player_harness.dart';

/// How long Panel News (Xtream 501) takes to open: its stop waits for it.
const _slowOpen = Duration(seconds: 9);

const _inUse = ValueKey('multiview-in-use');
const _buffering = ValueKey('multiview-buffering');

/// The streams of the one-connection subscription (Panel News 501, Panel
/// Sport 502), in the engines and in separate windows, and whether two were
/// ever open at once. An engine's stream is open from its open until that
/// open is done and the engine was stopped or disposed after it; a
/// window's from [DetachedWindows.detach] until it is closed.
class _Streams {
  _Streams(this.rig) {
    rig.engines.onCreate = (e) => e.onOpen = (e, r) async {
      final channel = _channel(r.url);
      if (channel != null) {
        _opens('engine $channel', engine: e);
        _opening.add(e);
      }
      // Panel News opens slowly.
      if (channel == '501') await Future<void>.delayed(_slowOpen);
      _opening.remove(e);
      e.emitFirstFrame();
    };
  }

  final PlayerRig rig;
  final _opening = <FakeEngine>{};

  /// The channels of the separate windows playing.
  final windows = <String>[];

  /// What opened, in order: `engine 501`, `window 501`...
  final opens = <String>[];

  /// What opened while another stream of the subscription was open.
  final overlaps = <String>[];

  static String? _channel(String url) => url.contains('/501.')
      ? '501'
      : url.contains('/502.')
      ? '502'
      : null;

  /// Whether [e] has a stream of the subscription open.
  bool _holds(FakeEngine e) {
    final last = e.opened.lastOrNull;
    if (last == null || _channel(last.url) == null) return false;
    if (_opening.contains(e)) return true;
    final after = e.calls.skip(e.calls.lastIndexOf('open') + 1);
    return !after.any((c) => c == 'stop' || c == 'dispose');
  }

  void _opens(String what, {FakeEngine? engine}) {
    final open = [
      for (final e in rig.engines.created)
        if (!identical(e, engine) && _holds(e))
          'engine ${_channel(e.opened.last.url)}',
      for (final w in windows) 'window $w',
    ];
    if (open.isNotEmpty) overlaps.add('$what while ${open.join(', ')}');
    opens.add(what);
  }
}

/// Separate windows listed as soon as they are asked for, like the app's;
/// each plays its channel from then until it is closed ([_Streams]).
class _Windows extends ListingDetachedWindows {
  _Windows(super.rig, this.streams);

  final _Streams streams;

  @override
  Future<int> detach(DetachRequest request) {
    streams
      .._opens('window ${request.channelKey}')
      ..windows.add(request.channelKey);
    return super.detach(request);
  }

  @override
  Future<void> close(int viewerId, {Duration? wait}) {
    for (final w in state) {
      if (w.id == viewerId) streams.windows.remove(w.channelKey);
    }
    return super.close(viewerId, wait: wait);
  }
}

/// The app with the Xtream subscription (one connection) and the free
/// list, and the split screen open with Free 1 (handed over by the player)
/// in tile 1, the active one. Returns the Xtream and the free source.
Future<(int, int)> _split(WidgetTester tester, _Streams streams) async {
  final rig = streams.rig;
  final xtream = await seedXtream(rig);
  final free = await seedFree(rig);
  await pumpPlayerApp(
    tester,
    rig,
    tv: false,
    platform: TargetPlatform.windows,
    overrides: [
      detachedWindowsProvider.overrideWith(() => _Windows(rig, streams)),
    ],
  );
  await openSplit(tester, freeRequest(free, 'f1'));
  return (xtream, free);
}

/// [_split], then tile 1 changes to Panel News, still opening.
Future<(int, int)> _newsOpening(WidgetTester tester, _Streams streams) async {
  final (xtream, free) = await _split(tester, streams);
  await press(tester, LogicalKeyboardKey.keyC);
  await openedPicker(tester);
  await pickChannel(tester, 'Panel News', sourceId: xtream);
  expect(streams.opens, ['engine 501']);
  return (xtream, free);
}

/// Lets Panel News finish opening (and its stop run).
Future<void> _newsDone(WidgetTester tester) async {
  await tester.pump(_slowOpen);
  await settleSplit(tester);
}

/// Back out of the split screen (window fullscreen first, if on).
Future<void> _leave(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    if (find.byType(MultiViewScreen).evaluate().isEmpty) break;
    await press(tester, LogicalKeyboardKey.escape);
    await settleSplit(tester);
  }
  expect(find.byType(MultiViewScreen), findsNothing);
}

ProviderContainer _app(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byKey(launcherKey)));

/// Panel Sport picked in tile [i] waits, showing it opening, while Panel
/// News stops; then it plays, and the two were never open at once.
Future<void> _sportWaitsThenPlays(
  WidgetTester tester,
  _Streams streams,
  int xtream,
  int i,
) async {
  final container = containerOf(tester);
  expect(container.read(connectionBudgetProvider).usedOn(xtream), 1);
  expect(container.read(connectionBudgetProvider).tilesOn(xtream), isEmpty);
  await _pickIn(tester, i, 'Panel Sport', sourceId: xtream);
  expect(find.byKey(_inUse), findsNothing);
  expect(inSlot(i, find.byKey(_buffering)), findsOneWidget);
  expect(streams.opens, ['engine 501']);

  await _newsDone(tester);
  expect(streams.opens, ['engine 501', 'engine 502']);
  expect(streams.overlaps, isEmpty);
  expect(find.byKey(_inUse), findsNothing);
  expect(inSlot(i, find.byKey(_buffering)), findsNothing);
  expect(container.read(connectionDrainsProvider), isEmpty);
  expect(container.read(connectionBudgetProvider).usedOn(xtream), 1);
  expect(
    container.read(connectionBudgetProvider).tilesOn(xtream),
    hasLength(1),
  );
}

/// Picks [name] in tile [i]: with its "+" when empty, else with C.
Future<void> _pickIn(
  WidgetTester tester,
  int i,
  String name, {
  int? sourceId,
}) async {
  final add = inSlot(i, find.byKey(const ValueKey('multiview-add')));
  if (add.evaluate().isNotEmpty) {
    await addChannel(tester, i, name, sourceId: sourceId);
    return;
  }
  await click(tester, slot(i));
  await press(tester, LogicalKeyboardKey.keyC);
  await openedPicker(tester);
  await pickChannel(tester, name, sourceId: sourceId);
}

void main() {
  group('a tile gives up Panel News while it still opens (one connection)', () {
    testWidgets('Delete: Panel Sport in tile 2 waits until it has stopped, '
        'then plays', (tester) async {
      final rig = PlayerRig();
      final streams = _Streams(rig);
      final (xtream, _) = await _newsOpening(tester, streams);

      await press(tester, LogicalKeyboardKey.delete);
      await _sportWaitsThenPlays(tester, streams, xtream, 1);
      await disposeRig(tester, rig);
    });

    testWidgets('a channel of another source in tile 1: Panel Sport in tile '
        '2 waits until it has stopped, then plays', (tester) async {
      final rig = PlayerRig();
      final streams = _Streams(rig);
      final (xtream, free) = await _newsOpening(tester, streams);

      await press(tester, LogicalKeyboardKey.keyC);
      await openedPicker(tester);
      await pickChannel(tester, 'Free 2', sourceId: free);
      await _sportWaitsThenPlays(tester, streams, xtream, 1);
      expect(
        rig.openedUrls.where((u) => u.contains(freeUrl('f2'))),
        hasLength(1),
      );
      await disposeRig(tester, rig);
    });

    testWidgets('4 -> 2 drops its tile: Panel Sport in a kept tile waits '
        'until it has stopped, then plays', (tester) async {
      final rig = PlayerRig();
      final streams = _Streams(rig);
      final (xtream, free) = await _split(tester, streams);
      await press(tester, LogicalKeyboardKey.keyL);
      await addChannel(tester, 1, 'Free 2', sourceId: free);
      await addChannel(tester, 2, 'Panel News', sourceId: xtream);
      expect(streams.opens, ['engine 501']);
      // Back to 2 from tile 1: Free 1 and Free 2 stay, Panel News goes.
      await click(tester, slot(0));
      await press(tester, LogicalKeyboardKey.keyL);
      expect(find.text('Panel News'), findsNothing);

      await _sportWaitsThenPlays(tester, streams, xtream, 1);
      await disposeRig(tester, rig);
    });

    testWidgets('leaving the split screen: the player on the same '
        'subscription opens once it has stopped', (tester) async {
      final rig = PlayerRig();
      final streams = _Streams(rig);
      final (xtream, _) = await _newsOpening(tester, streams);

      await _leave(tester);
      final container = _app(tester);
      expect(container.read(multiViewTilesProvider), isEmpty);
      expect(container.read(connectionBudgetProvider).usedOn(xtream), 1);
      await openPlayerFor(tester, xtreamRequest(xtream, '502'));
      expect(find.byType(PlayerScreen), findsNothing);
      expect(streams.opens, ['engine 501']);

      await _newsDone(tester);
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(streams.opens, ['engine 501', 'engine 502']);
      expect(streams.overlaps, isEmpty);
      expect(container.read(connectionDrainsProvider), isEmpty);
      await disposeRig(tester, rig);
    });

    testWidgets('the split screen goes away without its Back: the player on '
        'the same subscription opens once it has stopped', (tester) async {
      final rig = PlayerRig();
      final streams = _Streams(rig);
      final (xtream, _) = await _newsOpening(tester, streams);

      tester
          .state<NavigatorState>(find.byType(Navigator))
          .popUntil((route) => route.isFirst);
      await settleSplit(tester);
      expect(find.byType(MultiViewScreen), findsNothing);
      expect(_app(tester).read(connectionBudgetProvider).usedOn(xtream), 1);
      await openPlayerFor(tester, xtreamRequest(xtream, '502'));
      expect(find.byType(PlayerScreen), findsNothing);

      await _newsDone(tester);
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(streams.opens, ['engine 501', 'engine 502']);
      expect(streams.overlaps, isEmpty);
      await disposeRig(tester, rig);
    });

    testWidgets('D, then leaving the split screen: the window still opens, '
        'counted throughout; the player on the same subscription asks about '
        'it, and plays once it is closed', (tester) async {
      final rig = PlayerRig();
      final streams = _Streams(rig);
      final (xtream, _) = await _newsOpening(tester, streams);
      final l10n = await AppLocalizations.delegate.load(en);
      final windows = containerOf(
        tester,
      ).read(detachedWindowsProvider.notifier) as _Windows;

      await press(tester, LogicalKeyboardKey.keyD);
      expect(windows.detached, isEmpty);
      await _leave(tester);
      final container = _app(tester);
      expect(container.read(connectionBudgetProvider).usedOn(xtream), 1);
      await openPlayerFor(tester, xtreamRequest(xtream, '502'));
      expect(find.byType(PlayerScreen), findsNothing);

      // Panel News stopped, then went to the window the user asked for,
      // which the player now finds in its way.
      await _newsDone(tester);
      expect(windows.detached.single.channelKey, '501');
      expect(container.read(connectionDrainsProvider), isEmpty);
      expect(container.read(connectionBudgetProvider).usedOn(xtream), 1);
      expect(find.text(l10n.detachInUseTitle('Panel News')), findsOneWidget);
      expect(find.byType(PlayerScreen), findsNothing);
      expect(streams.opens, ['engine 501', 'window 501']);

      await tester.tap(find.text(l10n.detachCloseWindow));
      await settle(tester);
      expect(windows.closed, hasLength(1));
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(streams.opens, ['engine 501', 'window 501', 'engine 502']);
      expect(streams.overlaps, isEmpty);
      await disposeRig(tester, rig);
    });
  });

  group('a tile waiting for a stream to stop', () {
    testWidgets('changed again, it plays the new channel at once and never '
        'the one it waited for', (tester) async {
      final rig = PlayerRig();
      final streams = _Streams(rig);
      final (xtream, free) = await _newsOpening(tester, streams);
      await press(tester, LogicalKeyboardKey.delete);
      await addChannel(tester, 1, 'Panel Sport', sourceId: xtream);
      expect(inSlot(1, find.byKey(_buffering)), findsOneWidget);

      await press(tester, LogicalKeyboardKey.keyC);
      await openedPicker(tester);
      await pickChannel(tester, 'Free 2', sourceId: free);
      expect(
        rig.openedUrls.where((u) => u.contains(freeUrl('f2'))),
        hasLength(1),
      );
      expect(containerOf(tester).read(multiViewTilesProvider), {1: free});

      await _newsDone(tester);
      expect(streams.opens, ['engine 501']);
      expect(find.byKey(_inUse), findsNothing);
      expect(containerOf(tester).read(connectionDrainsProvider), isEmpty);
      await disposeRig(tester, rig);
    });

    testWidgets('the split screen closed meanwhile: nothing opens and no '
        'message shows', (tester) async {
      final rig = PlayerRig();
      final streams = _Streams(rig);
      final (xtream, _) = await _newsOpening(tester, streams);
      await press(tester, LogicalKeyboardKey.delete);
      await addChannel(tester, 1, 'Panel Sport', sourceId: xtream);
      expect(inSlot(1, find.byKey(_buffering)), findsOneWidget);

      await _leave(tester);
      await _newsDone(tester);
      expect(streams.opens, ['engine 501']);
      expect(find.byKey(_inUse), findsNothing);
      final container = _app(tester);
      expect(container.read(connectionDrainsProvider), isEmpty);
      expect(container.read(connectionBudgetProvider).usedOn(xtream), 0);
      await disposeRig(tester, rig);
    });
  });
}
