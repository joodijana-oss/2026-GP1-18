import '../gap_eval/eval_support.dart';
import 'ats_support.dart';

/// The counts and the decision rule of the ATS review evaluation
/// (tools/ats_eval/decision_rule.txt). Pure functions over the graded
/// sheet and the label mapping, so the tests can check every rule.

/// Every verdict a sheet row may have.
const Set<String> knownVerdicts = {
  'PLANTED',
  'NEUTRAL',
  'ARTIFACT',
  'WRONG',
  'PADDED',
  'FINE_FLAGGED',
  'DUPLICATE',
  'EMPTY',
};

/// The verdicts of a true issue.
const Set<String> trueVerdicts = {'PLANTED', 'NEUTRAL'};

/// The verdicts of a false or padded issue.
const Set<String> falseVerdicts = {
  'WRONG',
  'PADDED',
  'FINE_FLAGGED',
  'DUPLICATE',
};

/// Rows without a point label: they are left out of every count except
/// the invented-fact and misquote sums.
const Set<String> uncountedVerdicts = {'ARTIFACT', 'EMPTY'};

/// (a): recall must rise by at least 0.100, written as 1/10.
const int recallGainNumerator = 1;
const int recallGainDenominator = 10;

/// (b): precision may fall by at most 0.030, written as 3/100.
const int precisionMarginNumerator = 3;
const int precisionMarginDenominator = 100;

/// The rule decides on 3 runs per CV per version.
const int ruleRuns = 3;

/// The labels in a credits or point cell: several are separated by commas
/// or semicolons (credits also by spaces). Letter case and extra spaces
/// do not matter in a point label.
Set<String> creditsIn(String cell) => {
      for (final part in cell.split(RegExp(r'[,;\s]+')))
        if (part.trim().isNotEmpty) part.trim().toUpperCase(),
    };

Set<String> pointsIn(String cell) => {
      for (final part in cell.split(RegExp('[,;]')))
        if (part.trim().isNotEmpty)
          part.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
    };

/// A whole number cell; empty is 0. Null when it is not one.
int? countIn(String cell) {
  final text = cell.trim();
  if (text.isEmpty) return 0;
  final value = int.tryParse(text);
  return value == null || value < 0 ? null : value;
}

/// One graded row of the sheet.
class GradedRow {
  const GradedRow({
    required this.label,
    required this.cv,
    required this.area,
    required this.verdict,
    required this.credits,
    required this.points,
    required this.inventedFacts,
    required this.misquotes,
  });

  factory GradedRow.fromSheet(Map<String, String> row) => GradedRow(
        label: row['label'] ?? '',
        cv: row['cv'] ?? '',
        area: row['area'] ?? '',
        verdict: (row['verdict'] ?? '').trim().toUpperCase(),
        credits: creditsIn(row['credits'] ?? ''),
        points: pointsIn(row['point'] ?? ''),
        inventedFacts: countIn(row['invented_facts'] ?? '') ?? 0,
        misquotes: countIn(row['misquotes'] ?? '') ?? 0,
      );

  final String label;
  final String cv;
  final String area;
  final String verdict;
  final Set<String> credits;
  final Set<String> points;
  final int inventedFacts;
  final int misquotes;

  bool get isIssue => area != '(none)';
}

/// The problems a filled sheet still has before it can be frozen (empty
/// when it is ready). [planted] lists the planted problem IDs of each CV;
/// every CV of the sheet needs an entry, `[]` for a CV with none, so a
/// CV left out or misspelled cannot silently drop out of recall.
List<String> sheetProblems(
  List<Map<String, String>> rows,
  Map<String, Set<String>> planted,
) {
  final problems = <String>[];
  final missing = <String>{};
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final cv = row['cv'] ?? '';
    if (!planted.containsKey(cv) && missing.add(cv)) {
      problems.add('planted.json has no entry for "$cv": list its planted '
          'problem IDs, or [] for a CV with none.');
    }
    final where = 'row ${i + 2} (${row['label']}, ${row['area']} '
        '${row['n']})';
    final verdict = (row['verdict'] ?? '').trim().toUpperCase();
    final credits = creditsIn(row['credits'] ?? '');
    final none = row['area'] == '(none)';
    if (!knownVerdicts.contains(verdict)) {
      problems.add('$where: unknown verdict "${row['verdict']}".');
      continue;
    }
    if (none != (verdict == 'EMPTY')) {
      problems.add('$where: EMPTY is the verdict of an output with no '
          'issues, and only of it.');
    }
    if (verdict == 'PLANTED' && credits.isEmpty) {
      problems.add('$where: a PLANTED row must list what it credits.');
    }
    if (verdict != 'PLANTED' && credits.isNotEmpty) {
      problems.add('$where: only a PLANTED row may credit a problem.');
    }
    final known = planted[row['cv']] ?? const <String>{};
    for (final id in credits) {
      if (!known.contains(id)) {
        problems.add('$where: "$id" is not in planted.json for '
            '${row['cv']}.');
      }
    }
    if (!uncountedVerdicts.contains(verdict) &&
        pointsIn(row['point'] ?? '').isEmpty) {
      problems.add('$where: the point label is missing.');
    }
    for (final column in const ['invented_facts', 'misquotes']) {
      if (countIn(row[column] ?? '') == null) {
        problems.add('$where: $column must be a whole number (or empty).');
      }
    }
  }
  return problems;
}

/// The counts of one version.
class VersionCounts {
  const VersionCounts({
    required this.version,
    required this.outputs,
    required this.found,
    required this.plantedTotal,
    required this.trueIssues,
    required this.countedIssues,
    required this.inventedFacts,
    required this.misquotes,
    required this.cleanFalse,
    required this.consistency,
    required this.consistencyPerCv,
    required this.verdicts,
    required this.issuesPerArea,
    required this.areasAtCap,
  });

  final String version;
  final int outputs;

  /// (a) recall = found / plantedTotal.
  final int found;
  final int plantedTotal;

  /// (b) precision = trueIssues / countedIssues (1 when nothing counts).
  final int trueIssues;
  final int countedIssues;

  /// (c)
  final int inventedFacts;
  final int misquotes;

  /// (d)
  final int cleanFalse;

  /// (e), rounded to 2 decimals.
  final double consistency;
  final Map<String, double> consistencyPerCv;

  final Map<String, int> verdicts;
  final Map<String, int> issuesPerArea;

  /// Areas of an output that hold the 3 issues allowed, where a further
  /// problem could have been left out.
  final int areasAtCap;

  double get recall => plantedTotal == 0 ? double.nan : found / plantedTotal;

  double get precision =>
      countedIssues == 0 ? 1 : trueIssues / countedIssues;

  Map<String, Object> toJson() => {
        'version': version,
        'outputs': outputs,
        'recall': {'found': found, 'of': plantedTotal, 'value': recall},
        'precision': {
          'true': trueIssues,
          'counted': countedIssues,
          'value': precision,
        },
        'inventedFacts': inventedFacts,
        'misquotes': misquotes,
        'falseOrPaddedOnClean': cleanFalse,
        'consistency': consistency,
        'consistencyPerCv': consistencyPerCv,
        'verdicts': verdicts,
        'issuesPerArea': issuesPerArea,
        'areasAtCap': areasAtCap,
      };
}

/// (e): for each CV the mean Jaccard similarity of the point-label sets of
/// its runs, then the mean over the CVs, rounded to 2 decimals (half up).
/// It is computed on exact fractions, so the same value always rounds the
/// same way: 69/120 = 0.575 gives 0.58 whatever the order of the sums,
/// where binary floating point can give 0.57 or 0.58. Two empty sets count
/// as 1, and so does a CV with a single run. No CV gives 0.
double roundedConsistency(Iterable<List<Set<String>>> runsPerCv) {
  var total = _fraction(0, 1);
  var cvs = 0;
  for (final sets in runsPerCv) {
    var sum = _fraction(0, 1);
    var pairs = 0;
    for (var i = 0; i < sets.length; i++) {
      for (var j = i + 1; j < sets.length; j++) {
        final union = sets[i].union(sets[j]).length;
        sum = _add(
            sum,
            union == 0
                ? _fraction(1, 1)
                : _fraction(sets[i].intersection(sets[j]).length, union));
        pairs++;
      }
    }
    total = _add(
        total,
        pairs == 0
            ? _fraction(1, 1)
            : (num: sum.num, den: sum.den * BigInt.from(pairs)));
    cvs++;
  }
  if (cvs == 0) return 0;
  final den = total.den * BigInt.from(cvs);
  // Half up: round(100 * num / den) = floor((200 * num + den) / (2 * den)).
  final hundredths =
      (BigInt.from(200) * total.num + den) ~/ (BigInt.two * den);
  return hundredths.toInt() / 100;
}

typedef _Fraction = ({BigInt num, BigInt den});

_Fraction _fraction(int numerator, int denominator) =>
    (num: BigInt.from(numerator), den: BigInt.from(denominator));

/// a + b, reduced. Denominators are always positive.
_Fraction _add(_Fraction a, _Fraction b) {
  final top = a.num * b.den + b.num * a.den;
  final bottom = a.den * b.den;
  final divisor = top.gcd(bottom);
  return (num: top ~/ divisor, den: bottom ~/ divisor);
}

/// The counts of [version] over [slots] (all versions may be in it).
/// [roles] gives each CV's role ("planted" or "clean") and [planted] the
/// planted problem IDs of each CV.
VersionCounts countVersion(
  String version, {
  required List<Slot> slots,
  required List<GradedRow> rows,
  required Map<String, String> roles,
  required Map<String, Set<String>> planted,
}) {
  final mine = [for (final slot in slots) if (slot.version == version) slot];
  final byLabel = <String, List<GradedRow>>{};
  for (final row in rows) {
    byLabel.putIfAbsent(row.label, () => []).add(row);
  }

  var found = 0;
  var plantedTotal = 0;
  var trueIssues = 0;
  var countedIssues = 0;
  var invented = 0;
  var misquotes = 0;
  var cleanFalse = 0;
  var areasAtCap = 0;
  final verdicts = {for (final v in knownVerdicts) v: 0};
  final perArea = {for (final area in areaKeys) area: 0};
  final pointSets = <String, List<Set<String>>>{};

  for (final slot in mine) {
    final slotRows = byLabel[slot.label] ?? const <GradedRow>[];
    final role = roles[slot.cv];
    if (role == 'planted') {
      final ids = planted[slot.cv] ?? const <String>{};
      plantedTotal += ids.length;
      final credited = {for (final row in slotRows) ...row.credits};
      found += ids.where(credited.contains).length;
    }
    final points = <String>{};
    final areaCounts = <String, int>{};
    for (final row in slotRows) {
      verdicts[row.verdict] = (verdicts[row.verdict] ?? 0) + 1;
      invented += row.inventedFacts;
      misquotes += row.misquotes;
      if (row.isIssue) {
        perArea[row.area] = (perArea[row.area] ?? 0) + 1;
        areaCounts[row.area] = (areaCounts[row.area] ?? 0) + 1;
      }
      if (trueVerdicts.contains(row.verdict)) {
        trueIssues++;
        countedIssues++;
      } else if (falseVerdicts.contains(row.verdict)) {
        countedIssues++;
        if (role == 'clean') cleanFalse++;
      }
      if (!uncountedVerdicts.contains(row.verdict)) points.addAll(row.points);
    }
    areasAtCap += areaCounts.values.where((count) => count >= 3).length;
    pointSets.putIfAbsent(slot.cv, () => []).add(points);
  }

  final perCv = {
    for (final entry in pointSets.entries)
      entry.key: meanPairwiseJaccard(entry.value),
  };
  return VersionCounts(
    version: version,
    outputs: mine.length,
    found: found,
    plantedTotal: plantedTotal,
    trueIssues: trueIssues,
    countedIssues: countedIssues,
    inventedFacts: invented,
    misquotes: misquotes,
    cleanFalse: cleanFalse,
    consistency: roundedConsistency(pointSets.values),
    consistencyPerCv: perCv,
    verdicts: verdicts,
    issuesPerArea: perArea,
    areasAtCap: areasAtCap,
  );
}

/// One of the five conditions of the rule.
class RuleCheck {
  const RuleCheck(this.name, this.pass, this.detail);
  final String name;
  final bool pass;
  final String detail;

  Map<String, Object> toJson() =>
      {'rule': name, 'pass': pass, 'detail': detail};
}

/// The five conditions; NEW is adopted only when all of them pass. (a) and
/// (b) are compared exactly, as fractions of whole counts.
List<RuleCheck> decide(VersionCounts old, VersionCounts neu) {
  // (a) found_N/total_N - found_O/total_O >= 1/10
  final RuleCheck a;
  if (old.plantedTotal == 0 || neu.plantedTotal == 0) {
    a = const RuleCheck('(a) recall', false, 'no planted problems to count');
  } else {
    final gain = recallGainDenominator *
        (neu.found * old.plantedTotal - old.found * neu.plantedTotal);
    final needed =
        recallGainNumerator * neu.plantedTotal * old.plantedTotal;
    a = RuleCheck(
      '(a) recall',
      gain >= needed,
      'NEW ${neu.found}/${neu.plantedTotal} = ${f3(neu.recall)}, '
          'OLD ${old.found}/${old.plantedTotal} = ${f3(old.recall)}, '
          'gain ${signed3(neu.recall - old.recall)} (needs +0.100)',
    );
  }

  // (b) true_N/counted_N >= true_O/counted_O - 3/100 (a version with no
  // counted issue has precision 1)
  final pN = neu.countedIssues == 0 ? 1 : neu.trueIssues;
  final qN = neu.countedIssues == 0 ? 1 : neu.countedIssues;
  final pO = old.countedIssues == 0 ? 1 : old.trueIssues;
  final qO = old.countedIssues == 0 ? 1 : old.countedIssues;
  final b = RuleCheck(
    '(b) precision',
    precisionMarginDenominator * (pN * qO - pO * qN) +
            precisionMarginNumerator * qN * qO >=
        0,
    'NEW $pN/$qN = ${f3(pN / qN)}, OLD $pO/$qO = ${f3(pO / qO)} '
        '(NEW may be at most 0.030 lower)',
  );

  final c = RuleCheck(
    '(c) invented facts and misquotes',
    neu.inventedFacts <= old.inventedFacts && neu.misquotes <= old.misquotes,
    'invented facts NEW ${neu.inventedFacts}, OLD ${old.inventedFacts}; '
        'misquotes NEW ${neu.misquotes}, OLD ${old.misquotes}',
  );

  final d = RuleCheck(
    '(d) false or padded on the clean CV',
    neu.cleanFalse <= old.cleanFalse,
    'NEW ${neu.cleanFalse}, OLD ${old.cleanFalse}',
  );

  // Both values are already whole hundredths (roundedConsistency), so
  // these are exact whole numbers and an equal value is a tie.
  final e = RuleCheck(
    '(e) consistency',
    (neu.consistency * 100).round() >= (old.consistency * 100).round(),
    'NEW ${neu.consistency.toStringAsFixed(2)}, '
        'OLD ${old.consistency.toStringAsFixed(2)} (a tie passes)',
  );
  return [a, b, c, d, e];
}

bool adoptNew(List<RuleCheck> checks) => checks.every((check) => check.pass);

/// Why the scores cannot be computed (empty when they can): every CV with
/// the role "planted" needs at least one planted problem in planted.json,
/// or recall would be computed on fewer problems than the keys plant.
List<String> plantedSetProblems(
  Map<String, String> roles,
  Map<String, Set<String>> planted,
) =>
    [
      for (final entry in roles.entries)
        if (entry.value == 'planted' && (planted[entry.key] ?? {}).isEmpty)
          'CV "${entry.key}" is a planted CV, but planted.json lists no '
              'planted problem for it.',
    ];

/// Why a folder cannot decide (empty when it can): the rule decides on
/// [ruleRuns] runs per CV per version, with both versions, exactly one
/// clean CV and at least one planted CV.
List<String> decidingShapeProblems({
  required int runs,
  required List<String> versions,
  required Map<String, String> roles,
}) {
  final problems = <String>[];
  if (runs != ruleRuns) {
    problems.add('the rule decides on $ruleRuns runs per CV per version; '
        'this folder has $runs.');
  }
  if (!versions.contains('old') || !versions.contains('new')) {
    problems.add('the rule compares both versions, old and new; this '
        'folder has ${versions.join(', ')}.');
  }
  final clean = roles.values.where((role) => role == 'clean').length;
  if (clean != 1) {
    problems.add('the rule needs exactly one clean CV; this folder has '
        '$clean.');
  }
  if (!roles.values.contains('planted')) {
    problems.add('the rule needs at least one planted CV; this folder has '
        'none.');
  }
  return problems;
}
