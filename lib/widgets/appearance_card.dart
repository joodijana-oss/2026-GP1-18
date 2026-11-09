import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';

/// Profile card that lets the user pick Auto / Light / Dark.
class AppearanceCard extends StatelessWidget {
  const AppearanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final current = ThemeController.instance.choice;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.softBackground,
            borderRadius: BorderRadius.circular(27),
            border: Border.all(
              color: AppColors.lightGray.withValues(alpha: 0.85),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.045),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.tealText.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.palette_outlined,
                      color: AppColors.tealText,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Appearance',
                          style: TextStyle(
                            color: AppColors.navyText,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Choose light or dark mode.',
                          style: TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.lightGray.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    _option(
                      choice: AppThemeChoice.system,
                      current: current,
                      icon: Icons.phone_android_rounded,
                      label: 'Auto',
                    ),
                    _option(
                      choice: AppThemeChoice.light,
                      current: current,
                      icon: Icons.light_mode_outlined,
                      label: 'Light',
                    ),
                    _option(
                      choice: AppThemeChoice.dark,
                      current: current,
                      icon: Icons.dark_mode_outlined,
                      label: 'Dark',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _option({
    required AppThemeChoice choice,
    required AppThemeChoice current,
    required IconData icon,
    required String label,
  }) {
    final selected = choice == current;
    final foreground = selected ? AppColors.onBrand : AppColors.secondaryText;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label mode',
        child: InkWell(
          onTap: () => ThemeController.instance.setChoice(choice),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 44,
            decoration: BoxDecoration(
              color: selected ? AppColors.teal : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
