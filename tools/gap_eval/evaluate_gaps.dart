import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:masra/services/career_analysis_pipeline.dart';
import 'package:masra/services/job_postings.dart';
import 'package:masra/services/skill_gap_check.dart';

import 'eval_data.dart';
import 'eval_support.dart';
import 'gap_scoring.dart';

/// Evaluation of the skill gaps of the career analysis (real AI requests).
///
/// It runs the analysis steps the app runs (the same pipeline code) on a
/// set of test CVs, once per arm, and compares the gaps with the labels of
/// the person who wrote the CVs.
///
/// Arms (pass any of them with --arms):
///   G0E0  the original analysis: gaps by comparing two lists of names;
///         market names as they come.
///   G0E1  the same gap step, with single-skill market names.
///   G1E1  single-skill names, and the gap step reads the CV text. The
///         held-out evaluation chose it, and the app runs it
///         (AnalysisSettings.app).
///   G2E1  single-skill names, gaps by names, then a second request checks
///         each gap against the CV text. It lost and left the app; it runs
///         from its prompt text, tools/gap_eval/arms/gap_verification.txt,
///         sent through the AI service's JSON request, so it can still be
///         measured again.
///
/// The meaning links of the matching evaluation are in the app's code
/// again, switched off (the constants of LinkSettings in
/// lib/models/gap_link.dart): no link request is sent until an approach
/// passes its rules. They are measured with link_lists.dart,
/// evaluate_matching.dart and final_matching.dart, not by this tool; the
/// first request's text is also in tools/gap_eval/arms/skill_links.txt.
///
/// Paired inputs: for a CV and a run, the CV is read once and every arm
/// uses that answer. For a career goal, an extractor and a run, the market
/// skills are requested once and every CV of that goal uses them. So two
/// arms differ only in the step being compared. Every answer is stored in
/// the run folder, and a stored answer is never requested again, so a run
/// that stopped can be continued and every arm can be scored again later
/// without new requests.
///
/// Run from the project root:
///
///   dart run tools/gap_eval/evaluate_gaps.dart --set `folder`
///       --arms G0E0,G0E1,G1E1,G2E1 --runs 3
///
/// Options:
///   --set `folder`          the test set (manifest.json, CVs, labels)
///   --arms `list`           arms to run (default G0E0,G0E1,G1E1,G2E1)
///   --runs `n`              runs per case (default 3)
///   --out `folder`          the run folder (default
///                           build/gap_eval/`set`_`time`); pass an existing
///                           one to continue it
///   --partly-is-gap         count a partly shown skill as a gap
///   --concurrency `n`       requests at the same time (default 3)
///   --dry-run               print what would be requested and stop
///   --score `run folder`    score a finished run again (no requests) and
///                           write the review sheet for unjudged names
///   --details               with --score: also print the gaps per CV
///   --freeze                write the freeze file (hashes of the prompts,
///                           the code, the test set and the settings)
///   --freeze-file `file`    where the freeze file is (default
///                           tools/gap_eval/freeze.json)
///   --plan `file`           the plan whose decision rules are frozen too
///   --export-prompts        write the prompt texts the app still uses to
///                           tools/gap_eval/arms/
///
/// A held-out set (manifest "set": "heldout") only runs when the freeze
/// file matches: nothing may change between the freeze and the run.
///
/// The API key is read from `.env` by this tool and handed to the AI
/// service only. It is never printed or stored.
const List<String> defaultArms = ['G0E0', 'G0E1', 'G1E1', 'G2E1'];
const String defaultFreezeFile = 'tools/gap_eval/freeze.json';
const int defaultSeed = 20261119;

Future<void> main(List<String> arguments) async {
  final args = Args(arguments, known: const {
    '--arms', '--concurrency', '--details', '--dry-run', '--export-prompts',
    '--freeze', '--freeze-file', '--out', '--partly-is-gap', '--plan',
    '--runs', '--score', '--seed', '--set',
  });
  if (args.has('--export-prompts')) return _exportPrompts();
  final scorePath = args.value('--score');
  if (scorePath != null) {
    return _score(RunFolder(scorePath), details: args.has('--details'));
  }
  final setPath = args.value('--set') ?? fail('Pass --set <folder>.');
  final set = EvalSet.load(setPath);
  final arms = [
    for (final id in args.list('--arms').isEmpty
        ? defaultArms
        : args.list('--arms'))
      Arm.parse(id),
  ];
  final runs = args.integer('--runs', 3);
  final settings = <String, dynamic>{
    'set': set.name,
    'setPath': set.folder,
    'arms': [for (final arm in arms) arm.id],
    'runs': runs,
    'partlyIsGap': args.has('--partly-is-gap'),
    'seed': args.integer('--seed', defaultSeed),
  };
  final freezeFile = args.value('--freeze-file') ?? defaultFreezeFile;

  if (args.has('--freeze')) {
    final freeze = _freezeOf(set, settings, args.value('--plan'));
    writeJson(freezeFile, freeze);
    stdout.writeln('Freeze written to $freezeFile');
    (freeze['hashes'] as Map).forEach((name, hash) {
      stdout.writeln('  ${name.toString().padRight(22)} $hash');
    });
    return;
  }

  final careerNames = loadCareerNames();
  final goals = set.goals;
  for (final goal in goals) {
    if (!careerNames.containsKey(goal)) fail('Unknown career goal "$goal".');
  }
  final extractors = {for (final arm in arms) arm.extractorId}.toList()..sort();

  // ---- plan ---------------------------------------------------------
  final analyzeCount = set.cases.length * runs;
  final marketCount = goals.length * extractors.length * runs;
  var gapRequests = 0;
  for (final arm in arms) {
    gapRequests += set.cases.length * runs * (arm.gapMethod == 2 ? 2 : 1);
  }
  stdout.writeln('SKILL GAP EVALUATION');
  stdout.writeln('Test set   : ${set.folder} ("${set.name}", '
      '${set.cases.length} CVs, ${set.goals.length} career goals)');
  stdout.writeln('Arms       : ${[for (final a in arms) a.id].join(', ')}');
  stdout.writeln('Runs       : $runs per case');
  stdout.writeln('Requests   : $analyzeCount CV readings, $marketCount '
      'market-skill requests, $gapRequests gap requests (more when a '
      'fallback runs); about '
      '${analyzeCount + marketCount + gapRequests} in all');
  if (args.has('--dry-run')) {
    stdout.writeln('Dry run: nothing was requested.');
    return;
  }

  if (set.name == 'heldout') {
    _checkFreeze(freezeFile, _freezeOf(set, settings, args.value('--plan')));
  }

  final stamp = DateTime.now()
      .toIso8601String()
      .substring(0, 19)
      .replaceAll(RegExp('[-:]'), '')
      .replaceAll('T', '_');
  final run = RunFolder(
      args.value('--out') ?? 'build/gap_eval/${slug(set.name)}_$stamp');
  writeJson(run.configPath, {...settings, 'startedAt': stamp});
  stdout.writeln('Run folder : ${run.path}');

  // ---- the same data and code as the app ----------------------------
  final opportunities = loadOpportunities();
  final certifications = loadCertifications();
  final names = loadCatalogueNames(opportunities, certifications);
  final jobsCsv = readText(jobsPath);
  final ai = newAi();
  final concurrency = args.integer('--concurrency', 3);
  final partlyIsGap = settings['partlyIsGap'] == true;

  // G2 starts from the gaps found by names (G0 with the same extractor).
  AnalysisSettings settingsOf(Arm arm) => AnalysisSettings(
        gapMethod:
            arm.gapMethod == 1 ? GapMethod.cvEvidence : GapMethod.namesOnly,
        singleSkillNames: arm.extractor == 1,
        partlyIsGap: partlyIsGap,
      );
  CareerAnalysisPipeline pipelineOf(AnalysisSettings s) =>
      CareerAnalysisPipeline(ai, settings: s, names: names);

  /// The gaps of one arm. G0 and G1 are the app's own code; G2 adds its
  /// verification request from the arm text on top of G0.
  Future<GapOutcome> gapsOf(
    Arm arm,
    EvalCase c,
    Map<String, dynamic> cvAnalysis,
    List<String> targets,
  ) async {
    final settings = settingsOf(arm);
    final outcome = await pipelineOf(settings).skillGaps(
      cvText: c.cvText,
      cvAnalysis: cvAnalysis,
      targetSkills: targets,
    );
    if (arm.gapMethod != 2) return outcome;
    return verifiedFromArmText(
      outcome.gaps,
      cvText: c.cvText,
      cvAnalysis: cvAnalysis,
      settings: settings,
      requestJson: ai.requestJson,
    );
  }

  /// Runs [request] unless [path] already holds its answer. With [retry],
  /// a failed request is sent once more: reading the CV and the postings
  /// is the same for every arm, so a network error there says nothing
  /// about an arm. A gap request is never retried; its fallbacks are part
  /// of what is measured.
  Future<void> stored(
    String path,
    Future<Map<String, dynamic>> Function() request, {
    bool retry = false,
  }) async {
    if (File(path).existsSync()) {
      final old = readJson(path);
      if (old is Map && old['error'] == null) return;
    }
    for (var attempt = 1;; attempt++) {
      try {
        writeJson(path, await request());
        return;
      } catch (error) {
        if (retry && attempt < 2) continue;
        writeJson(path, {'error': error.toString().split('\n').first});
        return;
      }
    }
  }

  void progress(String what, int done, int total) {
    if (done == total || done % 10 == 0) {
      stdout.writeln('  $what: $done/$total');
    }
  }

  // ---- stage 1: read the CVs and the job postings --------------------
  final stage1 = <Future<void> Function()>[];
  for (final c in set.cases) {
    for (var r = 1; r <= runs; r++) {
      stage1.add(() => stored(
            run.analyzePath(c.id, r),
            () async => {'cvAnalysis': await ai.analyzeCv(cvText: c.cvText)},
            retry: true,
          ));
    }
  }
  for (final goal in goals) {
    final jobs = JobPostings.relevant(jobsCsv, goal,
        limit: JobPostings.analysisLimit);
    if (jobs.isEmpty) fail('No job postings for "$goal".');
    final marketText = JobPostings.marketText(jobs);
    for (final extractor in extractors) {
      final pipeline = pipelineOf(
          AnalysisSettings(singleSkillNames: extractor == 'E1'));
      for (var r = 1; r <= runs; r++) {
        stage1.add(() => stored(
              run.marketPath(goal, extractor, r),
              () async {
                final raw = await ai.extractMarketSkills(
                  careerName: careerNames[goal]!,
                  jobMarketText: marketText,
                  singleSkillNames: pipeline.settings.singleSkillNames,
                );
                return {
                  'goal': goal,
                  'extractor': extractor,
                  'run': r,
                  'postings': jobs.length,
                  'rawNames': raw,
                  'names': pipeline.cleanMarketSkills(raw),
                };
              },
              retry: true,
            ));
      }
    }
  }
  await runPool(stage1,
      concurrency: concurrency,
      onProgress: (done, total) => progress('CVs and postings', done, total));

  // ---- stage 2: gaps per arm ------------------------------------------
  final stage2 = <Future<void> Function()>[];
  for (final c in set.cases) {
    for (var r = 1; r <= runs; r++) {
      final cvAnalysis = run.analysis(c.id, r);
      for (final arm in arms) {
        final targets = run.market(c.goalId, arm.extractorId, r);
        final path = run.gapsPath(c.id, arm.id, r);
        if (cvAnalysis == null || targets == null) {
          writeJson(path, {'error': 'no CV reading or no market skills'});
          continue;
        }
        stage2.add(() => stored(path, () async {
              final outcome = await gapsOf(arm, c, cvAnalysis, targets);
              return {
                'case': c.id,
                'arm': arm.id,
                'run': r,
                'gaps': outcome.gaps,
                'method': outcome.method,
                'usedFallback': outcome.usedFallback,
                'failure': outcome.failure,
                'unverifiedQuotes': outcome.unverifiedQuotes,
                'statuses': outcome.statuses,
              };
            }));
      }
    }
  }
  await runPool(stage2,
      concurrency: concurrency,
      onProgress: (done, total) => progress('gaps', done, total));

  await _score(run, details: args.has('--details'));
}

// ---------------------------------------------------------
// SCORING
// ---------------------------------------------------------

Future<void> _score(RunFolder run, {required bool details}) async {
  final config = run.config;
  final set = EvalSet.load(config['setPath'].toString());
  final arms = [
    for (final id in config['arms'] as List) Arm.parse(id.toString()),
  ];
  final runs = (config['runs'] as num).toInt();
  final names = loadCatalogueNames(loadOpportunities(), loadCertifications());
  final out = StringBuffer();
  void line([String text = '']) {
    stdout.writeln(text);
    out.writeln(text);
  }

  // ---- the review sheet for names nobody has judged yet --------------
  final pending = <String, List<String>>{};
  final reviewed = <String, List<String>>{};
  for (final c in set.cases) {
    for (final extractor in {for (final arm in arms) arm.extractorId}) {
      for (var r = 1; r <= runs; r++) {
        for (final String name
            in run.market(c.goalId, extractor, r) ?? const <String>[]) {
          if (c.statusByName.containsKey(keyOf(name))) continue;
          final key = EvalSet.judgementKey(c.id, name);
          final row = [
            'n_${sha256OfText(key).substring(0, 10)}',
            c.id,
            name,
            '',
            '',
            '',
            '',
          ];
          reviewed.putIfAbsent(key, () => row);
          if (!set.judgements.containsKey(key)) {
            pending.putIfAbsent(key, () => row);
          }
        }
      }
    }
  }
  const namesHeader = [
    'row_id', 'case_id', 'name', 'status', 'label_skill', 'bundled', 'note',
  ];
  final seed = (config['seed'] as num?)?.toInt() ?? defaultSeed;
  final reviewRows = pending.values.toList()..shuffle(Random(seed));
  writeCsv('${run.path}/review/names_review.csv', namesHeader, reviewRows);
  // A fifth of all reviewed rows, without answers, for the second rater.
  final secondRows = reviewed.values.toList()..shuffle(Random(seed + 1));
  writeCsv('${run.path}/review/names_second.csv', namesHeader,
      secondRows.take((secondRows.length / 5).ceil()).toList());

  // ---- scores ---------------------------------------------------------
  line('SKILL GAP SCORES  (${run.path})');
  line('Test set: ${set.folder} ("${set.name}"), ${set.cases.length} CVs, '
      '$runs runs per case');
  if (pending.isNotEmpty) {
    line('PROVISIONAL: ${pending.length} (CV, name) pairs are not judged '
        'yet. They are left out of the scores below.');
    line('  Fill ${run.path}/review/names_review.csv, add its rows to '
        '${set.namesSheet}, then run --score again.');
  }

  final splits = <String, bool Function(EvalCase)?>{
    'all CVs': null,
    'unseen goals': (c) => !c.seenGoal,
    'seen goals': (c) => c.seenGoal,
  };
  final scores = <String, Map<String, GapScores>>{};
  for (final split in splits.entries) {
    final perArm = <String, GapScores>{};
    for (final arm in arms) {
      perArm[arm.id] = scoreArm(
        set: set,
        run: run,
        arm: arm,
        runs: runs,
        isKnown: names.isKnown,
        only: split.value,
      );
    }
    scores[split.key] = perArm;
    if (perArm.values.every((s) => s.cvs == 0)) continue;
    line();
    line('${split.key.toUpperCase()}  (${perArm.values.first.cvs} CVs)');
    line('  ${'Arm'.padRight(6)}${'FalseGap'.padLeft(9)}${'CVs>0'.padLeft(7)}'
        '${'Recall'.padLeft(8)}${'Prec'.padLeft(7)}${'F1'.padLeft(7)}'
        '${'Bundled'.padLeft(9)}${'(detector)'.padLeft(11)}'
        '${'Stable'.padLeft(8)}${'Fallback'.padLeft(10)}'
        '${'BadQuote'.padLeft(10)}${'Gaps'.padLeft(6)}${'Errors'.padLeft(8)}');
    for (final s in perArm.values) {
      line('  ${s.arm.padRight(6)}${f3(s.falseGap).padLeft(9)}'
          '${f3(s.cvsWithFalseGap).padLeft(7)}${f3(s.recall).padLeft(8)}'
          '${f3(s.precision).padLeft(7)}${f3(s.f1).padLeft(7)}'
          '${f3(s.bundled).padLeft(9)}${f3(s.bundledByDetector).padLeft(11)}'
          '${f3(s.stability).padLeft(8)}${f3(s.fallbackRate).padLeft(10)}'
          '${f3(s.unverifiedQuoteRate).padLeft(10)}'
          '${s.gapsPerRun.toStringAsFixed(1).padLeft(6)}'
          '${s.errors.toString().padLeft(8)}');
    }
  }
  line();
  line('  FalseGap: share of the gaps that the CV clearly shows (lower is '
      'better). CVs>0: share of the analyses with at least one such gap.');
  line('  Recall: share of the skills the CV does not show that were '
      'returned as gaps. Bundled: share of the gap names a reviewer marked');
  line('  as several things in one name; (detector) is the same by the '
      'shape of the name. Stable: how alike the runs of one CV are.');
  line('  Fallback: share of the runs where the wanted gap step failed and '
      'the fallback answered. BadQuote: answers dropped because their');
  line('  quote is not in the CV. Errors: runs without any result.');

  line();
  line('MARKET SKILL NAMES (the extractor), bundled share');
  for (final extractor in {for (final arm in arms) arm.extractorId}) {
    final b = bundledTargets(
      set: set,
      run: run,
      extractor: extractor,
      runs: runs,
      isKnown: names.isKnown,
    );
    line('  $extractor: reviewers ${f3(b.reviewer)}, detector '
        '${f3(b.detector)}  (${b.names} names)');
  }

  // ---- against today's analysis, and the decision rules ---------------
  final base = scores['all CVs']!['G0E0'];
  if (base == null || base.cvs == 0) {
    line();
    line('No G0E0 arm in this run: nothing to compare with.');
  } else {
    line();
    line('AGAINST G0E0 (the original analysis), paired over CVs, 95% bootstrap interval');
    final passed = <String>[];
    for (final arm in arms) {
      if (arm.id == 'G0E0') continue;
      final all = scores['all CVs']![arm.id]!;
      final unseen = scores['unseen goals']![arm.id]!;
      final unseenBase = scores['unseen goals']!['G0E0']!;
      final dAll = pairedDifference(all.falseGapByCase, base.falseGapByCase);
      final dUnseen =
          pairedDifference(unseen.falseGapByCase, unseenBase.falseGapByCase);
      final dRecall = pairedDifference(all.recallByCase, base.recallByCase);
      line('  ${arm.id}');
      line('    FalseGap, all CVs     : ${signed3(dAll.difference)}  '
          '[${signed3(dAll.low)}, ${signed3(dAll.high)}]  (${dAll.cvs} CVs)');
      line('    FalseGap, unseen goals: ${signed3(dUnseen.difference)}  '
          '[${signed3(dUnseen.low)}, ${signed3(dUnseen.high)}]  '
          '(${dUnseen.cvs} CVs)');
      line('    Recall, all CVs       : ${signed3(dRecall.difference)}  '
          '[${signed3(dRecall.low)}, ${signed3(dRecall.high)}]');

      final guards = <String, bool>{
        'every run gave a result': all.errors == 0,
        'recall not more than 0.05 below G0E0':
            all.recall >= base.recall - 0.05,
        'bundled gap names at most 2% (reviewers)': all.bundled <= 0.02,
        'fallback in at most 10% of the runs': all.fallbackRate <= 0.10,
      };
      final adoption = <String, bool>{
        'FalseGap at least 0.05 lower on all CVs, interval excludes 0':
            dAll.difference <= -0.05 && dAll.high < 0,
        'FalseGap at least 0.05 lower on unseen goals (point estimate)':
            dUnseen.cvs > 0 && dUnseen.difference <= -0.05,
      };
      for (final rule in {...guards, ...adoption}.entries) {
        line('    ${rule.value ? 'pass' : 'FAIL'}  ${rule.key}');
      }
      if ([...guards.values, ...adoption.values].every((ok) => ok)) {
        passed.add(arm.id);
      }
    }
    line();
    if (pending.isNotEmpty) {
      line('DECISION: none yet, the scores are provisional (unjudged names).');
    } else if (passed.isEmpty) {
      line('DECISION: no arm passes every rule. Today\'s analysis stays.');
    } else {
      passed.sort((a, b) => scores['all CVs']![a]!
          .falseGap
          .compareTo(scores['all CVs']![b]!.falseGap));
      line('DECISION: arms that pass every rule, lowest FalseGap first: '
          '${passed.join(', ')}');
      if (passed.length > 1) {
        final first = scores['all CVs']![passed[0]]!;
        final second = scores['all CVs']![passed[1]]!;
        final d =
            pairedDifference(first.falseGapByCase, second.falseGapByCase);
        line('  ${passed[0]} against ${passed[1]}: '
            '${signed3(d.difference)} [${signed3(d.low)}, ${signed3(d.high)}]'
            '${d.low <= 0 && d.high >= 0 ? '  within noise: prefer fewer requests (G1 before G2), then the more stable arm' : ''}');
      }
      if (set.name != 'heldout') {
        line('  This is not the held-out set: use it to develop, not to '
            'decide.');
      }
    }
  }

  if (details) {
    line();
    line('GAPS PER CV  (! = the CV shows it, ~ = partly, ? = not judged)');
    for (final c in set.cases) {
      line('  ${c.id}  (${c.goalId})');
      for (final arm in arms) {
        for (var r = 1; r <= runs; r++) {
          final record = run.gaps(c.id, arm.id, r);
          if (record == null) continue;
          final marked = [
            for (final gap in record.gaps)
              '${const {
                    'shown': '!',
                    'partly': '~',
                    'not_shown': '',
                  }[set.statusOf(c, gap)] ?? '?'}$gap',
          ];
          line('    ${arm.id} r$r${record.usedFallback ? ' (fallback)' : ''}'
              '${record.error != null ? ' ERROR ${record.error}' : ''}: '
              '${marked.join('; ')}');
        }
      }
    }
  }

  File('${run.path}/scores.txt').writeAsStringSync(out.toString());
  writeJson('${run.path}/scores.json', {
    for (final split in scores.entries)
      split.key: {
        for (final s in split.value.values)
          s.arm: {
            'cvs': s.cvs,
            'falseGap': s.falseGap,
            'cvsWithFalseGap': s.cvsWithFalseGap,
            'recall': s.recall,
            'precision': s.precision,
            'f1': s.f1,
            'bundled': s.bundled,
            'bundledByDetector': s.bundledByDetector,
            'stability': s.stability,
            'fallbackRate': s.fallbackRate,
            'unverifiedQuoteRate': s.unverifiedQuoteRate,
            'gapsPerRun': s.gapsPerRun,
            'errors': s.errors,
            'emptyGapRuns': s.emptyGapRuns,
            'recallSkipped': s.recallSkipped,
            'unjudged': s.unjudged,
          },
      },
  });
  stdout.writeln();
  stdout.writeln('Scores written to ${run.path}/scores.txt and scores.json; '
      'review sheets in ${run.path}/review/');
}

// ---------------------------------------------------------
// FREEZE
// ---------------------------------------------------------

/// Everything that must not change between the freeze and the held-out
/// run, as hashes: the prompts and all the code that takes part (the app's
/// services, models and matching code, and these tools), the catalogue
/// data, the test set files, the settings of the run, and the decision
/// rules of the plan when its file is given.
Map<String, dynamic> _freezeOf(
  EvalSet set,
  Map<String, dynamic> settings,
  String? planPath,
) {
  String? decisionRules;
  if (planPath != null) {
    final plan = readText(planPath);
    final from = plan.indexOf('### 4.5');
    final to = plan.indexOf('### 4.6');
    if (from < 0 || to < from) fail('$planPath has no section 4.5.');
    decisionRules = sha256OfText(plan.substring(from, to));
  }
  return {
    'settings': {
      for (final key in const ['set', 'arms', 'runs', 'partlyIsGap', 'seed'])
        key: settings[key],
    },
    'hashes': {
      'services': sha256OfFolder('lib/services'),
      'utils': sha256OfFolder('lib/utils'),
      'models': sha256OfFolder('lib/models'),
      'gapEvalTools': sha256OfFolder('tools/gap_eval'),
      'recommenderEvalTools': sha256OfFolder('tools/recommender_eval'),
      'catalogueData': sha256OfFolder('lib/assets/data',
          extensions: const ['.json', '.csv']),
      'testSet': sha256OfFolder(set.folder,
          extensions: const ['.json', '.txt'], skip: const {'judgements'}),
      'decisionRules': ?decisionRules,
    },
  };
}

void _checkFreeze(String freezeFile, Map<String, dynamic> now) {
  if (!File(freezeFile).existsSync()) {
    fail('This is a held-out set and there is no freeze file ($freezeFile). '
        'Run with --freeze first, when development is finished.');
  }
  final frozen = readJson(freezeFile);
  final differences = <String>[];
  void compare(String part) {
    final a = frozen is Map ? frozen[part] : null;
    final b = now[part] as Map;
    for (final key in {...(a is Map ? a.keys : const []), ...b.keys}) {
      // The decision rules are compared only when the plan file is given.
      if (key == 'decisionRules' && b[key] == null) continue;
      if ('${a is Map ? a[key] : null}' != '${b[key]}') {
        differences.add('$part.$key');
      }
    }
  }

  compare('settings');
  compare('hashes');
  if (differences.isNotEmpty) {
    fail('The held-out run does not match the freeze file ($freezeFile). '
        'Changed since the freeze: ${differences.join(', ')}.\n'
        'Nothing was requested. A change after the freeze means the '
        'held-out numbers would no longer be blind.');
  }
  stdout.writeln('Freeze file matches: $freezeFile');
}

// ---------------------------------------------------------
// PROMPT TEXTS
// ---------------------------------------------------------

/// Writes the texts of the requests the app still makes to
/// tools/gap_eval/arms/, with placeholders for the inputs. The texts of
/// the arms that left the app are already there and are not touched.
void _exportPrompts() {
  promptTexts().forEach((name, text) {
    File('tools/gap_eval/arms/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    stdout.writeln('tools/gap_eval/arms/$name  ${sha256OfText(text)}');
  });
}

// ---------------------------------------------------------
// G2: THE VERIFICATION ARM, FROM ITS TEXT
// ---------------------------------------------------------

/// G2 as it ran in the held-out evaluation, before it left the app: the
/// gaps found by names ([proposed]) are checked against the CV text by one
/// more request (tools/gap_eval/arms/gap_verification.txt), with the same
/// time limit, the same quote check and the same fallback (when the check
/// fails, the gaps found by names are kept).
Future<GapOutcome> verifiedFromArmText(
  List<String> proposed, {
  required String cvText,
  required Map<String, dynamic> cvAnalysis,
  required AnalysisSettings settings,
  required Future<Map<String, dynamic>> Function({
    required String prompt,
    required int maxTokens,
    Duration? timeLimit,
  }) requestJson,
}) async {
  if (proposed.isEmpty) {
    return const GapOutcome(gaps: [], method: GapOutcome.namesOnly);
  }
  try {
    final decoded = await requestJson(
      prompt: filledArm(
        'gap_verification.txt',
        cvText: cvText,
        lists: {
          'CERTIFICATIONS_HELD':
              CareerAnalysisPipeline.heldCertifications(cvAnalysis),
          'SKILL_GAPS_FOUND_BY_NAMES': proposed,
        },
      ),
      maxTokens: 2500,
      timeLimit: settings.gapCheckLimit,
    ).timeout(settings.gapCheckLimit);
    final checked = SkillGapCheck.resolve(
      targetSkills: proposed,
      raw: decoded['skills'],
      cvText: cvText,
      partlyIsGap: settings.partlyIsGap,
    );
    return GapOutcome(
      gaps: checked.gaps,
      method: namesVerified,
      statuses: checked.toStoredList(),
      unverifiedQuotes: checked.unverifiedQuotes,
    );
  } catch (error) {
    return GapOutcome(
      gaps: proposed,
      method: GapOutcome.namesOnly,
      usedFallback: true,
      failure: error is TimeoutException
          ? 'time limit reached'
          : error.toString(),
    );
  }
}

/// The method name G2 records in its answers.
const String namesVerified = 'names-verified';
