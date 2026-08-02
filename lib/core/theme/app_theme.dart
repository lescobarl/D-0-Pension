import 'package:flutter/material.dart';
import '../models/app_metadata.dart';

/// Application theme based on Excel executive colors.
/// Primary: Verde Petroleo (#004D40), Accent: Dorado (#C5A059).
/// Colors can be overridden via [ThemeConfig] from metadata JSON.
///
/// MOBILE-FIRST DESIGN:
/// - Responsive fonts that scale well on phones and tablets
/// - Compact spacing to maximize screen real estate
/// - High contrast for readability on small screens
/// - Touch-friendly targets (minimum 44px)
class AppTheme {
  AppTheme._();

  // Default palette (Verde Petroleo / Dorado)
  static const Color primary = Color(0xFF004D40);
  static const Color primaryLight = Color(0xFF39796B);
  static const Color primaryDark = Color(0xFF00251A);
  static const Color accent = Color(0xFFC5A059);
  static const Color accentLight = Color(0xFFF9D18B);
  static const Color accentDark = Color(0xFF92712B);
  static const Color backgroundLight = Color(0xFFF5F5F5);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF424242);
  static const Color textHint = Color(0xFF9E9E9E);
  static const Color errorColor = Color(0xFFD32F2F);
  static const Color successColor = Color(0xFF2E7D32);
  static const Color warningColor = Color(0xFFF57C00);
  static const Color dividerColor = Color(0xFFE0E0E0);

  // Font size constants for mobile-first design
  // Optimized for phone screens (360-430px width)
  static const double fontSizeTab = 13;
  static const double fontSizeTabSmall = 11;
  static const double fontSizeBody = 15;
  static const double fontSizeBodySmall = 13;
  static const double fontSizeLabel = 14;
  static const double fontSizeInput = 15;
  static const double fontSizeSectionTitle = 17;
  static const double fontSizeCardTitle = 16;
  static const double fontSizeResultValue = 16;
  static const double fontSizeTotalLarge = 28;
  static const double fontSizeTotalMedium = 22;
  static const double fontSizeIcon = 20;
  static const double fontSizeTableHeader = 12;
  static const double fontSizeTableData = 12;

  // Spacing constants
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 12;
  static const double spacingLg = 16;
  static const double spacingXl = 24;

  // Border radius
  static const double radiusSm = 8;
  static const double radiusMd = 10;
  static const double radiusLg = 12;

  /// Responsive font size helper - returns a size that works on mobile
  /// while being slightly larger on tablets/desktop.
  static double responsiveFont(BuildContext context, double baseSize) {
    final width = MediaQuery.of(context).size.width;
    if (width > 900) return baseSize + 2; // tablet/desktop
    if (width > 600) return baseSize + 1; // large phone
    return baseSize; // small phone
  }

  /// Parse a hex color string (e.g. "#004D40") to [Color].
  static Color _parseHex(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  /// Build a [ThemeData] from a [ThemeConfig] (loaded from metadata JSON).
  /// Falls back to default static colors if [config] is null.
  static ThemeData fromConfig(ThemeConfig? config) {
    final primaryColor = config != null
        ? _parseHex(config.primaryColor)
        : AppTheme.primary;
    final accentColor =
        config != null ? _parseHex(config.accentColor) : AppTheme.accent;
    final bgLight = config != null
        ? _parseHex(config.backgroundLight)
        : AppTheme.backgroundLight;
    final cardBg = config != null
        ? _parseHex(config.cardBackground)
        : AppTheme.cardBackground;
    final errColor =
        config != null ? _parseHex(config.errorColor) : AppTheme.errorColor;

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        secondary: accentColor,
        surface: cardBg,
        error: errColor,
      ),
      scaffoldBackgroundColor: bgLight,
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 48,
        titleTextStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: accentColor,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: fontSizeTab,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: fontSizeTabSmall,
        ),
        tabAlignment: TabAlignment.start,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        margin: const EdgeInsets.symmetric(horizontal: spacingSm, vertical: spacingXs),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 1,
          shadowColor: primaryColor.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontSize: fontSizeBody, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: BorderSide(color: primaryColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: errorColor, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: errorColor, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: spacingMd, vertical: spacingMd),
        labelStyle: TextStyle(fontSize: fontSizeLabel, color: textSecondary),
        hintStyle: TextStyle(fontSize: fontSizeBody, color: textHint),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryColor,
        inactiveTrackColor: primaryColor.withValues(alpha: 0.24),
        thumbColor: primaryColor,
        overlayColor: primaryColor.withValues(alpha: 0.12),
        valueIndicatorColor: primaryColor,
        valueIndicatorTextStyle: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
        trackHeight: 6,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
        valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
      ),
      dividerTheme: const DividerThemeData(
        space: spacingLg,
        thickness: 1,
        color: dividerColor,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primaryColor;
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primaryColor.withValues(alpha: 0.5);
          return null;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primaryColor;
          return null;
        }),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primaryColor,
        selectionHandleColor: primaryColor,
        selectionColor: primaryColor.withValues(alpha: 0.2),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: Colors.grey.shade800,
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }

  /// Convenience getter for the default theme (static colors).
  static ThemeData get lightTheme => fromConfig(null);
}
