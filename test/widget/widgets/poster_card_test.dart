import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/theme/tokens.dart';
import 'package:iptv_player/widgets/poster_card.dart';
import 'package:iptv_player/widgets/states.dart';

import '../support/tv_harness.dart';

void main() {
  test('heightForWidth = 2:3 poster + gap + title', () {
    expect(
      PosterCard.heightForWidth(100),
      150 + Spacing.sm + PosterCard.titleHeight,
    );
  });

  for (final locale in testLocales) {
    group('PosterCard (${locale.languageCode})', () {
      testWidgets('2:3 poster, title and continue-watching bar', (
        tester,
      ) async {
        await pumpTv(
          tester,
          const Align(
            alignment: AlignmentDirectional.topStart,
            child: SizedBox(
              width: 120,
              child: PosterCard(title: 'Demo Movie', progress: 0.6),
            ),
          ),
          locale: locale,
        );
        final poster = tester.getSize(find.byType(AspectRatio));
        expect(poster.width, 120);
        expect(poster.height, 180);
        expect(
          tester.getSize(find.byType(PosterCard)).height,
          PosterCard.heightForWidth(120),
        );
        // Placeholder (no poster URL) repeats the title.
        expect(find.text('Demo Movie'), findsNWidgets(2));
        expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
        final bar = tester.widget<ProgressLine>(find.byType(ProgressLine));
        expect(bar.value, 0.6);
        expect(tester.takeException(), isNull);
      });

      testWidgets('grid navigation and select', (tester) async {
        final selected = <int>[];
        await pumpTv(
          tester,
          GridView.builder(
            padding: const EdgeInsets.all(Spacing.xl),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: TvLayout.posterColumnsTv,
              crossAxisSpacing: Spacing.lg,
              mainAxisSpacing: Spacing.lg,
              mainAxisExtent: PosterCard.heightForWidth(
                (960 - 2 * Spacing.xl - 5 * Spacing.lg) / 6,
              ),
            ),
            itemCount: 18,
            itemBuilder: (context, i) => PosterCard(
              key: ValueKey(i),
              title: 'Movie $i',
              autofocus: i == 0,
              onSelect: () => selected.add(i),
            ),
          ),
          locale: locale,
        );
        expect(tester.takeException(), isNull);
        final towardsNext = locale == ar
            ? LogicalKeyboardKey.arrowLeft
            : LogicalKeyboardKey.arrowRight;
        await press(tester, towardsNext);
        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.enter);
        expect(selected, [7]);
      });
    });
  }
}
