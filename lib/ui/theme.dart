import 'package:flutter/material.dart';

import '../core/app_state.dart';

/// Colors of one business, so it is always obvious which side is open.
class Palette {
  const Palette({required this.primary, required this.dark, required this.soft, required this.accent});

  final Color primary;
  final Color dark;
  final Color soft;
  final Color accent;
}

/// المعرض: deep blue with a warm amber accent.
const showroomPalette = Palette(
  primary: Color(0xFF1C4E8C),
  dark: Color(0xFF12345E),
  soft: Color(0xFFE7EEF8),
  accent: Color(0xFFF0A23B),
);

/// التجارة: field green with a wheat gold accent.
const tradePalette = Palette(
  primary: Color(0xFF2F6B33),
  dark: Color(0xFF1E4721),
  soft: Color(0xFFE9F2E4),
  accent: Color(0xFFD4A03A),
);

/// Login and setup screens, before a business is open.
const neutralPalette = Palette(
  primary: Color(0xFF28435F),
  dark: Color(0xFF1A2D40),
  soft: Color(0xFFE9EEF3),
  accent: Color(0xFFD4A03A),
);

class AppColors {
  static Palette get palette {
    if (!app.hasDb) return neutralPalette;
    return app.isCrops ? tradePalette : showroomPalette;
  }

  static Color get primary => palette.primary;
  static Color get primarySoft => palette.soft;
  static Color get accent => palette.accent;

  static const crops = Color(0xFF2F6B33);
  static const cropsSoft = Color(0xFFE9F2E4);
  static const appliances = Color(0xFF1C4E8C);
  static const appliancesSoft = Color(0xFFE7EEF8);
  static const accounts = Color(0xFF6B4C9A);
  static const accountsSoft = Color(0xFFF0EBF7);
  static const good = Color(0xFF1E8A4C);
  static const goodSoft = Color(0xFFE5F4EB);
  static const bad = Color(0xFFC0392B);
  static const badSoft = Color(0xFFFBEAE8);
  static const warn = Color(0xFFD3790A);
  static const warnSoft = Color(0xFFFCF1E2);
  static const bg = Color(0xFFF3F5F7);
  static const border = Color(0xFFDFE4E9);
  static const text = Color(0xFF17202A);
  static const muted = Color(0xFF687481);

  /// Paper of the account page (صفحة الحساب).
  static const paper = Color(0xFFFFFCF2);
  static const paperLine = Color(0xFFE8DFC4);
  static const paperMargin = Color(0xFFE08A8A);
  static const ink = Color(0xFF1F2A44);
}

ThemeData buildTheme(Palette p) {
  final scheme = ColorScheme.fromSeed(
    seedColor: p.primary,
    primary: p.primary,
    secondary: p.accent,
    surface: Colors.white,
  );
  const font = 'Plex';
  final radius = BorderRadius.circular(14);
  OutlineInputBorder border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c, width: w));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: font,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0.6,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: font, fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.text),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(AppColors.border),
      enabledBorder: border(AppColors.border),
      focusedBorder: border(p.primary, 1.8),
      errorBorder: border(AppColors.bad),
      focusedErrorBorder: border(AppColors.bad, 1.8),
      labelStyle: const TextStyle(color: AppColors.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: font, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: const BorderSide(color: AppColors.border),
        textStyle: const TextStyle(fontFamily: font, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontFamily: font, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: Colors.white,
        selectedBackgroundColor: p.soft,
        selectedForegroundColor: p.primary,
        side: const BorderSide(color: AppColors.border),
        textStyle: const TextStyle(fontFamily: font, fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.soft,
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? p.primary : AppColors.muted),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: font,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? p.primary : AppColors.muted,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: p.soft,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: const TextStyle(fontFamily: font, fontSize: 13, color: AppColors.text),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1, thickness: 1),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
      titleTextStyle: TextStyle(fontFamily: font, fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text),
      subtitleTextStyle: TextStyle(fontFamily: font, fontSize: 13, color: AppColors.muted),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.primary,
      foregroundColor: Colors.white,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary),
  );
}
