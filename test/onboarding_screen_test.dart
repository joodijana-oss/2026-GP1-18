import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masra/screens/onboarding_screen.dart';
import 'package:masra/theme/app_colors.dart';
import 'package:masra/theme/app_theme.dart';

// The welcome page shows the light picture with the navy logo in light mode,
// and the new dark picture with the white logo (coloured road and compass)
// in dark mode. No Firebase app is needed, and the button is never tapped
// (it opens Sign Up, which needs Firebase).
//
// Roboto is loaded under the name 'Arial' (the theme's font) before the
// tests. The default test font draws every letter as a full square, wider
// than any real font, so the button text would "overflow" in a test but not
// on a phone. Android shows Roboto for 'Arial', since the app does not
// bundle Arial.

const _lightBackground = 'lib/assets/images/welcome_background.PNG';
const _darkBackground = 'lib/assets/images/welcome_background_dark.png';
const _lightLogo = 'lib/assets/images/Logoo.png';
const _darkLogo = 'lib/assets/images/logo_dark_mode.png';
const _tagline = 'GUIDE • DEVELOP • ACHIEVE';

/// Loads Roboto from the Flutter SDK as the 'Arial' family.
Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    fail('FLUTTER_ROOT is not set, so Roboto cannot be found. '
        'Run this file with "flutter test".');
  }
  final dir = '$root/bin/cache/artifacts/material_fonts';
  final loader = FontLoader('Arial');
  for (final name in [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ]) {
    final file = File('$dir/$name');
    if (!file.existsSync()) {
      fail('${file.path} is missing, so the page would be measured with the '
          'square test font instead of Roboto.');
    }
    loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await loader.load();
}

/// Finds the Image widgets that show the bundled picture [name].
Finder _asset(String name) => find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName == name,
    );

/// Shows the welcome page in light or dark mode on a screen of [size]
/// logical pixels, with its pictures loaded so the logo has its real height.
Future<void> _showWelcome(
  WidgetTester tester, {
  required bool dark,
  Size size = const Size(411, 914),
}) async {
  AppColors.isDark = dark;
  addTearDown(() => AppColors.isDark = false);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.current, home: const OnboardingScreen()),
  );

  // Pictures do not load by themselves in a widget test, so load each one
  // now. This also proves every picture is in the app bundle and decodes.
  final context = tester.element(find.byType(OnboardingScreen));
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  final errors = <Object>[];
  await tester.runAsync(() async {
    for (final image in images) {
      await precacheImage(
        image.image,
        context,
        onError: (error, _) => errors.add(error),
      );
    }
  });
  await tester.pump();
  expect(errors, isEmpty);
}

Color? _taglineColor(WidgetTester tester) =>
    tester.widget<Text>(find.text(_tagline)).style?.color;

BoxDecoration _buttonDecoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .ancestor(
          of: find.byType(ElevatedButton),
          matching: find.byType(Container),
        )
        .first,
  );
  return container.decoration! as BoxDecoration;
}

List<Color> _buttonGradient(WidgetTester tester) =>
    (_buttonDecoration(tester).gradient! as LinearGradient).colors;

List<BoxShadow>? _buttonGlow(WidgetTester tester) =>
    _buttonDecoration(tester).boxShadow;

/// Finds the faint cream layer that sits over the light picture.
Finder _lightOverlay() => find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.color == AppColors.onBrand.withValues(alpha: 0.02),
    );

/// Finds the status bar style the page asks for, if it asks for one.
Finder _statusBarStyle() => find.byWidgetPredicate(
      (widget) => widget is AnnotatedRegion<SystemUiOverlayStyle>,
    );

Color? _buttonLabelColor(WidgetTester tester) => tester
    .widget<ElevatedButton>(find.byType(ElevatedButton))
    .style
    ?.foregroundColor
    ?.resolve(<WidgetState>{});

/// Reads the PNG header: width, height, bit depth and colour type.
List<int> _pngHeader(ByteData data) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  for (var i = 0; i < signature.length; i++) {
    expect(data.getUint8(i), signature[i], reason: 'not a PNG file');
  }
  return [
    data.getUint32(16),
    data.getUint32(20),
    data.getUint8(24),
    data.getUint8(25),
  ];
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  testWidgets('dark mode shows the dark picture and the white logo',
      (tester) async {
    await _showWelcome(tester, dark: true);

    expect(_asset(_darkBackground), findsOneWidget);
    expect(_asset(_darkLogo), findsOneWidget);
    expect(_asset(_lightBackground), findsNothing);
    expect(_asset(_lightLogo), findsNothing);

    expect(_taglineColor(tester), AppColors.onBrandTeal);
    expect(
      _buttonGradient(tester),
      const [Color(0xFFF2B544), Color(0xFFF7CB6B)],
    );
    expect(_buttonLabelColor(tester), const Color(0xFF06365A));

    // No cream layer over the dark picture, and a gold glow under the button.
    expect(_lightOverlay(), findsNothing);
    expect(_buttonGlow(tester), [
      BoxShadow(
        color: const Color(0xFFF2B544).withValues(alpha: 0.38),
        blurRadius: 22,
        offset: const Offset(0, 8),
      ),
    ]);

    // Light status bar icons, so they show on the navy sky. The navigation
    // bar is left alone.
    final style = tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(_statusBarStyle())
        .value;
    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.statusBarBrightness, Brightness.dark);
    expect(style.systemNavigationBarColor, isNull);
    expect(style.systemNavigationBarIconBrightness, isNull);
  });

  testWidgets('light mode keeps the light picture and the navy logo',
      (tester) async {
    await _showWelcome(tester, dark: false);

    expect(_asset(_lightBackground), findsOneWidget);
    expect(_asset(_lightLogo), findsOneWidget);
    expect(_asset(_darkBackground), findsNothing);
    expect(_asset(_darkLogo), findsNothing);

    expect(_taglineColor(tester), const Color(0xFF60788C));
    expect(
      _buttonGradient(tester),
      const [Color(0xFF06365A), Color(0xFF0B4F6C), Color(0xFF0B91A6)],
    );
    expect(_buttonLabelColor(tester), AppColors.onBrand);

    // The faint cream layer and the teal glow stay as they were, and the
    // page still leaves the status bar style alone.
    expect(_lightOverlay(), findsOneWidget);
    expect(_buttonGlow(tester), [
      BoxShadow(
        color: const Color(0xFF0B91A6).withValues(alpha: 0.24),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ]);
    expect(_statusBarStyle(), findsNothing);
  });

  testWidgets('the page follows a theme change while it is open',
      (tester) async {
    await _showWelcome(tester, dark: false);
    expect(_asset(_lightLogo), findsOneWidget);

    // Rebuild every widget, the way main.dart does when the theme changes.
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    AppColors.isDark = true;
    tester.binding.rootElement!.visitChildren(rebuild);
    await tester.pump();
    expect(_asset(_darkBackground), findsOneWidget);
    expect(_asset(_darkLogo), findsOneWidget);
    expect(_asset(_lightLogo), findsNothing);
    expect(_taglineColor(tester), AppColors.onBrandTeal);
    expect(
      _buttonGradient(tester),
      const [Color(0xFFF2B544), Color(0xFFF7CB6B)],
    );
    expect(_lightOverlay(), findsNothing);
    expect(_statusBarStyle(), findsOneWidget);

    AppColors.isDark = false;
    tester.binding.rootElement!.visitChildren(rebuild);
    await tester.pump();
    expect(_asset(_lightBackground), findsOneWidget);
    expect(_asset(_lightLogo), findsOneWidget);
    expect(_asset(_darkLogo), findsNothing);
    expect(_taglineColor(tester), const Color(0xFF60788C));
    expect(
      _buttonGradient(tester),
      const [Color(0xFF06365A), Color(0xFF0B4F6C), Color(0xFF0B91A6)],
    );
    expect(_lightOverlay(), findsOneWidget);
    expect(_statusBarStyle(), findsNothing);
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('fits a small phone in $mode mode', (tester) async {
      const screen = Size(320, 568);
      await _showWelcome(tester, dark: dark, size: screen);

      expect(find.text("Let's Get Started"), findsOneWidget);
      // A RenderFlex overflow would be reported here.
      expect(tester.takeException(), isNull);

      final button = tester.getRect(find.byType(ElevatedButton));
      expect(button.left, greaterThanOrEqualTo(0));
      expect(button.right, lessThanOrEqualTo(screen.width));
      expect(button.bottom, lessThanOrEqualTo(screen.height));

      final logo = tester.getRect(_asset(dark ? _darkLogo : _lightLogo));
      expect(logo.height, greaterThan(0));
      expect(logo.top, greaterThanOrEqualTo(0));
    });
  }

  test('the new pictures are real PNGs of the right size', () async {
    // Loading through rootBundle also proves pubspec bundles them.
    final logo = _pngHeader(await rootBundle.load(_darkLogo));
    // 990 x 397, 8 bits per channel, colour type 6 (red, green, blue, alpha).
    expect(logo, [990, 397, 8, 6]);

    final background = _pngHeader(await rootBundle.load(_darkBackground));
    // The original picture, not enlarged.
    expect(background.sublist(0, 2), [733, 1600]);
  });

  testWidgets('the dark-mode logo is truly see-through, with no checker '
      'squares', (tester) async {
    final data = await rootBundle.load(_darkLogo);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    late ByteData rgba;
    late int width;
    late int height;
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      width = frame.image.width;
      height = frame.image.height;
      // Straight (not premultiplied) colours, so half-transparent edge
      // pixels keep their real colour instead of looking grey.
      rgba = (await frame.image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!;
    });

    int alphaAt(int x, int y) => rgba.getUint8((y * width + x) * 4 + 3);
    expect(alphaAt(0, 0), 0);
    expect(alphaAt(width - 1, 0), 0);
    expect(alphaAt(0, height - 1), 0);
    expect(alphaAt(width - 1, height - 1), 0);

    final total = width * height;
    var clear = 0;
    var solid = 0;
    var greyResidue = 0;
    for (var i = 0; i < total; i++) {
      final r = rgba.getUint8(i * 4);
      final g = rgba.getUint8(i * 4 + 1);
      final b = rgba.getUint8(i * 4 + 2);
      final a = rgba.getUint8(i * 4 + 3);
      if (a == 0) clear++;
      if (a == 255) solid++;
      if (a < 13) continue;
      // The checker squares were grey (red, green and blue nearly equal)
      // and darker than the white letters. A visible pixel like that would
      // be a leftover square or a grey edge.
      final spread = [r, g, b].reduce((x, y) => x > y ? x : y) -
          [r, g, b].reduce((x, y) => x < y ? x : y);
      final lum = (r + g + b) ~/ 3;
      if (spread < 20 && lum < 215) greyResidue++;
    }
    expect(clear / total, greaterThan(0.5));
    expect(solid / total, greaterThan(0.15));
    expect(greyResidue, lessThanOrEqualTo(20));
  });
}
