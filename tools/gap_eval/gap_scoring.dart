import 'dart:math';

import 'package:masra/services/market_skill_names.dart';

import 'eval_data.dart';
import 'eval_support.dart';

/// Scores of the skill-gap evaluation (task 6), from the stored answers of
/// a run and the writer's labels. Nothing here makes a request, so every
/// arm can be scored again at any time.
///
/// For a CV, an arm and a run: T is the market skills of the CV's career
/// goal and G the gaps the arm returned (G is part of T). Each name has a
/// status from the labels or from the review sheet: shown, partly or
/// not_shown.
///
///  - FalseGap  = gaps the CV clearly shows / all gaps. The primary number.
///  - Recall    = not-shown market skills returned as gaps / all not-shown
///                market skills.
///  - Precision = not-shown gaps / gaps that are not "partly".
///  - Bundled   = gaps a reviewer marked as several things in one name.
///  - Stability = how alike the gap lists of the runs of one CV are (mean
///                pairwise Jaccard).
/// Each CV weighs the same (macro average) and runs are averaged first.
/// A name nobody has judged yet is left out, and counted, so a score with
/// open review rows is marked as provisional.
class GapScores {
  final String arm;
  final int cvs;
  final double falseGap;
  final double cvsWithFalseGap;
  final double recall;
  final double precision;
  final double bundled;
  final double bundledByDetector;
  final double stability;
  final double fallbackRate;
  final double unverifiedQuoteRate;
  final double gapsPerRun;
  final int errors;
  final int emptyGapRuns;
  final int recallSkipped;
  final int unjudged;

  /// case id -> its FalseGap and Recall (mean over runs), for the paired
  /// bootstrap. Recall is NaN for a CV without a not-shown market skill.
  final Map<String, double> falseGapByCase;
  final Map<String, double> recallByCase;

  const GapScores({
    required this.arm,
    required this.cvs,
    required this.falseGap,
    required this.cvsWithFalseGap,
    required this.recall,
    required this.precision,
    required this.bundled,
    required this.bundledByDetector,
    required this.stability,
    required this.fallbackRate,
    required this.unverifiedQuoteRate,
    required this.gapsPerRun,
    required this.errors,
    required this.emptyGapRuns,
    required this.recallSkipped,
    required this.unjudged,
    required this.falseGapByCase,
    required this.recallByCase,
  });

  double get f1 => precision + recall <= 0
      ? 0
      : 2 * precision * recall / (precision + recall);
}

GapScores scoreArm({
  required EvalSet set,
  required RunFolder run,
  required Arm arm,
  required int runs,
  required bool Function(String name) isKnown,
  bool Function(EvalCase c)? only,
}) {
  final falseGapByCase = <String, double>{};
  final recallByCase = <String, double>{};
  final withFalseGap = <double>[];
  final precisionByCase = <double>[];
  final bundledByCase = <double>[];
  final detectorByCase = <double>[];
  final stabilityByCase = <double>[];
  final gapCounts = <double>[];
  var fallbacks = 0;
  var records = 0;
  var unverified = 0;
  var checked = 0;
  var errors = 0;
  var emptyRuns = 0;
  var recallSkipped = 0;
  final unjudged = <String>{};

  for (final c in set.cases) {
    if (only != null && !only(c)) continue;
    final falseGaps = <double>[];
    final recalls = <double>[];
    final precisions = <double>[];
    final bundledShares = <double>[];
    final detectorShares = <double>[];
    final gapSets = <Set<String>>[];
    var anyFalse = 0;
    var scoredRuns = 0;

    for (var r = 1; r <= runs; r++) {
      final record = run.gaps(c.id, arm.id, r);
      final targets = run.market(c.goalId, arm.extractorId, r);
      if (record == null || record.error != null || targets == null) {
        errors++;
        continue;
      }
      records++;
      scoredRuns++;
      if (record.usedFallback) fallbacks++;
      unverified += record.unverifiedQuotes;
      checked += record.checkedSkills;
      gapCounts.add(record.gaps.length.toDouble());
      if (record.gaps.isEmpty) emptyRuns++;
      gapSets.add(record.gaps.map(keyOf).toSet());

      var shown = 0, notShown = 0, partly = 0, judged = 0;
      var bundled = 0, bundledJudged = 0, detected = 0;
      for (final gap in record.gaps) {
        switch (set.statusOf(c, gap)) {
          case 'shown':
            shown++;
            judged++;
          case 'partly':
            partly++;
            judged++;
          case 'not_shown':
            notShown++;
            judged++;
          default:
            unjudged.add('${c.id}|${keyOf(gap)}');
        }
        final isBundled = set.bundledOf(c, gap);
        if (isBundled != null) {
          bundledJudged++;
          if (isBundled) bundled++;
        }
        if (MarketSkillNames.looksBundled(gap, isKnown: isKnown)) detected++;
      }
      falseGaps.add(judged == 0 ? 0 : shown / judged);
      if (shown > 0) anyFalse++;
      if (judged - partly > 0) precisions.add(notShown / (judged - partly));
      if (bundledJudged > 0) bundledShares.add(bundled / bundledJudged);
      if (record.gaps.isNotEmpty) {
        detectorShares.add(detected / record.gaps.length);
      }

      final gapKeys = record.gaps.map(keyOf).toSet();
      var missing = 0, found = 0;
      for (final target in targets) {
        final status = set.statusOf(c, target);
        if (status == null) unjudged.add('${c.id}|${keyOf(target)}');
        if (status != 'not_shown') continue;
        missing++;
        if (gapKeys.contains(keyOf(target))) found++;
      }
      if (missing == 0) {
        recallSkipped++;
      } else {
        recalls.add(found / missing);
      }
    }

    if (scoredRuns == 0) continue;
    falseGapByCase[c.id] = meanOf(falseGaps);
    recallByCase[c.id] = recalls.isEmpty ? double.nan : meanOf(recalls);
    withFalseGap.add(anyFalse / scoredRuns);
    if (precisions.isNotEmpty) precisionByCase.add(meanOf(precisions));
    if (bundledShares.isNotEmpty) bundledByCase.add(meanOf(bundledShares));
    if (detectorShares.isNotEmpty) detectorByCase.add(meanOf(detectorShares));
    stabilityByCase.add(meanPairwiseJaccard(gapSets));
  }

  return GapScores(
    arm: arm.id,
    cvs: falseGapByCase.length,
    falseGap: meanOf(falseGapByCase.values),
    cvsWithFalseGap: meanOf(withFalseGap),
    recall: meanOf(recallByCase.values.where((v) => !v.isNaN)),
    precision: meanOf(precisionByCase),
    bundled: meanOf(bundledByCase),
    bundledByDetector: meanOf(detectorByCase),
    stability: meanOf(stabilityByCase),
    fallbackRate: records == 0 ? 0 : fallbacks / records,
    unverifiedQuoteRate: checked == 0 ? 0 : unverified / checked,
    gapsPerRun: meanOf(gapCounts),
    errors: errors,
    emptyGapRuns: emptyRuns,
    recallSkipped: recallSkipped,
    unjudged: unjudged.length,
    falseGapByCase: falseGapByCase,
    recallByCase: recallByCase,
  );
}

/// candidate minus baseline for one per-CV number, with the 95% interval
/// of a paired bootstrap over CVs (each CV with all its runs is one unit).
({double difference, double low, double high, int cvs}) pairedDifference(
  Map<String, double> candidate,
  Map<String, double> baseline,
) {
  final ids = [
    for (final id in candidate.keys)
      if (baseline.containsKey(id) &&
          !candidate[id]!.isNaN &&
          !baseline[id]!.isNaN)
        id,
  ];
  if (ids.isEmpty) {
    return (difference: double.nan, low: double.nan, high: double.nan, cvs: 0);
  }
  final differences = [for (final id in ids) candidate[id]! - baseline[id]!];
  final interval = bootstrapInterval((Random random) {
    var sum = 0.0;
    for (var i = 0; i < differences.length; i++) {
      sum += differences[random.nextInt(differences.length)];
    }
    return sum / differences.length;
  });
  return (
    difference: meanOf(differences),
    low: interval.low,
    high: interval.high,
    cvs: ids.length,
  );
}

/// The share of the market skill names of one extractor that reviewers
/// marked as bundled, and the share the detector flags, over the career
/// goals of the set's CVs.
({double reviewer, double detector, int names}) bundledTargets({
  required EvalSet set,
  required RunFolder run,
  required String extractor,
  required int runs,
  required bool Function(String name) isKnown,
}) {
  var names = 0, judged = 0, bundled = 0, detected = 0;
  for (final c in set.cases) {
    for (var r = 1; r <= runs; r++) {
      for (final String name
            in run.market(c.goalId, extractor, r) ?? const <String>[]) {
        names++;
        if (MarketSkillNames.looksBundled(name, isKnown: isKnown)) detected++;
        final isBundled = set.bundledOf(c, name);
        if (isBundled == null) continue;
        judged++;
        if (isBundled) bundled++;
      }
    }
  }
  return (
    reviewer: judged == 0 ? double.nan : bundled / judged,
    detector: names == 0 ? double.nan : detected / names,
    names: names,
  );
}
