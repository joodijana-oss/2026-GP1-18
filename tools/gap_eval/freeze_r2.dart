import 'dart:convert';
import 'dart:io';

import 'package:masra/services/career_analysis_pipeline.dart';

import 'approaches.dart';
import 'decision_rules.dart'
    show
        amendedTimingMediansOf,
        amendedTimingRuns,
        firstRatioLimit,
        fullCandidateOf,
        guardNumberProblems,
        guardVerdictOf,
        warmRatioLimit;
import 'eval_support.dart';
import 'link_requests.dart';

/// The freeze of the final matching measurement, shared by the tool that
/// sends its requests (final_matching.dart), the tool that runs the persona
/// and timing guards (evaluate_recommender.dart --guard-json) and the tool
/// that scores (evaluate_matching.dart --decision): each checks it before
/// it does anything, so nothing can change between the freeze and the
/// decision.

const String defaultFreezeFile = 'tools/gap_eval/freeze_r2.json';
const String exclusionFile = 'tools/gap_eval/dev_names.txt';
const String decisionRuleFile = 'tools/gap_eval/decision_rule_r2.txt';
const String gradingFile = 'tools/gap_eval/grading_r2.txt';

/// The two persona files of the persona guard, and the name of the hash of
/// each in the freeze.
const String developmentPersonasFile =
    'test/fixtures/opportunity_eval_personas.json';
const String heldOutPersonasFile =
    'test/fixtures/opportunity_eval_personas_heldout.json';
const Map<String, String> personaHashNames = {
  developmentPersonasFile: 'personas',
  heldOutPersonasFile: 'personasHeldOut',
};

/// Fixed by the plan.
const int frozenMarketRuns = 8;
const int frozenWriterLinkRuns = 3;
const int writerChunk = 12;
const int maxDecisionNames = 150;
const Map<String, int> seeds = {
  'sample': 20261121,
  'bootstrap': 20261121,
  'secondRater': 20261122,
  'developmentLowerBound': 20261123,
};

/// Everything that must not change between the freeze and the final
/// measurement, as hashes, next to what the freeze fixes by value.
Map<String, dynamic> hashesNow(List<String> personaLinks) => {
      'services': sha256OfFolder('lib/services'),
      'utils': sha256OfFolder('lib/utils'),
      'models': sha256OfFolder('lib/models'),
      // The tools, the prompt texts of arms/, the exclusion list, the
      // decision rule and the grading instructions.
      'gapEvalTools':
          sha256OfFolder('tools/gap_eval', extensions: const ['.dart', '.txt']),
      'recommenderEvalTools': sha256OfFolder('tools/recommender_eval'),
      'catalogueData': sha256OfFolder('lib/assets/data',
          extensions: const ['.json', '.csv']),
      'exclusionList': sha256OfText(readText(exclusionFile)),
      'decisionRule': sha256OfText(readText(decisionRuleFile)),
      'gradingInstructions': sha256OfText(readText(gradingFile)),
      'personas': sha256OfText(readText(developmentPersonasFile)),
      'personasHeldOut': sha256OfText(readText(heldOutPersonasFile)),
      for (final path in personaLinks)
        'personaLinks:$path': sha256OfText(readText(path)),
    };

String slashes(String path) => path.replaceAll('\\', '/');

/// The hash of the freeze file itself. A guard file and a run folder carry
/// it, so neither can be used with another freeze.
String freezeShaOf(String freezeFile) => sha256OfText(readText(freezeFile));

// ---------------------------------------------------------
// WHAT THE FREEZE FIXES BY VALUE
// ---------------------------------------------------------

/// The settings of the freeze that someone decided: how the persona guard
/// compares (rule 7.2 b), how long the analysis waits for links, whether
/// the writers' names are decision names, and which link file belongs to
/// which persona file. Each decision that is not the written rule needs
/// its source: where the user's own instruction set it.
///
/// Returns the fields to freeze, or the reason they cannot be frozen.
/// [graceInCode] is what the app waits (AnalysisSettings.app.linkGrace).
({Map<String, dynamic>? settings, String? problem}) freezeSettings({
  required String precision,
  String precisionSource = '',
  required String tolerance,
  String toleranceSource = '',
  required String? graceSeconds,
  String graceSource = '',
  required String? writerNames,
  String writerSource = '',
  String? earlierGrades,
  required List<String> personaLinks,
  Duration? graceInCode,
}) {
  ({Map<String, dynamic>? settings, String? problem}) no(String problem) =>
      (settings: null, problem: problem);

  if (precision != 'full' && precision != '3') {
    return no('--persona-precision is full or 3.');
  }
  if (precision == '3' && precisionSource.trim().isEmpty) {
    return no('A comparison at 3 decimals is frozen only with '
        '--precision-source: where the user\'s own instruction set it.');
  }
  if (tolerance != '0' && tolerance != '0.02') {
    return no('--persona-tolerance is 0 or 0.02.');
  }
  if (tolerance == '0.02' && toleranceSource.trim().isEmpty) {
    return no('A tolerance of 0.02 is frozen only with --tolerance-source: '
        'where the user\'s own instruction for this round set it.');
  }

  final inCode = graceInCode ?? AnalysisSettings.app.linkGrace;
  final seconds = int.tryParse(graceSeconds ?? '');
  if (seconds == null) {
    return no('Pass --link-grace-seconds <n>: how long the analysis waits '
        'for links after the gap step.');
  }
  if (Duration(seconds: seconds) != inCode) {
    return no('--link-grace-seconds $seconds is not what the app does: '
        'AnalysisSettings.app.linkGrace is ${inCode.inMilliseconds / 1000} '
        'seconds.');
  }
  if (graceSource.trim().isEmpty) {
    return no('The link grace is frozen only with --grace-source: where the '
        'user\'s own instruction set it.');
  }

  if (writerNames != 'on' && writerNames != 'off') {
    return no('Pass --writer-names on or off: whether the writers\' names '
        'of the final set are decision names.');
  }
  if (writerSource.trim().isEmpty) {
    return no('--writer-names is frozen only with --writer-source: the '
        'user\'s answer, word for word.');
  }
  final useWriters = writerNames == 'on';
  if (earlierGrades != null && !useWriters) {
    return no('--earlier-grades goes in only with --writer-names on.');
  }
  if (earlierGrades == null && useWriters) {
    return no('With --writer-names on, pass --earlier-grades with the sheet '
        'the earlier run graded on the writers\' names: its hash goes into '
        'the freeze, and the report compares with it (report only).');
  }
  if (earlierGrades != null && !File(earlierGrades).existsSync()) {
    return no('File not found: $earlierGrades.');
  }

  if (personaLinks.length != 2) {
    return no('Pass --persona-links with exactly two files: the links of '
        'the development personas first, then those of the held-out '
        'personas.');
  }
  final links = personaLinks.map(slashes).toList();

  return (
    settings: {
      'personaGuard': {
        'precision': precision == '3' ? 3 : 'full',
        'tolerance': tolerance == '0' ? 0 : 0.02,
        'source': [
          if (precision == '3') precisionSource.trim(),
          if (tolerance == '0.02') toleranceSource.trim(),
          if (precision == 'full' && tolerance == '0')
            'round 1 rule: not lower than today (TopGapRank not higher), at '
                'full precision',
        ].join(' '),
      },
      'linkGrace': {'seconds': seconds, 'source': graceSource.trim()},
      'writerNames': {'use': useWriters, 'source': writerSource.trim()},
      if (earlierGrades != null)
        'earlierGrades': {
          'path': slashes(earlierGrades),
          'sha256': sha256OfText(readText(earlierGrades)),
          'use': 'report only',
        },
      'personaLinks': links,
      'personaLinkFor': {
        developmentPersonasFile: links[0],
        heldOutPersonasFile: links[1],
      },
    },
    problem: null,
  );
}

/// What is wrong with the settings of a frozen file, by field name. Empty
/// when they are complete and still what the code does.
List<String> freezeSettingProblems(
  Map<String, dynamic> frozen, {
  Duration? graceInCode,
}) {
  final problems = <String>[];
  bool hasSource(Map map) => '${map['source'] ?? ''}'.trim().isNotEmpty;

  final guard = frozen['personaGuard'];
  if (guard is! Map) {
    problems.add('personaGuard (missing)');
  } else {
    final precision = '${guard['precision']}';
    final tolerance = guard['tolerance'];
    if (precision != 'full' && precision != '3') {
      problems.add('personaGuard.precision');
    }
    if (tolerance != 0 && tolerance != 0.02) {
      problems.add('personaGuard.tolerance');
    }
    if ((precision == '3' || tolerance == 0.02) && !hasSource(guard)) {
      problems.add('personaGuard.source (missing)');
    }
  }

  final grace = frozen['linkGrace'];
  final inCode = graceInCode ?? AnalysisSettings.app.linkGrace;
  if (grace is! Map) {
    problems.add('linkGrace (missing)');
  } else {
    final seconds = grace['seconds'];
    if (seconds is! int || Duration(seconds: seconds) != inCode) {
      problems.add('linkGrace.seconds (the app waits '
          '${inCode.inMilliseconds / 1000} s)');
    }
    if (!hasSource(grace)) problems.add('linkGrace.source (missing)');
  }

  final writers = frozen['writerNames'];
  if (writers is! Map || writers['use'] is! bool) {
    problems.add('writerNames (missing)');
  } else if (!hasSource(writers)) {
    problems.add('writerNames.source (missing)');
  }

  final earlier = frozen['earlierGrades'];
  if (earlier == null && writers is Map && writers['use'] == true) {
    problems.add('earlierGrades (missing; it goes with the writers\' names)');
  }
  if (earlier != null) {
    if (earlier is! Map || earlier['path'] == null) {
      problems.add('earlierGrades');
    } else if (writers is Map && writers['use'] != true) {
      problems.add('earlierGrades (only with the writers\' names)');
    } else {
      final path = earlier['path'].toString();
      if (!File(path).existsSync() ||
          sha256OfText(readText(path)) != '${earlier['sha256']}') {
        problems.add('earlierGrades ($path)');
      }
    }
  }

  final links = frozenList(frozen, 'personaLinks');
  final pairs = frozen['personaLinkFor'];
  if (links.length != 2 ||
      pairs is! Map ||
      pairs.length != 2 ||
      '${pairs[developmentPersonasFile]}' != links[0] ||
      '${pairs[heldOutPersonasFile]}' != links[1]) {
    problems.add('personaLinkFor');
  }
  return problems;
}

/// Everything that changed since the freeze, or that the frozen file lacks.
///
/// With an [amendment] of this freeze (the timing amendment of rule 7.2
/// (d), read from [amendmentFileOf] of [freezeFile]), the tools of
/// tools/gap_eval are compared with the hash the amendment recorded when it
/// was written, because the amendment changed them. Nothing else is
/// substituted: every other hash and field is still compared with the
/// freeze itself, and whatever is wrong with the amendment
/// ([amendmentProblems], with [freezeSha], the hash of the freeze file) is
/// listed as "amendment: ...".
List<String> freezeDifferences(
  Map<String, dynamic> frozen, {
  Duration? graceInCode,
  Map<String, dynamic>? amendment,
  String? freezeSha,
  String freezeFile = defaultFreezeFile,
}) {
  final before = frozen['hashes'] is Map ? frozen['hashes'] as Map : const {};
  final now = hashesNow(frozenList(frozen, 'personaLinks'));
  String expected(Object? key) => amendment != null && key == 'gapEvalTools'
      ? '${amendedToolsHashOf(amendment)}'
      : '${before[key]}';
  return [
    for (final key in {...before.keys, ...now.keys})
      if (expected(key) != '${now[key]}') key.toString(),
    if ('${frozen['decisionGoals']}' != '$decisionGoals') 'decisionGoals',
    if ('${frozen['promptExampleGoals']}' != '$promptExampleGoals')
      'promptExampleGoals',
    if (frozen['marketRuns'] != frozenMarketRuns) 'marketRuns',
    if (frozen['writerLinkRuns'] != frozenWriterLinkRuns) 'writerLinkRuns',
    if ('${frozen['seeds']}' != '$seeds') 'seeds',
    ...freezeSettingProblems(frozen, graceInCode: graceInCode),
    if (amendment != null)
      for (final problem in amendmentProblems(amendment,
          frozen: frozen, freezeSha: freezeSha ?? '', freezeFile: freezeFile))
        'amendment: $problem',
  ];
}

/// Fails when anything changed since the freeze; returns the frozen file.
Map<String, dynamic> checkFreeze(String freezeFile) {
  if (!File(freezeFile).existsSync()) {
    fail('There is no freeze file ($freezeFile). Write it with '
        'final_matching.dart --write-freeze when development is finished.');
  }
  final frozen = Map<String, dynamic>.from(readJson(freezeFile) as Map);
  // The timing amendment of this freeze, when there is one, is checked with
  // it: it says which hash the amended tools of tools/gap_eval have.
  final amendment = readAmendment(freezeFile);
  final differences = freezeDifferences(
    frozen,
    amendment: amendment,
    freezeSha: amendment == null ? null : freezeShaOf(freezeFile),
    freezeFile: freezeFile,
  );
  if (differences.isNotEmpty) {
    fail('The freeze does not match ($freezeFile). Changed since the '
        'freeze, or missing in it: ${differences.join(', ')}.\nNothing was '
        'requested. A change after the freeze means development is not '
        'finished: go back to the development data, then freeze again.');
  }
  return frozen;
}

/// The strings of a list field of the frozen file.
List<String> frozenList(Map<String, dynamic> frozen, String field) => [
      for (final value in frozen[field] is List ? frozen[field] as List : [])
        value.toString(),
    ];

/// How the frozen persona guard compares: [decimals] null is full
/// precision.
({int? decimals, double tolerance}) frozenGuard(Map<String, dynamic> frozen) {
  final guard = frozen['personaGuard'] as Map;
  return (
    decimals: '${guard['precision']}' == '3' ? 3 : null,
    tolerance: (guard['tolerance'] as num).toDouble(),
  );
}

/// The frozen precision as the tools take it on the command line.
String frozenPrecision(Map<String, dynamic> frozen) =>
    frozenGuard(frozen).decimals == null ? 'full' : '3';

/// Whether the writers' names of the final set are decision names.
bool frozenWriterNames(Map<String, dynamic> frozen) =>
    (frozen['writerNames'] as Map)['use'] == true;

// ---------------------------------------------------------
// THE GUARD FILES
// ---------------------------------------------------------

/// What makes a guard file (evaluate_recommender.dart --guard-json)
/// unusable with this freeze, whatever the candidate: it was written under
/// another freeze, at another precision or tolerance, or its persona file
/// and link file are not a frozen pair with the frozen content.
List<String> guardFileProblems(
  Map<String, dynamic> guard, {
  required Map<String, dynamic> frozen,
  required String freezeSha,
}) {
  final problems = <String>[];
  if ('${guard['freezeSha256']}' != freezeSha) {
    problems.add('it was written under another freeze');
  }
  final rule = frozen['personaGuard'] as Map;
  if ('${guard['precision']}' != '${rule['precision']}') {
    problems.add('its precision is ${guard['precision']}, the frozen one is '
        '${rule['precision']}');
  }
  if (guard['tolerance'] != rule['tolerance']) {
    problems.add('its tolerance is ${guard['tolerance']}, the frozen one is '
        '${rule['tolerance']}');
  }
  final personas = guard['personas'] is Map ? guard['personas'] as Map : {};
  final links = guard['links'] is Map ? guard['links'] as Map : {};
  final pairs = frozen['personaLinkFor'] as Map;
  final hashes = frozen['hashes'] as Map;
  final personasPath = slashes('${personas['path']}');
  final linksPath = slashes('${links['path']}');
  if (!pairs.containsKey(personasPath)) {
    problems.add('$personasPath is not a frozen persona file');
  } else {
    if ('${pairs[personasPath]}' != linksPath) {
      problems.add('$linksPath is not the frozen link file of $personasPath '
          '(that is ${pairs[personasPath]})');
    }
    if ('${personas['sha256']}' != '${hashes[personaHashNames[personasPath]]}') {
      problems.add('$personasPath is not the frozen content');
    }
    if ('${links['sha256']}' != '${hashes['personaLinks:$linksPath']}') {
      problems.add('$linksPath is not the frozen content');
    }
  }
  return problems;
}

/// True when [guard] was run with the settings rule 7.2 reads for
/// [candidate]: the same link source and the same opportunity settings,
/// field by field. The persona guard and the timing guard rank
/// opportunities only, so an "-opp" fallback takes the guard runs of its
/// full candidate. A candidate whose certifications use links also needs
/// the certification lists checked with its own certification settings.
bool guardFits(Map<String, dynamic> guard, Approach candidate) =>
    guard['source'] == candidate.source.name &&
    guard['opportunities'] ==
        settingKey(candidate.source, candidate.opportunities) &&
    (!candidate.certifications.enabled ||
        guard['certifications'] ==
            settingKey(candidate.source, candidate.certifications));

/// The guard files of [candidate]: exactly one usable file per frozen
/// persona file, in the frozen order. [guards] maps the path of each file
/// passed with --guards to its content.
({List<Map<String, dynamic>> files, List<String> problems}) guardFilesFor(
  Approach candidate,
  Map<String, Map<String, dynamic>> guards, {
  required Map<String, dynamic> frozen,
  required String freezeSha,
}) {
  final problems = <String>[];
  guards.forEach((path, guard) {
    for (final problem in [
      ...guardFileProblems(guard, frozen: frozen, freezeSha: freezeSha),
      ...guardNumberProblems(guard),
    ]) {
      problems.add('$path: $problem');
    }
  });
  final files = <Map<String, dynamic>>[];
  for (final personas in (frozen['personaLinkFor'] as Map).keys) {
    final fitting = [
      for (final guard in guards.values)
        if (guard['personas'] is Map &&
            slashes('${(guard['personas'] as Map)['path']}') == personas &&
            guardFits(guard, candidate))
          guard,
    ];
    if (fitting.length == 1) {
      files.add(fitting.single);
    } else {
      problems.add('${candidate.id} needs exactly one guard file for '
          '$personas run with its own opportunity settings '
          '(${settingKey(candidate.source, candidate.opportunities)}); '
          '${fitting.length} were passed');
    }
  }
  return (files: files, problems: problems);
}

/// The frozen candidates a guard file of these settings serves
/// ([guardFits]).
List<String> candidatesServedBy(
  Map<String, dynamic> guard,
  Map<String, dynamic> frozen,
) =>
    [
      for (final id in frozenList(frozen, 'candidates'))
        if (guardFits(guard, Approach.parse(id))) id,
    ];

/// Why a guard run of [approach] would be of no use under the freeze
/// [frozen], or null. It must be a frozen candidate. An "-opp" fallback
/// whose full candidate is frozen too is never run itself: it takes the
/// guard runs of its full candidate, which serve both, while a run as the
/// fallback would not serve the full candidate.
String? guardApproachProblem(Approach approach, Map<String, dynamic> frozen) {
  final candidates = frozenList(frozen, 'candidates');
  if (!candidates.contains(approach.id)) {
    return '${approach.id} is not a frozen candidate '
        '(${candidates.join(', ')}): its guard file would serve none of '
        'them.';
  }
  final full = fullCandidateOf(approach.id);
  if (full != null && candidates.contains(full)) {
    return 'Run the guard as $full: the fallback ${approach.id} takes the '
        'guard runs of its full candidate, and a run as ${approach.id} would '
        'not serve $full.';
  }
  return null;
}

// ---------------------------------------------------------
// WHERE FILES MAY BE
// ---------------------------------------------------------

String _absolute(String path) {
  final text = Uri.file(File(path).absolute.path).normalizePath().path;
  final clean = text.replaceFirst(RegExp(r'/+$'), '');
  return Platform.isWindows ? clean.toLowerCase() : clean;
}

/// [path] with forward slashes and no slash at the end.
String _trimmed(String path) => slashes(path).replaceFirst(RegExp(r'/+$'), '');

/// True when [file] lies inside [folder] (at any depth).
bool isInside(String file, String folder) =>
    _absolute(file).startsWith('${_absolute(folder)}/');

/// The folder of the earlier final run. It holds the writers' names and
/// the earlier grades, and it is only ever read.
const String earlierRunFolder = 'build/gap_eval/final_r2';

/// Why nothing may be written to [path], or null: no tool of the final
/// measurement writes into the earlier run's folder, not even into a new
/// sub-folder of it.
String? earlierRunWriteProblem(String path) =>
    _absolute(path) == _absolute(earlierRunFolder) ||
            isInside(path, earlierRunFolder)
        ? '$path lies in $earlierRunFolder, the folder of the earlier final '
            'run, which is only ever read. Use a new folder.'
        : null;

/// Where the guard files of a run lie: the guards folder of its run
/// folder, next to its judgements folder.
String guardsFolderOf(String runFolder) => '${_trimmed(runFolder)}/guards';

/// The persona file of every guard file at the top of [folder], by path.
/// Every .json file there is read: the folder holds the guard files and
/// their printed output only. A .json file that is not a guard file maps
/// to null.
Map<String, String?> guardPersonaFilesIn(String folder) {
  final directory = Directory(folder);
  if (!directory.existsSync()) return const {};
  final files = directory
      .listSync()
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return {
    for (final file in files)
      slashes(file.path): () {
        final decoded = readJson(file.path);
        final personas = decoded is Map && decoded['personas'] is Map
            ? (decoded['personas'] as Map)['path']
            : null;
        return personas == null ? null : slashes('$personas');
      }(),
  };
}

/// The persona files that more than one guard file in [folder] was run on.
List<String> personaFilesGuardedTwice(String folder) {
  final count = <String, int>{};
  for (final personas in guardPersonaFilesIn(folder).values) {
    if (personas != null) count[personas] = (count[personas] ?? 0) + 1;
  }
  return [
    for (final entry in count.entries)
      if (entry.value > 1) entry.key,
  ];
}

/// Why the decision may not use the guard files [paths] for the run in
/// [runFolder], or null. They must lie in the run's guards folder, as
/// graded sheets must lie in its judgements folder. And that folder may
/// hold at most one guard file per persona file: a guard is run once, so
/// a second file for the same persona file means it was run again, and
/// then neither file is used.
String? guardInputProblem(List<String> paths, {required String runFolder}) {
  final folder = guardsFolderOf(runFolder);
  final outside = [
    for (final path in paths)
      if (!isInside(path, folder)) path,
  ];
  if (outside.isNotEmpty) {
    return 'With --decision every guard file must lie in $folder, where the '
        'guards of this run are written. Outside it: ${outside.join(', ')}.';
  }
  final twice = personaFilesGuardedTwice(folder);
  if (twice.isNotEmpty) {
    return '$folder holds more than one guard file for ${twice.join(', ')}. '
        'A guard is run once: a second file means it was run again, and '
        'neither is used.';
  }
  return null;
}

/// Why the decision may not run with these inputs, or null.
///
/// Whether the writers' names are decision names is frozen, so
/// --writer-names is passed exactly when the freeze says so. [runFolder],
/// the first run folder, must be one the measurement started under this
/// freeze: its run.json carries [freezeSha], the hash of the freeze file.
/// And every graded sheet ([sheets]: those of --grades and --second) must
/// lie in its judgements folder: that is where the blind graders of this
/// run write, so a sheet graded for an earlier run, or by someone who had
/// seen the code, cannot be passed in.
String? decisionInputProblem(
  Map<String, dynamic> frozen, {
  required bool writerNames,
  required String runFolder,
  required String freezeSha,
  required List<String> sheets,
}) {
  final frozenUse = frozenWriterNames(frozen);
  if (frozenUse && !writerNames) {
    return 'The freeze says the writers\' names are decision names: pass '
        '--writer-names.';
  }
  if (!frozenUse && writerNames) {
    return 'The freeze says the writers\' names are not used: --writer-names '
        'is refused.';
  }
  final marker = File(runMarkerPath(runFolder));
  if (!marker.existsSync()) {
    return 'With --decision the first run folder must be one that '
        'final_matching.dart started under this freeze: $runFolder has no '
        'run.json.';
  }
  final started = readJson(marker.path);
  if (started is! Map || '${started['freezeSha256']}' != freezeSha) {
    return '$runFolder was started under another freeze (${marker.path}).';
  }
  final judgements = '${_trimmed(runFolder)}/judgements';
  final outside = [
    for (final sheet in sheets)
      if (!isInside(sheet, judgements)) sheet,
  ];
  if (outside.isNotEmpty) {
    return 'With --decision every graded sheet must lie in $judgements, '
        'where the blind graders of this run write. Outside it: '
        '${outside.join(', ')}.';
  }
  return null;
}

/// The marker final_matching.dart writes into its run folder before
/// anything else.
String runMarkerPath(String out) => '${_trimmed(out)}/run.json';

/// Why the measurement may not use [out], or null. A folder that another
/// run started (it holds stored answers, the hashes of a set, a pool or
/// grades, and no marker of this freeze) is never written: its files would
/// be taken for answers of this run. A folder that holds only the guard
/// output and notes of this run is fine. Nothing inside the earlier run's
/// folder is ever written ([earlierRunWriteProblem]).
String? runFolderProblem(String out, String freezeSha) {
  final earlier = earlierRunWriteProblem(out);
  if (earlier != null) return earlier;
  final marker = File(runMarkerPath(out));
  if (marker.existsSync()) {
    final decoded = readJson(marker.path);
    if (decoded is Map && '${decoded['freezeSha256']}' == freezeSha) {
      return null;
    }
    return '$out was started under another freeze (${marker.path}). Use a '
        'new folder.';
  }
  const runData = ['raw', 'review', 'judgements', 'set_file_hashes.json'];
  final found = [
    for (final name in runData)
      if (FileSystemEntity.typeSync('${slashes(out)}/$name') !=
          FileSystemEntityType.notFound)
        name,
  ];
  if (found.isEmpty) return null;
  return '$out already holds the files of another run (${found.join(', ')}) '
      'and was not started by this tool under this freeze. Use a new '
      'folder.';
}

/// Why a guard file of the personas in [personasPath] may not be written
/// to [path] at [precision] ("full" or "3") under the freeze [frozen], or
/// null. A guard is run once: its file is never written again, no second
/// file is written next to it for the same persona file, and it is written
/// at the frozen precision only.
String? guardJsonProblem(
  String path, {
  required String precision,
  required String personasPath,
  required Map<String, dynamic> frozen,
}) {
  final earlier = earlierRunWriteProblem(path);
  if (earlier != null) return earlier;
  final fixed = frozenPrecision(frozen);
  if (precision != fixed) {
    return 'The frozen persona guard compares at precision $fixed: pass '
        '--guard-precision $fixed.';
  }
  if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
    return '$path already exists. A guard is run once and its file is never '
        'written again.';
  }
  final personas = slashes(personasPath);
  final before = [
    for (final entry in guardPersonaFilesIn(File(path).parent.path).entries)
      if (entry.value == personas) entry.key,
  ];
  if (before.isNotEmpty) {
    return '${before.join(', ')} already holds the guard of $personas in '
        'this folder. A guard is run once per persona file.';
  }
  return null;
}

// ---------------------------------------------------------
// THE TIMING AMENDMENT (rule 7.2 d, amendment 1)
// ---------------------------------------------------------

/// The amended text of rule 7.2 (d). It is a constant of the tools, so it
/// is part of the tool hash the amendment records.
const String amendedTimingRule = 'Rule 7.2 (d), amendment 1 (one fixed '
    're-measurement, approved by the user after the development first-call '
    'ratio of B/10/10/bt was 1.1006 against the 1.10 limit). For each '
    'persona file (development and held-out), run the TIMING block of '
    'evaluate_recommender 5 separate times (separate processes, each with '
    'its 21 alternating repetitions, ABBA order), for the frozen candidate '
    'B/10/10/bt (its result serves the -opp fallback too, as before), with '
    'the frozen link file of that persona file. Take the median of the 5 '
    'ratios for each of: first call (limit 1.10) and recommend() with the '
    'index built (limit 2.00), compared at full precision. Pass only if all '
    'four medians (2 files x 2 ratios) are within their limits. Measured '
    'once. No further re-measurement. If it fails, task 4 stops and A0 '
    'stays. The persona guard results already in '
    'build/gap_eval/final_r3/guards/ stay as they are; only the timing part '
    'is replaced by this rule.';

/// The name of each persona file in the timing files and run folders.
const Map<String, String> timingLabels = {
  developmentPersonasFile: 'dev',
  heldOutPersonasFile: 'heldout',
};

/// What a timing file says it is.
const String timingKind = 'timing, rule 7.2 (d), amendment 1';

/// The folder of the separate runs, inside the guards folder, and the only
/// files a run folder may hold.
const String timingRunsFolderName = 'timing_runs';
const List<String> timingRunFileNames = [
  'guard.json',
  'guard.txt',
  'guard.err.txt',
];

/// The fields of a run file that are the timing itself. Every other field
/// is the persona part, which must be the recorded guard file's.
const Set<String> timingFieldsOfRun = {
  'warmRatio',
  'firstRatio',
  'timingPass',
};

Map<String, dynamic> _mapOf(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

String _folderOf(String path) {
  final clean = _trimmed(path);
  final at = clean.lastIndexOf('/');
  return at < 0 ? '.' : clean.substring(0, at);
}

String _nameOf(String path) => _trimmed(path).split('/').last;

String _withTxt(String path) => path.toLowerCase().endsWith('.json')
    ? '${path.substring(0, path.length - 5)}.txt'
    : path;

bool _sameJson(dynamic a, dynamic b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_sameJson(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameJson(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// The object a JSON file holds, or null when the file is missing, cannot
/// be read, or does not hold a JSON object. It never stops the tool.
Map<String, dynamic>? timingJsonOf(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    var text = file.readAsStringSync();
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final decoded = jsonDecode(text);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
}

/// The hash of a file as the freeze hashes text, or null when it is
/// missing.
String? timingShaOf(String path) =>
    File(path).existsSync() ? sha256OfText(readText(path)) : null;

/// Where the amendment of the freeze [freezeFile] lies: next to it. It is
/// a .json file, so it is outside the hash of the tools.
String amendmentFileOf(String freezeFile) {
  final path = slashes(freezeFile);
  final stem = path.toLowerCase().endsWith('.json')
      ? path.substring(0, path.length - 5)
      : path;
  return '${stem}_amendment_timing.json';
}

/// The amendment of the freeze [freezeFile], or null when there is none.
/// A file that is not a JSON object is read as an empty amendment, which
/// [amendmentProblems] refuses.
Map<String, dynamic>? readAmendment(String freezeFile) {
  final path = amendmentFileOf(freezeFile);
  if (!File(path).existsSync()) return null;
  return timingJsonOf(path) ?? <String, dynamic>{};
}

/// The hash of the amendment file of [freezeFile]. A timing file carries
/// it, so it cannot be used with another amendment.
String amendmentShaOf(String freezeFile) =>
    sha256OfText(readText(amendmentFileOf(freezeFile)));

/// The hash of the tools of tools/gap_eval the amendment recorded when it
/// was written, or null when it holds none.
String? amendedToolsHashOf(Map<String, dynamic> amendment) {
  final tools = _mapOf(_mapOf(amendment['toolHashes'])['gapEvalTools']);
  final amended = tools['amended'];
  return amended is String ? amended : null;
}

/// The frozen candidates the guards and the timing are run as: those that
/// are not the fallback of another frozen candidate.
List<String> amendedCandidatesOf(Map<String, dynamic> frozen) => [
      for (final id in frozenList(frozen, 'candidates'))
        if (guardApproachProblem(Approach.parse(id), frozen) == null) id,
    ];

/// The guards folder the amendment's guard files lie in, or null when they
/// are not all in one folder.
String? amendedGuardsFolderOf(Map<String, dynamic> amendment) {
  final folders = <String, String>{};
  for (final entry in _mapOf(amendment['guardFiles']).values) {
    if (entry is! Map || entry['path'] is! String) return null;
    final folder = _folderOf(entry['path'] as String);
    folders[_absolute(folder)] = folder;
  }
  return folders.length == 1 ? folders.values.single : null;
}

/// The folder of run [run] of the persona file with [label], below the
/// guards folder [guards].
String timingRunFolderOf(String guards, String label, int run) =>
    '${_trimmed(guards)}/$timingRunsFolderName/${label}_$run';

/// What is wrong with the amendment of a freeze. Empty when it amends this
/// freeze ([freezeFile] with the hash [freezeSha]), says what the tools
/// do, and its recorded guard files are still the files it recorded.
List<String> amendmentProblems(
  Map<String, dynamic> amendment, {
  required Map<String, dynamic> frozen,
  required String freezeSha,
  String freezeFile = defaultFreezeFile,
}) {
  final problems = <String>[];
  if (amendment['amendment'] != 1) problems.add('amendment is not 1');
  if (amendment['rule'] != '7.2 (d)') problems.add('rule is not 7.2 (d)');
  if (amendment['text'] != amendedTimingRule) {
    problems.add('text is not the amended rule of the tools');
  }
  if ('${amendment['source'] ?? ''}'.trim().isEmpty) {
    problems.add('source (missing)');
  }
  if (amendment['freezeFile'] is! String ||
      slashes(amendment['freezeFile'] as String) != slashes(freezeFile)) {
    problems.add('freezeFile is not $freezeFile');
  }
  if ('${amendment['freezeSha256']}' != freezeSha) {
    problems.add('freezeSha256 is not the hash of the freeze file');
  }
  final candidate = '${amendment['candidate']}';
  if (!frozenList(frozen, 'candidates').contains(candidate)) {
    problems.add('candidate $candidate is not a frozen candidate');
  } else if (!amendedCandidatesOf(frozen).contains(candidate)) {
    problems.add('candidate $candidate is a fallback: the timing is '
        'measured as its full candidate');
  }
  if (amendment['runs'] != amendedTimingRuns) {
    problems.add('runs is not $amendedTimingRuns');
  }
  if (amendment['statistic'] != 'median') {
    problems.add('statistic is not median');
  }
  if (amendment['warmLimit'] != warmRatioLimit) {
    problems.add('warmLimit is not $warmRatioLimit');
  }
  if (amendment['firstLimit'] != firstRatioLimit) {
    problems.add('firstLimit is not $firstRatioLimit');
  }
  if (amendment['comparedAt'] != 'full precision') {
    problems.add('comparedAt is not full precision');
  }

  final tools = _mapOf(_mapOf(amendment['toolHashes'])['gapEvalTools']);
  if ('${tools['frozen']}' != '${_mapOf(frozen['hashes'])['gapEvalTools']}') {
    problems.add('toolHashes.gapEvalTools.frozen is not the hash in the '
        'freeze');
  }
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch('${tools['amended']}')) {
    problems.add('toolHashes.gapEvalTools.amended is not a sha256');
  }

  final personaFiles = _mapOf(frozen['personaLinkFor']).keys.toSet();
  final guardFiles = _mapOf(amendment['guardFiles']);
  if (guardFiles.length != personaFiles.length ||
      !guardFiles.keys.toSet().containsAll(personaFiles)) {
    problems.add('guardFiles does not name exactly the frozen persona files');
  }
  guardFiles.forEach((personas, entry) {
    final recorded = _mapOf(entry);
    final path = recorded['path'];
    if (path is! String) {
      problems.add('guardFiles of $personas has no path');
    } else if (!File(path).existsSync()) {
      problems.add('the recorded guard file $path is missing');
    } else if (timingShaOf(path) != '${recorded['sha256']}') {
      problems.add('the recorded guard file $path changed since the '
          'amendment was written');
    }
  });
  if (guardFiles.isNotEmpty && amendedGuardsFolderOf(amendment) == null) {
    problems.add('the recorded guard files are not in one folder');
  }

  final timingFiles = _mapOf(amendment['timingFiles']);
  if (timingFiles.length != personaFiles.length ||
      !timingFiles.keys.toSet().containsAll(personaFiles)) {
    problems.add('timingFiles does not name exactly the frozen persona '
        'files');
  }
  timingFiles.forEach((personas, value) {
    final guardPath = _mapOf(guardFiles[personas])['path'];
    final label = timingLabels[personas];
    final expected = guardPath is String && label != null
        ? '${_folderOf(guardPath)}/timing_$label.json'
        : null;
    if (expected == null || value != expected) {
      problems.add('timingFiles of $personas is not '
          '${expected ?? 'a file next to its guard file'}');
    }
  });
  return problems;
}

/// The line the tools print after "The freeze matches", or null when the
/// freeze [freezeFile] has no amendment. It is called after [checkFreeze],
/// which has checked the amendment.
String? amendmentLine(String freezeFile) {
  if (readAmendment(freezeFile) == null) return null;
  return 'Amendment 1 of rule 7.2 (d) matches '
      '(${amendmentFileOf(freezeFile)}, sha256 '
      '${amendmentShaOf(freezeFile)}).';
}

/// Why the amendment may not be written to [amendmentFile], or null. It is
/// written once, over a freeze whose only difference is the changed tools
/// of tools/gap_eval, and it names the guard files of the frozen candidate
/// ([guards]: path -> content, one per frozen persona file) whose persona
/// part passed: the amendment replaces the timing part only. [source] is
/// the user's decision, in printable ASCII.
String? amendmentWriteProblem({
  required String amendmentFile,
  required Map<String, dynamic> frozen,
  required String freezeSha,
  required Map<String, Map<String, dynamic>> guards,
  required String source,
  Duration? graceInCode,
}) {
  if (FileSystemEntity.typeSync(amendmentFile) !=
      FileSystemEntityType.notFound) {
    return '$amendmentFile already exists. The amendment is written once.';
  }
  final other = [
    for (final difference
        in freezeDifferences(frozen, graceInCode: graceInCode))
      if (difference != 'gapEvalTools') difference,
  ];
  if (other.isNotEmpty) {
    return 'The freeze does not match apart from the amended tools: '
        '${other.join(', ')}. The amendment excuses only the tools of '
        'tools/gap_eval.';
  }
  final candidates = amendedCandidatesOf(frozen);
  if (candidates.length != 1) {
    return 'The amendment is for one frozen candidate that is not a '
        'fallback; the freeze has ${candidates.length} '
        '(${candidates.join(', ')}).';
  }
  final candidate = Approach.parse(candidates.single);

  for (final entry in guards.entries) {
    final problems = [
      ...guardFileProblems(entry.value, frozen: frozen, freezeSha: freezeSha),
      ...guardNumberProblems(entry.value),
      if (entry.value['approach'] != candidate.id)
        'its approach is ${entry.value['approach']}, not ${candidate.id}',
      if (!guardFits(entry.value, candidate))
        'it was not run with the settings of ${candidate.id}',
    ];
    if (problems.isNotEmpty) {
      return '${entry.key} cannot be recorded: ${problems.join('; ')}.';
    }
  }
  final personaFiles = _mapOf(frozen['personaLinkFor']).keys.toList();
  final files = <Map<String, dynamic>>[];
  for (final personas in personaFiles) {
    final fitting = [
      for (final guard in guards.values)
        if (slashes('${_mapOf(guard['personas'])['path']}') == personas) guard,
    ];
    if (fitting.length != 1) {
      return 'Pass exactly one guard file for $personas; '
          '${fitting.length} were passed.';
    }
    files.add(fitting.single);
  }
  if (guards.length != personaFiles.length) {
    return 'Pass exactly one guard file per frozen persona file '
        '(${personaFiles.length}); ${guards.length} were passed.';
  }
  final rule = frozenGuard(frozen);
  final verdict = guardVerdictOf(files,
      decimals: rule.decimals, tolerance: rule.tolerance);
  if (verdict.personaStatus != 'pass' || !verdict.sameWithoutLinks) {
    return 'The persona part of the guard files does not pass (persona '
        'guard ${verdict.personaStatus}, without links as today '
        '${verdict.sameWithoutLinks ? 'yes' : 'NO'}). The amendment replaces '
        'the timing part only.';
  }
  if (source.trim().isEmpty) {
    return 'The source file is empty: the amendment records the user\'s '
        'decision.';
  }
  if (RegExp(r'[^ -~]').hasMatch(source.trim())) {
    return 'The source must be one line of printable ASCII (the tools and '
        'their records are English only).';
  }
  return null;
}

/// How the fields of a run file differ from the recorded guard file of the
/// same persona file, or null. Every field except the timing itself
/// ([timingFieldsOfRun]) must be equal, and both must have the same
/// fields: the persona part uses stored links, so it is the same on every
/// run unless something changed.
String? timingRunDifference(
  Map<String, dynamic> run,
  Map<String, dynamic> guard,
) {
  final extra = [
    for (final key in run.keys)
      if (!guard.containsKey(key)) key,
  ]..sort();
  if (extra.isNotEmpty) {
    return 'it has fields the guard file does not have: ${extra.join(', ')}';
  }
  final missing = [
    for (final key in guard.keys)
      if (!run.containsKey(key)) key,
  ]..sort();
  if (missing.isNotEmpty) {
    return 'it lacks fields of the guard file: ${missing.join(', ')}';
  }
  final different = [
    for (final key in guard.keys)
      if (!timingFieldsOfRun.contains(key) && !_sameJson(run[key], guard[key]))
        key,
  ];
  return different.isEmpty
      ? null
      : 'its persona part differs from the guard file: '
          '${different.join(', ')}';
}

/// Why the file of one timing run cannot be used, or null. [run] is its
/// content (null: missing or not JSON), [guard] the recorded guard file of
/// its persona file. [personaDiffers] is true when the fault is that its
/// persona part is not the guard file's.
({String? problem, bool personaDiffers}) timingRunCheck(
  Map<String, dynamic>? run, {
  required Map<String, dynamic> guard,
  required Map<String, dynamic> frozen,
  required String freezeSha,
  required String candidate,
}) {
  ({String? problem, bool personaDiffers}) no(String problem) =>
      (problem: problem, personaDiffers: false);
  if (run == null) return no('guard.json is missing or is not JSON');
  final unusable =
      guardFileProblems(run, frozen: frozen, freezeSha: freezeSha);
  if (unusable.isNotEmpty) return no(unusable.join('; '));
  if (run['approach'] != candidate) {
    return no('its approach is ${run['approach']}, not $candidate');
  }
  for (final field in const ['warmRatio', 'firstRatio']) {
    final value = run[field];
    if (value is! num || !value.isFinite) return no('$field is not a number');
  }
  final difference = timingRunDifference(run, guard);
  return (problem: difference, personaDiffers: difference != null);
}

/// What lies under the guards folder [folder], at any depth, that the plan
/// does not expect there: anything but the recorded guard files and the
/// timing files (each with its printed .txt), the folder of the runs, a
/// run folder per label and run number, and in it the three files of a
/// run. It lists names only and reads no file. An expected entry that is
/// absent is no problem here: the timing checks require what must exist.
List<String> amendedGuardsFolderProblems(
  String folder,
  Map<String, dynamic> amendment,
) {
  final directory = Directory(folder);
  if (!directory.existsSync()) return const [];
  final root = _absolute(folder);
  final expected = <String>{};
  void allow(dynamic path) {
    if (path is String) {
      expected.addAll([_absolute(path), _absolute(_withTxt(path))]);
    }
  }

  for (final entry in _mapOf(amendment['guardFiles']).values) {
    allow(_mapOf(entry)['path']);
  }
  _mapOf(amendment['timingFiles']).values.forEach(allow);

  final runsName = timingRunsFolderName.toLowerCase();
  bool isRunFolder(String name) {
    final match = RegExp(r'^(.+)_([0-9]+)$').firstMatch(name);
    if (match == null || !timingLabels.values.contains(match.group(1))) {
      return false;
    }
    final run = int.parse(match.group(2)!);
    return '$run' == match.group(2) && run >= 1 && run <= amendedTimingRuns;
  }

  final problems = <String>[];
  for (final entity
      in directory.listSync(recursive: true, followLinks: false)) {
    final absolute = _absolute(entity.path);
    final parts = absolute.substring(root.length + 1).split('/');
    final isFolder = entity is Directory;
    final isFile = entity is File;
    bool ok;
    if (parts.length == 1) {
      ok = (isFolder && parts[0] == runsName) ||
          (isFile && expected.contains(absolute));
    } else if (parts[0] != runsName || !isRunFolder(parts[1])) {
      ok = false;
    } else if (parts.length == 2) {
      ok = isFolder;
    } else {
      ok = parts.length == 3 &&
          isFile &&
          timingRunFileNames.contains(parts[2]);
    }
    if (!ok) problems.add('${slashes(entity.path)} is not expected there');
  }
  return problems..sort();
}

/// What makes a timing file unusable for the decision. Empty only for a
/// file at [path] that the measurement wrote under this freeze and this
/// amendment, whose 5 runs all finished with the persona part of the
/// recorded guard file, whose run files are still the files it lists, and
/// whose medians and status are what its ratios give.
List<String> timingFileProblems(
  Map<String, dynamic> timing, {
  required String path,
  required Map<String, dynamic> frozen,
  required String freezeSha,
  required Map<String, dynamic> amendment,
  required String amendmentSha,
}) {
  final problems = <String>[];
  final measured = _mapOf(timing['measured']);
  final personasPart = _mapOf(measured['personas']);
  final linksPart = _mapOf(measured['links']);
  final personas = slashes('${personasPart['path']}');
  final pairs = _mapOf(frozen['personaLinkFor']);
  final hashes = _mapOf(frozen['hashes']);
  final label = timingLabels[personas];
  final guards = amendedGuardsFolderOf(amendment);
  if (!pairs.containsKey(personas) || label == null) {
    return ['$personas is not a frozen persona file'];
  }
  if (guards == null) {
    return ['the amendment does not name the guard files of one folder'];
  }

  if (timing['kind'] != timingKind) {
    problems.add('its kind is not "$timingKind"');
  }
  if (timing['label'] != label) problems.add('its label is not $label');
  if ('${timing['freezeSha256']}' != freezeSha) {
    problems.add('it was written under another freeze');
  }
  if ('${timing['amendmentSha256']}' != amendmentSha) {
    problems.add('it was written under another amendment');
  }
  final named = _mapOf(amendment['timingFiles'])[personas];
  if (named is! String || _absolute(path) != _absolute(named)) {
    problems.add('its path is not the one the amendment names for $personas '
        '($named)');
  }
  final frozenLinks = '${pairs[personas]}';
  if (slashes('${linksPart['path']}') != frozenLinks) {
    problems.add('${linksPart['path']} is not the frozen link file of '
        '$personas (that is $frozenLinks)');
  }
  if ('${personasPart['sha256']}' !=
      '${hashes[personaHashNames[personas]]}') {
    problems.add('$personas is not the frozen content');
  }
  if ('${linksPart['sha256']}' != '${hashes['personaLinks:$frozenLinks']}') {
    problems.add('$frozenLinks is not the frozen content');
  }

  final recorded = _mapOf(_mapOf(amendment['guardFiles'])[personas]);
  final recordedPath = '${recorded['path']}';
  final guardPart = _mapOf(timing['guardFile']);
  if (slashes('${guardPart['path']}') != slashes(recordedPath) ||
      '${guardPart['sha256']}' != '${recorded['sha256']}') {
    problems.add('its guardFile is not the guard file the amendment recorded '
        'for $personas');
  }
  final guard = timingShaOf(recordedPath) == '${recorded['sha256']}'
      ? timingJsonOf(recordedPath)
      : null;
  if (guard == null) {
    problems.add('the recorded guard file $recordedPath is missing or '
        'changed');
  }
  final candidate = '${amendment['candidate']}';
  if (timing['approach'] != candidate) {
    problems.add('its approach is ${timing['approach']}, not $candidate');
  }
  if (guard != null) {
    for (final field in const ['source', 'opportunities', 'certifications']) {
      if (timing[field] != guard[field]) {
        problems.add('its $field is not that of the recorded guard file');
      }
    }
  }

  final status = timing['status'];
  if (status == 'incomplete') {
    problems.add('its status is incomplete: the measurement stopped '
        '(${timing['stopReason']})');
  } else if (status != 'pass' && status != 'fail') {
    problems.add('its status is neither pass nor fail');
  } else if (timing['stopReason'] != null) {
    problems.add('it has a stopReason');
  }
  if (timing['personaSameAsGuard'] != true) {
    problems.add('personaSameAsGuard is not true');
  }
  if (timing['warmLimit'] != warmRatioLimit ||
      timing['firstLimit'] != firstRatioLimit) {
    problems.add('its limits are not $warmRatioLimit and $firstRatioLimit');
  }
  if (timing['comparedAt'] != 'full precision') {
    problems.add('comparedAt is not full precision');
  }

  List<dynamic> listOf(String field) =>
      timing[field] is List ? timing[field] as List : const [];
  final runs = listOf('runs');
  final ratioLists = {
    'warmRatio': listOf('warmRatios'),
    'firstRatio': listOf('firstRatios'),
  };
  if (runs.length != amendedTimingRuns) {
    problems.add('it lists ${runs.length} runs, not $amendedTimingRuns');
  }
  for (var i = 0; i < runs.length; i++) {
    final number = i + 1;
    final entry = _mapOf(runs[i]);
    final expectedFile =
        '${timingRunFolderOf(guards, label, number)}/guard.json';
    if (entry['run'] != number) {
      problems.add('run $number is numbered ${entry['run']}');
    }
    if (entry['exitCode'] != 0) {
      problems.add('run $number ended with exit code ${entry['exitCode']}');
    }
    if (entry['file'] is! String ||
        slashes(entry['file'] as String) != expectedFile) {
      problems.add('the file of run $number is not $expectedFile');
      continue;
    }
    final sha = timingShaOf(expectedFile);
    if (sha == null) {
      problems.add('$expectedFile is missing');
      continue;
    }
    if (sha != '${entry['sha256']}') {
      problems.add('$expectedFile changed since the measurement');
    }
    final run = timingJsonOf(expectedFile);
    if (guard != null) {
      final check = timingRunCheck(run,
          guard: guard,
          frozen: frozen,
          freezeSha: freezeSha,
          candidate: candidate);
      if (check.problem != null) {
        problems.add('$expectedFile: ${check.problem}');
      }
    }
    ratioLists.forEach((field, list) {
      final inRun = run?[field];
      if (inRun is! num ||
          entry[field] != inRun ||
          i >= list.length ||
          list[i] != inRun) {
        problems.add('the $field of run $number is not the one in its run '
            'file');
      }
    });
  }

  final runsFolder = '${_trimmed(guards)}/$timingRunsFolderName';
  final found = Directory(runsFolder).existsSync()
      ? ([
          for (final entity in Directory(runsFolder).listSync())
            if (_nameOf(entity.path).startsWith('${label}_'))
              _nameOf(entity.path),
        ]..sort())
      : <String>[];
  final wanted = [
    for (var run = 1; run <= amendedTimingRuns; run++) '${label}_$run',
  ];
  if (found.join(',') != wanted.join(',')) {
    problems.add('$runsFolder holds '
        '${found.isEmpty ? 'no run folder' : found.join(', ')} of $label, '
        'not exactly ${wanted.join(', ')}');
  }

  final verdict = amendedTimingMediansOf(timing);
  if (verdict == null) {
    problems.add('it does not hold $amendedTimingRuns ratios of each kind');
  } else {
    if (timing['warmMedian'] != verdict.warm ||
        timing['firstMedian'] != verdict.first) {
      problems.add('its medians are not the medians of its ratios');
    }
    if ((status == 'pass' || status == 'fail') &&
        status != (verdict.passes ? 'pass' : 'fail')) {
      problems.add('its status is not what its medians give');
    }
  }
  return problems;
}

/// Why the timing of the persona file [personas] may not be measured now,
/// or null. It is measured once: an existing timing file, or a single run
/// folder of this persona file, means it was started before, and then
/// nothing runs again. The held-out file is measured only after the
/// development file gave a usable result (pass or fail).
String? timingMeasureProblem({
  required String personas,
  required Map<String, dynamic> frozen,
  required String freezeSha,
  required Map<String, dynamic> amendment,
  required String amendmentSha,
}) {
  final label = timingLabels[personas];
  final pairs = _mapOf(frozen['personaLinkFor']);
  if (label == null || !pairs.containsKey(personas)) {
    return '$personas is not a frozen persona file '
        '(${pairs.keys.join(', ')}).';
  }
  final guards = amendedGuardsFolderOf(amendment);
  final timingFiles = _mapOf(amendment['timingFiles']);
  final timingFile = timingFiles[personas];
  if (guards == null || timingFile is! String) {
    return 'The amendment does not name the guard files and the timing file '
        'of $personas.';
  }
  if (FileSystemEntity.typeSync(timingFile) !=
      FileSystemEntityType.notFound) {
    return '$timingFile already exists. The timing is measured once: nothing '
        'is run again.';
  }
  final runsFolder = Directory('${_trimmed(guards)}/$timingRunsFolderName');
  if (runsFolder.existsSync()) {
    final started = [
      for (final entity in runsFolder.listSync())
        if (_nameOf(entity.path).startsWith('${label}_')) slashes(entity.path),
    ]..sort();
    if (started.isNotEmpty) {
      return 'A measurement of $personas was started before '
          '(${started.join(', ')}). The timing is measured once: nothing is '
          'run again.';
    }
  }
  if (personas != developmentPersonasFile) {
    final first = timingFiles[developmentPersonasFile];
    if (first is! String || !File(first).existsSync()) {
      return 'The development persona file is measured first: its timing '
          'file ($first) does not exist yet.';
    }
    final content = timingJsonOf(first);
    final problems = content == null
        ? ['it is not a JSON object']
        : timingFileProblems(content,
            path: first,
            frozen: frozen,
            freezeSha: freezeSha,
            amendment: amendment,
            amendmentSha: amendmentSha);
    if (problems.isNotEmpty) {
      return 'The development timing file ($first) holds no usable result: '
          '${problems.join('; ')}. The held-out file is measured only after '
          'one. Nothing is run.';
    }
  }
  return null;
}

/// Why the decision may not use the guard files [paths] under the
/// amendment, or empty: they must be exactly the files the amendment
/// recorded, by path and by content. A run file of the timing measurement
/// can therefore never stand in for one of them.
List<String> amendedGuardProblems(
  List<String> paths,
  Map<String, dynamic> amendment,
) {
  final recorded = <String, Map<String, dynamic>>{
    for (final entry in _mapOf(amendment['guardFiles']).values)
      if (_mapOf(entry)['path'] is String)
        _absolute(_mapOf(entry)['path'] as String): _mapOf(entry),
  };
  final problems = <String>[];
  final passed = <String>{};
  for (final path in paths) {
    final entry = recorded[_absolute(path)];
    if (entry == null) {
      problems.add('$path is not a guard file the amendment recorded');
    } else if (!passed.add(_absolute(path))) {
      problems.add('$path is passed twice');
    } else if (timingShaOf(path) != '${entry['sha256']}') {
      problems.add('$path is missing or changed since the amendment recorded '
          'it');
    }
  }
  for (final entry in recorded.entries) {
    if (!passed.contains(entry.key)) {
      problems.add('${entry.value['path']}, which the amendment recorded, '
          'was not passed');
    }
  }
  return problems;
}

/// The timing files of each of [candidates], by persona file: every file
/// of [timingByPath] (path -> content) must be usable
/// ([timingFileProblems]), and each candidate needs exactly one per frozen
/// persona file that fits it ([guardFits]). So an "-opp" fallback takes
/// the timing files of its full candidate, as it takes its guard files.
({
  Map<String, Map<String, Map<String, dynamic>>> files,
  List<String> problems
}) amendedTimingFor(
  List<Approach> candidates,
  Map<String, Map<String, dynamic>> timingByPath, {
  required Map<String, dynamic> frozen,
  required String freezeSha,
  required Map<String, dynamic> amendment,
  required String amendmentSha,
}) {
  final problems = <String>[];
  timingByPath.forEach((path, timing) {
    for (final problem in timingFileProblems(timing,
        path: path,
        frozen: frozen,
        freezeSha: freezeSha,
        amendment: amendment,
        amendmentSha: amendmentSha)) {
      problems.add('$path: $problem');
    }
  });
  String personasOf(Map<String, dynamic> timing) =>
      slashes('${_mapOf(_mapOf(timing['measured'])['personas'])['path']}');
  final files = <String, Map<String, Map<String, dynamic>>>{};
  for (final candidate in candidates) {
    final own = files[candidate.id] = {};
    for (final personas in _mapOf(frozen['personaLinkFor']).keys) {
      final fitting = [
        for (final timing in timingByPath.values)
          if (personasOf(timing) == personas && guardFits(timing, candidate))
            timing,
      ];
      if (fitting.length == 1) {
        own[personas] = fitting.single;
      } else {
        problems.add('${candidate.id} needs exactly one timing file for '
            '$personas; ${fitting.length} were passed');
      }
    }
  }
  return (files: files, problems: problems);
}

/// Why the decision may not run with these inputs, or null: with an
/// amendment ([amended]) the guards are read together with the timing
/// files it names, and without one there are no timing files.
String? timingInputProblem({
  required bool amended,
  required bool hasGuards,
  required bool hasTiming,
  String amendmentFile = '',
}) {
  if (hasTiming && !amended) {
    return '--timing is read only with the amendment of rule 7.2 (d), and '
        'this freeze has none.';
  }
  if (hasTiming && !hasGuards) {
    return '--timing goes with --guards: the persona part of rule 7.2 comes '
        'from the guard files.';
  }
  if (amended && hasGuards && !hasTiming) {
    return 'Rule 7.2 (d) is amended ($amendmentFile): pass --timing with the '
        'timing files it names.';
  }
  return null;
}
