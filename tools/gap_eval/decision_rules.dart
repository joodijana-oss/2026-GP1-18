import 'package:masra/models/gap_link.dart';

import 'approaches.dart';

/// The parts of the selection and decision rules of evaluate_matching.dart
/// that do not need the data: which approaches must be fully graded, and
/// how the winner is picked among the candidates that pass (rule 7.4 of
/// tools/gap_eval/decision_rule_r2.txt). They are kept apart so the tests
/// can check them on small, invented inputs.

/// True for a control: today's matching, the word controls and round 1's
/// ungated links. A control is reported and compared with, never chosen.
bool isControl(Approach approach) =>
    approach.source == LinkSource.none ||
    approach.source == LinkSource.words ||
    approach.id == 'M1' ||
    approach.id == 'M2';

/// The id of the full candidate an "-opp" fallback belongs to, or null for
/// an id that is not a fallback.
String? fullCandidateOf(String id) =>
    id.endsWith('-opp') ? id.substring(0, id.length - 4) : null;

/// [approaches] with the controls the rules compare against, each once:
/// today's matching (A0), in development round 1's ungated links (M1, for
/// rule 2), and the gated word control of every approach that has links
/// (the meaning control of rule 7.6). The pool takes their items too, so
/// none of their pairs is left without a grade.
List<Approach> withControls(
  List<Approach> approaches, {
  required bool development,
}) {
  final result = <Approach>[];
  final ids = <String>{};
  void add(Approach approach) {
    if (ids.add(approach.id)) result.add(approach);
  }

  approaches.forEach(add);
  add(Approach.parse('A0'));
  if (development) add(Approach.parse('M1'));
  for (final approach in approaches) {
    if (!isControl(approach)) add(approach.gatedControl);
  }
  return result;
}

/// The approaches whose grades a rule depends on, for the candidate
/// [candidate]: the candidate itself and today's A0, plus round 1's M1 in
/// the development selection (rule 2) and the gated word control in the
/// final decision (rule 7.6).
List<String> neededFor(Approach candidate, {required bool development}) => [
      candidate.id,
      'A0',
      if (development) 'M1' else candidate.gatedControl.id,
    ];

/// Null when none of [needed] has a pair without a grade; otherwise the
/// reason the rules cannot be applied yet. An ungraded pair is never
/// counted as 0 and never left out: it is graded first.
String? notGradedYet(Map<String, int> ungradedById, Iterable<String> needed) {
  final open = <String, int>{
    for (final id in needed)
      if ((ungradedById[id] ?? 0) > 0) id: ungradedById[id]!,
  };
  if (open.isEmpty) return null;
  final total = open.values.fold<int>(0, (sum, n) => sum + n);
  return '$total pooled pairs have no grade '
      '(${open.entries.map((e) => '${e.key} ${e.value}').join(', ')})';
}

/// How many switches an approach turns on, over both catalogues: links in
/// a catalogue count one, and so does each switch of their settings. Rule
/// 7.4's last tie-break, "fewer moving parts".
int movingPartsOf(Approach approach) {
  int of(LinkSettings s) => !s.enabled
      ? 0
      : 1 +
          (s.termSupport ? 1 : 0) +
          (s.tagSupport ? 1 : 0) +
          (s.termEvidence ? 1 : 0) +
          (s.reasonOnly ? 1 : 0) +
          (s.phraseSearch ? 1 : 0) +
          (s.useCovers ? 0 : 1);
  return of(approach.opportunities) + of(approach.certifications);
}

/// What the decision needs to know of one frozen candidate.
class CandidateResult {
  final String id;

  /// Whether it passes every rule this tool checks (7.2c and 7.3).
  final bool passes;
  final double teachHit;

  /// Mean of the two catalogues.
  final double falseUncovered;

  /// AI requests per analysis (A and B: 1; C: 2).
  final int requests;
  final int movingParts;

  const CandidateResult({
    required this.id,
    required this.passes,
    required this.teachHit,
    required this.falseUncovered,
    required this.requests,
    required this.movingParts,
  });
}

/// Rule 7.4: the highest TeachHit@5 among the candidates that pass. An
/// "-opp" fallback can win only when its full candidate fails. When others
/// are within noise of the best ([withinNoise]: the interval of their
/// difference includes 0), the lower FalseUncovered wins, then fewer
/// requests per analysis, then fewer moving parts. Null when nothing
/// passes, or when the order still cannot tell the first two apart (the
/// user decides); [notes] say why.
({String? winner, List<String> notes}) pickWinner(
  List<CandidateResult> results, {
  required bool Function(String a, String b) withinNoise,
}) {
  final notes = <String>[];
  final passing = {for (final r in results) if (r.passes) r.id};
  final allowed = <CandidateResult>[];
  for (final result in results) {
    if (!result.passes) continue;
    final full = fullCandidateOf(result.id);
    if (full != null && passing.contains(full)) {
      notes.add('${result.id} is left out: its full candidate $full passes.');
      continue;
    }
    allowed.add(result);
  }
  if (allowed.isEmpty) return (winner: null, notes: notes);

  allowed.sort((a, b) => b.teachHit.compareTo(a.teachHit));
  final best = allowed.first;
  final close = [
    best,
    for (final other in allowed.skip(1))
      if (withinNoise(best.id, other.id)) other,
  ];
  if (close.length == 1) return (winner: best.id, notes: notes);

  notes.add('Within noise of ${best.id}: '
      '${close.skip(1).map((r) => r.id).join(', ')}. Ordered by lower '
      'FalseUncovered, then fewer requests, then fewer moving parts.');
  int byTieBreak(CandidateResult a, CandidateResult b) {
    final byUncovered = a.falseUncovered.compareTo(b.falseUncovered);
    if (byUncovered != 0) return byUncovered;
    final byRequests = a.requests.compareTo(b.requests);
    if (byRequests != 0) return byRequests;
    return a.movingParts.compareTo(b.movingParts);
  }

  close.sort(byTieBreak);
  if (byTieBreak(close[0], close[1]) == 0) {
    notes.add('${close[0].id} and ${close[1].id} cannot be told apart by '
        'these rules: the user decides.');
    return (winner: null, notes: notes);
  }
  return (winner: close.first.id, notes: notes);
}

// ---------------------------------------------------------
// THE PERSONA GUARD (rule 7.2 b) AND THE GUARD FILES
// ---------------------------------------------------------

/// [v] in thousandths: [v] rounded to 3 decimals with the call the reports
/// use to print nDCG@10, GapCov@10 and P@5. The guard table prints
/// TopGapRank with 2 decimals, but the user's rule compares all four
/// numbers at 3 decimals, so the guard prints the four compared values
/// once more, at 3 decimals.
int thousandths(double v) =>
    (double.parse(v.toStringAsFixed(3)) * 1000).round();

/// Rule 7.2 (b): the ranking with links against today's. Both lists hold
/// nDCG@10, GapCov@10, P@5 and TopGapRank, in this order. The first three
/// must be at least today's value minus [tolerance]; TopGapRank must be at
/// most today's plus [tolerance].
///
/// [decimals] null compares the numbers as they were computed (the tool's
/// own rule, with a tiny margin for the last bits of a double). [decimals]
/// 3 compares them as the reports print them, rounded to 3 decimals. No
/// other value is accepted.
bool personaGuardPasses(
  List<double> withLinks,
  List<double> today, {
  int? decimals,
  double tolerance = 0,
}) {
  if (withLinks.length != 4 || today.length != 4) {
    throw ArgumentError('The persona guard compares four numbers.');
  }
  if (decimals == null) {
    const epsilon = 1e-9;
    return withLinks[0] >= today[0] - tolerance - epsilon &&
        withLinks[1] >= today[1] - tolerance - epsilon &&
        withLinks[2] >= today[2] - tolerance - epsilon &&
        withLinks[3] <= today[3] + tolerance + epsilon;
  }
  if (decimals != 3) {
    throw ArgumentError('The persona guard compares at full precision or at '
        '3 decimals.');
  }
  final allowed = thousandths(tolerance);
  return thousandths(withLinks[0]) >= thousandths(today[0]) - allowed &&
      thousandths(withLinks[1]) >= thousandths(today[1]) - allowed &&
      thousandths(withLinks[2]) >= thousandths(today[2]) - allowed &&
      thousandths(withLinks[3]) <= thousandths(today[3]) + allowed;
}

/// The three results of the persona guard. "pending" is the case of rule
/// 7.2 (b): the guard fails as measured, but it passes when every item
/// that entered a first 10 without a label gets the best label a tester
/// could give it ([passesWithBestLabels]). Labels are only ever added, so
/// that is the most blind labelling could change. With no such item the
/// two inputs are equal and "pending" cannot occur.
String guardStatus({
  required bool passes,
  required bool passesWithBestLabels,
}) =>
    passes ? 'pass' : (passesWithBestLabels ? 'pending' : 'fail');

/// The limits of the timing guard (rule 7.2 d). The ratios are compared at
/// full precision: the 3-decimal reading is for the persona guard only.
const double warmRatioLimit = 2.00;
const double firstRatioLimit = 1.10;

bool timingPasses(double warmRatio, double firstRatio) =>
    warmRatio <= warmRatioLimit && firstRatio <= firstRatioLimit;

/// Rule 7.2 (d), amendment 1: how many separate runs the timing is
/// measured with, per persona file.
const int amendedTimingRuns = 5;

/// Rule 7.2 (d), amendment 1: the median of 5 separate runs of each ratio,
/// compared with the same limits at full precision. The median is the
/// middle value of a sorted copy, so nothing is averaged. Throws unless
/// both lists hold exactly [amendedTimingRuns] values.
({double warm, double first, bool passes}) amendedTimingVerdict(
    List<double> warmRatios, List<double> firstRatios) {
  if (warmRatios.length != amendedTimingRuns ||
      firstRatios.length != amendedTimingRuns) {
    throw ArgumentError('The amended timing rule takes the median of exactly '
        '$amendedTimingRuns ratios of each kind.');
  }
  double middle(List<double> values) =>
      ([...values]..sort())[amendedTimingRuns ~/ 2];
  final warm = middle(warmRatios);
  final first = middle(firstRatios);
  return (warm: warm, first: first, passes: timingPasses(warm, first));
}

/// The verdict of a timing file from its lists of ratios ("warmRatios" and
/// "firstRatios"), or null when it does not hold [amendedTimingRuns]
/// numbers of each kind.
({double warm, double first, bool passes})? amendedTimingMediansOf(
    Map<String, dynamic> timingFile) {
  List<double>? numbers(dynamic raw) => raw is List &&
          raw.length == amendedTimingRuns &&
          raw.every((value) => value is num)
      ? [for (final value in raw) (value as num).toDouble()]
      : null;
  final warm = numbers(timingFile['warmRatios']);
  final first = numbers(timingFile['firstRatios']);
  return warm == null || first == null
      ? null
      : amendedTimingVerdict(warm, first);
}

/// What the guard files of one candidate say, over all persona files.
class GuardVerdict {
  /// 7.2 (a): an analysis without links gives the opportunity ranking and
  /// the certification lists of today, on every persona file.
  final bool sameWithoutLinks;

  /// 7.2 (b): "pass" when every file passes, "fail" when one fails with the
  /// best labels too, otherwise "pending".
  final String personaStatus;

  /// 7.2 (d), on every persona file.
  final bool timing;

  /// One line per file, for the report.
  final List<String> lines;

  const GuardVerdict({
    required this.sameWithoutLinks,
    required this.personaStatus,
    required this.timing,
    required this.lines,
  });

  bool get passes => sameWithoutLinks && personaStatus == 'pass' && timing;

  /// Everything passes except that the persona guard waits for labels.
  bool get onlyPending =>
      sameWithoutLinks && personaStatus == 'pending' && timing;
}

/// The numeric fields every guard file holds: the four guard numbers of
/// today and with links, both scored once more with the best labels for
/// the unlabelled new items, the number of those items and the two timing
/// ratios. [guardVerdictOf] computes every verdict from them.
const List<String> guardNumberLists = [
  'today',
  'withLinks',
  'todayWithBestLabels',
  'withBestLabels',
];
const List<String> guardNumbers = ['unlabelled', 'warmRatio', 'firstRatio'];

/// What is missing or malformed among the numbers of a guard file.
List<String> guardNumberProblems(Map<String, dynamic> guard) => [
      for (final field in guardNumberLists)
        if (guard[field] is! List ||
            (guard[field] as List).length != 4 ||
            (guard[field] as List).any((value) => value is! num))
          '$field is not a list of four numbers',
      for (final field in guardNumbers)
        if (guard[field] is! num) '$field is not a number',
    ];

/// Reads the guard files evaluate_recommender.dart wrote with --guard-json
/// (one per persona file) at the frozen reading of rule 7.2 (b). The
/// verdicts are computed again here from the numbers in the files, so a
/// file cannot carry a verdict its numbers do not give. Each file must
/// have the numbers of [guardNumberProblems].
///
/// With [amendedTiming] (rule 7.2 (d), amendment 1: the timing file of each
/// persona file, by the path of the persona file), the timing verdict of a
/// file comes from the medians of its timing file, and the single run of
/// the guard file is reported only. A persona file without a timing file
/// fails the timing. The persona verdicts still come from the guard files.
GuardVerdict guardVerdictOf(
  List<Map<String, dynamic>> files, {
  required int? decimals,
  required double tolerance,
  Map<String, Map<String, dynamic>>? amendedTiming,
}) {
  List<double> numbers(dynamic raw) =>
      [for (final value in raw as List) (value as num).toDouble()];
  var same = files.isNotEmpty;
  var timing = files.isNotEmpty;
  var status = files.isEmpty ? 'fail' : 'pass';
  final lines = <String>[];
  for (final file in files) {
    final today = numbers(file['today']);
    final withLinks = numbers(file['withLinks']);
    final passes = personaGuardPasses(withLinks, today,
        decimals: decimals, tolerance: tolerance);
    // Labels are added to the persona file, so both sides are scored again
    // with them. Without unlabelled items there is nothing a label could
    // change.
    final passesWithBest = (file['unlabelled'] as num) > 0 &&
        personaGuardPasses(
          numbers(file['withBestLabels']),
          numbers(file['todayWithBestLabels']),
          decimals: decimals,
          tolerance: tolerance,
        );
    final fileStatus = guardStatus(
      passes: passes,
      passesWithBestLabels: passes || passesWithBest,
    );
    if (fileStatus == 'fail') {
      status = 'fail';
    } else if (fileStatus == 'pending' && status == 'pass') {
      status = 'pending';
    }
    final fileSame = file['sameWithoutLinks'] == true &&
        file['certificationListsSame'] == true;
    same = same && fileSame;
    final warm = (file['warmRatio'] as num).toDouble();
    final first = (file['firstRatio'] as num).toDouble();
    var fileTiming = timingPasses(warm, first);
    var timingText = 'timing '
        'ratios ${warm.toStringAsFixed(4)} and ${first.toStringAsFixed(4)} '
        '${fileTiming ? 'pass' : 'FAIL'}';
    if (amendedTiming != null) {
      // Rule 7.2 (d), amendment 1: the verdict comes from the timing file
      // of this persona file, never from the single run of the guard file.
      final personas =
          '${(file['personas'] as Map)['path']}'.replaceAll('\\', '/');
      final measured = amendedTiming[personas];
      final medians =
          measured == null ? null : amendedTimingMediansOf(measured);
      fileTiming = medians?.passes ?? false;
      timingText = measured == null
          ? 'timing (rule 7.2 d, amendment 1) FAIL: no timing file'
          : medians == null
              ? 'timing (rule 7.2 d, amendment 1) FAIL: the timing file does '
                  'not hold $amendedTimingRuns ratios of each kind'
              : 'timing (rule 7.2 d, amendment 1) medians '
                  '${medians.warm.toStringAsFixed(4)} and '
                  '${medians.first.toStringAsFixed(4)} of $amendedTimingRuns '
                  'runs ${fileTiming ? 'pass' : 'FAIL'}; the single run of '
                  'the guard file, ${warm.toStringAsFixed(4)} and '
                  '${first.toStringAsFixed(4)}, is reported only';
    }
    timing = timing && fileTiming;
    String three(double v) => v.toStringAsFixed(3);
    lines.add('${(file['personas'] as Map)['path']}: without links as today '
        '${fileSame ? 'yes' : 'NO'}; persona guard $fileStatus (with links '
        '${withLinks.map(three).join(' / ')}, today '
        '${today.map(three).join(' / ')}; at full precision '
        '${personaGuardPasses(withLinks, today) ? 'yes' : 'NO'}); '
        '$timingText');
  }
  return GuardVerdict(
    sameWithoutLinks: same,
    personaStatus: status,
    timing: timing,
    lines: lines,
  );
}

/// The candidates whose only open point is rule 7.2 (b)'s "pending": they
/// pass every rule scored on the decision names ([passesOtherRules]) and
/// every guard, except that the persona guard fails as measured and would
/// pass with the best labels. While there is one, no winner is named: the
/// user decides on blind labelling first.
List<String> pendingCandidates(
  Map<String, bool> passesOtherRules,
  Map<String, GuardVerdict> guards,
) =>
    [
      for (final entry in passesOtherRules.entries)
        if (entry.value && (guards[entry.key]?.onlyPending ?? false))
          entry.key,
    ];
