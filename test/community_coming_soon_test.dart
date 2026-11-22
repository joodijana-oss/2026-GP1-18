import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masra/features/career_comparator/career_comparator_screen.dart';
import 'package:masra/features/community/community_screen.dart';
import 'package:masra/features/heatmap/heatmap_screen.dart';
import 'package:masra/features/job_match/job_match_screen.dart';
import 'package:masra/features/learning_roadmap/learning_roadmap_screen.dart';
import 'package:masra/features/mock_interview/mock_interview_screen.dart';
import 'package:masra/features/project_discovery/project_discovery_screen.dart';
import 'package:masra/theme/app_colors.dart';
import 'package:masra/widgets/feature_placeholder.dart';

// Community shows the same "Coming soon" page as the other features that
// are not built yet, under its own header, and the shared page scrolls
// instead of cutting off its pill with large text or on a small phone. No
// Firebase app is needed.

const _description =
    'Connect with other Computing students and graduates, ask questions and share your progress.';

/// A page with an "Open" button that pushes Community, as Home, Explore and
/// Profile do.
Widget _launcher() {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CommunityScreen()),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

void _setSurface(WidgetTester tester, Size size, {double textScale = 1}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (textScale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
}

/// This text inside the shared "Coming soon" page body.
Finder _inBody(String text) => find.descendant(
  of: find.byType(ComingSoonMessage),
  matching: find.text(text),
);

void main() {
  testWidgets('Community shows the Coming soon page under its header', (
    tester,
  ) async {
    await tester.pumpWidget(_launcher());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.groups_2_outlined), findsOneWidget);
    // Once in the header and once in the body
    expect(find.text('Community'), findsNWidgets(2));
    expect(_inBody('Community'), findsOneWidget);
    expect(find.text(_description), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);

    // The back arrow is still the only button, and it still goes back
    expect(find.byType(IconButton), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityScreen), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('the Coming soon page is centred across the screen', (
    tester,
  ) async {
    _setSurface(tester, const Size(390, 844));
    await tester.pumpWidget(const MaterialApp(home: CommunityScreen()));

    expect(tester.getCenter(_inBody('Community')).dx, 195);
    expect(tester.getCenter(find.text('Coming soon')).dx, 195);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'no layout errors on a 320 phone in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        AppColors.isDark = dark;
        addTearDown(() => AppColors.isDark = false);
        _setSurface(tester, const Size(320, 568));
        await tester.pumpWidget(const MaterialApp(home: CommunityScreen()));

        expect(tester.takeException(), isNull);
        expect(find.text('Coming soon'), findsOneWidget);
      },
    );
  }

  // Before the page could scroll, these cut off the pill (by 37 and 228).
  for (final (size, textScale) in [
    (const Size(360, 640), 1.3),
    (const Size(390, 844), 2.0),
  ]) {
    testWidgets('large text scrolls to the pill (${size.width.toInt()} wide, '
        'text size $textScale)', (tester) async {
      _setSurface(tester, size, textScale: textScale);
      await tester.pumpWidget(const MaterialApp(home: CommunityScreen()));

      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Coming soon'));
      await tester.pumpAndSettle();
      final pill = tester.getRect(find.text('Coming soon'));
      expect(pill.top, greaterThanOrEqualTo(0));
      expect(pill.bottom, lessThanOrEqualTo(size.height));
    });
  }

  testWidgets('the six placeholder pages still use the same page', (
    tester,
  ) async {
    const pages = <(Widget, String, String)>[
      (
        CareerComparatorScreen(),
        'Career Path Comparator',
        'Compare different career paths and discover which one fits you best.',
      ),
      (
        LearningRoadmapScreen(),
        'Personalized Learning Roadmap',
        'Follow a personalized path to develop the skills you need.',
      ),
      (
        ProjectDiscoveryScreen(),
        'Smart Project Discovery',
        'Discover GitHub projects matched to your skills and interests.',
      ),
      (
        JobMatchScreen(),
        'Job Match',
        'Compare your profile with job requirements and discover your match.',
      ),
      (
        MockInterviewScreen(),
        'AI Mock Interview Simulator',
        'Practice realistic interviews and improve your interview skills with AI.',
      ),
      (
        HeatmapScreen(),
        'Job Demand Heatmap',
        'Explore job demand and career opportunities across Saudi Arabia.',
      ),
    ];

    for (final (page, title, description) in pages) {
      await tester.pumpWidget(MaterialApp(home: page));

      expect(_inBody(title), findsOneWidget, reason: title);
      expect(_inBody(description), findsOneWidget, reason: title);
      expect(_inBody('Coming soon'), findsOneWidget, reason: title);
    }
  });
}
