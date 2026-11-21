import 'dart:io';

import 'package:masra/models/gap_link.dart';

import '../gap_eval/eval_support.dart';
import '../gap_eval/link_requests.dart';

/// Asks the AI model for the meaning links of the skill gaps of the test
/// personas, and stores the answers in one file, so the persona guard of
/// evaluate_recommender.dart (`--links`) can be repeated without a request.
///
/// The request is the app's own, with the catalogue names the app bundles.
/// It runs several times per persona because the answers of the AI model
/// vary; the guard compares the mean.
///
/// Run it from the project root (real AI requests; the key is read from
/// the local .env file and never printed):
///
///   dart run tools/recommender_eval/link_persona_gaps.dart \
///     --personas test/fixtures/opportunity_eval_personas.json \
///     --request typed --runs 3 --out build/gap_eval/persona_links/dev_typed.json
///
/// Options:
///   --request `which`  names (the first request) or typed (default)
///   --runs `n`         answers per persona (default 3)
///   --limit `n`        send at most n requests (a smoke test)
///   --dry-run          print the estimate, send nothing
///
/// The file it writes:
///   {personas, request, runs, generatedOn,
///    links: [ {`persona id`: [ {gap, kind, concepts, ...}, ... ]}, ... ]}
/// one map per run. A persona whose request failed has no entry in that
/// run, which the guard reports and treats as "no links", as the app does.
/// When the file exists, only the missing entries are requested.
Future<void> main(List<String> arguments) async {
  final args = Args(arguments, known: const {
    '--concurrency', '--dry-run', '--limit', '--out', '--personas',
    '--request', '--runs',
  });
  final personasPath =
      args.value('--personas') ?? 'test/fixtures/opportunity_eval_personas.json';
  final outPath = args.value('--out') ?? fail('Pass --out <file>.');
  final runs = args.integer('--runs', 3);
  final request = linkRequestOf(args.value('--request') ?? 'typed');
  final limit = args.integer('--limit', 0);

  final decoded = readJson(personasPath);
  if (decoded is! List) fail('$personasPath is not a JSON list.');
  final gapsById = <String, List<String>>{};
  for (final item in decoded) {
    if (item is! Map) continue;
    final id = item['id']?.toString() ?? '';
    final gaps = [
      for (final gap in item['skillGaps'] as List? ?? const [])
        if (gap.toString().trim().isNotEmpty) gap.toString().trim(),
    ];
    if (id.isNotEmpty && gaps.isNotEmpty) gapsById[id] = gaps;
  }
  if (gapsById.isEmpty) fail('$personasPath has no persona with skill gaps.');

  // What an earlier call already stored.
  final results = [for (var r = 0; r < runs; r++) <String, dynamic>{}];
  if (File(outPath).existsSync()) {
    final earlier = readJson(outPath);
    final lists = earlier is Map ? earlier['links'] : null;
    if (earlier is Map && earlier['request'] != request.name) {
      fail('$outPath holds answers of another link request.');
    }
    for (var r = 0; lists is List && r < lists.length && r < runs; r++) {
      if (lists[r] is Map) results[r].addAll(Map<String, dynamic>.from(lists[r]));
    }
  }

  final requester = LinkRequester();
  final todo = <({int r, String id, List<String> gaps})>[
    for (var r = 0; r < runs; r++)
      for (final entry in gapsById.entries)
        if (results[r][entry.key] is! List)
          (r: r, id: entry.key, gaps: entry.value),
  ];
  final batch = limit > 0 && todo.length > limit ? todo.sublist(0, limit) : todo;
  stdout.writeln('${gapsById.length} personas, $runs runs, '
      '${request == LinkRequest.typed ? 'typed' : 'first'} link request. '
      'To send now: ${batch.length}'
      '${batch.length < todo.length ? ' of ${todo.length}' : ''}.');
  printEstimate(
    'Estimate',
    [for (final item in batch) requester.estimate(item.gaps, request)],
  );
  if (args.has('--dry-run') || batch.isEmpty) return;

  CreditStop? stop;
  await runPool(
    [
      for (final item in batch)
        () async {
          if (stop != null) return;
          try {
            final links = await requester.request(item.gaps, request);
            if (links == null) return;
            results[item.r][item.id] = [for (final link in links) link.toMap()];
          } on CreditStop catch (error) {
            stop = error;
          }
        },
    ],
    concurrency: args.integer('--concurrency', 3),
    onProgress: (done, total) {
      if (done % 6 == 0 || done == total) stdout.writeln('  $done/$total');
    },
  );

  final now = DateTime.now();
  writeJson(outPath, {
    'personas': personasPath,
    'request': request.name,
    'runs': runs,
    'generatedOn': '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}',
    'links': results,
  });
  stdout.writeln('Links written to $outPath. Sent: ${requester.meter.summary}.'
      '${requester.failed > 0 ? ' ${requester.failed} requests failed and have no entry; run the same command again to send only those.' : ''}');
  if (stop != null) {
    stdout.writeln('$stop. Nothing more was sent.');
    exit(2);
  }
  exit(0);
}
