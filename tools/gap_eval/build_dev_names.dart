import 'dart:io';

import 'eval_support.dart';
import 'link_requests.dart';

/// Builds the exclusion list of the final matching measurement
/// (tools/gap_eval/dev_names.txt): every skill name anybody could have seen
/// while the approaches were developed. A name of the final measurement
/// that is in this list does not count in the decision.
///
/// The list holds short hashes, not names: for each name the hash of its
/// normalized form and the hash of its synonym table form, so another
/// spelling of a seen name is seen too. No name is written to the file.
///
/// What is read (nothing is requested, nothing else is written):
///   - every market list, link answer and gap list stored in the run
///     folders under build/gap_eval;
///   - the skill gaps and market skills of the persona files, and the gaps
///     of the stored persona links (--links);
///   - the label, role and "also called" names of the development sets
///     (--sets);
///   - every quoted text in the prompt templates of the app (every .dart
///     file of lib/services) and of tools/gap_eval/arms/ (the prompt
///     examples are among them);
///   - names given in plain text files, one per line (--extra), for the
///     cases that were reported to the developers.
///
/// Run it from the project root:
///
///   dart run tools/gap_eval/build_dev_names.dart \
///     --sets test/fixtures/cv_eval_dev,`round 1 blind set` \
///     --links `persona link files` --extra `file with the reported names`
///
/// The untouched set must never be passed to this tool: its names are the
/// ones the list is there to protect.
void main(List<String> arguments) {
  final args = Args(arguments, known: const {
    '--extra', '--links', '--out', '--personas', '--run-root', '--sets',
  });
  final outPath = args.value('--out') ?? 'tools/gap_eval/dev_names.txt';
  final names = <String>{};
  final counts = <String, int>{};
  void add(String source, Iterable<dynamic> values) {
    var added = 0;
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isEmpty) continue;
      if (names.add(text)) added++;
    }
    counts[source] = (counts[source] ?? 0) + added;
  }

  List<dynamic> listOf(dynamic value) => value is List ? value : const [];

  // ---- run folders ---------------------------------------------------
  final root = Directory(args.value('--run-root') ?? 'build/gap_eval');
  if (root.existsSync()) {
    for (final file in root.listSync(recursive: true).whereType<File>()) {
      final path = file.path.replaceAll('\\', '/');
      if (!path.endsWith('.json') || !path.contains('/raw/')) continue;
      dynamic data;
      try {
        data = readJson(path);
      } on Object {
        continue;
      }
      if (data is! Map) continue;
      if (path.contains('/raw/market/')) {
        add('stored market lists', listOf(data['names']));
        add('stored market lists', listOf(data['rawNames']));
      } else if (path.contains('/raw/links')) {
        add('stored link answers', [
          for (final link in listOf(data['links']))
            if (link is Map) link['gap'],
        ]);
      } else if (path.contains('/raw/gaps/')) {
        add('stored gap lists', listOf(data['gaps']));
      } else if (path.endsWith('/raw/writer_names.json')) {
        fail('$path holds writers\' names of a final measurement: the '
            'exclusion list is built before that measurement, not after.');
      }
    }
  }

  // ---- personas ------------------------------------------------------
  for (final path in [
    'test/fixtures/opportunity_eval_personas.json',
    'test/fixtures/opportunity_eval_personas_heldout.json',
    ...args.list('--personas'),
  ]) {
    // A persona file that is not there stops the tool (readJson says
    // which): its names would otherwise be missing from the list.
    for (final persona in listOf(readJson(path))) {
      if (persona is! Map) continue;
      add('persona files', listOf(persona['skillGaps']));
      add('persona files', listOf(persona['targetSkills']));
    }
  }
  for (final path in args.list('--links')) {
    final data = readJson(path);
    for (final run in listOf(data is Map ? data['links'] : null)) {
      if (run is! Map) continue;
      for (final links in run.values) {
        add('stored persona links', [
          for (final link in listOf(links))
            if (link is Map) link['gap'],
        ]);
      }
    }
  }

  // ---- development sets ------------------------------------------------
  for (final folder in args.list('--sets')) {
    final path = folder.replaceAll('\\', '/').replaceFirst(RegExp(r'/+$'), '');
    if (path.split('/').contains('final_set')) {
      fail('The untouched set must not be read by this tool.');
    }
    void addEntries(dynamic entries) {
      for (final entry in listOf(entries)) {
        if (entry is! Map) continue;
        add('set labels and roles', [entry['skill']]);
        add('set labels and roles', listOf(entry['alsoCalled']));
      }
    }

    for (final file in Directory(path).listSync().whereType<File>()) {
      final name = file.path.replaceAll('\\', '/').split('/').last;
      if (name.endsWith('.labels.json')) {
        final labels = readJson(file.path);
        if (labels is! Map) continue;
        for (final part in const ['shown', 'partly', 'notShown']) {
          addEntries(labels[part]);
        }
      } else if (name == 'roles.json') {
        final roles = readJson(file.path);
        if (roles is Map) roles.values.forEach(addEntries);
      }
    }
  }

  // ---- prompt templates ------------------------------------------------
  // The prompts of the app live in its service files. Every .dart file of
  // lib/services is read, so each quoted text of every prompt is in the
  // list (the request texts that promptTexts() builds are among them), and
  // no file has to be named here.
  final quoted = RegExp('"([^"\\n]{2,60})"');
  final serviceFiles = Directory('lib/services')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (serviceFiles.isEmpty) {
    fail('No .dart file under lib/services: run this from the project root.');
  }
  final templates = <String>[
    ...promptTexts().values,
    for (final file in serviceFiles) file.readAsStringSync(),
    for (final file in Directory('tools/gap_eval/arms')
        .listSync()
        .whereType<File>())
      file.readAsStringSync(),
  ];
  for (final text in templates) {
    add('quoted texts in prompt templates',
        [for (final match in quoted.allMatches(text)) match.group(1)]);
  }

  // ---- reported cases --------------------------------------------------
  for (final path in args.list('--extra')) {
    add('names given with --extra', readText(path).split('\n'));
  }

  final hashes = <String>{
    for (final name in names) ...exclusionKeys(name),
  }.toList()
    ..sort();
  final buffer = StringBuffer()
    ..writeln('# Exclusion list of the final matching measurement.')
    ..writeln('# Built by tools/gap_eval/build_dev_names.dart; do not edit.')
    ..writeln('# Each line is the short hash of a skill name seen in '
        'development')
    ..writeln('# (its normalized form or its synonym table form). '
        '${names.length} names.');
  hashes.forEach(buffer.writeln);
  File(outPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(buffer.toString());

  stdout.writeln('EXCLUSION LIST');
  counts.forEach((source, count) {
    stdout.writeln('  ${source.padRight(34)} $count new names');
  });
  stdout.writeln('  ${names.length} names, ${hashes.length} hashes, written to '
      '$outPath (sha256 ${sha256OfText(buffer.toString())})');
}
