import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masra/features/career_analysis/career_analysis_screen.dart';
import 'package:masra/features/career_comparator/career_comparator_screen.dart';
import 'package:masra/features/certifications/certifications_screen.dart';
import 'package:masra/features/community/community_screen.dart';
import 'package:masra/features/cv_improvement/cv_improvement_screen.dart';
import 'package:masra/features/heatmap/heatmap_screen.dart';
import 'package:masra/features/job_match/job_match_screen.dart';
import 'package:masra/features/learning_roadmap/learning_roadmap_screen.dart';
import 'package:masra/features/mock_interview/mock_interview_screen.dart';
import 'package:masra/features/opportunities/opportunities_screen.dart';
import 'package:masra/features/project_discovery/project_discovery_screen.dart';
import 'package:masra/screens/explore_screen.dart';
import 'package:masra/screens/home_screen.dart';
import 'package:masra/theme/app_colors.dart';
import 'package:masra/widgets/feature_placeholder.dart';
import 'package:masra/widgets/soon_badge.dart';

// The "Soon" badge on every card and tile that opens a feature that is not
// built yet, the one list that decides which features those are, and the
// learning roadmap prompt that must stay as it is. Home and Explore are
// pumped without a Firebase app: their loads fail quietly and Home shows its
// recommendations error message instead of cards.
//
// The test font draws every letter as a square, so text wraps more than on
// a phone. Some tests use a wide or tall surface for that reason.

const _unbuiltScreens = <Widget>[
  CareerComparatorScreen(),
  LearningRoadmapScreen(),
  ProjectDiscoveryScreen(),
  JobMatchScreen(),
  MockInterviewScreen(),
  HeatmapScreen(),
];

const _builtScreens = <Widget>[
  CareerAnalysisScreen(),
  CertificationsScreen(),
  OpportunitiesScreen(),
  CVImprovementScreen(),
  CommunityScreen(),
];

const _unbuiltCards = [
  'Career Path Comparator',
  'Personalized Learning Roadmap',
  'Smart Project Discovery',
  'Job Match',
  'AI Mock Interview Simulator',
  'Job Demand Heatmap',
];

const _builtCards = [
  'AI Career Analysis',
  'Certification Recommender',
  'Opportunity Radar',
  'CV Improvement Assistant',
];

void _setSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void _setDark(bool dark) {
  AppColors.isDark = dark;
  addTearDown(() => AppColors.isDark = false);
}

/// The InkWell of the Explore card with this title.
Finder _exploreCard(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(InkWell)).first;

/// The tappable label under a Home quick action tile.
Finder _tileLabel(String label) => find
    .ancestor(of: find.text(label), matching: find.byType(GestureDetector))
    .first;

/// A "Soon" badge under this quick action tile's label.
Finder _tileBadge(String label) =>
    find.descendant(of: _tileLabel(label), matching: find.byType(SoonBadge));

Future<void> _pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  // Home's background animation repeats, so pumpAndSettle would never end.
  await tester.pump(const Duration(seconds: 2));
}

// Home loads the journey stage from Firestore, which tests don't have, so
// the stage is set on the screen's state directly.
Future<void> _setStage(WidgetTester tester, int stage) async {
  final dynamic state = tester.state(find.byType(HomeScreen));
  state.currentJourneyStage = stage;
  state.setState(() {});
  await tester.pump(const Duration(milliseconds: 100));
}

/// Where every "Soon" badge on the screen is drawn.
List<Rect> _badgeRects(WidgetTester tester) {
  final badges = find.byType(SoonBadge);
  return [
    for (var i = 0; i < badges.evaluate().length; i++)
      tester.getRect(badges.at(i)),
  ];
}

Color? _soonColor(WidgetTester tester, Finder badge) => tester
    .widget<Text>(find.descendant(of: badge, matching: find.text('Soon')))
    .style
    ?.color;

void main() {
  group('the one list of features that are not built yet', () {
    test('holds exactly the six unbuilt feature screens', () {
      expect(comingSoonScreens, {
        CareerComparatorScreen,
        LearningRoadmapScreen,
        ProjectDiscoveryScreen,
        JobMatchScreen,
        MockInterviewScreen,
        HeatmapScreen,
      });
    });

    test('isComingSoon is true only for those screens', () {
      for (final screen in _unbuiltScreens) {
        expect(isComingSoon(screen), isTrue, reason: '${screen.runtimeType}');
      }
      for (final screen in _builtScreens) {
        expect(isComingSoon(screen), isFalse, reason: '${screen.runtimeType}');
      }
      expect(isComingSoon(null), isFalse);
    });

    testWidgets('opensComingSoon checks a route builder the same way', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );

      expect(opensComingSoon(context, null), isFalse);
      for (final screen in _unbuiltScreens) {
        expect(opensComingSoon(context, (_) => screen), isTrue);
      }
      for (final screen in _builtScreens) {
        expect(opensComingSoon(context, (_) => screen), isFalse);
      }
    });

    // If a feature is built but left on the list, this fails and points to
    // the list in lib/widgets/soon_badge.dart.
    testWidgets('every screen on the list still opens the Coming soon page', (
      tester,
    ) async {
      for (final screen in _unbuiltScreens) {
        await tester.pumpWidget(MaterialApp(home: screen));
        expect(
          find.byType(FeaturePlaceholder),
          findsOneWidget,
          reason: '${screen.runtimeType}',
        );
        expect(find.text('Coming soon'), findsOneWidget);
      }
    });
  });

  group('the badge', () {
    Widget host(Widget badge) => MaterialApp(
      home: Scaffold(body: Center(child: badge)),
    );

    testWidgets('the big badge shows a clock and "Soon"', (tester) async {
      await tester.pumpWidget(host(const SoonBadge()));
      expect(find.text('Soon'), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    });

    testWidgets('the small badge shows "Soon" with no clock', (tester) async {
      await tester.pumpWidget(host(const SoonBadge(small: true)));
      expect(find.text('Soon'), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsNothing);
    });

    testWidgets('screen readers hear "Coming soon", not "Soon"', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(const SoonBadge()));
      expect(find.bySemanticsLabel('Coming soon'), findsOneWidget);
      expect(find.bySemanticsLabel('Soon'), findsNothing);
      semantics.dispose();
    });

    for (final dark in [false, true]) {
      testWidgets('text colours in ${dark ? 'dark' : 'light'} mode', (
        tester,
      ) async {
        _setDark(dark);
        await tester.pumpWidget(
          host(
            const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SoonBadge(key: ValueKey('plain')),
                SoonBadge(key: ValueKey('brand'), onBrand: true),
              ],
            ),
          ),
        );

        expect(
          _soonColor(tester, find.byKey(const ValueKey('plain'))),
          AppColors.navyText,
        );
        expect(
          _soonColor(tester, find.byKey(const ValueKey('brand'))),
          AppColors.onBrand,
        );
      });
    }

    // A quick action tile is about 62 wide on a 320 phone, and an Explore
    // card's text column about 140. The pill shrinks instead of overflowing.
    for (final scale in [1.0, 2.0]) {
      testWidgets('the badge fits a small phone at text size $scale', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(
          host(
            const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 62,
                  child: Column(
                    children: [SoonBadge(key: ValueKey('tile'), small: true)],
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [SoonBadge(key: ValueKey('card'))],
                  ),
                ),
              ],
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byKey(const ValueKey('tile'))).width,
          lessThanOrEqualTo(62),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('card'))).width,
          lessThanOrEqualTo(140),
        );
      });
    }
  });

  group('Explore', () {
    testWidgets(
      'the six unbuilt cards have the badge and the built ones do not',
      (tester) async {
        // Tall enough for the list to build every card
        _setSurface(tester, const Size(390, 2600));
        await tester.pumpWidget(const MaterialApp(home: ExploreScreen()));
        await tester.pump();

        for (final title in _unbuiltCards) {
          expect(
            find.descendant(
              of: _exploreCard(title),
              matching: find.text('Soon'),
            ),
            findsOneWidget,
            reason: title,
          );
        }
        for (final title in _builtCards) {
          expect(
            find.descendant(
              of: _exploreCard(title),
              matching: find.text('Soon'),
            ),
            findsNothing,
            reason: title,
          );
        }
        expect(find.text('Soon'), findsNWidgets(6));
      },
    );

    testWidgets('screen readers hear "Coming soon" with the card title', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      _setSurface(tester, const Size(390, 2600));
      await tester.pumpWidget(const MaterialApp(home: ExploreScreen()));
      await tester.pump();

      expect(
        tester.getSemantics(find.text('Job Match')).label,
        matches(RegExp(r'Job Match[\s\S]*Coming soon')),
      );
      expect(
        tester.getSemantics(find.text('Opportunity Radar')).label,
        isNot(contains('Coming soon')),
      );
      semantics.dispose();
    });

    testWidgets('tapping a card with the badge still opens its page', (
      tester,
    ) async {
      _setSurface(tester, const Size(390, 2600));
      await tester.pumpWidget(const MaterialApp(home: ExploreScreen()));
      await tester.pump();

      await tester.tap(find.text('Job Match'));
      await tester.pumpAndSettle();

      expect(find.byType(JobMatchScreen), findsOneWidget);
      expect(find.byType(FeaturePlaceholder), findsOneWidget);
      expect(find.text('Coming soon'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      testWidgets(
        'no layout errors on a 320 phone in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
          _setDark(dark);
          _setSurface(tester, const Size(320, 2600));
          await tester.pumpWidget(const MaterialApp(home: ExploreScreen()));
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.text('Soon'), findsNWidgets(6));
        },
      );
    }
  });

  group('Home', () {
    testWidgets('Match a Job and Practice Interview tiles have the badge', (
      tester,
    ) async {
      _setSurface(tester, const Size(390, 2600));
      await _pumpHome(tester);

      expect(_tileBadge('Match a Job'), findsOneWidget);
      expect(_tileBadge('Practice\nInterview'), findsOneWidget);
      expect(_tileBadge('Analyze CV'), findsNothing);
      expect(_tileBadge('Improve CV'), findsNothing);
      expect(tester.widget<SoonBadge>(_tileBadge('Match a Job')).small, isTrue);
    });

    testWidgets('screen readers hear "Coming soon" with the tile label', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      _setSurface(tester, const Size(390, 2600));
      await _pumpHome(tester);

      expect(
        find.bySemanticsLabel(RegExp(r'Match a Job[\s\S]*Coming soon')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Practice\nInterview[\s\S]*Coming soon')),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.text('Analyze CV')).label,
        isNot(contains('Coming soon')),
      );
      semantics.dispose();
    });

    // "Your Next Step" and Saudi Market Insight are not tapped as a whole,
    // so their button and link say "Coming soon" and the badge itself is
    // not read. Someone who jumps straight to the button still hears it.
    testWidgets('screen readers hear "Coming soon" on the button and link', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      _setSurface(tester, const Size(390, 2600));
      await _pumpHome(tester);

      expect(
        tester.getSemantics(find.text('Explore Market')),
        isSemantics(label: 'Explore Market, Coming soon', hasTapAction: true),
      );
      // Stage 0: the button opens Career Analysis, which is built
      expect(
        find.bySemanticsLabel(RegExp(r'Start Analysis[\s\S]*Coming soon')),
        findsNothing,
      );

      await _setStage(tester, 1);
      expect(
        tester.getSemantics(find.text('Continue')),
        isSemantics(label: 'Continue, Coming soon', hasTapAction: true),
      );

      // The tiles merge it into their label; nothing reads it on its own
      expect(find.bySemanticsLabel('Coming soon'), findsNothing);
      semantics.dispose();
    });

    testWidgets('tapping the Match a Job label still opens Job Match', (
      tester,
    ) async {
      _setSurface(tester, const Size(390, 2600));
      await _pumpHome(tester);

      await tester.tap(find.text('Match a Job'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(JobMatchScreen), findsOneWidget);
      expect(find.text('Coming soon'), findsOneWidget);
    });

    testWidgets('the Saudi Market Insight card has the badge under its link', (
      tester,
    ) async {
      _setSurface(tester, const Size(390, 2600));
      await _pumpHome(tester);

      final link = tester.getRect(find.text('Explore Market'));
      final underLink = _badgeRects(
        tester,
      ).where((rect) => rect.top >= link.bottom && rect.top < link.bottom + 40);

      expect(underLink, hasLength(1));
    });

    testWidgets('the next step has no badge when it opens Career Analysis', (
      tester,
    ) async {
      _setSurface(tester, const Size(390, 2600));
      await _pumpHome(tester);

      expect(find.text('Start Analysis'), findsWidgets);
      expect(
        find.byWidgetPredicate((w) => w is SoonBadge && w.onBrand),
        findsNothing,
      );
      // The two tiles and the market card
      expect(find.text('Soon'), findsNWidgets(3));
    });

    for (final (stage, button, description) in [
      (
        1,
        'Continue',
        'Based on your skill gaps, continue developing the skills needed for your career path.',
      ),
      (
        2,
        'Find Projects',
        'Work on hands-on projects that showcase your skills and strengthen your portfolio.',
      ),
      (
        3,
        'Practice Interview',
        'Practice interviews and polish your profile so you are ready to apply with confidence.',
      ),
    ]) {
      for (final dark in [false, true]) {
        testWidgets('the next step "$button" has a light badge in '
            '${dark ? 'dark' : 'light'} mode', (tester) async {
          _setDark(dark);
          _setSurface(tester, const Size(390, 2600));
          await _pumpHome(tester);
          await _setStage(tester, stage);

          expect(find.text(button), findsOneWidget);
          final badge = find.byWidgetPredicate(
            (w) => w is SoonBadge && w.onBrand,
          );
          expect(badge, findsOneWidget);
          expect(_soonColor(tester, badge), AppColors.onBrand);

          // Under the description and above the button
          final rect = tester.getRect(badge);
          expect(
            rect.top,
            greaterThanOrEqualTo(tester.getRect(find.text(description)).bottom),
          );
          expect(
            rect.bottom,
            lessThanOrEqualTo(tester.getRect(find.text(button)).top),
          );
          expect(find.text('Soon'), findsNWidgets(4));
        });
      }
    }

    // On a 640 surface the test font wraps the labels as a phone does:
    // "Match a Job" on one line and "Practice Interview" on two.
    testWidgets('the tile badges line up', (tester) async {
      _setSurface(tester, const Size(640, 2600));
      await _pumpHome(tester);

      final heights = [
        for (final label in [
          'Analyze CV',
          'Improve CV',
          'Match a Job',
          'Practice\nInterview',
        ])
          tester.getSize(find.text(label)).height,
      ];
      expect(heights.toSet(), hasLength(1));

      expect(
        tester.getTopLeft(_tileBadge('Match a Job')).dy,
        tester.getTopLeft(_tileBadge('Practice\nInterview')).dy,
      );
    });

    // In the test font Home at 320 wide already overflows in the next step
    // button row, the "Explore Masra" title row and its "View All Features"
    // button, before this change (it fits on a phone). So this test does
    // not expect zero errors. It fails on any error from the badge and
    // checks that every badge stays inside its tile or card.
    for (final dark in [false, true]) {
      testWidgets(
        'the badges fit a 320 phone in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
          _setDark(dark);
          _setSurface(tester, const Size(320, 2600));

          final errors = <String>[];
          final previous = FlutterError.onError;
          FlutterError.onError = (details) => errors.add(details.toString());
          try {
            await _pumpHome(tester);
            await _setStage(tester, 1);
          } finally {
            FlutterError.onError = previous;
          }

          expect(errors.where((e) => e.contains('soon_badge.dart')), isEmpty);

          for (final label in ['Match a Job', 'Practice\nInterview']) {
            // The tile's own Column: the label's Column is the closest
            final tile = tester.getRect(
              find
                  .ancestor(of: find.text(label), matching: find.byType(Column))
                  .at(1),
            );
            final badge = tester.getRect(_tileBadge(label));
            expect(badge.left, greaterThanOrEqualTo(tile.left), reason: label);
            expect(badge.right, lessThanOrEqualTo(tile.right), reason: label);
            expect(badge.bottom, lessThanOrEqualTo(tile.bottom), reason: label);
          }

          final card = tester.getRect(
            find
                .ancestor(
                  of: find.text('Your Next Step'),
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w is Container &&
                        w.decoration is BoxDecoration &&
                        (w.decoration as BoxDecoration).gradient != null,
                  ),
                )
                .first,
          );
          final cardBadge = tester.getRect(
            find.byWidgetPredicate((w) => w is SoonBadge && w.onBrand),
          );
          expect(card.contains(cardBadge.topLeft), isTrue);
          expect(card.contains(cardBadge.bottomRight), isTrue);

          for (final rect in _badgeRects(tester)) {
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(320));
          }
        },
      );
    }
  });

  group('the learning roadmap stays', () {
    // The prompt is a private part of a screen that needs Firebase, so its
    // source text is checked instead.
    test('the "Create your learning roadmap?" prompt is unchanged', () {
      final source = File(
        'lib/features/career_analysis/career_analysis_screen.dart',
      ).readAsStringSync();

      for (final text in [
        "'Create My Roadmap'",
        "'Create your learning roadmap?'",
        "'Masra will use your latest skill gaps and career goal to create a personalized learning roadmap.'",
        "'Cancel'",
        "'Create'",
        'const LearningRoadmapScreen()',
      ]) {
        expect(source, contains(text));
      }
    });

    testWidgets('the roadmap screen still opens', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LearningRoadmapScreen()));

      expect(find.text('Personalized Learning Roadmap'), findsNWidgets(2));
      expect(
        find.text('Follow a personalized path to develop the skills you need.'),
        findsOneWidget,
      );
      expect(find.text('Coming soon'), findsOneWidget);
    });
  });
}
