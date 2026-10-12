import 'package:flutter/material.dart';

class AppTheme {
  // Primary & Action Colors (WCAG AA verified >= 4.5:1 for body, >= 3:1 for large/UI)
  static const Color primaryGreen = Color(0xFF1B5E20); // 7.85:1 on white
  static const Color brandGreen = primaryGreen; // #1B5E20
  static const Color darkActionTint = Color(0xFF66BB6A); // 8.12:1 on dark bg
  static const Color darkButtonFill = Color(0xFF2E7D32); // 5.13:1 with white text

  // Glassmorphism Design Tokens
  static const Color scaffoldBg = Color(0xFFEAF1EC); // #EAF1EC
  static const Color warnOrange = Color(0xFFB34700); // #B34700
  static const Color amberChip = Color(0xFFF59E0B); // #F59E0B
  static const Color amberChipText = Color(0xFF2E1B00); // #2E1B00
  static const Color sosRed = Color(0xFFC62828); // #C62828
  static const double blurSigma = 18.0; // Shared glass blur sigma constant
  static const Color glassBorderColor = Color(0xBFFFFFFF); // 1px white at 75% opacity
  static const Color glassTopHighlight = Color(0xE6FFFFFF); // 1px white at 90% opacity
  static const Color glassShadowColor = Color(0x241B5E20); // rgba(27, 94, 32, 0.14)
  static const BoxShadow glassBoxShadow = BoxShadow(
    color: glassShadowColor,
    offset: Offset(0, 10),
    blurRadius: 28,
  );
  static const Color solidCardBorderColor = Color(0x0F14301F); // rgba(20, 48, 31, 0.06)
  static const Color solidCardShadowColor = Color(0x0F14301F); // rgba(20, 48, 31, 0.06)
  static const BoxShadow solidCardBoxShadow = BoxShadow(
    color: solidCardShadowColor,
    offset: Offset(0, 2),
    blurRadius: 8,
  );

  // Semantic Colors
  static const Color danger = sosRed; // 5.62:1 on white
  static const Color dangerDark = Color(0xFFFF8A80); // 8.40:1 on dark surface
  static const Color warningText = warnOrange; // #B34700
  static const Color warningDark = Color(0xFFFFAB91); // 9.10:1 on dark surface
  static const Color cautionAmber = amberChip; // Fill only, dark text #2E1B00
  static const Color success = Color(0xFF2E7D32); // 5.13:1 on white
  static const Color successDark = Color(0xFF81C784); // 8.60:1 on dark surface
  static const Color info = Color(0xFF0277BD); // 4.86:1 on white
  static const Color infoDark = Color(0xFF4FC3F7); // 8.90:1 on dark surface

  // Legacy and semantic aliases kept for clean call sites
  static const Color secondaryTerracotta = warningText;
  static const Color accentGold = cautionAmber;
  static const Color skyBlue = info;
  static const Color dangerRed = danger;
  static const Color successGreen = success;
  static const Color infoBlue = info;
  static const Color cautionAmberFill = amberChip;
  static const Color cautionAmberText = amberChipText;
  static const Color primaryGreenDarkFill = darkButtonFill;

  // Neutrals — Light
  static const Color textPrimaryLight = Color(0xFF14301F); // #14301F
  static const Color textSecondaryLight = Color(0xFF4C6355); // #4C6355
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceSolidLight = Color(0xFFFFFFFF);
  static const Color outlineLight = solidCardBorderColor;
  static const Color bgLight = scaffoldBg;

  // Neutrals — Dark
  static const Color darkBg = Color(0xFF12110B);
  static const Color surfaceCard = Color(0xFF1A201C);
  static const Color surfaceDark = Color(0xE01A201C);
  static const Color textPrimaryDark = Color(0xFFF2F5F2);
  static const Color textSecondaryDark = Color(0xFFB8C4B9);
  static const Color outlineDark = Color(0x26FFFFFF);

  // Spacing Scale: 4 / 8 / 12 / 16 / 24 / 32
  static const double s4 = 4.0;
  static const double s8 = 8.0;
  static const double s12 = 12.0;
  static const double s16 = 16.0;
  static const double s24 = 24.0;
  static const double s32 = 32.0;
  static const double screenPadding = 16.0;

  // Radii: 12 (inputs, chips), 20 (cards, sheets), 999 (pills)
  static const double rInput = 12.0;
  static const double rChip = 12.0;
  static const double rCard = 20.0;
  static const double rSheet = 20.0;
  static const double rPill = 999.0;

  // Typography Scale (line-height >= 1.4 for Devanagari legibility)
  static const TextStyle heroTempStyle = TextStyle(
    fontSize: 64,
    fontWeight: FontWeight.w800,
    height: 1.05,
    letterSpacing: -1.5,
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
    fontWeight: FontWeight.w400,
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
        Theme.of(context).cardTheme.shape is RoundedRectangleBorder &&
            ((Theme.of(context).cardTheme.shape as RoundedRectangleBorder).side.width >= 2.0);
  }

  static Color primaryActionColor(BuildContext context) {
    if (isHighContrast(context)) return const Color(0xFF004D20);
    return Theme.of(context).brightness == Brightness.dark ? darkActionTint : primaryGreen;
  }

  static Color accentTint(BuildContext context) => primaryActionColor(context);

  static Color primaryButtonFill(BuildContext context) {
    if (isHighContrast(context)) return const Color(0xFF004D20);
    return Theme.of(context).brightness == Brightness.dark ? darkButtonFill : primaryGreen;
  }

  static Color textPrimary(BuildContext context) {
    if (isHighContrast(context)) return Colors.black;
    return Theme.of(context).brightness == Brightness.dark ? textPrimaryDark : textPrimaryLight;
  }

  static Color textSecondary(BuildContext context) {
    if (isHighContrast(context)) return const Color(0xFF1F1F1F);
    return Theme.of(context).brightness == Brightness.dark ? textSecondaryDark : textSecondaryLight;
  }

  static Color surfaceFill(BuildContext context) {
    if (isHighContrast(context)) return Colors.white;
    return Theme.of(context).brightness == Brightness.dark ? surfaceDark : surfaceLight;
  }

  static Color borderColor(BuildContext context) {
    if (isHighContrast(context)) return Colors.black;
    return Theme.of(context).brightness == Brightness.dark ? outlineDark : outlineLight;
  }

  static Color borderSubtle(BuildContext context) => borderColor(context);

  static double borderWidth(BuildContext context) {
    return isHighContrast(context) ? 2.0 : 1.0;
  }

  static Color semanticDangerText(BuildContext context) {
    if (isHighContrast(context)) return const Color(0xFFB71C1C);
    return Theme.of(context).brightness == Brightness.dark ? dangerDark : danger;
  }

  static Color semanticWarningText(BuildContext context) {
    if (isHighContrast(context)) return const Color(0xFF870000);
    return Theme.of(context).brightness == Brightness.dark ? warningDark : warningText;
  }

  static Color semanticSuccessText(BuildContext context) {
    if (isHighContrast(context)) return const Color(0xFF004D20);
    return Theme.of(context).brightness == Brightness.dark ? successDark : success;
  }

  static Color semanticInfoText(BuildContext context) {
    if (isHighContrast(context)) return const Color(0xFF01579B);
    return Theme.of(context).brightness == Brightness.dark ? infoDark : info;
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
        primary: primaryGreen,
        onPrimary: Colors.white,
        secondary: success,
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
          side: const BorderSide(color: outlineLight, width: 1),
        ),
        color: surfaceLight,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimaryLight,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceSolidLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: s16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: outlineLight, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: outlineLight, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: primaryGreen, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rInput)),
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 6,
        shadowColor: Colors.black26,
        backgroundColor: surfaceSolidLight,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryGreen.withValues(alpha: 0.14),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? primaryGreen : textSecondaryLight,
            height: 1.3,
          );
        }),
      ),
      extensions: const <ThemeExtension<dynamic>>[
        GlassTheme.light,
      ],
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
        secondary: successDark,
        onSecondary: Colors.black,
        error: dangerDark,
        onError: Colors.black,
        surface: surfaceCard,
        onSurface: textPrimaryDark,
        onSurfaceVariant: textSecondaryDark,
        outline: outlineDark,
        surfaceContainerHighest: Color(0xFF242C26),
      ),
      scaffoldBackgroundColor: darkBg,
      textTheme: _buildTextTheme(textPrimaryDark, textSecondaryDark),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rCard),
          side: const BorderSide(color: outlineDark, width: 1),
        ),
        color: surfaceDark,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimaryDark,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: s16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: outlineDark, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: outlineDark, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: darkActionTint, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rInput),
          borderSide: const BorderSide(color: dangerDark, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rInput)),
          backgroundColor: darkButtonFill,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 8,
        shadowColor: Colors.black54,
        backgroundColor: surfaceCard,
        surfaceTintColor: Colors.transparent,
        indicatorColor: darkActionTint.withValues(alpha: 0.2),
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
      extensions: const <ThemeExtension<dynamic>>[
        GlassTheme.dark,
      ],
    );
  }

  // Outdoor High-Contrast Theme for bright sunlight readability
  static ThemeData highContrastTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
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
        centerTitle: false,
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
          borderSide: const BorderSide(color: Color(0xFF004D20), width: 2.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rInput),
            side: const BorderSide(color: Colors.black, width: 2),
          ),
          backgroundColor: const Color(0xFF004D20),
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, height: 1.4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFF004D20),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: Colors.black,
            height: 1.3,
          );
        }),
      ),
      extensions: const <ThemeExtension<dynamic>>[
        GlassTheme.highContrast,
      ],
    );
  }
}

@immutable
class GlassTheme extends ThemeExtension<GlassTheme> {
  final Color scaffoldBg;
  final Color textPrimary;
  final Color textSecondary;
  final Color brandGreen;
  final Color warnOrange;
  final Color amberChip;
  final Color amberChipText;
  final Color sosRed;
  final double blurSigma;
  final Color glassBorderColor;
  final Color glassTopHighlight;
  final BoxShadow glassShadow;
  final Color solidCardColor;
  final Color solidCardBorderColor;
  final BoxShadow solidCardShadow;

  const GlassTheme({
    required this.scaffoldBg,
    required this.textPrimary,
    required this.textSecondary,
    required this.brandGreen,
    required this.warnOrange,
    required this.amberChip,
    required this.amberChipText,
    required this.sosRed,
    required this.blurSigma,
    required this.glassBorderColor,
    required this.glassTopHighlight,
    required this.glassShadow,
    required this.solidCardColor,
    required this.solidCardBorderColor,
    required this.solidCardShadow,
  });

  static const GlassTheme light = GlassTheme(
    scaffoldBg: AppTheme.scaffoldBg,
    textPrimary: AppTheme.textPrimaryLight,
    textSecondary: AppTheme.textSecondaryLight,
    brandGreen: AppTheme.brandGreen,
    warnOrange: AppTheme.warnOrange,
    amberChip: AppTheme.amberChip,
    amberChipText: AppTheme.amberChipText,
    sosRed: AppTheme.sosRed,
    blurSigma: AppTheme.blurSigma,
    glassBorderColor: AppTheme.glassBorderColor,
    glassTopHighlight: AppTheme.glassTopHighlight,
    glassShadow: AppTheme.glassBoxShadow,
    solidCardColor: Colors.white,
    solidCardBorderColor: AppTheme.solidCardBorderColor,
    solidCardShadow: AppTheme.solidCardBoxShadow,
  );

  static const GlassTheme dark = GlassTheme(
    scaffoldBg: AppTheme.darkBg,
    textPrimary: AppTheme.textPrimaryDark,
    textSecondary: AppTheme.textSecondaryDark,
    brandGreen: AppTheme.darkActionTint,
    warnOrange: AppTheme.warningDark,
    amberChip: AppTheme.amberChip,
    amberChipText: AppTheme.amberChipText,
    sosRed: AppTheme.sosRed,
    blurSigma: AppTheme.blurSigma,
    glassBorderColor: Color(0x3DFFFFFF),
    glassTopHighlight: Color(0x59FFFFFF),
    glassShadow: BoxShadow(
      color: Color(0x47000000),
      offset: Offset(0, 10),
      blurRadius: 28,
    ),
    solidCardColor: AppTheme.surfaceCard,
    solidCardBorderColor: AppTheme.outlineDark,
    solidCardShadow: BoxShadow(
      color: Color(0x3D000000),
      offset: Offset(0, 2),
      blurRadius: 8,
    ),
  );

  static const GlassTheme highContrast = GlassTheme(
    scaffoldBg: Colors.white,
    textPrimary: Colors.black,
    textSecondary: Color(0xFF1F1F1F),
    brandGreen: Color(0xFF004D20),
    warnOrange: Color(0xFF870000),
    amberChip: AppTheme.amberChip,
    amberChipText: Colors.black,
    sosRed: Color(0xFFB71C1C),
    blurSigma: 0.0,
    glassBorderColor: Colors.black,
    glassTopHighlight: Colors.transparent,
    glassShadow: BoxShadow(color: Colors.transparent),
    solidCardColor: Colors.white,
    solidCardBorderColor: Colors.black,
    solidCardShadow: BoxShadow(color: Colors.transparent),
  );

  @override
  GlassTheme copyWith({
    Color? scaffoldBg,
    Color? textPrimary,
    Color? textSecondary,
    Color? brandGreen,
    Color? warnOrange,
    Color? amberChip,
    Color? amberChipText,
    Color? sosRed,
    double? blurSigma,
    Color? glassBorderColor,
    Color? glassTopHighlight,
    BoxShadow? glassShadow,
    Color? solidCardColor,
    Color? solidCardBorderColor,
    BoxShadow? solidCardShadow,
  }) {
    return GlassTheme(
      scaffoldBg: scaffoldBg ?? this.scaffoldBg,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      brandGreen: brandGreen ?? this.brandGreen,
      warnOrange: warnOrange ?? this.warnOrange,
      amberChip: amberChip ?? this.amberChip,
      amberChipText: amberChipText ?? this.amberChipText,
      sosRed: sosRed ?? this.sosRed,
      blurSigma: blurSigma ?? this.blurSigma,
      glassBorderColor: glassBorderColor ?? this.glassBorderColor,
      glassTopHighlight: glassTopHighlight ?? this.glassTopHighlight,
      glassShadow: glassShadow ?? this.glassShadow,
      solidCardColor: solidCardColor ?? this.solidCardColor,
      solidCardBorderColor: solidCardBorderColor ?? this.solidCardBorderColor,
      solidCardShadow: solidCardShadow ?? this.solidCardShadow,
    );
  }

  @override
  GlassTheme lerp(ThemeExtension<GlassTheme>? other, double t) {
    if (other is! GlassTheme) return this;
    return GlassTheme(
      scaffoldBg: Color.lerp(scaffoldBg, other.scaffoldBg, t) ?? scaffoldBg,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      brandGreen: Color.lerp(brandGreen, other.brandGreen, t) ?? brandGreen,
      warnOrange: Color.lerp(warnOrange, other.warnOrange, t) ?? warnOrange,
      amberChip: Color.lerp(amberChip, other.amberChip, t) ?? amberChip,
      amberChipText: Color.lerp(amberChipText, other.amberChipText, t) ?? amberChipText,
      sosRed: Color.lerp(sosRed, other.sosRed, t) ?? sosRed,
      blurSigma: t < 0.5 ? blurSigma : other.blurSigma,
      glassBorderColor: Color.lerp(glassBorderColor, other.glassBorderColor, t) ?? glassBorderColor,
      glassTopHighlight: Color.lerp(glassTopHighlight, other.glassTopHighlight, t) ?? glassTopHighlight,
      glassShadow: BoxShadow.lerp(glassShadow, other.glassShadow, t) ?? glassShadow,
      solidCardColor: Color.lerp(solidCardColor, other.solidCardColor, t) ?? solidCardColor,
      solidCardBorderColor: Color.lerp(solidCardBorderColor, other.solidCardBorderColor, t) ?? solidCardBorderColor,
      solidCardShadow: BoxShadow.lerp(solidCardShadow, other.solidCardShadow, t) ?? solidCardShadow,
    );
  }
}
