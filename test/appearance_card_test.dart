import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masra/theme/theme_controller.dart';
import 'package:masra/widgets/appearance_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Appearance card changes and saves the theme choice',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController.instance;
    await theme.load();
    expect(theme.choice, AppThemeChoice.system);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppearanceCard())),
    );
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(theme.choice, AppThemeChoice.dark);
    expect(theme.isDark, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_choice'), 'dark');

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(theme.isDark, isFalse);

    // A fresh load (like reopening the app) restores the saved choice.
    await theme.setChoice(AppThemeChoice.dark);
    await theme.load();
    expect(theme.choice, AppThemeChoice.dark);

    await theme.setChoice(AppThemeChoice.system);
  });
}
