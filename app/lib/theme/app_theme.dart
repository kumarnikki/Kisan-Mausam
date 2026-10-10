import 'package:flutter/material.dart';

class AppTheme {
  // Agriculture-focused color palette
  static const Color primaryGreen = Color(0xFF1B5E20);      // Deep Lush Crop Green
  static const Color secondaryTerracotta = Color(0xFFBF360C); // Fertile Soil / Terracotta
  static const Color accentGold = Color(0xFFF9A825);        // Ripe Wheat Gold
  static const Color skyBlue = Color(0xFF0288D1);           // Monsoon Rain Blue
  static const Color darkBg = Color(0xFF0D1B12);            // Deep Forest Night
  static const Color surfaceCard = Color(0xFF162B1D);       // Dark card background

  static ThemeData lightTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGreen,
        brightness: Brightness.light,
        primary: const Color(0xFF1B5E20),
        onPrimary: Colors.white,
        secondary: const Color(0xFF388E3C),
        surface: const Color(0xFFF4F7F4),
        surfaceContainerHigh: Colors.white,
        error: const Color(0xFFBA1A1A),
      ),
      scaffoldBackgroundColor: const Color(0xFFF4F7F4),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52), // Large touch targets (>= 48 dp)
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF1B5E20),
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGreen,
        brightness: Brightness.dark,
        primary: const Color(0xFF4CAF50),
        onPrimary: Colors.black,
        secondary: const Color(0xFF81C784),
        surface: darkBg,
        surfaceContainerHigh: surfaceCard,
      ),
      scaffoldBackgroundColor: darkBg,
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: surfaceCard,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceCard,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF4CAF50),
          foregroundColor: Colors.black,
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // Outdoor High-Contrast Theme for bright sunlight readability
  static ThemeData highContrastTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF004D20),
        onPrimary: Colors.white,
        secondary: Color(0xFFB71C1C),
        onSecondary: Colors.white,
        error: Color(0xFFB71C1C),
        onError: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black,
        surfaceContainerHigh: Color(0xFFE0E0E0),
      ),
      scaffoldBackgroundColor: Colors.white,
      cardTheme: CardThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.black, width: 2),
        ),
        color: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Colors.black, width: 2),
          ),
          backgroundColor: const Color(0xFF004D20),
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}
