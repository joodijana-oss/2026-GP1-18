import 'dart:math';

import 'package:masra/utils/skill_matcher.dart';

/// Ranking metrics for the offline evaluation of the opportunity
/// recommender (see evaluate_recommender.dart in this folder).
///
/// Every function takes the ranked list of opportunity ids (best first) and
/// the testers' labels, and returns one number. They are pure functions, so
/// test/ranking_metrics_test.dart checks them against values worked out by
/// hand.

// ---------------------------------------------------------
// RELEVANCE
// ---------------------------------------------------------

/// Precision@k: the share of the first [k] results that the testers
/// labelled relevant (grade 1 or 2). Always divided by [k], so a list with
/// fewer than k results is not rewarded for being short.
double precisionAt(int k, List<String> ranked, Map<String, int> grades) {
  final relevant = ranked.take(k).where((id) => (grades[id] ?? 0) >= 1).length;
  return relevant / k;
}

/// nDCG@k (normalized discounted cumulative gain): like precision, but a
/// "very relevant" result (grade 2) is worth more than a "relevant" one
/// (grade 1), and a result near the top is worth more than one further down.
///
///   gain of a result      = 2^grade - 1          (grade 2 -> 3, grade 1 -> 1)
///   discount at rank i    = log2(i + 1)          (rank 1 -> 1, rank 3 -> 2)
///   DCG                   = sum of gain / discount over the first k results
///   nDCG                  = DCG / DCG of the best possible order
///
/// 1.0 means the first k results are the best possible ones in the best
/// order. Null when there is no relevant label at all.
double? ndcgAt(int k, List<String> ranked, Map<String, int> grades) {
  double dcg(List<int> gradesInOrder) {
    var sum = 0.0;
    for (var i = 0; i < gradesInOrder.length && i < k; i++) {
      sum += (pow(2, gradesInOrder[i]) - 1) / (log(i + 2) / ln2);
    }
    return sum;
  }

  final ideal = grades.values.toList()..sort((a, b) => b.compareTo(a));
  final idealDcg = dcg(ideal);
  if (idealDcg == 0) return null;
  return dcg([for (final id in ranked) grades[id] ?? 0]) / idealDcg;
}

// ---------------------------------------------------------
// COVERAGE AND ORDER
// ---------------------------------------------------------

/// Gap coverage@k: the share of the user's skill [gaps] that at least one
/// of the first [k] results teaches, according to the labels.
/// [teachesNormalized] maps an opportunity id to the gap names it teaches,
/// already passed through [SkillMatcher.normalize].
double gapCoverageAt(
  int k,
  List<String> ranked,
  Map<String, Set<String>> teachesNormalized,
  List<String> gaps,
) {
  if (gaps.isEmpty) return 0;
  final taught = <String>{};
  for (final id in ranked.take(k)) {
    taught.addAll(teachesNormalized[id] ?? const {});
  }
  final covered =
      gaps.where((gap) => taught.contains(SkillMatcher.normalize(gap))).length;
  return covered / gaps.length;
}

/// Ties@k: how many of the first [k] results share their exact score with
/// another of the first k. Tied results are ordered by a tie-break (for
/// example the title), not by how well they fit the user.
int tiesAt(int k, List<double> scores) {
  final top = scores.take(k).toList();
  var tied = 0;
  for (var i = 0; i < top.length; i++) {
    for (var j = 0; j < top.length; j++) {
      if (i != j && (top[i] - top[j]).abs() <= 1e-9) {
        tied++;
        break;
      }
    }
  }
  return tied;
}

/// The 1-based rank of the first result that is in [idsTeachingGap], or the
/// list length + 1 when there is none. Used for the most demanded skill
/// gap: a lower rank means the user sees it sooner.
int firstHitRank(List<String> ranked, Set<String> idsTeachingGap) {
  for (var i = 0; i < ranked.length; i++) {
    if (idsTeachingGap.contains(ranked[i])) return i + 1;
  }
  return ranked.length + 1;
}

// ---------------------------------------------------------
// HELPERS
// ---------------------------------------------------------

/// The middle value of [values] (the mean of the two middle values for an
/// even count). 0 for an empty list.
double median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

/// The mean of [values]. 0 for an empty list.
double mean(Iterable<double> values) {
  var sum = 0.0;
  var count = 0;
  for (final value in values) {
    sum += value;
    count++;
  }
  return count == 0 ? 0 : sum / count;
}
