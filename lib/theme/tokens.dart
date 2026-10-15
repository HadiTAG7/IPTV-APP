import 'package:flutter/widgets.dart';

/// Colour palette for the dark, high-contrast TV-friendly theme.
abstract final class AppColors {
  static const background = Color(0xFF0B0E13);
  static const surface = Color(0xFF151A22);
  static const surfaceHigh = Color(0xFF1F2632);
  static const surfaceHighest = Color(0xFF2A3341);
  static const outline = Color(0xFF3A4352);

  /// Accent used for focus borders, progress and primary actions.
  static const accent = Color(0xFFFFB020);
  static const onAccent = Color(0xFF1A1200);

  static const textPrimary = Color(0xFFF3F5F9);
  static const textSecondary = Color(0xFFB4BCC8);
  static const textDisabled = Color(0xFF6E7785);

  static const error = Color(0xFFFF6B6B);
  static const success = Color(0xFF4CD08A);
  static const warning = Color(0xFFFFD166);
  static const favorite = Color(0xFFFFC83D);

  static const progressTrack = Color(0x33FFFFFF);
  static const scrim = Color(0xCC000000);

  /// Background colours for initials avatars, picked by name hash.
  static const avatarPalette = <Color>[
    Color(0xFF2F5D8A),
    Color(0xFF7A3E9D),
    Color(0xFF2E7D6B),
    Color(0xFF9C4A2F),
    Color(0xFF5E6B2E),
    Color(0xFF8A2F55),
    Color(0xFF3E4C9C),
    Color(0xFF6B4F2E),
  ];
}

/// Spacing scale in logical pixels (TV design space is 960 x 540).
abstract final class Spacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii.
abstract final class Radii {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 16;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
}

/// Focus highlight tokens shared by every focusable TV widget.
abstract final class FocusTokens {
  /// Border drawn around the focused item.
  static const double borderWidth = 3;

  /// Scale applied to the focused item.
  static const double scale = 1.06;

  static const Duration animation = Duration(milliseconds: 120);

  /// Scroll animation used to centre a newly focused item.
  static const Duration scroll = Duration(milliseconds: 160);

  /// [animation], or none where animations are off (Lite mode, or the
  /// system's reduce-motion setting).
  static Duration animationOf(BuildContext context) =>
      _motion(context, animation);

  /// [scroll], or none where animations are off.
  static Duration scrollOf(BuildContext context) => _motion(context, scroll);

  static Duration _motion(BuildContext context, Duration duration) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
      ? Duration.zero
      : duration;

  static const Color borderColor = AppColors.accent;
}

/// Layout constants for the large (TV / desktop) layout.
abstract final class TvLayout {
  /// Width of the TV design canvas in logical pixels.
  static const double designWidth = 960;

  /// Height of the TV design canvas in logical pixels (16:9).
  static const double designHeight = 540;

  /// Overscan-safe horizontal margin on TV.
  static const double overscanHorizontal = 48;

  /// Overscan-safe vertical margin on TV.
  static const double overscanVertical = 27;

  static const EdgeInsets overscan = EdgeInsets.symmetric(
    horizontal: overscanHorizontal,
    vertical: overscanVertical,
  );

  /// Fixed row height for channel lists on TV.
  static const double channelExtent = 56;

  /// Fixed row height for channel lists on phones.
  static const double channelExtentPhone = 64;

  /// Poster grid columns.
  static const int posterColumnsTv = 6;
  static const int posterColumnsPhone = 3;
}

/// Scale factor that maps the 960-wide TV design onto [logicalWidth].
///
/// Returns 1.0 for non-positive widths.
double tvScaleFactor(double logicalWidth) =>
    logicalWidth > 0 ? logicalWidth / TvLayout.designWidth : 1.0;
