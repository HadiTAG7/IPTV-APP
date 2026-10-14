import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/widgets/section_header.dart';
import 'package:iptv_player/widgets/states.dart';

import '../support/tv_harness.dart';

void main() {
  final strings = {
    en: (
      loading: 'Loading…',
      empty: 'Nothing here yet',
      error: 'Something went wrong',
      retry: 'Retry',
    ),
    ar: (
      loading: 'جارٍ التحميل…',
      empty: 'لا يوجد شيء هنا بعد',
      error: 'حدث خطأ ما',
      retry: 'إعادة المحاولة',
    ),
  };

  for (final locale in testLocales) {
    final s = strings[locale]!;
    group('states (${locale.languageCode})', () {
      testWidgets('LoadingView shows a localized default', (tester) async {
        await pumpTv(tester, const LoadingView(), locale: locale);
        expect(find.text(s.loading), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });

      testWidgets('EmptyView default and custom message', (tester) async {
        await pumpTv(tester, const EmptyView(), locale: locale);
        expect(find.text(s.empty), findsOneWidget);
        await pumpTv(
          tester,
          const EmptyView(message: 'Custom', icon: Icons.star),
          locale: locale,
        );
        expect(find.text('Custom'), findsOneWidget);
        expect(find.byIcon(Icons.star), findsOneWidget);
      });

      testWidgets('holding OK on Retry retries once', (tester) async {
        var retries = 0;
        await pumpTv(
          tester,
          ErrorView(onRetry: () => retries++),
          locale: locale,
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
        for (var i = 0; i < 5; i++) {
          await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
        await tester.pump();
        expect(retries, 1);

        // Enter and the game pad A button behave the same.
        for (final key in [
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.gameButtonA,
        ]) {
          await tester.sendKeyDownEvent(key);
          await tester.sendKeyRepeatEvent(key);
          await tester.sendKeyRepeatEvent(key);
          await tester.sendKeyUpEvent(key);
        }
        await tester.pump();
        expect(retries, 3);
      });

      testWidgets('ErrorView retry is focused and OK retries', (tester) async {
        var retries = 0;
        await pumpTv(
          tester,
          ErrorView(details: 'HTTP 503', onRetry: () => retries++),
          locale: locale,
        );
        expect(find.text(s.error), findsOneWidget);
        expect(find.text('HTTP 503'), findsOneWidget);
        expect(find.text(s.retry), findsOneWidget);

        await press(tester, LogicalKeyboardKey.select);
        expect(retries, 1);
        await tester.tap(find.text(s.retry));
        expect(retries, 2);
      });

      testWidgets('ErrorView without retry has no button', (tester) async {
        await pumpTv(tester, const ErrorView(message: 'Boom'), locale: locale);
        expect(find.text('Boom'), findsOneWidget);
        expect(find.byType(FilledButton), findsNothing);
      });
    });
  }

  group('ProgressLine', () {
    double factor(WidgetTester tester) => tester
        .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .widthFactor!;

    testWidgets('clamps its value', (tester) async {
      for (final (value, expected) in [
        (0.4, 0.4),
        (-1.0, 0.0),
        (3.0, 1.0),
        (double.nan, 0.0),
      ]) {
        await pumpTv(
          tester,
          SizedBox(width: 200, child: ProgressLine(value: value)),
        );
        expect(factor(tester), expected);
      }
    });

    testWidgets('fills from the reading start', (tester) async {
      for (final locale in testLocales) {
        await pumpTv(
          tester,
          const Center(
            child: SizedBox(width: 200, child: ProgressLine(value: 0.25)),
          ),
          locale: locale,
        );
        final track = tester.getRect(find.byType(ProgressLine));
        final fill = tester.getRect(
          find
              .descendant(
                of: find.byType(FractionallySizedBox),
                matching: find.byType(ColoredBox),
              )
              .first,
        );
        expect(fill.width, closeTo(50, 0.01));
        if (locale == ar) {
          expect(fill.right, closeTo(track.right, 0.01));
        } else {
          expect(fill.left, closeTo(track.left, 0.01));
        }
      }
    });
  });

  testWidgets('SectionHeader shows title and trailing', (tester) async {
    await pumpTv(
      tester,
      const SectionHeader('Continue watching', trailing: Text('12')),
    );
    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Continue watching')),
      matchesSemantics(isHeader: true, label: 'Continue watching'),
    );
  });
}
