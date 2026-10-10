import 'package:flutter/material.dart';

class AppTheme {
  // Primary 3D Lavender-Violet Brand Palette (matching reference UI)
  static const Color primaryViolet = Color(0xFF622CFD);
  static const Color primaryVioletDeep = Color(0xFF4B18D6);
  static const Color periwinkleTop = Color(0xFFA594FF);
  static const Color periwinkleMid = Color(0xFF8C75FF);
  static const Color periwinkleBottom = Color(0xFF7559F6);
  static const Color heroCardTop = Color(0xFFFBF9FF);
  static const Color heroCardBottom = Color(0xFFEDE7FF);

  // Kept as primaryGreen alias so all existing call sites use the new vibrant violet seamlessly
  static const Color primaryGreen = primaryViolet;
  static const Color darkActionTint = Color(0xFFA78BFA);
  static const Color darkButtonFill = Color(0xFF622CFD);

  // Semantic Colors
  static const Color danger = Color(0xFFD32F2F);
  static const Color dangerDark = Color(0xFFFF8A80);
  static const Color warningText = Color(0xFFC2410C);
  static const Color warningDark = Color(0xFFFFAB91);
  static const Color cautionAmber = Color(0xFFFFB800);
  static const Color success = Color(0xFF16A34A);
  static const Color successDark = Color(0xFF86EFAC);
  static const Color info = Color(0xFF4F46E5);
  static const Color infoDark = Color(0xFFA5B4FC);

  // Legacy and semantic aliases kept for clean call sites
  static const Color secondaryTerracotta = warningText;
  static const Color accentGold = cautionAmber;
  static const Color skyBlue = info;
  static const Color dangerRed = danger;
  static const Color successGreen = success;
  static const Color infoBlue = info;
  static const Color cautionAmberFill = cautionAmber;
  static const Color cautionAmberText = textPrimaryLight;
  static const Color primaryGreenDarkFill = darkButtonFill;

  // Neutrals — Light (Deep Indigo-Violet typography on Frosted Lavender-White surfaces)
  static const Color textPrimaryLight = Color(0xFF23154F);
  static const Color textSecondaryLight = Color(0xFF6E6295);
  static const Color surfaceLight = Color(0xF2F9F7FF);
  static const Color surfaceSolidLight = Color(0xFFFFFFFF);
  static const Color outlineLight = Color(0x28622CFD);
  static const Color bgLight = Color(0xFFEAE4FF);

  // Neutrals — Dark (Midnight Violet)
  static const Color darkBg = Color(0xFF120D24);
  static const Color surfaceCard = Color(0xFF1E1638);
  static const Color surfaceDark = Color(0xEB21183D);
  static const Color textPrimaryDark = Color(0xFFF6F4FF);
  static const Color textSecondaryDark = Color(0xFFC4B8E8);
  static const Color outlineDark = Color(0x33A78BFA);

  // Spacing Scale: 4 / 8 / 12 / 16 / 24 / 32
  static const double s4 = 4.0;
  static const double s8 = 8.0;
  static const double s12 = 12.0;
  static const double s16 = 16.0;
  static const double s24 = 24.0;
  static const double s32 = 32.0;
  static const double screenPadding = 16.0;

  // Radii: 16 (inputs, chips), 24 (cards, sheets), 999 (pills)
  static const double rInput = 16.0;
  static const double rChip = 16.0;
  static const double rCard = 24.0;
  static const double rSheet = 28.0;
  static const double rPill = 999.0;

  // Typography Scale
  static const TextStyle heroTempStyle = TextStyle(
    fontSize: 80,
    fontWeight: FontWeight.w800,
    height: 1.0,
    letterSpacing: -2.5,
  );

  static const TextStyle titleStyle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.4,
  );

  static const TextStyle sectionStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.4,
  );

  static const TextStyle bodyStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.45,
  );

  static const TextStyle labelStyle = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Duration motionDuration(BuildContext context, Duration base) {
    final disable = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return disable ? Duration.zero : base;
  }

  static bool isHighContrast(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return cs.primary == const Color(0xFF004D20) ||
        cs.primary == const Color(0xFF310096) ||
        (Theme.of(context).cardTheme.shape is RoundedRectangleBorder &&
            ((Theme.of(context).cardTheme.shape as RoundedRectangleBorder)
                    .side
                    .width >=
                2.0));
  }

  static Color primaryActionColor(BuildContext context) {
    if (isHighContrast(context)) return const Color(0xFF310096);
    return Theme.of(context).brightness == Brightness.dark
        ? darkActionTint
        : primaryViolet;
  }

  static Color accentTint(BuildContext context) => primaryActionColor(context);

  static Color primaryButtonFill(BuildContext context) {
    if (isHighContrast(context)) return const Color(0xFF310096);
    return Theme.of(context).brightness == Brightness.dark
        ? darkButtonFill
        : primaryViolet;
  }

  static Color textPrimary(BuildContext context) {
    if (isHighContrast(context)) return Colors.black;
    return Theme.of(context).brightness == Brightness.dark
        ? textPrimaryDark
        : textPrimaryLight;
  }

  static Color textSecondary(BuildContext context) {
    if (isHighContrast(context)) return const Color(0xFF1F1F1F);
    return Theme.of(context).brightness == Brightness.dark
        ? textSecondaryDark
        : textSecondaryLight;
  }

  static Color surfaceFill(BuildContext context) {
    if (isHighContrast(context)) return Colors.white;
    return Theme.of(context).brightness == Brightness.dark
        ? surfaceDark
        : surfaceLight;
  }

  static Color borderColor(BuildContext context) {
    if (isHighContrast(context)) return Colors.black;
    return Theme.of(context).brightness == Brightness.dark
        ? outlineDark
        : outlineLight;
  }

  static Color borderSubtle(BuildContext context) => borderColor(context);

  static double borderWidth(BuildContext context) {
    return isHighContrast(context) ? 2.0 : 1.2;
  }

  static Color semanticDangerText(BuildContext context) {
    if (isHighContrast(context)) return const Color(0xFFB71C1C);
    return Theme.of(context).brightness == Brightness.dark ? dangerDark : danger;
  }

  static Color semanticWarningText(BuildContext context) {
    if (isHighContrast(context)) return const Color(0xFF870000);
    return Theme.of(context).brightness == Brightness.dark
        ? warningDark
        : warningText;
  }

  static Color semanticSuccessText(BuildContext context) {
    if (isHighContrast(context)) return const Color(0xFF004D20);
    return Theme.of(context).brightness == Brightness.dark
        ? successDark
        : success;
  }

  static Color semanticInfoText(BuildContext context) {
    if (isHighContrast(context)) return const Color(0xFF310096);
    return Theme.of(context).brightness == Brightness.dark ? infoDark : info;
  }

  static List<BoxShadow> softShadow(BuildContext context) {
    if (isHighContrast(context)) return const [];
    final dark = isDark(context);
    return [
      BoxShadow(
        color: dark
            ? Colors.black.withValues(alpha: 0.35)
            : const Color(0xFF622CFD).withValues(alpha: 0.10),
        blurRadius: 24,
        offset: const Offset(0, 10),
      ),
    ];
  }

  static TextTheme _buildTextTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge: heroTempStyle.copyWith(color: primary),
      headlineMedium: titleStyle.copyWith(color: primary),
      titleLarge: titleStyle.copyWith(color: primary),
      titleMedium: sectionStyle.copyWith(color: primary),
      bodyLarge: bodyStyle.copyWith(color: primary),
      bodyMedium: bodyStyle.copyWith(color: primary),
      bodySmall: labelStyle.copyWith(color: secondary),
      labelLarge: labelStyle.copyWith(color: primary, fontSize: 14),
      labelMedium: labelStyle.copyWith(color: secondary),
    );
  }

  static ThemeData lightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: primaryViolet,
        onPrimary: Colors.white,
        secondary: primaryVioletDeep,
        onSecondary: Colors.white,
        error: danger,
        onError: Colors.white,
        surface: surfaceSolidLight,
        onSurface: textPrimaryLight,
        onSurfaceVariant: textSecondaryLight,
        outline: outlineLight,
        surfaceContainerHighest: bgLight,
      ),
      scaffoldBackgroundColor: bgLight,
      textTheme: _buildTextTheme(textPrimaryLight, textSecondaryLight),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rCard),
          side: const BorderSide(color: outlineLight, width: 1.2),
        ),
        color: surfaceLight,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimaryLight,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceSolidLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: s16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: outlineLight, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: outlineLight, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: primaryViolet, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 4,
          shadowColor: primaryViolet.withValues(alpha: 0.35),
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rPill)),
          backgroundColor: primaryViolet,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        elevation: 12,
        shadowColor: const Color(0xFF4B18D6).withValues(alpha: 0.18),
        backgroundColor: const Color(0xF6F7F5FF),
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryViolet.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? primaryViolet : textSecondaryLight,
            height: 1.3,
          );
        }),
      ),
    );
  }

  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: darkActionTint,
        onPrimary: Colors.white,
        secondary: primaryViolet,
        onSecondary: Colors.white,
        error: dangerDark,
        onError: Colors.black,
        surface: surfaceCard,
        onSurface: textPrimaryDark,
        onSurfaceVariant: textSecondaryDark,
        outline: outlineDark,
        surfaceContainerHighest: Color(0xFF2B2050),
      ),
      scaffoldBackgroundColor: darkBg,
      textTheme: _buildTextTheme(textPrimaryDark, textSecondaryDark),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rCard),
          side: const BorderSide(color: outlineDark, width: 1.2),
        ),
        color: surfaceDark,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimaryDark,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: s16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: outlineDark, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: outlineDark, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: darkActionTint, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: dangerDark, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 4,
          shadowColor: primaryViolet.withValues(alpha: 0.4),
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rPill)),
          backgroundColor: darkButtonFill,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        elevation: 10,
        shadowColor: Colors.black54,
        backgroundColor: surfaceCard,
        surfaceTintColor: Colors.transparent,
        indicatorColor: darkActionTint.withValues(alpha: 0.22),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? darkActionTint : textSecondaryDark,
            height: 1.3,
          );
        }),
      ),
    );
  }

  // Outdoor High-Contrast Theme for bright sunlight readability
  static ThemeData highContrastTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF310096),
        onPrimary: Colors.white,
        secondary: Color(0xFFB71C1C),
        onSecondary: Colors.white,
        error: Color(0xFFB71C1C),
        onError: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black,
        onSurfaceVariant: Color(0xFF1F1F1F),
        outline: Colors.black,
        surfaceContainerHighest: Color(0xFFE0E0E0),
      ),
      scaffoldBackgroundColor: Colors.white,
      textTheme: _buildTextTheme(Colors.black, const Color(0xFF1F1F1F)),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rCard),
          side: const BorderSide(color: Colors.black, width: 2),
        ),
        color: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: s16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: Colors.black, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: Colors.black, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: Color(0xFF310096), width: 2.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rPill),
            side: const BorderSide(color: Colors.black, width: 2),
          ),
          backgroundColor: const Color(0xFF310096),
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, height: 1.4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFF310096),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: Colors.black,
            height: 1.3,
          );
        }),
      ),
    );
  }
}
