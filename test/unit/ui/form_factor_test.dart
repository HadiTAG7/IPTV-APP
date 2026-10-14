import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/form_factor.dart';
import 'package:iptv_player/core/platform/device_caps.dart';
import 'package:iptv_player/theme/tokens.dart';

void main() {
  const tvCaps = DeviceCaps(uiModeTv: true, leanback: true, touch: false);
  const fireCaps = DeviceCaps(fireTv: true, touch: false);
  const phoneCaps = DeviceCaps();
  const desktopCaps = DeviceCaps.desktop();
  const tvSize = Size(960, 540);
  const phoneSize = Size(400, 860);

  group('resolveFormFactor', () {
    const android = TargetPlatform.android;
    const windows = TargetPlatform.windows;
    const linux = TargetPlatform.linux;
    const auto = FormFactorOverride.auto;
    const tv = FormFactorOverride.tv;
    const phone = FormFactorOverride.phone;

    // (label, caps, override, platform) -> expected
    const matrix = [
      ('tv box', tvCaps, auto, android, FormFactor.tv),
      ('fire tv', fireCaps, auto, android, FormFactor.tv),
      ('tv box forced phone', tvCaps, phone, android, FormFactor.phone),
      ('tv box forced tv', tvCaps, tv, android, FormFactor.tv),
      ('phone', phoneCaps, auto, android, FormFactor.phone),
      ('phone forced tv', phoneCaps, tv, android, FormFactor.tv),
      ('phone forced phone', phoneCaps, phone, android, FormFactor.phone),
      ('ios', phoneCaps, auto, TargetPlatform.iOS, FormFactor.phone),
      ('windows', desktopCaps, auto, windows, FormFactor.desktop),
      ('windows forced phone', desktopCaps, phone, windows, FormFactor.desktop),
      ('windows forced tv', desktopCaps, tv, windows, FormFactor.tv),
      ('linux', desktopCaps, auto, linux, FormFactor.desktop),
      ('macos', desktopCaps, auto, TargetPlatform.macOS, FormFactor.desktop),
      ('linux forced tv', desktopCaps, tv, linux, FormFactor.tv),
      // TV-looking caps on a desktop OS still give the desktop shell.
      ('tv caps on windows', tvCaps, auto, windows, FormFactor.desktop),
    ];

    for (final (label, caps, override, platform, expected) in matrix) {
      test('$label -> ${expected.name}', () {
        for (final size in [tvSize, phoneSize]) {
          expect(resolveFormFactor(caps, override, size, platform), expected);
        }
      });
    }
  });

  group('useLargeLayout', () {
    test('TV and desktop always', () {
      expect(useLargeLayout(FormFactor.tv, phoneSize), isTrue);
      expect(useLargeLayout(FormFactor.desktop, phoneSize), isTrue);
    });

    test('phones only when landscape and at least 900 wide', () {
      expect(useLargeLayout(FormFactor.phone, phoneSize), isFalse);
      expect(useLargeLayout(FormFactor.phone, const Size(860, 400)), isFalse);
      expect(useLargeLayout(FormFactor.phone, const Size(900, 600)), isTrue);
      expect(useLargeLayout(FormFactor.phone, const Size(1280, 800)), isTrue);
      expect(useLargeLayout(FormFactor.phone, const Size(800, 1280)), isFalse);
      expect(useLargeLayout(FormFactor.phone, const Size(1000, 1000)), isFalse);
    });
  });

  test('overscan padding only on TV', () {
    expect(
      overscanPadding(FormFactor.tv),
      const EdgeInsets.symmetric(horizontal: 48, vertical: 27),
    );
    expect(overscanPadding(FormFactor.phone), EdgeInsets.zero);
    expect(overscanPadding(FormFactor.desktop), EdgeInsets.zero);
  });

  group('tokens', () {
    test('TV scale factor is logical width / 960', () {
      expect(tvScaleFactor(960), 1.0);
      expect(tvScaleFactor(1920), 2.0);
      expect(tvScaleFactor(1280), closeTo(1.3333, 0.0001));
      expect(tvScaleFactor(0), 1.0);
      expect(tvScaleFactor(-5), 1.0);
    });

    test('focus tokens', () {
      expect(FocusTokens.borderWidth, 3);
      expect(FocusTokens.scale, 1.06);
      expect(TvLayout.overscan, overscanPadding(FormFactor.tv));
    });
  });
}
