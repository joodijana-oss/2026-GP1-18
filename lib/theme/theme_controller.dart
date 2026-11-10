import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the user picked in Profile > Appearance.
enum AppThemeChoice { system, light, dark }

/// Remembers the user's light / dark choice on this device and tells the
/// app when it changes.
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const String _prefsKey = 'theme_choice';

  AppThemeChoice _choice = AppThemeChoice.system;
  AppThemeChoice get choice => _choice;

  /// True when the app should be dark right now.
  bool get isDark {
    switch (_choice) {
      case AppThemeChoice.light:
        return false;
      case AppThemeChoice.dark:
        return true;
      case AppThemeChoice.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    }
  }

  /// Reads the saved choice. Call once before runApp.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      _choice = AppThemeChoice.values.firstWhere(
        (c) => c.name == saved,
        orElse: () => AppThemeChoice.system,
      );
    } catch (_) {
      _choice = AppThemeChoice.system;
    }
  }

  Future<void> setChoice(AppThemeChoice choice) async {
    if (choice == _choice) return;
    _choice = choice;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, choice.name);
    } catch (_) {
      // Not saved: the choice still applies until the app is closed.
    }
  }

  /// Call when the phone's own light / dark setting changes.
  void phoneBrightnessChanged() {
    if (_choice == AppThemeChoice.system) notifyListeners();
  }
}
