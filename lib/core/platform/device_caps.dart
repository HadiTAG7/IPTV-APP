import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Hardware and TV signals reported by the Android side over
/// `MethodChannel('app/device')`, method `getCaps`.
///
/// Map keys (the channel contract): `uiModeTv`, `leanback`, `fireTv`, `touch`,
/// `totalRamMb`, `isLowRamDevice`, `cpuCount`, `hardware`, `socManufacturer`,
/// `supportedAbis`, `decoders`, `sdkInt`, `model`, `manufacturer`.
/// [toMap] also writes `platform`, which [fromMap] reads when present.
@immutable
class DeviceCaps {
  const DeviceCaps({
    this.platform = TargetPlatform.android,
    this.uiModeTv = false,
    this.leanback = false,
    this.fireTv = false,
    this.touch = true,
    this.totalRamMb = 0,
    this.isLowRamDevice = false,
    this.cpuCount = 0,
    this.hardware = '',
    this.socManufacturer,
    this.supportedAbis = const [],
    this.decoders = const {},
    this.sdkInt = 0,
    this.model = '',
    this.manufacturer = '',
  });

  /// Defaults for platforms without the device channel (Windows, Linux...).
  const DeviceCaps.desktop({this.platform = TargetPlatform.windows})
    : uiModeTv = false,
      leanback = false,
      fireTv = false,
      touch = false,
      totalRamMb = 0,
      isLowRamDevice = false,
      cpuCount = 0,
      hardware = '',
      socManufacturer = null,
      supportedAbis = const [],
      decoders = const {},
      sdkInt = 0,
      model = '',
      manufacturer = '';

  /// Builds caps from the channel map, tolerating missing or mistyped keys.
  factory DeviceCaps.fromMap(Map<Object?, Object?> map) {
    final platformName = map['platform'];
    final platform = TargetPlatform.values.firstWhere(
      (p) => p.name == platformName,
      orElse: () => TargetPlatform.android,
    );
    return DeviceCaps(
      platform: platform,
      uiModeTv: _bool(map['uiModeTv']),
      leanback: _bool(map['leanback']),
      fireTv: _bool(map['fireTv']),
      touch: _bool(map['touch'], fallback: true),
      totalRamMb: _int(map['totalRamMb']),
      isLowRamDevice: _bool(map['isLowRamDevice']),
      cpuCount: _int(map['cpuCount']),
      hardware: _string(map['hardware']) ?? '',
      socManufacturer: _string(map['socManufacturer']),
      supportedAbis: _stringList(map['supportedAbis']),
      decoders: _boolMap(map['decoders']),
      sdkInt: _int(map['sdkInt']),
      model: _string(map['model']) ?? '',
      manufacturer: _string(map['manufacturer']) ?? '',
    );
  }

  static const channel = MethodChannel('app/device');

  /// Decoder keys reported in [decoders].
  static const decoderKeys = <String>[
    'audio/ac3',
    'audio/eac3',
    'audio/vnd.dts',
    'audio/mpeg-L2',
    'video/hevc',
    'video/mpeg2',
  ];

  /// Reads caps from the platform. Android asks the device channel and falls
  /// back to plain phone defaults if it fails; other platforms (and web) get
  /// [DeviceCaps.desktop].
  static Future<DeviceCaps> load({
    TargetPlatform? platform,
    MethodChannel methodChannel = channel,
  }) async {
    final p = platform ?? defaultTargetPlatform;
    if (kIsWeb || p != TargetPlatform.android) {
      return DeviceCaps.desktop(platform: p);
    }
    try {
      final map = await methodChannel.invokeMapMethod<Object?, Object?>(
        'getCaps',
      );
      if (map == null) return const DeviceCaps();
      return DeviceCaps.fromMap(map);
    } on PlatformException {
      return const DeviceCaps();
    } on MissingPluginException {
      return const DeviceCaps();
    }
  }

  final TargetPlatform platform;
  final bool uiModeTv;
  final bool leanback;
  final bool fireTv;
  final bool touch;

  /// Total RAM in MB; 0 means unknown.
  final int totalRamMb;
  final bool isLowRamDevice;

  /// Number of CPU cores; 0 means unknown.
  final int cpuCount;

  /// `Build.HARDWARE`.
  final String hardware;

  /// `Build.SOC_MANUFACTURER` (API 31+).
  final String? socManufacturer;
  final List<String> supportedAbis;

  /// MIME type -> decoder available, see [decoderKeys].
  final Map<String, bool> decoders;
  final int sdkInt;
  final String model;
  final String manufacturer;

  bool get isAndroid => platform == TargetPlatform.android;

  bool get isDesktop =>
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux ||
      platform == TargetPlatform.macOS;

  /// Android TV, Google TV, Fire TV or any Android device without touch.
  bool get isTv => isAndroid && (uiModeTv || leanback || fireTv || !touch);

  static final _amlogic = RegExp(
    'amlogic|meson|g12|sm1|sc2|s905|s912|s922',
    caseSensitive: false,
  );

  /// Amlogic SoC (common in TV boxes); affects the VOD engine default.
  bool get isAmlogic =>
      _amlogic.hasMatch(hardware) ||
      (socManufacturer != null && _amlogic.hasMatch(socManufacturer!));

  /// Low-memory device: Lite mode is on by default.
  bool get lite => (totalRamMb > 0 && totalRamMb <= 2048) || isLowRamDevice;

  /// Whether a decoder for [mime] was reported.
  bool hasDecoder(String mime) => decoders[mime] ?? false;

  Map<String, Object?> toMap() => {
    'platform': platform.name,
    'uiModeTv': uiModeTv,
    'leanback': leanback,
    'fireTv': fireTv,
    'touch': touch,
    'totalRamMb': totalRamMb,
    'isLowRamDevice': isLowRamDevice,
    'cpuCount': cpuCount,
    'hardware': hardware,
    'socManufacturer': socManufacturer,
    'supportedAbis': List<String>.of(supportedAbis),
    'decoders': Map<String, bool>.of(decoders),
    'sdkInt': sdkInt,
    'model': model,
    'manufacturer': manufacturer,
  };

  @override
  bool operator ==(Object other) =>
      other is DeviceCaps &&
      other.platform == platform &&
      other.uiModeTv == uiModeTv &&
      other.leanback == leanback &&
      other.fireTv == fireTv &&
      other.touch == touch &&
      other.totalRamMb == totalRamMb &&
      other.isLowRamDevice == isLowRamDevice &&
      other.cpuCount == cpuCount &&
      other.hardware == hardware &&
      other.socManufacturer == socManufacturer &&
      listEquals(other.supportedAbis, supportedAbis) &&
      mapEquals(other.decoders, decoders) &&
      other.sdkInt == sdkInt &&
      other.model == model &&
      other.manufacturer == manufacturer;

  @override
  int get hashCode => Object.hash(
    platform,
    uiModeTv,
    leanback,
    fireTv,
    touch,
    totalRamMb,
    isLowRamDevice,
    cpuCount,
    hardware,
    socManufacturer,
    Object.hashAll(supportedAbis),
    sdkInt,
    model,
    manufacturer,
  );

  @override
  String toString() => 'DeviceCaps(${toMap()})';
}

bool _bool(Object? v, {bool fallback = false}) => switch (v) {
  final bool b => b,
  final num n => n != 0,
  final String s => s == 'true' || s == '1',
  _ => fallback,
};

int _int(Object? v) => switch (v) {
  final int i => i,
  final num n => n.toInt(),
  final String s => int.tryParse(s.trim()) ?? 0,
  _ => 0,
};

String? _string(Object? v) => switch (v) {
  null => null,
  final String s => s,
  _ => '$v',
};

List<String> _stringList(Object? v) => switch (v) {
  final List<Object?> l => [
    for (final e in l)
      if (e != null) '$e',
  ],
  _ => const [],
};

Map<String, bool> _boolMap(Object? v) => switch (v) {
  final Map<Object?, Object?> m => {
    for (final e in m.entries)
      if (e.key != null) '${e.key}': _bool(e.value),
  },
  _ => const {},
};
