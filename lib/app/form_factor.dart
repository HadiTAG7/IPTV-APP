import 'package:flutter/widgets.dart';

import '../core/platform/device_caps.dart';
import '../theme/tokens.dart';

/// Which shell and navigation model the app uses.
enum FormFactor { tv, phone, desktop }

/// User override from Settings > Device mode.
enum FormFactorOverride { auto, tv, phone }

/// Picks the form factor.
///
/// Desktop platforms are [FormFactor.desktop] unless overridden to TV.
/// Elsewhere an explicit override wins, then [DeviceCaps.isTv]. Tablets stay
/// [FormFactor.phone]; [useLargeLayout] gives them the large layout by size.
FormFactor resolveFormFactor(
  DeviceCaps caps,
  FormFactorOverride override,
  Size logicalSize,
  TargetPlatform platform,
) {
  final desktop =
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux ||
      platform == TargetPlatform.macOS;
  if (desktop) {
    return override == FormFactorOverride.tv
        ? FormFactor.tv
        : FormFactor.desktop;
  }
  return switch (override) {
    FormFactorOverride.tv => FormFactor.tv,
    FormFactorOverride.phone => FormFactor.phone,
    FormFactorOverride.auto => caps.isTv ? FormFactor.tv : FormFactor.phone,
  };
}

/// Large layout: TV, desktop, or any landscape screen at least 900 dp wide.
bool useLargeLayout(FormFactor f, Size s) =>
    f == FormFactor.tv ||
    f == FormFactor.desktop ||
    (s.width > s.height && s.width >= 900);

/// Overscan-safe padding: 48 x 27 dp on TV, none elsewhere.
EdgeInsets overscanPadding(FormFactor f) =>
    f == FormFactor.tv ? TvLayout.overscan : EdgeInsets.zero;

/// Makes the resolved [FormFactor] available to descendants.
class FormFactorScope extends InheritedWidget {
  const FormFactorScope({
    super.key,
    required this.formFactor,
    required super.child,
  });

  final FormFactor formFactor;

  /// The nearest form factor, or [FormFactor.phone] when none is provided.
  static FormFactor of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<FormFactorScope>()
          ?.formFactor ??
      FormFactor.phone;

  static bool isTv(BuildContext context) => of(context) == FormFactor.tv;

  @override
  bool updateShouldNotify(FormFactorScope oldWidget) =>
      oldWidget.formFactor != formFactor;
}

/// Lays [child] out on a canvas [TvLayout.designWidth] wide and scales it to
/// the available width, so TV screens look the same at any density.
///
/// The [MediaQuery] seen by [child] reports the design-space size. The widget
/// tree has the same shape at every size (including the design width and an
/// empty, minimised window), so resizing never remounts [child] or loses its
/// state.
class TvViewport extends StatelessWidget {
  const TvViewport({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final usable =
            width.isFinite && height.isFinite && width > 0 && height > 0;
        final scale = usable ? tvScaleFactor(width) : 1.0;
        final design = usable
            ? Size(TvLayout.designWidth, height / scale)
            : constraints.smallest;
        final mq = MediaQuery.of(context);
        return FittedBox(
          fit: BoxFit.fill,
          child: SizedBox.fromSize(
            size: design,
            child: MediaQuery(
              data: mq.copyWith(
                size: design,
                devicePixelRatio: mq.devicePixelRatio * scale,
                padding: mq.padding / scale,
                viewPadding: mq.viewPadding / scale,
                viewInsets: mq.viewInsets / scale,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
