import 'package:flutter/material.dart';

import '../features/career_analysis/career_analysis_screen.dart';
import '../theme/app_colors.dart';

/// Shown after the user replaces the CV in the profile.
///
/// The saved AI Career Analysis, CV review, and certification matches belong
/// to the old CV, so the user is offered to run AI Career Analysis again.
Future<void> showAnalysisUpdatePrompt(BuildContext context) async {
  final runNow = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: AppColors.softBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        icon: Icon(
          Icons.auto_awesome_rounded,
          color: AppColors.tealText,
          size: 32,
        ),
        title: Text(
          'Update Your Results',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.navyText,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'Your new CV is saved. Run AI Career Analysis again so your analysis, CV review, and certification matches are updated.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.secondaryText,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Later',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Run Analysis',
              style: TextStyle(
                color: AppColors.tealText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      );
    },
  );

  if (runNow == true && context.mounted) {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CareerAnalysisScreen()),
    );
  }
}
