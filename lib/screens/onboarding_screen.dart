import 'package:flutter/material.dart';
import 'signup_screen.dart';
import '../theme/app_colors.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  void goToSignUp(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SignupScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ==========================
          // BACKGROUND IMAGE
          // ==========================
          Positioned.fill(
            child: Image.asset(
              'lib/assets/images/welcome_background.PNG',
              fit: BoxFit.cover,
            ),
          ),

          // ==========================
          // VERY LIGHT OVERLAY
          // ==========================
          Positioned.fill(
            child: Container(
              color: AppColors.white.withValues(alpha: 0.02),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  SizedBox(height: size.height * 0.20),

                  // ==========================
                  // MASRA LOGO
                  // ==========================
                  Image.asset(
                    'lib/assets/images/Logoo.png',
                    width: size.width * 0.62,
                    fit: BoxFit.contain,
                  ),

                  const SizedBox(height: 14),

                  // ==========================
                  // GUIDE • DEVELOP • ACHIEVE
                  // ==========================
                  const Text(
                    'G U I D E   •   D E V E L O P   •   A C H I E V E',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 2.2,
                    ),
                  ),

                  const Spacer(),

                  // ==========================
// GET STARTED BUTTON
// ==========================
Container(
  width: double.infinity,
  height: 60,
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(20),
    gradient: const LinearGradient(
      colors: [
        AppColors.navy,
        AppColors.secondaryNavy,
        AppColors.teal,
      ],
    ),
    boxShadow: [
      BoxShadow(
        color: AppColors.teal.withValues(
          alpha: 0.24,
        ),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  ),
  child: ElevatedButton(
    onPressed: () => goToSignUp(context),
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      foregroundColor: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),
    child: const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Let's Get Started",
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(width: 10),
        Icon(
          Icons.arrow_forward_rounded,
          size: 22,
        ),
      ],
    ),
  ),
),
                  const SizedBox(height: 34),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}