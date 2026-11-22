import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:masra/services/claude_service.dart' show AnalysisAi;

import '../tools/ats_eval/ats_scoring.dart';
import '../tools/ats_eval/ats_support.dart';
import '../tools/ats_eval/evaluate_ats.dart'
    show evaluate, flagProblem, freezeFolder, scoreFolder, slotsLeftExitCode;
import '../tools/gap_eval/eval_support.dart'
    show readCsv, sha256OfText, writeCsv;

/// The helpers and the decision rule of the ATS review evaluation
/// (tools/ats_eval), on small invented inputs. No AI request is sent:
/// requests go to a MockClient or to a server on this machine.
void main() {
  String placeholderText() => AnalysisAi.cvImprovementPrompt(
        cvText: '{{CV_TEXT}}',
        careerName: '{{CAREER_NAME}}',
        today: '{{TODAY}}',
      );

  group('the review texts', () {
    test('the old text is the one the app sent, with each placeholder once',
        () {
      final old = File(oldTextPath).readAsStringSync().replaceAll('\r\n', '\n');
      expect(sha256OfText(old),
          '61df986f8be2f4ebaad6784eb0388c8eb7784769f99de7fe873d1443355509bb');
      for (final placeholder in [
        careerPlaceholder,
        todayPlaceholder,
        cvPlaceholder,
      ]) {
        expect(placeholder.allMatches(old).length, 1, reason: placeholder);
      }
    });

    test('the app sends the old text again; the measured new text stays '
        'pinned', () {
      // The measured new text was not adopted (decision KEEP OLD), so the
      // app sends the old text, word for word.
      expect(sha256OfText(placeholderText()),
          '61df986f8be2f4ebaad6784eb0388c8eb7784769f99de7fe873d1443355509bb');
      expect(newTextSha256,
          '512c0968af9bf7b8000b30fd448d2151f7c760e93d4453080894b76ffd3c131e');
      expect(oldTextSha256,
          '61df986f8be2f4ebaad6784eb0388c8eb7784769f99de7fe873d1443355509bb');
    });

    test('the decision rule is the fixed one', () {
      final rule =
          File(decisionRulePath).readAsStringSync().replaceAll('\r\n', '\n');
      expect(sha256OfText(rule),
          'abcf81b7807733ba08d573734081a76fad891f505646304a2597c4125f978894');
      expect(decisionRuleSha256,
          'abcf81b7807733ba08d573734081a76fad891f505646304a2597c4125f978894');
    });

    test('filling puts the CV in as written, after the other inputs', () {
      final old = File(oldTextPath).readAsStringSync();
      const cv = 'Line one {{TODAY}} and {{CAREER_NAME}} stay\r\nline two';
      final filled = fillReviewText(old,
          careerName: 'Web Developer', today: '2026-11-22', cvText: cv);
      expect(filled, contains(cv));
      expect(filled, contains('TARGET CAREER GOAL:\nWeb Developer\n'));
      expect(filled, contains("TODAY'S DATE:\n2026-11-22\n"));
      expect('{{TODAY}}'.allMatches(filled).length, 1);
      expect('{{CV_TEXT}}'.allMatches(filled).length, 0);
    });

    test('filling the new text gives what the app sends', () {
      expect(
        fillReviewText(placeholderText(),
            careerName: 'Data Analyst', today: '2026-01-05', cvText: 'CV'),
        AnalysisAi.cvImprovementPrompt(
            cvText: 'CV', careerName: 'Data Analyst', today: '2026-01-05'),
      );
    });

    test('a placeholder missing or twice stops filling', () {
      expect(
        () => fillReviewText('{{CAREER_NAME}} {{TODAY}}',
            careerName: 'a', today: 'b', cvText: 'c'),
        throwsFormatException,
      );
      expect(
        () => fillReviewText('{{CAREER_NAME}} {{TODAY}} {{CV_TEXT}} {{TODAY}}',
            careerName: 'a', today: 'b', cvText: 'c'),
        throwsFormatException,
      );
    });
  });

  group('labels', () {
    test('the same seed gives the same labels', () {
      final a = assignLabels(['ho_a', 'ho_b'], ['old', 'new'], 3, 7);
      final b = assignLabels(['ho_a', 'ho_b'], ['old', 'new'], 3, 7);
      expect([for (final s in a) s.toJson()], [for (final s in b) s.toJson()]);
    });

    test('every slot has one label and every label one slot', () {
      final slots =
          assignLabels(['ho_a', 'ho_b', 'ho_c'], ['old', 'new'], 3, 20261122);
      expect(slots, hasLength(18));
      expect({for (final s in slots) s.label}, hasLength(18));
      expect({for (final s in slots) s.rawName}, hasLength(18));
      for (final cv in ['ho_a', 'ho_b', 'ho_c']) {
        expect(
          {for (final s in slots) if (s.cv == cv) s.label},
          {for (var i = 1; i <= 6; i++) '${cv}_0$i'},
        );
        expect({for (final s in slots) if (s.cv == cv) '${s.version}${s.run}'},
            {'old1', 'old2', 'old3', 'new1', 'new2', 'new3'});
      }
    });
  });

  group('quotes', () {
    test('finds quoted spans and leaves apostrophes alone', () {
      expect(quotedSpans('The heading "Side Work" is unclear, and so is '
          "'My Stuff'."), ['Side Work', 'My Stuff']);
      expect(quotedSpans("Don't change the CV's layout."), isEmpty);
      expect(quotedSpans('Rename “Fun Corner” and ‘Odd Jobs’, don’t wait.'),
          ['Fun Corner', 'Odd Jobs']);
      expect(quotedSpans("Rewrite 'I don't know' as a point."),
          ["I don't know"]);
    });

    const cv = 'Designed a booking app for a local gym.\n'
        'Wrote unit tests in Python and fixed bugs. Led a team of four '
        'students.\nTeam lead – 2024 “Hack Day” winner';

    test('ignores case, whitespace, quote marks, dashes and "..." gaps', () {
      expect(quoteInCv('designed a BOOKING app', cv), isTrue);
      expect(quoteInCv('Designed a booking   app\nfor a local gym', cv),
          isTrue);
      expect(quoteInCv('Wrote unit tests ... fixed bugs', cv), isTrue);
      expect(quoteInCv('Wrote unit tests … fixed bugs.', cv), isTrue);
      expect(quoteInCv('Team lead - 2024 "Hack Day" winner', cv), isTrue);
      expect(quoteInCv('Team lead – 2024', cv), isTrue);
    });

    test('rejects changed words and words joined from two sentences', () {
      expect(quoteInCv('Designed a mobile app', cv), isFalse);
      expect(quoteInCv('fixed bugs led a team', cv), isFalse);
      expect(quoteInCv('Designed a booking app ... led a team', cv), isFalse);
      expect(quoteInCv('Wrote unit tests in Java', cv), isFalse);
    });

    test('the sheet marks quotes that are not in the CV', () {
      final rows = sheetRowsFor('cv1_01', 'cv1', {
        ...emptyAreas(),
        'readability': [
          {
            'issue': 'The point "Wrote unit tests in Python" is short.',
            'suggestion': 'Write "Wrote [number] unit tests in Python".',
          },
        ],
      }, cv);
      expect(rows.sheet, hasLength(1));
      expect(rows.sheet.single[2], 'readability');
      expect(rows.sheet.single[6], 'Wrote [number] unit tests in Python');
      expect([for (final q in rows.quotes) q.last], ['in CV', 'NOT in CV']);

      final empty = sheetRowsFor('cv1_02', 'cv1', emptyAreas(), cv);
      expect(empty.sheet.single[2], '(none)');
      expect(empty.sheet.single[7], 'EMPTY');
      expect(empty.sheet.single, hasLength(sheetHeader.length));
    });
  });

  group('stops and failures', () {
    test('credit, rate and key errors stop; others do not', () {
      expect(stopReason(402, ''), StopKind.credit);
      expect(
          stopReason(400, '{"error": {"message": "Your credit balance is too '
              'low"}}'),
          StopKind.credit);
      expect(stopReason(429, ''), StopKind.rate);
      expect(stopReason(500, '{"error": {"type": "rate_limit_error"}}'),
          StopKind.rate);
      expect(stopReason(401, ''), StopKind.key);
      expect(stopReason(403, ''), StopKind.key);
      expect(stopReason(200, 'credit billing rate_limit'), isNull);
      expect(stopReason(500, 'internal error'), isNull);
      expect(stopReason(529, '{"error": {"type": "overloaded_error"}}'),
          isNull);
    });

    test('the stop message holds only the status', () {
      expect(const AtsStop(StopKind.rate, 429).message,
          'STOPPED: credit/rate error (HTTP 429). Re-run the same command to '
          'resume.');
      expect(const AtsStop(StopKind.key, 401).message,
          'STOPPED: key or permission error (HTTP 401).');
    });

    Future<(HttpServer, List<int>)> serve(
        Future<void> Function(HttpRequest request) handle) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final hits = <int>[0];
      server.listen((request) async {
        hits[0]++;
        await handle(request);
      });
      return (server, hits);
    }

    for (final (status, kind) in [
      (401, StopKind.key),
      (403, StopKind.key),
      (429, StopKind.rate),
      (402, StopKind.credit),
    ]) {
      test('AtsMeter stops at HTTP $status and then sends nothing', () async {
        final (server, hits) = await serve((request) async {
          request.response
            ..statusCode = status
            ..write('{"error": {"type": "error"}}');
          await request.response.close();
        });
        final meter = AtsMeter();
        final url = Uri.parse('http://127.0.0.1:${server.port}/');
        try {
          await expectLater(
            meter.post(url, body: '{}'),
            throwsA(isA<AtsStop>()
                .having((s) => s.kind, 'kind', kind)
                .having((s) => s.status, 'status', status)),
          );
          await expectLater(meter.post(url, body: '{}'), throwsA(isA<AtsStop>()));
          expect(hits[0], 1);
        } finally {
          meter.close();
          await server.close(force: true);
        }
      });
    }

    test('AtsMeter passes other answers on and counts their tokens', () async {
      var call = 0;
      final (server, hits) = await serve((request) async {
        call++;
        request.response
          ..statusCode = call == 1 ? 500 : 200
          ..write(call == 1
              ? 'internal error'
              : jsonEncode({
                  'usage': {'input_tokens': 120, 'output_tokens': 30},
                }));
        await request.response.close();
      });
      final meter = AtsMeter();
      final url = Uri.parse('http://127.0.0.1:${server.port}/');
      final counter = UsageCounter();
      try {
        final first = await withUsage(counter, () => meter.post(url));
        expect(first.statusCode, 500);
        expect(first.body, 'internal error');
        final second = await withUsage(counter, () => meter.post(url));
        expect(second.statusCode, 200);
        expect(jsonDecode(second.body)['usage']['output_tokens'], 30);
        expect(hits[0], 2);
        expect(meter.stop, isNull);
        expect((counter.inputTokens, counter.outputTokens), (120, 30));
        expect((meter.inputTokens, meter.outputTokens), (120, 30));
      } finally {
        meter.close();
        await server.close(force: true);
      }
    });

    test('AtsMeter refuses every request after a stop', () async {
      final meter = AtsMeter()..stop = const AtsStop(StopKind.rate, 429);
      await expectLater(meter.post(Uri.parse('http://127.0.0.1:9/')),
          throwsA(isA<AtsStop>()));
      meter.close();
    });

    test('a failed request is described by its status and kind only',
        () async {
      Future<({int? status, String kind})> failureOf(http.Response reply) {
        final ai = AnalysisAi()
          ..apiKey = 'test-key'
          ..client = MockClient((_) async => reply);
        return ai
            .requestJson(prompt: 'P', maxTokens: 10)
            .then<({int? status, String kind})>(
                (_) => throw StateError('no failure'),
                onError: (Object e) => describeFailure(e));
      }

      String reply(Object content, {String stop = 'end_turn'}) =>
          jsonEncode({'stop_reason': stop, 'content': content});

      expect(await failureOf(http.Response('{"secret": "body"}', 503)),
          (status: 503, kind: 'http'));
      expect(
          await failureOf(http.Response(
              reply([
                {'type': 'text', 'text': '{}'},
              ], stop: 'max_tokens'),
              200)),
          (status: null, kind: 'cut_off'));
      expect(
          await failureOf(http.Response(
              reply([
                {'type': 'text', 'text': '{not json'},
              ]),
              200)),
          (status: null, kind: 'invalid_json'));
      expect(await failureOf(http.Response(reply([]), 200)),
          (status: null, kind: 'empty'));
      expect(describeFailure(TimeoutException('slow')),
          (status: null, kind: 'timeout'));
      expect(describeFailure(StateError('x')), (status: null, kind: 'other'));
    });

    test('the requests of a version are summed, retries included', () {
      final summary = requestSummary([
        {
          'attempts': 1,
          'failedAttempts': [],
          'seconds': 40.0,
          'inputTokens': 3100,
          'outputTokens': 3000,
        },
        {
          'attempts': 2,
          'failedAttempts': [
            {'status': null, 'kind': 'timeout'},
          ],
          'seconds': 130.5,
          'inputTokens': 6200,
          'outputTokens': 9000,
        },
        {
          'attempts': 1,
          'failedAttempts': [],
          'seconds': 50.0,
          'inputTokens': 3100,
          'outputTokens': 5000,
        },
      ], [
        {
          'failedRuns': 1,
          'history': [
            {
              'attempts': [
                {'status': 529, 'kind': 'http'},
                {'status': null, 'kind': 'cut_off'},
              ],
            },
          ],
        },
      ]);
      expect(summary['answered'], 3);
      expect(summary['firstTry'], 2);
      expect(summary['afterRetry'], 1);
      expect(summary['failedAttempts'],
          {'cut_off': 1, 'http 529': 1, 'timeout': 1});
      expect(summary['secondsPerSlot'],
          {'mean': 220.5 / 3, 'median': 50.0, 'max': 130.5});
      expect(summary['firstTrySeconds'],
          {'mean': 45.0, 'median': 45.0, 'max': 50.0});
      expect(summary['firstTryOutputTokens'],
          {'mean': 4000.0, 'median': 4000.0, 'max': 5000.0});
      expect(summary['answeredInputTokens'], 12400);
      expect(summary['answeredOutputTokens'], 17000);
      expect(requestSummary(const [], const [])['firstTrySeconds'],
          {'mean': null, 'median': null, 'max': null});
    });

    test('flags that would be silently ignored stop the tool', () {
      expect(flagProblem(['--freeze', '--score', '--out', 'x']), isNotNull);
      expect(flagProblem(['--freeze', '--report-only', '--out', 'x']),
          isNotNull);
      expect(flagProblem(['--score', '--dry-run', '--out', 'x']), isNotNull);
      expect(flagProblem(['--freeze', '--runs', '3', '--out', 'x']),
          isNotNull);
      expect(flagProblem(['--set', 's.json', '--report-only']), isNotNull);
      expect(flagProblem(['--score', '--report-only', '--out', 'x']), isNull);
      expect(flagProblem(['--set', 's.json', '--dry-run']), isNull);
      expect(flagProblem(['--freeze', '--out', 'x']), isNull);
    });
  });

  group('scoring', () {
    GradedRow row(String label, String cv, String verdict,
            {String credits = '',
            String point = '',
            int invented = 0,
            int misquotes = 0,
            String area = 'readability'}) =>
        GradedRow.fromSheet({
          'label': label,
          'cv': cv,
          'area': verdict == 'EMPTY' ? '(none)' : area,
          'verdict': verdict,
          'credits': credits,
          'point': point,
          'invented_facts': '$invented',
          'misquotes': '$misquotes',
        });

    const slots = [
      Slot(cv: 'p1', version: 'old', run: 1, label: 'p1_01'),
      Slot(cv: 'p1', version: 'old', run: 2, label: 'p1_02'),
      Slot(cv: 'c1', version: 'old', run: 1, label: 'c1_01'),
      Slot(cv: 'c1', version: 'old', run: 2, label: 'c1_02'),
    ];
    const roles = {'p1': 'planted', 'c1': 'clean'};
    final planted = {
      'p1': {'P1', 'P2'},
      'c1': <String>{},
    };

    test('counts recall, precision, sums, the clean CV and consistency', () {
      final rows = [
        row('p1_01', 'p1', 'PLANTED', credits: 'P1', point: 'P1'),
        row('p1_01', 'p1', 'ARTIFACT'),
        row('p1_01', 'p1', 'WRONG', point: 'wrong date'),
        row('p1_02', 'p1', 'PLANTED', credits: 'P1 P2', point: 'P1; P2'),
        row('p1_02', 'p1', 'NEUTRAL', point: 'vague verb', invented: 1),
        row('c1_01', 'c1', 'PADDED', point: 'add cloud', misquotes: 1),
        row('c1_02', 'c1', 'EMPTY'),
      ];
      final c = countVersion('old',
          slots: slots, rows: rows, roles: roles, planted: planted);
      expect((c.found, c.plantedTotal), (3, 4));
      expect((c.trueIssues, c.countedIssues), (3, 5));
      expect((c.inventedFacts, c.misquotes), (1, 1));
      expect(c.cleanFalse, 1);
      // p1: {p1, wrong date} and {p1, p2, vague verb} -> 1/4; c1: {add
      // cloud} and {} -> 0; mean 0.125, rounded 0.13.
      expect(c.consistencyPerCv['p1'], 0.25);
      expect(c.consistencyPerCv['c1'], 0.0);
      expect(c.consistency, 0.13);
      expect(c.verdicts['ARTIFACT'], 1);
      expect(c.issuesPerArea['readability'], 6);
    });

    test('runs with no issues at all are fully consistent', () {
      final rows = [
        row('p1_01', 'p1', 'EMPTY'),
        row('p1_02', 'p1', 'EMPTY'),
        row('c1_01', 'c1', 'EMPTY'),
        row('c1_02', 'c1', 'EMPTY'),
      ];
      final c = countVersion('old',
          slots: slots, rows: rows, roles: roles, planted: planted);
      expect(c.consistency, 1.0);
      expect(c.precision, 1.0);
      expect((c.found, c.plantedTotal), (0, 4));
    });

    test('consistency rounds an exact halfway value the same way every time',
        () {
      // 0.4 and 0.75 average to exactly 0.575; binary floating point gives
      // 57.49999999999999 hundredths, so the old rounding said 0.57.
      expect(((0.4 + 0.75) / 2 * 100).round(), 57);
      final a = [
        {'x', 'y'},
        {'x', 'y', 'z', 'v', 'w'},
      ];
      final b = [
        {'x', 'y', 'z'},
        {'x', 'y', 'z', 'v'},
      ];
      expect(roundedConsistency([a, b]), 0.58);
      expect(roundedConsistency([b, a]), 0.58);
      // 3 runs, Jaccards 1/4, 1/2 and 1/2: mean 5/12 = 0.41666...
      expect(
          roundedConsistency([
            [
              {'p'},
              {'p', 'q'},
              {'p', 'q', 'r', 's'},
            ],
          ]),
          0.42);
      expect(roundedConsistency([[<String>{}, <String>{}]]), 1.0);
      expect(roundedConsistency([[{'p'}]]), 1.0);
      expect(roundedConsistency(const []), 0.0);
    });

    test('a CV missing from planted.json stops the freeze', () {
      Map<String, String> sheetRow(String cv) => {
            'label': '${cv}_01',
            'cv': cv,
            'area': 'readability',
            'n': '1',
            'verdict': 'NEUTRAL',
            'credits': '',
            'point': 'x',
            'invented_facts': '',
            'misquotes': '',
          };
      final problems =
          sheetProblems([sheetRow('p1'), sheetRow('p2'), sheetRow('p2')],
              planted);
      expect(problems, hasLength(1));
      expect(problems.single, contains('"p2"'));
    });

    test('a planted CV with no planted problem stops the score', () {
      expect(plantedSetProblems(roles, planted), isEmpty);
      expect(plantedSetProblems(roles, {'c1': <String>{}}), hasLength(1));
      expect(
          plantedSetProblems(roles, {'p1': <String>{}, 'c1': <String>{}}),
          hasLength(1));
    });

    test('only a folder with the rule\'s shape decides', () {
      const decidingRoles = {
        'ho_a': 'planted',
        'ho_b': 'planted',
        'ho_c': 'clean',
        'ho_d': 'planted',
      };
      expect(
          decidingShapeProblems(
              runs: 3, versions: ['old', 'new'], roles: decidingRoles),
          isEmpty);
      for (final (runs, versions, roles) in [
        (2, ['old', 'new'], decidingRoles),
        (3, ['new'], decidingRoles),
        (3, ['old', 'new'], {...decidingRoles, 'ho_d': 'clean'}),
        (3, ['old', 'new'], {'ho_a': 'planted', 'ho_b': 'planted'}),
        (3, ['old', 'new'], {'ho_c': 'clean'}),
      ]) {
        expect(
            decidingShapeProblems(
                runs: runs, versions: versions, roles: roles),
            hasLength(1),
            reason: '$runs $versions $roles');
      }
    });

    test('a sheet is checked before it is frozen', () {
      Map<String, String> sheetRow(String verdict,
              {String area = 'readability',
              String credits = '',
              String point = 'x',
              String invented = ''}) =>
          {
            'label': 'p1_01',
            'cv': 'p1',
            'area': area,
            'n': '1',
            'verdict': verdict,
            'credits': credits,
            'point': point,
            'invented_facts': invented,
            'misquotes': '',
          };
      expect(
          sheetProblems([
            sheetRow('PLANTED', credits: 'p1', point: 'P1'),
            sheetRow('NEUTRAL'),
            sheetRow('ARTIFACT', point: ''),
            sheetRow('EMPTY', area: '(none)', point: ''),
          ], planted),
          isEmpty);
      final problems = sheetProblems([
        sheetRow('MAYBE'),
        sheetRow('PLANTED', point: 'P1'),
        sheetRow('NEUTRAL', credits: 'P1'),
        sheetRow('PLANTED', credits: 'P9', point: 'P9'),
        sheetRow('WRONG', point: ''),
        sheetRow('EMPTY', point: ''),
        sheetRow('NEUTRAL', invented: 'two'),
      ], planted);
      expect(problems, hasLength(7));
    });

    VersionCounts counts({
      int found = 13,
      int total = 30,
      int trueIssues = 100,
      int counted = 100,
      int invented = 2,
      int misquotes = 1,
      int clean = 2,
      double consistency = 0.5,
    }) =>
        VersionCounts(
          version: 'x',
          outputs: 12,
          found: found,
          plantedTotal: total,
          trueIssues: trueIssues,
          countedIssues: counted,
          inventedFacts: invented,
          misquotes: misquotes,
          cleanFalse: clean,
          consistency: consistency,
          consistencyPerCv: const {},
          verdicts: const {},
          issuesPerArea: const {},
          areasAtCap: 0,
        );

    test('the boundaries pass, compared exactly', () {
      // In floating point the gain of exactly 0.100 falls short.
      expect(16 / 30 - 13 / 30 < 0.1, isTrue);
      final checks = decide(
        counts(),
        counts(found: 16, trueIssues: 97, counted: 100),
      );
      expect([for (final c in checks) c.pass], everyElement(isTrue));
      expect(adoptNew(checks), isTrue);
    });

    test('each condition failing alone keeps OLD', () {
      final old = counts();
      final failing = {
        '(a) recall': counts(found: 15, trueIssues: 97),
        '(b) precision': counts(found: 16, trueIssues: 96),
        '(c) invented facts and misquotes': counts(found: 16, invented: 3),
        '(c) misquotes': counts(found: 16, misquotes: 2),
        '(d) false or padded on the clean CV': counts(found: 16, clean: 3),
        '(e) consistency': counts(found: 16, consistency: 0.49),
      };
      failing.forEach((name, neu) {
        final checks = decide(old, neu);
        expect(adoptNew(checks), isFalse, reason: name);
        expect([for (final c in checks) if (!c.pass) c.name], hasLength(1),
            reason: name);
      });
    });
  });

  group('the whole run, answered on this machine', () {
    test('runs, resumes a failed slot, writes the blind files, freezes and '
        'scores', () async {
      final dir = Directory.systemTemp.createTempSync('ats_eval_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final root = dir.path.replaceAll('\\', '/');
      const plantedCv = 'Sami Example\r\nsami@example.com\r\nPROJECTS\r\n'
          'Built a chat app with a mobile framework.\r\n';
      const cleanCv = 'Huda Example\r\nhuda@example.com | +966 50 000 0000\r\n'
          'EXPERIENCE\r\nTrained a classifier on survey data.\r\n';
      File('$root/a.txt').writeAsStringSync(plantedCv);
      File('$root/c.txt').writeAsStringSync(cleanCv);
      File('$root/set.json').writeAsStringSync(jsonEncode({
        'date': '2026-11-22',
        'cvs': [
          {
            'id': 't_a',
            'text': 'a.txt',
            'goal': 'mobile_developer',
            'role': 'planted',
          },
          {
            'id': 't_c',
            'text': '$root/c.txt',
            'goal': 'A Goal Not In The List',
            'role': 'clean',
          },
        ],
      }));

      var calls = 0;
      final prompts = <String>[];
      AnalysisAi fake(AtsMeter meter) => AnalysisAi()
        ..apiKey = 'test-key'
        ..client = MockClient((request) async {
          calls++;
          if (calls <= 2) return http.Response('server error', 500);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['max_tokens'], 10000);
          expect(body.containsKey('thinking'), isFalse);
          final prompt = (body['messages'] as List).single['content'] as String;
          prompts.add(prompt);
          final review = {
            ...emptyAreas(),
            if (prompt.contains('Built a chat app'))
              'cvStructure': [
                {
                  'issue': 'The contact details have no phone number.',
                  'suggestion': 'Add a phone number under "Sami Example".',
                },
              ],
          };
          return http.Response(
            jsonEncode({
              'stop_reason': 'end_turn',
              'content': [
                {'type': 'text', 'text': jsonEncode(review)},
              ],
            }),
            200,
          );
        });

      final out = '$root/out';
      final command = [
        '--set', '$root/set.json', '--out', out,
        '--runs', '3', '--concurrency', '1',
      ];
      // The first slot fails twice: it is left to try again.
      expect(await evaluate(command, newService: fake), slotsLeftExitCode);
      expect(Directory('$out/sealed/failed').listSync(), hasLength(1));
      expect(Directory('$out/sealed/raw').listSync(), hasLength(11));
      expect(Directory('$out/blind').existsSync(), isFalse);
      // The next run sends only that slot and writes the blind files.
      expect(await evaluate(command, newService: fake), 0);
      expect(calls, 14);
      expect(prompts, hasLength(12));

      final oldText = File(oldTextPath).readAsStringSync();
      final expected = {
        for (final (_, name, text) in [
          ('t_a', 'Mobile Developer', plantedCv),
          ('t_c', 'A Goal Not In The List', cleanCv),
        ]) ...{
          fillReviewText(oldText,
              careerName: name, today: '2026-11-22', cvText: text),
          AnalysisAi.cvImprovementPrompt(
              cvText: text, careerName: name, today: '2026-11-22'),
        },
      };
      expect(prompts.toSet(), expected);

      final outputs = Directory('$out/blind/outputs')
          .listSync()
          .whereType<File>()
          .toList();
      expect(outputs, hasLength(12));
      expect({for (final f in outputs) f.lastModifiedSync()}, hasLength(1));
      expect(File('$out/blind/cv_text/t_a.txt').readAsStringSync(), plantedCv);
      final mapping =
          jsonDecode(File('$out/sealed/mapping.json').readAsStringSync());
      expect(mapping['slots'], hasLength(12));

      final sheetPath = '$out/blind/sheet.csv';
      final sheet = readCsv(sheetPath);
      expect(sheet, hasLength(12));
      expect(sheet.where((r) => r['verdict'] == 'EMPTY'), hasLength(6));
      final quotes = readCsv('$out/blind/quotes.csv');
      expect(quotes, hasLength(6));
      expect(quotes.every((q) => q['check'] == 'in CV'), isTrue);

      // The grader's part.
      writeCsv(sheetPath, sheetHeader, [
        for (final row in sheet)
          [
            for (final column in sheetHeader)
              row['verdict'] == 'EMPTY'
                  ? row[column] ?? ''
                  : switch (column) {
                      'verdict' => 'PLANTED',
                      'credits' => 'P1',
                      'point' => 'P1',
                      _ => row[column] ?? '',
                    },
          ],
      ]);
      File('$out/blind/planted.json')
          .writeAsStringSync(jsonEncode({'t_a': ['P1'], 't_c': []}));
      final graded = File(sheetPath).readAsStringSync();

      // A run after the blind files exist changes nothing.
      expect(await evaluate(command, newService: fake), 0);
      expect(calls, 14);
      expect(File(sheetPath).readAsStringSync(), graded);

      freezeFolder(out);
      expect(File('$out/freeze.json').existsSync(), isTrue);
      scoreFolder(out, reportOnly: false);
      final result =
          jsonDecode(File('$out/result.json').readAsStringSync()) as Map;
      expect(result['decision'], 'KEEP OLD');
      expect(result['counts']['old']['recall']['found'], 3);
      expect(result['counts']['new']['recall']['of'], 3);
      expect(result['counts']['new']['falseOrPaddedOnClean'], 0);
      expect(result['checks'], hasLength(5));
      // The requests of each version: the slot that failed twice in the
      // first run was answered at the first try of the second run.
      final requests = result['requestsPerVersion'] as Map;
      expect(requests.keys.toSet(), {'old', 'new'});
      var answered = 0, firstTry = 0, failedHttp = 0;
      for (final r in requests.values) {
        answered += r['answered'] as int;
        firstTry += r['firstTry'] as int;
        failedHttp += (r['failedAttempts'] as Map)['http 500'] as int? ?? 0;
        expect(r['secondsPerSlot']['max'], isA<double>());
      }
      expect((answered, firstTry, failedHttp), (12, 12, 2));
    },
        // The tool compares the app's text with the old one and stops when
        // they are the same. The app sends the old text again, so this run
        // cannot happen until a new text is pinned for a new measurement.
        skip: 'The app sends the old review text again; nothing to compare.');
  });
}
