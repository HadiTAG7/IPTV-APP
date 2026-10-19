// On Linux the runner has no "iptv_player/window" channel: the viewer does
// not offer "Keep on top" and "Small window" there (they would do nothing);
// fullscreen and Close stay. Synthetic data only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/platform/window_controls.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';

import '../support/fake_engine.dart';
import 'support/viewer_harness.dart';

void main() {
  testWidgets('Linux: no pin or small window, fullscreen and Close stay', (
    tester,
  ) async {
    final channel = FakeViewerChannel();
    final engines = FakeEngineFactory()
      ..onCreate = (e) => e.onOpen = (e, _) => e.emitFirstFrame();
    final errors = <String>[];
    // The GTK runner registers no window channel: nobody answers.
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'iptv_player/window',
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'iptv_player/window',
        null,
      ),
    );
    await pumpViewer(
      tester,
      channel: channel,
      engines: engines,
      // As runViewer builds it on Linux.
      window: WindowControls.native(
        platform: TargetPlatform.linux,
        onError: errors.add,
      ),
      platform: TargetPlatform.linux,
    );
    channel.deliver(
      const PlayMessage(url: 'http://127.0.0.1:9/live/501.ts', title: 'News'),
    );
    await settleViewer(tester);
    await hoverViewer(tester);

    expect(find.byKey(const ValueKey('viewer-osd')), findsOneWidget);
    expect(find.byKey(const ValueKey('viewer-pin')), findsNothing);
    expect(find.byKey(const ValueKey('viewer-compact')), findsNothing);
    expect(find.byKey(const ValueKey('viewer-fullscreen')), findsOneWidget);
    expect(find.byKey(const ValueKey('viewer-close')), findsOneWidget);
    expect(errors.where((e) => e.contains('Compact')), isEmpty);
    expect(errors.where((e) => e.contains('AlwaysOnTop')), isEmpty);
    await unmountViewer(tester);
  });

  test('only the Windows runner has pin and small window', () {
    expect(
      WindowControls.native(platform: TargetPlatform.windows)
          .supportsCompactAndPin,
      isTrue,
    );
    expect(
      WindowControls.native(platform: TargetPlatform.linux)
          .supportsCompactAndPin,
      isFalse,
    );
  });
}
