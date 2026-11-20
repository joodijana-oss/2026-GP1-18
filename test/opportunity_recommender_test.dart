import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:masra/models/opportunity.dart';
import 'package:masra/services/opportunity_index.dart';
import 'package:masra/services/opportunity_recommender.dart';

final DateTime today = DateTime(2026, 11, 14);

Opportunity opp(
  String id, {
  String source = 'coursera',
  String provider = '',
  String type = 'Course',
  String? title,
  String description = 'Description',
  List<String> objectives = const [],
  List<String> requirements = const [],
  List<String> skills = const [],
  List<String> paths = const [],
  DateTime? start,
  DateTime? end,
  DateTime? deadline,
}) {
  return Opportunity(
    id: id,
    source: source,
    provider: provider,
    type: type,
    title: title ?? id,
    description: description,
    objectives: objectives,
    requirements: requirements,
    field: 'Field',
    location: 'Online',
    isFree: true,
    price: '',
    duration: '',
    url: 'https://example.com',
    skills: skills,
    careerPathIds: paths,
    startDate: start,
    endDate: end,
    registrationDeadline: deadline,
  );
}

Map<String, dynamic> analysis({
  String goal = 'data_analyst',
  List<String> gaps = const ['SQL', 'Power BI'],
  List<String> current = const ['Python', 'Excel'],
  List<String>? targets,
}) {
  return {
    'careerGoalId': goal,
    'skillGaps': gaps,
    'currentSkills': current,
    'targetSkills': ?targets,
  };
}

List<String> ids(List<OpportunityMatch> matches) =>
    matches.map((m) => m.opportunity.id).toList();

/// Unrelated opportunities, so that a skill found in one or two records is
/// rare in the catalogue, as it is in the real data.
List<Opportunity> fillers(int count) => [
      for (var i = 0; i < count; i++)
        opp('filler_$i',
            title: 'Cooking class $i', skills: ['Cooking'], paths: ['chef']),
    ];

void main() {
  const recommender = OpportunityRecommender();

  OpportunityRecommendations recommend(
    List<Opportunity> opportunities, {
    Map<String, dynamic>? data,
    String? level,
    RankingWeights weights = const RankingWeights(),
  }) {
    return OpportunityRecommender(weights: weights).recommend(
      analysis: data ?? analysis(),
      opportunities: opportunities,
      now: today,
      experienceLevel: level,
    );
  }

  OpportunityMatch only(OpportunityRecommendations recs, String id) =>
      recs.matched.firstWhere((m) => m.opportunity.id == id);

  test('closed events are hidden and counted', () {
    final recs = recommend([
      opp('deadline_passed',
          source: 'tuwaiq',
          paths: ['data_analyst'],
          deadline: DateTime(2026, 11, 13),
          start: DateTime(2026, 11, 20)),
      opp('already_started',
          source: 'tuwaiq',
          paths: ['data_analyst'],
          start: DateTime(2026, 11, 1)),
      opp('deadline_today',
          source: 'tuwaiq',
          paths: ['data_analyst'],
          deadline: DateTime(2026, 11, 14)),
      opp('self_paced', paths: ['data_analyst']),
    ]);
    expect(ids(recs.matched), ['deadline_today', 'self_paced']);
    expect(recs.closedHidden, 2);
  });

  test('gap matching uses SkillMatcher synonyms', () {
    final recs = recommend([
      opp('db_course', skills: ['Databases and SQL']),
    ]);
    final match = only(recs, 'db_course');
    expect(match.gapSkills, ['SQL']);
    expect(match.goalRelated, isFalse);
  });

  test('a specific tool like React only matches when mentioned', () {
    final recs = recommend(
      [
        opp('general_frontend',
            skills: ['Frontend Frameworks'],
            description: 'Build modern web interfaces.'),
        opp('mentions_tool',
            skills: ['Frontend Frameworks'],
            description: 'Build web apps with React.'),
      ],
      data: analysis(goal: 'web_developer', gaps: ['React']),
    );
    expect(ids(recs.matched), ['mentions_tool']);
    expect(only(recs, 'mentions_tool').gapSkills, ['React']);
  });

  test('requirements are not evidence, objectives are', () {
    final recs = recommend(
      [
        opp('in_requirements',
            requirements: ['Experience with Power BI'],
            skills: ['Excel']),
        opp('in_objectives',
            objectives: ['Build dashboards in Power BI'],
            skills: ['Excel']),
      ],
      data: analysis(goal: '', gaps: ['Power BI']),
    );
    expect(ids(recs.matched), ['in_objectives']);
    expect(only(recs, 'in_objectives').gapSkills, ['Power BI']);
  });

  test('an opportunity for the career goal matches without gaps', () {
    final recs = recommend([
      opp('goal_only', skills: ['Linux'], paths: ['data_analyst']),
    ]);
    final match = only(recs, 'goal_only');
    expect(match.gapSkills, isEmpty);
    expect(match.goalRelated, isTrue);
    expect(match.score, 0);
    expect(match.gapCoverage, isEmpty);
  });

  test('unrelated opportunities and current skills alone are excluded', () {
    final recs = recommend([
      opp('unrelated', skills: ['Linux'], paths: ['network_engineer']),
      opp('current_only', skills: ['Python'], paths: ['software_engineer']),
    ]);
    expect(recs.matched, isEmpty);
    expect(recs.isEmpty, isTrue);
    expect(recs.closedHidden, 0);
  });

  test('current skills never repeat a gap skill', () {
    final recs = recommend(
      [
        opp('sql_python', skills: ['Databases and SQL', 'Python']),
      ],
      data: analysis(gaps: ['SQL'], current: ['Python', 'Databases']),
    );
    final match = only(recs, 'sql_python');
    expect(match.gapSkills, ['SQL']);
    expect(match.currentSkills, ['Python']);
    expect(match.score, greaterThan(0));
  });

  group('finding gaps', () {
    test('a one-word gap is found in a title (Microservices)', () {
      final recs = recommend(
        [
          ...fillers(30),
          opp('serverless',
              title:
                  'Application Development using Microservices and Serverless',
              skills: ['Cloud Computing']),
        ],
        data: analysis(goal: 'software_engineer', gaps: ['Microservices']),
      );
      expect(ids(recs.matched), ['serverless']);
      expect(only(recs, 'serverless').gapSkills, ['Microservices']);
    });

    test('singular and plural names find each other', () {
      final recs = recommend(
        [
          ...fillers(30),
          opp('building', title: 'Building Microservices'),
        ],
        data: analysis(goal: 'software_engineer', gaps: ['Microservice']),
      );
      expect(ids(recs.matched), ['building']);
    });

    test('one passing word in a description is not evidence, two are', () {
      final recs = recommend(
        [
          ...fillers(30),
          opp('passing',
              title: 'Database Administration',
              description: 'Covers backups, indexes and statistics.'),
          opp('taught',
              title: 'Numbers for analysts',
              description:
                  'Statistics from the start. Practise statistics on data.'),
        ],
        data: analysis(goal: '', gaps: ['Statistics']),
      );
      expect(ids(recs.matched), ['taught']);
    });

    test('gap skills keep the order of the analysis', () {
      final recs = recommend(
        [
          opp('both', skills: ['Power BI', 'Databases and SQL']),
        ],
      );
      expect(only(recs, 'both').gapSkills, ['SQL', 'Power BI']);
      expect(only(recs, 'both').gapCoverage.keys, ['SQL', 'Power BI']);
    });
  });

  group('tiers', () {
    test('a goal-only opportunity never outranks one that teaches a gap', () {
      final recs = recommend(
        [
          ...fillers(30),
          opp('big_goal_only',
              source: 'tuwaiq',
              type: 'Bootcamp',
              title: 'Cloud Engineering Bootcamp',
              paths: ['cloud_devops_engineer'],
              start: DateTime(2026, 12, 1),
              end: DateTime(2027, 3, 1),
              deadline: DateTime(2026, 11, 25)),
          opp('small_webinar',
              source: 'doroob',
              type: 'Webinar',
              title: 'Containers in one hour',
              description: 'What Docker is, and how to run Docker images.',
              paths: ['software_engineer']),
        ],
        data: analysis(goal: 'cloud_devops_engineer', gaps: ['Docker']),
      );
      expect(ids(recs.matched), ['small_webinar', 'big_goal_only']);
      expect(only(recs, 'small_webinar').score, greaterThan(0));
      expect(only(recs, 'small_webinar').goalRelated, isFalse);
      expect(only(recs, 'big_goal_only').score, 0);
      expect(only(recs, 'big_goal_only').gapSkills, isEmpty);
    });

    test(
        'goal-only order: dated events, then nearest date, current skills, '
        'title', () {
      final recs = recommend(
        [
          opp('beta', title: 'Beta', paths: ['data_analyst']),
          opp('alpha', title: 'Alpha', paths: ['data_analyst']),
          opp('builds_on_skills',
              paths: ['data_analyst'], skills: ['Python', 'Excel']),
          opp('event_later',
              source: 'tuwaiq',
              paths: ['data_analyst'],
              deadline: DateTime(2026, 12, 10)),
          opp('event_sooner',
              source: 'tuwaiq',
              paths: ['data_analyst'],
              start: DateTime(2026, 12, 1)),
          opp('one_gap',
              skills: ['Databases and SQL'], paths: ['data_analyst']),
          opp('two_gaps',
              skills: ['Databases and SQL', 'Power BI'],
              paths: ['data_analyst']),
        ],
        data: analysis(current: ['Python', 'Excel']),
      );

      expect(ids(recs.matched), [
        'two_gaps', // teaches both gaps
        'one_gap', // teaches one gap
        'event_sooner', // goal only, dated, 1 Dec
        'event_later', // goal only, dated, 10 Dec
        'builds_on_skills', // goal only, builds on two current skills
        'alpha', // goal only, by title
        'beta',
      ]);
      expect(only(recs, 'builds_on_skills').currentSkills, ['Python', 'Excel']);
    });

    test('goal-only order prefers deeper opportunities of the same kind', () {
      final recs = recommend([
        opp('webinar', type: 'Webinar', title: 'A', paths: ['data_analyst']),
        opp('bootcamp', type: 'Bootcamp', title: 'B', paths: ['data_analyst']),
      ]);
      expect(ids(recs.matched), ['bootcamp', 'webinar']);
    });
  });

  group('ranking', () {
    test('coverage: the first results cover different gaps', () {
      final list = [
        ...fillers(30),
        opp('a1',
            title: 'SQL Fundamentals',
            skills: ['Databases and SQL'],
            paths: ['data_analyst']),
        opp('a2',
            title: 'SQL Essentials',
            skills: ['Databases and SQL'],
            paths: ['data_analyst']),
        opp('b1',
            title: 'Reporting for business',
            description: 'Learn Power BI step by step.',
            paths: ['data_analyst']),
      ];

      // With the re-ranking, the second pick goes to the gap still open.
      final diverse = recommend(list);
      expect(ids(diverse.matched).take(2), contains('b1'));

      // Without it, the two strongest matches come first, both on SQL.
      final plain =
          recommend(list, weights: const RankingWeights(diversity: 0));
      expect(ids(plain.matched).take(2).toSet(), {'a1', 'a2'});
      expect(ids(plain.matched).last, 'b1');
    });

    test('market demand: the first gap weighs more', () {
      final list = [
        ...fillers(30),
        opp('kubernetes', title: 'Kubernetes Basics'),
        opp('terraform', title: 'Terraform Basics'),
      ];
      final byGapOrder = recommend(list,
          data: analysis(goal: '', gaps: ['Kubernetes', 'Terraform']));
      expect(ids(byGapOrder.matched), ['kubernetes', 'terraform']);

      // The market order of the analysis wins over the gap order.
      final byMarket = recommend(list,
          data: analysis(
              goal: '',
              gaps: ['Kubernetes', 'Terraform'],
              targets: ['Terraform', 'Linux', 'Kubernetes']));
      expect(ids(byMarket.matched), ['terraform', 'kubernetes']);

      // A market list that misses a gap is not used at all.
      final incomplete = recommend(list,
          data: analysis(
              goal: '',
              gaps: ['Kubernetes', 'Terraform'],
              targets: ['Terraform', 'Linux']));
      expect(ids(incomplete.matched), ['kubernetes', 'terraform']);
    });

    test('depth: a bootcamp covers a gap more than a webinar', () {
      final recs = recommend(
        [
          ...fillers(30),
          opp('webinar',
              source: 'tuwaiq',
              type: 'Webinar',
              title: 'Kubernetes',
              skills: ['Kubernetes'],
              start: DateTime(2026, 12, 1),
              end: DateTime(2026, 12, 1)),
          opp('bootcamp',
              source: 'tuwaiq',
              type: 'Bootcamp',
              title: 'Kubernetes',
              skills: ['Kubernetes'],
              start: DateTime(2026, 12, 1),
              end: DateTime(2027, 2, 1)),
        ],
        data: analysis(goal: '', gaps: ['Kubernetes']),
      );
      expect(ids(recs.matched), ['bootcamp', 'webinar']);
      expect(
        only(recs, 'bootcamp').gapCoverage['Kubernetes']!,
        greaterThan(only(recs, 'webinar').gapCoverage['Kubernetes']!),
      );
    });

    test('level: too advanced ranks lower, too easy does not', () {
      final list = [
        ...fillers(30),
        opp('advanced',
            title: 'Advanced Kubernetes', skills: ['Kubernetes']),
        opp('basics', title: 'Kubernetes Basics', skills: ['Kubernetes']),
      ];
      final data = analysis(goal: '', gaps: ['Kubernetes']);
      double coverage(OpportunityRecommendations recs, String id) =>
          only(recs, id).gapCoverage['Kubernetes']!;

      final beginner = recommend(list, data: data, level: 'Beginner');
      expect(ids(beginner.matched), ['basics', 'advanced']);
      expect(
        coverage(beginner, 'advanced') / coverage(beginner, 'basics'),
        closeTo(0.7, 1e-9),
      );

      // An intermediate user still lacks the skill: the basics are not
      // lowered.
      final intermediate = recommend(list, data: data, level: 'Intermediate');
      expect(coverage(intermediate, 'basics'),
          greaterThan(coverage(intermediate, 'advanced')));
      expect(
        coverage(intermediate, 'advanced') / coverage(intermediate, 'basics'),
        closeTo(0.85, 1e-9),
      );

      // An advanced user still lacks the skill: the basics are not lowered.
      final advanced = recommend(list, data: data, level: 'Advanced');
      expect(coverage(advanced, 'advanced'),
          closeTo(coverage(advanced, 'basics'), 1e-9));

      // The optional step for easier opportunities (off by default).
      final easier = recommend(list,
          data: data,
          level: 'Advanced',
          weights: const RankingWeights(easierStep: 0.1));
      expect(ids(easier.matched), ['advanced', 'basics']);
      expect(
        coverage(easier, 'basics') / coverage(easier, 'advanced'),
        closeTo(0.8, 1e-9),
      );

      // An unknown level changes nothing.
      final unknown = recommend(list, data: data, level: 'Expert');
      expect(coverage(unknown, 'advanced'),
          closeTo(coverage(unknown, 'basics'), 1e-9));
    });

    test('IDF: a rare skill counts more than a common one', () {
      final list = [
        for (var i = 0; i < 12; i++) opp('python_$i', title: 'Basic Python'),
        opp('kafka', title: 'Using Kafka'),
      ];
      final data = analysis(goal: '', gaps: ['Python', 'Kafka'], current: []);

      final withIdf = recommend(list,
          data: data,
          weights: const RankingWeights(demandDecay: 1, diversity: 0));
      expect(ids(withIdf.matched).first, 'kafka');

      // Without IDF all thirteen tie, and the title decides.
      final withoutIdf = recommend(list,
          data: data,
          weights: const RankingWeights(
              demandDecay: 1, diversity: 0, useIdf: false));
      expect(ids(withoutIdf.matched).first, 'python_0');
      expect(ids(withoutIdf.matched).last, 'kafka');
    });

    test('field weights: a title match beats a description match', () {
      final recs = recommend(
        [
          ...fillers(30),
          opp('in_description',
              title: 'Managing Company Data',
              description: 'An overview of data governance.'),
          opp('in_title', title: 'Data Governance Explained'),
        ],
        data: analysis(goal: '', gaps: ['Data Governance']),
      );
      expect(ids(recs.matched), ['in_title', 'in_description']);
    });

    test('career goal: outside the career path ranks lower', () {
      final recs = recommend(
        [
          ...fillers(30),
          opp('outside', title: 'Kubernetes Basics', paths: ['other_path']),
          opp('inside', title: 'Kubernetes Basics', paths: ['data_analyst']),
        ],
        data: analysis(gaps: ['Kubernetes']),
      );
      expect(ids(recs.matched), ['inside', 'outside']);
      expect(
        only(recs, 'outside').gapCoverage['Kubernetes']! /
            only(recs, 'inside').gapCoverage['Kubernetes']!,
        closeTo(0.8, 1e-9),
      );
    });

    test('two names of one skill are one aspect, not counted twice', () {
      final list = [
        ...fillers(30),
        opp('routing', title: 'Network Course A', skills: [
          'Routing and Switching',
        ]),
        opp('wireless', title: 'Network Course B', skills: [
          'Wireless Networks',
        ]),
      ];
      final recs = recommend(list,
          data: analysis(
              goal: '', gaps: ['Wireless', 'Switching', 'Routing']));

      // Both names are reported ...
      expect(only(recs, 'routing').gapSkills, ['Switching', 'Routing']);
      // ... but they weigh as one skill, so the more demanded Wireless gap
      // still comes first.
      expect(ids(recs.matched), ['wireless', 'routing']);
    });

    test('equal gains: dated events first, then title, then id', () {
      final recs = recommend(
        [
          ...fillers(30),
          opp('z_id', title: 'Kubernetes Basics'),
          opp('a_id', title: 'Kubernetes Basics'),
          opp('b_title', title: 'Kubernetes Advice'),
          opp('dated',
              title: 'Kubernetes Sprint', deadline: DateTime(2026, 12, 1)),
        ],
        data: analysis(goal: '', gaps: ['Kubernetes']),
        weights: const RankingWeights(diversity: 0),
      );
      expect(ids(recs.matched), ['dated', 'b_title', 'a_id', 'z_id']);
    });

    test('scores are between 0 and 1 and never rise down the list', () {
      final recs = recommend([
        ...fillers(30),
        opp('a', title: 'SQL Fundamentals', skills: ['Databases and SQL']),
        opp('b', title: 'Power BI Dashboards', paths: ['data_analyst']),
        opp('c',
            type: 'Webinar',
            title: 'SQL and Power BI',
            paths: ['data_analyst']),
        opp('d', description: 'SQL queries for reports.'),
        opp('e', title: 'Goal only', paths: ['data_analyst']),
      ]);
      final scores = recs.matched.map((m) => m.score).toList();
      expect(scores.first, closeTo(1, 1e-9));
      for (var i = 1; i < scores.length; i++) {
        expect(scores[i], lessThanOrEqualTo(scores[i - 1] + 1e-12));
      }
      expect(scores.every((s) => s >= 0 && s <= 1 + 1e-12), isTrue);
      expect(recs.matched.last.opportunity.id, 'e');
    });

    test('the index does not remember the weights of an earlier call', () {
      final list = [
        opp('webinar',
            type: 'Webinar',
            title: 'Kubernetes',
            skills: ['Kubernetes'],
            paths: ['data_analyst']),
      ];
      final data = analysis(gaps: ['Kubernetes']);

      final usual = recommend(list, data: data);
      final noDepth = recommend(list,
          data: data, weights: const RankingWeights(depthFloor: 1));
      final usualAgain = recommend(list, data: data);

      final depth = OpportunityRecommender.depthOf(1.5);
      expect(only(usual, 'webinar').gapCoverage['Kubernetes'],
          closeTo(depth, 1e-9));
      expect(only(noDepth, 'webinar').gapCoverage['Kubernetes'],
          closeTo(1, 1e-9));
      expect(only(usualAgain, 'webinar').gapCoverage['Kubernetes'],
          closeTo(depth, 1e-9));
    });

    test('the same input gives the same list', () {
      final list = [
        ...fillers(10),
        opp('a', title: 'SQL Fundamentals', skills: ['Databases and SQL']),
        opp('b', title: 'Power BI Dashboards', paths: ['data_analyst']),
        opp('c', title: 'Goal only', paths: ['data_analyst']),
      ];
      final first = recommend(list);
      final second = recommend(List<Opportunity>.of(list));
      expect(ids(second.matched), ids(first.matched));
      expect(second.matched.map((m) => m.score),
          first.matched.map((m) => m.score));
    });
  });

  group('reasons follow the evidence', () {
    test('query expansion is off: another name of the group is not enough',
        () {
      final list = [
        ...fillers(30),
        opp('vm',
            title: 'Vulnerability Management Program',
            paths: ['cybersecurity_analyst']),
      ];
      final data = analysis(
          goal: 'cybersecurity_analyst', gaps: ['Penetration Testing']);
      final usual = recommend(list, data: data);
      expect(usual.matched.single.gapSkills, isEmpty,
          reason: 'Listed for the career goal only.');

      final expanded = recommend(list,
          data: data, weights: const RankingWeights(expandSynonyms: true));
      expect(only(expanded, 'vm').gapSkills, ['Penetration Testing']);
    });

    test('a Computer Vision course does not claim NLP', () {
      final recs = recommend(
        [
          ...fillers(30),
          opp('cv',
              title: 'Applied Computer Vision',
              skills: ['Deep Learning', 'PyTorch']),
          opp('nlp',
              title: 'Text models',
              skills: ['Natural Language Processing', 'Deep Learning']),
        ],
        data: analysis(
            goal: 'ai_ml_engineer',
            gaps: ['Deep Learning', 'NLP', 'Computer Vision']),
      );
      expect(only(recs, 'cv').gapSkills, ['Deep Learning', 'Computer Vision']);
      expect(only(recs, 'nlp').gapSkills, ['Deep Learning', 'NLP']);
      expect(only(recs, 'cv').gapCoverage.keys,
          ['Deep Learning', 'Computer Vision']);
    });

    test('of one aspect, only the gaps the opportunity names are listed', () {
      final recs = recommend(
        [
          ...fillers(30),
          opp('vpn', title: 'VPN Basics', skills: ['Network Security']),
          opp('generic',
              title: 'Protecting company systems',
              skills: ['Network Defense']),
        ],
        data: analysis(
            goal: '', gaps: ['Firewall', 'Network Security', 'VPN']),
      );
      // The tag names Network Security, the title names VPN.
      expect(only(recs, 'vpn').gapSkills, ['Network Security', 'VPN']);
      // Names none of them: the most demanded one is shown.
      expect(only(recs, 'generic').gapSkills, ['Firewall']);
    });

    test('C# and C++ are different gaps', () {
      final recs = recommend(
        [
          ...fillers(30),
          opp('c', title: 'C for Everyone', skills: ['C']),
          opp('csharp', title: 'C# Fundamentals'),
          opp('list',
              title: 'Language models',
              description: 'a) read text b) train c) use T5. Then c) again.'),
        ],
        data: analysis(goal: '', gaps: ['C#', 'C++']),
      );
      expect(ids(recs.matched), ['csharp']);
      expect(only(recs, 'csharp').gapSkills, ['C#']);
      expect(recs.uncoveredGaps, ['C++']);
    });

    test('a loose objective mention counts only inside the career path', () {
      const objective = 'Analyze network traffic and apply defense, '
          'monitoring and initial response controls.';
      final recs = recommend(
        [
          ...fillers(30),
          opp('in_path',
              title: 'Cloud Programme',
              objectives: [objective],
              paths: ['cloud_devops_engineer']),
          opp('outside',
              title: 'Security Diploma',
              objectives: [objective],
              paths: ['cybersecurity_analyst']),
        ],
        data: analysis(goal: 'cloud_devops_engineer', gaps: ['Monitoring']),
      );
      expect(ids(recs.matched), ['in_path']);
      expect(only(recs, 'in_path').gapSkills, ['Monitoring']);
    });

    test('gapSkillsByCoverage puts the main topics first', () {
      final recs = recommend(
        [
          ...fillers(30),
          opp('a',
              title: 'Power BI Dashboards',
              skills: ['Power BI'],
              description: 'Some SQL for reports, then more SQL.'),
          // A real SQL course: next to it, "a" covers SQL only a little.
          opp('sql',
              title: 'SQL Fundamentals', skills: ['Databases and SQL']),
        ],
      );
      final match = only(recs, 'a');
      expect(match.gapSkills, ['SQL', 'Power BI']);
      expect(match.gapSkillsByCoverage, ['Power BI', 'SQL']);
    });
  });

  group('uncovered gaps', () {
    test('a gap nothing covers is reported, in the order of the analysis',
        () {
      final recs = recommend(
        [
          ...fillers(30),
          opp('sql', title: 'SQL Fundamentals', paths: ['data_analyst']),
        ],
        data: analysis(gaps: ['Splunk', 'SQL', 'NoSQL']),
      );
      expect(recs.uncoveredGaps, ['Splunk', 'NoSQL']);
    });

    test('a product is its own aspect: a SIEM course does not cover Splunk',
        () {
      final recs = recommend(
        [
          ...fillers(30),
          opp('soc',
              title: 'SOC Analyst Program', skills: ['Security Operations']),
        ],
        data: analysis(goal: '', gaps: ['SIEM', 'Splunk']),
      );
      expect(only(recs, 'soc').gapSkills, ['SIEM']);
      expect(recs.uncoveredGaps, ['Splunk']);
    });

    test('a gap covered by a tag of its group is not reported', () {
      final recs = recommend(
        [
          ...fillers(30),
          opp('net', title: 'VPN Basics', skills: ['Network Security']),
        ],
        data: analysis(goal: '', gaps: ['Firewall', 'VPN']),
      );
      expect(only(recs, 'net').gapSkills, ['VPN']);
      expect(recs.uncoveredGaps, isEmpty);
    });
  });

  group('filter re-ranks the shown part', () {
    // Doroob has one strong course on Power BI and Tableau. On Coursera
    // there are two SQL courses, one Tableau course and one Power BI
    // course.
    final list = [
      ...fillers(30),
      opp('doroob_bi',
          source: 'doroob',
          title: 'Power BI and Tableau Program',
          skills: ['Power BI', 'Tableau'],
          paths: ['data_analyst']),
      opp('sql_1',
          title: 'SQL Fundamentals',
          skills: ['Databases and SQL'],
          paths: ['data_analyst']),
      opp('sql_2',
          title: 'SQL for Data Science',
          skills: ['Databases and SQL'],
          paths: ['data_analyst']),
      opp('tableau', title: 'Tableau Basics', paths: ['data_analyst']),
      opp('power_bi', title: 'Power BI Basics', paths: ['data_analyst']),
    ];
    final data = analysis(gaps: ['SQL', 'Power BI', 'Tableau']);

    test('the first results of a filtered list cover different gaps', () {
      final recs = recommend(list, data: data);
      final coursera = recs.filter(source: 'Coursera');
      expect(coursera.map((m) => m.opportunity.id).toSet(),
          {'sql_1', 'sql_2', 'tableau', 'power_bi'});

      // The first three of the filtered list teach all three gaps.
      final firstThree = {
        for (final m in coursera.take(3)) ...m.gapSkills,
      };
      expect(firstThree, {'SQL', 'Power BI', 'Tableau'});

      // Without re-ranking, the order of the full list would put both SQL
      // courses before a Tableau or Power BI course.
      final kept = recs.matched
          .where((m) => m.opportunity.sourceLabel == 'Coursera')
          .map((m) => m.opportunity.id)
          .take(2)
          .toSet();
      expect(kept, {'sql_1', 'sql_2'});
    });

    test('filtered scores never rise and no filter keeps the full list', () {
      final recs = recommend(list, data: data);
      final coursera = recs.filter(source: 'Coursera');
      for (var i = 1; i < coursera.length; i++) {
        expect(coursera[i].score,
            lessThanOrEqualTo(coursera[i - 1].score + 1e-12));
      }
      expect(ids(recs.filter()), ids(recs.matched));
    });
  });

  test('recommendInBackground gives the same list as recommend', () async {
    final list = [
      ...fillers(10),
      opp('a', title: 'SQL Fundamentals', skills: ['Databases and SQL']),
      opp('b', title: 'Power BI Dashboards', paths: ['data_analyst']),
      opp('c', title: 'Goal only', paths: ['data_analyst']),
    ];
    // A port cannot be sent to another isolate, like some values a
    // Firestore document can hold. Only the plain fields must be sent.
    final port = RawReceivePort();
    addTearDown(port.close);
    final data = {...analysis(), 'notSendable': port};
    // The list has no index yet, so the ranking runs on the other isolate.
    final background = await recommender.recommendInBackground(
        analysis: data, opportunities: list, now: today);
    final direct = recommender.recommend(
        analysis: data, opportunities: List.of(list), now: today);
    expect(ids(background.matched), ids(direct.matched));
    expect(background.matched.map((m) => m.score),
        direct.matched.map((m) => m.score));
    expect(ids(background.filter(source: 'Coursera')),
        ids(direct.filter(source: 'Coursera')));
  });

  group('recommendInBackground keeps the index it built', () {
    List<Opportunity> catalogue() => List.unmodifiable([
          ...fillers(10),
          opp('a', title: 'SQL Fundamentals', skills: ['Databases and SQL']),
          opp('b', title: 'Power BI Dashboards', paths: ['data_analyst']),
          opp('c', title: 'Goal only', paths: ['data_analyst']),
        ]);

    test('the second call on the same list reuses the index', () async {
      final list = catalogue();
      expect(OpportunityIndex.cachedFor(list), isNull);

      final first = await recommender.recommendInBackground(
          analysis: analysis(), opportunities: list, now: today);
      final index = OpportunityIndex.cachedFor(list);
      expect(index, isNotNull);
      // Built on the other isolate: objects sent back are copies...
      expect(list.any((o) => identical(o, first.matched.first.opportunity)),
          isFalse);
      // ...but the kept index points to the objects of this list.
      for (var i = 0; i < list.length; i++) {
        expect(identical(index!.opportunityAt(i), list[i]), isTrue);
      }

      final second = await recommender.recommendInBackground(
          analysis: analysis(), opportunities: list, now: today);
      expect(identical(OpportunityIndex.cachedFor(list), index), isTrue);
      expect(identical(OpportunityIndex.of(list), index), isTrue);
      // Ranked here on the kept index, with the same result.
      expect(list.any((o) => identical(o, second.matched.first.opportunity)),
          isTrue);
      expect(ids(second.matched), ids(first.matched));
      expect(second.matched.map((m) => m.score),
          first.matched.map((m) => m.score));

      // Another user on the same list: still no new index.
      final other = await recommender.recommendInBackground(
          analysis: analysis(gaps: const ['Tableau']),
          opportunities: list,
          now: today);
      expect(identical(OpportunityIndex.cachedFor(list), index), isTrue);
      expect(ids(other.matched),
          ids(recommender
              .recommend(
                  analysis: analysis(gaps: const ['Tableau']),
                  opportunities: List.of(list),
                  now: today)
              .matched));
    });

    test('a list changed after the call is indexed again', () async {
      final list = List.of(catalogue());
      await recommender.recommendInBackground(
          analysis: analysis(), opportunities: list, now: today);
      final first = OpportunityIndex.cachedFor(list);
      expect(first, isNotNull);

      list[0] = opp('new', title: 'Advanced SQL Queries');
      expect(OpportunityIndex.cachedFor(list), isNull);
      final recs = await recommender.recommendInBackground(
          analysis: analysis(), opportunities: list, now: today);
      expect(ids(recs.matched), contains('new'));
      final second = OpportunityIndex.cachedFor(list);
      expect(second, isNotNull);
      expect(identical(second, first), isFalse);
    });

    test('a new list (a refresh) gets its own index', () async {
      final list = catalogue();
      await recommender.recommendInBackground(
          analysis: analysis(), opportunities: list, now: today);
      final refreshed = catalogue();
      expect(OpportunityIndex.cachedFor(refreshed), isNull);
      await recommender.recommendInBackground(
          analysis: analysis(), opportunities: refreshed, now: today);
      expect(OpportunityIndex.cachedFor(refreshed), isNotNull);
      expect(
          identical(OpportunityIndex.cachedFor(refreshed),
              OpportunityIndex.cachedFor(list)),
          isFalse);
    });
  });

  group('formula helpers', () {
    test('demandWeight falls by the decay at every rank', () {
      expect(OpportunityRecommender.demandWeight(0), 1);
      expect(OpportunityRecommender.demandWeight(1), closeTo(0.87, 1e-12));
      expect(OpportunityRecommender.demandWeight(5),
          closeTo(pow(0.87, 5), 1e-12));
      expect(OpportunityRecommender.demandWeight(3, decay: 1), 1);
    });

    test('depthOf goes from the floor to 1 and grows with the hours', () {
      expect(OpportunityRecommender.depthOf(0), 0.5);
      expect(OpportunityRecommender.depthOf(18), closeTo(1, 1e-12));
      expect(OpportunityRecommender.depthOf(240), 1);
      expect(OpportunityRecommender.depthOf(1.5), closeTo(0.656, 0.001));
      expect(OpportunityRecommender.depthOf(14),
          greaterThan(OpportunityRecommender.depthOf(2)));
      expect(
        OpportunityRecommender.depthOf(1.5,
            weights: const RankingWeights(depthFloor: 1)),
        1,
      );
    });

    test('userLevelOf maps the profile experience level', () {
      expect(OpportunityRecommender.userLevelOf('No Experience'), 0);
      expect(OpportunityRecommender.userLevelOf('Beginner'), 0);
      expect(OpportunityRecommender.userLevelOf('Intermediate'), 1);
      expect(OpportunityRecommender.userLevelOf('Advanced'), 2);
      expect(OpportunityRecommender.userLevelOf(null), isNull);
      expect(OpportunityRecommender.userLevelOf('Guru'), isNull);
    });

    test('levelFit only lowers opportunities above the user level', () {
      expect(OpportunityRecommender.levelFit(2, 0), closeTo(0.7, 1e-12));
      expect(OpportunityRecommender.levelFit(1, 0), closeTo(0.85, 1e-12));
      expect(OpportunityRecommender.levelFit(0, 2), 1);
      expect(OpportunityRecommender.levelFit(0, 1), 1);
      expect(OpportunityRecommender.levelFit(1, 1), 1);
      expect(OpportunityRecommender.levelFit(null, 1), 1);
      expect(OpportunityRecommender.levelFit(2, null), 1);
      expect(OpportunityRecommender.levelFit(2, 0, step: 0), 1);
      // The optional step for easier opportunities, for advanced users only.
      expect(OpportunityRecommender.levelFit(0, 2, easierStep: 0.1),
          closeTo(0.8, 1e-12));
      expect(OpportunityRecommender.levelFit(1, 2, easierStep: 0.1),
          closeTo(0.9, 1e-12));
      expect(OpportunityRecommender.levelFit(0, 1, easierStep: 0.1), 1);
    });
  });

  group('types, sources and filter', () {
    final recs = recommender.recommend(
      analysis: analysis(),
      now: today,
      opportunities: [
        opp('course', paths: ['data_analyst']),
        opp('bootcamp',
            source: 'tuwaiq', type: 'Bootcamp', paths: ['data_analyst']),
        opp('program',
            source: 'doroob',
            type: 'Training Program',
            paths: ['data_analyst']),
        opp('hackathon',
            source: 'tuwaiq',
            type: 'Hackathon',
            paths: ['data_analyst'],
            deadline: DateTime(2026, 12, 1)),
        opp('workshop',
            source: 'other',
            provider: 'Udacity',
            type: 'Workshop',
            paths: ['data_analyst']),
      ],
    );

    test('types and sources come in a fixed order, others last', () {
      expect(recs.types,
          ['Training Program', 'Bootcamp', 'Hackathon', 'Course', 'Workshop']);
      expect(recs.sources, ['Tuwaiq Academy', 'Doroob', 'Coursera', 'Udacity']);
    });

    test('filter by type, by source label, or both', () {
      expect(ids(recs.filter(type: 'Bootcamp')), ['bootcamp']);
      expect(ids(recs.filter(source: 'Tuwaiq Academy')),
          ['hackathon', 'bootcamp']);
      expect(recs.filter(type: 'Course', source: 'Tuwaiq Academy'), isEmpty);
      expect(recs.filter().length, recs.matched.length);
      expect(recs.filter(source: 'tuwaiq'), isEmpty);
    });
  });

  test('no career goal and no gaps means no recommendations', () {
    final recs = recommend(
      [
        opp('a', skills: ['Python'], paths: ['data_analyst'])
      ],
      data: analysis(goal: '', gaps: []),
    );
    expect(recs.isEmpty, isTrue);
    expect(recs.careerGoalId, '');
    expect(recs.skillGaps, isEmpty);
  });

  // Checks on the bundled catalogue. The thresholds are loose on purpose:
  // adding or editing opportunities should not break them, only a real
  // regression of the ranking should.
  group('bundled catalogue', () {
    final catalog = [
      for (final record in jsonDecode(
        File('lib/assets/data/Masra_Opportunities.json').readAsStringSync(),
      ) as List)
        Opportunity.fromMap('', Map<String, dynamic>.from(record as Map)),
    ];
    final evalDate = DateTime(2026, 11, 19);

    const personas = <String, Map<String, dynamic>>{
      'data_analyst': {
        'careerGoalId': 'data_analyst',
        'currentSkills': ['Python', 'Pandas', 'Excel'],
        'skillGaps': [
          'SQL',
          'Power BI',
          'Tableau',
          'Statistics',
          'Data Visualization',
          'Data Cleaning',
        ],
      },
      'cybersecurity_analyst': {
        'careerGoalId': 'cybersecurity_analyst',
        'currentSkills': ['Networking', 'Python'],
        'skillGaps': [
          'SIEM',
          'Incident Response',
          'Threat Hunting',
          'Linux',
          'Network Security',
          'Splunk',
        ],
      },
      'software_engineer': {
        'careerGoalId': 'software_engineer',
        'currentSkills': ['Java', 'OOP', 'Git'],
        'skillGaps': [
          'React',
          'Node.js',
          'Docker',
          'AWS',
          'System Design',
          'REST APIs',
          'Microservices',
        ],
      },
    };

    OpportunityRecommendations run(String persona) => recommender.recommend(
          analysis: personas[persona]!,
          opportunities: catalog,
          now: evalDate,
          experienceLevel: 'Beginner',
        );

    test('the Microservices course is found for a Microservices gap', () {
      final recs = run('software_engineer');
      final withGap = recs.matched
          .where((m) => m.gapSkills.contains('Microservices'))
          .map((m) => m.opportunity.title)
          .toList();
      expect(
        withGap,
        contains('Application Development using Microservices and Serverless'),
        reason: 'This course has "Microservices" in its title. If it was '
            'removed from Masra_Opportunities.json, update this test.',
      );
    });

    for (final persona in personas.keys) {
      test('$persona: gap items first, distinct scores, wide coverage', () {
        final recs = run(persona);
        final matched = recs.matched;
        final gaps = (personas[persona]!['skillGaps'] as List).cast<String>();

        final firstGoalOnly = matched.indexWhere((m) => m.gapSkills.isEmpty);
        final lastGapItem =
            matched.lastIndexWhere((m) => m.gapSkills.isNotEmpty);
        expect(lastGapItem, greaterThanOrEqualTo(9),
            reason: 'Expected at least 10 opportunities that teach a gap.');
        if (firstGoalOnly >= 0) {
          expect(firstGoalOnly, greaterThan(lastGapItem),
              reason: 'A goal-only opportunity is ranked above one that '
                  'teaches a skill gap.');
        }

        final top = matched.take(10).toList();
        expect(top.map((m) => m.score).toSet().length, top.length,
            reason: 'Two of the first 10 results have the same score, so '
                'their order is decided by the tie-break only.');

        final covered = {for (final m in top) ...m.gapSkills};
        final coverable = {for (final m in matched) ...m.gapSkills};
        expect(
            covered.length,
            greaterThanOrEqualTo(
                min(gaps.length - 2, coverable.length - 1)),
            reason: 'The first 10 results cover only $covered of the gaps '
                '$gaps (the catalogue can cover $coverable).');
      });
    }

    test('recommend() is fast once the index is built', () {
      run('data_analyst'); // builds the index
      final watch = Stopwatch()..start();
      for (final persona in personas.keys) {
        run(persona);
      }
      // Three calls. The limit is generous so a slow test machine passes.
      expect(watch.elapsedMilliseconds, lessThan(150));
    });
  });
}
