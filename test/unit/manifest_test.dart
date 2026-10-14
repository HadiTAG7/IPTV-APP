import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _androidNs = 'http://schemas.android.com/apk/res/android';
const _main = 'android/app/src/main';
const _res = '$_main/res';

const _densities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

XmlElement _root(String path) =>
    XmlDocument.parse(File(path).readAsStringSync()).rootElement;

String? _attr(XmlElement element, String name) =>
    element.getAttribute(name, namespaceUri: _androidNs);

Set<String?> _names(XmlElement parent, String tag) =>
    parent.findElements(tag).map((e) => _attr(e, 'name')).toSet();

/// Width and height from a PNG's IHDR chunk.
(int, int) _pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  expect(bytes.sublist(0, 8), [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ], reason: '$path is not a PNG');
  final data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
}

String _string(String valuesDir, String name) =>
    _root('$_res/$valuesDir/strings.xml')
        .findElements('string')
        .singleWhere((e) => e.getAttribute('name') == name)
        .innerText;

void main() {
  final manifest = _root('$_main/AndroidManifest.xml');
  final application = manifest.getElement('application')!;
  final activity = application
      .findElements('activity')
      .singleWhere((e) => _attr(e, 'name') == '.MainActivity');

  group('AndroidManifest', () {
    test('requests network access in the main manifest', () {
      expect(
        _names(manifest, 'uses-permission'),
        containsAll([
          'android.permission.INTERNET',
          'android.permission.ACCESS_NETWORK_STATE',
        ]),
      );
    });

    test('never requests camera, microphone or location', () {
      final permissions = _names(manifest, 'uses-permission');
      for (final forbidden in [
        'android.permission.CAMERA',
        'android.permission.RECORD_AUDIO',
        'android.permission.ACCESS_FINE_LOCATION',
        'android.permission.ACCESS_COARSE_LOCATION',
        'android.permission.ACCESS_BACKGROUND_LOCATION',
      ]) {
        expect(permissions, isNot(contains(forbidden)));
      }
    });

    test('touchscreen, faketouch and leanback are optional', () {
      final features = {
        for (final f in manifest.findElements('uses-feature'))
          _attr(f, 'name'): _attr(f, 'required'),
      };
      expect(features, {
        'android.hardware.touchscreen': 'false',
        'android.hardware.faketouch': 'false',
        'android.software.leanback': 'false',
      });
    });

    test('application is TV-ready', () {
      expect(_attr(application, 'label'), '@string/app_name');
      expect(_attr(application, 'icon'), '@mipmap/ic_launcher');
      expect(_attr(application, 'banner'), '@drawable/banner');
      expect(_attr(application, 'usesCleartextTraffic'), 'true');
      expect(_attr(application, 'allowBackup'), 'false');
      expect(_attr(application, 'enableOnBackInvokedCallback'), 'true');
    });

    test('MainActivity appears in the phone and TV launchers', () {
      expect(_attr(activity, 'exported'), 'true');
      final launcher = activity
          .findElements('intent-filter')
          .where(
            (f) => _names(f, 'action').contains('android.intent.action.MAIN'),
          );
      expect(launcher, hasLength(1));
      expect(
        _names(launcher.single, 'category'),
        containsAll([
          'android.intent.category.LAUNCHER',
          'android.intent.category.LEANBACK_LAUNCHER',
        ]),
      );
    });

    test(
      'configChanges keeps the template list plus navigation|touchscreen',
      () {
        final changes = _attr(activity, 'configChanges')!.split('|').toSet();
        expect(
          changes,
          containsAll([
            'orientation',
            'keyboardHidden',
            'keyboard',
            'screenSize',
            'smallestScreenSize',
            'locale',
            'layoutDirection',
            'fontScale',
            'screenLayout',
            'density',
            'uiMode',
            'navigation',
            'touchscreen',
          ]),
        );
      },
    );

    test('keeps the Flutter template entries', () {
      expect(_attr(activity, 'launchMode'), 'singleTop');
      expect(_attr(activity, 'taskAffinity'), '');
      expect(_attr(activity, 'theme'), '@style/LaunchTheme');
      expect(
        activity.findElements('meta-data').map((m) => _attr(m, 'name')),
        contains('io.flutter.embedding.android.NormalTheme'),
      );
      final embedding = application
          .findElements('meta-data')
          .singleWhere((m) => _attr(m, 'name') == 'flutterEmbedding');
      expect(_attr(embedding, 'value'), '2');
      expect(
        manifest
            .getElement('queries')!
            .findAllElements('action')
            .map((a) => _attr(a, 'name')),
        contains('android.intent.action.PROCESS_TEXT'),
      );
    });

    test('nothing locks the screen orientation', () {
      final locked = manifest.descendantElements.where(
        (e) => _attr(e, 'screenOrientation') != null,
      );
      expect(locked, isEmpty);
    });
  });

  group('Resources', () {
    test('app name in English and Arabic', () {
      expect(_string('values', 'app_name'), 'IPTV Player');
      expect(_string('values-ar', 'app_name'), 'مشغّل IPTV');
    });

    test('TV banners are exactly 320x180', () {
      expect(_pngSize('$_res/drawable-xhdpi/banner.png'), (320, 180));
      expect(_pngSize('$_res/drawable-ar-xhdpi/banner.png'), (320, 180));
    });

    test('legacy launcher icons use the standard sizes', () {
      _densities.forEach((density, scale) {
        final px = (48 * scale).round();
        expect(_pngSize('$_res/mipmap-$density/ic_launcher.png'), (
          px,
          px,
        ), reason: density);
      });
    });

    test('adaptive icon layers resolve', () {
      final icon = _root('$_res/mipmap-anydpi-v26/ic_launcher.xml');
      expect(
        _attr(icon.getElement('background')!, 'drawable'),
        '@color/ic_launcher_background',
      );
      expect(
        _attr(icon.getElement('foreground')!, 'drawable'),
        '@drawable/ic_launcher_foreground',
      );
      final colors = _root('$_res/values/colors.xml')
          .findElements('color')
          .map((c) => c.getAttribute('name'));
      expect(colors, contains('ic_launcher_background'));
      _densities.forEach((density, scale) {
        final px = (108 * scale).round();
        expect(_pngSize('$_res/drawable-$density/ic_launcher_foreground.png'), (
          px,
          px,
        ), reason: density);
      });
    });
  });
}
