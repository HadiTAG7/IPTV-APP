import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/help/licenses.dart';

class _CountingBundle extends CachingAssetBundle {
  _CountingBundle(this.text);

  final String text;
  final loaded = <String>[];

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }
}

Future<List<LicenseEntry>> _tajawalEntries() async => [
  for (final e in await LicenseRegistry.licenses.toList())
    if (e.packages.contains(kTajawalLicensePackage)) e,
];

String _text(LicenseEntry e) => e.paragraphs.map((p) => p.text).join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void reset() {
    LicenseRegistry.reset();
    resetFontLicensesForTest();
  }

  setUp(reset);
  tearDown(reset);

  test('registers the bundled Tajawal OFL once', () async {
    registerFontLicenses();
    registerFontLicenses();
    final entries = await _tajawalEntries();
    expect(entries, hasLength(1));
    final text = _text(entries.single);
    expect(text, contains('SIL Open Font License'));
    expect(text, contains('Boutros'));
  });

  test('reads the licence text only when the licences are listed', () async {
    final bundle = _CountingBundle('Copyright Tajawal authors.\n\nOFL text.');
    registerFontLicenses(bundle: bundle);
    expect(bundle.loaded, isEmpty);
    final entries = await _tajawalEntries();
    expect(bundle.loaded, [kTajawalLicenseAsset]);
    expect(_text(entries.single), contains('OFL text.'));
  });

  testWidgets('the licences page lists the font', (tester) async {
    registerFontLicenses(
      bundle: _CountingBundle('Tajawal licence text for the page.'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showLicensePage(context: context),
            child: const Text('licences'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('licences'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(find.text(kTajawalLicensePackage), findsOneWidget);
  });
}
