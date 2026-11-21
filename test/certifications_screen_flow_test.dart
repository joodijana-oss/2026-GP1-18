import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masra/features/certifications/certification_setup_memory.dart';
import 'package:masra/features/certifications/certifications_screen.dart';
import 'package:masra/models/certification.dart';
import 'package:masra/services/certification_service.dart';
import 'package:masra/services/content_based_recommender.dart';
import 'package:masra/services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The Certification Recommender screen with fake services: when the setup
// page shows, when the results open straight away, and how "Change" and
// back work. No Firebase app is needed.

const _setupHero = 'Find Certifications That Fit You';
const _findButton = 'Find Certifications';
const _resultsTitle = 'Your Certification Matches';
const _matching = 'Matching certifications to your skill gaps';
const _loadError =
    'We could not load your certification matches. Check your connection and try again.';

// The "Your choices" summaries. The space before the dot and the space in
// "Top 5" are non-breaking ( ).
const _gaps5 = 'Close my skill gaps · Top 5';
const _strengthen10 = 'Strengthen my skills · Top 10';

// The notes under a Top 5 / Top 10 list. Only certifications that cover a
// gap (or build on a skill) are counted.
String _n1Gaps(int shown, int found) =>
    'Showing $shown of $found certifications that cover your gaps. Tap Change and choose All to see every one.';
String _n1Skills(int shown, int found) =>
    'Showing $shown of $found certifications that build on your skills. Tap Change and choose All to see every one.';
String _n2GapsMany(int found, int limit) =>
    'We found $found certifications that cover your gaps, fewer than the $limit you chose.';
String _n2GapsOne(int limit) =>
    'We found 1 certification that covers your gaps, fewer than the $limit you chose.';
String _n2SkillsMany(int found, int limit) =>
    'We found $found certifications that build on your skills, fewer than the $limit you chose.';
String _n2SkillsOne(int limit) =>
    'We found 1 certification that builds on your skills, fewer than the $limit you chose.';

// The messages shown instead of a list when no certification covers a gap
// (or builds on a skill).
const _eGaps =
    'We keep adding new ones. For now, look for training in Opportunity Radar.';
const _eSkills =
    'We keep adding new ones. For now, look for hackathons and training in Opportunity Radar.';
const _eNoGaps =
    'Tap Change and choose Strengthen my skills to build on what you know.';
const _eNoSkills =
    'Tap Change and choose Close my skill gaps to learn what your career goal needs.';

/// A certification card: the only place with this icon.
final _cards = find.byIcon(Icons.chevron_right_rounded);

/// Gives the screen a saved analysis instead of reading Firestore.
class _FakeUserService implements UserService {
  Map<String, dynamic>? analysis;

  _FakeUserService(this.analysis);

  @override
  Future<Map<String, dynamic>?> getValidLatestAnalysis() async => analysis;

  @override
  Future<Map<String, dynamic>?> getUser() async => {'experienceLevel': 'Entry'};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Gives the screen a small catalog and counts how often it is read.
class _FakeCertificationService implements CertificationService {
  int calls = 0;

  /// How many of the next reads fail, as if the phone were offline.
  int failuresLeft = 0;

  /// The certifications it returns: three for both career goals.
  List<Certification> catalog = [
    _cert('sql_cert', 'SQL Certificate', ['Databases and SQL']),
    _cert('bi_cert', 'Power BI Certificate', ['Power BI']),
    _cert('python_cert', 'Python Certificate', ['Python']),
  ];

  @override
  Future<List<Certification>> getAll({bool forceRefresh = false}) async {
    calls++;
    if (failuresLeft > 0) {
      failuresLeft--;
      throw Exception('No connection');
    }
    return catalog;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Certification _cert(String id, String name, List<String> skills) {
  return Certification(
    id: id,
    name: name,
    shortName: '',
    issuer: 'Issuer',
    examCode: '',
    level: 'Beginner',
    category: 'Category',
    description: 'Description',
    descriptionAr: '',
    careerPaths: const ['data_analyst', 'software_engineer'],
    skills: skills,
    officialUrl: 'https://example.com',
    verified: true,
    statusNote: '',
  );
}

/// An analysis shaped like the one saved in Firestore.
Map<String, dynamic> analysisMap({
  int seconds = 1700000000,
  String goal = 'data_analyst',
}) {
  return {
    'analyzedAt': Timestamp(seconds, 0),
    'careerGoalId': goal,
    'careerGoalName': goal == 'data_analyst'
        ? 'Data Analyst'
        : 'Software Engineer',
    'skillGaps': ['SQL', 'Power BI'],
    'currentSkills': ['Python', 'Excel'],
    'certifications': <Map<String, dynamic>>[],
  };
}

/// Saved choices for a user, as the screen stores them.
Map<String, Object> savedRun(
  String uid, {
  String goal = 'closeGaps',
  int limit = 5,
  String analysisKey = '1700000000.0',
  String careerGoalId = 'data_analyst',
}) {
  return {
    CertificationSetupMemory.goalKey(uid): goal,
    CertificationSetupMemory.limitKey(uid): limit,
    CertificationSetupMemory.analysisKeyFor(uid): analysisKey,
    CertificationSetupMemory.careerGoalKey(uid): careerGoalId,
  };
}

/// A page with an "Open" button below the screen, so back can be tested
/// and reopening creates a new screen each time.
Widget _launcher({
  required _FakeUserService users,
  required _FakeCertificationService certs,
  required String? Function() uid,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CertificationsScreen(
                  userService: users,
                  certificationService: certs,
                  currentUserId: uid,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

// The hero icon moves forever, so the tests never wait for everything to
// settle. They pump long enough for the 900 ms matching view instead.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 1000));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> openScreen(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await settle(tester);
}

/// The header scrolls with the page, so it is scrolled back into view first.
Future<void> tapBackArrow(WidgetTester tester) async {
  final arrow = find.byIcon(Icons.arrow_back_ios_new_rounded);
  await tester.ensureVisible(arrow);
  await tester.pump();
  await tester.tap(arrow);
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pump();
  await tester.tap(find.text(text));
  await tester.pump();
}

Future<void> tapFind(WidgetTester tester) async {
  await tapText(tester, _findButton);
  await settle(tester);
}

/// True when the option with this title is shown as selected.
bool isSelected(WidgetTester tester, String title) {
  final semantics = tester.widget<Semantics>(
    find.ancestor(of: find.text(title), matching: find.byType(Semantics)).first,
  );
  return semantics.properties.selected ?? false;
}

void expectSetup() {
  expect(find.text(_setupHero), findsOneWidget);
  expect(find.text(_findButton), findsOneWidget);
  expect(find.text(_resultsTitle), findsNothing);
}

void expectResults(String choices) {
  expect(find.text(_resultsTitle), findsOneWidget);
  expect(find.text('Your choices'), findsOneWidget);
  expect(find.text(choices), findsOneWidget);
  expect(find.text('Change'), findsOneWidget);
  expect(find.text(_setupHero), findsNothing);
}

void main() {
  late _FakeUserService users;
  late _FakeCertificationService certs;
  late String uid;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    users = _FakeUserService(analysisMap());
    certs = _FakeCertificationService();
    uid = 'uid-a';
  });

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(
      _launcher(users: users, certs: certs, uid: () => uid),
    );
  }

  testWidgets('the first time shows the setup, then remembers the choices', (
    tester,
  ) async {
    await start(tester);
    await openScreen(tester);
    expectSetup();

    await tapFind(tester);
    expectResults(_gaps5);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(CertificationSetupMemory.goalKey(uid)), 'closeGaps');
    expect(prefs.getInt(CertificationSetupMemory.limitKey(uid)), 5);
    expect(
      prefs.getString(CertificationSetupMemory.analysisKeyFor(uid)),
      '1700000000.0',
    );
    expect(
      prefs.getString(CertificationSetupMemory.careerGoalKey(uid)),
      'data_analyst',
    );
  });

  testWidgets('nothing changed: the results open and the setup never shows', (
    tester,
  ) async {
    await start(tester);
    await openScreen(tester);
    await tapFind(tester);
    await tapBackArrow(tester);
    expect(find.text('Open'), findsOneWidget);

    await tester.tap(find.text('Open'));
    var sawMatching = false;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text(_setupHero), findsNothing);
      expect(find.text(_findButton), findsNothing);
      if (find.text(_matching).evaluate().isNotEmpty) sawMatching = true;
    }
    await settle(tester);

    expect(sawMatching, isTrue);
    expectResults(_gaps5);
  });

  testWidgets('a new analysis shows the setup with the last choices', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(
      savedRun(uid, goal: 'strengthenSkills', limit: 10),
    );
    users.analysis = analysisMap(seconds: 1700000100);

    await start(tester);
    await openScreen(tester);

    expectSetup();
    expect(isSelected(tester, 'Strengthen my skills'), isTrue);
    expect(isSelected(tester, 'Close my skill gaps'), isFalse);
    expect(isSelected(tester, 'Top 10'), isTrue);
    expect(isSelected(tester, 'Top 5'), isFalse);
  });

  testWidgets('a changed career goal shows the setup', (tester) async {
    SharedPreferences.setMockInitialValues(savedRun(uid));
    users.analysis = analysisMap(goal: 'software_engineer');

    await start(tester);
    await openScreen(tester);

    expectSetup();
  });

  testWidgets('another user on the same phone sees the setup', (tester) async {
    SharedPreferences.setMockInitialValues(savedRun('uid-a'));

    await start(tester);
    await openScreen(tester);
    expectResults(_gaps5);
    await tapBackArrow(tester);

    uid = 'uid-b';
    await openScreen(tester);
    expectSetup();
  });

  testWidgets('an old install with only the device-wide keys sees the setup', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'cert_recommender_goal': 'strengthenSkills',
      'cert_recommender_limit': 10,
    });

    await start(tester);
    await openScreen(tester);

    expectSetup();
    // The old device-wide choices are not used as defaults.
    expect(isSelected(tester, 'Close my skill gaps'), isTrue);
    expect(isSelected(tester, 'Top 5'), isTrue);
  });

  testWidgets('Change then back returns to the same results', (tester) async {
    SharedPreferences.setMockInitialValues(savedRun(uid));

    await start(tester);
    await openScreen(tester);
    expectResults(_gaps5);
    final callsBefore = certs.calls;
    final prefs = await SharedPreferences.getInstance();
    final savedBefore = {
      for (final key in prefs.getKeys()) key: prefs.get(key),
    };

    // Scroll down the results first: the setup must open at the top.
    await tester.ensureVisible(find.text('Fresh with every analysis'));
    await tester.pump();
    await tapText(tester, 'Change');
    await settle(tester);
    expectSetup();
    final arrowTop = tester
        .getTopLeft(find.byIcon(Icons.arrow_back_ios_new_rounded))
        .dy;
    expect(arrowTop, inInclusiveRange(0, 100));
    expect(isSelected(tester, 'Close my skill gaps'), isTrue);
    expect(isSelected(tester, 'Top 5'), isTrue);

    await tapText(tester, 'Strengthen my skills');
    await tapText(tester, 'Top 10');
    expect(isSelected(tester, 'Strengthen my skills'), isTrue);

    // The header back arrow.
    await tapBackArrow(tester);
    expectResults(_gaps5);
    expect(certs.calls, callsBefore);
    expect({
      for (final key in prefs.getKeys()) key: prefs.get(key),
    }, savedBefore);

    // The system back gesture does the same and does not close the screen.
    await tapText(tester, 'Change');
    await settle(tester);
    expectSetup();
    await tester.binding.handlePopRoute();
    await settle(tester);
    expectResults(_gaps5);
    expect(find.text('Open'), findsNothing);

    // From the results, back leaves the screen.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('Change and Find saves the new choices for next time', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(savedRun(uid));

    await start(tester);
    await openScreen(tester);
    await tapText(tester, 'Change');
    await settle(tester);
    await tapText(tester, 'Strengthen my skills');
    await tapText(tester, 'Top 10');
    await tapFind(tester);

    expectResults(_strengthen10);
    expect(find.textContaining('to strengthen your skills'), findsOneWidget);
    // Only 1 certification builds on the skills for Top 10: the heading
    // says the list is complete, and the note says how many were found.
    expect(find.text('The only one to strengthen your skills'), findsOneWidget);
    expect(find.text(_n2SkillsOne(10)), findsOneWidget);
    expect(find.text('Python Certificate'), findsOneWidget);
    expect(find.text('SQL Certificate'), findsNothing);
    expect(find.text('Power BI Certificate'), findsNothing);

    await tapBackArrow(tester);
    await openScreen(tester);
    expectResults(_strengthen10);
  });

  // The heading over the list follows the choice, not only the number of
  // cards, so it never disagrees with "Your choices".
  testWidgets('enough certifications for the choice: the heading says Top 5', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(savedRun(uid));
    // They all cover a gap, so they all count.
    certs.catalog = [
      for (var i = 1; i <= 6; i++)
        _cert('cert_$i', 'Certificate $i', ['Power BI']),
    ];

    await start(tester);
    await openScreen(tester);

    expectResults(_gaps5);
    expect(find.text('Top 5 to close your gaps'), findsOneWidget);
    expect(find.text(_n1Gaps(5, 6)), findsOneWidget);
    expect(_cards, findsNWidgets(5));
    expect(find.text('Certificate 6'), findsNothing);
    expect(find.textContaining('fewer than'), findsNothing);
  });

  testWidgets('fewer certifications than chosen: the heading says All 2', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(savedRun(uid));

    await start(tester);
    await openScreen(tester);

    expectResults(_gaps5);
    expect(find.text('All 2 to close your gaps'), findsOneWidget);
    expect(find.text(_n2GapsMany(2, 5)), findsOneWidget);
    expect(_cards, findsNWidgets(2));
    // Python covers no gap, so the list is not filled up with it.
    expect(find.text('Python Certificate'), findsNothing);
    expect(find.text('Relevant to your career goal.'), findsNothing);
    expect(find.textContaining('Top 2'), findsNothing);
    expect(find.textContaining('Tap Change and choose All'), findsNothing);
  });

  testWidgets('one certification for the choice: the heading says so', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(savedRun(uid));
    certs.catalog = [
      _cert('sql_cert', 'SQL Certificate', ['Databases and SQL']),
    ];

    await start(tester);
    await openScreen(tester);

    expectResults(_gaps5);
    expect(find.text('The only one to close your gaps'), findsOneWidget);
    expect(find.text(_n2GapsOne(5)), findsOneWidget);
  });

  // Very large text: the "How many?" labels are taller than the old fixed
  // 46 dp tile, yet stay inside their tiles, and all three tiles keep the
  // same height. The screen is wide so the rest of the setup page fits.
  testWidgets('the How many? tiles grow with large text', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 3.5;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await start(tester);
    await openScreen(tester);

    expect(tester.takeException(), isNull);
    expectSetup();
    final tiles = [
      for (final label in ['Top 5', 'Top 10', 'All'])
        tester.getRect(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        ),
    ];
    for (final (i, label) in ['Top 5', 'Top 10', 'All'].indexed) {
      // The label got all the height its lines need, so none is cut off.
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(
          paragraph.getMinIntrinsicHeight(paragraph.size.width),
        ),
      );
      final text = tester.getRect(find.text(label));
      expect(tiles[i].top, lessThanOrEqualTo(text.top));
      expect(tiles[i].bottom, greaterThanOrEqualTo(text.bottom));
      expect(tiles[i].height, tiles[0].height);
    }
    expect(tiles[0].height, greaterThanOrEqualTo(46));
  });

  testWidgets('the back arrow on a first-time setup leaves the screen', (
    tester,
  ) async {
    await start(tester);
    await openScreen(tester);
    expectSetup();

    await tapBackArrow(tester);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Certification Recommender'), findsNothing);
  });

  testWidgets('leaving a first-time setup without Find saves nothing', (
    tester,
  ) async {
    await start(tester);
    await openScreen(tester);
    await tapText(tester, 'Strengthen my skills');
    await tapText(tester, 'Top 10');
    await tapBackArrow(tester);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);

    // Still a first time: the setup shows with the defaults, not the picks.
    await openScreen(tester);
    expectSetup();
    expect(isSelected(tester, 'Close my skill gaps'), isTrue);
    expect(isSelected(tester, 'Top 5'), isTrue);
  });

  testWidgets('leaving the setup without Find keeps the saved choices', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(
      savedRun(uid, goal: 'strengthenSkills', limit: 10),
    );
    users.analysis = analysisMap(seconds: 1700000100);
    final prefs = await SharedPreferences.getInstance();
    final savedBefore = {
      for (final key in prefs.getKeys()) key: prefs.get(key),
    };

    await start(tester);
    await openScreen(tester);
    expectSetup();
    await tapText(tester, 'Close my skill gaps');
    await tapText(tester, 'All');
    await tapBackArrow(tester);

    expect({
      for (final key in prefs.getKeys()) key: prefs.get(key),
    }, savedBefore);

    // The analysis is still new to the saved run, so the setup shows again
    // with the saved choices.
    await openScreen(tester);
    expectSetup();
    expect(isSelected(tester, 'Strengthen my skills'), isTrue);
    expect(isSelected(tester, 'Top 10'), isTrue);
    expect(isSelected(tester, 'All'), isFalse);
  });

  testWidgets('without a signed-in user the setup shows and nothing is saved', (
    tester,
  ) async {
    await tester.pumpWidget(
      _launcher(users: users, certs: certs, uid: () => null),
    );
    await openScreen(tester);
    expectSetup();

    await tapFind(tester);
    expectResults(_gaps5);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);

    await tapBackArrow(tester);
    await openScreen(tester);
    expectSetup();
  });

  testWidgets('Find fails on the setup: Try Again shows the results', (
    tester,
  ) async {
    certs.failuresLeft = 1;

    await start(tester);
    await openScreen(tester);
    await tapFind(tester);
    expect(find.text(_loadError), findsOneWidget);
    expect(find.text(_resultsTitle), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);

    await tapText(tester, 'Try Again');
    await settle(tester);
    expectResults(_gaps5);
    expect(prefs.getString(CertificationSetupMemory.goalKey(uid)), 'closeGaps');
  });

  testWidgets('the results fail to open: back leaves, and Try Again works', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(savedRun(uid));
    certs.failuresLeft = 1;

    await start(tester);
    await openScreen(tester);
    expect(find.text(_loadError), findsOneWidget);

    // Back from the error leaves the screen (no lock-in).
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('Open'), findsOneWidget);

    // The next time it loads, and Try Again also works after a failure.
    certs.failuresLeft = 1;
    await openScreen(tester);
    expect(find.text(_loadError), findsOneWidget);
    await tapText(tester, 'Try Again');
    await settle(tester);
    expectResults(_gaps5);
  });

  testWidgets('Find after Change reuses the catalog, so it cannot fail offline', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(savedRun(uid));

    await start(tester);
    await openScreen(tester);
    expectResults(_gaps5);
    final callsBefore = certs.calls;

    // The catalog was read when the results opened. Find after Change only
    // matches again on the phone, so a lost connection does not matter.
    certs.failuresLeft = 1;
    await tapText(tester, 'Change');
    await settle(tester);
    await tapText(tester, 'Strengthen my skills');
    await tapText(tester, 'Top 10');
    await tapFind(tester);

    expect(find.text(_loadError), findsNothing);
    expectResults(_strengthen10);
    expect(certs.calls, callsBefore);

    // Back from these results leaves the screen.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('Open'), findsOneWidget);
  });

  // A small phone with large text: the "Change" button moves under the
  // choices so the summary is never squeezed or cut off.
  for (final (width, textScale) in [(360.0, 1.3), (320.0, 2.0)]) {
    testWidgets('the choices row fits ${width.toInt()} dp at text $textScale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 740);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      SharedPreferences.setMockInitialValues(
        savedRun(uid, goal: 'strengthenSkills', limit: 10),
      );
      // Skills that no certification uses leave no cards, so the test
      // looks only at the choices row.
      users.analysis = {
        ...analysisMap(),
        'currentSkills': ['Public Speaking'],
      };

      await start(tester);
      await openScreen(tester);

      expect(tester.takeException(), isNull);
      expectResults(_strengthen10);
      final summary = tester.renderObject<RenderParagraph>(
        find.text(_strengthen10),
      );
      expect(summary.didExceedMaxLines, isFalse);
      expect(
        tester.getTopLeft(find.text('Change')).dy,
        greaterThan(tester.getBottomLeft(find.text(_strengthen10)).dy),
      );
    });
  }

  testWidgets('on a wide screen the Change button sits beside the choices', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(savedRun(uid));

    await start(tester);
    await openScreen(tester);

    final summary = tester.getRect(find.text(_gaps5));
    final change = tester.getRect(find.text('Change'));
    expect(change.left, greaterThan(summary.right));
    expect(change.top, lessThan(summary.bottom));
  });

  // The results list only certifications that cover a skill gap (or build
  // on a skill the user has). The others for the career goal are never
  // listed, and no list fills up with them.
  group('only certifications that cover a gap', () {
    String choices(String goal, int limit) =>
        CertificationSetupMemory.choicesSummary(
          goal == 'closeGaps'
              ? CertificationGoal.closeGaps
              : CertificationGoal.strengthenSkills,
          limit == 0 ? null : limit,
        );

    testWidgets('All, close gaps: only the ones that cover a gap', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(savedRun(uid, limit: 0));

      await start(tester);
      await openScreen(tester);

      expectResults(choices('closeGaps', 0));
      expect(find.text('Covers your skill gaps'), findsOneWidget);
      expect(_cards, findsNWidgets(2));
      // The ranking is unchanged: same number of gaps, then name order.
      expect(
        tester.getTopLeft(find.text('Power BI Certificate')).dy,
        lessThan(tester.getTopLeft(find.text('SQL Certificate')).dy),
      );
      expect(find.text('1 of 2 gaps covered'), findsNWidgets(2));
      expect(find.text('Python Certificate'), findsNothing);
      expect(find.text('Also for your career goal'), findsNothing);
      expect(find.text('Relevant to your career goal.'), findsNothing);
    });

    testWidgets('All, strengthen: only the ones that build on a skill', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(
        savedRun(uid, goal: 'strengthenSkills', limit: 0),
      );

      await start(tester);
      await openScreen(tester);

      expectResults(choices('strengthenSkills', 0));
      expect(find.text('Builds on your skills'), findsOneWidget);
      expect(_cards, findsOneWidget);
      expect(find.text('Python Certificate'), findsOneWidget);
      expect(find.text('Uses 1 of your 2 skills'), findsOneWidget);
      expect(find.text('SQL Certificate'), findsNothing);
      expect(find.text('Power BI Certificate'), findsNothing);
      expect(find.text('Also for your career goal'), findsNothing);
    });

    testWidgets('Top 10, close gaps, fewer found: says how many', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(savedRun(uid, limit: 10));

      await start(tester);
      await openScreen(tester);

      expectResults(choices('closeGaps', 10));
      expect(find.text('All 2 to close your gaps'), findsOneWidget);
      expect(find.text(_n2GapsMany(2, 10)), findsOneWidget);
      expect(_cards, findsNWidgets(2));
      expect(find.text('Python Certificate'), findsNothing);
    });

    testWidgets('Top 5, strengthen, one found: says so', (tester) async {
      SharedPreferences.setMockInitialValues(
        savedRun(uid, goal: 'strengthenSkills', limit: 5),
      );

      await start(tester);
      await openScreen(tester);

      expectResults(choices('strengthenSkills', 5));
      expect(find.text('The only one to strengthen your skills'), findsOneWidget);
      expect(find.text(_n2SkillsOne(5)), findsOneWidget);
      expect(_cards, findsOneWidget);
    });

    testWidgets('Top 5, strengthen, two found: says how many', (tester) async {
      SharedPreferences.setMockInitialValues(
        savedRun(uid, goal: 'strengthenSkills', limit: 5),
      );
      certs.catalog = [
        ...certs.catalog,
        _cert('excel_cert', 'Excel Certificate', ['Excel']),
      ];

      await start(tester);
      await openScreen(tester);

      expectResults(choices('strengthenSkills', 5));
      expect(find.text('All 2 to strengthen your skills'), findsOneWidget);
      expect(find.text(_n2SkillsMany(2, 5)), findsOneWidget);
      expect(_cards, findsNWidgets(2));
      expect(find.text('Excel Certificate'), findsOneWidget);
      expect(find.text('Python Certificate'), findsOneWidget);
      expect(find.text('SQL Certificate'), findsNothing);
      expect(find.text('Power BI Certificate'), findsNothing);
    });

    testWidgets('Top 10, strengthen, more found: Showing 10 of 11', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(
        savedRun(uid, goal: 'strengthenSkills', limit: 10),
      );
      certs.catalog = [
        for (var i = 1; i <= 11; i++)
          _cert('cert_$i', 'Certificate $i', ['Python']),
      ];

      await start(tester);
      await openScreen(tester);

      expectResults(_strengthen10);
      expect(find.text('Top 10 to strengthen your skills'), findsOneWidget);
      expect(find.text(_n1Skills(10, 11)), findsOneWidget);
      expect(_cards, findsNWidgets(10));
      // Ties are ranked by name: 1, 10, 11, 2 ... 9, so 9 is left out.
      expect(find.text('Certificate 9'), findsNothing);
      expect(find.textContaining('fewer than'), findsNothing);
    });

    testWidgets('Top 5, close gaps, exactly 5 found: no note', (tester) async {
      SharedPreferences.setMockInitialValues(savedRun(uid));
      certs.catalog = [
        for (var i = 1; i <= 5; i++)
          _cert('cert_$i', 'Certificate $i', ['Power BI']),
      ];

      await start(tester);
      await openScreen(tester);

      expectResults(_gaps5);
      expect(find.text('Top 5 to close your gaps'), findsOneWidget);
      expect(_cards, findsNWidgets(5));
      expect(find.textContaining('Showing'), findsNothing);
      expect(find.textContaining('fewer than'), findsNothing);
    });

    for (final goal in ['closeGaps', 'strengthenSkills']) {
      for (final limit in [0, 5, 10]) {
        final label = CertificationSetupMemory.limitLabel(
          limit == 0 ? null : limit,
        );
        testWidgets('none found, $goal, $label: only a message', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues(
            savedRun(uid, goal: goal, limit: limit),
          );
          users.analysis = {
            ...analysisMap(),
            'skillGaps': ['Kubernetes'],
            'currentSkills': ['Public Speaking'],
          };

          await start(tester);
          await openScreen(tester);

          final forGaps = goal == 'closeGaps';
          expectResults(choices(goal, limit));
          expect(
            find.text(
              forGaps
                  ? 'No certification covers your gaps yet'
                  : 'No certification builds on your skills yet',
            ),
            findsOneWidget,
          );
          expect(find.text(forGaps ? _eGaps : _eSkills), findsOneWidget);
          expect(_cards, findsNothing);
          for (final name in [
            'SQL Certificate',
            'Power BI Certificate',
            'Python Certificate',
          ]) {
            expect(find.text(name), findsNothing);
          }
          expect(find.textContaining('to close your gaps'), findsNothing);
          expect(find.textContaining('to strengthen your skills'), findsNothing);
          expect(find.text('Covers your skill gaps'), findsNothing);
          expect(find.text('Builds on your skills'), findsNothing);
          expect(find.text('Also for your career goal'), findsNothing);
          expect(
            find.text('Here are certifications that fit your career goal.'),
            findsNothing,
          );
          expect(find.textContaining('Showing'), findsNothing);
          expect(find.textContaining('fewer than'), findsNothing);
          expect(find.text('Fresh with every analysis'), findsOneWidget);
        });
      }
    }

    testWidgets('no skill gaps in the analysis: only a message', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(savedRun(uid));
      users.analysis = {...analysisMap(), 'skillGaps': <String>[]};

      await start(tester);
      await openScreen(tester);

      expectResults(_gaps5);
      expect(find.text('No skill gaps found'), findsOneWidget);
      expect(find.text(_eNoGaps), findsOneWidget);
      expect(_cards, findsNothing);
    });

    testWidgets('no skills in the analysis: only a message', (tester) async {
      SharedPreferences.setMockInitialValues(
        savedRun(uid, goal: 'strengthenSkills', limit: 0),
      );
      users.analysis = {...analysisMap(), 'currentSkills': <String>[]};

      await start(tester);
      await openScreen(tester);

      expectResults(choices('strengthenSkills', 0));
      expect(find.text('No skills found'), findsOneWidget);
      expect(find.text(_eNoSkills), findsOneWidget);
      expect(_cards, findsNothing);
    });

    testWidgets('no certification for the career goal: message unchanged', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(savedRun(uid));
      certs.catalog = [];

      await start(tester);
      await openScreen(tester);

      expectResults(_gaps5);
      expect(find.text('No matching certifications yet'), findsOneWidget);
      expect(
        find.text(
          'We do not have certifications for this career goal yet. We keep adding new ones, so check back soon.',
        ),
        findsOneWidget,
      );
      expect(_cards, findsNothing);
    });

    testWidgets('a certification in the CV is still hidden and counted', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(savedRun(uid, limit: 0));
      users.analysis = {
        ...analysisMap(),
        'certifications': [
          {'name': 'Power BI Certificate'},
        ],
      };

      await start(tester);
      await openScreen(tester);

      expectResults(choices('closeGaps', 0));
      expect(_cards, findsOneWidget);
      expect(find.text('SQL Certificate'), findsOneWidget);
      expect(find.text('Power BI Certificate'), findsNothing);
      expect(
        find.text('1 certification already listed in your CV is hidden.'),
        findsOneWidget,
      );
    });

    testWidgets('none found and one hidden: the message and the hidden note', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(savedRun(uid, limit: 0));
      users.analysis = {
        ...analysisMap(),
        'skillGaps': ['Kubernetes'],
        'certifications': [
          {'name': 'Power BI Certificate'},
        ],
      };

      await start(tester);
      await openScreen(tester);

      expectResults(choices('closeGaps', 0));
      expect(find.text('No certification covers your gaps yet'), findsOneWidget);
      expect(find.text(_eGaps), findsOneWidget);
      expect(
        find.text('1 certification already listed in your CV is hidden.'),
        findsOneWidget,
      );
      expect(_cards, findsNothing);
    });
  });
}
