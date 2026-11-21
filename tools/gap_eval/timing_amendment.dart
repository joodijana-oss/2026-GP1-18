import 'dart:async' show FutureExtensions;
import 'dart:convert';
import 'dart:io';

import 'approaches.dart';
import 'decision_rules.dart';
import 'eval_support.dart';
import 'freeze_r2.dart';

/// The timing amendment of rule 7.2 (d) of the final matching measurement
/// (amendment 1): the timing guard is measured once more, as the median of
/// 5 separate runs per persona file, and compared with the same limits at
/// full precision. The persona part of the guards stays as it was run.
///
/// Three modes, from the project root. None sends a request, and none
/// reads `.env`.
///
/// Write the amendment, once (it records the user's decision, the guard
/// files whose persona part stands, and the hash of the amended tools):
///
///   dart run tools/gap_eval/timing_amendment.dart --write-amendment \
///     --guards `dev.json`,`heldout.json` --source-file `file` [--dry-run]
///
/// Measure the timing of one persona file, once (the development file
/// first, the held-out file only after a usable development result). It
/// runs evaluate_recommender.dart 5 times, each in its own process and
/// folder, one after another, and writes one timing file:
///
///   dart run tools/gap_eval/timing_amendment.dart --measure \
///     --personas `frozen persona file` [--dry-run]
///
/// The verdict the decision will read, without writing anything (exit code
/// 0: PASS, 2: FAIL, 1: NOT USABLE):
///
///   dart run tools/gap_eval/timing_amendment.dart --check
///
/// Options:
///   --freeze-file `file`   default tools/gap_eval/freeze_r2.json; the
///                          amendment lies next to it
///   --dry-run              with --write-amendment or --measure: every
///                          check, and what would be written or run;
///                          nothing is created and nothing is run
Future<void> main(List<String> arguments) async {
  final args = Args(arguments, known: const {
    '--check', '--dry-run', '--freeze-file', '--guards', '--measure',
    '--personas', '--source-file', '--write-amendment',
  });
  final freezeFile = args.value('--freeze-file') ?? defaultFreezeFile;
  final modes = [
    for (final mode in const ['--write-amendment', '--measure', '--check'])
      if (args.has(mode)) mode,
  ];
  if (modes.length != 1) {
    fail('Pass exactly one of --write-amendment, --measure and --check.');
  }
  void only(String mode, List<String> flags) {
    for (final flag in flags) {
      if (args.has(flag) && modes.single != mode) {
        fail('$flag belongs to $mode.');
      }
    }
  }

  only('--write-amendment', const ['--guards', '--source-file']);
  only('--measure', const ['--personas']);
  if (modes.single == '--check' && args.has('--dry-run')) {
    fail('--check writes nothing: --dry-run is not needed.');
  }
  if (!File('pubspec.yaml').existsSync() || !File(freezeFile).existsSync()) {
    fail('Run this from the project root, where pubspec.yaml and the freeze '
        'file ($freezeFile) are.');
  }

  switch (modes.single) {
    case '--write-amendment':
      _writeAmendment(args, freezeFile);
    case '--measure':
      await _measure(args, freezeFile);
    default:
      _check(freezeFile);
  }
}

// ---------------------------------------------------------
// THE AMENDMENT
// ---------------------------------------------------------

/// The amendment of the freeze [frozen] (the file [freezeFile] with the
/// hash [freezeSha]): the amended rule, the user's decision ([source]),
/// the guard files whose persona part stands ([guards]: path -> content,
/// one per frozen persona file), where the timing files go, and the hash
/// of the amended tools of tools/gap_eval ([amendedTools]) next to the
/// frozen one.
Map<String, dynamic> amendmentOf({
  required Map<String, dynamic> frozen,
  required String freezeFile,
  required String freezeSha,
  required Map<String, Map<String, dynamic>> guards,
  required String source,
  required String amendedTools,
}) {
  final candidates = amendedCandidatesOf(frozen);
  final pathOf = <String, String>{
    for (final entry in guards.entries)
      if (entry.value['personas'] is Map)
        slashes('${(entry.value['personas'] as Map)['path']}'):
            slashes(entry.key),
  };
  final personaFiles = [
    for (final personas in (frozen['personaLinkFor'] as Map).keys)
      if (pathOf.containsKey(personas)) personas.toString(),
  ];
  String folderOf(String path) =>
      path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '.';
  return {
    'amendment': 1,
    'rule': '7.2 (d)',
    'text': amendedTimingRule,
    'source': source.trim(),
    'freezeFile': slashes(freezeFile),
    'freezeSha256': freezeSha,
    'candidate': candidates.isEmpty ? null : candidates.first,
    'runs': amendedTimingRuns,
    'statistic': 'median',
    'warmLimit': warmRatioLimit,
    'firstLimit': firstRatioLimit,
    'comparedAt': 'full precision',
    'toolHashes': {
      'gapEvalTools': {
        'frozen': (frozen['hashes'] as Map)['gapEvalTools'],
        'amended': amendedTools,
      },
    },
    'guardFiles': {
      for (final personas in personaFiles)
        personas: {
          'path': pathOf[personas],
          'sha256': timingShaOf(pathOf[personas]!),
        },
    },
    'timingFiles': {
      for (final personas in personaFiles)
        personas: '${folderOf(pathOf[personas]!)}/'
            'timing_${timingLabels[personas]}.json',
    },
  };
}

void _writeAmendment(Args args, String freezeFile) {
  final dryRun = args.has('--dry-run');
  final amendmentFile = amendmentFileOf(freezeFile);
  final frozen = Map<String, dynamic>.from(readJson(freezeFile) as Map);
  final freezeSha = freezeShaOf(freezeFile);
  final guardPaths = args.list('--guards');
  if (guardPaths.isEmpty) {
    fail('Pass --guards with the guard files whose persona part stands, one '
        'per frozen persona file.');
  }
  final sourceFile = args.value('--source-file') ??
      fail('Pass --source-file with the file that holds the user\'s '
          'decision.');
  final source = readText(sourceFile).trim();
  final guards = <String, Map<String, dynamic>>{};
  for (final path in guardPaths) {
    guards[path] = timingJsonOf(path) ??
        fail('$path is missing or is not a JSON object. Nothing was '
            'written.');
  }
  final problem = amendmentWriteProblem(
    amendmentFile: amendmentFile,
    frozen: frozen,
    freezeSha: freezeSha,
    guards: guards,
    source: source,
  );
  if (problem != null) fail('$problem\nNothing was written.');

  final amendment = amendmentOf(
    frozen: frozen,
    freezeFile: freezeFile,
    freezeSha: freezeSha,
    guards: guards,
    source: source,
    amendedTools:
        '${hashesNow(frozenList(frozen, 'personaLinks'))['gapEvalTools']}',
  );
  // The freeze must match with exactly this amendment, as every tool will
  // check it from now on.
  final differences = freezeDifferences(frozen,
      amendment: amendment, freezeSha: freezeSha, freezeFile: freezeFile);
  if (differences.isNotEmpty) {
    fail('With this amendment the freeze would not match: '
        '${differences.join(', ')}.\nNothing was written.');
  }
  final text = const JsonEncoder.withIndent(' ').convert(amendment);
  stdout.writeln(text);
  if (dryRun) {
    stdout.writeln('DRY RUN: nothing was written. The amendment would go to '
        '$amendmentFile (sha256 ${sha256OfText(text)}).');
    return;
  }
  if (FileSystemEntity.typeSync(amendmentFile) !=
      FileSystemEntityType.notFound) {
    fail('$amendmentFile already exists. The amendment is written once.');
  }
  writeJson(amendmentFile, amendment);
  stdout.writeln('Amendment written to $amendmentFile (sha256 '
      '${amendmentShaOf(freezeFile)}).');
}

// ---------------------------------------------------------
// THE MEASUREMENT
// ---------------------------------------------------------

/// Runs one guard run: the arguments of the Dart executable, and the run's
/// own folder, in which guard.txt already exists. Returns the exit code.
typedef GuardRunner = Future<int> Function(
    List<String> args, String outputFolder);

/// What [measureTiming] did. [refusal]: why nothing was run. [commands]:
/// the arguments of each of the 5 runs. [timingPath] and [file]: the
/// timing file and its content, when the runs were started.
typedef TimingMeasurement = ({
  String? refusal,
  List<List<String>> commands,
  String? links,
  String? timingPath,
  Map<String, dynamic>? file,
});

/// The arguments of run [run] of the persona file [personas]: the guard
/// tool as the guards ran it, with its own folder for the guard file. The
/// persona file, the link file and the freeze file are passed exactly as
/// the freeze writes them, so the run file records the same paths as the
/// recorded guard file.
List<String> timingRunArguments({
  required String personas,
  required Map<String, dynamic> frozen,
  required String freezeFile,
  required Map<String, dynamic> amendment,
  required int run,
}) =>
    [
      'run',
      'tools/recommender_eval/evaluate_recommender.dart',
      '--personas',
      personas,
      '--links',
      '${(frozen['personaLinkFor'] as Map)[personas]}',
      '--approach',
      '${amendment['candidate']}',
      '--guard-precision',
      frozenPrecision(frozen),
      '--guard-json',
      '${timingRunFolderOf(amendedGuardsFolderOf(amendment)!, timingLabels[personas]!, run)}'
          '/guard.json',
      '--freeze-file',
      freezeFile,
    ];

/// The content of a timing file. [runs] holds every run that started, in
/// run order; a run that failed has no ratios. With [amendedTimingRuns]
/// good runs and no [stopReason], the medians decide the status; anything
/// else is "incomplete", which the decision never uses.
Map<String, dynamic> timingFileOf({
  required String personas,
  required Map<String, dynamic> frozen,
  required String freezeFile,
  required String freezeSha,
  required Map<String, dynamic> amendment,
  required String amendmentFile,
  required String amendmentSha,
  required Map<String, dynamic> guard,
  required List<Map<String, dynamic>> runs,
  required String startedAt,
  required String finishedAt,
  String? stopReason,
  bool personaSameAsGuard = true,
}) {
  final links = '${(frozen['personaLinkFor'] as Map)[personas]}';
  final hashes = frozen['hashes'] as Map;
  final recorded = (amendment['guardFiles'] as Map)[personas] as Map;
  List<double> ratios(String field) => [
        for (final run in runs)
          if (run[field] is num) (run[field] as num).toDouble(),
      ];
  final warm = ratios('warmRatio');
  final first = ratios('firstRatio');
  final complete = stopReason == null &&
      runs.length == amendedTimingRuns &&
      warm.length == amendedTimingRuns &&
      first.length == amendedTimingRuns;
  final verdict = complete ? amendedTimingVerdict(warm, first) : null;
  return {
    'kind': timingKind,
    'label': timingLabels[personas],
    'freezeFile': slashes(freezeFile),
    'freezeSha256': freezeSha,
    'amendmentFile': slashes(amendmentFile),
    'amendmentSha256': amendmentSha,
    'approach': amendment['candidate'],
    'source': guard['source'],
    'opportunities': guard['opportunities'],
    'certifications': guard['certifications'],
    'measured': {
      'personas': {
        'path': personas,
        'sha256': hashes[personaHashNames[personas]],
      },
      'links': {'path': links, 'sha256': hashes['personaLinks:$links']},
    },
    'guardFile': {'path': recorded['path'], 'sha256': recorded['sha256']},
    'startedAt': startedAt,
    'finishedAt': finishedAt,
    'runs': runs,
    'warmRatios': warm,
    'firstRatios': first,
    'warmMedian': verdict?.warm,
    'firstMedian': verdict?.first,
    'warmLimit': warmRatioLimit,
    'firstLimit': firstRatioLimit,
    'comparedAt': 'full precision',
    'personaSameAsGuard': personaSameAsGuard,
    'stopReason': complete
        ? null
        : (stopReason ??
            'fewer than $amendedTimingRuns runs gave both ratios'),
    'status': verdict == null
        ? 'incomplete'
        : (verdict.passes ? 'pass' : 'fail'),
  };
}

/// The one timing measurement of the persona file [personas] under the
/// amendment: 5 runs of the guard tool through [run], one after another,
/// each in its own folder below the guards folder, and then the timing
/// file. It is refused, with nothing created and nothing run, when the
/// guards folder holds anything the plan does not expect or when this
/// persona file was measured or started before ([timingMeasureProblem]).
///
/// A run that fails, or whose persona part is not the recorded guard
/// file's, ends the measurement at once: no later run starts, and the
/// timing file is written with the status "incomplete" and the reason. So
/// does a run whose folder is already there, or that [run] cannot start
/// (it throws): that run is listed with exit code -1.
/// With [dryRun] every check is applied and nothing is created or run.
Future<TimingMeasurement> measureTiming({
  required String personas,
  required Map<String, dynamic> frozen,
  required String freezeFile,
  required String freezeSha,
  required Map<String, dynamic> amendment,
  required String amendmentFile,
  required String amendmentSha,
  required GuardRunner run,
  bool dryRun = false,
  void Function(String line)? log,
}) async {
  TimingMeasurement refused(String why) => (
        refusal: why,
        commands: const [],
        links: null,
        timingPath: null,
        file: null,
      );
  final pairs = frozen['personaLinkFor'];
  final label = timingLabels[personas];
  if (pairs is! Map || !pairs.containsKey(personas) || label == null) {
    return refused('$personas is not a frozen persona file.');
  }
  final guards = amendedGuardsFolderOf(amendment);
  if (guards == null) {
    return refused('The amendment does not name the guard files of one '
        'folder.');
  }
  final unexpected = amendedGuardsFolderProblems(guards, amendment);
  if (unexpected.isNotEmpty) {
    return refused('$guards holds what the plan does not expect:\n  '
        '${unexpected.join('\n  ')}\nNothing is run.');
  }
  final problem = timingMeasureProblem(
    personas: personas,
    frozen: frozen,
    freezeSha: freezeSha,
    amendment: amendment,
    amendmentSha: amendmentSha,
  );
  if (problem != null) return refused(problem);
  final recorded = (amendment['guardFiles'] as Map)[personas];
  final guardPath = recorded is Map ? '${recorded['path']}' : '';
  final guard =
      recorded is Map && timingShaOf(guardPath) == '${recorded['sha256']}'
          ? timingJsonOf(guardPath)
          : null;
  if (guard == null) {
    return refused('The recorded guard file of $personas ($guardPath) is '
        'missing or changed. Nothing is run.');
  }
  final candidate = '${amendment['candidate']}';
  final timingPath = '${(amendment['timingFiles'] as Map)[personas]}';
  final commands = [
    for (var number = 1; number <= amendedTimingRuns; number++)
      timingRunArguments(
        personas: personas,
        frozen: frozen,
        freezeFile: freezeFile,
        amendment: amendment,
        run: number,
      ),
  ];
  final links = '${pairs[personas]}';
  if (dryRun) {
    return (
      refusal: null,
      commands: commands,
      links: links,
      timingPath: timingPath,
      file: null,
    );
  }

  String now() => DateTime.now().toIso8601String();
  final startedAt = now();
  final runs = <Map<String, dynamic>>[];
  String? stopReason;
  var personaSame = true;
  for (var number = 1; number <= amendedTimingRuns; number++) {
    final folder = timingRunFolderOf(guards, label, number);
    final runStarted = now();
    // The folder and its guard.txt exist before the process starts, so a
    // measurement that is killed halfway still leaves its trace. Both must
    // be new: a run folder that is already there belongs to another
    // measurement, and this one stops. A runner that throws stops it too.
    // Either way the run is listed with exit code -1 and the timing file
    // is written as incomplete.
    var exit = -1;
    String? notRun;
    if (FileSystemEntity.typeSync(folder) != FileSystemEntityType.notFound) {
      notRun = 'its folder $folder was already there, so another '
          'measurement may be using it';
    } else {
      try {
        Directory(folder).createSync(recursive: true);
        File('$folder/guard.txt').createSync(exclusive: true);
      } catch (error) {
        notRun = 'its folder could not be made as a new folder: '
            '${_oneLine(error)}';
      }
    }
    if (notRun == null) {
      try {
        exit = await run(commands[number - 1], folder);
      } catch (error) {
        notRun = 'it could not be run: ${_oneLine(error)}';
      }
    }
    log?.call(notRun == null
        ? 'run $number of $amendedTimingRuns finished, exit $exit'
        : 'run $number of $amendedTimingRuns did not finish');
    final file = '$folder/guard.json';
    final content = notRun == null ? timingJsonOf(file) : null;
    final check = notRun != null
        ? (problem: notRun, personaDiffers: false)
        : exit != 0
            ? (problem: 'it ended with exit code $exit', personaDiffers: false)
            : timingRunCheck(content,
                guard: guard,
                frozen: frozen,
                freezeSha: freezeSha,
                candidate: candidate);
    runs.add({
      'run': number,
      'file': file,
      // A run that did not finish has no file of its own to hash: the
      // folder may be another measurement's, still being written.
      'sha256': notRun == null ? timingShaOf(file) : null,
      'output': '$folder/guard.txt',
      'exitCode': exit,
      if (check.problem == null) ...{
        'warmRatio': content!['warmRatio'],
        'firstRatio': content['firstRatio'],
      } else
        'stopReason': check.problem,
      'startedAt': runStarted,
      'finishedAt': now(),
    });
    if (check.problem != null) {
      stopReason = 'run $number: ${check.problem}';
      personaSame = !check.personaDiffers;
      break;
    }
  }

  final file = timingFileOf(
    personas: personas,
    frozen: frozen,
    freezeFile: freezeFile,
    freezeSha: freezeSha,
    amendment: amendment,
    amendmentFile: amendmentFile,
    amendmentSha: amendmentSha,
    guard: guard,
    runs: runs,
    startedAt: startedAt,
    finishedAt: now(),
    stopReason: stopReason,
    personaSameAsGuard: personaSame,
  );
  // Written once: never over a file that appeared in the meantime.
  if (FileSystemEntity.typeSync(timingPath) != FileSystemEntityType.notFound) {
    return (
      refusal: '$timingPath appeared while the runs were measured. It was '
          'not written again.',
      commands: commands,
      links: links,
      timingPath: timingPath,
      file: file,
    );
  }
  writeJson(timingPath, file);
  return (
    refusal: null,
    commands: commands,
    links: links,
    timingPath: timingPath,
    file: file,
  );
}

/// The real runner: one process of the Dart executable this tool runs
/// with, started without a shell from the project root. Its standard
/// output and its errors are drained at the same time into guard.txt and
/// guard.err.txt of [outputFolder], so a full pipe can never block it; an
/// empty guard.err.txt is not kept.
Future<int> runGuardProcess(List<String> args, String outputFolder) async {
  final output = File('$outputFolder/guard.txt').openWrite();
  final errors = File('$outputFolder/guard.err.txt').openWrite();
  void dropEmptyErrors() {
    final errorFile = File('$outputFolder/guard.err.txt');
    if (errorFile.existsSync() && errorFile.lengthSync() == 0) {
      errorFile.deleteSync();
    }
  }

  final Process process;
  try {
    process = await Process.start(
      Platform.resolvedExecutable,
      args,
      workingDirectory: Directory.current.path,
    );
  } catch (_) {
    // Nothing was started: both files are closed before the error goes on
    // to the measurement, which records it.
    await Future.wait<dynamic>([output.close(), errors.close()]);
    dropEmptyErrors();
    rethrow;
  }
  // The guard tool reads nothing from its input.
  process.stdin.close().ignore();
  final done = await Future.wait<dynamic>([
    process.stdout.pipe(output),
    process.stderr.pipe(errors),
    process.exitCode,
  ]);
  dropEmptyErrors();
  return done[2] as int;
}

/// An error as one line, for a stop reason.
String _oneLine(Object error) =>
    '$error'.replaceAll(RegExp(r'\s+'), ' ').trim();

String _four(dynamic value) =>
    value is num ? value.toStringAsFixed(4) : '$value';

/// The lines that show the ratios, the medians, the limits and the verdict
/// of a timing file.
List<String> timingReportLines(Map<String, dynamic> timing) {
  List<dynamic> listOf(String field) =>
      timing[field] is List ? timing[field] as List : const [];
  return [
    '  first-call ratios: ${listOf('firstRatios').map(_four).join(', ')}',
    '  ratios with the index built: '
        '${listOf('warmRatios').map(_four).join(', ')}',
    '  median, first call: ${_four(timing['firstMedian'])} (full precision '
        '${timing['firstMedian']}), limit at most '
        '${firstRatioLimit.toStringAsFixed(2)}',
    '  median, index built: ${_four(timing['warmMedian'])} (full precision '
        '${timing['warmMedian']}), limit at most '
        '${warmRatioLimit.toStringAsFixed(2)}',
    '  status: ${timing['status']}',
  ];
}

Future<void> _measure(Args args, String freezeFile) async {
  final dryRun = args.has('--dry-run');
  final personas = args.value('--personas') ??
      fail('Pass --personas with a frozen persona file.');
  final frozen = checkFreeze(freezeFile);
  final amendment = readAmendment(freezeFile) ??
      fail('The freeze has no amendment of rule 7.2 (d) '
          '(${amendmentFileOf(freezeFile)}). Nothing is measured.');
  stdout.writeln('The freeze matches ($freezeFile).');
  stdout.writeln(amendmentLine(freezeFile));
  final dart = Platform.resolvedExecutable.replaceAll('\\', '/').toLowerCase();
  if (!dart.endsWith('/dart.exe') && !dart.endsWith('/dart')) {
    fail('This tool starts the runs with the Dart executable it runs with, '
        'and that is ${Platform.resolvedExecutable}. Start it with "dart '
        'run". Nothing is measured.');
  }
  if (!File('tools/recommender_eval/evaluate_recommender.dart').existsSync()) {
    fail('tools/recommender_eval/evaluate_recommender.dart is not here. Run '
        'this from the project root.');
  }

  final result = await measureTiming(
    personas: personas,
    frozen: frozen,
    freezeFile: freezeFile,
    freezeSha: freezeShaOf(freezeFile),
    amendment: amendment,
    amendmentFile: amendmentFileOf(freezeFile),
    amendmentSha: amendmentShaOf(freezeFile),
    run: runGuardProcess,
    dryRun: dryRun,
    log: stdout.writeln,
  );
  final file = result.file;
  if (file == null) {
    if (result.refusal != null) fail(result.refusal!);
    stdout.writeln('DRY RUN: nothing is created and nothing is run.');
    stdout.writeln('Persona file: $personas');
    stdout.writeln('Link file: ${result.links}');
    stdout.writeln('The $amendedTimingRuns runs, one after another, from '
        '${Directory.current.path}:');
    for (final command in result.commands) {
      stdout.writeln('  ${Platform.resolvedExecutable} ${command.join(' ')}');
    }
    stdout.writeln('Each run writes guard.json, guard.txt and, when it '
        'prints errors, guard.err.txt into its own folder.');
    stdout.writeln('Timing file: ${result.timingPath}');
    return;
  }

  stdout.writeln('TIMING (rule 7.2 d, amendment 1) of $personas');
  timingReportLines(file).forEach(stdout.writeln);
  stdout.writeln('  persona part the same as the guard file: '
      '${file['personaSameAsGuard'] == true ? 'yes' : 'NO'}');
  if (file['stopReason'] != null) {
    stdout.writeln('  stopped: ${file['stopReason']}');
  }
  if (result.refusal != null) fail(result.refusal!);
  stdout.writeln('Timing file: ${result.timingPath} (sha256 '
      '${timingShaOf(result.timingPath!)}). It is measured once: nothing is '
      'run again.');
  if (file['status'] == 'incomplete') exitCode = 1;
}

// ---------------------------------------------------------
// THE VERDICT
// ---------------------------------------------------------

/// The verdict of the timing files the amendment names, with the checks
/// the decision applies: what the guards folder holds, each timing file
/// ([timingFileProblems]), one fitting file per frozen candidate and
/// persona file ([amendedTimingFor]) and the medians.
///
/// "FAIL" when a usable file fails, whatever the other shows: nothing can
/// then make all four medians pass. Otherwise "NOT USABLE" when a file is
/// missing or unusable, or the folder holds something unexpected.
/// Otherwise "PASS". It writes nothing.
({String verdict, List<String> lines}) amendedTimingCheck({
  required Map<String, dynamic> frozen,
  required String freezeSha,
  required Map<String, dynamic> amendment,
  required String amendmentSha,
}) {
  final lines = <String>[];
  var usable = true;
  var failed = false;
  final guards = amendedGuardsFolderOf(amendment);
  final unexpected = guards == null
      ? ['the amendment does not name the guard files of one folder']
      : amendedGuardsFolderProblems(guards, amendment);
  if (unexpected.isNotEmpty) {
    usable = false;
    lines.add('The guards folder:');
    lines.addAll(unexpected.map((problem) => '  $problem'));
  }
  final named = amendment['timingFiles'] is Map
      ? amendment['timingFiles'] as Map
      : const {};
  final good = <String, Map<String, dynamic>>{};
  for (final personas in (frozen['personaLinkFor'] as Map).keys) {
    final path = named[personas];
    lines.add('$personas ($path):');
    final content = path is String ? timingJsonOf(path) : null;
    if (path is! String || content == null) {
      usable = false;
      lines.add('  NOT USABLE: the timing file is missing or is not a JSON '
          'object');
      continue;
    }
    final problems = timingFileProblems(content,
        path: path,
        frozen: frozen,
        freezeSha: freezeSha,
        amendment: amendment,
        amendmentSha: amendmentSha);
    if (problems.isNotEmpty) {
      usable = false;
      lines.add('  NOT USABLE:');
      lines.addAll(problems.map((problem) => '    $problem'));
      continue;
    }
    good[path] = content;
    final verdict = amendedTimingMediansOf(content)!;
    lines.addAll(timingReportLines(content));
    lines.add('  verdict of this file: ${verdict.passes ? 'pass' : 'FAIL'}');
    if (!verdict.passes) failed = true;
  }
  if (usable) {
    final found = amendedTimingFor(
      [
        for (final id in frozenList(frozen, 'candidates')) Approach.parse(id),
      ],
      good,
      frozen: frozen,
      freezeSha: freezeSha,
      amendment: amendment,
      amendmentSha: amendmentSha,
    );
    if (found.problems.isNotEmpty) {
      usable = false;
      lines.addAll(found.problems.toSet().map((problem) => '  $problem'));
    }
  }
  return (
    verdict: failed ? 'FAIL' : (usable ? 'PASS' : 'NOT USABLE'),
    lines: lines,
  );
}

void _check(String freezeFile) {
  final frozen = checkFreeze(freezeFile);
  final amendment = readAmendment(freezeFile) ??
      fail('The freeze has no amendment of rule 7.2 (d) '
          '(${amendmentFileOf(freezeFile)}).');
  stdout.writeln('The freeze matches ($freezeFile).');
  stdout.writeln(amendmentLine(freezeFile));
  final result = amendedTimingCheck(
    frozen: frozen,
    freezeSha: freezeShaOf(freezeFile),
    amendment: amendment,
    amendmentSha: amendmentShaOf(freezeFile),
  );
  result.lines.forEach(stdout.writeln);
  stdout.writeln('TIMING (rule 7.2 d, amendment 1): ${result.verdict}');
  exitCode = switch (result.verdict) { 'PASS' => 0, 'FAIL' => 2, _ => 1 };
}
