import 'package:flutter/material.dart';

abstract final class AppColors {
  // Background & surfaces
  static const Color background = Color(0xFFF5ECE3); // matte warm beige
  static const Color surface = Color(0xFFFFF0F5);    // lavender blush (cards)
  static const Color pink = Color(0xFFF2AFC4);        // pastel pink (buttons/tiles)
  static const Color pinkBright = Color(0xFFD6176E);  // hot pink (ring, active)
  static const Color beige = Color(0xFFCBAD9A);       // beige accent / unselected

  // Text
  static const Color textDark = Color(0xFF3D2B1F);
  static const Color textMid = Color(0xFF7A5A4A);
  static const Color textLight = Color(0xFFB89A8A);

  // Glass
  static const Color glassFill = Color(0x55FFFFFF);
  static const Color glassBorder = Color(0x70FFFFFF);
  static const Color glassPinkTint = Color(0x22F2AFC4);
}

abstract final class AppTheme {
  static ThemeData get light {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFFF2AFC4),
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.pinkBright,
      secondary: AppColors.pink,
      surface: AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleTextStyle: TextStyle(
          color: AppColors.textDark,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: AppColors.pinkBright,
        unselectedItemColor: AppColors.beige,
        type: BottomNavigationBarType.fixed,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
            color: AppColors.textDark, fontWeight: FontWeight.w800),
        headlineMedium: TextStyle(
            color: AppColors.textDark, fontWeight: FontWeight.w700),
        headlineSmall: TextStyle(
            color: AppColors.textDark, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: AppColors.textDark),
        bodyMedium: TextStyle(color: AppColors.textMid),
        bodySmall: TextStyle(color: AppColors.textLight),
        labelLarge: TextStyle(
            color: AppColors.textDark, fontWeight: FontWeight.w600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.pink,
          foregroundColor: AppColors.textDark,
          shape: const StadiumBorder(),
        ),
      ),
    );
  }
}
