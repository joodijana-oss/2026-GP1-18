import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:masra/services/user_service.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'profile_setup_screen.dart';

// ============================================================
// SPLASH SCREEN
// أول شاشة تفتح: تشيك هل المستخدم مسجل دخول وتوديه للمكان الصح
// ============================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _decideStartScreen();
  }

  Future<void> _decideStartScreen() async {
    // الافتراضي: مستخدم مو مسجل يروح للـ Onboarding
    Widget next = const OnboardingScreen();

    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        // 1) الأدمن ما يدخل التطبيق
        final token = await user.getIdTokenResult();

        if (token.claims?['admin'] == true) {
          await FirebaseAuth.instance.signOut();
        } else {
          // 2) هل البروفايل مكتمل؟
          final data = await UserService().getUser();
          final completed = data?['profileCompleted'] == true;

          next = completed ? const HomeScreen() : const ProfileSetupScreen();
        }
      } catch (_) {
        // لو صار خطأ (مثلاً ما فيه نت) يروح للـ Onboarding،
        // وتسجيل دخوله يبقى محفوظ للمرة الجاية
      }
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => next),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.secondaryNavy,
              AppColors.navy,
              AppColors.teal,
            ],
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Masra',
              style: TextStyle(
                color: AppColors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: 24),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}