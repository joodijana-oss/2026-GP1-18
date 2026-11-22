import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'signup_screen.dart';
import '../theme/app_colors.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  // Dark-mode button colours, taken from the sun and the glowing road in the
  // dark picture: a lighter gold for the right end of the gradient, and the
  // light-mode navy for the label so it stays dark on the gold.
  static const Color _lightGold = Color(0xFFF7CB6B);
  static const Color _navyOnGold = Color(0xFF06365A);

  // The background picture and the logo of each mode.
  static const String _lightBackground =
      'lib/assets/images/welcome_background.PNG';
  static const String _darkBackground =
      'lib/assets/images/welcome_background_dark.png';
  static const String _lightLogo = 'lib/assets/images/Logoo.png';
  static const String _darkLogo = 'lib/assets/images/logo_dark_mode.png';

  // The four pictures, each with the listener that holds it while the page
  // is open (see didChangeDependencies).
  final List<(ImageStream, ImageStreamListener)> _heldPictures = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load the pictures of both modes when the page opens, not only the two
    // on screen, and hold them until it closes. If the theme changes while
    // the page is open (Appearance on Auto and the phone switches), the other
    // two are then ready and show in the same frame, instead of a blank
    // background and logo while they load. Being in the image cache is not
    // enough: Android warns of low memory each time the app goes to the
    // background (for example while the user opens Settings to change the
    // theme), and Flutter then empties the cache except for the pictures
    // that something still listens to. The two on screen are asked for
    // first. Each picture is decoded at its own size, as Image.asset does, so
    // nothing looks different; all four are smaller than a 1080 x 2400
    // screen.
    //
    // Done once. This method runs again when the screen size or the phone's
    // theme changes, but each picture has a single size (no 2x or 3x
    // copies), so the ones already held stay right. Asking again would not
    // help and could lose them: right after a low-memory warning a new
    // request has to wait for the list of files, so swapping the old request
    // for the new one would let go of the picture in between.
    if (_heldPictures.isNotEmpty) return;
    final isDark = AppColors.isDark;
    final onScreen = isDark
        ? [_darkBackground, _darkLogo]
        : [_lightBackground, _lightLogo];
    final other = isDark
        ? [_lightBackground, _lightLogo]
        : [_darkBackground, _darkLogo];
    final configuration = createLocalImageConfiguration(context);
    for (final picture in [...onScreen, ...other]) {
      final stream = AssetImage(picture).resolve(configuration);
      final listener = ImageStreamListener(
        // Only holds the picture; the Image widgets draw it.
        (image, synchronousCall) => image.dispose(),
        // Reported quietly, as precacheImage does. A picture on screen also
        // shows its own error.
        onError: (error, stackTrace) => FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'image resource service',
            context: ErrorDescription('while loading a welcome page picture'),
            silent: true,
          ),
        ),
      );
      stream.addListener(listener);
      _heldPictures.add((stream, listener));
    }
  }

  @override
  void didHaveMemoryPressure() {
    // The same warning also empties the list of the app's files that
    // AssetImage reads to find a picture, and on a phone reading it again
    // takes a moment. Read it again now, while the app is in the background,
    // so the first frame after a theme change does not wait for it with no
    // background and logo. If it fails, AssetImage reads it again later, as
    // before.
    AssetManifest.loadFromAssetBundle(DefaultAssetBundle.of(context)).ignore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Let go of the pictures. The image cache then keeps or drops them as it
    // does any other picture.
    for (final (stream, listener) in _heldPictures) {
      stream.removeListener(listener);
    }
    super.dispose();
  }

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
    // Read on every build (not stored) so the page swaps pictures when the
    // theme changes while it is open: main.dart rebuilds every widget then.
    final isDark = AppColors.isDark;

    final page = Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ==========================
          // BACKGROUND IMAGE
          // ==========================
          // The light picture in light mode. In dark mode, the dark picture
          // instead: navy sky, teal hills and a golden road to the sun.
          Positioned.fill(
            child: Image.asset(
              isDark ? _darkBackground : _lightBackground,
              fit: BoxFit.cover,
            ),
          ),

          // ==========================
          // VERY LIGHT OVERLAY
          // ==========================
          // Only on the light picture; the dark picture is shown as it is.
          if (!isDark)
            Positioned.fill(
              child: Container(
                color: AppColors.onBrand.withValues(alpha: 0.02),
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
                    // The navy logo on the light picture. On the dark picture,
                    // the white logo with the coloured road and compass. Both
                    // files have the same shape, so the layout does not move.
                    isDark ? _darkLogo : _lightLogo,
                    width: size.width * 0.62,
                    fit: BoxFit.contain,
                  ),

                  const SizedBox(height: 14),

                  // ==========================
                  // GUIDE • DEVELOP • ACHIEVE
                  // ==========================
                  Text(
                    // The wide look comes from letterSpacing, not from
                    // spaces between letters, so the line fits on small
                    // phones and screen readers read whole words.
                    'GUIDE • DEVELOP • ACHIEVE',
                    semanticsLabel: 'Guide, develop, achieve',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      // Fixed colours picked for each picture, not the theme's
                      // text colours: grey-blue on the light picture, pale
                      // teal-white on the dark one.
                      color: isDark
                          ? AppColors.onBrandTeal
                          : const Color(0xFF60788C),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 3.5,
                    ),
                  ),

                  const Spacer(),

                  // ==========================
// GET STARTED BUTTON
// ==========================
// Navy to teal on the light picture. In dark mode, gold with a navy label,
// matching the sun and the road, so the first tap stands out.
Container(
  width: double.infinity,
  height: 60,
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(20),
    gradient: LinearGradient(
      colors: isDark
          ? [AppColors.gold, _lightGold]
          : [
              AppColors.navy,
              AppColors.secondaryNavy,
              AppColors.teal,
            ],
    ),
    boxShadow: [
      BoxShadow(
        color: isDark
            ? AppColors.gold.withValues(alpha: 0.38)
            : AppColors.teal.withValues(alpha: 0.24),
        blurRadius: isDark ? 22 : 18,
        offset: const Offset(0, 8),
      ),
    ],
  ),
  child: ElevatedButton(
    onPressed: () => goToSignUp(context),
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      foregroundColor: isDark ? _navyOnGold : AppColors.onBrand,
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

    // In dark mode, ask for light status bar icons so they show on the navy
    // sky. Flutter keeps the last style it was given, so after a screen with
    // a cream app bar (such as Explore) the icons would stay dark here. Only
    // the status bar changes, not the navigation bar. Light mode sets
    // nothing, as before.
    if (!isDark) return page;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: page,
    );
  }
}