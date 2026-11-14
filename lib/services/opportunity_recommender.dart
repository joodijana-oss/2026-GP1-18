import 'dart:math';

import '../models/opportunity.dart';
import '../utils/skill_matcher.dart';
import 'content_based_recommender.dart';

/// One recommended opportunity and why it was recommended.
class OpportunityMatch {
  final Opportunity opportunity;

  /// The user's skill gaps (as written in the analysis) that this
  /// opportunity teaches.
  final List<String> gapSkills;

  /// The user's current skills (as written in the analysis) that this
  /// opportunity builds on. Never repeats a skill from [gapSkills].
  final List<String> currentSkills;

  /// True when the opportunity is listed for the user's career goal.
  final bool goalRelated;

  /// Higher is better (see [OpportunityRecommender]).
  final double score;

  const OpportunityMatch({
    required this.opportunity,
    required this.gapSkills,
    required this.currentSkills,
    required this.goalRelated,
    required this.score,
  });
}

/// The result of [OpportunityRecommender.recommend].
class OpportunityRecommendations {
  final String careerGoalId;

  /// The skill gaps the ranking used.
  final List<String> skillGaps;

  /// Open opportunities that cover a skill gap or fit the career goal,
  /// best first.
  final List<OpportunityMatch> matched;

  /// How many opportunities were skipped because registration has closed
  /// or the event has already started.
  final int closedHidden;

  const OpportunityRecommendations({
    required this.careerGoalId,
    required this.skillGaps,
    required this.matched,
    required this.closedHidden,
  });

  bool get isEmpty => matched.isEmpty;

  static const List<String> _typeOrder = [
    'Training Program',
    'Bootcamp',
    'Hackathon',
    'Meetup',
    'Webinar',
    'Course',
  ];

  static const List<String> _sourceOrder = [
    'Tuwaiq Academy',
    'Doroob',
    'Coursera',
  ];

  /// The types found in [matched], known types first in a fixed order.
  List<String> get types =>
      _ordered(matched.map((m) => m.opportunity.type), _typeOrder);

  /// The platforms ([Opportunity.sourceLabel]) found in [matched], known
  /// platforms first in a fixed order.
  List<String> get sources =>
      _ordered(matched.map((m) => m.opportunity.sourceLabel), _sourceOrder);

  /// The matches of one type and/or one platform (compared with
  /// [Opportunity.sourceLabel]). Null means no filter. Order is kept.
  List<OpportunityMatch> filter({String? type, String? source}) {
    return matched
        .where((m) => type == null || m.opportunity.type == type)
        .where((m) => source == null || m.opportunity.sourceLabel == source)
        .toList();
  }

  /// Distinct non-empty [values]: those in [order] first, in that order,
  /// then the rest by name.
  static List<String> _ordered(Iterable<String> values, List<String> order) {
    final present = values.where((v) => v.isNotEmpty).toSet();
    final rest = present.where((v) => !order.contains(v)).toList()..sort();
    return [...order.where(present.contains), ...rest];
  }
}

/// Content-based recommender for learning opportunities (Tuwaiq Academy
/// events, Doroob and Coursera courses). It runs on the phone and needs no
/// trained model: it compares the user's analysis (career goal, skill gaps,
/// current skills) with the content of each opportunity.
///
/// Steps:
///  1. Skip opportunities the user can no longer join
///     ([Opportunity.isOpen]) and count them.
///  2. Find the skill gaps it teaches and the current skills it builds on
///     with [SkillMatcher]. The evidence is the title, description,
///     objectives and skills. Requirements are not used: they are what the
///     learner needs before joining, not what it teaches.
///  3. Keep it when it covers at least one skill gap or is listed for the
///     career goal. Building on current skills alone is not enough.
///  4. Score:
///       3 per skill gap covered (at most 4 counted)
///     + 4 when listed for the career goal
///     + 0.5 per current skill it builds on (at most 2 counted)
///     + 1 for a dated event that is still open, so live events are not
///       buried under hundreds of always-available courses.
///  5. Rank: higher score first, then dated events, then the nearest
///     deadline (or start date), then title.
class OpportunityRecommender {
  const OpportunityRecommender();

  static const double gapWeight = 3;
  static const int maxGapsCounted = 4;
  static const double goalWeight = 4;
  static const double currentWeight = 0.5;
  static const int maxCurrentCounted = 2;
  static const double liveEventBonus = 1;

  OpportunityRecommendations recommend({
    required Map<String, dynamic> analysis,
    required List<Opportunity> opportunities,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final goalId = analysis['careerGoalId']?.toString().trim() ?? '';
    final gaps = ContentBasedRecommender.skillGapsOf(analysis);
    final current = ContentBasedRecommender.currentSkillsOf(analysis);

    final matched = <OpportunityMatch>[];
    var closed = 0;

    for (final opportunity in opportunities) {
      if (!opportunity.isOpen(today)) {
        closed++;
        continue;
      }

      final evidence = [
        opportunity.title,
        opportunity.description,
        ...opportunity.objectives,
        ...opportunity.skills,
      ].join(' ');

      final gapSkills = SkillMatcher.matchedSkills(
        gaps,
        opportunity.skills,
        evidence: evidence,
      );
      final gapKeys = gapSkills.map(SkillMatcher.canonical).toSet();
      final currentSkills = SkillMatcher.matchedSkills(
        current,
        opportunity.skills,
        evidence: evidence,
      ).where((s) => !gapKeys.contains(SkillMatcher.canonical(s))).toList();

      final goalRelated =
          goalId.isNotEmpty && opportunity.careerPathIds.contains(goalId);
      if (gapSkills.isEmpty && !goalRelated) continue;

      matched.add(OpportunityMatch(
        opportunity: opportunity,
        gapSkills: gapSkills,
        currentSkills: currentSkills,
        goalRelated: goalRelated,
        score: scoreOf(
          gapCount: gapSkills.length,
          goalRelated: goalRelated,
          currentCount: currentSkills.length,
          liveEvent: opportunity.hasDates,
        ),
      ));
    }

    matched.sort(_byRank);

    return OpportunityRecommendations(
      careerGoalId: goalId,
      skillGaps: gaps,
      matched: matched,
      closedHidden: closed,
    );
  }

  /// The score of one opportunity (see the class comment).
  /// [liveEvent] is true for a dated event that is still open.
  static double scoreOf({
    required int gapCount,
    required bool goalRelated,
    required int currentCount,
    required bool liveEvent,
  }) {
    return gapWeight * min(gapCount, maxGapsCounted) +
        (goalRelated ? goalWeight : 0) +
        currentWeight * min(currentCount, maxCurrentCounted) +
        (liveEvent ? liveEventBonus : 0);
  }

  // ---------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------

  static int _byRank(OpportunityMatch a, OpportunityMatch b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;

    final oa = a.opportunity;
    final ob = b.opportunity;
    final byDated = (ob.hasDates ? 1 : 0).compareTo(oa.hasDates ? 1 : 0);
    if (byDated != 0) return byDated;

    final da = _keyDate(oa);
    final db = _keyDate(ob);
    if (da != null && db != null) {
      final byDate = da.compareTo(db);
      if (byDate != 0) return byDate;
    } else if (da != null || db != null) {
      return da != null ? -1 : 1; // a known date first
    }

    return oa.title.toLowerCase().compareTo(ob.title.toLowerCase());
  }

  /// The date that matters most to the user: the deadline, else the start.
  static DateTime? _keyDate(Opportunity o) =>
      o.registrationDeadline ?? o.startDate ?? o.endDate;
}
