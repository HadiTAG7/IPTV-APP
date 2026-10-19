// Retry in a failed detached window. The failed window holds no connection
// (the main player or another window may take it meanwhile), so its Retry
// asks the app, which plays the channel again only when the source has a
// connection free without that window, and otherwise tells the window what
// uses it. The window reports every (re)opening, so the app counts it.
// Synthetic data only (127.0.0.1 URLs, made-up credentials).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/player/connection_budget.dart';
import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';
import 'package:iptv_player/sources/models.dart';

import '../support/fake_engine.dart';
import '../support/fake_viewer.dart';
import 'support/viewer_harness.dart';

const _url = 'http://127.0.0.1:9/live/viewer7/Secret-Pass-9/501.ts';

const _play = PlayMessage(
  url: _url,
  title: 'Panel News',
  channelKey: '501',
  maxConnections: 1,
  secrets: ['viewer7', 'Secret-Pass-9'],
);

DetachRequest _request({String key = '501'}) => DetachRequest(
  sourceId: 7,
  channelKey: key,
  title: 'Panel News',
  stream: StreamRequest(
    url: 'http://127.0.0.1:9/live/viewer7/Secret-Pass-9/$key.ts',
    kind: PlayableKind.live,
  ),
  maxConnections: 1,
  secrets: const {'viewer7', 'Secret-Pass-9'},
);

/// The app's side over a real loopback server, with fake viewer processes.
class _App {
  _App() {
    container = ProviderContainer(
      overrides: [
        viewerLauncherProvider.overrideWithValue(launcher),
        viewerTimeoutsProvider.overrideWithValue(
          const ViewerTimeouts(
            start: Duration(seconds: 5),
            handshake: Duration(seconds: 5),
            close: Duration(milliseconds: 800),
          ),
        ),
        ringLogProvider.overrideWithValue(log),
        initialSettingsProvider.overrideWithValue(const AppSettings()),
      ],
    );
    addTearDown(container.dispose);
  }

  final launcher = FakeViewerLauncher();
  final log = RingLog();
  late final ProviderContainer container;

  DetachedWindows get windows =>
      container.read(detachedWindowsProvider.notifier);

  DetachedViewer window(int id) =>
      container.read(detachedWindowsProvider).singleWhere((w) => w.id == id);

  bool get fits => connectionFits(container, 7);

  /// A window on source 7 whose stream failed.
  Future<(int, FakeViewerProcess)> failedWindow() async {
    final id = await windows.detach(_request());
    final p = launcher.last;
    await until(() => p.received.isNotEmpty);
    p
      ..send(const OpeningMessage())
      ..send(const ViewerErrorMessage('HTTP error 404'));
    await until(() => window(id).status == ViewerStatus.failed);
    return (id, p);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the window', () {
    testWidgets('Retry opens nothing until the app sends the stream', (
      tester,
    ) async {
      final channel = FakeViewerChannel();
      final engines = FakeEngineFactory();
      await pumpViewer(tester, channel: channel, engines: engines);
      await failViewer(tester, channel, engines, _play);
      expect(channel.sentTypes, ['ready', 'opening', 'error']);
      final opens = engines.last.opened.length;

      // Meanwhile the main player took the account's only connection; the
      // user clicks Retry in the window.
      engines.last.onOpen = (e, _) => e.emitFirstFrame();
      await tester.tap(find.byKey(const ValueKey('player-retry')));
      await settleViewer(tester);
      expect(engines.last.opened, hasLength(opens));
      expect(channel.sentTypes.last, 'retry');

      // The app allows it: the stream opens, and the app hears so first.
      channel.deliver(_play);
      await settleViewer(tester);
      expect(engines.last.opened, hasLength(opens + 1));
      expect(channel.sentTypes.sublist(3), ['retry', 'opening', 'playing']);
      expect(find.byKey(const ValueKey('player-failure')), findsNothing);
      await unmountViewer(tester);
    });

    testWidgets('a refused Retry says the main window uses the connection, '
        'opens nothing and offers Close', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final channel = FakeViewerChannel();
      final engines = FakeEngineFactory();
      final exits = <int>[];
      await pumpViewer(
        tester,
        channel: channel,
        engines: engines,
        exits: exits,
      );
      await failViewer(tester, channel, engines, _play);
      final opens = engines.last.opened.length;

      await tester.tap(find.byKey(const ValueKey('player-retry')));
      await settleViewer(tester);
      channel.deliver(const InUseMessage(ConnectionInUseBy.mainWindow));
      await settleViewer(tester);
      expect(find.text(l10n.viewerInUseMainWindow), findsOneWidget);
      expect(find.text(l10n.playerPlaybackFailed), findsNothing);
      expect(engines.last.opened, hasLength(opens));

      // Retry asks again (the main player may be closed by now).
      await tester.tap(find.byKey(const ValueKey('player-retry')));
      await settleViewer(tester);
      expect(channel.sentTypes.where((t) => t == 'retry'), hasLength(2));
      channel.deliver(const InUseMessage(ConnectionInUseBy.otherWindow));
      await settleViewer(tester);
      expect(find.text(l10n.viewerInUseOtherWindow), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('player-close')));
      await settleViewer(tester);
      expect(channel.sentTypes.last, 'closed');
      expect(exits, [1]);
      expect(engines.last.opened, hasLength(opens));
      await unmountViewer(tester);
    });
  });

  group('the app', () {
    test('a failed window frees the connection; Retry with it still free '
        'plays again and counts the window first', () async {
      final app = _App();
      final (id, p) = await app.failedWindow();
      expect(app.fits, isTrue);

      p.send(const RetryMessage());
      await until(() => p.received.length == 2);
      final again = p.received.last as PlayMessage;
      expect(again.url, _request().stream.url);
      expect(app.window(id).status, ViewerStatus.opening);
      expect(app.fits, isFalse);
      expect(app.log.dump(), contains('playing again'));
      await app.windows.close(id);
    });

    test('Retry while the main player holds the one connection is refused '
        'and the window stays failed', () async {
      final app = _App();
      final (id, p) = await app.failedWindow();
      // The user opened a channel of that source in the main window.
      app.container.read(mainPlayerSourceProvider.notifier).set(7);

      p.send(const RetryMessage());
      await until(() => p.received.length == 2);
      expect(
        p.received.last,
        isA<InUseMessage>().having(
          (m) => m.by,
          'by',
          ConnectionInUseBy.mainWindow,
        ),
      );
      expect(p.received.whereType<PlayMessage>(), hasLength(1));
      expect(app.window(id).status, ViewerStatus.failed);
      expect(app.log.dump(), contains('retry refused'));

      // The main player closed: Retry plays again.
      app.container.read(mainPlayerSourceProvider.notifier).set(null);
      p.send(const RetryMessage());
      await until(() => p.received.length == 3);
      expect(p.received.last, isA<PlayMessage>());
      expect(app.window(id).status, ViewerStatus.opening);
      await app.windows.close(id);
    });

    test('Retry while a split-screen tile holds the one connection is '
        'refused as the main window', () async {
      final app = _App();
      final (id, p) = await app.failedWindow();
      app.container.read(multiViewTilesProvider.notifier).set({0: 7});

      p.send(const RetryMessage());
      await until(() => p.received.length == 2);
      expect(
        p.received.last,
        isA<InUseMessage>().having(
          (m) => m.by,
          'by',
          ConnectionInUseBy.mainWindow,
        ),
      );
      expect(app.window(id).status, ViewerStatus.failed);

      // The split screen closed: Retry plays again.
      app.container.read(multiViewTilesProvider.notifier).set(const {});
      p.send(const RetryMessage());
      await until(() => p.received.length == 3);
      expect(p.received.last, isA<PlayMessage>());
      await app.windows.close(id);
    });

    test(
      'Retry while another window holds the one connection is refused',
      () async {
        final app = _App();
        final (failed, p) = await app.failedWindow();
        // A second window on the same source took the connection.
        final other = await app.windows.detach(_request(key: '502'));
        expect(app.window(other).holdsConnection, isTrue);

        p.send(const RetryMessage());
        await until(() => p.received.length == 2);
        expect(
          p.received.last,
          isA<InUseMessage>().having(
            (m) => m.by,
            'by',
            ConnectionInUseBy.otherWindow,
          ),
        );
        expect(app.window(failed).status, ViewerStatus.failed);
        await app.windows.closeAll();
      },
    );

    test('Retry from a window that is not failed is ignored', () async {
      final app = _App();
      final id = await app.windows.detach(_request());
      final p = app.launcher.last;
      await until(() => p.received.isNotEmpty);
      p
        ..send(const PlayingMessage())
        ..send(const RetryMessage());
      await until(() => app.window(id).status == ViewerStatus.playing);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(p.received, hasLength(1));
      await app.windows.close(id);
    });

    test('a window opening again is counted at once', () async {
      final app = _App();
      final (id, p) = await app.failedWindow();
      expect(app.fits, isTrue);
      p.send(const OpeningMessage());
      await until(() => app.window(id).status == ViewerStatus.opening);
      expect(app.fits, isFalse);
      await app.windows.close(id);
    });
  });
}
