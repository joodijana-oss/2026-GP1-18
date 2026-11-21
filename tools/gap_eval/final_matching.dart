import 'dart:io';

import 'package:masra/models/gap_link.dart';
import 'package:masra/services/career_analysis_pipeline.dart';
import 'package:masra/services/job_postings.dart';
import 'package:masra/services/opportunity_index.dart';
import 'package:masra/utils/skill_matcher.dart';

import 'approaches.dart';
import 'decision_rules.dart';
import 'eval_data.dart';
import 'eval_support.dart';
import 'freeze_r2.dart';
import 'link_requests.dart';

/// The requests of the final matching measurement, and the freeze that
/// guards it. The measurement runs once, by one agent, after development
/// is finished; everything it may use is fixed by the freeze file.
///
/// What it does, in this order:
///   1. checks the freeze (nothing is requested when anything changed);
///   2. records the SHA-256 of every file of the untouched set;
///   3. reads the writers' skill names of the set (stratum W): the "skill"
///      field of every label file and of the role file, per career goal;
///   4. asks for the market skills of the decision goals (stratum M),
///      8 lists per goal, with the app's own request;
///   5. prints the size report: the hole names per stratum and catalogue,
///      after the exclusion list;
///   6. asks for the links of every market list (one answer per list and
///      frozen link request) and of the writers' hole names (requests of
///      at most 12 names, 3 answers each).
/// After it, evaluate_matching.dart pools, and scores once every pooled
/// pair is graded.
///
/// Freeze, when development is finished (no request):
///
///   dart run tools/gap_eval/final_matching.dart --write-freeze \
///     --candidates `ids` --requests `names,typed` \
///     --persona-links `development links file,held-out links file` \
///     --persona-precision full|3 --precision-source `where the user set it` \
///     --persona-tolerance 0 \
///     --link-grace-seconds `n` --grace-source `where the user set it` \
///     --writer-names on|off --writer-source `the user's answer` \
///     [--earlier-grades `sheet`, with --writer-names on only]
///
/// The freeze records, each with its source: how the persona guard compares
/// (at full precision, the default, or at 3 decimals; a tolerance of 0.02
/// needs --tolerance-source), how long the analysis waits for links after
/// the gap step (it must be what the app does), and whether the writers'
/// names of the set are decision names. --earlier-grades names a sheet of
/// an earlier run that the report compares with; it is hashed and never
/// used as grades. It is required with --writer-names on and refused with
/// off. An existing freeze file is never written again.
///
/// Check (no request):
///
///   dart run tools/gap_eval/final_matching.dart --freeze-check
///
/// The measurement (real AI requests; the key is read from the local .env
/// file and never printed). Always with --dry-run first:
///
///   dart run tools/gap_eval/final_matching.dart --set `the untouched set` \
///     --out `a new run folder` --dry-run
///
/// Options:
///   --set `folder`           the set whose label and role files are read.
///                            Required when the freeze says the writers'
///                            names are used, refused when it says they are
///                            not: no set file is then read and no request
///                            is sent for a writers' name.
///   --out `folder`           the run folder. Required: there is no
///                            default, so an earlier run's folder is never
///                            written by mistake. The tool writes run.json
///                            into it first and refuses a folder that holds
///                            another run's files, and any folder inside
///                            build/gap_eval/final_r2.
///   --market-runs `n`        market lists per decision goal (default: the
///                            frozen number, 8)
///   --writer-link-runs `n`   link answers per request of writers' names
///                            (default: the frozen number, 3)
///   --limit `n`              send at most n market requests and n link
///                            requests (the smoke test)
///   --concurrency `n`        requests at the same time (default 3)
///   --freeze-file `file`     default tools/gap_eval/freeze_r2.json
///   --dry-run                print what would be read and sent, with the
///                            estimate; send nothing
///   --rehearsal              for a development set only: reads its label
///                            and role files to show that the reader works.
///                            It needs --dry-run, skips the freeze check
///                            and writes nothing.
///
/// A stored answer is never requested again, so a run that stopped is
/// continued by the same command. The tool stops at the first billing or
/// credit error, without a retry.
Future<void> main(List<String> arguments) async {
  final args = Args(arguments, known: const {
    '--candidates', '--concurrency', '--dry-run', '--earlier-grades',
    '--freeze-check', '--freeze-file', '--grace-source', '--limit',
    '--link-grace-seconds', '--market-runs', '--out', '--persona-links',
    '--persona-precision', '--persona-tolerance', '--precision-source',
    '--rehearsal', '--requests', '--set', '--tolerance-source',
    '--write-freeze', '--writer-link-runs', '--writer-names',
    '--writer-source',
  });
  final freezeFile = args.value('--freeze-file') ?? defaultFreezeFile;

  if (args.has('--write-freeze')) return _writeFreeze(args, freezeFile);
  if (args.has('--freeze-check')) {
    checkFreeze(freezeFile);
    stdout.writeln('The freeze matches ($freezeFile).');
    final amended = amendmentLine(freezeFile);
    if (amended != null) stdout.writeln(amended);
    return;
  }

  final dryRun = args.has('--dry-run');
  final rehearsal = args.has('--rehearsal');
  if (rehearsal && !dryRun) fail('--rehearsal needs --dry-run.');
  for (final flag in const [
    '--writer-names', '--writer-source', '--earlier-grades',
    '--persona-precision', '--precision-source', '--link-grace-seconds',
    '--grace-source',
  ]) {
    if (args.has(flag)) fail('$flag belongs to --write-freeze.');
  }

  Map<String, dynamic> frozen;
  if (rehearsal) {
    stdout.writeln('REHEARSAL on a development set: nothing is requested, '
        'nothing is written, the freeze is not checked.');
    frozen = {
      'requests': args.list('--requests').isEmpty
          ? ['typed']
          : args.list('--requests'),
      'marketRuns': frozenMarketRuns,
      'writerLinkRuns': frozenWriterLinkRuns,
      'writerNames': {'use': true},
    };
  } else {
    frozen = checkFreeze(freezeFile);
    stdout.writeln('The freeze matches ($freezeFile).');
    final amended = amendmentLine(freezeFile);
    if (amended != null) stdout.writeln(amended);
  }
  // Whether the writers' names of the set are decision names is frozen.
  // When they are not, no file of the set is read at all.
  final useWriters = frozenWriterNames(frozen);
  if (!useWriters && args.has('--set')) {
    fail('The freeze says the writers\' names are not used: --set is '
        'refused and no file of the set is read.');
  }
  final setPath = !useWriters
      ? null
      : (args.value('--set') ?? fail('Pass --set <folder>.'))
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'/+$'), '');
  if (rehearsal && setPath!.split('/').contains('final_set')) {
    fail('A rehearsal reads a development set, never the untouched set.');
  }
  // A rehearsal writes nothing and reads no stored answer; its folder name
  // only has to be one that no run uses.
  final outPath = rehearsal
      ? (args.value('--out') ?? 'build/gap_eval/rehearsal_writes_nothing')
      : (args.value('--out') ??
          fail('Pass --out <a new run folder>. There is no default, so the '
              'folder of an earlier run is never written by mistake.'));
  final run = RunFolder(outPath);
  final earlierRun = earlierRunWriteProblem(outPath);
  if (earlierRun != null) fail('$earlierRun Nothing was requested.');
  if (!rehearsal) {
    final freezeSha = freezeShaOf(freezeFile);
    final problem = runFolderProblem(run.path, freezeSha);
    if (problem != null) fail('$problem Nothing was requested.');
    if (!dryRun && !File(runMarkerPath(run.path)).existsSync()) {
      writeJson(runMarkerPath(run.path), {
        'tool': 'final_matching.dart',
        'freezeFile': freezeFile,
        'freezeSha256': freezeSha,
        'writerNames': useWriters,
      });
    }
  }
  final requests = [
    for (final id in frozen['requests'] as List) linkRequestOf(id.toString()),
  ];
  final marketRuns = args.integer('--market-runs', frozen['marketRuns'] as int);
  final writerRuns =
      args.integer('--writer-link-runs', frozen['writerLinkRuns'] as int);
  if (!rehearsal &&
      (marketRuns != frozen['marketRuns'] ||
          writerRuns != frozen['writerLinkRuns'])) {
    fail('The number of runs is frozen: ${frozen['marketRuns']} market '
        'lists per goal and ${frozen['writerLinkRuns']} link answers per '
        'request of writers\' names.');
  }
  final limit = args.integer('--limit', 0);
  final concurrency = args.integer('--concurrency', 3);

  // ---- the files of the set -------------------------------------------
  final hashes = setPath == null ? const <String, String>{} : _fileHashes(setPath);
  stdout.writeln(setPath == null
      ? 'Set: not read (the freeze says the writers\' names are not used).'
      : 'Set: ${hashes.length} files.');
  if (!dryRun && setPath != null) {
    final hashPath = '${run.path}/set_file_hashes.json';
    if (File(hashPath).existsSync()) {
      final before = readJson(hashPath);
      if (before.toString() != hashes.toString()) {
        fail('The files of the set changed since this run started '
            '($hashPath). Nothing was requested.');
      }
    } else {
      writeJson(hashPath, hashes);
    }
  }

  // ---- stratum W: the writers' names ----------------------------------
  final excluded = _excludedKeys();
  bool isExcluded(String name) => exclusionKeys(name).any(excluded.contains);
  final opportunities = loadOpportunities();
  final certifications = loadCertifications();
  final index = OpportunityIndex.of(opportunities);
  final certificationSkills = {for (final c in certifications) ...c.skills};
  bool opportunityHole(String name) => !index.anyTagCovers(name);
  bool certificationHole(String name) =>
      !certificationSkills.any((skill) => SkillMatcher.matches(name, skill));

  final writers =
      setPath == null ? <String, List<String>>{} : writerNamesOf(setPath);
  stdout.writeln('');
  stdout.writeln('WRITERS\' NAMES (stratum W), as the files give them');
  if (setPath == null) {
    stdout.writeln('  Not used (frozen): stratum W is empty, no request is '
        'sent for a writers\' name, and the decision rests on the market '
        'names alone.');
  } else if (writers.isEmpty) {
    stdout.writeln('  The set has no label or role file with skill names: '
        'stratum W is empty and the decision rests on the market names '
        'alone.');
  }
  for (final goal in writers.keys.toList()..sort()) {
    stdout.writeln('  ${goal.padRight(38)} ${writers[goal]!.length} names'
        '${promptExampleGoals.contains(goal) ? '   (left out: the prompt examples come from this goal)' : ''}');
  }
  for (final goal in promptExampleGoals) {
    writers.remove(goal);
  }
  if (!dryRun && setPath != null) {
    writeJson('${run.path}/raw/writer_names.json', writers);
  }

  // ---- stratum M: the market lists of the decision goals --------------
  final meter = UsageMeter();
  final names = loadCatalogueNames(opportunities, certifications);
  final requester = LinkRequester(meter: meter, names: names);
  final jobsCsv = readText(jobsPath);
  final careerNames = loadCareerNames();
  final marketTexts = <String, String>{};
  final postings = <String, int>{};
  stdout.writeln('');
  stdout.writeln('DECISION GOALS (stratum M), postings sent to the market '
      'step');
  for (final goal in decisionGoals) {
    final jobs =
        JobPostings.relevant(jobsCsv, goal, limit: JobPostings.analysisLimit);
    postings[goal] = jobs.length;
    stdout.writeln('  ${goal.padRight(38)} ${jobs.length} postings'
        '${jobs.isEmpty ? '   (dropped: no postings)' : ''}');
    if (jobs.isNotEmpty) marketTexts[goal] = JobPostings.marketText(jobs);
  }
  if (rehearsal) {
    // A development run never touches a decision goal, not even to count
    // tokens of its market request beyond the posting text above.
    marketTexts.clear();
  }

  final marketTodo = <({String goal, int r})>[
    for (final goal in marketTexts.keys)
      for (var r = 1; r <= marketRuns; r++)
        if (run.market(goal, 'E1', r) == null) (goal: goal, r: r),
  ];
  final marketBatch = limit > 0 && marketTodo.length > limit
      ? marketTodo.sublist(0, limit)
      : marketTodo;
  stdout.writeln('');
  // The factor measured on the link prompts is used here too, to stay on
  // the safe side: the market prompt's own factor has not been measured.
  printEstimate(
    'Market requests to send now (${marketTodo.length} missing)',
    [
      for (final item in marketBatch)
        (
          input: ((roughTokens(marketTexts[item.goal]!) + 700) *
                  LinkRequester.inputFactor)
              .ceil(),
          output: (500 * LinkRequester.outputFactor).ceil(),
        ),
    ],
  );

  CreditStop? stop;
  if (!dryRun && marketBatch.isNotEmpty) {
    final ai = newAi(meter: meter);
    final pipeline = CareerAnalysisPipeline(
      ai,
      settings: const AnalysisSettings(singleSkillNames: true),
      names: names,
    );
    await runPool(
      [
        for (final item in marketBatch)
          () async {
            if (stop != null) return;
            for (var attempt = 1; attempt <= 2; attempt++) {
              try {
                final raw = await ai.extractMarketSkills(
                  careerName: careerNames[item.goal]!,
                  jobMarketText: marketTexts[item.goal]!,
                  singleSkillNames: true,
                );
                writeJson(run.marketPath(item.goal, 'E1', item.r), {
                  'goal': item.goal,
                  'extractor': 'E1',
                  'run': item.r,
                  'postings': postings[item.goal],
                  'rawNames': raw,
                  'names': pipeline.cleanMarketSkills(raw),
                });
                return;
              } on CreditStop catch (error) {
                stop = error;
                return;
              } catch (_) {
                if (meter.stopped != null) {
                  stop = meter.stopped;
                  return;
                }
              }
            }
          },
      ],
      concurrency: concurrency,
      onProgress: (done, total) {
        if (done % 8 == 0 || done == total) stdout.writeln('  $done/$total');
      },
    );
    stdout.writeln('Market requests sent so far: ${meter.summary}.');
    if (stop != null) {
      stdout.writeln('$stop. Nothing more was sent.');
      exit(2);
    }
  }

  // ---- size report -----------------------------------------------------
  // goal -> normalized name -> spelling, market names first, so a writers'
  // name that is also a market name of the goal counts once, as M.
  final market = <String, Map<String, String>>{};
  for (final goal in marketTexts.keys) {
    for (final r in run.marketRuns(goal, 'E1')) {
      for (final name in run.market(goal, 'E1', r) ?? const <String>[]) {
        final key = keyOf(name);
        if (key.isNotEmpty) (market[goal] ??= {}).putIfAbsent(key, () => name);
      }
    }
  }
  final writerHoles = <String, List<String>>{};
  var seenInDevelopment = 0;
  final count = {'M': [0, 0, 0], 'W': [0, 0, 0]};
  void counted(String stratum, String name) {
    final o = opportunityHole(name), c = certificationHole(name);
    count[stratum]![0]++;
    if (o) count[stratum]![1]++;
    if (c) count[stratum]![2]++;
  }

  for (final entry in market.entries) {
    for (final name in entry.value.values) {
      if (!opportunityHole(name) && !certificationHole(name)) continue;
      if (isExcluded(name)) {
        seenInDevelopment++;
        continue;
      }
      counted('M', name);
    }
  }
  for (final goal in writers.keys.toList()..sort()) {
    final seen = <String>{};
    for (final name in writers[goal]!) {
      final key = keyOf(name);
      if (key.isEmpty || !seen.add(key)) continue;
      if (market[goal]?.containsKey(key) ?? false) continue;
      if (!opportunityHole(name) && !certificationHole(name)) continue;
      if (isExcluded(name)) {
        seenInDevelopment++;
        continue;
      }
      counted('W', name);
      (writerHoles[goal] ??= []).add(name);
    }
  }
  final total = count['M']![0] + count['W']![0];
  stdout.writeln('');
  stdout.writeln('SIZE REPORT (decision hole names, after the exclusion '
      'list; $seenInDevelopment hole names left out as seen in development)');
  for (final stratum in const ['M', 'W']) {
    final c = count[stratum]!;
    stdout.writeln('  ${stratum == 'M' ? 'market names (M)  ' : 'writers\' names (W)'}'
        ' ${c[0].toString().padLeft(4)} names: ${c[1]} holes for '
        'opportunities, ${c[2]} for certifications');
  }
  stdout.writeln('  together            ${total.toString().padLeft(4)} names'
      '${total < 40 ? '   SMALL SAMPLE (fewer than 40): the report gives every interval; the decision rule applies as written, and no names, runs or goals are added.' : ''}'
      '${total > maxDecisionNames ? '   More than $maxDecisionNames: evaluate_matching.dart draws $maxDecisionNames by (stratum, goal) with --max-names $maxDecisionNames --seed ${seeds['sample']}.' : ''}');
  if (marketTodo.length > marketBatch.length || (dryRun && !rehearsal)) {
    stdout.writeln('  (Market lists are still missing, so the market names '
        'above are not complete yet.)');
  }

  // ---- link requests ---------------------------------------------------
  final linkTodo = <({
    String goal,
    String list,
    int r,
    LinkRequest request,
    List<String> skills
  })>[];
  for (final request in requests) {
    for (final goal in marketTexts.keys) {
      for (final r in run.marketRuns(goal, 'E1')) {
        final skills = run.market(goal, 'E1', r) ?? const <String>[];
        if (skills.isEmpty) continue;
        if (File(run.linksPath(goal, 'E1', r, request: request)).existsSync()) {
          continue;
        }
        linkTodo.add(
            (goal: goal, list: 'E1', r: r, request: request, skills: skills));
      }
    }
    for (final goal in writerHoles.keys.toList()..sort()) {
      final holes = writerHoles[goal]!;
      for (var start = 0, n = 1; start < holes.length; start += writerChunk, n++) {
        final skills = holes.sublist(
            start,
            start + writerChunk > holes.length
                ? holes.length
                : start + writerChunk);
        for (var r = 1; r <= writerRuns; r++) {
          if (File(run.linksPath(goal, 'W$n', r, request: request))
              .existsSync()) {
            continue;
          }
          linkTodo.add((
            goal: goal,
            list: 'W$n',
            r: r,
            request: request,
            skills: skills
          ));
        }
      }
    }
  }
  final linkBatch = limit > 0 && linkTodo.length > limit
      ? linkTodo.sublist(0, limit)
      : linkTodo;
  stdout.writeln('');
  printEstimate(
    'Link requests to send now (${linkTodo.length} missing; with the '
    'factors the development requests measured)',
    [for (final item in linkBatch) requester.estimate(item.skills, item.request)],
  );
  if (dryRun) {
    if (!rehearsal) {
      stdout.writeln('The link requests of the market lists can only be '
          'counted once those lists exist: expect ${marketTexts.length * marketRuns * requests.length} '
          'more, each about 2,100 input and 900 output tokens.');
    }
    return;
  }
  if (marketTodo.length > marketBatch.length) {
    stdout.writeln('Market lists are still missing (--limit): run the same '
        'command again before the link requests of the full run.');
  }

  await runPool(
    [
      for (final item in linkBatch)
        () async {
          if (stop != null) return;
          try {
            final links = await requester.request(item.skills, item.request);
            if (links == null) return;
            writeJson(
              run.linksPath(item.goal, item.list, item.r, request: item.request),
              {
                'goal': item.goal,
                'list': item.list,
                'run': item.r,
                'request': item.request.name,
                'links': [for (final link in links) link.toMap()],
              },
            );
          } on CreditStop catch (error) {
            stop = error;
          }
        },
    ],
    concurrency: concurrency,
    onProgress: (done, total) {
      if (done % 8 == 0 || done == total) stdout.writeln('  $done/$total');
    },
  );
  stdout.writeln('Sent in this call: ${meter.summary}.');
  if (requester.failed > 0) {
    stdout.writeln('${requester.failed} link requests failed and have no '
        'stored answer; run the same command again to send only those.');
  }
  if (stop != null) {
    stdout.writeln('$stop. Nothing more was sent.');
    exit(2);
  }
  exit(0);
}

// ---------------------------------------------------------
// THE SET
// ---------------------------------------------------------

/// The SHA-256 of every file of the set, by relative path.
Map<String, String> _fileHashes(String folder) {
  final directory = Directory(folder);
  if (!directory.existsSync()) fail('$folder does not exist.');
  final root = directory.absolute.path.replaceAll('\\', '/');
  final result = <String, String>{};
  final files = directory.listSync(recursive: true).whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final path = file.absolute.path.replaceAll('\\', '/');
    result[path.substring(root.length + 1)] =
        sha256Hex(file.readAsBytesSync());
  }
  return result;
}

Set<String> _excludedKeys() {
  if (!File(exclusionFile).existsSync()) {
    fail('$exclusionFile is missing: build it with build_dev_names.dart.');
  }
  return {
    for (final line in readText(exclusionFile).split('\n'))
      if (line.trim().isNotEmpty && !line.startsWith('#')) line.trim(),
  };
}

// ---------------------------------------------------------
// FREEZE
// ---------------------------------------------------------

void _writeFreeze(Args args, String freezeFile) {
  final earlierRun = earlierRunWriteProblem(freezeFile);
  if (earlierRun != null) fail(earlierRun);
  // Guard files and run folders carry the hash of the freeze file, so a
  // second freeze would leave them unusable without a word.
  if (FileSystemEntity.typeSync(freezeFile) != FileSystemEntityType.notFound) {
    fail('$freezeFile already exists. A freeze is written once: the guard '
        'files and the run folder carry its hash. Nothing was written.');
  }
  final candidates = args.list('--candidates');
  if (candidates.isEmpty) fail('Pass --candidates <approach ids>.');
  // Every id must be one the evaluation knows, and one that can be chosen.
  for (final id in candidates) {
    final approach = Approach.parse(id);
    if (approach.id == Approach.appId || isControl(approach)) {
      fail('$id is not a candidate: it is a control or the check of the '
          'shipped code.');
    }
  }
  final requests = args.list('--requests');
  if (requests.isEmpty) fail('Pass --requests names and/or typed.');
  requests.forEach(linkRequestOf);
  final decided = freezeSettings(
    precision: args.value('--persona-precision') ?? 'full',
    precisionSource: args.value('--precision-source') ?? '',
    tolerance: args.value('--persona-tolerance') ?? '0',
    toleranceSource: args.value('--tolerance-source') ?? '',
    graceSeconds: args.value('--link-grace-seconds'),
    graceSource: args.value('--grace-source') ?? '',
    writerNames: args.value('--writer-names'),
    writerSource: args.value('--writer-source') ?? '',
    earlierGrades: args.value('--earlier-grades'),
    personaLinks: args.list('--persona-links'),
  );
  final settings = decided.settings ?? fail(decided.problem!);
  final freeze = {
    'candidates': candidates,
    'requests': requests,
    'decisionGoals': decisionGoals,
    'promptExampleGoals': promptExampleGoals,
    'marketRuns': frozenMarketRuns,
    'writerLinkRuns': frozenWriterLinkRuns,
    'writerNamesPerRequest': writerChunk,
    'maxDecisionNames': maxDecisionNames,
    'seeds': seeds,
    ...settings,
    'hashes': hashesNow(frozenList(settings, 'personaLinks')),
  };
  writeJson(freezeFile, freeze);
  stdout.writeln('Freeze written to $freezeFile');
  final guard = settings['personaGuard'] as Map;
  stdout.writeln('  persona guard            precision ${guard['precision']}, '
      'tolerance ${guard['tolerance']}');
  stdout.writeln('  link grace               '
      '${(settings['linkGrace'] as Map)['seconds']} s');
  stdout.writeln('  writers\' names           '
      '${frozenWriterNames(settings) ? 'on' : 'off'}');
  (freeze['hashes'] as Map).forEach((name, hash) {
    stdout.writeln('  ${name.toString().padRight(24)} $hash');
  });
}
