// Checks the saved results of Section 5.1 (Experimental Results) again,
// without any request to the AI service, and writes what it found to
// evaluation/logs/rerun_<date>.txt.
//
// Run it from the project root:
//
//   dart run tools/rerun_evaluations.dart
//
// What it does (evaluation/README.md explains each experiment):
//  1. Skill gaps: scores the two saved runs again with
//     tools/gap_eval/evaluate_gaps.dart --score and compares the result with
//     the saved scores.txt.
//  2. Opportunity recommender: runs tools/recommender_eval/evaluate_recommender.dart
//     on both sets of test users and compares the output with the saved one.
//     The TIMING block is left out, because times change from run to run.
//  3. ATS review: runs the two Python scorers on the saved blind grades, when
//     Python is installed, and checks the counts and the decision.
//  4. Matching by meaning: checks the SHA-256 of the saved grades and of the
//     saved score output. Its scoring tool refuses to run on code that changed
//     after its freeze (see evaluation/README.md), so it is not scored again.
//
// The saved files are copied to build/rerun first, so they are never changed.
// The exit code is 1 when any check differs.
import 'dart:convert';
import 'dart:io';

import 'gap_eval/eval_support.dart' show sha256Hex;

final _log = StringBuffer();
var _same = 0;
var _different = 0;
var _skipped = 0;

Future<void> main() async {
  final date = DateTime.now().toIso8601String().substring(0, 10);
  final work = Directory('build/rerun');
  if (work.existsSync()) work.deleteSync(recursive: true);
  work.createSync(recursive: true);

  _line('RERUN OF THE SECTION 5.1 EVALUATIONS ($date)');
  _line('No request is sent to the AI service. Saved files are copied to '
      'build/rerun before use.');

  await _skillGaps();
  await _recommender();
  await _atsReview();
  _matching();

  _line();
  _line('SUMMARY: $_same same, $_different different, $_skipped skipped.');
  final out = File('evaluation/logs/rerun_$date.txt');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(_log.toString());
  stdout.writeln('Written to ${out.path}');
  exitCode = _different > 0 ? 1 : 0;
}

// ---- 1. skill gaps -----------------------------------------------------------

Future<void> _skillGaps() async {
  _section('1. SKILL GAPS OF THE AI CAREER ANALYSIS (Section 5.1.1)');
  for (final name in ['final_run', 'first_run']) {
    final saved = 'evaluation/skill_gaps/$name';
    final copy = 'build/rerun/skill_gaps_$name';
    _copyDirectory(saved, copy);
    final result = await _run('dart', [
      'run', 'tools/gap_eval/evaluate_gaps.dart', '--score', copy, '--details',
    ]);
    if (result.exitCode != 0) {
      _check('skill gaps, $name', false, 'the scoring tool failed:\n${result.text}');
      continue;
    }
    // The first line names the folder, which differs between the two copies.
    final now = _withoutFirstLine(File('$copy/scores.txt').readAsStringSync());
    final before = _withoutFirstLine(File('$saved/scores.txt').readAsStringSync());
    _compare('skill gaps, $name: scores.txt', now, before);
    _quote(now, from: 'ALL CVS', until: 'MARKET SKILL NAMES');
    _quote(now, from: 'AGAINST G0E0', until: 'GAPS PER CV');
  }
}

// ---- 2. opportunity recommender ---------------------------------------------

Future<void> _recommender() async {
  _section('2. RANKING OF THE OPPORTUNITY RECOMMENDER (Section 5.1.2)');
  final runs = {
    'development test users': (
      const <String>[],
      'evaluation/recommender/development_2026-11-22.txt',
    ),
    'held-out test users': (
      const [
        '--personas', 'test/fixtures/opportunity_eval_personas_heldout.json',
        '--ablation',
      ],
      'evaluation/recommender/heldout_2026-11-22.txt',
    ),
  };
  for (final entry in runs.entries) {
    final (args, saved) = entry.value;
    final result = await _run('dart', [
      'run', 'tools/recommender_eval/evaluate_recommender.dart', ...args,
    ]);
    if (result.exitCode != 0) {
      _check('recommender, ${entry.key}', false, 'the tool failed:\n${result.text}');
      continue;
    }
    _compare('recommender, ${entry.key} (without TIMING)',
        _withoutTiming(result.text), _withoutTiming(File(saved).readAsStringSync()));
    _quote(result.text, from: 'AVERAGE OVER', until: 'Rankings identical');
  }
}

// ---- 3. ATS review ------------------------------------------------------------

Future<void> _atsReview() async {
  _section('3. REVIEW INSTRUCTIONS OF THE CV IMPROVEMENT ASSISTANT (Section 5.1.4)');
  final python = await _findPython();
  if (python == null) {
    _skip('ATS scorers', 'Python was not found. Run by hand: python '
        'evaluation/ats_review/score_heldout.py evaluation/ats_review/grades');
    return;
  }
  final held = await _run(python, [
    'evaluation/ats_review/score_heldout.py', 'evaluation/ats_review/grades',
  ]);
  _expect('ATS held-out scorer', held, const [
    'recall 62 / 78',
    'recall 54 / 78',
    'precision 82 / 93',
    'precision 75 / 81',
    '(a) recall gain -8 / 78 = -0.1026 FAIL',
    'DECISION: KEEP OLD',
  ]);
  _quote(held.text, from: 'OLD', until: 'check all 18');
  final dev = await _run(python, ['evaluation/ats_review/score_dev.py']);
  _expect('ATS development scorer', dev, const [
    'old flawed found 22 /36',
    'new flawed found 33 /36',
  ]);
  _quote(dev.text, from: 'old', until: null);
}

Future<String?> _findPython() async {
  for (final name in ['python', 'python3', 'py']) {
    try {
      final r = await Process.run(name, ['--version']);
      if (r.exitCode == 0 && '${r.stdout}${r.stderr}'.contains('Python 3')) {
        return name;
      }
    } on ProcessException {
      // try the next name
    }
  }
  return null;
}

// ---- 4. matching by meaning ---------------------------------------------------

void _matching() {
  _section('4. MATCHING SKILL GAPS BY MEANING (Section 5.1.3)');
  // Recorded when the grades were saved (after the catalogue texts that named
  // an AI product were redacted; the scorer does not read that column).
  const recorded = {
    'evaluation/matching/final_run/judgements/teaching.csv':
        'e0575cad5858ad934f833e33cd5350f9416cb1ebc37f9b1dbe3b5c1142c50328',
    'evaluation/matching/final_run/judgements/teaching_second.csv':
        '3444e1802b5b963d1282327c3107c2ba4cf4f5e945e059771fe3c327126ee9da',
    'evaluation/matching/final_run/review/matching_scores_r2.txt':
        '12b4362684cbc61ff20fc69af733c755294af2892ce72fa79271b146e58c30b0',
  };
  for (final entry in recorded.entries) {
    final file = File(entry.key);
    if (!file.existsSync()) {
      _check(entry.key, false, 'missing');
      continue;
    }
    final hash = sha256Hex(file.readAsBytesSync());
    _check('SHA-256 of ${entry.key}', hash == entry.value,
        hash == entry.value ? '' : 'now $hash, recorded ${entry.value}');
  }
  _skip('matching scores', 'not scored again: the scoring tool checks the '
      'freeze in tools/gap_eval/freeze_r2.json and refuses to run on later '
      'code (see evaluation/README.md, "Matching by meaning").');
  _quote(File('evaluation/matching/final_run/review/matching_scores_r2.txt')
      .readAsStringSync(), from: 'DECISION RULES', until: 'ATTRIBUTIONS OF');
}

// ---- helpers --------------------------------------------------------------------

class _Result {
  _Result(this.exitCode, this.text);
  final int exitCode;
  final String text;
}

Future<_Result> _run(String executable, List<String> args) async {
  _line('\$ $executable ${args.join(' ')}');
  final r = await Process.run(executable, args,
      runInShell: Platform.isWindows,
      stdoutEncoding: utf8,
      stderrEncoding: utf8);
  return _Result(r.exitCode, '${r.stdout}${r.stderr}'.replaceAll('\r\n', '\n'));
}

void _compare(String what, String now, String before) {
  final a = now.replaceAll('\r\n', '\n').trimRight().split('\n');
  final b = before.replaceAll('\r\n', '\n').trimRight().split('\n');
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : '(no line)';
    final y = i < b.length ? b[i] : '(no line)';
    if (x.trimRight() != y.trimRight()) {
      _check(what, false, 'first difference at line ${i + 1}:\n  now  : $x\n  saved: $y');
      return;
    }
  }
  _check(what, true, '');
}

void _expect(String what, _Result result, List<String> wanted) {
  final missing = [for (final w in wanted) if (!result.text.contains(w)) w];
  _check(what, result.exitCode == 0 && missing.isEmpty,
      missing.isEmpty ? '' : 'missing: ${missing.join(' | ')}\n${result.text}');
}

void _check(String what, bool ok, String detail) {
  if (ok) {
    _same++;
  } else {
    _different++;
  }
  _line('${ok ? 'SAME     ' : 'DIFFERENT'}  $what');
  if (detail.isNotEmpty) _line(detail);
}

void _skip(String what, String why) {
  _skipped++;
  _line('SKIPPED    $what: $why');
}

String _withoutFirstLine(String text) {
  final t = text.replaceAll('\r\n', '\n');
  final i = t.indexOf('\n');
  return i < 0 ? '' : t.substring(i + 1);
}

/// The output without its TIMING block (from the TIMING line to the next
/// empty line, or to the end).
String _withoutTiming(String text) {
  final out = <String>[];
  var inTiming = false;
  for (final line in text.replaceAll('\r\n', '\n').split('\n')) {
    if (line.startsWith('TIMING')) inTiming = true;
    if (!inTiming) out.add(line);
    if (inTiming && line.trim().isEmpty) inTiming = false;
  }
  return out.join('\n');
}

/// Copies the lines from the first one that starts with [from] up to the
/// line that starts with [until] (or to the end) into the log.
void _quote(String text, {required String from, required String? until}) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final start = lines.indexWhere((l) => l.trimLeft().startsWith(from));
  if (start < 0) return;
  var end = until == null
      ? lines.length
      : lines.indexWhere((l) => l.trimLeft().startsWith(until), start + 1);
  if (end < 0) end = lines.length;
  _line();
  for (final l in lines.sublist(start, end)) {
    _line('    $l');
  }
}

void _section(String title) {
  _line();
  _line(title);
}

void _line([String text = '']) {
  _log.writeln(text);
  stdout.writeln(text);
}

void _copyDirectory(String from, String to) {
  final source = Directory(from);
  for (final entity in source.listSync(recursive: true)) {
    final relative = entity.path.substring(source.path.length);
    if (entity is File) {
      final target = File('$to$relative');
      target.parent.createSync(recursive: true);
      entity.copySync(target.path);
    }
  }
}
