import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  /// Theme for the current mode. Built from [AppColors], so set
  /// [AppColors.isDark] before reading it.
  static ThemeData get current {
    final brightness = AppColors.isDark ? Brightness.dark : Brightness.light;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,

      // =========================
      // GENERAL
      // =========================
      scaffoldBackgroundColor: AppColors.background,

      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.navy,
        brightness: brightness,
        primary: AppColors.isDark ? AppColors.tealText : AppColors.navy,
        onPrimary: AppColors.isDark ? AppColors.background : AppColors.onBrand,
        secondary: AppColors.teal,
        surface: AppColors.background,
        onSurface: AppColors.darkText,
      ),

      fontFamily: 'Arial',

      // =========================
      // APP BAR
      // =========================
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.navyText,
        elevation: 0,
        centerTitle: false,
      ),

      // =========================
      // BUTTONS
      // =========================
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: AppColors.onBrand,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 16,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      ),

      // =========================
      // TEXT FIELDS
      // =========================
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.softBackground,

        hintStyle: TextStyle(
          color: AppColors.secondaryText,
        ),

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.lightGray,
          ),
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.lightGray,
          ),
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.tealText,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
