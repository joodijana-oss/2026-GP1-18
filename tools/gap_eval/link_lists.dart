import 'dart:io';

import 'package:masra/models/gap_link.dart';

import 'eval_data.dart';
import 'eval_support.dart';
import 'link_requests.dart';

/// Asks the AI model for the meaning links of market lists that are
/// already stored in run folders, and stores each answer next to its list
/// (raw/links for the first request, raw/links_typed for the typed one).
/// Development only: the lists were produced in development, so their
/// names are development names. It refuses the career goals whose names
/// decide the final measurement.
///
/// Run it from the project root (real AI requests; the key is read from
/// the local .env file and never printed):
///
///   dart run tools/gap_eval/link_lists.dart \
///     --runs build/gap_eval/heldout_qa1,build/gap_eval/qa1_dev_smoke \
///     --request typed --dry-run
///
/// Options:
///   --runs `folders`     run folders, comma separated
///   --request `which`    names (the first request) or typed (default)
///   --extractors `list`  market lists to link (default E1)
///   --goals `list`       only these career goals
///   --limit `n`          send at most n requests (a smoke test)
///   --concurrency `n`    requests at the same time (default 3)
///   --dry-run            print the requests and the estimate, send nothing
///
/// An answer that is already stored is never requested again. The tool
/// stops at the first billing or credit error, without a retry.
Future<void> main(List<String> arguments) async {
  final args = Args(arguments, known: const {
    '--concurrency', '--dry-run', '--extractors', '--goals', '--limit',
    '--request', '--runs',
  });
  final runs = [for (final path in args.list('--runs')) RunFolder(path)];
  if (runs.isEmpty) fail('Pass --runs <folder[,folder]>.');
  final request = linkRequestOf(args.value('--request') ?? 'typed');
  final extractors = args.list('--extractors').isEmpty
      ? const ['E1']
      : args.list('--extractors');
  final goals = args.list('--goals').toSet();
  final limit = args.integer('--limit', 0);

  final requester = LinkRequester();
  final todo = <({RunFolder run, String goal, String extractor, int r, List<String> skills})>[];
  var stored = 0;
  for (final run in runs) {
    for (final extractor in extractors) {
      for (final goal in run.marketGoals(extractor)) {
        if (goals.isNotEmpty && !goals.contains(goal)) continue;
        if (decisionGoals.contains(goal)) {
          fail('$goal is a decision goal of the final measurement: no link '
              'request may be sent for it in development.');
        }
        for (final r in run.marketRuns(goal, extractor)) {
          final skills = run.market(goal, extractor, r);
          if (skills == null || skills.isEmpty) continue;
          if (File(run.linksPath(goal, extractor, r, request: request))
              .existsSync()) {
            stored++;
            continue;
          }
          todo.add((run: run, goal: goal, extractor: extractor, r: r, skills: skills));
        }
      }
    }
  }
  final batch = limit > 0 && todo.length > limit ? todo.sublist(0, limit) : todo;

  stdout.writeln('LINK REQUESTS FOR STORED MARKET LISTS '
      '(${request == LinkRequest.typed ? 'typed request' : 'first request'})');
  stdout.writeln('Already stored: $stored. To send now: ${batch.length}'
      '${batch.length < todo.length ? ' of ${todo.length}' : ''}.');
  printEstimate(
    'Estimate',
    [for (final item in batch) requester.estimate(item.skills, request)],
  );
  if (args.has('--dry-run') || batch.isEmpty) return;

  CreditStop? stop;
  await runPool(
    [
      for (final item in batch)
        () async {
          if (stop != null) return;
          try {
            final links = await requester.request(item.skills, request);
            if (links == null) return;
            writeJson(
              item.run.linksPath(item.goal, item.extractor, item.r,
                  request: request),
              {
                'goal': item.goal,
                'extractor': item.extractor,
                'run': item.r,
                'request': request.name,
                'links': [for (final link in links) link.toMap()],
              },
            );
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
  stdout.writeln('Sent: ${requester.meter.summary}.');
  if (requester.failed > 0) {
    stdout.writeln('${requester.failed} requests failed and have no stored '
        'answer; run the same command again to send only those.');
  }
  if (stop != null) {
    stdout.writeln('$stop. Nothing more was sent.');
    exit(2);
  }
  exit(0);
}
