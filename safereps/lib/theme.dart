import 'package:flutter/material.dart';

enum ThemeFlavor { pink, blue }

abstract final class AppColors {
  // Common colors
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);
  
  // Baseline Pink-theme constants (fallback for legacy code)
  static const Color background = Color(0xFFF5ECE3);
  static const Color surface    = Color(0xFFFFF0F5);
  static const Color pink       = Color(0xFFF2AFC4);
  static const Color pinkBright = Color(0xFFD6176E);
  static const Color beige      = Color(0xFFCBAD9A);
  static const Color textDark   = Color(0xFF3D2B1F);
  static const Color textMid    = Color(0xFF7A5A4A);
  static const Color textLight  = Color(0xFFB89A8A);
  static const Color glassFill   = Color(0x55FFFFFF);
  static const Color glassBorder = Color(0x70FFFFFF);
}

abstract final class AppTheme {
  static ThemeData fromFlavor(ThemeFlavor flavor) {
    final bool isPink = flavor == ThemeFlavor.pink;

    // Palette Definition
    final Color background = isPink ? const Color(0xFFF5ECE3) : const Color(0xFFF0F4F8);
    final Color surface = isPink ? const Color(0xFFFFF0F5) : const Color(0xFFFAFCFE);
    final Color primary = isPink ? const Color(0xFFD6176E) : const Color(0xFF6096BA);
    final Color accent = isPink ? const Color(0xFFF2AFC4) : const Color(0xFFA9C9D3);
    final Color unselected = isPink ? const Color(0xFFCBAD9A) : const Color(0xFF9CB4BF);

    final Color textDark = isPink ? const Color(0xFF3D2B1F) : const Color(0xFF1A212B);
    final Color textMid = isPink ? const Color(0xFF7A5A4A) : const Color(0xFF546E7A);
    final Color textLight = isPink ? const Color(0xFFB89A8A) : const Color(0xFF90A4AE);

    final Color glassTint   = isPink ? const Color(0x22F2AFC4) : const Color(0x228EACCD);
    final Color glassFill   = isPink ? const Color(0x55FFFFFF) : const Color(0x40FFFFFF);
    final Color glassBorder = isPink ? const Color(0x70FFFFFF) : const Color(0x50FFFFFF);

    final base = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: primary,
      secondary: accent,
      surface: surface,
      outline: unselected,
      onSurface: textDark,
      onSurfaceVariant: textMid,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textDark,
        titleTextStyle: TextStyle(
          color: textDark,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: primary,
        unselectedItemColor: unselected,
        type: BottomNavigationBarType.fixed,
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(color: textDark, fontWeight: FontWeight.w800),
        headlineMedium: TextStyle(color: textDark, fontWeight: FontWeight.w700),
        headlineSmall: TextStyle(color: textDark, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: textDark),
        bodyMedium: TextStyle(color: textMid),
        bodySmall: TextStyle(color: textLight),
        labelLarge: TextStyle(color: textDark, fontWeight: FontWeight.w600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: textDark,
          shape: const StadiumBorder(),
        ),
      ),
    ).copyWith(
      extensions: [
        BrandColors(
          textDark: textDark,
          textMid: textMid,
          textLight: textLight,
          unselected: unselected,
          accent: accent,
          glassTint: glassTint,
          glassFill: glassFill,
          glassBorder: glassBorder,
        ),
      ],
    );
  }

  static BrandColors colors(BuildContext context) =>
      Theme.of(context).extension<BrandColors>()!;

  static ThemeData get light => fromFlavor(ThemeFlavor.pink);
}

class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors({
    required this.textDark,
    required this.textMid,
    required this.textLight,
    required this.unselected,
    required this.accent,
    required this.glassTint,
    required this.glassFill,
    required this.glassBorder,
  });

  final Color textDark;
  final Color textMid;
  final Color textLight;
  final Color unselected;
  final Color accent;
  final Color glassTint;
  final Color glassFill;
  final Color glassBorder;

  @override
  BrandColors copyWith({
    Color? textDark,
    Color? textMid,
    Color? textLight,
    Color? unselected,
    Color? accent,
    Color? glassTint,
    Color? glassFill,
    Color? glassBorder,
  }) {
    return BrandColors(
      textDark: textDark ?? this.textDark,
      textMid: textMid ?? this.textMid,
      textLight: textLight ?? this.textLight,
      unselected: unselected ?? this.unselected,
      accent: accent ?? this.accent,
      glassTint: glassTint ?? this.glassTint,
      glassFill: glassFill ?? this.glassFill,
      glassBorder: glassBorder ?? this.glassBorder,
    );
  }

  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) {
    if (other is! BrandColors) return this;
    return BrandColors(
      textDark: Color.lerp(textDark, other.textDark, t)!,
      textMid: Color.lerp(textMid, other.textMid, t)!,
      textLight: Color.lerp(textLight, other.textLight, t)!,
      unselected: Color.lerp(unselected, other.unselected, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      glassTint: Color.lerp(glassTint, other.glassTint, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
    );
  }
}
