import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/providers.dart';
import 'package:iptv_player/app/root_gate.dart';
import 'package:iptv_player/core/platform/device_caps.dart';
import 'package:iptv_player/theme/tokens.dart';

import 'app_harness.dart';

void main() {
  const mib = 1 << 20;

  void restoreImageCache() {
    PaintingBinding.instance.imageCache
      ..maximumSizeBytes = 100 * mib
      ..maximumSize = 1000;
  }

  test('image cache budget: 32 MB in Lite mode, 48 MB otherwise', () {
    addTearDown(restoreImageCache);
    final cache = ImageCache();
    applyImageCacheBudget(cache, lite: true);
    expect(cache.maximumSizeBytes, 32 * mib);
    expect(cache.maximumSize, 250);
    applyImageCacheBudget(cache, lite: false);
    expect(cache.maximumSizeBytes, 48 * mib);
    expect(cache.maximumSize, 500);
  });

  testWidgets('Lite mode caps the image cache and turns animations off, '
      'and follows the setting', (tester) async {
    addTearDown(restoreImageCache);
    final db = openAppTestDb();
    await addTestSource(db, lastSyncAt: DateTime.now());
    await pumpApp(
      tester,
      db: db,
      caps: const DeviceCaps(
        uiModeTv: true,
        leanback: true,
        isLowRamDevice: true,
      ),
      fakePages: true,
    );
    final cache = PaintingBinding.instance.imageCache;
    final gate = find.byType(RootGate);
    expect(cache.maximumSizeBytes, 32 * mib);
    expect(cache.maximumSize, 250);
    expect(MediaQuery.disableAnimationsOf(tester.element(gate)), isTrue);
    expect(FocusTokens.animationOf(tester.element(gate)), Duration.zero);
    final scales = find.byType(AnimatedScale);
    expect(scales, findsWidgets);
    for (final s in tester.widgetList<AnimatedScale>(scales)) {
      expect(s.duration, Duration.zero);
    }

    final container = ProviderScope.containerOf(tester.element(gate));
    await container.read(settingsProvider.notifier).setLite(LiteSetting.off);
    await settle(tester);
    expect(cache.maximumSizeBytes, 48 * mib);
    expect(cache.maximumSize, 500);
    expect(MediaQuery.disableAnimationsOf(tester.element(gate)), isFalse);
    for (final s in tester.widgetList<AnimatedScale>(scales)) {
      expect(s.duration, FocusTokens.animation);
    }
    await disposeApp(tester, db);
  });
}
