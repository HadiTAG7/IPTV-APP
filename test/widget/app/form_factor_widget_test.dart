import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app/form_factor.dart';
import 'package:iptv_player/theme/app_theme.dart';
import 'package:iptv_player/theme/tokens.dart';

import '../support/tv_harness.dart';

void main() {
  testWidgets('TvViewport lays out on a 960-wide canvas', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1; // 1920 x 1080 logical: scale 2
    addTearDown(tester.view.reset);
    Size? seen;
    await tester.pumpWidget(
      TvViewport(
        child: Builder(
          builder: (context) {
            seen = MediaQuery.sizeOf(context);
            return const SizedBox.expand(key: ValueKey('content'));
          },
        ),
      ),
    );
    expect(seen, const Size(TvLayout.designWidth, TvLayout.designHeight));
    final content = find.byKey(const ValueKey('content'));
    expect(tester.getSize(content), const Size(960, 540));
    expect(tester.getRect(content), const Rect.fromLTWH(0, 0, 1920, 1080));
  });

  testWidgets('TvViewport at the design width is an identity layout', (
    tester,
  ) async {
    Size? seen;
    double? dpr;
    await pumpTv(
      tester,
      TvViewport(
        child: Builder(
          builder: (context) {
            seen = MediaQuery.sizeOf(context);
            dpr = MediaQuery.devicePixelRatioOf(context);
            return const SizedBox.expand(key: ValueKey('content'));
          },
        ),
      ),
    );
    final content = find.byKey(const ValueKey('content'));
    expect(seen, tester.getSize(content));
    expect(dpr, 2);
    expect(tester.getSize(content).width, TvLayout.designWidth);
  });

  testWidgets('TvViewport keeps child state across any resize', (tester) async {
    var created = 0;
    _CounterState counter() => tester.state(find.byType(_Counter));
    addTearDown(tester.view.reset);
    Future<void> resize(Size physical, double dpr) async {
      tester.view.physicalSize = physical;
      tester.view.devicePixelRatio = dpr;
      await tester.pump();
    }

    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2; // exactly the design width
    // No key: a GlobalKey would hide a remount by reparenting the state.
    await tester.pumpWidget(
      TvViewport(child: _Counter(onCreate: () => created++)),
    );
    counter().value = 7;

    await resize(const Size(2000, 1080), 2); // 1000 dp: scaled
    await resize(const Size(1918, 1080), 2); // 959 dp
    await resize(const Size(1920, 1080), 1); // 1920 dp: scale 2
    await resize(Size.zero, 1); // minimised window
    await resize(const Size(1920, 1080), 2);
    expect(tester.takeException(), isNull);
    expect(created, 1);
    expect(counter().value, 7);
  });

  testWidgets('FormFactorScope', (tester) async {
    late FormFactor inner;
    late FormFactor outer;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          outer = FormFactorScope.of(context);
          return FormFactorScope(
            formFactor: FormFactor.tv,
            child: Builder(
              builder: (context) {
                inner = FormFactorScope.of(context);
                expect(FormFactorScope.isTv(context), isTrue);
                return const SizedBox();
              },
            ),
          );
        },
      ),
    );
    expect(outer, FormFactor.phone);
    expect(inner, FormFactor.tv);
  });

  test('theme is dark, Tajawal and accent-based', () {
    final theme = AppTheme.dark(tv: true);
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, AppColors.accent);
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.textTheme.bodyMedium?.fontFamily, kAppFontFamily);
    final focused = theme.filledButtonTheme.style!.side!.resolve({
      WidgetState.focused,
    });
    expect(focused?.width, FocusTokens.borderWidth);
    expect(theme.filledButtonTheme.style!.side!.resolve({}), isNull);
  });

  testWidgets('Arabic text renders with Tajawal glyphs', (tester) async {
    const label = 'مشغّل IPTV';
    await pumpTv(
      tester,
      const Column(
        children: [
          Text(label, key: ValueKey('tajawal')),
          Text(
            label,
            key: ValueKey('fallback'),
            style: TextStyle(fontFamily: 'NoSuchFamily'),
          ),
        ],
      ),
      locale: ar,
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byKey(const ValueKey('tajawal')),
        matching: find.byType(RichText),
      ),
    );
    expect(paragraph.text.style?.fontFamily, kAppFontFamily);
    // The test font draws every glyph as a 1 em square; real Tajawal glyphs
    // are proportional and much narrower.
    final tajawal = tester.getSize(find.byKey(const ValueKey('tajawal')));
    final fallback = tester.getSize(find.byKey(const ValueKey('fallback')));
    expect(tajawal.width, lessThan(fallback.width * 0.8));
  });
}

class _Counter extends StatefulWidget {
  const _Counter({required this.onCreate});

  final VoidCallback onCreate;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int value = 0;

  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
