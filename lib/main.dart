import 'package:flutter/material.dart';
import 'package:masra/screens/onboarding_screen.dart';
import 'package:masra/theme/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Masra',

      // Masra theme
      theme: AppTheme.lightTheme,

      // يمنع الـ bounce والتمطيط في كل صفحات التطبيق
      scrollBehavior: const MasraScrollBehavior(),

      // First screen
      home: const OnboardingScreen(),
    );
  }
}

// ============================================================
// GLOBAL SCROLL BEHAVIOR
// يمنع التمطيط / overscroll effect
// ============================================================

class MasraScrollBehavior extends MaterialScrollBehavior {
  const MasraScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}