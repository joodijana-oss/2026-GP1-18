import 'package:flutter/material.dart';
import 'package:masra/screens/email_action_screen.dart';
import 'package:masra/screens/reset_password_screen.dart';
import 'package:masra/screens/splash_screen.dart';
import 'package:masra/theme/app_colors.dart';
import 'package:masra/theme/app_theme.dart';
import 'package:masra/theme/theme_controller.dart';
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

  // The user's saved light / dark choice (Profile > Appearance)
  await ThemeController.instance.load();

  // Must be added before runApp (see PasswordResetLinkObserver)
  WidgetsBinding.instance.addObserver(PasswordResetLinkObserver(navigatorKey));

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

// Applies the light / dark choice from ThemeController (Profile >
// Appearance): Auto follows the phone, Light and Dark are fixed.
class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final ThemeController _theme = ThemeController.instance;

  @override
  void initState() {
    super.initState();
    AppColors.isDark = _theme.isDark;
    _theme.addListener(_applyTheme);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _theme.removeListener(_applyTheme);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The phone switched between light and dark while the app is open.
  @override
  void didChangePlatformBrightness() => _theme.phoneBrightnessChanged();

  void _applyTheme() {
    if (_theme.isDark == AppColors.isDark) return;

    setState(() => AppColors.isDark = _theme.isDark);

    // AppColors are plain getters, so widgets don't know they changed.
    // Ask every widget on screen to rebuild; nothing loses its state.
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Masra',

      // Masra theme (light or dark, from AppColors.isDark)
      theme: AppTheme.current,

      // يمنع الـ bounce والتمطيط في كل صفحات التطبيق
      scrollBehavior: const MasraScrollBehavior(),

      navigatorKey: navigatorKey,

      // First screen: SplashScreen by default.
      // App opened from a link (cold start): if it's a reset password link,
      // open ResetPasswordScreen on top of Splash. Splash still decides the
      // start screen underneath without replacing the reset screen.
      // Same for an email change link (EmailActionScreen).
      onGenerateInitialRoutes: (initialRoute) {
        final code = resetCodeFromLink(initialRoute);
        final emailAction = emailActionFromLink(initialRoute);

        return [
          MaterialPageRoute(
            settings: const RouteSettings(name: '/'),
            builder: (context) => const SplashScreen(),
          ),
          if (code != null)
            MaterialPageRoute(
              builder: (context) => ResetPasswordScreen(oobCode: code),
            )
          else if (emailAction != null)
            MaterialPageRoute(
              builder: (context) => EmailActionScreen(
                mode: emailAction.mode,
                oobCode: emailAction.oobCode,
              ),
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