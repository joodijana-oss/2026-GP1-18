import 'dart:convert';
import 'dart:io';

import 'package:masra/models/opportunity.dart';
import 'package:masra/services/opportunity_index.dart';
import 'package:masra/services/opportunity_recommender.dart';
import 'package:masra/utils/skill_matcher.dart';

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

  const _Options({
    required this.personasPath,
    required this.catalogPath,
    required this.top,
    required this.ablation,
    required this.dumpBaselinePath,
  });

  factory _Options.parse(List<String> args) {
    String? valueOf(String flag) {
      final index = args.indexOf(flag);
      if (index < 0) return null;
      if (index + 1 >= args.length) _fail('$flag needs a file path.');
      return args[index + 1];
    }

    return _Options(
      personasPath: valueOf('--personas') ?? defaultPersonas,
      catalogPath: valueOf('--catalog') ?? defaultCatalog,
      top: args.contains('--top'),
      ablation: args.contains('--ablation'),
      dumpBaselinePath: valueOf('--dump-baseline'),
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
