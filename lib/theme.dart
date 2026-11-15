import 'package:flutter/material.dart';

/// Corner radius used everywhere (bubbles, dialogs, menus, inputs, buttons).
const double kRadius = 6;

/// Shared animation timings.
const Duration kAnimFast = Duration(milliseconds: 180);
const Duration kAnimMedium = Duration(milliseconds: 280);

const BorderRadius kBorderRadius = BorderRadius.all(Radius.circular(kRadius));
const RoundedRectangleBorder kShape = RoundedRectangleBorder(borderRadius: kBorderRadius);

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF5B8DEF),
    brightness: Brightness.dark,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    dialogTheme: const DialogThemeData(shape: kShape),
    popupMenuTheme: const PopupMenuThemeData(shape: kShape),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadius)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: kShape),
    chipTheme: const ChipThemeData(shape: kShape),
    cardTheme: const CardThemeData(shape: kShape),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(color: Color(0xEE303030), borderRadius: kBorderRadius),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      border: const OutlineInputBorder(borderRadius: kBorderRadius),
      enabledBorder: OutlineInputBorder(
        borderRadius: kBorderRadius,
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: kBorderRadius,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: kShape, minimumSize: const Size.fromHeight(48)),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: kShape)),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: kShape)),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        // TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
