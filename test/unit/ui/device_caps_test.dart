import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/platform/device_caps.dart';

/// Shape of the Android `getCaps` reply as it arrives over the channel.
Map<Object?, Object?> _channelMap({
  bool uiModeTv = true,
  bool leanback = true,
  bool fireTv = false,
  bool touch = false,
  int totalRamMb = 1843,
  bool isLowRamDevice = false,
  String hardware = 'amlogic',
  String? socManufacturer = 'Amlogic',
}) => <Object?, Object?>{
  'uiModeTv': uiModeTv,
  'leanback': leanback,
  'fireTv': fireTv,
  'touch': touch,
  'totalRamMb': totalRamMb,
  'isLowRamDevice': isLowRamDevice,
  'cpuCount': 4,
  'hardware': hardware,
  'socManufacturer': socManufacturer,
  'supportedAbis': <Object?>['armeabi-v7a', 'armeabi'],
  'decoders': <Object?, Object?>{
    'audio/ac3': false,
    'audio/eac3': false,
    'audio/vnd.dts': false,
    'audio/mpeg-L2': true,
    'video/hevc': true,
    'video/mpeg2': true,
  },
  'sdkInt': 30,
  'model': 'Example Box 4K',
  'manufacturer': 'ExampleCorp',
};

const _contractKeys = {
  'uiModeTv',
  'leanback',
  'fireTv',
  'touch',
  'totalRamMb',
  'isLowRamDevice',
  'cpuCount',
  'hardware',
  'socManufacturer',
  'supportedAbis',
  'decoders',
  'sdkInt',
  'model',
  'manufacturer',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fromMap', () {
    test('reads every contract key', () {
      final caps = DeviceCaps.fromMap(_channelMap());
      expect(caps.platform, TargetPlatform.android);
      expect(caps.uiModeTv, isTrue);
      expect(caps.leanback, isTrue);
      expect(caps.fireTv, isFalse);
      expect(caps.touch, isFalse);
      expect(caps.totalRamMb, 1843);
      expect(caps.isLowRamDevice, isFalse);
      expect(caps.cpuCount, 4);
      expect(caps.hardware, 'amlogic');
      expect(caps.socManufacturer, 'Amlogic');
      expect(caps.supportedAbis, ['armeabi-v7a', 'armeabi']);
      expect(caps.decoders.keys, unorderedEquals(DeviceCaps.decoderKeys));
      expect(caps.hasDecoder('audio/ac3'), isFalse);
      expect(caps.hasDecoder('video/hevc'), isTrue);
      expect(caps.hasDecoder('video/av1'), isFalse);
      expect(caps.sdkInt, 30);
      expect(caps.model, 'Example Box 4K');
      expect(caps.manufacturer, 'ExampleCorp');
    });

    test('tolerates missing keys and loose types', () {
      final caps = DeviceCaps.fromMap(<Object?, Object?>{
        'uiModeTv': 1,
        'touch': 'false',
        'totalRamMb': '2048',
        'cpuCount': 8.0,
        'hardware': null,
        'supportedAbis': <Object?>['arm64-v8a', null, 7],
        'decoders': <Object?, Object?>{'audio/ac3': 1, null: true},
        'sdkInt': 'x',
      });
      expect(caps.uiModeTv, isTrue);
      expect(caps.leanback, isFalse);
      expect(caps.touch, isFalse);
      expect(caps.totalRamMb, 2048);
      expect(caps.cpuCount, 8);
      expect(caps.hardware, '');
      expect(caps.socManufacturer, isNull);
      expect(caps.supportedAbis, ['arm64-v8a', '7']);
      expect(caps.decoders, {'audio/ac3': true});
      expect(caps.sdkInt, 0);
      expect(caps.model, '');
    });

    test('an empty map is a plain touch phone', () {
      final caps = DeviceCaps.fromMap(const {});
      expect(caps, const DeviceCaps());
      expect(caps.touch, isTrue);
      expect(caps.isTv, isFalse);
      expect(caps.lite, isFalse);
    });

    test('toMap round-trips and keeps the channel contract keys', () {
      final caps = DeviceCaps.fromMap(_channelMap());
      final map = caps.toMap();
      expect(map.keys.toSet().difference({'platform'}), _contractKeys);
      expect(DeviceCaps.fromMap(map), caps);
      expect(DeviceCaps.fromMap(map).hashCode, caps.hashCode);

      const desktop = DeviceCaps.desktop(platform: TargetPlatform.linux);
      expect(DeviceCaps.fromMap(desktop.toMap()), desktop);
    });
  });

  group('isTv', () {
    test('any TV signal on Android', () {
      expect(const DeviceCaps(uiModeTv: true).isTv, isTrue);
      expect(const DeviceCaps(leanback: true).isTv, isTrue);
      expect(const DeviceCaps(fireTv: true).isTv, isTrue);
      expect(const DeviceCaps(touch: false).isTv, isTrue);
      expect(const DeviceCaps().isTv, isFalse);
    });

    test('never on desktop', () {
      const caps = DeviceCaps.desktop();
      expect(caps.touch, isFalse);
      expect(caps.uiModeTv, isFalse);
      expect(caps.isTv, isFalse);
      expect(caps.isDesktop, isTrue);
    });
  });

  group('isAmlogic', () {
    const amlogic = [
      'amlogic',
      'AMLOGIC',
      'Meson',
      'g12a',
      'G12B',
      'sm1',
      'sc2',
      's905x4',
      'S905W',
      's912',
      's922x',
    ];
    for (final hw in amlogic) {
      test('hardware "$hw"', () {
        expect(DeviceCaps(hardware: hw).isAmlogic, isTrue);
      });
    }

    test('SoC manufacturer alone is enough', () {
      expect(
        const DeviceCaps(
          hardware: 'qcom',
          socManufacturer: 'Amlogic',
        ).isAmlogic,
        isTrue,
      );
    });

    for (final hw in ['qcom', 'mt8696', 'rk3328', 'exynos', '']) {
      test('not "$hw"', () {
        expect(
          DeviceCaps(hardware: hw, socManufacturer: 'Mediatek').isAmlogic,
          isFalse,
        );
      });
    }
  });

  group('lite', () {
    test('2 GB or less', () {
      expect(const DeviceCaps(totalRamMb: 1024).lite, isTrue);
      expect(const DeviceCaps(totalRamMb: 2048).lite, isTrue);
      expect(const DeviceCaps(totalRamMb: 2049).lite, isFalse);
      expect(const DeviceCaps(totalRamMb: 4096).lite, isFalse);
    });

    test('low-RAM flag wins', () {
      expect(
        const DeviceCaps(totalRamMb: 8192, isLowRamDevice: true).lite,
        isTrue,
      );
    });

    test('unknown RAM is not lite', () {
      expect(const DeviceCaps().lite, isFalse);
      expect(const DeviceCaps.desktop().lite, isFalse);
    });
  });

  group('load', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(
      () => messenger.setMockMethodCallHandler(DeviceCaps.channel, null),
    );

    test('asks app/device getCaps on Android', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(DeviceCaps.channel, (call) async {
        seen = call;
        return _channelMap();
      });
      final caps = await DeviceCaps.load(platform: TargetPlatform.android);
      expect(DeviceCaps.channel.name, 'app/device');
      expect(seen?.method, 'getCaps');
      expect(caps.isTv, isTrue);
      expect(caps.isAmlogic, isTrue);
      expect(caps.lite, isTrue);
    });

    test('falls back to phone defaults when the channel fails', () async {
      messenger.setMockMethodCallHandler(
        DeviceCaps.channel,
        (call) async => throw PlatformException(code: 'boom'),
      );
      expect(
        await DeviceCaps.load(platform: TargetPlatform.android),
        const DeviceCaps(),
      );

      messenger.setMockMethodCallHandler(DeviceCaps.channel, null);
      expect(
        await DeviceCaps.load(platform: TargetPlatform.android),
        const DeviceCaps(),
      );

      messenger.setMockMethodCallHandler(
        DeviceCaps.channel,
        (call) async => null,
      );
      expect(
        await DeviceCaps.load(platform: TargetPlatform.android),
        const DeviceCaps(),
      );
    });

    test('desktop defaults elsewhere without touching the channel', () async {
      var called = false;
      messenger.setMockMethodCallHandler(DeviceCaps.channel, (call) async {
        called = true;
        return null;
      });
      for (final p in [TargetPlatform.windows, TargetPlatform.linux]) {
        final caps = await DeviceCaps.load(platform: p);
        expect(caps.platform, p);
        expect(caps.touch, isFalse);
        expect(caps.uiModeTv, isFalse);
        expect(caps.isTv, isFalse);
      }
      expect(called, isFalse);
    });
  });
}
