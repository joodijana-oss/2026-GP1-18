import 'package:flutter_test/flutter_test.dart';
import 'package:masra/models/certification.dart';
import 'package:masra/models/gap_link.dart';
import 'package:masra/models/opportunity.dart';
import 'package:masra/services/content_based_recommender.dart';
import 'package:masra/services/opportunity_index.dart';
import 'package:masra/services/opportunity_recommender.dart';

final DateTime today = DateTime(2026, 11, 14);

Opportunity opp(
  String id, {
  String? title,
  String description = 'Description',
  List<String> objectives = const [],
  List<String> skills = const [],
  List<String> paths = const ['product_manager'],
}) {
  return Opportunity(
    id: id,
    source: 'coursera',
    provider: '',
    type: 'Course',
    title: title ?? id,
    description: description,
    objectives: objectives,
    requirements: const [],
    field: 'Field',
    location: 'Online',
    isFree: true,
    price: '',
    duration: '',
    url: 'https://example.com',
    skills: skills,
    careerPathIds: paths,
    startDate: null,
    endDate: null,
    registrationDeadline: null,
  );
}

Certification cert(
  String id, {
  String? name,
  List<String> skills = const [],
  String description = 'Description',
  List<String> paths = const ['product_manager'],
}) {
  return Certification(
    id: id,
    name: name ?? id,
    shortName: '',
    issuer: 'Issuer',
    examCode: '',
    level: 'Beginner',
    category: 'Category',
    description: description,
    descriptionAr: '',
    careerPaths: paths,
    skills: skills,
    officialUrl: 'https://example.com',
    verified: true,
    statusNote: '',
  );
}

/// A stored link. [concepts] are broader-skill names unless they are also
/// listed in [same].
Map<String, dynamic> link(
  String gap,
  List<String> concepts, {
  String kind = 'skill',
  List<String> same = const [],
  List<String> phrases = const [],
  List<String> terms = const [],
}) =>
    {
      'gap': gap,
      'kind': kind,
      'concepts': concepts,
      'same': same,
      'phrases': phrases,
      'terms': terms,
    };

Map<String, dynamic> analysis({
  List<String> gaps = const ['Roadmap Planning'],
  List<Map<String, dynamic>>? links,
}) {
  return {
    'careerGoalId': 'product_manager',
    'skillGaps': gaps,
    'currentSkills': const <String>[],
    'gapLinks': ?links,
  };
}

/// What a ranked list says, to compare two rankings exactly.
List<String> signature(OpportunityRecommendations result) => [
      for (final m in result.matched)
        '${m.opportunity.id}|${m.score}|${m.gapSkills.join(',')}|'
            '${m.gapCoverage}',
      'uncovered:${result.uncoveredGaps.join(',')}',
    ];

List<String> certSignature(CertificationRecommendations result) => [
      for (final m in result.matched)
        '${m.certification.id}|${m.matchedSkills.join(',')}',
      '--',
      for (final m in result.others) m.certification.id,
    ];

/// Two courses carry the tag "Product Management". Only one of them says
/// anything about a roadmap. "Planning" is a common word here (the meal
/// planning classes), "roadmap" is rare.
List<Opportunity> catalogue({int mealClasses = 10}) => [
      opp('pm_basics',
          title: 'Product Management Basics',
          description: 'The daily work of a product team.',
          skills: ['Product Management']),
      opp('pm_roadmap',
          title: 'Deciding What To Build',
          description: 'Build a roadmap for the next release.',
          skills: ['Product Management']),
      opp('pm_planning',
          title: 'Sprint Planning For Product Teams',
          description: 'Run a planning meeting.',
          skills: ['Product Management']),
      opp('sql_course', title: 'SQL for Everyone', skills: ['Databases and SQL']),
      for (var i = 0; i < mealClasses; i++)
        opp('meal_$i',
            title: 'Meal planning class $i',
            skills: ['Cooking'],
            paths: ['chef']),
      for (var i = 0; i < 40; i++)
        opp('filler_$i',
            title: 'Pottery class $i', skills: ['Pottery'], paths: ['potter']),
    ];

const LinkSettings gated = LinkSettings();

OpportunityRecommendations rank(
  Map<String, dynamic> analysis,
  List<Opportunity> list, {
  LinkSettings links = gated,
}) =>
    OpportunityRecommender(weights: RankingWeights(links: links))
        .recommend(analysis: analysis, opportunities: list, now: today);

List<String> teaching(OpportunityRecommendations result, String gap) => [
      for (final m in result.matched)
        if (m.gapSkills.contains(gap)) m.opportunity.id,
    ]..sort();

List<Certification> certifications() => [
      cert('cert_basics',
          name: 'Product Fundamentals Certificate',
          description: 'Covers the work of a product team.',
          skills: ['Product Management']),
      cert('cert_roadmap',
          name: 'Product Planning Certificate',
          description: 'Teaches how to keep a roadmap.',
          skills: ['Product Management']),
      cert('cert_sql', skills: ['SQL']),
      for (var i = 0; i < 10; i++)
        cert('cert_planning_$i',
            description: 'Event planning.',
            skills: ['Cooking'],
            paths: ['chef']),
      for (var i = 0; i < 40; i++)
        cert('cert_filler_$i', skills: ['Pottery'], paths: ['potter']),
    ];

List<String> certified(
  Map<String, dynamic> analysis,
  List<Certification> list, {
  LinkSettings links = gated,
  String gap = 'Roadmap Planning',
}) =>
    [
      for (final m in ContentBasedRecommender(links: links)
          .recommendCertifications(analysis: analysis, certifications: list)
          .matched)
        if (m.matchedSkills.contains(gap)) m.certification.id,
    ]..sort();

void main() {
  final broad = analysis(links: [
    link('Roadmap Planning', ['Product Management']),
  ]);
  final same = analysis(links: [
    link('Roadmap Planning', ['Product Management'],
        same: ['Product Management']),
  ]);

  group('the app', () {
    test('matching by meaning is switched off until it is chosen', () {
      expect(LinkSettings.requestedByApp, isFalse);
      expect(LinkSettings.appOpportunities.enabled, isFalse);
      expect(LinkSettings.appCertifications.enabled, isFalse);
      expect(const RankingWeights().links.enabled, isFalse);
      expect(const ContentBasedRecommender().links.enabled, isFalse);
    });
  });

  group('opportunities', () {
    test('an analysis without links is ranked exactly as with links off', () {
      final list = catalogue();
      final plain = analysis(gaps: ['Roadmap Planning', 'SQL']);
      final off = signature(rank(plain, list, links: LinkSettings.off));
      for (final settings in const [
        gated,
        LinkSettings.ungated,
        LinkSettings(termSupport: true, tagSupport: true, reasonOnly: true),
        LinkSettings(termEvidence: true, phraseSearch: true),
      ]) {
        expect(signature(rank(plain, list, links: settings)), off);
      }
    });

    test('with links off, stored links change nothing', () {
      final list = catalogue();
      expect(
        signature(rank(broad, list, links: LinkSettings.off)),
        signature(rank(analysis(), list, links: LinkSettings.off)),
      );
    });

    test('without the gate, every course with the linked tag counts', () {
      final result = rank(broad, catalogue(), links: LinkSettings.ungated);
      expect(teaching(result, 'Roadmap Planning'),
          ['pm_basics', 'pm_planning', 'pm_roadmap']);
      expect(result.uncoveredGaps, isEmpty);
    });

    test('a broader-skill link counts only where the text supports the gap',
        () {
      final result = rank(broad, catalogue());
      // "roadmap" is rare in this catalogue and pm_roadmap says it.
      // pm_planning only says "planning", a common word here; pm_basics
      // says neither.
      expect(teaching(result, 'Roadmap Planning'), ['pm_roadmap']);
      expect(result.uncoveredGaps, isEmpty);
      // The card shows the user's own gap name.
      final match =
          result.matched.firstWhere((m) => m.opportunity.id == 'pm_roadmap');
      expect(match.gapSkills, ['Roadmap Planning']);
    });

    test('a same-skill link needs no support', () {
      final result = rank(same, catalogue());
      expect(teaching(result, 'Roadmap Planning'),
          ['pm_basics', 'pm_planning', 'pm_roadmap']);
    });

    test('with broader links ignored, only same-skill links count', () {
      const sameOnly = LinkSettings(useCovers: false);
      expect(teaching(rank(broad, catalogue(), links: sameOnly),
          'Roadmap Planning'), isEmpty);
      expect(teaching(rank(same, catalogue(), links: sameOnly),
          'Roadmap Planning'), hasLength(3));
    });

    test('what is distinctive comes from the catalogue at run time', () {
      // The same word, "planning": common with the meal planning classes,
      // rare without them.
      final common = rank(broad, catalogue());
      expect(teaching(common, 'Roadmap Planning'), isNot(contains('pm_planning')));
      final rare = rank(broad, catalogue(mealClasses: 0));
      expect(teaching(rare, 'Roadmap Planning'),
          ['pm_planning', 'pm_roadmap']);
      // A larger share lets the common word count too.
      final loose =
          rank(broad, catalogue(), links: const LinkSettings(theta: 0.5));
      expect(teaching(loose, 'Roadmap Planning'),
          ['pm_planning', 'pm_roadmap']);
    });

    test('the support test reads the index', () {
      final index = OpportunityIndex.build(catalogue());
      Set<String> ids(Set<int> docs) =>
          {for (final i in docs) index.opportunityAt(i).id};
      expect(ids(index.supportFor('Roadmap Planning', theta: 0.05)),
          {'pm_roadmap'});
      // The whole name as a phrase counts whatever the shares are.
      expect(ids(index.supportFor('Planning Meeting', theta: 0)),
          {'pm_planning'});
      // Tags count only when asked for: "databases" is only in the tag of
      // the SQL course, never in a title or a description.
      expect(ids(index.supportFor('Databases Tuning', theta: 0.05)), isEmpty);
      expect(ids(index.supportFor('Databases Tuning', theta: 0.05, tags: true)),
          {'sql_course'});
      // A number is not a word of the subject: "10" is in one title only
      // (Pottery class 10), but it says nothing about a release.
      expect(ids(index.supportFor('Release 10', theta: 0.05)), {'pm_roadmap'});
    });

    test('a hole gap linked to a broader name keeps its own place on the '
        'cards when the broader name is a gap too', () {
      final whole = analysis(
        gaps: ['Product Management', 'Roadmap Planning'],
        links: [
          link('Roadmap Planning', ['Product Management']),
        ],
      );
      final result = rank(whole, catalogue());
      List<String> reasonOf(String id) =>
          result.matched.firstWhere((m) => m.opportunity.id == id).gapSkills;
      // The course that shows the roadmap is said to teach both gaps; the
      // others only the one they carry the tag of.
      expect(reasonOf('pm_roadmap'), ['Product Management', 'Roadmap Planning']);
      expect(reasonOf('pm_basics'), ['Product Management']);
      expect(teaching(result, 'Roadmap Planning'), ['pm_roadmap']);
      expect(result.uncoveredGaps, isEmpty);
      // It ranks first: it covers both gaps.
      expect(result.matched.first.opportunity.id, 'pm_roadmap');

      // Without the gate every course with the tag counts for the hole gap,
      // so it is one aspect with the broader gap and no course is rewarded
      // twice for the same tag.
      final ungated = rank(whole, catalogue(), links: LinkSettings.ungated);
      expect(
          ungated.matched
              .firstWhere((m) => m.opportunity.id == 'pm_roadmap')
              .gapSkills,
          ['Product Management']);

      // Reason-only keeps the tag's evidence for the ranking, so the two
      // gaps share an aspect; the hole gap is still named where the text
      // supports it, and nowhere else.
      final reasonOnly =
          rank(whole, catalogue(), links: const LinkSettings(reasonOnly: true));
      List<String> reasonOnlyOf(String id) => reasonOnly.matched
          .firstWhere((m) => m.opportunity.id == id)
          .gapSkills;
      expect(reasonOnlyOf('pm_roadmap'),
          ['Product Management', 'Roadmap Planning']);
      expect(reasonOnlyOf('pm_basics'), ['Product Management']);
      expect(reasonOnly.uncoveredGaps, isEmpty);
    });

    test('a separate field of study never uses links', () {
      final result = rank(
        analysis(gaps: ['Computer Vision'], links: [
          link('Computer Vision', ['Product Management'],
              same: ['Product Management']),
        ]),
        catalogue(),
        links: LinkSettings.ungated,
      );
      expect(teaching(result, 'Computer Vision'), isEmpty);
      expect(result.uncoveredGaps, ['Computer Vision']);
    });

    test('a stored term supports only when the setting says so: one word '
        'when it is distinctive, more words as a phrase', () {
      const withTerms = LinkSettings(termSupport: true);
      Map<String, dynamic> withTerm(String term) => analysis(links: [
            link('Release Scoping', ['Product Management'], terms: [term]),
          ], gaps: ['Release Scoping']);
      List<String> found(String term, LinkSettings settings) => teaching(
          rank(withTerm(term), catalogue(), links: settings),
          'Release Scoping');

      // Without the switch a term is not looked at ("release" is in the
      // gap name itself, so that course is supported anyway).
      expect(found('daily work', gated), ['pm_roadmap']);
      // A phrase must be there as a phrase.
      expect(found('daily work', withTerms), ['pm_basics', 'pm_roadmap']);
      expect(found('work daily', withTerms), ['pm_roadmap']);
      // One word: "planning" is common, "sprint" is rare.
      expect(found('planning', withTerms), ['pm_roadmap']);
      expect(found('sprint', withTerms), ['pm_planning', 'pm_roadmap']);
    });

    test('reason-only keeps an unsupported course in the ranking but does '
        'not name the gap on it', () {
      final result = rank(broad, catalogue(),
          links: const LinkSettings(reasonOnly: true));
      expect(teaching(result, 'Roadmap Planning'), ['pm_roadmap']);
      final basics =
          result.matched.firstWhere((m) => m.opportunity.id == 'pm_basics');
      expect(basics.gapSkills, isEmpty);
      expect(basics.score, greaterThan(0));
      // Without it the unsupported course has no evidence at all.
      final strict = rank(broad, catalogue());
      expect(
          strict.matched
              .firstWhere((m) => m.opportunity.id == 'pm_basics')
              .score,
          0);
    });

    test('a tool, a certification, a specific product and a gap that a tag '
        'covers never use links', () {
      final list = catalogue();
      for (final kind in const ['tool', 'certification']) {
        final result = rank(
          analysis(links: [
            link('Roadmap Planning', ['Product Management'],
                same: ['Product Management'], kind: kind),
          ]),
          list,
          links: LinkSettings.ungated,
        );
        expect(teaching(result, 'Roadmap Planning'), isEmpty);
      }
      // "Tableau" is a specific product in the table.
      final product = rank(
        analysis(gaps: ['Tableau'], links: [
          link('Tableau', ['Product Management'], same: ['Product Management']),
        ]),
        list,
        links: LinkSettings.ungated,
      );
      expect(teaching(product, 'Tableau'), isEmpty);
      // "SQL" is covered by the tag "Databases and SQL": the link is not
      // used, so the product courses are not attributed to it.
      final covered = rank(
        analysis(gaps: ['SQL'], links: [
          link('SQL', ['Product Management'], same: ['Product Management']),
        ]),
        list,
        links: LinkSettings.ungated,
      );
      expect(teaching(covered, 'SQL'), ['sql_course']);
    });

    test('a hole with no linked name can be found by a stored term of two '
        'words or more, when the setting allows it', () {
      final bare = analysis(links: [
        link('Roadmap Planning', const [], terms: ['next release', 'roadmap']),
      ]);
      expect(teaching(rank(bare, catalogue()), 'Roadmap Planning'), isEmpty);
      expect(
        teaching(
            rank(bare, catalogue(),
                links: const LinkSettings(termEvidence: true)),
            'Roadmap Planning'),
        ['pm_roadmap'],
      );
    });

    test('the background call passes the links on', () async {
      final list = catalogue();
      final here = rank(broad, list);
      final there = await OpportunityRecommender(
              weights: const RankingWeights(links: gated))
          .recommendInBackground(
              analysis: broad, opportunities: catalogue(), now: today);
      expect(signature(there), signature(here));
    });
  });

  group('certifications', () {
    test('an analysis without links gives the list of links off', () {
      final list = certifications();
      final plain = analysis(gaps: ['Roadmap Planning', 'SQL']);
      List<String> run(LinkSettings settings) => certSignature(
          ContentBasedRecommender(links: settings)
              .recommendCertifications(analysis: plain, certifications: list));
      final off = run(LinkSettings.off);
      for (final settings in const [
        gated,
        LinkSettings.ungated,
        LinkSettings(termSupport: true, tagSupport: true),
        LinkSettings(termEvidence: true, phraseSearch: true),
      ]) {
        expect(run(settings), off);
      }
    });

    test('the same gate decides the matched skills', () {
      final list = certifications();
      expect(certified(broad, list, links: LinkSettings.off), isEmpty);
      expect(certified(broad, list, links: LinkSettings.ungated),
          ['cert_basics', 'cert_roadmap']);
      // "planning" is in the name of cert_roadmap but it is common here;
      // "roadmap" is rare and only cert_roadmap says it.
      expect(certified(broad, list), ['cert_roadmap']);
      expect(certified(same, list), ['cert_basics', 'cert_roadmap']);
      expect(certified(broad, list, links: const LinkSettings(useCovers: false)),
          isEmpty);
    });

    test('distinctive is counted from the list it is given', () {
      final small = [
        for (final c in certifications())
          if (!c.id.startsWith('cert_planning')) c,
      ];
      // Without the event planning certificates "planning" is rare, but no
      // product certificate says it outside cert_roadmap's name.
      expect(certified(broad, small), ['cert_roadmap']);
      final texts = CertificationTexts.of(small);
      expect(texts.supportFor('Roadmap Planning', theta: 0.05), {1});
      // "description" is the whole text of most certificates here.
      expect(texts.supportFor('Description Writing', theta: 0.05), isEmpty);
      expect(texts.supportFor('Product Team', theta: 0), {0});
    });

    test('a tool, a certification and a gap that a certification skill '
        'matches never use links', () {
      final list = certifications();
      expect(
        certified(
            analysis(links: [
              link('Roadmap Planning', ['Product Management'],
                  same: ['Product Management'], kind: 'tool'),
            ]),
            list,
            links: LinkSettings.ungated),
        isEmpty,
      );
      expect(
        certified(
            analysis(gaps: ['SQL'], links: [
              link('SQL', ['Product Management'], same: ['Product Management']),
            ]),
            list,
            links: LinkSettings.ungated,
            gap: 'SQL'),
        ['cert_sql'],
      );
    });

    test('a specific product and a separate field of study never use links',
        () {
      final list = certifications();
      for (final gap in const ['Tableau', 'Computer Vision']) {
        expect(
          certified(
              analysis(gaps: [gap], links: [
                link(gap, ['Product Management'],
                    same: ['Product Management']),
              ]),
              list,
              links: LinkSettings.ungated,
              gap: gap),
          isEmpty,
          reason: gap,
        );
      }
    });

    test('a stored term supports a certification only when the setting says '
        'so: one word when it is distinctive, more words as a phrase', () {
      const withTerms = LinkSettings(termSupport: true);
      List<String> found(String term, LinkSettings settings) => certified(
            analysis(gaps: ['Release Scoping'], links: [
              link('Release Scoping', ['Product Management'], terms: [term]),
            ]),
            certifications(),
            links: settings,
            gap: 'Release Scoping',
          );

      // No word of the gap is in a certification text, so without terms
      // nothing supports it.
      expect(found('roadmap', gated), isEmpty);
      // "roadmap" is rare; "planning" is in the event planning ones too.
      expect(found('roadmap', withTerms), ['cert_roadmap']);
      expect(found('planning', withTerms), isEmpty);
      // A phrase must be there as a phrase.
      expect(found('product team', withTerms), ['cert_basics']);
      expect(found('team product', withTerms), isEmpty);
    });

    test('current skills never use links', () {
      final result = const ContentBasedRecommender(links: LinkSettings.ungated)
          .recommendCertifications(
        analysis: {
          'careerGoalId': 'product_manager',
          'skillGaps': const <String>[],
          'currentSkills': const ['Roadmap Planning'],
          'gapLinks': [
            link('Roadmap Planning', ['Product Management']),
          ],
        },
        certifications: certifications(),
        goal: CertificationGoal.strengthenSkills,
      );
      expect(result.matched, isEmpty);
    });
  });

  group('stored links', () {
    test('a link of the first request reads as broader-skill names', () {
      final links = GapLink.listFrom([
        {
          'gap': 'Roadmap Planning',
          'kind': 'skill',
          'concepts': ['Product Management'],
          'phrases': ['product roadmap'],
        },
      ]);
      expect(links.single.same, isEmpty);
      expect(links.single.covers, ['Product Management']);
      expect(links.single.supportTerms, ['product roadmap']);
    });

    test('a typed link keeps its two kinds apart and survives a round trip',
        () {
      const typed = GapLink(
        gap: 'Roadmap Planning',
        concepts: ['Product Planning', 'Product Management'],
        same: ['Product Planning'],
        terms: ['roadmap'],
      );
      final back = GapLink.listFrom([typed.toMap()]).single;
      expect(back.same, ['Product Planning']);
      expect(back.covers, ['Product Management']);
      expect(back.terms, ['roadmap']);
      expect(back.isProduct, isFalse);
    });

    test('anything unusable is skipped', () {
      expect(GapLink.listFrom(null), isEmpty);
      expect(GapLink.listFrom('links'), isEmpty);
      expect(
        GapLink.listFrom([
          42,
          {'gap': ''},
          {'gap': 'Roadmap Planning', 'kind': 'unknown', 'same': ['Other']},
        ]).map((l) => '${l.gap}|${l.kind}|${l.same}'),
        ['Roadmap Planning|skill|[]'],
      );
    });
  });
}
