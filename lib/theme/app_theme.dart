import 'package:flutter/material.dart';

import 'tokens.dart';

/// Bundled UI font (Arabic + Latin).
const kAppFontFamily = 'Tajawal';

/// Builds the app's dark, high-contrast theme.
///
/// Sizes target the 960 x 540 TV design canvas; [tv] only tightens a few
/// touch-oriented defaults (visual density, tap targets).
abstract final class AppTheme {
  static ThemeData dark({bool tv = false}) {
    const scheme = ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      primaryContainer: Color(0xFF4A3500),
      onPrimaryContainer: Color(0xFFFFDDA6),
      secondary: Color(0xFF8FB8FF),
      onSecondary: Color(0xFF0A1B33),
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: AppColors.background,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.surfaceHigh,
      surfaceContainerHighest: AppColors.surfaceHighest,
      outline: AppColors.outline,
      outlineVariant: AppColors.surfaceHighest,
      error: AppColors.error,
      onError: Color(0xFF2A0000),
      scrim: AppColors.scrim,
    );

    final textTheme = _textTheme();
    final focusSide = WidgetStateProperty.resolveWith<BorderSide?>(
      (states) => states.contains(WidgetState.focused)
          ? const BorderSide(
              color: AppColors.textPrimary,
              width: FocusTokens.borderWidth,
            )
          : null,
    );
    const buttonShape = RoundedRectangleBorder(borderRadius: Radii.mdAll);
    const buttonPadding = EdgeInsets.symmetric(
      horizontal: Spacing.xl,
      vertical: Spacing.md,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: kAppFontFamily,
      textTheme: textTheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      focusColor: AppColors.accent.withValues(alpha: 0.24),
      hoverColor: AppColors.textPrimary.withValues(alpha: 0.06),
      splashFactory: tv ? NoSplash.splashFactory : null,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: tv
          ? MaterialTapTargetSize.shrinkWrap
          : MaterialTapTargetSize.padded,
      iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 22),
      dividerTheme: const DividerThemeData(
        color: AppColors.surfaceHighest,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: const AppBarThemeData(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: Radii.mdAll),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: Radii.lgAll),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          side: focusSide,
          shape: const WidgetStatePropertyAll(buttonShape),
          padding: const WidgetStatePropertyAll(buttonPadding),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.focused)
                  ? AppColors.accent
                  : AppColors.outline,
              width: states.contains(WidgetState.focused)
                  ? FocusTokens.borderWidth
                  : 1,
            ),
          ),
          foregroundColor: const WidgetStatePropertyAll(AppColors.textPrimary),
          shape: const WidgetStatePropertyAll(buttonShape),
          padding: const WidgetStatePropertyAll(buttonPadding),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          side: focusSide,
          shape: const WidgetStatePropertyAll(buttonShape),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? const BorderSide(
                    color: AppColors.accent,
                    width: FocusTokens.borderWidth,
                  )
                : null,
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        selectedColor: AppColors.accent,
        selectedTileColor: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: Radii.mdAll),
        contentPadding: EdgeInsetsDirectional.symmetric(horizontal: Spacing.lg),
      ),
      inputDecorationTheme: const InputDecorationThemeData(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        contentPadding: EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.md,
        ),
        labelStyle: TextStyle(color: AppColors.textSecondary),
        hintStyle: TextStyle(color: AppColors.textDisabled),
        border: OutlineInputBorder(
          borderRadius: Radii.mdAll,
          borderSide: BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.mdAll,
          borderSide: BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.mdAll,
          borderSide: BorderSide(
            color: AppColors.accent,
            width: FocusTokens.borderWidth,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Radii.mdAll,
          borderSide: BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: Radii.mdAll,
          borderSide: BorderSide(
            color: AppColors.error,
            width: FocusTokens.borderWidth,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.onAccent
              : AppColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.surfaceHighest,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.progressTrack,
        circularTrackColor: Colors.transparent,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.accent.withValues(alpha: 0.18),
        selectedIconTheme: const IconThemeData(color: AppColors.accent),
        unselectedIconTheme: const IconThemeData(
          color: AppColors.textSecondary,
        ),
        selectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: AppColors.accent,
        ),
        unselectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.accent.withValues(alpha: 0.18),
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceHigh,
        selectedColor: AppColors.accent,
        labelStyle: textTheme.labelLarge,
        side: const BorderSide(color: AppColors.outline),
        shape: const StadiumBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHighest,
        contentTextStyle: textTheme.bodyMedium,
        behavior: SnackBarBehavior.floating,
      ),
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceHighest,
          borderRadius: Radii.smAll,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.accent,
        selectionColor: AppColors.accent.withValues(alpha: 0.35),
        selectionHandleColor: AppColors.accent,
      ),
    );
  }

  static TextTheme _textTheme() {
    const primary = AppColors.textPrimary;
    const secondary = AppColors.textSecondary;
    TextStyle s(double size, FontWeight w, Color c, [double height = 1.3]) =>
        TextStyle(
          fontFamily: kAppFontFamily,
          fontSize: size,
          fontWeight: w,
          color: c,
          height: height,
        );
    return TextTheme(
      displaySmall: s(32, FontWeight.w700, primary, 1.2),
      headlineMedium: s(26, FontWeight.w700, primary, 1.2),
      headlineSmall: s(22, FontWeight.w700, primary, 1.25),
      titleLarge: s(19, FontWeight.w700, primary),
      titleMedium: s(16, FontWeight.w500, primary),
      titleSmall: s(14, FontWeight.w500, primary),
      bodyLarge: s(16, FontWeight.w400, primary, 1.45),
      bodyMedium: s(14, FontWeight.w400, primary, 1.45),
      bodySmall: s(12, FontWeight.w400, secondary, 1.35),
      labelLarge: s(14, FontWeight.w500, primary, 1.2),
      labelMedium: s(12, FontWeight.w500, secondary, 1.2),
      labelSmall: s(11, FontWeight.w500, secondary, 1.2),
    );
  }
}
