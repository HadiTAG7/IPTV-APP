import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/app.dart';
import 'package:iptv_player/app/form_factor.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/platform/device_caps.dart';
import 'package:iptv_player/features/diagnostics/diagnostics_report.dart';
import 'package:iptv_player/features/diagnostics/diagnostics_screen.dart';
import 'package:iptv_player/features/diagnostics/engine_ab_test.dart';
import 'package:iptv_player/features/diagnostics/providers.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/player/engine/engine_factory.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/player/player_providers.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/theme/app_theme.dart';
import 'package:iptv_player/tv/dpad_shortcuts.dart';
import 'package:iptv_player/tv/key_repeat.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../player_ui/support/player_harness.dart';

const _boxCaps = DeviceCaps(
  uiModeTv: true,
  leanback: true,
  touch: false,
  totalRamMb: 2048,
  cpuCount: 4,
  hardware: 'g12a',
  socManufacturer: 'Amlogic',
  supportedAbis: ['armeabi-v7a', 'armeabi'],
  decoders: {'audio/ac3': true, 'video/hevc': true},
  sdkInt: 30,
  model: 'Box 1',
  manufacturer: 'Acme',
);

const _secret = 'hunter2-secret';

class _DiagRig {
  _DiagRig() : rig = PlayerRig();

  final PlayerRig rig;
  final options = <EngineOptions>[];
}

Future<void> _pumpDiagnostics(
  WidgetTester tester,
  _DiagRig d, {
  bool tv = true,
  Locale locale = en,
  DeviceCaps? caps,
  TargetPlatform platform = TargetPlatform.android,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final rig = d.rig;
  final size = tv ? const Size(960, 540) : const Size(390, 800);
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  addTearDown(() => applyFocusHighlightStrategy(tv: false));
  KeyRepeatThrottle.instance = KeyRepeatThrottle(clock: rig.clock);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      rig.platformCalls.add(call);
      if (call.method == 'Clipboard.setData') {
        rig.clipboard = (call.arguments as Map)['text'] as String?;
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(rig.db),
        deviceCapsProvider.overrideWithValue(
          caps ?? (tv ? _boxCaps : phoneCaps),
        ),
        ringLogProvider.overrideWithValue(rig.log),
        clockProvider.overrideWithValue(rig.clock),
        targetPlatformProvider.overrideWithValue(platform),
        engineFactoryBuilderProvider.overrideWithValue((options) {
          d.options.add(options);
          return rig.engines.call;
        }),
        appVersionProvider.overrideWith((ref) async => '0.1.0+1'),
        diagnosticsTestTimeoutProvider.overrideWithValue(timeout),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          navigatorKey: ref.watch(navigatorKeyProvider),
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(tv: tv),
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          shortcuts: appShortcuts,
          builder: (context, child) =>
              AppFrame(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: DiagnosticsScreen()),
        ),
      ),
    ),
  );
  await settle(tester);
}

Finder _result(EngineKind e, int stream) =>
    find.byKey(ValueKey('diagnostics-result-${e.name}-$stream'));

void main() {
  group('device report', () {
    forLocales((locale) {
      testWidgets(
        'TV shows caps, version and settings (${locale.languageCode})',
        (tester) async {
          final d = _DiagRig();
          await _pumpDiagnostics(tester, d, locale: locale);
          final l10n = lookupAppLocalizations(locale);
          expect(find.text('Acme Box 1'), findsOneWidget);
          expect(find.text(l10n.diagRamMb(2048)), findsOneWidget);
          expect(find.text('armeabi-v7a, armeabi'), findsOneWidget);
          expect(find.text('g12a · Amlogic'), findsOneWidget);
          expect(find.text('android · SDK 30'), findsOneWidget);
          expect(find.text(l10n.settingsVersion('0.1.0+1')), findsOneWidget);
          expect(find.text(l10n.deviceModeTv), findsWidgets);
          expect(
            find.text('uiModeTv on · leanback on · fireTv off'),
            findsOneWidget,
          );
          expect(find.text('${l10n.diagDecoders} · audio/ac3'), findsOneWidget);
          // The first action has the focus.
          expect(focusedIn(const ValueKey('diagnostics-run')), isTrue);
          await disposeRig(tester, d.rig);
        },
      );
    });

    testWidgets('phone layout renders and scrolls to the log', (tester) async {
      final d = _DiagRig();
      d.rig.log.info('hello from the log');
      await _pumpDiagnostics(tester, d, tv: false);
      expect(find.byKey(const ValueKey('diagnostics')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('diagnostics-log-view')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('hello from the log'), findsOneWidget);
      await disposeRig(tester, d.rig);
    });

    testWidgets('the remote steps through sections down to the log', (
      tester,
    ) async {
      final d = _DiagRig();
      for (var i = 0; i < 50; i++) {
        d.rig.log.info('line $i');
      }
      await _pumpDiagnostics(tester, d);
      for (final key in [
        'diagnostics-engine',
        'diagnostics-device',
        'diagnostics-app',
        'diagnostics-settings',
        'diagnostics-sources',
      ]) {
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(focusedIn(ValueKey(key)), isTrue, reason: key);
      }
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn(const ValueKey('diagnostics-log-view')), isTrue);
      expect(find.textContaining('line 49'), findsOneWidget);
      // Up scrolls the log toward older lines before leaving it.
      final list = tester.widget<ListView>(
        find.descendant(
          of: find.byKey(const ValueKey('diagnostics-log-view')),
          matching: find.byType(ListView),
        ),
      );
      final scroll = list.controller!;
      expect(scroll.offset, 0);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(scroll.offset, greaterThan(0));
      expect(focusedIn(const ValueKey('diagnostics-log-view')), isTrue);
      await disposeRig(tester, d.rig);
    });
  });

  group('engine A/B test', () {
    forLocales((locale) {
      testWidgets('plays both test streams on both engines '
          '(${locale.languageCode})', (tester) async {
        final d = _DiagRig();
        d.rig.autoPlay();
        await _pumpDiagnostics(tester, d, locale: locale);
        final l10n = lookupAppLocalizations(locale);
        expect(
          find.descendant(
            of: _result(EngineKind.exo, 0),
            matching: find.text(l10n.diagnostics_notRun),
          ),
          findsOneWidget,
        );
        await press(tester, LogicalKeyboardKey.select);
        await settle(tester);
        for (final e in [EngineKind.exo, EngineKind.mpv]) {
          for (final s in [0, 1]) {
            expect(
              find.descendant(
                of: _result(e, s),
                matching: find.text(l10n.diagFirstFrameMs(0)),
              ),
              findsOneWidget,
            );
          }
        }
        expect(d.rig.openedUrls, [
          for (var i = 0; i < 2; i++)
            for (final s in kDiagnosticsTestStreams) s.url,
        ]);
        // One engine at a time, each closed before the next.
        expect(d.rig.engines.maxAlive, 1);
        expect(d.rig.engines.created.every((e) => e.disposed), isTrue);
        expect(d.rig.engines.created.map((e) => e.kind), [
          EngineKind.exo,
          EngineKind.exo,
          EngineKind.mpv,
          EngineKind.mpv,
        ]);
        expect(find.text(l10n.diagnostics_runAgain), findsOneWidget);
        await disposeRig(tester, d.rig);
      });
    });

    testWidgets('failures and timeouts are reported', (tester) async {
      final d = _DiagRig();
      d.rig.engines.onCreate = (e) {
        if (e.kind == EngineKind.exo) {
          e.onOpen = (e, _) => e.emitError('Source error');
        }
        // mpv never shows a frame: timeout.
      };
      await _pumpDiagnostics(tester, d, timeout: const Duration(seconds: 2));
      await press(tester, LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
      expect(
        find.descendant(
          of: _result(EngineKind.exo, 0),
          matching: find.text('Failed · Source error'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _result(EngineKind.mpv, 1),
          matching: find.text('Failed'),
        ),
        findsOneWidget,
      );
      expect(d.rig.engines.created.every((e) => e.disposed), isTrue);
      await disposeRig(tester, d.rig);
    });

    testWidgets('the ExoPlayer view type can be switched for the test', (
      tester,
    ) async {
      final d = _DiagRig();
      d.rig.autoPlay();
      await _pumpDiagnostics(tester, d);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedIn(const ValueKey('diagnostics-exo-view')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text('ExoPlayer view: Platform view'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.select);
      await settle(tester);
      expect(d.options.last.exoViewType, VideoViewType.platformView);
      await disposeRig(tester, d.rig);
    });

    testWidgets('desktop tests mpv only', (tester) async {
      final d = _DiagRig();
      d.rig.autoPlay();
      await _pumpDiagnostics(
        tester,
        d,
        caps: const DeviceCaps.desktop(platform: TargetPlatform.linux),
        platform: TargetPlatform.linux,
      );
      expect(find.byKey(const ValueKey('diagnostics-exo-view')), findsNothing);
      expect(_result(EngineKind.exo, 0), findsNothing);
      await press(tester, LogicalKeyboardKey.select);
      await settle(tester);
      expect(d.rig.engines.created.map((e) => e.kind), [
        EngineKind.mpv,
        EngineKind.mpv,
      ]);
      await disposeRig(tester, d.rig);
    });
  });

  group('report', () {
    testWidgets('«Copy report» copies a redacted report', (tester) async {
      final d = _DiagRig();
      d.rig.log
        ..addSecret(_secret)
        ..info('login with $_secret')
        ..info('GET http://127.0.0.1:9/get.php?username=bob&password=pw123')
        // A stream of an imported playlist: the account is in the path.
        ..info('Open http://127.0.0.1:9/alice7/Zx-Path-Secret/501.ts');
      await d.rig.db.sourcesDao.create(
        const SourceConfig(
          kind: SourceKind.xtream,
          url: 'http://127.0.0.1:9',
          name: 'Private name',
          username: 'bob',
          password: 'pw123',
        ),
      );
      await _pumpDiagnostics(tester, d);
      await settle(tester);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedIn(const ValueKey('diagnostics-copy')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      final report = d.rig.clipboard!;
      expect(report, startsWith('IPTV Player diagnostics'));
      expect(report, contains('App: 0.1.0+1'));
      expect(report, contains('Device: android SDK 30, Acme Box 1'));
      expect(report, contains('Sources: 1'));
      expect(report, contains('- xtream'));
      expect(report, contains('login with ***'));
      expect(report, isNot(contains(_secret)));
      expect(report, isNot(contains('pw123')));
      expect(report, isNot(contains('Private name')));
      expect(report, contains('Open http://127.0.0.1:9/***.ts'));
      expect(report, isNot(contains('alice7')));
      expect(report, isNot(contains('Zx-Path-Secret')));
      // Nor on screen.
      expect(find.textContaining('Zx-Path-Secret'), findsNothing);
      expect(find.text('Copied'), findsOneWidget);
      await disposeRig(tester, d.rig);
    });

    forLocales((locale) {
      testWidgets('«Show QR» shows the summary (${locale.languageCode})', (
        tester,
      ) async {
        final d = _DiagRig();
        await _pumpDiagnostics(tester, d, locale: locale);
        for (var i = 0; i < 3; i++) {
          await press(
            tester,
            locale == ar
                ? LogicalKeyboardKey.arrowLeft
                : LogicalKeyboardKey.arrowRight,
          );
        }
        expect(focusedIn(const ValueKey('diagnostics-qr')), isTrue);
        await press(tester, LogicalKeyboardKey.select);
        expect(find.byType(PrettyQrView), findsOneWidget);
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<TextButton>(),
          isNotNull,
        );
        await press(tester, LogicalKeyboardKey.select);
        expect(find.byType(PrettyQrView), findsNothing);
        expect(focusedIn(const ValueKey('diagnostics-qr')), isTrue);
        await disposeRig(tester, d.rig);
      });
    });

    test('the summary is capped and redacted', () {
      final long = DiagnosticsSnapshot(
        caps: DeviceCaps(model: 'M' * 3000),
        formFactor: FormFactor.tv,
        lite: false,
        settings: const AppSettings(),
      );
      expect(
        buildDiagnosticsSummary(long).length,
        lessThanOrEqualTo(kDiagnosticsQrMaxChars),
      );
      final snapshot = DiagnosticsSnapshot(
        caps: const DeviceCaps(hardware: 'k$_secret'),
        formFactor: FormFactor.tv,
        lite: true,
        settings: const AppSettings(),
        appVersion: '0.1.0+1',
        secrets: const [_secret],
      );
      final summary = buildDiagnosticsSummary(snapshot);
      expect(summary.length, lessThanOrEqualTo(kDiagnosticsQrMaxChars));
      expect(summary, startsWith('IPTV Player diagnostics'));
      expect(summary, contains('SoC: k***'));
      expect(summary, isNot(contains(_secret)));
      final report = buildDiagnosticsReport(snapshot);
      expect(report, contains('Sources: 0'));
      expect(report, isNot(contains(_secret)));
    });

    test('the chipset names Amlogic once', () {
      const box = DeviceCaps(hardware: 'g12a', socManufacturer: 'Amlogic');
      expect(chipsetParts(box), ['g12a', 'Amlogic']);
      expect(chipsetParts(const DeviceCaps(hardware: 'amlogic-sm1')), [
        'amlogic-sm1',
      ]);
      expect(
        chipsetParts(const DeviceCaps(hardware: 'mt8695', socManufacturer: '')),
        ['mt8695'],
      );
      expect(
        chipsetParts(const DeviceCaps(hardware: 'g12a', socManufacturer: 'X')),
        // Detected from the hardware name (g12a), named by no part.
        ['g12a', 'X', 'Amlogic'],
      );
      final summary = buildDiagnosticsSummary(
        const DiagnosticsSnapshot(
          caps: box,
          formFactor: FormFactor.tv,
          lite: false,
          settings: AppSettings(),
        ),
      );
      expect(summary, contains('SoC: g12a Amlogic, cores'));
      expect(summary, isNot(contains('(Amlogic)')));
    });
  });
}
