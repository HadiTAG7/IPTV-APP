import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/theme/tokens.dart';
import 'package:iptv_player/tv/tv_focusable.dart';
import 'package:iptv_player/widgets/channel_tile.dart';
import 'package:iptv_player/widgets/logo_image.dart';
import 'package:iptv_player/widgets/states.dart';

import '../support/tv_harness.dart';

Text _text(WidgetTester tester, String s) => tester.widget<Text>(find.text(s));

void main() {
  for (final locale in testLocales) {
    final rtl = locale == ar;
    group('ChannelTile (${locale.languageCode})', () {
      testWidgets('shows number, logo, name, programme, progress and star', (
        tester,
      ) async {
        await pumpTv(
          tester,
          const SizedBox(
            width: 420,
            height: TvLayout.channelExtent,
            child: ChannelTile(
              number: 107,
              name: 'Example News HD',
              nowTitle: 'Evening Bulletin',
              progress: 0.3,
              isFavorite: true,
            ),
          ),
          locale: locale,
        );
        expect(find.text('107'), findsOneWidget);
        expect(find.text('Example News HD'), findsOneWidget);
        expect(find.text('Evening Bulletin'), findsOneWidget);
        expect(find.byType(LogoImage), findsOneWidget);
        expect(find.text('EN'), findsOneWidget, reason: 'initials fallback');
        expect(find.byType(ProgressLine), findsOneWidget);
        expect(find.byIcon(Icons.star_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Number keeps Western digits and LTR order.
        expect(_text(tester, '107').textDirection, TextDirection.ltr);
        // Number sits on the reading-start side of the name.
        final numX = tester.getCenter(find.text('107')).dx;
        final nameX = tester.getCenter(find.text('Example News HD')).dx;
        expect(rtl ? numX > nameX : numX < nameX, isTrue);
      });

      testWidgets('per-string direction for mixed names', (tester) async {
        await pumpTv(
          tester,
          const Column(
            children: [
              SizedBox(
                width: 420,
                height: TvLayout.channelExtent,
                child: ChannelTile(
                  name: 'Example News',
                  nowTitle: 'نشرة الأخبار',
                ),
              ),
              SizedBox(
                width: 420,
                height: TvLayout.channelExtent,
                child: ChannelTile(name: 'قناة تجريبية', nowTitle: 'Morning'),
              ),
            ],
          ),
          locale: locale,
        );
        expect(_text(tester, 'Example News').textDirection, TextDirection.ltr);
        expect(_text(tester, 'نشرة الأخبار').textDirection, TextDirection.rtl);
        expect(_text(tester, 'قناة تجريبية').textDirection, TextDirection.rtl);
        expect(_text(tester, 'Morning').textDirection, TextDirection.ltr);
        // Alignment follows the UI, not the string.
        final align = rtl ? TextAlign.right : TextAlign.left;
        expect(_text(tester, 'Example News').textAlign, align);
        expect(_text(tester, 'قناة تجريبية').textAlign, align);
      });

      testWidgets('missing programme shows the localized placeholder', (
        tester,
      ) async {
        await pumpTv(
          tester,
          const SizedBox(
            width: 420,
            height: TvLayout.channelExtent,
            child: ChannelTile(name: 'Demo'),
          ),
          locale: locale,
        );
        expect(
          find.text(rtl ? 'لا توجد معلومات عن البرنامج' : 'No programme info'),
          findsOneWidget,
        );
        expect(find.byType(ProgressLine), findsNothing);
        expect(find.byIcon(Icons.star_rounded), findsNothing);
      });

      for (final scale in [1.15, 1.3, 2.0]) {
        testWidgets('fits the TV row at system text scale $scale', (
          tester,
        ) async {
          await pumpTv(
            tester,
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: SizedBox(
                    width: 420,
                    height: TvLayout.channelExtent,
                    child: ChannelTile(
                      number: 7,
                      name: rtl ? 'قناة الأخبار' : 'Example News',
                      nowTitle: rtl ? 'نشرة المساء' : 'Evening bulletin',
                      progress: 0.4,
                      isFavorite: true,
                    ),
                  ),
                ),
              ),
            ),
            locale: locale,
          );
          expect(tester.takeException(), isNull);
          final name = find.text(rtl ? 'قناة الأخبار' : 'Example News');
          expect(
            MediaQuery.textScalerOf(tester.element(name)),
            const TextScaler.linear(ChannelTile.maxTextScale),
          );
        });
      }

      testWidgets('rows fit the fixed list extent and respond to keys', (
        tester,
      ) async {
        final selected = <int>[];
        final menus = <int>[];
        await pumpTv(
          tester,
          SizedBox(
            width: 420,
            child: ListView.builder(
              itemExtent: TvLayout.channelExtent,
              itemCount: 30,
              itemBuilder: (context, i) => ChannelTile(
                key: ValueKey(i),
                autofocus: i == 0,
                number: i + 1,
                name: 'Channel ${i + 1} with a rather long display name',
                nowTitle: 'Programme title that is also quite long',
                progress: i / 30,
                isFavorite: i.isEven,
                onSelect: () => selected.add(i),
                onMenu: () => menus.add(i),
              ),
            ),
          ),
          locale: locale,
        );
        expect(tester.takeException(), isNull);
        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.select);
        await press(tester, LogicalKeyboardKey.contextMenu);
        expect(selected, [2]);
        expect(menus, [2]);
        expect(
          TvHighlight.of(
            tester.element(
              find.text(
                'Channel 3 with a rather '
                'long display name',
              ),
            ),
          ),
          isTrue,
        );
      });
    });
  }
}
