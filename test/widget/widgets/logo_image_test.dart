import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/time/clock.dart';
import 'package:iptv_player/widgets/logo_image.dart';

import '../support/tv_harness.dart';

void main() {
  for (final locale in testLocales) {
    group('LogoImage (${locale.languageCode})', () {
      testWidgets('no URL shows the initials avatar', (tester) async {
        await pumpTv(
          tester,
          const Center(
            child: LogoImage(url: null, name: 'Example News HD', size: 48),
          ),
          locale: locale,
        );
        expect(find.byType(Image), findsNothing);
        expect(find.byType(InitialsAvatar), findsOneWidget);
        expect(find.text('EN'), findsOneWidget);
        expect(tester.getSize(find.byType(InitialsAvatar)), const Size(48, 48));
      });

      testWidgets('non-http URLs never hit the network', (tester) async {
        await pumpTv(
          tester,
          const Center(
            child: LogoImage(url: 'file:///logo.png', name: 'قناة تجريبية'),
          ),
          locale: locale,
        );
        expect(find.byType(Image), findsNothing);
        expect(find.text('ق'), findsOneWidget);
      });

      testWidgets('failed load falls back to initials and is cached', (
        tester,
      ) async {
        const url = 'http://127.0.0.1:9/logos/demo.png';
        await pumpTv(
          tester,
          const Center(
            child: LogoImage(url: url, name: 'Demo Kids', size: 40),
          ),
          locale: locale,
        );
        final image = tester.widget<Image>(find.byType(Image));
        final provider = image.image as ResizeImage;
        expect((provider.imageProvider as NetworkImage).url, url);
        expect(provider.width, 80, reason: 'cacheWidth = size x DPR');
        // While loading the avatar is shown.
        expect(find.text('DK'), findsOneWidget);

        // The test HTTP client answers 400; let the load fail.
        await tester.runAsync(() async {
          for (var i = 0; i < 20 && !FailedImageCache.contains(url); i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump();
          }
        });
        await tester.pump();
        expect(FailedImageCache.contains(url), isTrue);
        expect(find.text('DK'), findsOneWidget);

        // A fresh build does not try the URL again.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          const TestApp(
            child: Center(
              child: LogoImage(url: url, name: 'Demo Kids'),
            ),
          ),
        );
        expect(find.byType(Image), findsNothing);
        expect(find.text('DK'), findsOneWidget);
      });

      testWidgets('a transient failure is retried once it expires', (
        tester,
      ) async {
        const url = 'http://127.0.0.1:9/logos/boot.png';
        final clock = FakeClock(DateTime.utc(2026, 10, 1, 20));
        FailedImageCache.clock = clock;
        addTearDown(() => FailedImageCache.clock = const SystemClock());
        await pumpTv(
          tester,
          const Center(
            child: LogoImage(url: url, name: 'Demo Kids'),
          ),
          locale: locale,
        );
        // Boot without Wi-Fi: the first load fails with a network error.
        FailedImageCache.add(url, error: Exception('Network is unreachable'));
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          TestApp(
            locale: locale,
            child: const Center(
              child: LogoImage(url: url, name: 'Demo Kids'),
            ),
          ),
        );
        expect(find.byType(Image), findsNothing);

        clock.advance(FailedImageCache.transientTtl);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          TestApp(
            locale: locale,
            child: const Center(
              child: LogoImage(url: url, name: 'Demo Kids'),
            ),
          ),
        );
        expect(find.byType(Image), findsOneWidget, reason: 'retried');
      });
    });
  }
}
