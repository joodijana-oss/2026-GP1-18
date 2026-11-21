import 'dart:convert';
import 'dart:io';

import 'package:masra/models/gap_link.dart';
import 'package:masra/models/opportunity.dart';
import 'package:masra/services/content_based_recommender.dart';
import 'package:masra/services/opportunity_index.dart';
import 'package:masra/services/opportunity_recommender.dart';
import 'package:masra/utils/skill_matcher.dart';

import '../gap_eval/approaches.dart';
import '../gap_eval/decision_rules.dart';
import '../gap_eval/eval_support.dart'
    show loadCertifications, readText, sha256OfText, writeCsv, writeJson;
import '../gap_eval/freeze_r2.dart'
    show
        candidatesServedBy,
        checkFreeze,
        defaultFreezeFile,
        freezeShaOf,
        frozenGuard,
        guardApproachProblem,
        guardFileProblems,
        guardJsonProblem,
        slashes;
import 'baseline_recommender.dart';
import 'ranking_metrics.dart';

/// Offline evaluation of the opportunity recommender.
///
/// It ranks the bundled opportunities for a set of test users (personas)
/// with two systems and prints their quality side by side:
///  - Baseline: the first recommender, frozen in baseline_recommender.dart;
///  - New: the recommender the app uses now
///    (lib/services/opportunity_recommender.dart).
///
/// Run it from the project root:
///
///   dart run tools/recommender_eval/evaluate_recommender.dart
///
/// Options:
///   --personas `file`       labelled personas (default
///                           test/fixtures/opportunity_eval_personas.json,
///                           the development set). The held-out set is
///                           test/fixtures/opportunity_eval_personas_heldout.json:
///                           8 other career paths, labelled by testers who
///                           never saw the ranking code. Nothing was tuned on
///                           it, so report its numbers.
///   --catalog `file`        opportunities
///                           (default lib/assets/data/Masra_Opportunities.json)
///   --top                   also print the first 10 results of each system
///   --ablation              also print the averages with one technique
///                           switched off at a time
///   --dump-baseline `file`  write the full baseline ranking of every persona
///                           as JSON (to prove the frozen copy never changes)
///   --links `file`          the meaning links of the personas, as written by
///                           link_persona_gaps.dart: also print the persona
///                           guard, the certification lists and the timing
///                           guard of the approach given with --approach
///   --approach `id`         the matching approach to guard (ids are listed
///                           in tools/gap_eval/approaches.dart; default M1)
///   --new-pairs `file`      write the (skill gap, certification) pairs that
///                           only the links attribute, for grading
///   --guard-precision `p`   how the persona guard compares with links and
///                           without: full (the default: the numbers as
///                           computed) or 3 (rounded to 3 decimals, as the
///                           reports print them). Both verdicts are always
///                           printed; this picks the one that counts.
///   --guard-json `file`     write the guard results for the final decision
///                           (evaluate_matching.dart --decision --guards).
///                           Only on a matching freeze, at the frozen
///                           precision, never over an existing file or
///                           next to another guard file of the same
///                           personas, never inside build/gap_eval/final_r2,
///                           and only for a frozen pair of personas and
///                           links and a frozen candidate (an "-opp"
///                           fallback takes its full candidate's runs).
///                           All of this is checked before anything is
///                           measured.
///   --freeze-file `file`    with --guard-json (default
///                           tools/gap_eval/freeze_r2.json)
///
/// The personas file is a list of
///   {id, careerGoalId, experienceLevel, currentSkills, skillGaps,
///    targetSkills (optional), relevant: [{id, grade 1|2, teaches: [...]}]}.
/// `relevant` are the testers' labels: grade 2 = very relevant, 1 =
/// relevant, not listed = not relevant. `teaches` names the skill gaps the
/// opportunity really teaches.
///
/// The date is fixed, so the same files always give the same numbers.
///
/// This folder sits next to the Node upload scripts in tools/. The scripts
/// here are Dart because they import the app's own ranking code
/// (package:masra/...). They must never import Flutter or Firestore code.
final DateTime evalDate = DateTime(2026, 11, 19);

const String defaultPersonas = 'test/fixtures/opportunity_eval_personas.json';
const String heldOutPersonas =
    'test/fixtures/opportunity_eval_personas_heldout.json';
const String defaultCatalog = 'lib/assets/data/Masra_Opportunities.json';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  // The guard file of the final decision: everything that could make it
  // unusable is checked before anything is measured.
  final guardFile = options.guardJsonPath;
  Map<String, dynamic>? frozen;
  Map<String, dynamic>? identity;
  if (guardFile != null) {
    if (options.linksPath == null) _fail('--guard-json needs --links.');
    if (options.catalogPath != defaultCatalog) {
      _fail('--guard-json measures the bundled catalogue: leave --catalog '
          'out.');
    }
    final fixed = checkFreeze(options.freezeFile);
    frozen = fixed;
    final problem = guardJsonProblem(guardFile,
        precision: options.guardPrecision,
        personasPath: options.personasPath,
        frozen: fixed);
    if (problem != null) _fail(problem);
    // What the file will record about itself, checked now as the decision
    // checks it, so a wrong pairing or approach stops the run before
    // anything is measured. A guard is run once.
    final approach = Approach.parse(options.approach);
    final self = _guardIdentity(options, approach, fixed);
    final problems = [
      ...guardFileProblems(self,
          frozen: fixed, freezeSha: '${self['freezeSha256']}'),
      ?guardApproachProblem(approach, fixed),
    ];
    if (problems.isNotEmpty) {
      _fail('The decision could not use this guard file:\n  '
          '${problems.join('\n  ')}\nNothing was measured or written.');
    }
    identity = self;
  }
  final catalog = _loadCatalog(options.catalogPath);
  final byId = {for (final o in catalog) o.id: o};
  final personas = _loadPersonas(options.personasPath, byId);

  stdout.writeln('OPPORTUNITY RECOMMENDER EVALUATION');
  stdout.writeln('Evaluation date : ${_day(evalDate)} (fixed)');
  stdout.writeln('Catalogue       : ${catalog.length} opportunities, '
      '${catalog.where((o) => o.isOpen(evalDate)).length} open on that date');
  stdout.writeln('Personas        : ${personas.length} '
      '(${options.personasPath})');
  if (options.personasPath.endsWith(heldOutPersonas.split('/').last)) {
    stdout.writeln('Note            : these personas are the held-out set. '
        'Nothing in the ranking was designed or tuned on them,');
    stdout.writeln('                  so these are the numbers to report. '
        'Differences of about 0.02 between systems are noise.');
  } else {
    stdout.writeln('Note            : these personas are a development set. '
        'They were seen while the ranking was designed and reviewed, so the');
    stdout.writeln('                  numbers are optimistic. Differences of '
        'about 0.02 between systems are noise at this sample size.');
  }

  const baseline = BaselineOpportunityRecommender();
  const recommender = OpportunityRecommender();

  final baselineRuns = <_Run>[];
  final newRuns = <_Run>[];
  for (final persona in personas) {
    baselineRuns.add(_runBaseline(baseline, persona, catalog));
    newRuns.add(_runNew(recommender, persona, catalog));
  }

  // ---- per persona -------------------------------------------------
  var identical = 0;
  for (var i = 0; i < personas.length; i++) {
    final persona = personas[i];
    final before = _Metrics.of(persona, baselineRuns[i]);
    final after = _Metrics.of(persona, newRuns[i]);
    if (_sameOrder(baselineRuns[i], newRuns[i])) identical++;

    stdout.writeln('');
    stdout.writeln('${persona.id}  (${persona.experienceLevel ?? 'no level'}, '
        '${persona.gaps.length} gaps, ${persona.grades.length} labels, '
        'labels allow GapCov ${_f(persona.bestGapCoverage, 2)})');
    stdout.writeln('  ${''.padRight(22)}${_head3()}');
    _row3('P@5', before.precision5, after.precision5);
    _row3('nDCG@10', before.ndcg10, after.ndcg10);
    _row3('GapCov@10', before.gapCoverage10, after.gapCoverage10);
    _row3('Ties@10', before.ties10.toDouble(), after.ties10.toDouble(),
        digits: 0);
    _row3('TopGapRank', before.topGapRank.toDouble(),
        after.topGapRank.toDouble(),
        digits: 0);
    _row3('Goal-only above gap', before.goalOnlyAboveGap.toDouble(),
        after.goalOnlyAboveGap.toDouble(),
        digits: 0);
    if (options.top) {
      _printTop('Baseline', persona, baselineRuns[i]);
      _printTop('New', persona, newRuns[i]);
    }
  }

  // ---- summary -----------------------------------------------------
  final before = [
    for (var i = 0; i < personas.length; i++)
      _Metrics.of(personas[i], baselineRuns[i]),
  ];
  final after = [
    for (var i = 0; i < personas.length; i++)
      _Metrics.of(personas[i], newRuns[i]),
  ];

  _perPersonaTable('nDCG@10 per persona', personas, before, after,
      (m) => m.ndcg10);
  _perPersonaTable('GapCov@10 per persona', personas, before, after,
      (m) => m.gapCoverage10);

  stdout.writeln('');
  stdout.writeln('AVERAGE OVER ${personas.length} PERSONAS');
  stdout.writeln('  ${''.padRight(22)}${_head3()}');
  _row3('nDCG@10', _avg(before, (m) => m.ndcg10), _avg(after, (m) => m.ndcg10));
  _row3('GapCov@10', _avg(before, (m) => m.gapCoverage10),
      _avg(after, (m) => m.gapCoverage10));
  _row3('TopGapRank', _avg(before, (m) => m.topGapRank.toDouble()),
      _avg(after, (m) => m.topGapRank.toDouble()));
  _row3('P@5 (sanity check)', _avg(before, (m) => m.precision5),
      _avg(after, (m) => m.precision5));
  _row3('Ties@10', _avg(before, (m) => m.ties10.toDouble()),
      _avg(after, (m) => m.ties10.toDouble()));
  _row3('Goal-only above gap',
      _avg(before, (m) => m.goalOnlyAboveGap.toDouble()),
      _avg(after, (m) => m.goalOnlyAboveGap.toDouble()));
  stdout.writeln('  (TopGapRank: rank of the first result that teaches the '
      'most demanded gap; lower is better. Ties and');
  stdout.writeln('   goal-only-above-gap: lower is better. P@5 is close to '
      'its maximum for both systems, so it says little.)');
  stdout.writeln('');
  stdout.writeln(
      'Rankings identical to baseline: $identical/${personas.length} personas');

  await _printTiming(personas, catalog);

  if (options.ablation) _printAblation(personas, catalog);

  if (options.linksPath != null) {
    final guard =
        await _printLinkGuard(options, personas, catalog, newRuns, frozen);
    final fixed = frozen;
    final self = identity;
    if (guardFile != null && fixed != null && self != null) {
      // The freeze file, the personas and the links must still be the
      // files checked before the run.
      final now = _guardIdentity(
          options, Approach.parse(options.approach), fixed);
      if (jsonEncode(now) != jsonEncode(self)) {
        _fail('The freeze file, the personas or the links changed while the '
            'guard ran. Nothing was written.');
      }
      writeJson(guardFile, {...self, ...guard});
      stdout.writeln('');
      stdout.writeln('Guard results written to $guardFile. It serves the '
          'frozen candidates ${candidatesServedBy(self, fixed).join(', ')}.');
    }
  }

  final dumpPath = options.dumpBaselinePath;
  if (dumpPath != null) {
    final dump = {
      for (var i = 0; i < personas.length; i++)
        personas[i].id: [
          for (var k = 0; k < baselineRuns[i].ids.length; k++)
            [baselineRuns[i].ids[k], baselineRuns[i].scores[k]],
        ],
    };
    File(dumpPath).writeAsStringSync(jsonEncode(dump));
    stdout.writeln('');
    stdout.writeln('Baseline rankings written to $dumpPath');
  }
}

// ---------------------------------------------------------
// RUNNING THE TWO SYSTEMS
// ---------------------------------------------------------

/// One ranked list, in the same shape for both systems.
class _Run {
  final List<String> ids;
  final List<double> scores;
  final List<List<String>> gapSkills;
  final List<String> titles;

  const _Run(this.ids, this.scores, this.gapSkills, this.titles);
}

_Run _runBaseline(
  BaselineOpportunityRecommender baseline,
  _Persona persona,
  List<Opportunity> catalog,
) {
  final matches = baseline.recommend(
    analysis: persona.analysis,
    opportunities: catalog,
    now: evalDate,
  );
  return _Run(
    [for (final m in matches) m.opportunity.id],
    [for (final m in matches) m.score],
    [for (final m in matches) m.gapSkills],
    [for (final m in matches) m.opportunity.title],
  );
}

_Run _runNew(
  OpportunityRecommender recommender,
  _Persona persona,
  List<Opportunity> catalog,
) {
  final matches = recommender
      .recommend(
        analysis: persona.analysis,
        opportunities: catalog,
        now: evalDate,
        experienceLevel: persona.experienceLevel,
      )
      .matched;
  return _Run(
    [for (final m in matches) m.opportunity.id],
    [for (final m in matches) m.score],
    [for (final m in matches) m.gapSkills],
    [for (final m in matches) m.opportunity.title],
  );
}

bool _sameOrder(_Run a, _Run b) {
  if (a.ids.length != b.ids.length) return false;
  for (var i = 0; i < a.ids.length; i++) {
    if (a.ids[i] != b.ids[i]) return false;
  }
  return true;
}

// ---------------------------------------------------------
// METRICS OF ONE RUN
// ---------------------------------------------------------

class _Metrics {
  final double precision5;
  final double ndcg10;
  final double gapCoverage10;
  final int ties10;

  /// Rank of the first result whose label teaches the first (most
  /// demanded) skill gap.
  final int topGapRank;

  /// Results that teach no gap but sit above a result that does.
  final int goalOnlyAboveGap;

  const _Metrics({
    required this.precision5,
    required this.ndcg10,
    required this.gapCoverage10,
    required this.ties10,
    required this.topGapRank,
    required this.goalOnlyAboveGap,
  });

  factory _Metrics.of(_Persona persona, _Run run) {
    final topGap = SkillMatcher.normalize(persona.gaps.first);
    final teachingTopGap = {
      for (final entry in persona.teaches.entries)
        if (entry.value.contains(topGap)) entry.key,
    };
    return _Metrics(
      precision5: precisionAt(5, run.ids, persona.grades),
      ndcg10: ndcgAt(10, run.ids, persona.grades) ?? 0,
      gapCoverage10:
          gapCoverageAt(10, run.ids, persona.teaches, persona.gaps),
      ties10: tiesAt(10, run.scores),
      topGapRank: firstHitRank(run.ids, teachingTopGap),
      goalOnlyAboveGap: _goalOnlyAboveGap(run),
    );
  }

  static int _goalOnlyAboveGap(_Run run) {
    final lastGapItem = run.gapSkills.lastIndexWhere((g) => g.isNotEmpty);
    var count = 0;
    for (var i = 0; i < lastGapItem; i++) {
      if (run.gapSkills[i].isEmpty) count++;
    }
    return count;
  }
}

double _avg(List<_Metrics> metrics, double Function(_Metrics) pick) =>
    mean(metrics.map(pick));

// ---------------------------------------------------------
// TIMING
// ---------------------------------------------------------

/// A profile shaped like a real CV analysis, used only for timing (it has
/// no labels): 12 skill gaps, the most the AI analysis returns, and 25
/// current skills (real CVs give about 15 to 30). The labelled personas have
/// only 2 to 4 current skills, which would understate the first call.
const Map<String, dynamic> timingProfile = {
  'careerGoalId': 'software_engineer',
  'skillGaps': [
    'Docker', 'Kubernetes', 'CI/CD', 'AWS', 'Microservices', 'REST APIs',
    'System Design', 'Unit Testing', 'React', 'Node.js', 'PostgreSQL',
    'Terraform',
  ],
  'currentSkills': [
    'Java', 'Python', 'JavaScript', 'HTML', 'CSS', 'SQL', 'MySQL', 'Git',
    'Linux', 'Object-Oriented Programming', 'Data Structures', 'Algorithms',
    'Spring Boot', 'Agile', 'Scrum', 'Jira', 'Excel', 'Communication',
    'Teamwork', 'Problem Solving', 'Bash', 'Networking', 'Flutter',
    'Firebase', 'Figma',
  ],
};

Future<void> _printTiming(
  List<_Persona> personas,
  List<Opportunity> catalog,
) async {
  const baseline = BaselineOpportunityRecommender();
  const recommender = OpportunityRecommender();

  double milliseconds(void Function() action) {
    final watch = Stopwatch()..start();
    action();
    return watch.elapsedMicroseconds / 1000;
  }

  OpportunityRecommendations realistic(List<Opportunity> list) =>
      recommender.recommend(
        analysis: timingProfile,
        opportunities: list,
        now: evalDate,
        experienceLevel: 'Intermediate',
      );

  final build = [
    for (var i = 0; i < 5; i++)
      milliseconds(() => OpportunityIndex.build(catalog)),
  ];

  // A new list object has no index yet, as after the app starts or after a
  // pull to refresh.
  final freshList = List<Opportunity>.of(catalog);
  final firstCall =
      milliseconds(() => _runNew(recommender, personas.first, freshList));
  final newUser = [
    for (final persona in personas.skip(1))
      milliseconds(() => _runNew(recommender, persona, freshList)),
  ];
  final firstRealistic = [
    for (var i = 0; i < 5; i++)
      milliseconds(() => realistic(List<Opportunity>.of(catalog))),
  ];

  final warmNew = <double>[];
  final warmBaseline = <double>[];
  for (var round = 0; round < 30; round++) {
    for (final persona in personas) {
      warmNew.add(milliseconds(() => _runNew(recommender, persona, freshList)));
    }
  }
  for (var round = 0; round < 30; round++) {
    for (final persona in personas) {
      warmBaseline
          .add(milliseconds(() => _runBaseline(baseline, persona, catalog)));
    }
  }

  // The app's path. recommendInBackground builds the index on a background
  // isolate the first time it sees a list (the wall time includes starting
  // the isolate; the screen keeps drawing meanwhile) and keeps the index
  // for that list. Later calls on the same list rank on this isolate.
  Future<double> background(
    Map<String, dynamic> analysis,
    List<Opportunity> list, {
    String? level = 'Intermediate',
  }) async {
    final watch = Stopwatch()..start();
    await recommender.recommendInBackground(
      analysis: analysis,
      opportunities: list,
      now: evalDate,
      experienceLevel: level,
    );
    return watch.elapsedMicroseconds / 1000;
  }

  final backgroundFirst = <double>[];
  final backgroundSame = <double>[];
  final backgroundNewUser = <double>[];
  var indexKept = true;
  for (var round = 0; round < 3; round++) {
    // A new list object, as after the app starts or after a refresh.
    final list = List<Opportunity>.unmodifiable(catalog);
    backgroundFirst.add(await background(timingProfile, list));
    final kept = OpportunityIndex.cachedFor(list);
    indexKept = indexKept && kept != null;
    for (var i = 0; i < 10; i++) {
      backgroundSame.add(await background(timingProfile, list));
    }
    // Users the index has not seen: their skills are searched now.
    for (final persona in personas) {
      backgroundNewUser.add(await background(persona.analysis, list,
          level: persona.experienceLevel));
    }
    // Still the index built in the background, never built again.
    indexKept = indexKept && identical(OpportunityIndex.cachedFor(list), kept);
  }
  double slowest(List<double> values) =>
      values.reduce((a, b) => a > b ? a : b);

  stdout.writeln('');
  stdout.writeln('TIMING (this computer; a JIT run of this script is slower '
      'than a release build, debug mode on an emulator is slower still)');
  stdout.writeln('  Build the index once per opportunity list '
      '(median of 5)        : ${_f(median(build), 1)} ms');
  stdout.writeln('  First recommend() on a new list, first persona (includes '
      'the build): ${_f(firstCall, 1)} ms');
  stdout.writeln('  First recommend() on a new list, realistic profile '
      '(12 gaps, 25 current skills, median of 5): '
      '${_f(median(firstRealistic), 1)} ms');
  stdout.writeln('  recommend() for a new user, index already built '
      '(median)     : ${_f(median(newUser), 2)} ms');
  stdout.writeln('  recommend() repeated, New      (median of '
      '${warmNew.length} calls)        : ${_f(median(warmNew), 2)} ms'
      '   (slowest ${_f(warmNew.reduce((a, b) => a > b ? a : b), 2)} ms)');
  stdout.writeln('  recommend() repeated, Baseline (median of '
      '${warmBaseline.length} calls)        : '
      '${_f(median(warmBaseline), 2)} ms');
  stdout.writeln('  The app calls recommendInBackground():');
  stdout.writeln('    new list, builds the index on a background isolate, '
      'wall time (median of ${backgroundFirst.length}): '
      '${_f(median(backgroundFirst), 1)} ms');
  stdout.writeln('    same list, same user again, runs here on the kept '
      'index (median of ${backgroundSame.length}): '
      '${_f(median(backgroundSame), 2)} ms'
      '   (slowest ${_f(slowest(backgroundSame), 2)} ms)');
  stdout.writeln('    same list, a user not seen before, runs here on the '
      'kept index (median of ${backgroundNewUser.length}): '
      '${_f(median(backgroundNewUser), 2)} ms'
      '   (slowest ${_f(slowest(backgroundNewUser), 2)} ms)');
  stdout.writeln('    index built in the background kept and reused, never '
      'built again for the same list: ${indexKept ? 'yes' : 'NO'}');
  stdout.writeln('  The index is built once per list: when the screen first '
      'opens, and once after each pull to refresh or retry, which loads a '
      'new list.');
}

// ---------------------------------------------------------
// ABLATION
// ---------------------------------------------------------

/// Runs the new recommender with one technique switched off at a time, so
/// the team can show what each technique adds.
void _printAblation(List<_Persona> personas, List<Opportunity> catalog) {
  const variants = <String, RankingWeights>{
    'Full (defaults)': RankingWeights(),
    'Query expansion on': RankingWeights(expandSynonyms: true),
    'No IDF': RankingWeights(useIdf: false),
    'Equal gap weights (decay 1)': RankingWeights(demandDecay: 1),
    'No depth (floor 1)': RankingWeights(depthFloor: 1),
    'No level fit (step 0)': RankingWeights(levelStep: 0),
    'Easier-level step 0.1': RankingWeights(easierStep: 0.1),
    'No off-goal discount': RankingWeights(offGoalFactor: 1),
    'No re-ranking (diversity 0)': RankingWeights(diversity: 0),
    'Diversity 0.5': RankingWeights(diversity: 0.5),
    'Diversity 0.8': RankingWeights(diversity: 0.8),
    'Diversity 1': RankingWeights(diversity: 1),
  };

  stdout.writeln('');
  stdout.writeln('ABLATION (average over ${personas.length} personas; one '
      'setting changed at a time)');
  stdout.writeln('  ${'Variant'.padRight(30)}'
      '${'nDCG@10'.padLeft(9)}${'GapCov@10'.padLeft(11)}'
      '${'TopGapRank'.padLeft(12)}${'P@5'.padLeft(8)}${'Ties@10'.padLeft(9)}');
  final perPersona = <String, List<_Metrics>>{};
  variants.forEach((name, weights) {
    final recommender = OpportunityRecommender(weights: weights);
    final metrics = [
      for (final persona in personas)
        _Metrics.of(persona, _runNew(recommender, persona, catalog)),
    ];
    perPersona[name] = metrics;
    stdout.writeln('  ${name.padRight(30)}'
        '${_f(_avg(metrics, (m) => m.ndcg10), 3).padLeft(9)}'
        '${_f(_avg(metrics, (m) => m.gapCoverage10), 3).padLeft(11)}'
        '${_f(_avg(metrics, (m) => m.topGapRank.toDouble()), 3).padLeft(12)}'
        '${_f(_avg(metrics, (m) => m.precision5), 3).padLeft(8)}'
        '${_f(_avg(metrics, (m) => m.ties10.toDouble()), 2).padLeft(9)}');
  });
  stdout.writeln('  Read "Equal gap weights" with all three columns: the '
      'labels do not reward market demand, so demand');
  stdout.writeln('  weights can cost nDCG and coverage while TopGapRank '
      'shows whether the most demanded gap comes sooner.');

  stdout.writeln('');
  stdout.writeln('ABLATION, nDCG@10 PER PERSONA (columns in the order of the '
      'personas above)');
  perPersona.forEach((name, metrics) {
    stdout.writeln('  ${name.padRight(30)}'
        '${[for (final m in metrics) _f(m.ndcg10, 3).padLeft(7)].join()}');
  });
}

// ---------------------------------------------------------
// INPUT
// ---------------------------------------------------------

class _Options {
  final String personasPath;
  final String catalogPath;
  final bool top;
  final bool ablation;
  final String? dumpBaselinePath;
  final String? linksPath;
  final String approach;
  final String? newPairsPath;

  /// "full" or "3".
  final String guardPrecision;
  final String? guardJsonPath;
  final String freezeFile;

  const _Options({
    required this.guardPrecision,
    required this.guardJsonPath,
    required this.freezeFile,
    required this.personasPath,
    required this.catalogPath,
    required this.top,
    required this.ablation,
    required this.dumpBaselinePath,
    required this.linksPath,
    required this.approach,
    required this.newPairsPath,
  });

  factory _Options.parse(List<String> args) {
    // A misspelt option must stop the run, not be ignored: "--link" for
    // "--links" would measure the ranking without links.
    const known = {
      '--personas', '--catalog', '--top', '--ablation', '--dump-baseline',
      '--links', '--approach', '--new-pairs', '--guard-precision',
      '--guard-json', '--freeze-file',
    };
    final unknown = [
      for (final arg in args)
        if (arg.startsWith('--') && !known.contains(arg)) arg,
    ];
    if (unknown.isNotEmpty) {
      _fail('Unknown option${unknown.length == 1 ? '' : 's'}: '
          '${unknown.join(', ')}. This tool knows: '
          '${(known.toList()..sort()).join(', ')}.');
    }

    String? valueOf(String flag) {
      final index = args.indexOf(flag);
      if (index < 0) return null;
      if (index + 1 >= args.length) _fail('$flag needs a value.');
      return args[index + 1];
    }

    final precision = valueOf('--guard-precision') ?? 'full';
    if (precision != 'full' && precision != '3') {
      _fail('--guard-precision is full or 3.');
    }
    if (valueOf('--freeze-file') != null && valueOf('--guard-json') == null) {
      _fail('--freeze-file belongs to --guard-json.');
    }

    return _Options(
      guardPrecision: precision,
      guardJsonPath: valueOf('--guard-json'),
      freezeFile: valueOf('--freeze-file') ?? defaultFreezeFile,
      personasPath: valueOf('--personas') ?? defaultPersonas,
      catalogPath: valueOf('--catalog') ?? defaultCatalog,
      top: args.contains('--top'),
      ablation: args.contains('--ablation'),
      dumpBaselinePath: valueOf('--dump-baseline'),
      linksPath: valueOf('--links'),
      approach: valueOf('--approach') ?? 'M1',
      newPairsPath: valueOf('--new-pairs'),
    );
  }
}

/// One test user with the testers' labels.
class _Persona {
  final String id;
  final Map<String, dynamic> analysis;
  final String? experienceLevel;
  final List<String> gaps;

  /// opportunity id -> grade (1 or 2).
  final Map<String, int> grades;

  /// opportunity id -> normalized names of the gaps it teaches.
  final Map<String, Set<String>> teaches;

  const _Persona({
    required this.id,
    required this.analysis,
    required this.experienceLevel,
    required this.gaps,
    required this.grades,
    required this.teaches,
  });

  /// The same persona whose stored analysis also holds meaning links.
  _Persona withLinks(List<dynamic> links) => _Persona(
        id: id,
        analysis: {...analysis, 'gapLinks': links},
        experienceLevel: experienceLevel,
        gaps: gaps,
        grades: grades,
        teaches: teaches,
      );

  /// The same persona as if a tester had given each of [ids] the best
  /// label: [grade], and teaching every gap of the persona. Labels are only
  /// added: an item that has a label keeps it.
  _Persona withBestLabels(Iterable<String> ids, int grade) => _Persona(
        id: id,
        analysis: analysis,
        experienceLevel: experienceLevel,
        gaps: gaps,
        grades: {for (final id in ids) id: grade, ...grades},
        teaches: {
          for (final id in ids) id: gaps.map(SkillMatcher.normalize).toSet(),
          ...teaches,
        },
      );

  /// The gap coverage a perfect ranking could reach with these labels.
  double get bestGapCoverage =>
      gapCoverageAt(grades.length, grades.keys.toList(), teaches, gaps);
}

List<Opportunity> _loadCatalog(String path) {
  final decoded = _readJson(path);
  if (decoded is! List) _fail('$path is not a JSON list.');
  final result = <Opportunity>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final opportunity =
        Opportunity.fromMap('', Map<String, dynamic>.from(item));
    if (opportunity.id.isEmpty || opportunity.title.isEmpty) continue;
    result.add(opportunity);
  }
  return result;
}

/// Reads the personas and checks the labels. A label that cannot be used
/// (unknown id, closed on the evaluation date, grade not 1 or 2) is dropped
/// with a warning.
List<_Persona> _loadPersonas(String path, Map<String, Opportunity> byId) {
  final decoded = _readJson(path);
  if (decoded is! List) _fail('$path is not a JSON list.');

  List<String> strings(dynamic raw) => raw is List
      ? [
          for (final value in raw)
            if (value.toString().trim().isNotEmpty) value.toString().trim(),
        ]
      : <String>[];

  final personas = <_Persona>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final id = item['id']?.toString() ?? 'persona_${personas.length + 1}';
    final gaps = strings(item['skillGaps']);
    if (gaps.isEmpty) {
      stdout.writeln('WARNING $id: no skillGaps, persona skipped.');
      continue;
    }
    final gapKeys = gaps.map(SkillMatcher.normalize).toSet();

    final grades = <String, int>{};
    final teaches = <String, Set<String>>{};
    final labels = item['relevant'];
    for (final label in labels is List ? labels : const []) {
      if (label is! Map) continue;
      final opportunityId = label['id']?.toString() ?? '';
      final grade = label['grade'];
      final opportunity = byId[opportunityId];
      if (opportunity == null) {
        stdout.writeln('WARNING $id: unknown opportunity "$opportunityId", '
            'label dropped.');
        continue;
      }
      if (!opportunity.isOpen(evalDate)) {
        stdout.writeln('WARNING $id: "$opportunityId" is closed on the '
            'evaluation date, label dropped.');
        continue;
      }
      if (grade != 1 && grade != 2) {
        stdout.writeln('WARNING $id: "$opportunityId" has grade $grade '
            '(must be 1 or 2), label dropped.');
        continue;
      }
      final taught = strings(label['teaches']);
      for (final name in taught) {
        if (!gapKeys.contains(SkillMatcher.normalize(name))) {
          stdout.writeln('WARNING $id: "$opportunityId" teaches "$name", '
              'which is not one of the persona\'s gaps.');
        }
      }
      grades[opportunityId] = grade as int;
      teaches[opportunityId] = taught.map(SkillMatcher.normalize).toSet();
    }

    final targetSkills = strings(item['targetSkills']);
    personas.add(_Persona(
      id: id,
      analysis: {
        'careerGoalId': item['careerGoalId']?.toString() ?? '',
        'skillGaps': gaps,
        'currentSkills': strings(item['currentSkills']),
        if (targetSkills.isNotEmpty) 'targetSkills': targetSkills,
      },
      experienceLevel: item['experienceLevel']?.toString(),
      gaps: gaps,
      grades: grades,
      teaches: teaches,
    ));
  }
  if (personas.isEmpty) _fail('$path has no usable persona.');
  return personas;
}

dynamic _readJson(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    _fail('File not found: $path (run this from the project root).');
  }
  var text = file.readAsStringSync();
  if (text.startsWith('﻿')) text = text.substring(1);
  try {
    return jsonDecode(text);
  } on FormatException catch (e) {
    _fail('$path is not valid JSON: ${e.message}');
  }
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}

// ---------------------------------------------------------
// HELPERS (printing)
// ---------------------------------------------------------

String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _f(double value, int digits) => value.toStringAsFixed(digits);

String _signed(double value, int digits) =>
    '${value >= 0 ? '+' : ''}${value.toStringAsFixed(digits)}';

String _head3() =>
    '${'Baseline'.padLeft(10)}${'New'.padLeft(10)}${'Change'.padLeft(10)}';

void _row3(String name, double before, double after, {int digits = 3}) {
  stdout.writeln('  ${name.padRight(22)}'
      '${_f(before, digits).padLeft(10)}'
      '${_f(after, digits).padLeft(10)}'
      '${_signed(after - before, digits).padLeft(10)}');
}

/// One metric for every persona, with a wins / ties / losses line (a tie is
/// a change smaller than 0.0005).
void _perPersonaTable(
  String title,
  List<_Persona> personas,
  List<_Metrics> before,
  List<_Metrics> after,
  double Function(_Metrics) pick,
) {
  stdout.writeln('');
  stdout.writeln(title.toUpperCase());
  stdout.writeln('  ${'Persona'.padRight(34)}${_head3()}');
  var wins = 0;
  var ties = 0;
  var losses = 0;
  for (var i = 0; i < personas.length; i++) {
    final b = pick(before[i]);
    final a = pick(after[i]);
    final change = a - b;
    if (change.abs() < 0.0005) {
      ties++;
    } else if (change > 0) {
      wins++;
    } else {
      losses++;
    }
    stdout.writeln('  ${personas[i].id.padRight(34)}'
        '${_f(b, 3).padLeft(10)}${_f(a, 3).padLeft(10)}'
        '${_signed(change, 3).padLeft(10)}');
  }
  stdout.writeln('  ${'Average'.padRight(34)}'
      '${_f(_avg(before, pick), 3).padLeft(10)}'
      '${_f(_avg(after, pick), 3).padLeft(10)}'
      '${_signed(_avg(after, pick) - _avg(before, pick), 3).padLeft(10)}');
  stdout.writeln('  New is better for $wins, the same for $ties and worse '
      'for $losses of ${personas.length} personas.');
}

void _printTop(String name, _Persona persona, _Run run) {
  stdout.writeln('  Top 10, $name:');
  for (var i = 0; i < run.ids.length && i < 10; i++) {
    final grade = persona.grades[run.ids[i]] ?? 0;
    stdout.writeln('    ${(i + 1).toString().padLeft(2)}. '
        'grade $grade  score ${_f(run.scores[i], 3).padLeft(7)}  '
        '${run.titles[i]}  gaps=${run.gapSkills[i]}');
  }
}

// ---------------------------------------------------------
// MEANING LINKS (persona guard and timing guard)
// ---------------------------------------------------------

/// Reads the file link_persona_gaps.dart wrote: per run, the personas with
/// their links added to the analysis as `gapLinks`.
List<List<_Persona>> _linkedPersonas(String path, List<_Persona> personas) {
  final decoded = _readJson(path);
  final runs = decoded is Map ? decoded['links'] : null;
  if (runs is! List || runs.isEmpty) _fail('$path has no "links" list.');
  final result = <List<_Persona>>[];
  for (var r = 0; r < runs.length; r++) {
    final byPersona = runs[r] is Map ? runs[r] as Map : const {};
    final missing = [
      for (final persona in personas)
        if (byPersona[persona.id] is! List) persona.id,
    ];
    if (missing.isNotEmpty) {
      stdout.writeln('WARNING links run ${r + 1}: no links for '
          '${missing.join(', ')} (ranked without links, as the app does '
          'when the link request fails).');
    }
    result.add([
      for (final persona in personas)
        byPersona[persona.id] is List
            ? persona.withLinks(byPersona[persona.id] as List)
            : persona,
    ]);
  }
  return result;
}

/// What a guard file records about itself: the freeze it was written
/// under, the approach and its settings, the personas and links files with
/// their hashes, and the precision and tolerance of the persona guard. The
/// decision checks these fields (guardFileProblems), and so does
/// --guard-json before it measures anything.
Map<String, dynamic> _guardIdentity(
  _Options options,
  Approach approach,
  Map<String, dynamic> frozen,
) {
  final rule = frozenGuard(frozen);
  return {
    'freezeFile': slashes(options.freezeFile),
    'freezeSha256': freezeShaOf(options.freezeFile),
    'approach': approach.id,
    'source': approach.source.name,
    'opportunities': settingKey(approach.source, approach.opportunities),
    'certifications': settingKey(approach.source, approach.certifications),
    'personas': {
      'path': slashes(options.personasPath),
      'sha256': sha256OfText(readText(options.personasPath)),
    },
    'links': {
      'path': slashes(options.linksPath!),
      'sha256': sha256OfText(readText(options.linksPath!)),
    },
    // The precision the guard is computed at; guardJsonProblem and
    // guardFileProblems check it against the frozen one.
    'precision': options.guardPrecision == '3' ? 3 : 'full',
    'tolerance': rule.tolerance == 0 ? 0 : rule.tolerance,
  };
}

/// The guard for meaning links: the same personas ranked with links, next
/// to the ranking without links printed above. Labels were collected
/// without links, so an opportunity that only the links bring up has no
/// label and counts as not relevant until a tester labels it.
///
/// Returns what was measured, as --guard-json stores it next to the fields
/// of [_guardIdentity]. [frozen] is the freeze the guard file is written
/// under, or null: the tolerance is then 0. The precision is the one given
/// with --guard-precision.
Future<Map<String, dynamic>> _printLinkGuard(
  _Options options,
  List<_Persona> personas,
  List<Opportunity> catalog,
  List<_Run> plainRuns,
  Map<String, dynamic>? frozen,
) async {
  final approach = Approach.parse(options.approach);
  final linked = _linkedPersonas(options.linksPath!, personas);
  final weights = RankingWeights(links: approach.opportunities);

  final plain = [
    for (var i = 0; i < personas.length; i++)
      _Metrics.of(personas[i], plainRuns[i]),
  ];

  stdout.writeln('');
  stdout.writeln('MEANING LINKS, PERSONA GUARD, approach ${approach.id} '
      '(average over ${personas.length} personas)');
  stdout.writeln('  ${''.padRight(26)}${'nDCG@10'.padLeft(9)}'
      '${'GapCov@10'.padLeft(11)}${'P@5'.padLeft(8)}'
      '${'TopGapRank'.padLeft(12)}${'Changed'.padLeft(9)}'
      '${'New, no label'.padLeft(15)}');
  void row(String label, List<double> values, [String tail = '']) {
    stdout.writeln('  ${label.padRight(26)}${_f(values[0], 3).padLeft(9)}'
        '${_f(values[1], 3).padLeft(11)}${_f(values[2], 3).padLeft(8)}'
        '${_f(values[3], 2).padLeft(12)}$tail');
  }

  List<double> averages(List<_Metrics> metrics) => [
        _avg(metrics, (m) => m.ndcg10),
        _avg(metrics, (m) => m.gapCoverage10),
        _avg(metrics, (m) => m.precision5),
        _avg(metrics, (m) => m.topGapRank.toDouble()),
      ];
  final without = averages(plain);
  row('Without links (New above)', without);

  final decimals = options.guardPrecision == '3' ? 3 : null;
  final tolerance = frozen == null ? 0.0 : frozenGuard(frozen).tolerance;
  bool notWorse(List<double> values, {int? decimals, double tolerance = 0}) =>
      personaGuardPasses(values, without,
          decimals: decimals, tolerance: tolerance);

  // The best label a tester could give: the highest grade the persona file
  // uses, on an item that teaches every gap of its persona.
  final bestGrade = [
    for (final persona in personas) ...persona.grades.values,
  ].fold<int>(1, (best, grade) => grade > best ? grade : best);

  // The setting on the personas as they are (no links stored) must give
  // the ranking printed above, exactly.
  final recommender = OpportunityRecommender(weights: weights);
  var sameWithoutLinks = true;
  for (var i = 0; i < personas.length; i++) {
    final run = _runNew(recommender, personas[i], catalog);
    if (!_sameOrder(plainRuns[i], run)) sameWithoutLinks = false;
  }

  final runAverages = <List<double>>[];
  // [r][i]: the ranking of persona i in link run r.
  final linkRuns = <List<_Run>>[];
  // Per persona, the items without a label that newly entered the first 10
  // of any link run.
  final newUnlabelled = List.generate(personas.length, (_) => <String>{});
  final unlabelled = <String>{};
  for (var r = 0; r < linked.length; r++) {
    var changed = 0;
    var newWithoutLabel = 0;
    final metrics = <_Metrics>[];
    final runs = <_Run>[];
    for (var i = 0; i < personas.length; i++) {
      final persona = linked[r][i];
      final run = _runNew(recommender, persona, catalog);
      runs.add(run);
      metrics.add(_Metrics.of(persona, run));
      if (!_sameOrder(plainRuns[i], run)) changed++;
      final before = plainRuns[i].ids.take(10).toSet();
      for (var k = 0; k < run.ids.length && k < 10; k++) {
        final id = run.ids[k];
        if (before.contains(id) || persona.grades.containsKey(id)) continue;
        newWithoutLabel++;
        newUnlabelled[i].add(id);
        unlabelled.add('${persona.id}: ${run.titles[k]} ($id)');
      }
    }
    linkRuns.add(runs);
    final values = averages(metrics);
    runAverages.add(values);
    row('links run ${r + 1}', values,
        '${'$changed/${personas.length}'.padLeft(9)}'
        '${'$newWithoutLabel'.padLeft(15)}');
  }
  final meanValues = [
    for (var k = 0; k < 4; k++) mean(runAverages.map((v) => v[k])),
  ];

  // Rule 7.2 (b), "pending": blind labelling adds labels to the persona
  // file, so the guard is then run again with them on both sides and in
  // every link run. Here every such item gets the best label. Today's
  // numbers can fall too: a new label raises the best possible ranking.
  final bestPersonas = [
    for (var i = 0; i < personas.length; i++)
      newUnlabelled[i].isEmpty
          ? personas[i]
          : personas[i].withBestLabels(newUnlabelled[i], bestGrade),
  ];
  final todayBest = averages([
    for (var i = 0; i < personas.length; i++)
      _Metrics.of(bestPersonas[i], plainRuns[i]),
  ]);
  final bestByRun = [
    for (final runs in linkRuns)
      averages([
        for (var i = 0; i < personas.length; i++)
          _Metrics.of(bestPersonas[i], runs[i]),
      ]),
  ];
  final bestValues = [
    for (var k = 0; k < 4; k++) mean(bestByRun.map((v) => v[k])),
  ];
  row('links, mean of ${runAverages.length} runs', meanValues);
  if (unlabelled.isNotEmpty) {
    row('  no links, best labels', todayBest);
    row('  links, best labels', bestValues);
  }

  final passesFull = notWorse(meanValues);
  final passesThree = notWorse(meanValues, decimals: 3);
  final passes =
      notWorse(meanValues, decimals: decimals, tolerance: tolerance);
  final passesWithBest = personaGuardPasses(bestValues, todayBest,
      decimals: decimals, tolerance: tolerance);
  final status =
      guardStatus(passes: passes, passesWithBestLabels: passesWithBest);
  final precisionName = decimals == null ? 'full' : '3 decimals';
  final toleranceName = tolerance == 0 ? '0' : '0.02';
  String yes(bool value) => value ? 'yes' : 'NO';

  stdout.writeln('  An analysis without links gives the ranking above with '
      'this setting: ${yes(sameWithoutLinks)}');
  stdout.writeln('  links (mean of the runs), not worse than without links '
      'on all four numbers:');
  stdout.writeln('    at full precision, tolerance 0 : ${yes(passesFull)}');
  stdout.writeln('    at 3 decimals, tolerance 0     : ${yes(passesThree)}');
  stdout.writeln('    with the best labels for the ${unlabelled.length} '
      'unlabelled new items, precision $precisionName, tolerance '
      '$toleranceName: ${yes(passesWithBest)}');
  if (unlabelled.isNotEmpty) {
    stdout.writeln('      (both sides scored with those labels, in every '
        'link run, as the guard would be run after blind labelling)');
  }
  stdout.writeln('    with a tolerance of 0.02, full precision '
      '(${tolerance == 0.02 ? 'frozen' : 'not in force'}): '
      '${yes(notWorse(meanValues, tolerance: 0.02))}');
  stdout.writeln('  Differences to without links (mean of the runs): nDCG@10 '
      '${_f(meanValues[0] - without[0], 4)}, GapCov@10 '
      '${_f(meanValues[1] - without[1], 4)}, P@5 '
      '${_f(meanValues[2] - without[2], 4)}, TopGapRank '
      '${_f(meanValues[3] - without[3], 4)}');
  stdout.writeln('  (Changed: personas whose ranking differs from the one '
      'without links. New, no label: opportunities that');
  stdout.writeln('   entered the first 10 and that no tester labelled; they '
      'count as not relevant until they are labelled.)');
  if (unlabelled.isNotEmpty) {
    stdout.writeln('  To label:');
    for (final line in unlabelled) {
      stdout.writeln('    $line');
    }
  }
  if (decimals == 3) {
    // The table prints TopGapRank with 2 decimals; the guard compares all
    // four numbers at 3.
    String three(List<double> values) =>
        values.map((v) => _f(v, 3)).join(' / ');
    stdout.writeln('  Compared at 3 decimals (nDCG@10 / GapCov@10 / P@5 / '
        'TopGapRank): links ${three(meanValues)}, without links '
        '${three(without)}');
  }
  stdout.writeln('  PERSONA GUARD (precision $precisionName, tolerance '
      '$toleranceName): ${status == 'fail' ? 'FAIL' : status}'
      '${status == 'pending' ? '   (it fails as measured and passes with the best labels: the user decides on blind labelling)' : ''}');

  final certificationListsSame =
      _printCertificationLists(options, personas, linked, approach);
  final timing = _printTimingGuard(personas, linked.first, catalog, weights);

  return {
    'metrics': const ['nDCG@10', 'GapCov@10', 'P@5', 'TopGapRank'],
    'today': without,
    'withLinks': meanValues,
    'todayWithBestLabels': todayBest,
    'withBestLabels': bestValues,
    'linkRuns': runAverages.length,
    'passesFullPrecision': passesFull,
    'passesThreeDecimals': passesThree,
    'unlabelled': unlabelled.length,
    'unlabelledItems': unlabelled.toList(),
    'passesWithBestLabels': passesWithBest,
    'guardStatus': status,
    'sameWithoutLinks': sameWithoutLinks,
    'certificationListsSame': certificationListsSame,
    'warmRatio': timing.warmRatio,
    'firstRatio': timing.firstRatio,
    'timingPass': timingPasses(timing.warmRatio, timing.firstRatio),
  };
}

/// The certification list of every persona without links (which must be
/// the list of today) and with links, and the (skill gap, certification)
/// pairs that only the links attribute. Those pairs are what a reviewer
/// has to grade. Returns whether the lists without links are today's.
bool _printCertificationLists(
  _Options options,
  List<_Persona> personas,
  List<List<_Persona>> linked,
  Approach approach,
) {
  final certifications = loadCertifications();

  List<CertificationMatch> matched(_Persona persona, LinkSettings settings) =>
      ContentBasedRecommender(links: settings)
          .recommendCertifications(
            analysis: persona.analysis,
            certifications: certifications,
            experienceLevel: persona.experienceLevel,
          )
          .matched;
  String listOf(List<CertificationMatch> matches) => matches.isEmpty
      ? '(none)'
      : matches.map((m) => m.certification.id).join(', ');
  Set<String> pairsOf(List<CertificationMatch> matches) => {
        for (final match in matches)
          for (final skill in match.matchedSkills)
            '$skill|${match.certification.id}',
      };

  stdout.writeln('');
  stdout.writeln('CERTIFICATIONS PER PERSONA, without and with links');
  final newPairs = <String, List<String>>{};
  var sameAsToday = true;
  for (var i = 0; i < personas.length; i++) {
    final persona = personas[i];
    final none = matched(persona, LinkSettings.off);
    // The setting on an analysis without links.
    final today = matched(persona, approach.certifications);
    if (listOf(none) != listOf(today)) sameAsToday = false;
    stdout.writeln('  ${persona.id}');
    stdout.writeln('    without links : ${listOf(none)}');
    final known = pairsOf(none);
    for (var r = 0; r < linked.length; r++) {
      final withLinks = matched(linked[r][i], approach.certifications);
      final added = pairsOf(withLinks).difference(known);
      stdout.writeln('    links run ${r + 1}   : ${listOf(withLinks)}'
          '${added.isEmpty ? '' : '   new: ${added.map((p) => p.replaceFirst('|', ' -> ')).join('; ')}'}');
      for (final pair in added) {
        final parts = pair.split('|');
        final certification =
            certifications.firstWhere((c) => c.id == parts[1]);
        newPairs.putIfAbsent(
          '${persona.analysis['careerGoalId']}|$pair',
          () => [
            'p_${newPairs.length + 1}',
            persona.analysis['careerGoalId'].toString(),
            parts[0],
            'certification',
            certification.id,
            certification.name,
            '${certification.description} '
                'Skills: ${certification.skills.join(', ')}.',
            '',
            '',
          ],
        );
      }
    }
  }
  stdout.writeln('  Lists without links equal the lists of this setting on '
      'personas without links: ${sameAsToday ? 'yes' : 'NO'}');
  stdout.writeln('  (Skill gap, certification) pairs that only links '
      'attribute: ${newPairs.length}');

  final path = options.newPairsPath;
  if (path != null) {
    writeCsv(
      path,
      const [
        'row_id', 'career_goal_id', 'gap', 'item_type', 'item_id',
        'item_title', 'item_text', 'grade', 'note',
      ],
      newPairs.values.toList(),
    );
    stdout.writeln('  Written for grading (2 = teaches the skill as a main '
        'topic, 1 = as a clear part, 0 = no): $path');
  }
  return sameAsToday;
}

/// The timing guard: today's setting and the setting with links measured
/// in this process, 21 repetitions, taking turns so that neither runs
/// while the machine happens to be busier, and compared by their medians.
/// Returns the two ratios at full precision, which is how the limits are
/// compared.
({double warmRatio, double firstRatio}) _printTimingGuard(
  List<_Persona> personas,
  List<_Persona> linked,
  List<Opportunity> catalog,
  RankingWeights weights,
) {
  const today = OpportunityRecommender(
      weights: RankingWeights(links: LinkSettings.off));
  final candidate = OpportunityRecommender(weights: weights);
  const repetitions = 21;

  double milliseconds(void Function() action) {
    final watch = Stopwatch()..start();
    action();
    return watch.elapsedMicroseconds / 1000;
  }

  void all(OpportunityRecommender recommender, List<_Persona> list,
      List<Opportunity> opportunities) {
    for (final persona in list) {
      _runNew(recommender, persona, opportunities);
    }
  }

  // Warm-up, so neither side pays for the first compilation.
  all(today, linked, List<Opportunity>.of(catalog));
  all(candidate, linked, List<Opportunity>.of(catalog));

  // The two take turns in ABBA order: today first in even repetitions, the
  // candidate first in odd ones. Whichever runs second runs right after
  // the other's work (and its garbage), so a fixed order would always
  // charge that to the same side.
  void inTurn(int repetition, void Function() runToday,
      void Function() runCandidate) {
    if (repetition.isEven) {
      runToday();
      runCandidate();
    } else {
      runCandidate();
      runToday();
    }
  }

  // 1. recommend() with the index built: every persona once per
  //    repetition, on a list that already has its index and has seen
  //    these users.
  final warmList = List<Opportunity>.of(catalog);
  all(today, linked, warmList);
  all(candidate, linked, warmList);
  final warmToday = <double>[];
  final warmCandidate = <double>[];
  for (var i = 0; i < repetitions; i++) {
    inTurn(
      i,
      () => warmToday.add(milliseconds(() => all(today, linked, warmList))),
      () => warmCandidate
          .add(milliseconds(() => all(candidate, linked, warmList))),
    );
  }

  // 2. The first call on a new list: the index is built, then the first
  //    persona is ranked.
  final firstToday = <double>[];
  final firstCandidate = <double>[];
  for (var i = 0; i < repetitions; i++) {
    final a = List<Opportunity>.of(catalog);
    final b = List<Opportunity>.of(catalog);
    inTurn(
      i,
      () => firstToday.add(milliseconds(() => _runNew(today, linked.first, a))),
      () => firstCandidate
          .add(milliseconds(() => _runNew(candidate, linked.first, b))),
    );
  }

  final warmRatio = median(warmCandidate) / median(warmToday);
  final firstRatio = median(firstCandidate) / median(firstToday);
  stdout.writeln('');
  stdout.writeln('TIMING GUARD (same process, $repetitions repetitions '
      'taking turns in ABBA order, medians; links run 1)');
  stdout.writeln('  recommend() for all ${linked.length} personas, index '
      'built: today ${_f(median(warmToday), 2)} ms, with links '
      '${_f(median(warmCandidate), 2)} ms, ratio ${_f(warmRatio, 2)} '
      '(limit 2.00): ${warmRatio <= 2 ? 'pass' : 'FAIL'}');
  stdout.writeln('  first recommend() on a new list (builds the index): '
      'today ${_f(median(firstToday), 1)} ms, with links '
      '${_f(median(firstCandidate), 1)} ms, ratio ${_f(firstRatio, 2)} '
      '(limit 1.10): ${firstRatio <= firstRatioLimit ? 'pass' : 'FAIL'}');
  stdout.writeln('  The ratios are compared at full precision: '
      '${_f(warmRatio, 4)} and ${_f(firstRatio, 4)}.');
  return (warmRatio: warmRatio, firstRatio: firstRatio);
}
