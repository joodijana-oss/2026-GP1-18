import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:masra/models/gap_link.dart';
import 'package:masra/services/analysis_requests.dart';
import 'package:masra/services/career_analysis_pipeline.dart';

const String cv = '''
Sara Example
Product intern, a Riyadh-based delivery company (Jun 2026 - Aug 2026)
- Interviewed 12 customers and turned their answers into a feature list
Certifications: Certified Scrum Product Owner (Scrum Alliance)
Skills: Figma, SQL, C#
''';

const List<Map<String, String>> jobs = [
  {
    'title': 'Associate Product Manager',
    'description': 'Owns the roadmap and talks to customers.',
    'city': 'Riyadh',
    'source': 'test',
  },
];

/// Answers the AI requests from memory and records which ones were made.
class FakeAi implements AnalysisRequests {
  List<String> market = ['User Research', 'Roadmap Planning', 'SQL'];
  List<String> gapsByNames = ['User Research', 'Roadmap Planning'];
  dynamic evidence = [
    {
      'skill': 'User Research',
      'status': 'shown',
      'quote': 'Interviewed 12 customers',
    },
    {'skill': 'Roadmap Planning', 'status': 'missing', 'quote': ''},
    {'skill': 'SQL', 'status': 'shown', 'quote': 'Skills: Figma, SQL'},
  ];

  Object? evidenceError;
  Object? namesError;
  Duration evidenceDelay = Duration.zero;

  /// When the evidence check answered (the end of the gap step).
  DateTime? evidenceAnsweredAt;

  /// The answer of the typed link request.
  dynamic links = [
    {
      'skill': 'User Research',
      'kind': 'skill',
      'same': ['UX Research'],
      'covers': [],
      'terms': ['user interviews'],
    },
    {
      'skill': 'Roadmap Planning',
      'kind': 'skill',
      'same': [],
      'covers': ['Product Management', 'Not A Catalogue Name'],
      'terms': ['roadmap', 'a term that is much too long to keep'],
    },
    {'skill': 'SQL', 'kind': 'tool', 'same': ['SQL'], 'covers': []},
  ];
  Object? linkError;
  Duration linkDelay = Duration.zero;
  List<String>? linkSkillsSeen;
  List<String>? linkConceptsSeen;
  LinkRequest? linkRequestSeen;

  /// The arguments of the gap requests, to compare two runs.
  final List<String> gapInputs = [];

  final List<String> calls = [];
  bool? askedForSingleNames;
  List<String>? certificationsSeen;
  Duration? namesTimeLimit;

  @override
  Future<Map<String, dynamic>> analyzeCv({required String cvText}) async {
    calls.add('analyze');
    return {
      'strengths': ['Talks to customers'],
      'currentSkills': ['Figma', 'SQL'],
      'education': [],
      'certifications': [
        {
          'name': 'Certified Scrum Product Owner',
          'issuer': 'Scrum Alliance',
          'year': '',
        },
      ],
      'projects': [],
      'experience': [],
    };
  }

  @override
  Future<List<String>> extractMarketSkills({
    required String careerName,
    required String jobMarketText,
    bool singleSkillNames = false,
  }) async {
    calls.add('market');
    askedForSingleNames = singleSkillNames;
    return market;
  }

  @override
  Future<List<String>> identifySkillGaps({
    required List<String> currentSkills,
    required List<String> targetSkills,
    Duration? timeLimit,
  }) async {
    calls.add('names');
    gapInputs.add('names|$currentSkills|$targetSkills');
    namesTimeLimit = timeLimit;
    if (namesError != null) throw namesError!;
    return gapsByNames;
  }

  @override
  Future<dynamic> checkSkillsAgainstCv({
    required String cvText,
    required List<String> currentSkills,
    required List<String> certifications,
    required List<String> targetSkills,
    Duration? timeLimit,
  }) async {
    calls.add('evidence');
    gapInputs.add(
        'evidence|$cvText|$currentSkills|$certifications|$targetSkills|'
        '$timeLimit');
    certificationsSeen = certifications;
    await Future<void>.delayed(evidenceDelay);
    evidenceAnsweredAt = DateTime.now();
    if (evidenceError != null) throw evidenceError!;
    return evidence;
  }

  @override
  Future<dynamic> linkSkillsToConcepts({
    required List<String> skills,
    required List<String> concepts,
    LinkRequest request = LinkRequest.typed,
    Duration? timeLimit,
  }) async {
    calls.add('link');
    linkSkillsSeen = skills;
    linkConceptsSeen = concepts;
    linkRequestSeen = request;
    await Future<void>.delayed(linkDelay);
    if (linkError != null) throw linkError!;
    return links;
  }
}

/// What the app runs, with the link request switched on.
const AnalysisSettings withLinks = AnalysisSettings(
  gapMethod: GapMethod.cvEvidence,
  singleSkillNames: true,
  linkSkills: true,
);

final CatalogueNames names = CatalogueNames(
  opportunityTags: const ['Product Management', 'UX Research'],
);

Future<Map<String, dynamic>> run(
  FakeAi ai,
  AnalysisSettings settings, {
  void Function(int step)? onStep,
  bool Function()? isCancelled,
}) =>
    CareerAnalysisPipeline(ai, settings: settings, names: names).run(
      cvText: cv,
      careerGoalId: 'product_manager',
      careerName: 'Product Manager',
      jobs: jobs,
      onStep: onStep,
      isCancelled: isCancelled,
    );

const List<String> originalFields = [
  'strengths',
  'currentSkills',
  'skillGaps',
  'targetSkills',
  'education',
  'certifications',
  'projects',
  'experience',
  'careerGoalId',
  'careerGoalName',
  'marketJobCount',
  'analysisSource',
  'marketBased',
];

void main() {
  group('what the app runs', () {
    test('single-skill market names and the CV evidence check, no links', () {
      const app = AnalysisSettings.app;
      expect(app.gapMethod, GapMethod.cvEvidence);
      expect(app.singleSkillNames, isTrue);
      expect(app.partlyIsGap, isFalse);
      expect(app.isOriginal, isFalse);
      // Matching by meaning stays off until it has passed its rules.
      expect(app.linkSkills, isFalse);
    });

    test('a pipeline built without settings runs what the app runs',
        () async {
      final ai = FakeAi();
      await CareerAnalysisPipeline(ai).run(
        cvText: cv,
        careerGoalId: 'product_manager',
        careerName: 'Product Manager',
        jobs: jobs,
      );
      expect(ai.calls, ['analyze', 'market', 'evidence']);
    });

    test('makes three requests and saves the gaps the CV does not show',
        () async {
      final ai = FakeAi();
      final steps = <int>[];
      final analysis =
          await run(ai, AnalysisSettings.app, onStep: steps.add);

      expect(ai.calls, ['analyze', 'market', 'evidence']);
      expect(ai.askedForSingleNames, isTrue);
      expect(ai.certificationsSeen,
          ['Certified Scrum Product Owner (Scrum Alliance)']);
      expect(steps, [1, 2]);

      // "User Research" is shown by an activity, so it is not a gap.
      expect(analysis['skillGaps'], ['Roadmap Planning']);
      expect(analysis['gapMethod'], 'cv-evidence');
      expect(analysis['analysisVersion'], 2);
      expect(analysis['targetSkillStatus'], [
        {'skill': 'User Research', 'status': 'shown'},
        {'skill': 'Roadmap Planning', 'status': 'missing'},
        {'skill': 'SQL', 'status': 'shown'},
      ]);
      expect(analysis.keys, [
        ...originalFields,
        'analysisVersion',
        'gapMethod',
        'targetSkillStatus',
      ]);
      expect(analysis.containsKey('gapLinks'), isFalse);
    });

    test('when the evidence check fails, the names-only path answers with '
        'its shorter time limit', () async {
      final ai = FakeAi()..evidenceError = Exception('AI request failed');
      final analysis = await run(ai, AnalysisSettings.app);
      expect(ai.calls, ['analyze', 'market', 'evidence', 'names']);
      expect(ai.namesTimeLimit, AnalysisSettings.app.fallbackLimit);
      expect(analysis['skillGaps'], ['User Research', 'Roadmap Planning']);
      expect(analysis['gapMethod'], 'names-only');
      expect(analysis.containsKey('targetSkillStatus'), isFalse);
    });

    test('bundled market names are cleaned before the gap step', () async {
      final ai = FakeAi()
        ..market = ['Design Tools (Figma, Sketch)', 'Python or R', 'SQL']
        ..evidence = [
          {'skill': 'Figma', 'status': 'shown', 'quote': 'Skills: Figma, SQL'},
        ];
      final analysis = await run(ai, AnalysisSettings.app);
      expect(analysis['targetSkills'], ['Figma', 'Sketch', 'Python', 'R', 'SQL']);
      expect(analysis['skillGaps'], ['Sketch', 'Python', 'R', 'SQL']);
    });

    test('C# and C++ stay two skills, and only the one the CV shows is no gap',
        () async {
      final ai = FakeAi()
        ..market = ['C#', 'C++', 'C']
        ..evidence = [
          {'skill': 'C#', 'status': 'shown', 'quote': 'Skills: Figma, SQL, C#'},
        ];
      final analysis = await run(ai, AnalysisSettings.app);
      expect(analysis['targetSkills'], ['C#', 'C++', 'C']);
      expect(analysis['skillGaps'], ['C++', 'C']);
    });

    test('when cleaning would leave nothing, the market names are kept',
        () async {
      final ai = FakeAi()
        ..market = ['Prototyping Tools']
        ..evidence = [
          {'skill': 'Prototyping Tools', 'status': 'missing', 'quote': ''},
        ];
      final analysis = await run(ai, AnalysisSettings.app);
      expect(analysis['targetSkills'], ['Prototyping Tools']);
      expect(analysis['skillGaps'], ['Prototyping Tools']);
    });
  });

  group('the original analysis', () {
    test('makes the three original requests and saves the original fields',
        () async {
      final ai = FakeAi();
      final steps = <int>[];
      final analysis =
          await run(ai, const AnalysisSettings(), onStep: steps.add);

      expect(const AnalysisSettings().isOriginal, isTrue);
      expect(ai.calls, ['analyze', 'market', 'names']);
      expect(ai.askedForSingleNames, isFalse);
      expect(ai.namesTimeLimit, isNull,
          reason: 'the usual limit, as before');
      expect(steps, [1, 2]);
      expect(analysis.keys, originalFields);
      expect(analysis['skillGaps'], ['User Research', 'Roadmap Planning']);
      expect(analysis['targetSkills'], ai.market);
      expect(analysis['marketJobCount'], 1);
    });

    test('bundled market names are left as they are', () async {
      final ai = FakeAi()..market = ['Design Tools (Figma, Sketch)', 'SQL'];
      final analysis = await run(ai, const AnalysisSettings());
      expect(analysis['targetSkills'], ['Design Tools (Figma, Sketch)', 'SQL']);
    });

    test('no postings and no market skills are errors, as before', () async {
      final pipeline = CareerAnalysisPipeline(FakeAi());
      await expectLater(
        pipeline.run(
          cvText: cv,
          careerGoalId: 'product_manager',
          careerName: 'Product Manager',
          jobs: const [],
        ),
        throwsException,
      );
      await expectLater(
        run(FakeAi()..market = [], const AnalysisSettings()),
        throwsException,
      );
      await expectLater(
        run(FakeAi()..market = [], AnalysisSettings.app),
        throwsException,
      );
    });
  });

  group('the gap check fails', () {
    test('an error falls back to the comparison by names, once', () async {
      final ai = FakeAi()..evidenceError = Exception('AI request failed');
      final analysis = await run(ai, AnalysisSettings.app);
      expect(ai.calls.where((call) => call == 'evidence'), hasLength(1),
          reason: 'one attempt, no retry');
      expect(analysis['gapMethod'], 'names-only');
    });

    test('an unusable answer falls back too', () async {
      final ai = FakeAi()..evidence = 'I could not read the CV';
      final analysis = await run(ai, AnalysisSettings.app);
      expect(analysis['gapMethod'], 'names-only');
      expect(analysis['skillGaps'], ['User Research', 'Roadmap Planning']);
    });

    test('a late answer falls back without a second attempt', () async {
      final ai = FakeAi()..evidenceDelay = const Duration(milliseconds: 300);
      final analysis = await run(
        ai,
        const AnalysisSettings(
          gapMethod: GapMethod.cvEvidence,
          singleSkillNames: true,
          gapCheckLimit: Duration(milliseconds: 30),
        ),
      );
      expect(ai.calls.where((call) => call == 'evidence'), hasLength(1));
      expect(analysis['gapMethod'], 'names-only');
      expect(analysis['skillGaps'], ['User Research', 'Roadmap Planning']);
    });

    test('when the comparison by names fails as well, it is an error',
        () async {
      final ai = FakeAi()
        ..evidenceError = Exception('AI request failed')
        ..namesError = Exception('AI request failed');
      await expectLater(run(ai, AnalysisSettings.app), throwsException);
    });

    test('the outcome says a fallback ran and why', () async {
      final ai = FakeAi()..evidenceError = TimeoutException('late');
      final outcome =
          await CareerAnalysisPipeline(ai, settings: AnalysisSettings.app)
              .skillGaps(
        cvText: cv,
        cvAnalysis: const {'currentSkills': <String>[]},
        targetSkills: ai.market,
      );
      expect(outcome.usedFallback, isTrue);
      expect(outcome.failure, 'time limit reached');
      expect(outcome.method, GapOutcome.namesOnly);
    });
  });

  group('meaning links', () {
    test('the link request runs next to the gap step and the links of the '
        'gaps are stored', () async {
      final ai = FakeAi();
      final analysis = await run(ai, withLinks);

      expect(ai.calls.take(2), ['analyze', 'market']);
      expect(ai.calls.skip(2), unorderedEquals(['evidence', 'link']));
      expect(ai.linkSkillsSeen, ['User Research', 'Roadmap Planning', 'SQL']);
      expect(ai.linkRequestSeen, LinkRequest.typed);
      // The synonym table names and the opportunity tags.
      expect(ai.linkConceptsSeen, containsAll(['Product Management', 'UX Research']));

      // Only "Roadmap Planning" is a gap. A name the app does not know is
      // dropped, and so is a term of more than four words.
      expect(analysis['skillGaps'], ['Roadmap Planning']);
      expect(analysis['gapLinks'], [
        {
          'gap': 'Roadmap Planning',
          'kind': 'skill',
          'concepts': ['Product Management'],
          'phrases': <String>[],
          'terms': ['roadmap'],
        },
      ]);
    });

    test('the gap step sends the same requests and finds the same gaps with '
        'links on and off', () async {
      final off = FakeAi();
      final on = FakeAi();
      final without = await run(off, AnalysisSettings.app);
      final withThem = await run(on, withLinks);

      expect(on.gapInputs, off.gapInputs);
      expect(on.calls.where((call) => call != 'link'), off.calls);
      expect({...withThem}..remove('gapLinks'), without);

      // The same when the evidence check fails and the names answer.
      final offFailing = FakeAi()..evidenceError = Exception('AI failed');
      final onFailing = FakeAi()..evidenceError = Exception('AI failed');
      final plain = await run(offFailing, AnalysisSettings.app);
      final linked = await run(onFailing, withLinks);
      expect(onFailing.gapInputs, offFailing.gapInputs);
      expect({...linked}..remove('gapLinks'), plain);
    });

    test('the first link request can be asked for, and its answer is read',
        () async {
      final ai = FakeAi()
        ..links = [
          {
            'skill': 'Roadmap Planning',
            'kind': 'skill',
            'concepts': ['Product Management', 'UX Research', 'SQL'],
            'phrases': ['product roadmap', 'roadmap', 'Roadmap Planning'],
          },
        ];
      final analysis = await run(
        ai,
        const AnalysisSettings(
          gapMethod: GapMethod.cvEvidence,
          singleSkillNames: true,
          linkSkills: true,
          linkRequest: LinkRequest.names,
        ),
      );
      expect(ai.linkRequestSeen, LinkRequest.names);
      // At most two names; a one-word phrase and the skill's own name are
      // not phrases.
      expect(analysis['gapLinks'], [
        {
          'gap': 'Roadmap Planning',
          'kind': 'skill',
          'concepts': ['Product Management', 'UX Research'],
          'phrases': ['product roadmap'],
        },
      ]);
    });

    test('a name is the same skill or a broader one, never both', () {
      final links = CareerAnalysisPipeline.linksFrom(
        [
          {
            'skill': 'Roadmap Planning',
            'kind': 'Skill',
            'same': ['Product Management'],
            'covers': ['Product Management', 'UX Research'],
          },
        ],
        skills: const ['Roadmap Planning'],
        concepts: names.concepts,
      );
      expect(links.single.same, ['Product Management']);
      expect(links.single.covers, ['UX Research']);
    });

    test('a failing link request keeps the gaps and saves no links', () async {
      final ai = FakeAi()..linkError = Exception('AI request failed');
      final analysis = await run(ai, withLinks);
      expect(analysis['skillGaps'], ['Roadmap Planning']);
      expect(analysis['gapMethod'], 'cv-evidence');
      expect(analysis.containsKey('gapLinks'), isFalse);
    });

    test('an unusable link answer saves no links', () async {
      for (final answer in [
        null,
        'not json',
        {'links': 'none'},
      ]) {
        final ai = FakeAi()..links = answer;
        final analysis = await run(ai, withLinks);
        expect(analysis['skillGaps'], ['Roadmap Planning']);
        expect(analysis.containsKey('gapLinks'), isFalse);
      }
    });

    test('a link request that passes its time limit saves no links and '
        'holds the analysis no longer than that limit', () async {
      final ai = FakeAi()..linkDelay = const Duration(seconds: 2);
      final watch = Stopwatch()..start();
      final analysis = await run(
        ai,
        const AnalysisSettings(
          gapMethod: GapMethod.cvEvidence,
          singleSkillNames: true,
          linkSkills: true,
          linkLimit: Duration(milliseconds: 40),
        ),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(analysis['skillGaps'], ['Roadmap Planning']);
      expect(analysis.containsKey('gapLinks'), isFalse);
    });

    test('the limit of the link request is shorter than the gap check\'s, '
        'so a slow link request never outlasts the gap step\'s own limit',
        () {
      expect(AnalysisSettings.app.linkLimit,
          lessThan(AnalysisSettings.app.gapCheckLimit));
    });

    test('a slow link request holds the saved result no longer than the '
        'grace after the gap step, and its late answer is dropped', () async {
      final ai = FakeAi()
        ..evidenceDelay = const Duration(milliseconds: 50)
        ..linkDelay = const Duration(seconds: 3);
      final analysis = await run(
        ai,
        const AnalysisSettings(
          gapMethod: GapMethod.cvEvidence,
          singleSkillNames: true,
          linkSkills: true,
          linkGrace: Duration(milliseconds: 100),
        ),
      );
      final saved = DateTime.now();
      // The gap step ended when the evidence check answered; the result
      // came at most the grace (plus scheduling) after it, long before the
      // link request's own limit of 45 seconds.
      expect(saved.difference(ai.evidenceAnsweredAt!),
          lessThan(const Duration(milliseconds: 600)));
      expect(analysis['skillGaps'], ['Roadmap Planning']);
      expect(analysis.containsKey('gapLinks'), isFalse);
    });

    test('a link answer that comes within the grace is stored', () async {
      final ai = FakeAi()..linkDelay = const Duration(milliseconds: 30);
      final analysis = await run(
        ai,
        const AnalysisSettings(
          gapMethod: GapMethod.cvEvidence,
          singleSkillNames: true,
          linkSkills: true,
          linkGrace: Duration(seconds: 2),
        ),
      );
      expect(analysis['gapLinks'], isNotEmpty);
    });

    test('the app waits a few seconds at most for links after the gap step',
        () {
      expect(AnalysisSettings.app.linkGrace,
          lessThanOrEqualTo(const Duration(seconds: 3)));
    });

    test('a link is stored under the gap\'s own spelling', () {
      final links = CareerAnalysisPipeline.linksForGaps(
        const [GapLink(gap: 'roadmap planning', concepts: ['Product Management'])],
        const ['Roadmap Planning'],
      );
      expect(links.single.gap, 'Roadmap Planning');
      expect(links.single.concepts, ['Product Management']);
    });

    test('a refused save drops the links with the other new fields', () {
      expect(CareerAnalysisPipeline.optionalFields, contains('gapLinks'));
    });
  });

  group('leaving the screen', () {
    test('after the CV is read, nothing more is requested', () async {
      final ai = FakeAi();
      await expectLater(
        run(ai, AnalysisSettings.app, isCancelled: () => true),
        throwsA(isA<AnalysisCancelled>()),
      );
      expect(ai.calls, ['analyze']);
    });

    test('after the market skills are known, the gap step is not sent',
        () async {
      final ai = FakeAi();
      var asked = 0;
      await expectLater(
        run(ai, AnalysisSettings.app, isCancelled: () => ++asked > 1),
        throwsA(isA<AnalysisCancelled>()),
      );
      expect(ai.calls, ['analyze', 'market']);
    });

    test('a screen that stays open gets its analysis', () async {
      final ai = FakeAi();
      final analysis =
          await run(ai, AnalysisSettings.app, isCancelled: () => false);
      expect(analysis['skillGaps'], ['Roadmap Planning']);
    });
  });

  group('saving', () {
    final refused = StateError('permission-denied');
    bool isRefusal(Object error) => identical(error, refused);

    test('a refused save is repeated once without the new fields', () async {
      final saved = <Map<String, dynamic>>[];
      final analysis = await run(FakeAi(), AnalysisSettings.app);
      await CareerAnalysisPipeline.saveWithFallback(
        analysis,
        save: (map) async {
          saved.add(map);
          if (saved.length == 1) throw refused;
        },
        isRefusal: isRefusal,
      );
      expect(saved, hasLength(2));
      expect(saved.last.keys, originalFields);
      expect(saved.last['skillGaps'], ['Roadmap Planning']);
    });

    test('a saved analysis needs only one write', () async {
      final saved = <Map<String, dynamic>>[];
      await CareerAnalysisPipeline.saveWithFallback(
        const {'skillGaps': <String>[], 'gapMethod': 'cv-evidence'},
        save: (map) async => saved.add(map),
        isRefusal: isRefusal,
      );
      expect(saved, hasLength(1));
      expect(saved.single['gapMethod'], 'cv-evidence');
    });

    test('other errors, and a refusal without new fields, are not hidden',
        () async {
      var writes = 0;
      await expectLater(
        CareerAnalysisPipeline.saveWithFallback(
          const {'gapMethod': 'cv-evidence'},
          save: (_) async {
            writes++;
            throw Exception('offline');
          },
          isRefusal: isRefusal,
        ),
        throwsException,
      );
      expect(writes, 1);

      writes = 0;
      await expectLater(
        CareerAnalysisPipeline.saveWithFallback(
          const {'skillGaps': <String>[]},
          save: (_) async {
            writes++;
            throw refused;
          },
          isRefusal: isRefusal,
        ),
        throwsStateError,
      );
      expect(writes, 1);
    });
  });

  group('catalogue names', () {
    test('the synonym table and the tags are known', () {
      expect(names.isKnown('product management'), isTrue);
      expect(names.isKnown('Databases and SQL'), isTrue);
      expect(names.isKnown('Astrology'), isFalse);
    });

    test('tags are read from the opportunities file, whatever its state', () {
      expect(
        CatalogueNames.opportunityTagsFromJson(
          '﻿[{"id": "a", "skills": ["Product Management", 7, "UX Research"]},'
          ' {"id": "b", "skills": ["Product Management", " "]}, {"id": "c"}, 3]',
        ),
        ['Product Management', 'UX Research'],
      );
      expect(CatalogueNames.opportunityTagsFromJson('not json'), isEmpty);
      expect(CatalogueNames.opportunityTagsFromJson('{"a": 1}'), isEmpty);
    });
  });
}
