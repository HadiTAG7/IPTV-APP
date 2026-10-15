// The player's Guide button inside the real home shells.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/app.dart';
import 'package:iptv_player/app/home_shell.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/app/shell_phone.dart';
import 'package:iptv_player/app/shell_tv.dart';
import 'package:iptv_player/features/diagnostics/providers.dart';
import 'package:iptv_player/player/player_providers.dart';
import 'package:iptv_player/player/ui/play_request.dart';
import 'package:iptv_player/player/ui/player_route.dart';
import 'package:iptv_player/player/ui/player_screen.dart';
import 'package:iptv_player/tv/dpad_shortcuts.dart';
import 'package:iptv_player/tv/key_repeat.dart';
import 'package:iptv_player/tv/tv_focusable.dart';

import 'support/player_harness.dart';

/// A Live tab whose only item opens the player for [request].
class _LivePage extends StatelessWidget {
  const _LivePage(this.request);

  final PlayRequest request;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.topStart,
    child: TvFocusable(
      key: const ValueKey('open-player'),
      onSelect: () => openPlayer(context, request),
      child: const SizedBox(width: 160, height: 48, child: Text('Play')),
    ),
  );
}

Future<void> _pumpShell(
  WidgetTester tester,
  PlayerRig rig,
  PlayRequest request, {
  required bool tv,
  Locale locale = en,
}) async {
  final size = tv ? const Size(960, 540) : const Size(390, 800);
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  addTearDown(() => applyFocusHighlightStrategy(tv: false));
  KeyRepeatThrottle.instance = KeyRepeatThrottle(clock: rig.clock);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(rig.db),
        deviceCapsProvider.overrideWithValue(tv ? tvCaps : phoneCaps),
        initialSettingsProvider.overrideWithValue(
          AppSettings(
            locale: locale == ar ? AppLocaleSetting.ar : AppLocaleSetting.en,
          ),
        ),
        ringLogProvider.overrideWithValue(rig.log),
        clockProvider.overrideWithValue(rig.clock),
        autoSyncOnStartProvider.overrideWithValue(false),
        engineFactoryBuilderProvider.overrideWithValue((_) => rig.engines.call),
        playerWakelockProvider.overrideWithValue(rig.wakelock.add),
        appVersionProvider.overrideWith((ref) async => '0.1.0+1'),
        homePageBuilderProvider.overrideWithValue(
          (tab) => tab == HomeTab.live
              ? _LivePage(request)
              : Center(child: Text('page:${tab.name}')),
        ),
      ],
      child: const IptvApp(),
    ),
  );
  await settle(tester);
}

void main() {
  forLocales((locale) {
    testWidgets('TV: Guide closes the player and shows the Guide tab '
        '(${locale.languageCode})', (tester) async {
      final rig = PlayerRig()..autoPlay();
      final id = await seedLive(rig);
      await _pumpShell(tester, rig, liveRequest(id), tv: true, locale: locale);

      // Rail -> page -> open the player.
      await press(
        tester,
        locale == ar
            ? LogicalKeyboardKey.arrowLeft
            : LogicalKeyboardKey.arrowRight,
      );
      expect(focusedIn(const ValueKey('open-player')), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      await settle(tester);
      expect(find.byType(PlayerScreen), findsOneWidget);

      await press(tester, LogicalKeyboardKey.select);
      expect(find.byKey(const ValueKey('player-osd-guide')), findsOneWidget);
      final next = locale == ar
          ? LogicalKeyboardKey.arrowLeft
          : LogicalKeyboardKey.arrowRight;
      for (var i = 0; i < 8; i++) {
        if (focusedIn(const ValueKey('player-osd-guide'))) break;
        await press(tester, next);
      }
      await press(tester, LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
      expect(rig.engine.calls, contains('stop'));
      final shell = tester.state<TvShellState>(find.byType(TvShell));
      expect(shell.current, HomeTab.guide);
      expect(find.text('page:guide'), findsOneWidget);
      await disposeRig(tester, rig);
    });
  });

  testWidgets('phone: the Guide key shows the Guide tab', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig);
    await _pumpShell(tester, rig, liveRequest(id), tv: false);
    await tester.tap(find.byKey(const ValueKey('open-player')));
    await settle(tester);
    expect(find.byType(PlayerScreen), findsOneWidget);
    await tester.sendKeyEvent(
      LogicalKeyboardKey.guide,
      physicalKey: PhysicalKeyboardKey.f1,
    );
    await tester.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsNothing);
    final shell = tester.state<PhoneShellState>(find.byType(PhoneShell));
    expect(shell.current, HomeTab.guide);
    await disposeRig(tester, rig);
  });
}
