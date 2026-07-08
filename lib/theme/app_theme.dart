import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants.dart';

class AppTheme {
  static ThemeData getLightTheme(Color primaryColor) {
    final baseTextTheme = ThemeData.light().textTheme;
    
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: GoogleFonts.interTextTheme(baseTextTheme).copyWith(
        headlineLarge: GoogleFonts.oswald(fontWeight: FontWeight.bold, color: AppColors.textDark),
        headlineMedium: GoogleFonts.oswald(fontWeight: FontWeight.bold, color: AppColors.textDark),
        headlineSmall: GoogleFonts.oswald(fontWeight: FontWeight.bold, color: AppColors.textDark),
        titleLarge: GoogleFonts.oswald(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.textDark),
        titleMedium: GoogleFonts.oswald(fontWeight: FontWeight.w600, color: AppColors.textDark),
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        surface: const Color(0xFFF5F5F5), // Slightly off-white surface
        onSurface: AppColors.textDark,
        surfaceContainerHighest: AppColors.surfaceWhite,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.surfaceWhite,
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2, // Added slight elevation for depth
        shadowColor: AppColors.cardShadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.m),
          side: const BorderSide(color: AppColors.borderGray, width: 1),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor, // Make App Bar Primary color by default for depth
        elevation: 4,
        centerTitle: false,
        titleTextStyle: GoogleFonts.oswald(
          color: Colors.white, // White text on deep background
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.borderGray),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.s),
          borderSide: const BorderSide(color: AppColors.borderGray),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.s),
          borderSide: const BorderSide(color: AppColors.borderGray),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.s),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        labelStyle: GoogleFonts.inter(color: AppColors.textLight),
        hintStyle: GoogleFonts.inter(color: AppColors.textLight.withValues(alpha: 0.5)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
        ),
      ),
    );
  }

  static ThemeData getDarkTheme(Color primaryColor) {
    // OLED Deep Black palette
    const darkBg = Color(0xFF000000); // Pure Black
    const darkSurface = Color(0xFF0A0A0A); // Very deep gray for cards
    const darkBorder = Color(0xFF1A1F1A); // Subtle dark border
    
    // Reduce lightening for dark mode to keep it deep
    final Color effectivePrimary = HSLColor.fromColor(primaryColor)
        .withLightness((HSLColor.fromColor(primaryColor).lightness + 0.05).clamp(0.0, 0.9))
        .toColor();

    final baseTextTheme = const TextTheme(
      headlineLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      bodyLarge: TextStyle(color: Color(0xFFE0E0E0)),
      bodyMedium: TextStyle(color: Color(0xFFE0E0E0)),
      bodySmall: TextStyle(color: Color(0xFFB0B0B0)),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: GoogleFonts.interTextTheme(baseTextTheme).copyWith(
        headlineLarge: GoogleFonts.oswald(fontWeight: FontWeight.bold, color: Colors.white),
        headlineMedium: GoogleFonts.oswald(fontWeight: FontWeight.bold, color: Colors.white),
        headlineSmall: GoogleFonts.oswald(fontWeight: FontWeight.bold, color: Colors.white),
        titleLarge: GoogleFonts.oswald(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
        titleMedium: GoogleFonts.oswald(fontWeight: FontWeight.w600, color: Colors.white),
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: effectivePrimary,
        secondary: effectivePrimary.withValues(alpha: 0.7),
        surface: darkSurface,
        onSurface: const Color(0xFFE0E0E0),
        onSurfaceVariant: const Color(0xFFB0B0B0),
        surfaceContainerHighest: const Color(0xFF121212),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: darkBg,
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0, 
        shadowColor: Colors.black.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.m),
          side: const BorderSide(color: darkBorder),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkBg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.oswald(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      dividerTheme: const DividerThemeData(color: darkBorder),
      listTileTheme: const ListTileThemeData(
        iconColor: Colors.white70,
        textColor: Colors.white,
      ),
      iconTheme: const IconThemeData(color: Color(0xFFB0B0B0)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0F0F0F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.s),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.s),
          borderSide: const BorderSide(color: darkBorder),
        ),
        labelStyle: GoogleFonts.inter(color: const Color(0xFFB0B0B0)),
        hintStyle: GoogleFonts.inter(color: const Color(0xFF757575)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: effectivePrimary,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: effectivePrimary,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
        ),
      ),
    );
  }
}
