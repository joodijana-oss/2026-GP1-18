import 'package:flutter/material.dart';

/// Masra colours, for light and dark mode.
///
/// Every colour is a getter that returns the light or the dark value
/// depending on [AppColors.isDark] (set by ThemeController from the phone's
/// setting). Because of that these colours cannot be used inside `const`
/// expressions.
///
/// Three groups:
///  - Fill colours (navy, teal, white, background...): backgrounds, cards,
///    buttons. Brand fills stay brand-coloured in dark mode; surfaces go dark.
///  - Text colours (navyText, tealText, darkText...): text, icons and borders
///    drawn ON a surface. They become light in dark mode.
///  - "onBrand" colours: text and icons drawn on a brand fill (navy header,
///    primary button). They are the same in both modes.
class AppColors {
  /// True while the app is showing its dark theme.
  static bool isDark = false;

  static Color _pick(int light, int dark) => Color(isDark ? dark : light);

  // =========================
  // BRAND FILLS
  // =========================

  // اللون الكحلي الأساسي - نفس زر الصفحة الترحيبية
  static Color get navy => _pick(0xFF06365A, 0xFF0B3D63);

  // كحلي ثانوي
  static Color get secondaryNavy => _pick(0xFF0B4F6C, 0xFF0F5676);

  // التركواز الأساسي
  static Color get teal => _pick(0xFF0B91A6, 0xFF0B91A6);

  // تركواز فاتح للخلفيات والكروت
  static Color get lightTeal => _pick(0xFFDCEEF1, 0xFF103845);

  // الذهبي المستوحى من الشمس والطريق
  static Color get gold => _pick(0xFFF2B544, 0xFFF2B544);

  // =========================
  // SURFACES
  // =========================

  // الأبيض الأساسي للتطبيق (#FDF8F3) - كروت وأسطح
  static Color get white => _pick(0xFFFDF8F3, 0xFF13212B);

  // الخلفية الأساسية
  static Color get background => _pick(0xFFFDF8F3, 0xFF0B161E);

  // خلفية خفيفة للكروت والحقول
  static Color get softBackground => _pick(0xFFFFFCF8, 0xFF13212B);

  // =========================
  // NEUTRALS (borders, dividers, disabled)
  // =========================

  static Color get lightGray => _pick(0xFFE6EAED, 0xFF243540);

  static Color get mediumGray => _pick(0xFFB8C2C8, 0xFF5B6C78);

  // =========================
  // TEXT / ICONS / BORDERS ON A SURFACE
  // =========================

  // العناوين
  static Color get darkText => _pick(0xFF06365A, 0xFFE4EEF3);

  // النصوص الثانوية (GUIDE • DEVELOP • ACHIEVE)
  static Color get secondaryText => _pick(0xFF60788C, 0xFF9DB0BD);

  static Color get navyText => _pick(0xFF06365A, 0xFFE4EEF3);

  static Color get secondaryNavyText => _pick(0xFF0B4F6C, 0xFFB9CFDA);

  static Color get tealText => _pick(0xFF0B91A6, 0xFF43C6DA);

  // =========================
  // ON BRAND FILLS (same in light and dark)
  // =========================

  static const Color onBrand = Color(0xFFFDF8F3);

  static const Color onBrandTeal = Color(0xFFDCEEF1);

  static const Color onBrandGray = Color(0xFFE6EAED);

  static const Color onBrandMuted = Color(0xFFB8C2C8);
}
