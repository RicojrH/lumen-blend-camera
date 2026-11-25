import 'package:flutter/material.dart';

class AppTheme {
  static const Color bgObsidian = Color(0xFF0A0C10);
  static const Color surfaceDark = Color(0xFF131720);
  static const Color surfaceElevated = Color(0xFF1B212E);
  static const Color borderSubtle = Color(0xFF283142);

  static const Color accentAmber = Color(0xFFF5A623);
  static const Color accentCyan = Color(0xFF38BDF8);
  static const Color accentMint = Color(0xFF34D399);
  static const Color accentRose = Color(0xFFFB7185);

  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static ThemeData get darkTheme {
    const cjkFallback = <String>[
      'Microsoft YaHei',
      'PingFang SC',
      'Hiragino Sans GB',
      'Noto Sans SC',
      'sans-serif',
    ];
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamilyFallback: cjkFallback),
      primaryTextTheme:
          base.primaryTextTheme.apply(fontFamilyFallback: cjkFallback),
      scaffoldBackgroundColor: bgObsidian,
      colorScheme: const ColorScheme.dark(
        primary: accentAmber,
        secondary: accentCyan,
        surface: surfaceDark,
        error: accentRose,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xE60A0C10),
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: borderSubtle, width: 1),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accentAmber,
        inactiveTrackColor: borderSubtle,
        thumbColor: Colors.white,
        overlayColor: accentAmber.withValues(alpha: 0.18),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceElevated,
        selectedColor: accentAmber.withValues(alpha: 0.22),
        side: const BorderSide(color: borderSubtle),
        labelStyle: const TextStyle(color: textPrimary, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceElevated,
        contentTextStyle: const TextStyle(color: textPrimary, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: borderSubtle),
        ),
      ),
    );
  }
}
