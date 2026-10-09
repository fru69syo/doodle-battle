import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Family name registered in pubspec.yaml (bundled, no runtime fetching).
const appFontFamily = 'ZenMaruGothic';

/// Minimum touch target for children (SPEC: ≥ 56 dp).
const double kMinTouch = 56;

/// Kid-friendly theme: big rounded buttons, bold text, high contrast.
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    secondary: AppColors.secondary,
    surface: AppColors.background,
    onSurface: AppColors.ink,
    error: AppColors.danger,
  );
  const shape = StadiumBorder();
  const textStyle = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: appFontFamily,
    scaffoldBackgroundColor: AppColors.background,
  );
  return base.copyWith(
    // Merge (not replace) the body styles so they keep the bundled font
    // family and the ink colour; replacing them made DefaultTextStyle fall
    // back to the platform font with no colour (white text on paper).
    textTheme: base.textTheme
        .copyWith(
          bodyLarge: base.textTheme.bodyLarge?.copyWith(
            fontSize: 18,
            height: 1.5,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            fontSize: 16,
            height: 1.5,
          ),
        )
        .apply(
          fontFamily: appFontFamily,
          bodyColor: AppColors.ink,
          displayColor: AppColors.ink,
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.ink,
      centerTitle: true,
      elevation: 0,
      toolbarHeight: 64,
      titleTextStyle: TextStyle(
        fontFamily: appFontFamily,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(kMinTouch * 2, kMinTouch),
        shape: shape,
        textStyle: textStyle,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(kMinTouch * 2, kMinTouch),
        shape: shape,
        textStyle: textStyle,
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.ink, width: 2),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(kMinTouch, kMinTouch),
        textStyle: textStyle.copyWith(fontSize: 18),
        foregroundColor: AppColors.secondary,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(kMinTouch, kMinTouch),
        iconSize: 32,
      ),
    ),
    switchTheme: const SwitchThemeData(
      materialTapTargetSize: MaterialTapTargetSize.padded,
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: const TextStyle(
        fontFamily: appFontFamily,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: appFontFamily,
        fontSize: 18,
        color: AppColors.ink,
        height: 1.5,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      contentTextStyle: TextStyle(fontFamily: appFontFamily, fontSize: 18),
    ),
  );
}
