import 'package:flutter_test/flutter_test.dart';
import 'package:masra/models/opportunity.dart';
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
}) {
  return {
    'careerGoalId': goal,
    'skillGaps': gaps,
    'currentSkills': current,
  };
}

List<String> ids(List<OpportunityMatch> matches) =>
    matches.map((m) => m.opportunity.id).toList();

void main() {
  const recommender = OpportunityRecommender();

  OpportunityRecommendations recommend(
    List<Opportunity> opportunities, {
    Map<String, dynamic>? data,
  }) {
    return recommender.recommend(
      analysis: data ?? analysis(),
      opportunities: opportunities,
      now: today,
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
    expect(match.score, OpportunityRecommender.goalWeight);
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
    expect(match.score, 3 + 0.5);
  });

  test('ranks by score, then dated events, then nearest date, then title',
      () {
    final recs = recommend(
      [
        opp('beta', title: 'Beta', paths: ['data_analyst']),
        opp('alpha', title: 'Alpha', paths: ['data_analyst']),
        opp('undated_tie',
            paths: ['data_analyst'], skills: ['Python', 'Excel']),
        opp('event_later',
            source: 'tuwaiq',
            paths: ['data_analyst'],
            deadline: DateTime(2026, 12, 10)),
        opp('event_sooner',
            source: 'tuwaiq',
            paths: ['data_analyst'],
            start: DateTime(2026, 12, 1)),
        opp('one_gap', skills: ['Databases and SQL'], paths: ['data_analyst']),
        opp('one_gap_event',
            source: 'tuwaiq',
            skills: ['Databases and SQL'],
            paths: ['data_analyst'],
            deadline: DateTime(2026, 12, 20)),
        opp('two_gaps',
            skills: ['Databases and SQL', 'Power BI'],
            paths: ['data_analyst']),
      ],
      data: analysis(current: ['Python', 'Excel']),
    );

    expect(ids(recs.matched), [
      'two_gaps', // 3 * 2 + 4 = 10
      'one_gap_event', // 3 + 4 + 1 = 8
      'one_gap', // 3 + 4 = 7
      'event_sooner', // 4 + 1 = 5, dated, 1 Dec
      'event_later', // 4 + 1 = 5, dated, 10 Dec
      'undated_tie', // 4 + 0.5 * 2 = 5, no dates
      'alpha', // 4
      'beta', // 4
    ]);
  });

  test('score caps the gap and current skill counts', () {
    expect(
      OpportunityRecommender.scoreOf(
        gapCount: 6,
        goalRelated: true,
        currentCount: 5,
        liveEvent: true,
      ),
      3 * 4 + 4 + 0.5 * 2 + 1,
    );
    expect(
      OpportunityRecommender.scoreOf(
        gapCount: 0,
        goalRelated: false,
        currentCount: 0,
        liveEvent: false,
      ),
      0,
    );
  });

  group('types, sources and filter', () {
    final recs = recommend([
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
    ]);

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
}
