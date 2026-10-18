import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/core/log/ring_log.dart';
import 'package:iptv_player/core/platform/window_fullscreen.dart';
import 'package:iptv_player/player/player_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(windowsWindowChannel, null),
  );

  test('Windows uses the runner channel', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(windowsWindowChannel, (call) async {
      calls.add(call.method);
      return null;
    });
    final window = WindowFullscreen.windows();
    await window.enter();
    await window.exit();
    expect(calls, ['enterFullscreen', 'exitFullscreen']);
  });

  test('failures are reported, never thrown', () async {
    messenger.setMockMethodCallHandler(windowsWindowChannel, (call) async {
      throw PlatformException(code: 'boom');
    });
    final errors = <String>[];
    final window = WindowFullscreen.windows(onError: errors.add);
    await window.enter();
    // No runner handler at all (an older runner): still no throw.
    messenger.setMockMethodCallHandler(windowsWindowChannel, null);
    await window.exit();
    expect(errors, hasLength(2));
    expect(errors.first, contains('enterFullscreen'));
    expect(errors.last, contains('exitFullscreen'));
  });

  test('the player window per platform', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(windowsWindowChannel, (call) async {
      calls.add(call.method);
      return null;
    });
    WindowFullscreen? windowFor(TargetPlatform platform) {
      final container = ProviderContainer(
        overrides: [
          targetPlatformProvider.overrideWithValue(platform),
          ringLogProvider.overrideWithValue(RingLog()),
        ],
      );
      addTearDown(container.dispose);
      return container.read(playerWindowProvider);
    }

    expect(windowFor(TargetPlatform.android), isNull);
    expect(windowFor(TargetPlatform.linux), isNotNull);
    await windowFor(TargetPlatform.windows)!.enter();
    expect(calls, ['enterFullscreen']);
  });
}
