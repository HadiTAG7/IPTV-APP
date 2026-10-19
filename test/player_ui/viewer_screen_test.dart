// The detached window's viewer screen with fake engines, a fake connection
// to the app and recorded window calls. Synthetic data only.
import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/core/platform/window_controls.dart';
import 'package:iptv_player/core/platform/window_fullscreen.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/player/detach/viewer_app.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';
import 'package:iptv_player/player/detach/viewer_screen.dart';
import 'package:iptv_player/player/engine/engine_factory.dart';
import 'package:iptv_player/player/engine/player_engine.dart';

import '../support/fake_engine.dart';
import 'support/player_harness.dart' show forLocales, en, ar;
import 'support/viewer_harness.dart' show FakeViewerChannel;

const _url = 'http://127.0.0.1:9/live/viewer7/Secret-Pass-9/501.ts';

const _play = PlayMessage(
  url: _url,
  headers: {'Referer': 'http://127.0.0.1:9/'},
  userAgent: 'Panel/2.0',
  title: 'Panel News',
  channelKey: '501',
  maxConnections: 1,
  hardwareDecoding: false,
  lite: true,
  secrets: ['viewer7', 'Secret-Pass-9'],
);

class _Rig {
  final channel = FakeViewerChannel();
  final engines = FakeEngineFactory();
  final options = <EngineOptions>[];
  final window = <String>[];
  final wakelock = <bool>[];
  final log = RingLog();
  int exits = 0;

  /// What the runner tells by itself (the small window maximized).
  final compactEnded = StreamController<void>.broadcast();

  late final controls = WindowControls(
    setAlwaysOnTop: (on) async => window.add('top $on'),
    setTitle: (title) async => window.add('title $title'),
    enterCompact: () async => window.add('enterCompact'),
    exitCompact: () async => window.add('exitCompact'),
    fullscreen: WindowFullscreen(
      enter: () async => window.add('enterFullscreen'),
      exit: () async => window.add('exitFullscreen'),
    ),
    compactEnded: compactEnded.stream,
  );

  FakeEngine get engine => engines.last;

  /// Every engine shows a first frame when opened.
  void autoPlay() =>
      engines.onCreate = (e) => e.onOpen = (e, _) => e.emitFirstFrame();
}

Future<_Rig> _pump(
  WidgetTester tester, {
  Locale locale = en,
  Size size = const Size(960, 540),
  _Rig? rig,
}) async {
  final r = rig ?? (_Rig()..autoPlay());
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ViewerApp(
      locale: locale,
      home: ViewerScreen(
        channel: r.channel,
        window: r.controls,
        exitProcess: () async => r.exits++,
        engines: (options) {
          r.options.add(options);
          return r.engines.call;
        },
        platform: TargetPlatform.windows,
        wakelock: r.wakelock.add,
        log: r.log,
        clock: FakeClock(DateTime.utc(2026, 10, 19, 20)),
      ),
    ),
  );
  await tester.pump();
  return r;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Moves the mouse over the video (shows the bar).
Future<TestGesture> _hover(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: const Offset(100, 100));
  await mouse.moveTo(const Offset(110, 105));
  await _settle(tester);
  return mouse;
}

Future<void> _tap(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('viewer-$id')));
  await _settle(tester);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  forLocales((locale) {
    testWidgets('says ready, then plays what the app sends '
        '(${locale.languageCode})', (tester) async {
      final rig = await _pump(tester, locale: locale);
      expect(rig.channel.sentTypes, ['ready']);
      expect(find.byKey(const ValueKey('viewer-buffering')), findsOneWidget);

      rig.channel.deliver(_play);
      await _settle(tester);
      final opened = rig.engine.opened.single;
      expect(opened.url, _url);
      expect(opened.isLive, isTrue);
      expect(opened.headers, {
        'Referer': 'http://127.0.0.1:9/',
        'User-Agent': 'Panel/2.0',
      });
      expect(rig.engine.kind, EngineKind.mpv);
      expect(rig.options.last.hardwareDecoding, isFalse);
      expect(rig.options.last.lite, isTrue);
      expect(rig.window, ['title Panel News']);
      expect(rig.channel.sentTypes, ['ready', 'opening', 'playing']);
      expect(rig.wakelock.last, isTrue);
      expect(find.byKey(const ValueKey('viewer-buffering')), findsNothing);

      // The bar shows the channel, in the app's language.
      await _hover(tester);
      final l10n = await AppLocalizations.delegate.load(locale);
      expect(find.text('Panel News'), findsOneWidget);
      expect(find.byTooltip(l10n.viewerPin), findsOneWidget);
      expect(find.byTooltip(l10n.viewerCompact), findsOneWidget);
      expect(find.byTooltip(l10n.playerFullscreen), findsOneWidget);
      expect(find.byTooltip(l10n.viewerMute), findsOneWidget);
      expect(find.byTooltip(l10n.commonClose), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('Panel News'))),
        locale == ar ? TextDirection.rtl : TextDirection.ltr,
      );
      await _unmount(tester);
    });
  });

  testWidgets('another channel from the app replaces the stream', (
    tester,
  ) async {
    final rig = await _pump(tester);
    rig.channel.deliver(_play);
    await _settle(tester);
    rig.channel.deliver(
      const PlayMessage(url: 'http://127.0.0.1:9/live/502.ts', title: 'Sport'),
    );
    await _settle(tester);
    expect(rig.engines.created, hasLength(1));
    expect(rig.engine.opened.map((r) => r.url), [
      _url,
      'http://127.0.0.1:9/live/502.ts',
    ]);
    expect(rig.engine.calls, containsAllInOrder(['open', 'stop', 'open']));
    expect(rig.window.last, 'title Sport');
    const told = ['ready', 'opening', 'playing', 'opening', 'playing'];
    expect(rig.channel.sentTypes, told);
    await _unmount(tester);
    // Torn down with the process: nothing more is sent or ended.
    expect(rig.channel.isClosed, isTrue);
    expect(rig.exits, 0);
    expect(rig.channel.sentTypes, told);
  });

  testWidgets('pin, small window and fullscreen call the window', (
    tester,
  ) async {
    final rig = await _pump(tester);
    rig.channel.deliver(_play);
    await _settle(tester);
    rig.window.clear();
    await _hover(tester);

    await _tap(tester, 'pin');
    await _tap(tester, 'pin');
    expect(rig.window, ['top true', 'top false']);

    rig.window.clear();
    await _tap(tester, 'compact');
    expect(rig.window, ['enterCompact']);
    // Fullscreen from the small window: the runner leaves it first, on
    // the monitor it is on now.
    await _tap(tester, 'fullscreen');
    expect(rig.window, ['enterCompact', 'enterFullscreen']);
    // And the small window from fullscreen.
    rig.window.clear();
    await _tap(tester, 'compact');
    expect(rig.window, ['exitFullscreen', 'enterCompact']);
    await _tap(tester, 'compact');
    expect(rig.window, ['exitFullscreen', 'enterCompact', 'exitCompact']);
    await _unmount(tester);
  });

  testWidgets('the small window maximized from its title bar is no longer '
      'small for the bar either', (tester) async {
    final rig = await _pump(tester);
    rig.channel.deliver(_play);
    await _settle(tester);
    await _hover(tester);
    final l10n = await AppLocalizations.delegate.load(en);
    await _tap(tester, 'compact');
    expect(find.byTooltip(l10n.viewerNormalSize), findsOneWidget);

    rig.compactEnded.add(null);
    await _settle(tester);
    expect(find.byTooltip(l10n.viewerCompact), findsOneWidget);
    expect(find.byTooltip(l10n.viewerNormalSize), findsNothing);
    // The next click makes it small again.
    rig.window.clear();
    await _tap(tester, 'compact');
    expect(rig.window, ['enterCompact']);
    await _unmount(tester);
  });

  testWidgets('F, F11 and double clicks toggle fullscreen; Escape leaves it', (
    tester,
  ) async {
    final rig = await _pump(tester);
    rig.channel.deliver(_play);
    await _settle(tester);
    rig.window.clear();

    // Escape outside fullscreen does nothing.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await _settle(tester);
    expect(rig.window, ['enterFullscreen', 'exitFullscreen']);

    final video = find.byKey(const ValueKey('viewer-gestures'));
    await tester.tap(video);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(video);
    await _settle(tester);
    expect(rig.window.last, 'enterFullscreen');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(rig.window.last, 'exitFullscreen');
    await _unmount(tester);
  });

  testWidgets('mute and volume reach the engine', (tester) async {
    final rig = await _pump(tester);
    rig.channel.deliver(_play);
    await _settle(tester);
    final engine = rig.engine;

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await _settle(tester);
    expect(engine.muted, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await _settle(tester);
    expect(engine.muted, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _settle(tester);
    expect(engine.volume, closeTo(0.8, 0.001));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await _settle(tester);
    expect(engine.volume, closeTo(0.9, 0.001));

    // The mouse wheel too.
    final mouse = await _hover(tester);
    await mouse.moveTo(const Offset(300, 400));
    tester.binding.handlePointerEvent(
      const PointerScrollEvent(
        position: Offset(300, 400),
        scrollDelta: Offset(0, 40),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await _settle(tester);
    expect(engine.volume, closeTo(0.8, 0.001));

    await _tap(tester, 'mute');
    expect(engine.muted, isTrue);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('viewer-mute')),
        matching: find.byIcon(Icons.volume_off),
      ),
      findsOneWidget,
    );
    // Turning the volume up unmutes.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await _settle(tester);
    expect(engine.muted, isFalse);
    await _unmount(tester);
  });

  testWidgets('a dropped stream reconnects under a banner', (tester) async {
    final rig = await _pump(tester);
    rig.channel.deliver(_play);
    await _settle(tester);
    rig.engine.emitError('Connection reset by peer');
    await _settle(tester);
    expect(find.byKey(const ValueKey('player-reconnect')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(rig.engine.opened, hasLength(2));
    expect(find.byKey(const ValueKey('player-reconnect')), findsNothing);
    expect(rig.channel.sentTypes, ['ready', 'opening', 'playing']);
    await _unmount(tester);
  });

  forLocales((locale) {
    testWidgets('a failure shows Retry; the app hears it redacted '
        '(${locale.languageCode})', (tester) async {
      final rig = _Rig();
      rig.engines.onCreate = (e) => e.onOpen = (e, r) {
        e.emitError('Failed to open ${r.url} (HTTP error 404 Not Found)');
      };
      await _pump(tester, rig: rig, locale: locale);
      rig.channel.deliver(_play);
      await _settle(tester);
      // One connection: a 404 right after opening may be the account's
      // connection still held elsewhere; it is retried twice first.
      expect(find.byKey(const ValueKey('player-failure')), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      expect(rig.engine.opened, hasLength(3));

      final l10n = await AppLocalizations.delegate.load(locale);
      expect(find.byKey(const ValueKey('player-failure')), findsOneWidget);
      expect(find.text(l10n.playerPlaybackFailed), findsOneWidget);
      expect(find.byKey(const ValueKey('player-copy-report')), findsNothing);
      final shown = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');
      expect(shown, isNot(contains('Secret-Pass-9')));
      final error = rig.channel.sent.last as ViewerErrorMessage;
      expect(error.message, contains('404'));
      expect(error.message, isNot(contains('Secret-Pass-9')));
      expect(error.message, isNot(contains('viewer7')));
      expect(rig.wakelock.last, isFalse);
      // The retry button has the keyboard.
      final retry = find.byKey(const ValueKey('player-retry'));
      expect(
        Focus.of(tester.element(find.text(l10n.playerRetry))).hasPrimaryFocus,
        isTrue,
      );

      // Close is on the card too.
      expect(find.byKey(const ValueKey('player-close')), findsOneWidget);

      // Retry asks the app; nothing opens before it answers.
      rig.autoPlay();
      rig.engine.onOpen = (e, _) => e.emitFirstFrame();
      await tester.tap(retry);
      await _settle(tester);
      expect(rig.engine.opened, hasLength(3));
      expect(rig.channel.sentTypes, ['ready', 'opening', 'error', 'retry']);
      // A second click while the app answers asks nothing more.
      await tester.tap(retry);
      await _settle(tester);
      expect(rig.channel.sentTypes.where((t) => t == 'retry'), hasLength(1));

      // The app sends the stream again.
      rig.channel.deliver(_play);
      await _settle(tester);
      expect(find.byKey(const ValueKey('player-failure')), findsNothing);
      expect(rig.engine.opened, hasLength(4));
      expect(rig.channel.sentTypes, [
        'ready',
        'opening',
        'error',
        'retry',
        'opening',
        'playing',
      ]);
      await _unmount(tester);
    });
  });

  group('closing', () {
    testWidgets('the app going away stops the stream and exits', (
      tester,
    ) async {
      final rig = await _pump(tester);
      rig.channel.deliver(_play);
      await _settle(tester);
      rig.channel.close();
      await _settle(tester);
      expect(rig.engine.calls.last, 'stop');
      expect(rig.exits, 1);
      expect(rig.channel.sentTypes, isNot(contains('closed')));
      expect(rig.wakelock.last, isFalse);
      await _unmount(tester);
    });

    testWidgets('close from the app', (tester) async {
      final rig = await _pump(tester);
      rig.channel.deliver(_play);
      await _settle(tester);
      rig.channel.deliver(const CloseMessage());
      await _settle(tester);
      expect(rig.engine.calls.last, 'stop');
      expect(rig.exits, 1);
      expect(rig.channel.isClosed, isTrue);
      expect(rig.channel.sentTypes, isNot(contains('closed')));
      await _unmount(tester);
    });

    testWidgets('the close button stops, tells the app, exits', (tester) async {
      final rig = await _pump(tester);
      rig.channel.deliver(_play);
      await _settle(tester);
      await _hover(tester);
      await _tap(tester, 'close');
      expect(rig.engine.calls.last, 'stop');
      expect(rig.channel.sentTypes.last, 'closed');
      expect(rig.exits, 1);
      expect(rig.channel.isClosed, isTrue);
      await _unmount(tester);
    });

    testWidgets("the window's own close button: stop, tell, let it exit", (
      tester,
    ) async {
      final rig = await _pump(tester);
      rig.channel.deliver(_play);
      await _settle(tester);
      AppExitResponse? response;
      unawaited(
        tester.binding.handleRequestAppExit().then((r) => response = r),
      );
      await _settle(tester);
      expect(response, AppExitResponse.exit);
      expect(rig.engine.calls.last, 'stop');
      expect(rig.channel.sentTypes.last, 'closed');
      // The platform exits by itself.
      expect(rig.exits, 0);
      await _unmount(tester);
    });
  });

  testWidgets('the small window keeps its buttons, without title or slider', (
    tester,
  ) async {
    final rig = await _pump(tester, size: const Size(320, 180));
    rig.channel.deliver(_play);
    await _settle(tester);
    await _hover(tester);
    for (final id in ['mute', 'pin', 'compact', 'fullscreen', 'close']) {
      expect(find.byKey(ValueKey('viewer-$id')), findsOneWidget, reason: id);
    }
    expect(find.text('Panel News'), findsNothing);
    expect(find.byKey(const ValueKey('viewer-volume')), findsNothing);
    await _unmount(tester);
  });
}
