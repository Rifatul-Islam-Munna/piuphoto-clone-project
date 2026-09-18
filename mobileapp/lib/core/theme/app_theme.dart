import 'package:flutter/material.dart';

/// Airpix design system.
///
/// The palette follows design.md: red-orange leads hierarchy, teal supports
/// secondary/info actions, yellow is reserved for highlights and status.
class AppColors {
  AppColors._();

  // design.md anchors.
  static const Color primary = Color(0xFFEA580C);
  static const Color primaryLight = Color(0xFFF97316);
  static const Color primaryDark = Color(0xFFC2410C);
  static const Color secondary = Color(0xFF0D9488);
  static const Color secondaryLight = Color(0xFF14B8A6);
  static const Color tertiary = Color(0xFFEAB308);

  static const Color gradientStart = primaryLight;
  static const Color gradientMiddle = primary;
  static const Color gradientEnd = primaryDark;

  static const Color background = Color(0xFFFFFFFF);
  static const Color foreground = Color(0xFF18181B);
  static const Color card = Colors.white;
  static const Color cardForeground = foreground;
  static const Color muted = Color(0xFFF7F7F6);
  static const Color mutedForeground = Color(0xFF71717A);
  static const Color border = Color(0xFFE7E5E4);
  static const Color input = Color(0xFFF5F5F4);
  static const Color destructive = Color(0xFFDC2626);
  static const Color destructiveForeground = Colors.white;
  static const Color darkSection = Color(0xFF18181B);
  static const Color cream = Color(0xFFFFF7ED);

  static const Color accentSoft = Color(0x14EA580C);
  static const Color secondarySoft = Color(0x140D9488);
  static const Color tertiarySoft = Color(0x18EAB308);
  static const Color surfaceHigh = Color(0xFFF5F5F4);
  static const Color surfaceWarm = Color(0xFFFFFBF7);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = tertiary;
  static const Color info = secondary;
}

class AppGradients {
  AppGradients._();

  static const LinearGradient brand = LinearGradient(
    colors: [
      AppColors.gradientStart,
      AppColors.gradientMiddle,
      AppColors.gradientEnd,
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient studio = LinearGradient(
    colors: [Color(0xFF27272A), Color(0xFF18181B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient subtleBrand = LinearGradient(
    colors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient discovery = LinearGradient(
    colors: [Color(0xFF0F766E), AppColors.secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppRadius {
  AppRadius._();

  static const double sm = 12;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 28;
}

class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppTextStyles {
  static const TextStyle title = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.foreground,
  );

  static const TextStyle subtitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.foreground,
  );

  static const TextStyle text = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.foreground,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.mutedForeground,
  );
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.secondary,
        onSecondary: Colors.white,
        tertiary: AppColors.tertiary,
        onTertiary: Color(0xFF422006),
        primaryContainer: Color(0xFFFFEDD5),
        onPrimaryContainer: AppColors.primaryDark,
        secondaryContainer: Color(0xFFCCFBF1),
        onSecondaryContainer: Color(0xFF115E59),
        tertiaryContainer: Color(0xFFFEF3C7),
        onTertiaryContainer: Color(0xFF713F12),
        surface: AppColors.card,
        onSurface: AppColors.foreground,
        surfaceContainerHighest: AppColors.muted,
        error: AppColors.destructive,
        onError: Colors.white,
        outline: AppColors.border,
        outlineVariant: AppColors.border,
      ),
      scaffoldBackgroundColor: AppColors.background,
      cardTheme: CardThemeData(
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 20,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.foreground,
          letterSpacing: -0.45,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.muted,
          disabledForegroundColor: AppColors.mutedForeground,
          elevation: 0,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.muted,
          disabledForegroundColor: AppColors.mutedForeground,
          elevation: 0,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.secondary,
          side: const BorderSide(color: AppColors.secondary),
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.secondary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.foreground),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.muted,
        hintStyle: const TextStyle(
          color: AppColors.mutedForeground,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: const TextStyle(
          color: AppColors.mutedForeground,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.destructive),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(
            color: AppColors.destructive,
            width: 1.4,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.muted,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.foreground,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.foreground,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: const BorderSide(color: AppColors.border),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.foreground,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.card,
        modalBackgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        dragHandleColor: AppColors.border,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.muted,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.mutedForeground,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.border,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.transparent,
        ),
        side: const BorderSide(color: AppColors.mutedForeground, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.foreground,
        unselectedLabelColor: AppColors.mutedForeground,
        indicatorColor: AppColors.primary,
        dividerColor: AppColors.border,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.foreground,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.card,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.mutedForeground,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: 34,
          height: 1.08,
          fontWeight: FontWeight.w700,
          color: AppColors.foreground,
          letterSpacing: -1.15,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          height: 1.12,
          fontWeight: FontWeight.w700,
          color: AppColors.foreground,
          letterSpacing: -0.8,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: AppColors.foreground,
          letterSpacing: -0.35,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          height: 1.25,
          fontWeight: FontWeight.w600,
          color: AppColors.foreground,
          letterSpacing: -0.1,
        ),
        titleSmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.foreground,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          height: 1.5,
          fontWeight: FontWeight.w400,
          color: AppColors.foreground,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.45,
          fontWeight: FontWeight.w400,
          color: AppColors.foreground,
        ),
        bodySmall: TextStyle(
          fontSize: 12.5,
          height: 1.4,
          fontWeight: FontWeight.w400,
          color: AppColors.mutedForeground,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.foreground,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.foreground,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.mutedForeground,
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primaryLight,
        onPrimary: Colors.white,
        secondary: AppColors.secondaryLight,
        onSecondary: Colors.white,
        tertiary: AppColors.tertiary,
        onTertiary: Color(0xFF422006),
        surface: Color(0xFF18181B),
        onSurface: Color(0xFFFAFAFA),
        surfaceContainerHighest: Color(0xFF27272A),
        error: AppColors.destructive,
        onError: Colors.white,
        outline: Color(0xFF3F3F46),
      ),
      scaffoldBackgroundColor: const Color(0xFF09090B),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF09090B),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }
}
