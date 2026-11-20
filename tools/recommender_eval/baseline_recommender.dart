import 'dart:math';

import 'package:masra/models/opportunity.dart';
import 'package:masra/services/content_based_recommender.dart';
import 'package:masra/utils/skill_matcher.dart';

/// One result of the [BaselineOpportunityRecommender].
class BaselineMatch {
  final Opportunity opportunity;
  final List<String> gapSkills;
  final bool goalRelated;
  final double score;

  const BaselineMatch({
    required this.opportunity,
    required this.gapSkills,
    required this.goalRelated,
    required this.score,
  });
}

/// A frozen copy of the first opportunity recommender (the version before
/// the ranking upgrade). It is kept only so evaluate_recommender.dart can
/// print "before" numbers next to "after" numbers. The app does not use it.
///
/// How it ranked:
///  1. Skip opportunities the user can no longer join.
///  2. Find the skill gaps and current skills with
///     [SkillMatcher.matchedSkills] over the title, description, objectives
///     and skills joined into one text.
///  3. Keep an opportunity when it covers at least one skill gap or is
///     listed for the career goal.
///  4. Score:
///       3 per skill gap covered (at most 4 counted)
///     + 4 when listed for the career goal
///     + 0.5 per current skill it builds on (at most 2 counted)
///     + 1 for a dated event that is still open.
///  5. Rank: higher score first, then dated events, then the nearest
///     deadline (or start date), then title.
///
/// Do not change this file: the comparison is only fair while it stays the
/// same as the original algorithm.
class BaselineOpportunityRecommender {
  const BaselineOpportunityRecommender();

  static const double gapWeight = 3;
  static const int maxGapsCounted = 4;
  static const double goalWeight = 4;
  static const double currentWeight = 0.5;
  static const int maxCurrentCounted = 2;
  static const double liveEventBonus = 1;

  List<BaselineMatch> recommend({
    required Map<String, dynamic> analysis,
    required List<Opportunity> opportunities,
    required DateTime now,
  }) {
    final goalId = analysis['careerGoalId']?.toString().trim() ?? '';
    final gaps = ContentBasedRecommender.skillGapsOf(analysis);
    final current = ContentBasedRecommender.currentSkillsOf(analysis);

    final matched = <BaselineMatch>[];

    for (final opportunity in opportunities) {
      if (!opportunity.isOpen(now)) continue;

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

      matched.add(BaselineMatch(
        opportunity: opportunity,
        gapSkills: gapSkills,
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
    return matched;
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

  static int _byRank(BaselineMatch a, BaselineMatch b) {
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
