import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:masra/services/claude_service.dart' show AnalysisAi;

import '../gap_eval/eval_support.dart';
import 'ats_scoring.dart';
import 'ats_support.dart';

/// Compares the ATS review text the app sent before (OLD,
/// old_improve_cv_prompt.txt) with the app's current text (NEW,
/// AnalysisAi.cvImprovementPrompt) on a set of CVs, under blind grading.
///
/// ```text
/// dart run tools/ats_eval/evaluate_ats.dart --set <set.json> --out <folder>
///     [--runs 3] [--versions old,new] [--seed 20261122] [--concurrency 2]
///     [--input-price 2] [--output-price 10] [--dry-run]
/// dart run tools/ats_eval/evaluate_ats.dart --freeze --out <folder>
/// dart run tools/ats_eval/evaluate_ats.dart --score --out <folder>
///     [--report-only]
/// ```
///
/// The set file:
///
/// ```text
/// {"date": "2026-11-22",
///  "cvs": [{"id": "ho_a", "text": "<.txt path>", "goal": "<goal id or
///           name>", "role": "planted"}, ...]}
/// ```
///
/// A relative text path is read from the set file's folder. A CV may carry
/// its own "date". The CV text is sent exactly as the file holds it.
///
/// Every request is sent the way the app sends the review (thinking on,
/// max_tokens 10000, the app's time limit) and parsed by the app's own
/// parsing. The API key is read from `.env` by eval_support and handed to
/// the AI service only; it is never printed or stored. `--dry-run` sends
/// nothing, writes nothing and does not read `.env`.
///
/// Files in the --out folder:
///
/// ```text
/// sealed/mapping.json      labels -> CV, version and run (the grader
///                          never opens sealed/)
/// sealed/raw/*.json        each answer, its tokens and times
/// sealed/failed/*.json     the failures of a slot, status and kind only
/// sealed/run_log.json      every command run with the meter's counts
/// blind/cv_text/<cv>.txt   the exact CV texts sent
/// blind/outputs/<label>.json  the five areas of each output
/// blind/sheet.csv          the grading sheet
/// blind/quotes.csv         every quoted span, "in CV" or "NOT in CV"
/// ```
///
/// The blind files are written once every slot is done, in label order and
/// with one shared file time, so neither the order nor the times tell the
/// versions apart.
const int defaultSeed = 20261122;
const int maxTokens = 10000;

/// A slot that still fails after its retry is tried again on later runs
/// of the command, at most this many more times.
const int extraTries = 3;

/// Output tokens per request for the two cost lines of the plan.
const int typicalOutputTokens = 4000;

Future<void> main(List<String> arguments) async {
  exitCode = await evaluate(arguments);
}

/// Exit code of a run that left failed slots to try again (re-run the same
/// command). 1 is a fatal error and 2 a stop (credit, rate or key error).
const int slotsLeftExitCode = 3;

/// The flags only a run reads.
const List<String> runOnlyFlags = [
  '--concurrency', '--dry-run', '--input-price', '--output-price', '--runs',
  '--seed', '--set', '--versions',
];

/// The command line of the tool; returns the exit code (0 done, 2
/// stopped, [slotsLeftExitCode] slots left to try again; a fatal error
/// exits with 1). [newService] makes the AI service the run sends with;
/// the tool uses the app's service with the key from `.env`, and the tests
/// a service that answers on this machine.
Future<int> evaluate(
  List<String> arguments, {
  AnalysisAi Function(AtsMeter meter)? newService,
}) async {
  final args = Args(arguments, known: const {
    '--concurrency', '--dry-run', '--freeze', '--input-price',
    '--output-price', '--out', '--report-only', '--runs', '--score',
    '--seed', '--set', '--versions',
  });
  final problem = flagProblem(arguments);
  if (problem != null) fail(problem);
  if (args.has('--freeze')) {
    freezeFolder(args.value('--out') ?? fail('Pass --out <folder>.'));
    return 0;
  }
  if (args.has('--score')) {
    scoreFolder(args.value('--out') ?? fail('Pass --out <folder>.'),
        reportOnly: args.has('--report-only'));
    return 0;
  }
  return _run(args, newService ?? (meter) => newAi(meter: meter));
}

/// A flag combination the tool would otherwise silently ignore, or null.
String? flagProblem(List<String> arguments) {
  final freeze = arguments.contains('--freeze');
  final score = arguments.contains('--score');
  if (freeze && score) return 'Pass --freeze or --score, not both.';
  if (arguments.contains('--report-only') && !score) {
    return '--report-only works only with --score.';
  }
  if (freeze || score) {
    for (final flag in runOnlyFlags) {
      if (arguments.contains(flag)) {
        return '$flag works only with a run, not with '
            '${freeze ? '--freeze' : '--score'}.';
      }
    }
  }
  return null;
}

// ---------------------------------------------------------
// THE SET
// ---------------------------------------------------------

class AtsCase {
  AtsCase({
    required this.id,
    required this.textPath,
    required this.cvText,
    required this.goal,
    required this.careerName,
    required this.role,
    required this.date,
  });

  final String id;
  final String textPath;
  final String cvText;
  final String goal;
  final String careerName;
  final String role;
  final String date;
}

final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

List<AtsCase> _loadSet(String path) {
  final decoded = readJson(path);
  if (decoded is! Map || decoded['cvs'] is! List) {
    fail('$path must be an object with a "cvs" list.');
  }
  final folder = File(path).absolute.parent.path;
  final setDate = decoded['date']?.toString();
  final careerNames = loadCareerNames();
  final cases = <AtsCase>[];
  for (final item in decoded['cvs'] as List) {
    if (item is! Map) fail('Every entry of "cvs" must be an object.');
    final id = item['id']?.toString() ?? '';
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(id)) {
      fail('CV id "$id" must use only a-z, 0-9 and _.');
    }
    if (cases.any((c) => c.id == id)) fail('CV id "$id" is listed twice.');
    final role = item['role']?.toString() ?? '';
    if (role != 'planted' && role != 'clean') {
      fail('CV "$id": role must be "planted" or "clean".');
    }
    final date = item['date']?.toString() ?? setDate ?? '';
    if (!_datePattern.hasMatch(date)) {
      fail('CV "$id": the date must be written YYYY-MM-DD, as the app '
          'sends it.');
    }
    final goal = item['goal']?.toString() ?? '';
    if (goal.isEmpty) fail('CV "$id" has no goal.');
    final written = item['text']?.toString() ?? '';
    if (written.isEmpty) fail('CV "$id" has no text path.');
    final textPath =
        File(written).isAbsolute ? written : '$folder/$written';
    final file = File(textPath);
    if (!file.existsSync()) fail('CV "$id": file not found: $textPath');
    var cvText = utf8.decode(file.readAsBytesSync());
    if (cvText.startsWith('﻿')) cvText = cvText.substring(1);
    if (cvText.trim().isEmpty) fail('CV "$id": the text is empty.');
    cases.add(AtsCase(
      id: id,
      textPath: textPath,
      cvText: cvText,
      goal: goal,
      careerName: careerNames[goal] ?? goal,
      role: role,
      date: date,
    ));
  }
  if (cases.isEmpty) fail('$path lists no CVs.');
  return cases;
}

/// The two review texts, checked against the pinned hashes.
({String oldTemplate, String newTemplate}) _templates() {
  final oldTemplate = readText(oldTextPath).replaceAll('\r\n', '\n');
  if (sha256OfText(oldTemplate) != oldTextSha256) {
    fail('$oldTextPath is not the text the app sent before '
        '(sha256 ${sha256OfText(oldTemplate)}, expected $oldTextSha256).');
  }
  final newTemplate = AnalysisAi.cvImprovementPrompt(
    cvText: cvPlaceholder,
    careerName: careerPlaceholder,
    today: todayPlaceholder,
  );
  if (newTemplate == oldTemplate) {
    fail('The app still sends the old review text; there is nothing to '
        'compare.');
  }
  if (sha256OfText(newTemplate) != newTextSha256) {
    fail('The app\'s review text is not the one the decision rule pins '
        '(sha256 ${sha256OfText(newTemplate)}, expected $newTextSha256).');
  }
  return (oldTemplate: oldTemplate, newTemplate: newTemplate);
}

// ---------------------------------------------------------
// RUNNING
// ---------------------------------------------------------

Future<int> _run(
  Args args,
  AnalysisAi Function(AtsMeter meter) newService,
) async {
  final setPath = args.value('--set') ?? fail('Pass --set <set.json>.');
  final dryRun = args.has('--dry-run');
  final out = args.value('--out') ??
      (dryRun ? null : fail('Pass --out <folder>.'));
  final runs = args.integer('--runs', 3);
  if (runs < 1) fail('--runs must be at least 1.');
  final concurrency = args.integer('--concurrency', 2);
  if (concurrency < 1) fail('--concurrency must be at least 1.');
  final seed = args.integer('--seed', defaultSeed);
  final versions =
      args.list('--versions').isEmpty ? knownVersions : args.list('--versions');
  for (final version in versions) {
    if (!knownVersions.contains(version)) {
      fail('Unknown version "$version" (known: ${knownVersions.join(', ')}).');
    }
  }
  if (versions.toSet().length != versions.length) {
    fail('A version is listed twice.');
  }
  double price(String flag, double fallback) {
    final text = args.value(flag);
    if (text == null) return fallback;
    final value = double.tryParse(text);
    if (value == null || value < 0) fail('$flag needs a number.');
    return value;
  }

  final defaults = UsageMeter();
  final inputPrice = price('--input-price', defaults.inputPrice);
  final outputPrice = price('--output-price', defaults.outputPrice);
  defaults.close();

  final cases = _loadSet(setPath);
  final templates = _templates();
  final texts = <String, String>{};
  for (final c in cases) {
    for (final version in versions) {
      final template =
          version == 'old' ? templates.oldTemplate : templates.newTemplate;
      final text = fillReviewText(template,
          careerName: c.careerName, today: c.date, cvText: c.cvText);
      if (version == 'new') {
        final app = AnalysisAi.cvImprovementPrompt(
            cvText: c.cvText, careerName: c.careerName, today: c.date);
        if (app != text) fail('The filled new text differs from the app\'s.');
      }
      texts['${c.id}_$version'] = text;
    }
  }

  // ---- plan ---------------------------------------------------------
  final requests = cases.length * versions.length * runs;
  stdout.writeln('ATS REVIEW EVALUATION');
  stdout.writeln('Set        : $setPath (${cases.length} CVs)');
  for (final c in cases) {
    stdout.writeln('  ${c.id.padRight(12)} ${c.role.padRight(8)} '
        '${c.date}  goal "${c.careerName}"  '
        '${c.cvText.length} chars, ~${roughTokens(c.cvText)} tokens  '
        '${c.textPath}');
  }
  stdout.writeln('Versions   : ${versions.join(', ')}');
  stdout.writeln('Runs       : $runs per CV per version');
  stdout.writeln('Requests   : $requests (thinking on, max_tokens $maxTokens)');
  for (final version in versions) {
    final sizes = [
      for (final c in cases) roughTokens(texts['${c.id}_$version']!),
    ]..sort();
    stdout.writeln('Input      : $version ~${sizes.first}'
        '${sizes.first == sizes.last ? '' : '-${sizes.last}'} '
        'tokens per request');
  }
  var inputTotal = 0;
  for (final c in cases) {
    for (final version in versions) {
      inputTotal += roughTokens(texts['${c.id}_$version']!) * runs;
    }
  }
  double costWith(int outputPerRequest) =>
      (inputTotal * inputPrice + requests * outputPerRequest * outputPrice) /
      1e6;
  stdout.writeln('Prices     : ${inputPrice.toStringAsFixed(2)} / '
      '${outputPrice.toStringAsFixed(2)} USD per million input / output '
      'tokens');
  stdout.writeln('Typical    : about ${costWith(typicalOutputTokens).toStringAsFixed(2)} '
      'USD ($typicalOutputTokens output tokens per request)');
  stdout.writeln('Ceiling    : about ${costWith(maxTokens).toStringAsFixed(2)} '
      'USD ($maxTokens output tokens per request, the max_tokens)');
  stdout.writeln('Old text   : sha256 $oldTextSha256 (checked)');
  stdout.writeln('New text   : sha256 $newTextSha256 (checked, differs from '
      'old)');
  if (dryRun) {
    stdout.writeln('Dry run: nothing sent, nothing written, .env not read.');
    return 0;
  }
  final folder = out!;

  // ---- mapping --------------------------------------------------------
  final slots = assignLabels([for (final c in cases) c.id], versions, runs,
      seed);
  final mapping = <String, Object>{
    'seed': seed,
    'runs': runs,
    'versions': versions,
    'cvs': [
      for (final c in cases)
        {
          'id': c.id,
          'role': c.role,
          'goal': c.goal,
          'careerName': c.careerName,
          'date': c.date,
          'cvTextSha256': sha256Hex(utf8.encode(c.cvText)),
        },
    ],
    'oldTemplateSha256': oldTextSha256,
    'newTemplateSha256': newTextSha256,
    'textSha256': {
      for (final entry in texts.entries)
        entry.key: sha256Hex(utf8.encode(entry.value)),
    },
    'slots': [for (final slot in slots) slot.toJson()],
  };
  final mappingFile = File('$folder/sealed/mapping.json');
  if (mappingFile.existsSync()) {
    final stored = jsonEncode(readJson(mappingFile.path));
    if (stored != jsonEncode(mapping)) {
      fail('$folder/sealed/mapping.json was written for another run (set, '
          'texts, versions, runs or seed differ). Use a new --out folder.');
    }
  } else {
    writeJson(mappingFile.path, mapping);
  }

  // ---- slots to run -------------------------------------------------------
  File rawFile(Slot slot) => File('$folder/sealed/raw/${slot.rawName}.json');
  File failedFile(Slot slot) =>
      File('$folder/sealed/failed/${slot.rawName}.json');
  int failedRuns(Slot slot) {
    final file = failedFile(slot);
    if (!file.existsSync()) return 0;
    final data = readJson(file.path);
    return data is Map ? (data['failedRuns'] as num?)?.toInt() ?? 0 : 0;
  }

  bool done(Slot slot) =>
      rawFile(slot).existsSync() || failedRuns(slot) > extraTries;
  final pending = [for (final slot in slots) if (!done(slot)) slot]
    ..shuffle(Random(seed));
  stdout.writeln('Slots      : ${slots.length - pending.length} of '
      '${slots.length} already done, ${pending.length} to send '
      '(concurrency $concurrency)');

  final started = DateTime.now();
  var succeeded = 0;
  var failed = 0;
  var finished = 0;
  final perVersion = {
    for (final version in versions) version: {'succeeded': 0, 'failed': 0},
  };
  AtsMeter? meter;
  AtsStop? stopSeen;
  AtsStop? currentStop() => stopSeen ?? meter?.stop;
  if (pending.isNotEmpty) {
    meter = AtsMeter(inputPrice: inputPrice, outputPrice: outputPrice);
    final activeMeter = meter;
    final ai = newService(activeMeter);
    Future<void> runSlot(Slot slot) async {
      if (currentStop() != null) return;
      final counter = UsageCounter();
      final slotStarted = DateTime.now();
      final failures = <Map<String, Object?>>[];
      Map<String, dynamic>? decoded;
      var attempts = 0;
      for (var attempt = 1; attempt <= 2; attempt++) {
        if (currentStop() != null) break;
        attempts = attempt;
        try {
          decoded = await withUsage(
            counter,
            () => ai.requestJson(
              prompt: texts['${slot.cv}_${slot.version}']!,
              maxTokens: maxTokens,
              enableThinking: true,
            ),
          );
          break;
        } catch (e) {
          if (e is AtsStop) stopSeen ??= e;
          if (currentStop() != null) break;
          final failure = describeFailure(e);
          failures.add({'status': failure.status, 'kind': failure.kind});
          if (attempt < 2) await Future.delayed(const Duration(seconds: 1));
        }
      }
      final answer = decoded;
      if (answer != null) {
        final finishedAt = DateTime.now();
        writeJson(rawFile(slot).path, {
          ...slot.toJson(),
          'attempts': attempts,
          'failedAttempts': failures,
          'startedAt': slotStarted.toIso8601String(),
          'finishedAt': finishedAt.toIso8601String(),
          'seconds': finishedAt.difference(slotStarted).inMilliseconds / 1000,
          'inputTokens': counter.inputTokens,
          'outputTokens': counter.outputTokens,
          'decoded': answer,
          'areas': ai.cvImprovementFrom(answer),
        });
        succeeded++;
        perVersion[slot.version]!['succeeded'] =
            perVersion[slot.version]!['succeeded']! + 1;
      } else if (currentStop() == null) {
        final earlier = failedFile(slot).existsSync()
            ? readJson(failedFile(slot).path)
            : null;
        final history = [
          if (earlier is Map && earlier['history'] is List)
            ...earlier['history'] as List,
          {'at': DateTime.now().toIso8601String(), 'attempts': failures},
        ];
        writeJson(failedFile(slot).path, {
          ...slot.toJson(),
          'failedRuns': failedRuns(slot) + 1,
          'history': history,
        });
        failed++;
        perVersion[slot.version]!['failed'] =
            perVersion[slot.version]!['failed']! + 1;
      } else {
        return;
      }
      finished++;
      stdout.writeln('  slot $finished of ${pending.length} '
          '${answer != null ? 'done' : 'failed'}');
      if (finished % 4 == 0) stdout.writeln('  meter: ${activeMeter.summary}');
    }

    await runPool([for (final slot in pending) () => runSlot(slot)],
        concurrency: concurrency);
    stdout.writeln('Meter      : ${activeMeter.summary}');
  }

  // ---- log --------------------------------------------------------------
  final stop = currentStop();
  final logFile = File('$folder/sealed/run_log.json');
  final log = logFile.existsSync() ? readJson(logFile.path) : null;
  writeJson(logFile.path, [
    if (log is List) ...log,
    {
      'startedAt': started.toIso8601String(),
      'finishedAt': DateTime.now().toIso8601String(),
      'sent': pending.length,
      'succeeded': succeeded,
      'failed': failed,
      'perVersion': perVersion,
      'stop': stop == null
          ? null
          : {'kind': stop.kind.name, 'status': stop.status},
      'requests': meter?.requests ?? 0,
      'inputTokens': meter?.inputTokens ?? 0,
      'outputTokens': meter?.outputTokens ?? 0,
      'costUsd': meter?.cost ?? 0,
      'inputPrice': inputPrice,
      'outputPrice': outputPrice,
    },
  ]);
  meter?.close();

  if (stop != null) {
    stdout.writeln(stop.message);
    return 2;
  }
  final left = [for (final slot in slots) if (!done(slot)) slot];
  if (left.isNotEmpty) {
    stdout.writeln('${left.length} slot(s) failed and can be tried again: '
        're-run the same command (each at most $extraTries more times).');
    return slotsLeftExitCode;
  }
  final exhausted = {for (final version in versions) version: 0};
  for (final slot in slots) {
    if (!rawFile(slot).existsSync()) {
      exhausted[slot.version] = exhausted[slot.version]! + 1;
    }
  }
  stdout.writeln('All ${slots.length} slots are done. Slots that never '
      'succeeded (they count as outputs with no issues): '
      '${exhausted.entries.map((e) => '${e.key} ${e.value}').join(', ')}.');

  if (File('$folder/blind/sheet.csv').existsSync()) {
    stdout.writeln('The blind files are already written; nothing changed.');
    return 0;
  }
  _writeBlind(folder, cases, slots, rawFile);
  stdout.writeln('Blind files written to $folder/blind (give the grader '
      'only that folder and the keys).');
  return 0;
}

void _writeBlind(
  String folder,
  List<AtsCase> cases,
  List<Slot> slots,
  File Function(Slot) rawFile,
) {
  final written = <File>[];
  final textOf = {for (final c in cases) c.id: c.cvText};
  for (final c in [...cases]..sort((a, b) => a.id.compareTo(b.id))) {
    final file = File('$folder/blind/cv_text/${c.id}.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync(c.cvText);
    written.add(file);
  }
  final sheet = <List<String>>[];
  final quotes = <List<String>>[];
  for (final slot in [...slots]..sort((a, b) => a.label.compareTo(b.label))) {
    final raw = rawFile(slot).existsSync() ? readJson(rawFile(slot).path) : null;
    final areas = raw is Map ? areasFrom(raw['areas']) : emptyAreas();
    final path = '$folder/blind/outputs/${slot.label}.json';
    writeJson(path, areas);
    written.add(File(path));
    final rows = sheetRowsFor(slot.label, slot.cv, areas, textOf[slot.cv]!);
    sheet.addAll(rows.sheet);
    quotes.addAll(rows.quotes);
  }
  writeCsv('$folder/blind/sheet.csv', sheetHeader, sheet);
  writeCsv('$folder/blind/quotes.csv', quotesHeader, quotes);
  written
    ..add(File('$folder/blind/sheet.csv'))
    ..add(File('$folder/blind/quotes.csv'));
  final time = DateTime.now();
  for (final file in written) {
    file.setLastModifiedSync(time);
  }
}

// ---------------------------------------------------------
// FREEZING THE GRADED SHEET
// ---------------------------------------------------------

Map<String, Set<String>> _readPlanted(String path) {
  final decoded = readJson(path);
  if (decoded is! Map) fail('$path must be an object: {"<cv>": ["P1", ...]}.');
  return {
    for (final entry in decoded.entries)
      entry.key.toString(): {
        for (final id in entry.value is List ? entry.value as List : const [])
          id.toString().trim().toUpperCase(),
      },
  };
}

/// The tool's columns of the sheet as the blind outputs give them, to
/// check that the grader changed none of them.
List<List<String>> _expectedToolColumns(String folder) {
  final outputs = Directory('$folder/blind/outputs');
  if (!outputs.existsSync()) fail('No $folder/blind/outputs folder.');
  final labels = [
    for (final file in outputs.listSync().whereType<File>())
      if (file.path.endsWith('.json'))
        file.uri.pathSegments.last
            .substring(0, file.uri.pathSegments.last.length - '.json'.length),
  ]..sort();
  final rows = <List<String>>[];
  for (final label in labels) {
    final cv = label.substring(0, label.lastIndexOf('_'));
    final cvText = utf8.decode(
        File('$folder/blind/cv_text/$cv.txt').readAsBytesSync());
    final generated = sheetRowsFor(label, cv,
        areasFrom(readJson('$folder/blind/outputs/$label.json')), cvText);
    for (final row in generated.sheet) {
      rows.add([for (final cell in row.take(toolColumns)) cellAsRead(cell)]);
    }
  }
  return rows;
}

/// Checks the graded sheet of [folder] and records its sha256 (--freeze).
void freezeFolder(String folder) {
  if (File('$folder/result.json').existsSync()) {
    fail('$folder is already scored; a scored sheet cannot be frozen again.');
  }
  final sheetPath = '$folder/blind/sheet.csv';
  final plantedPath = '$folder/blind/planted.json';
  final rows = readCsv(sheetPath);
  final planted = _readPlanted(plantedPath);
  final problems = <String>[];

  final expected = _expectedToolColumns(folder);
  if (expected.length != rows.length) {
    problems.add('The sheet has ${rows.length} rows; the outputs give '
        '${expected.length}. Rows must not be added or removed.');
  } else {
    for (var i = 0; i < rows.length; i++) {
      for (var j = 0; j < toolColumns; j++) {
        if ((rows[i][sheetHeader[j]] ?? '') != expected[i][j]) {
          problems.add('Row ${i + 2}: column ${sheetHeader[j]} does not '
              'match the outputs. Keep the rows in the order the tool wrote '
              'them, and fill only the grader\'s columns.');
          break;
        }
      }
    }
  }
  problems.addAll(sheetProblems(rows, planted));
  if (problems.isNotEmpty) {
    stderr.writeln('The sheet cannot be frozen yet:');
    for (final problem in problems.take(40)) {
      stderr.writeln('  $problem');
    }
    if (problems.length > 40) {
      stderr.writeln('  ... and ${problems.length - 40} more.');
    }
    exit(1);
  }
  final freeze = {
    'sheetSha256': sha256Hex(File(sheetPath).readAsBytesSync()),
    'plantedSha256': sha256Hex(File(plantedPath).readAsBytesSync()),
    'rows': rows.length,
    'frozenAt': DateTime.now().toIso8601String(),
  };
  writeJson('$folder/freeze.json', freeze);
  stdout.writeln('Frozen: ${rows.length} rows, sheet sha256 '
      '${freeze['sheetSha256']}, written to $folder/freeze.json.');
}

// ---------------------------------------------------------
// SCORING
// ---------------------------------------------------------

/// Scores a frozen sheet of [folder] under the decision rule (--score).
void scoreFolder(String folder, {required bool reportOnly}) {
  final freezePath = '$folder/freeze.json';
  if (!File(freezePath).existsSync()) {
    fail('No $freezePath: run --freeze on the graded sheet first.');
  }
  final freeze = readJson(freezePath) as Map;
  final sheetPath = '$folder/blind/sheet.csv';
  final plantedPath = '$folder/blind/planted.json';
  if (sha256Hex(File(sheetPath).readAsBytesSync()) != freeze['sheetSha256']) {
    fail('The sheet changed after it was frozen; scoring refused.');
  }
  if (sha256Hex(File(plantedPath).readAsBytesSync()) !=
      freeze['plantedSha256']) {
    fail('planted.json changed after the sheet was frozen; scoring refused.');
  }
  final rule = sha256OfText(readText(decisionRulePath));
  if (rule != decisionRuleSha256) {
    fail('$decisionRulePath is not the fixed decision rule (sha256 $rule, '
        'expected $decisionRuleSha256); scoring refused.');
  }

  // Only now the mapping is opened.
  final mapping = readJson('$folder/sealed/mapping.json') as Map;
  final slots = [
    for (final item in mapping['slots'] as List) Slot.fromJson(item as Map),
  ];
  final roles = {
    for (final c in mapping['cvs'] as List)
      (c as Map)['id'].toString(): c['role'].toString(),
  };
  final versions = [for (final v in mapping['versions'] as List) v.toString()];
  final runs = (mapping['runs'] as num).toInt();
  if (!reportOnly) {
    final shape =
        decidingShapeProblems(runs: runs, versions: versions, roles: roles);
    if (shape.isNotEmpty) {
      fail('This folder cannot decide: ${shape.join(' ')} Score it with '
          '--report-only to report it without a decision.');
    }
  }
  final sheet = readCsv(sheetPath);
  final rows = [for (final row in sheet) GradedRow.fromSheet(row)];
  final labels = {for (final slot in slots) slot.label};
  final sheetLabels = {for (final row in rows) row.label};
  if (!labels.containsAll(sheetLabels) || !sheetLabels.containsAll(labels)) {
    fail('The sheet\'s labels do not match the mapping.');
  }
  final planted = _readPlanted(plantedPath);
  final missingPlanted = plantedSetProblems(roles, planted);
  if (missingPlanted.isNotEmpty) {
    fail('Scoring refused: ${missingPlanted.join(' ')}');
  }

  final counts = {
    for (final version in versions)
      version: countVersion(version,
          slots: slots, rows: rows, roles: roles, planted: planted),
  };

  final never = {for (final version in versions) version: 0};
  for (final slot in slots) {
    if (!File('$folder/sealed/raw/${slot.rawName}.json').existsSync()) {
      never[slot.version] = never[slot.version]! + 1;
    }
  }
  final failedAttempts = {for (final version in versions) version: 0};
  List<Map<dynamic, dynamic>> sealed(String kind, String version) {
    final dir = Directory('$folder/sealed/$kind');
    if (!dir.existsSync()) return const [];
    return [
      for (final file in dir.listSync().whereType<File>())
        if (file.path.endsWith('.json'))
          if (readJson(file.path) case final Map data
              when data['version']?.toString() == version)
            data,
    ];
  }

  final requests = <String, Map<String, Object?>>{};
  for (final version in versions) {
    final failures = sealed('failed', version);
    for (final data in failures) {
      failedAttempts[version] = failedAttempts[version]! +
          ((data['failedRuns'] as num?)?.toInt() ?? 0);
    }
    requests[version] = requestSummary(sealed('raw', version), failures);
  }
  final runLog = File('$folder/sealed/run_log.json').existsSync()
      ? readJson('$folder/sealed/run_log.json')
      : null;
  var inputTokens = 0, outputTokens = 0;
  var cost = 0.0;
  for (final entry in runLog is List ? runLog : const []) {
    if (entry is! Map) continue;
    inputTokens += (entry['inputTokens'] as num?)?.toInt() ?? 0;
    outputTokens += (entry['outputTokens'] as num?)?.toInt() ?? 0;
    cost += (entry['costUsd'] as num?)?.toDouble() ?? 0;
  }

  stdout.writeln('ATS REVIEW EVALUATION: SCORE');
  stdout.writeln('Folder     : $folder');
  stdout.writeln('Decision rule sha256 $decisionRuleSha256 (checked); sheet '
      'frozen at ${freeze['frozenAt']}.');
  for (final version in versions) {
    final c = counts[version]!;
    stdout.writeln('');
    stdout.writeln('${version.toUpperCase()} (${c.outputs} outputs)');
    stdout.writeln('  (a) recall          ${c.found}/${c.plantedTotal} = '
        '${f3(c.recall)}');
    stdout.writeln('  (b) precision       ${c.trueIssues}/${c.countedIssues} '
        '= ${f3(c.precision)}');
    stdout.writeln('  (c) invented facts  ${c.inventedFacts}, misquotes '
        '${c.misquotes}');
    stdout.writeln('  (d) false or padded on the clean CV  ${c.cleanFalse}');
    stdout.writeln('  (e) consistency     ${c.consistency.toStringAsFixed(2)} '
        '(${c.consistencyPerCv.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join(', ')})');
    stdout.writeln('  verdicts            ${c.verdicts.entries.where((e) => e.value > 0).map((e) => '${e.key} ${e.value}').join(', ')}');
    stdout.writeln('  issues per area     ${c.issuesPerArea.entries.map((e) => '${e.key} ${e.value}').join(', ')}');
    stdout.writeln('  areas at the 3-issue cap  ${c.areasAtCap}');
    stdout.writeln('  failed requests     ${failedAttempts[version]} failed '
        'command runs; ${never[version]} slots never succeeded');
    final r = requests[version]!;
    final failedKinds = (r['failedAttempts'] as Map).entries
        .map((e) => '${e.key} ${e.value}')
        .join(', ');
    stdout.writeln('  requests            ${r['answered']} answered '
        '(${r['firstTry']} at the first try, ${r['afterRetry']} after a '
        'retry); failed attempts: '
        '${failedKinds.isEmpty ? 'none' : failedKinds}');
    String spreadLine(Object? value, String unit, int digits) {
      final s = value as Map;
      String n(Object? x) =>
          x == null ? 'n/a' : (x as double).toStringAsFixed(digits);
      return 'mean ${n(s['mean'])}$unit, median ${n(s['median'])}$unit, '
          'largest ${n(s['max'])}$unit';
    }

    stdout.writeln('  time per slot       '
        '${spreadLine(r['secondsPerSlot'], ' s', 1)} (retries included)');
    stdout.writeln('  first-try requests  '
        '${spreadLine(r['firstTrySeconds'], ' s', 1)}; output tokens '
        '${spreadLine(r['firstTryOutputTokens'], '', 0)}');
    stdout.writeln('  tokens (answered)   ${r['answeredInputTokens']} input, '
        '${r['answeredOutputTokens']} output');
  }
  stdout.writeln('');
  stdout.writeln('Meter      : $inputTokens input and $outputTokens output '
      'tokens, about ${cost.toStringAsFixed(3)} USD');

  final result = <String, Object?>{
    'folder': folder,
    'decisionRuleSha256': decisionRuleSha256,
    'sheetSha256': freeze['sheetSha256'],
    'counts': {for (final e in counts.entries) e.key: e.value.toJson()},
    'failedCommandRuns': failedAttempts,
    'neverSucceeded': never,
    'requestsPerVersion': requests,
    'tokens': {'input': inputTokens, 'output': outputTokens, 'costUsd': cost},
  };
  if (reportOnly || !counts.containsKey('old') || !counts.containsKey('new')) {
    stdout.writeln('development set: reported, does not decide');
    result['decision'] = 'report only';
  } else {
    final checks = decide(counts['old']!, counts['new']!);
    stdout.writeln('');
    for (final check in checks) {
      stdout.writeln('${check.pass ? 'PASS' : 'FAIL'}  ${check.name}: '
          '${check.detail}');
    }
    final adopt = adoptNew(checks);
    stdout.writeln('');
    stdout.writeln(adopt ? 'ADOPT NEW' : 'KEEP OLD');
    result['checks'] = [for (final check in checks) check.toJson()];
    result['decision'] = adopt ? 'ADOPT NEW' : 'KEEP OLD';
  }
  writeJson('$folder/result.json', result);
  stdout.writeln('Written to $folder/result.json');
}
