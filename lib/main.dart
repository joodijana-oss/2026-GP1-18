import 'package:flutter/material.dart';
import 'package:masra/screens/reset_password_screen.dart';
import 'package:masra/screens/splash_screen.dart';
import 'package:masra/theme/app_theme.dart';
import 'package:masra/utils/password_reset_link.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// Used to open the reset password screen from a link while the app is open
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Must be added before runApp (see PasswordResetLinkObserver)
  WidgetsBinding.instance.addObserver(PasswordResetLinkObserver(navigatorKey));

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

      navigatorKey: navigatorKey,

      // First screen: SplashScreen by default.
      // App opened from a link (cold start): if it's a reset password link,
      // open ResetPasswordScreen on top of Splash. Splash still decides the
      // start screen underneath without replacing the reset screen.
      onGenerateInitialRoutes: (initialRoute) {
        final code = resetCodeFromLink(initialRoute);

        return [
          MaterialPageRoute(
            settings: const RouteSettings(name: '/'),
            builder: (context) => const SplashScreen(),
          ),
          if (code != null)
            MaterialPageRoute(
              builder: (context) => ResetPasswordScreen(oobCode: code),
            ),
        ];
      },

      // Required fallback now that there is no `home:` (WidgetsApp asserts
      // that one exists). The app doesn't use named routes, so any name
      // just opens Splash.
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: settings,
        builder: (context) => const SplashScreen(),
      ),
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