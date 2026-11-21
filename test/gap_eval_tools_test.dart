import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:masra/models/gap_link.dart';

import '../tools/gap_eval/approaches.dart';
import '../tools/gap_eval/decision_rules.dart';
import '../tools/gap_eval/eval_data.dart';
import '../tools/gap_eval/eval_support.dart';
import '../tools/gap_eval/freeze_r2.dart';
import '../tools/gap_eval/link_requests.dart';
import '../tools/gap_eval/timing_amendment.dart' hide main;

/// The decision logic of the matching evaluation tools, on small invented
/// inputs. The tools themselves run on the stored development data.
void main() {
  group('approach ids', () {
    test('A, B and the fallback read as their settings say', () {
      final a = Approach.parse('A/10/05');
      expect(a.source, LinkSource.names);
      expect(a.opportunities.theta, 0.10);
      expect(a.certifications.theta, 0.05);
      expect(a.opportunities.supportGate, isTrue);
      expect(a.opportunities.termSupport, isFalse);

      final b = Approach.parse('B/10/10/bt');
      expect(b.source, LinkSource.typed);
      expect(b.opportunities.termSupport, isTrue);
      expect(b.opportunities.termEvidence, isTrue);

      final fallback = Approach.parse('A/10/05-opp');
      expect(fallback.opportunities.enabled, isTrue);
      expect(fallback.certifications.enabled, isFalse);
      expect(Approach.parse('A0').opportunities.enabled, isFalse);
    });

    test('the gated word control has the same gate and its own id', () {
      final control = Approach.parse('A/10/05/p').gatedControl;
      expect(control.id, 'L1g/10/05');
      expect(control.source, LinkSource.words);
      expect(control.opportunities.theta, 0.10);
      expect(control.certifications.theta, 0.05);
      // No terms: terms need the AI model.
      expect(control.opportunities.termSupport, isFalse);

      expect(Approach.parse('B/03/10/t/bt').gatedControl.id, 'L1g/03/10/t');
      expect(Approach.parse('A/10/05-opp').gatedControl.id, 'L1g/10/05-opp');
      expect(Approach.parse('A/10/05-opp').gatedControl.certifications.enabled,
          isFalse);
      // Without broader links there is no gate to copy: the ungated word
      // control.
      expect(Approach.parse('Bs').gatedControl.id, 'L1');
      expect(Approach.parse('Bs-opp').gatedControl.id, 'L1-opp');
    });
  });

  group('what must be graded', () {
    test('the controls are always pooled, each once', () {
      final development = withControls(
        [Approach.parse('A/10/05'), Approach.parse('A/10/05/p')],
        development: true,
      ).map((a) => a.id);
      expect(development, ['A/10/05', 'A/10/05/p', 'A0', 'M1', 'L1g/10/05']);

      final decision = withControls(
        [Approach.parse('B/10/10/bt')],
        development: false,
      ).map((a) => a.id);
      expect(decision, ['B/10/10/bt', 'A0', 'L1g/10/10']);
    });

    test('a rule cannot be applied while a pair it needs has no grade', () {
      final candidate = Approach.parse('A/10/05');
      final needed = neededFor(candidate, development: false);
      expect(needed, ['A/10/05', 'A0', 'L1g/10/05']);
      expect(neededFor(candidate, development: true), contains('M1'));

      expect(notGradedYet({'A/10/05': 0, 'A0': 0}, needed), isNull);
      // Ungraded pairs of today's matching or of the control block the
      // decision as much as the candidate's own.
      expect(notGradedYet({'A0': 3}, needed), contains('A0 3'));
      expect(notGradedYet({'L1g/10/05': 2}, needed), contains('L1g/10/05 2'));
      // Pairs of an approach the rule does not use do not.
      expect(notGradedYet({'B/10/10/bt': 9}, needed), isNull);
    });
  });

  group('the winner (rule 7.4)', () {
    CandidateResult result(
      String id, {
      bool passes = true,
      double hit = 0.5,
      double uncovered = 0.2,
      int parts = 2,
    }) =>
        CandidateResult(
          id: id,
          passes: passes,
          teachHit: hit,
          falseUncovered: uncovered,
          requests: 1,
          movingParts: parts,
        );

    test('the highest TeachHit wins when the others are not within noise',
        () {
      final picked = pickWinner(
        [result('A/10/05', hit: 0.6), result('B/10/10/bt', hit: 0.5)],
        withinNoise: (a, b) => false,
      );
      expect(picked.winner, 'A/10/05');
    });

    test('within noise, the lower FalseUncovered wins', () {
      final picked = pickWinner(
        [
          result('A/10/05', hit: 0.6, uncovered: 0.3),
          result('B/10/10/bt', hit: 0.58, uncovered: 0.1),
        ],
        withinNoise: (a, b) => true,
      );
      expect(picked.winner, 'B/10/10/bt');
    });

    test('a fallback wins only when its full candidate fails', () {
      expect(
        pickWinner(
          [result('A/10/05', hit: 0.5), result('A/10/05-opp', hit: 0.7)],
          withinNoise: (a, b) => false,
        ).winner,
        'A/10/05',
      );
      expect(
        pickWinner(
          [
            result('A/10/05', passes: false, hit: 0.8),
            result('A/10/05-opp', hit: 0.4),
          ],
          withinNoise: (a, b) => false,
        ).winner,
        'A/10/05-opp',
      );
    });

    test('nothing passes, or a tie the rules cannot break: no winner', () {
      expect(
        pickWinner([result('A/10/05', passes: false)],
                withinNoise: (a, b) => false)
            .winner,
        isNull,
      );
      expect(
        pickWinner([result('A/10/05'), result('B/10/10/bt')],
                withinNoise: (a, b) => true)
            .winner,
        isNull,
      );
    });

    test('moving parts count the catalogues with links and their switches',
        () {
      expect(movingPartsOf(Approach.parse('A0')), 0);
      expect(movingPartsOf(Approach.parse('A/10/05')), 2);
      expect(movingPartsOf(Approach.parse('A/10/05-opp')), 1);
      expect(movingPartsOf(Approach.parse('B/10/10/bt')), 6);
      expect(movingPartsOf(const Approach(
              'x', LinkSource.names, LinkSettings.off, LinkSettings.off)),
          0);
    });
  });

  group('names', () {
    test('a name is excluded by its normalized form and its table form', () {
      // Another spelling of the same name.
      expect(exclusionKeys('Release-Scoping').toSet(),
          exclusionKeys('release scoping').toSet());
      // A synonym of the table shares the table's key.
      expect(
        exclusionKeys('SQL').toSet().intersection(
            exclusionKeys('Databases and SQL').toSet()),
        isNotEmpty,
      );
      // No name is stored in the clear.
      for (final key in exclusionKeys('Roadmap Planning')) {
        expect(key, matches(RegExp(r'^[0-9a-f]{16}$')));
      }
    });

    test('the writers\' names are the "skill" fields, never "alsoCalled"',
        () {
      final folder = Directory.systemTemp.createTempSync('writer_names');
      addTearDown(() => folder.deleteSync(recursive: true));
      File('${folder.path}/manifest.json').writeAsStringSync(jsonEncode({
        'cases': [
          {'id': 'c1', 'careerGoalId': 'product_manager', 'labels': 'c1.labels.json'},
        ],
      }));
      File('${folder.path}/c1.labels.json').writeAsStringSync(jsonEncode({
        'shown': [
          {'skill': 'Roadmap Planning', 'alsoCalled': ['Product Roadmaps']},
        ],
        'notShown': [
          {'skill': 'roadmap planning'},
          {'skill': 'Release Scoping'},
        ],
      }));
      File('${folder.path}/roles.json').writeAsStringSync(jsonEncode({
        'telecom_engineer': [
          {'skill': 'Drive Testing', 'alsoCalled': ['Field Testing']},
        ],
      }));
      expect(writerNamesOf(folder.path), {
        'product_manager': ['Roadmap Planning', 'Release Scoping'],
        'telecom_engineer': ['Drive Testing'],
      });
    });

    test('a sheet the tool looks for by itself may be missing', () {
      expect(readCsv('${Directory.systemTemp.path}/no_such_sheet_here.csv',
              optional: true),
          isEmpty);
    });
  });

  group('the persona guard (rule 7.2 b)', () {
    // nDCG@10, GapCov@10, P@5, TopGapRank.
    const today = [0.8374, 0.933, 1.0, 1.25];
    List<double> withLinks({
      double ndcg = 0.8374,
      double coverage = 0.933,
      double precision = 1.0,
      double rank = 1.25,
    }) =>
        [ndcg, coverage, precision, rank];

    test('thousandths are the numbers as the reports print them', () {
      for (final value in const [
        0.8366, 0.8374, 0.8364, 0.928, 1.2504, 1.2506, 0.0, 1.0,
      ]) {
        expect(thousandths(value),
            (double.parse(value.toStringAsFixed(3)) * 1000).round());
        expect((thousandths(value) / 1000).toStringAsFixed(3),
            value.toStringAsFixed(3));
      }
      expect(thousandths(0.8366), 837);
      expect(thousandths(0.8364), 836);
    });

    test('a loss that 3 decimals do not show fails at full precision only',
        () {
      final values = withLinks(ndcg: 0.8366);
      expect(personaGuardPasses(values, today), isFalse);
      expect(personaGuardPasses(values, today, decimals: 3), isTrue);
    });

    test('a loss that 3 decimals show fails both ways', () {
      final lowerNdcg = withLinks(ndcg: 0.8364);
      expect(personaGuardPasses(lowerNdcg, today), isFalse);
      expect(personaGuardPasses(lowerNdcg, today, decimals: 3), isFalse);

      final lowerCoverage = withLinks(coverage: 0.928);
      expect(personaGuardPasses(lowerCoverage, today), isFalse);
      expect(personaGuardPasses(lowerCoverage, today, decimals: 3), isFalse);

      final lowerPrecision = withLinks(precision: 0.975);
      expect(personaGuardPasses(lowerPrecision, today), isFalse);
      expect(personaGuardPasses(lowerPrecision, today, decimals: 3), isFalse);
    });

    test('TopGapRank must not be higher, read the same two ways', () {
      final slightlyLater = withLinks(rank: 1.2504);
      expect(personaGuardPasses(slightlyLater, today), isFalse);
      expect(personaGuardPasses(slightlyLater, today, decimals: 3), isTrue);

      final later = withLinks(rank: 1.2506);
      expect(personaGuardPasses(later, today), isFalse);
      expect(personaGuardPasses(later, today, decimals: 3), isFalse);

      // Sooner is better.
      expect(personaGuardPasses(withLinks(rank: 1.0), today), isTrue);
      expect(personaGuardPasses(withLinks(rank: 1.0), today, decimals: 3),
          isTrue);
    });

    test('equal and better numbers pass both ways', () {
      expect(personaGuardPasses(withLinks(), today), isTrue);
      expect(personaGuardPasses(withLinks(), today, decimals: 3), isTrue);
      final better = withLinks(ndcg: 0.85, coverage: 0.95);
      expect(personaGuardPasses(better, today), isTrue);
      expect(personaGuardPasses(better, today, decimals: 3), isTrue);
    });

    test('a tolerance widens both readings by the same amount', () {
      final values = withLinks(ndcg: 0.8204);
      expect(personaGuardPasses(values, today, tolerance: 0.02), isTrue);
      expect(personaGuardPasses(values, today, decimals: 3, tolerance: 0.02),
          isTrue);
      final lower = withLinks(ndcg: 0.8164);
      expect(personaGuardPasses(lower, today, tolerance: 0.02), isFalse);
      expect(personaGuardPasses(lower, today, decimals: 3, tolerance: 0.02),
          isFalse);
    });

    test('only full precision and 3 decimals exist', () {
      expect(() => personaGuardPasses(withLinks(), today, decimals: 2),
          throwsArgumentError);
      expect(() => personaGuardPasses(const [1, 1, 1], today),
          throwsArgumentError);
    });

    test('pending only when the best labels would make the guard pass', () {
      expect(guardStatus(passes: true, passesWithBestLabels: true), 'pass');
      expect(guardStatus(passes: false, passesWithBestLabels: true),
          'pending');
      expect(guardStatus(passes: false, passesWithBestLabels: false), 'fail');
    });

    test('the timing limits are compared at full precision', () {
      expect(timingPasses(2.0, 1.10), isTrue);
      // Prints as 1.10, and is over the limit all the same.
      expect(timingPasses(1.5, 1.1004), isFalse);
      expect(timingPasses(2.0004, 1.0), isFalse);
    });
  });

  group('the freeze records what the user decided', () {
    ({Map<String, dynamic>? settings, String? problem}) settings({
      String precision = '3',
      String precisionSource = 'the user chose it in chat',
      String tolerance = '0',
      String toleranceSource = '',
      String? grace = '3',
      String graceSource = 'the user chose it in chat',
      String? writers = 'off',
      String writerSource = 'the user answered no',
      String? earlierGrades,
      List<String> links = const ['dev_links.json', 'heldout_links.json'],
    }) =>
        freezeSettings(
          precision: precision,
          precisionSource: precisionSource,
          tolerance: tolerance,
          toleranceSource: toleranceSource,
          graceSeconds: grace,
          graceSource: graceSource,
          writerNames: writers,
          writerSource: writerSource,
          earlierGrades: earlierGrades,
          personaLinks: links,
          graceInCode: const Duration(seconds: 3),
        );

    test('each decision is frozen with its source', () {
      final frozen = settings().settings!;
      expect(frozen['personaGuard'], {
        'precision': 3,
        'tolerance': 0,
        'source': 'the user chose it in chat',
      });
      expect(frozen['linkGrace'],
          {'seconds': 3, 'source': 'the user chose it in chat'});
      expect(frozen['writerNames'],
          {'use': false, 'source': 'the user answered no'});
      expect(frozen['personaLinkFor'], {
        developmentPersonasFile: 'dev_links.json',
        heldOutPersonasFile: 'heldout_links.json',
      });
      expect(frozen.containsKey('earlierGrades'), isFalse);
      expect(frozenGuard(frozen), (decimals: 3, tolerance: 0.0));
      expect(frozenWriterNames(frozen), isFalse);
      expect(
          freezeSettingProblems(frozen,
              graceInCode: const Duration(seconds: 3)),
          isEmpty);

      // Full precision is the default rule and needs no source.
      final full = settings(precision: 'full', precisionSource: '').settings!;
      expect((full['personaGuard'] as Map)['precision'], 'full');
      expect(frozenGuard(full).decimals, isNull);
      expect(frozenPrecision(full), 'full');
    });

    test('what is refused', () {
      expect(settings(precisionSource: ' ').problem,
          contains('--precision-source'));
      expect(settings(precision: '2').problem, contains('full or 3'));
      expect(settings(tolerance: '0.02').problem,
          contains('--tolerance-source'));
      expect(settings(tolerance: '0.05').problem, contains('0 or 0.02'));
      // The grace must be what the app does, and must be given.
      expect(settings(grace: '5').problem, contains('not what the app does'));
      expect(settings(grace: null).problem, contains('--link-grace-seconds'));
      expect(settings(graceSource: '').problem, contains('--grace-source'));
      expect(settings(writers: null).problem, contains('--writer-names'));
      expect(settings(writers: 'on', writerSource: '').problem,
          contains('--writer-source'));
      expect(settings(writers: 'off', earlierGrades: 'sheet.csv').problem,
          contains('--earlier-grades'));
      // With the writers' names, the earlier sheet's hash goes in.
      expect(settings(writers: 'on', writerSource: 'the user answered yes')
              .problem,
          contains('pass --earlier-grades'));
      expect(settings(links: const ['dev_links.json']).problem,
          contains('exactly two'));
    });

    test('the grace of this round is what the app waits', () {
      // The real code, not a number given by the test.
      expect(
        freezeSettings(
          precision: 'full',
          tolerance: '0',
          graceSeconds: '3',
          graceSource: 'the user chose it in chat',
          writerNames: 'off',
          writerSource: 'the user answered no',
          personaLinks: const ['a.json', 'b.json'],
        ).problem,
        isNull,
      );
    });

    test('a frozen file with a missing or changed decision does not match',
        () {
      List<String> problems(void Function(Map<String, dynamic>) change,
          {int graceInCode = 3}) {
        final frozen = jsonDecode(jsonEncode(settings().settings))
            as Map<String, dynamic>;
        change(frozen);
        return freezeSettingProblems(frozen,
            graceInCode: Duration(seconds: graceInCode));
      }

      expect(problems((f) => f.remove('personaGuard')),
          ['personaGuard (missing)']);
      expect(problems((f) => (f['personaGuard'] as Map)['precision'] = 2),
          ['personaGuard.precision']);
      expect(problems((f) => (f['personaGuard'] as Map)['tolerance'] = 0.05),
          ['personaGuard.tolerance']);
      expect(problems((f) => (f['personaGuard'] as Map)['source'] = ''),
          ['personaGuard.source (missing)']);
      // The code changed after the freeze.
      expect(problems((f) {}, graceInCode: 5).single,
          startsWith('linkGrace.seconds'));
      expect(problems((f) => f.remove('linkGrace')), ['linkGrace (missing)']);
      expect(problems((f) => f.remove('writerNames')),
          ['writerNames (missing)']);
      expect(problems((f) => (f['writerNames'] as Map)['use'] = true).single,
          startsWith('earlierGrades (missing'));
      expect(
          problems((f) => (f['personaLinkFor'] as Map)[heldOutPersonasFile] =
              'dev_links.json'),
          ['personaLinkFor']);
      expect(problems((f) => f.remove('personaLinkFor')), ['personaLinkFor']);
    });

    test('a freeze written to a folder matches until something changes',
        () {
      final folder = Directory.systemTemp.createTempSync('freeze_try');
      addTearDown(() => folder.deleteSync(recursive: true));
      final links = [
        '${folder.path}/dev_links.json',
        '${folder.path}/heldout_links.json',
      ];
      for (final path in links) {
        File(path).writeAsStringSync('{"links": []}');
      }
      final earlier = '${folder.path}/earlier.csv';
      File(earlier).writeAsStringSync('row_id,grade\n');
      final decided = freezeSettings(
        precision: '3',
        precisionSource: 'the user chose it in chat',
        tolerance: '0',
        graceSeconds: '3',
        graceSource: 'the user chose it in chat',
        writerNames: 'on',
        writerSource: 'the user answered yes',
        earlierGrades: earlier,
        personaLinks: links,
      ).settings!;
      final freezeFile = '${folder.path}/freeze.json';
      writeJson(freezeFile, {
        'candidates': ['B/10/10/bt', 'B/10/10/bt-opp'],
        'requests': ['typed'],
        'decisionGoals': decisionGoals,
        'promptExampleGoals': promptExampleGoals,
        'marketRuns': frozenMarketRuns,
        'writerLinkRuns': frozenWriterLinkRuns,
        'seeds': seeds,
        ...decided,
        'hashes': hashesNow(frozenList(decided, 'personaLinks')),
      });
      final frozen = Map<String, dynamic>.from(readJson(freezeFile) as Map);
      expect(freezeDifferences(frozen), isEmpty);
      expect((frozen['earlierGrades'] as Map)['use'], 'report only');
      expect(frozenWriterNames(frozen), isTrue);

      // The earlier sheet is only compared with, but it must stay the file
      // that was recorded.
      File(earlier).writeAsStringSync('row_id,grade\nr1,2\n');
      expect(
          freezeSettingProblems(frozen).single, startsWith('earlierGrades'));
    });
  });

  group('the guard files of the decision', () {
    const sha = 'the-sha-of-the-freeze-file';
    final frozen = <String, dynamic>{
      'personaGuard': {'precision': 3, 'tolerance': 0, 'source': 'user'},
      'personaLinkFor': {
        developmentPersonasFile: 'links/dev.json',
        heldOutPersonasFile: 'links/heldout.json',
      },
      'hashes': {
        'personas': 'p-dev',
        'personasHeldOut': 'p-heldout',
        'personaLinks:links/dev.json': 'l-dev',
        'personaLinks:links/heldout.json': 'l-heldout',
      },
    };
    final full = Approach.parse('B/10/10/bt');
    final fallback = Approach.parse('B/10/10/bt-opp');

    Map<String, dynamic> guard({
      bool heldOut = false,
      Approach? approach,
      String freezeSha = sha,
      Object precision = 3,
      String? links,
      List<double> today = const [0.8374, 0.933, 1.0, 1.25],
      List<double> withLinks = const [0.8369, 0.933, 1.0, 1.25],
      List<double>? todayWithBest,
      List<double>? withBest,
      int unlabelled = 0,
      bool passesWithBestLabels = false,
      bool same = true,
      double firstRatio = 1.02,
    }) {
      final ran = approach ?? full;
      return {
        'freezeFile': 'freeze.json',
        'freezeSha256': freezeSha,
        'approach': ran.id,
        'source': ran.source.name,
        'opportunities': settingKey(ran.source, ran.opportunities),
        'certifications': settingKey(ran.source, ran.certifications),
        'personas': {
          'path': heldOut ? heldOutPersonasFile : developmentPersonasFile,
          'sha256': heldOut ? 'p-heldout' : 'p-dev',
        },
        'links': {
          'path': links ?? (heldOut ? 'links/heldout.json' : 'links/dev.json'),
          'sha256': heldOut ? 'l-heldout' : 'l-dev',
        },
        'precision': precision,
        'tolerance': 0,
        'today': today,
        'withLinks': withLinks,
        'todayWithBestLabels': todayWithBest ?? today,
        'withBestLabels': withBest ?? withLinks,
        'unlabelled': unlabelled,
        'passesWithBestLabels': passesWithBestLabels,
        'sameWithoutLinks': same,
        'certificationListsSame': true,
        'warmRatio': 1.3,
        'firstRatio': firstRatio,
      };
    }

    List<String> problemsOf(Map<String, dynamic> file) =>
        guardFileProblems(file, frozen: frozen, freezeSha: sha);

    test('a file of this freeze, at its precision, on a frozen pair is taken',
        () {
      expect(problemsOf(guard()), isEmpty);
      expect(problemsOf(guard(heldOut: true)), isEmpty);
    });

    test('a file of another freeze, precision or pair is refused', () {
      expect(problemsOf(guard(freezeSha: 'another')).single,
          contains('another freeze'));
      expect(
          problemsOf(guard(precision: 'full')).single, contains('precision'));
      // The development personas with the held-out links.
      expect(problemsOf(guard(links: 'links/heldout.json')),
          anyElement(contains('not the frozen link file')));
      final otherPersonas = guard()
        ..['personas'] = {'path': 'other_personas.json', 'sha256': 'p-dev'};
      expect(problemsOf(otherPersonas).single,
          contains('not a frozen persona file'));
      final changedPersonas = guard()
        ..['personas'] = {'path': developmentPersonasFile, 'sha256': 'edited'};
      expect(problemsOf(changedPersonas).single,
          contains('not the frozen content'));
    });

    test(
        'a candidate needs one file per persona file, run with its own '
        'opportunity settings', () {
      final both = {'dev.json': guard(), 'heldout.json': guard(heldOut: true)};
      final found = guardFilesFor(full, both, frozen: frozen, freezeSha: sha);
      expect(found.problems, isEmpty);
      expect(found.files, hasLength(2));

      // One persona file missing.
      expect(
        guardFilesFor(full, {'dev.json': guard()},
                frozen: frozen, freezeSha: sha)
            .problems
            .single,
        contains(heldOutPersonasFile),
      );
      // Run with another opportunity setting.
      final other = Approach.parse('B/05/10/bt');
      expect(
        guardFilesFor(
          full,
          {
            'dev.json': guard(approach: other),
            'heldout.json': guard(heldOut: true),
          },
          frozen: frozen,
          freezeSha: sha,
        ).problems.single,
        contains('exactly one guard file'),
      );
      // The same persona file twice.
      expect(
        guardFilesFor(full, {...both, 'again.json': guard()},
                frozen: frozen, freezeSha: sha)
            .problems,
        isNotEmpty,
      );
    });

    test('the fallback takes the guard runs of its full candidate', () {
      final both = {'dev.json': guard(), 'heldout.json': guard(heldOut: true)};
      final found =
          guardFilesFor(fallback, both, frozen: frozen, freezeSha: sha);
      expect(found.problems, isEmpty);
      expect(found.files.map((file) => file['approach']),
          ['B/10/10/bt', 'B/10/10/bt']);
      // Not the other way round: the certification lists of the full
      // candidate must be checked with its own certification settings.
      final fallbackRuns = {
        'dev.json': guard(approach: fallback),
        'heldout.json': guard(heldOut: true, approach: fallback),
      };
      expect(
        guardFilesFor(full, fallbackRuns, frozen: frozen, freezeSha: sha)
            .problems,
        isNotEmpty,
      );
    });

    test('the verdict is computed from the numbers, at the frozen reading',
        () {
      GuardVerdict verdict(List<Map<String, dynamic>> files,
              {int? decimals = 3}) =>
          guardVerdictOf(files, decimals: decimals, tolerance: 0);

      // 0.8369 against 0.8374: equal at 3 decimals, lower at full precision.
      final files = [guard(), guard(heldOut: true)];
      expect(verdict(files).passes, isTrue);
      expect(verdict(files).personaStatus, 'pass');
      expect(verdict(files, decimals: null).personaStatus, 'fail');
      expect(verdict(files).lines, hasLength(2));

      // A real loss on one file.
      final loss = [
        guard(),
        guard(heldOut: true, withLinks: const [0.80, 0.933, 1.0, 1.25]),
      ];
      expect(verdict(loss).personaStatus, 'fail');
      expect(verdict(loss).passes, isFalse);

      // The same loss when labels for the new items would close it: both
      // sides scored again with the best labels.
      final waiting = [
        guard(),
        guard(
          heldOut: true,
          withLinks: const [0.80, 0.933, 1.0, 1.25],
          todayWithBest: const [0.8102, 0.933, 1.0, 1.25],
          withBest: const [0.8113, 0.95, 1.0, 1.25],
          unlabelled: 2,
          passesWithBestLabels: true,
        ),
      ];
      expect(verdict(waiting).personaStatus, 'pending');
      expect(verdict(waiting).passes, isFalse);
      expect(verdict(waiting).onlyPending, isTrue);
      // With nothing to label, a file cannot claim to be pending.
      final claimed = [
        guard(
            withLinks: const [0.80, 0.933, 1.0, 1.25],
            withBest: const [0.85, 0.933, 1.0, 1.25],
            passesWithBestLabels: true),
      ];
      expect(verdict(claimed).personaStatus, 'fail');
      // Nor can a file whose best-label numbers do not pass.
      final notByItsNumbers = [
        guard(
          withLinks: const [0.80, 0.933, 1.0, 1.25],
          todayWithBest: const [0.8302, 0.933, 1.0, 1.25],
          withBest: const [0.8113, 0.933, 1.0, 1.25],
          unlabelled: 1,
          passesWithBestLabels: true,
        ),
      ];
      expect(verdict(notByItsNumbers).personaStatus, 'fail');
      // Today's side is scored with the new labels too: the same numbers
      // with links pass against today's lower number.
      final todayFalls = [
        guard(
          withLinks: const [0.80, 0.933, 1.0, 1.25],
          todayWithBest: const [0.8052, 0.933, 1.0, 1.25],
          withBest: const [0.8113, 0.933, 1.0, 1.25],
          unlabelled: 1,
        ),
      ];
      expect(verdict(todayFalls).personaStatus, 'pending');
      // A failing file is not hidden by a pending one.
      expect(verdict([...waiting, ...loss]).personaStatus, 'fail');

      // 7.2 (a) and (d).
      expect(verdict([guard(same: false)]).sameWithoutLinks, isFalse);
      expect(verdict([guard(firstRatio: 1.1004)]).timing, isFalse);
      expect(verdict([guard(firstRatio: 1.1004)]).onlyPending, isFalse);
      expect(verdict(const []).passes, isFalse);
    });

    test('pending names no winner only for a candidate that passes the rest',
        () {
      final pending = guardVerdictOf(
        [
          guard(
            withLinks: const [0.80, 0.933, 1.0, 1.25],
            withBest: const [0.8402, 0.933, 1.0, 1.25],
            unlabelled: 1,
            passesWithBestLabels: true,
          ),
        ],
        decimals: 3,
        tolerance: 0,
      );
      final guards = {'B/10/10/bt': pending, 'B/10/10/bt-opp': pending};
      expect(
        pendingCandidates(
            {'B/10/10/bt': true, 'B/10/10/bt-opp': false}, guards),
        ['B/10/10/bt'],
      );
      expect(
        pendingCandidates(
            {'B/10/10/bt': false, 'B/10/10/bt-opp': false}, guards),
        isEmpty,
      );
    });

    test('a file without the numbers of a verdict is refused', () {
      final both = {
        'dev.json': guard()..remove('todayWithBestLabels'),
        'heldout.json': guard(heldOut: true)..['firstRatio'] = '1.02',
      };
      final problems =
          guardFilesFor(full, both, frozen: frozen, freezeSha: sha).problems;
      expect(problems, hasLength(2));
      expect(problems, anyElement(contains('todayWithBestLabels')));
      expect(problems, anyElement(contains('firstRatio')));
    });

    test('a guard file is written once, at the frozen precision', () {
      final folder = Directory.systemTemp.createTempSync('guard_json');
      addTearDown(() => folder.deleteSync(recursive: true));
      final path = '${folder.path}/dev.json';
      String? problem(String path, {String precision = '3'}) =>
          guardJsonProblem(path,
              precision: precision,
              personasPath: developmentPersonasFile,
              frozen: frozen);
      expect(problem(path), isNull);
      expect(problem(path, precision: 'full'), contains('--guard-precision 3'));
      writeJson(path, guard());
      expect(problem(path), contains('already exists'));
      // A second run of the same personas under another name, next to it.
      expect(problem('${folder.path}/dev2.json'),
          contains('already holds the guard'));
      // The other persona file has no guard there yet.
      expect(
        guardJsonProblem('${folder.path}/heldout.json',
            precision: '3', personasPath: heldOutPersonasFile, frozen: frozen),
        isNull,
      );
      // Never into the earlier run's folder, not even a new sub-folder.
      expect(problem('build/gap_eval/final_r2/guards_new/dev.json'),
          contains('only ever read'));
    });

    test('a guard is run as a frozen candidate, the fallback as its full one',
        () {
      final freeze = {
        ...frozen,
        'candidates': ['B/10/10/bt', 'B/10/10/bt-opp'],
      };
      expect(guardApproachProblem(full, freeze), isNull);
      expect(guardApproachProblem(fallback, freeze),
          contains('Run the guard as B/10/10/bt'));
      expect(guardApproachProblem(Approach.parse('B/05/10/bt'), freeze),
          contains('not a frozen candidate'));
      expect(guardApproachProblem(Approach.parse('A0'), freeze),
          contains('not a frozen candidate'));
      // A frozen fallback without its full candidate is run as itself.
      expect(
          guardApproachProblem(fallback, {
            ...frozen,
            'candidates': ['B/10/10/bt-opp'],
          }),
          isNull);
      // One run of the full candidate serves both.
      expect(candidatesServedBy(guard(), freeze),
          ['B/10/10/bt', 'B/10/10/bt-opp']);
      expect(candidatesServedBy(guard(approach: fallback), freeze),
          ['B/10/10/bt-opp']);
    });

    test('the decision takes guard files only from the run\'s guards folder',
        () {
      final folder = Directory.systemTemp.createTempSync('guards_folder');
      addTearDown(() => folder.deleteSync(recursive: true));
      final run = '${folder.path}/final_run';
      final guards = guardsFolderOf(run);
      writeJson('$guards/dev.json', guard());
      writeJson('$guards/heldout.json', guard(heldOut: true));
      File('$guards/dev.txt').writeAsStringSync('printed output');
      final paths = ['$guards/dev.json', '$guards/heldout.json'];
      expect(guardInputProblem(paths, runFolder: run), isNull);
      expect(guardsFolderOf('$run/'), guards);

      // From somewhere else.
      writeJson('${folder.path}/elsewhere/dev.json', guard());
      expect(
        guardInputProblem(
            ['${folder.path}/elsewhere/dev.json', '$guards/heldout.json'],
            runFolder: run),
        contains('elsewhere'),
      );
      // A JSON file that is not a guard file does not count.
      writeJson('$guards/notes.json', {'note': 'not a guard'});
      expect(guardInputProblem(paths, runFolder: run), isNull);
      // The guard run again under another name: neither file is used,
      // whichever is passed.
      writeJson('$guards/dev2.json', guard());
      expect(personaFilesGuardedTwice(guards), [developmentPersonasFile]);
      expect(guardInputProblem(paths, runFolder: run),
          contains('more than one guard file'));
      expect(
        guardInputProblem(['$guards/dev2.json', '$guards/heldout.json'],
            runFolder: run),
        contains('more than one guard file'),
      );
    });
  });

  group('what the decision accepts', () {
    Map<String, dynamic> frozen({required bool writers}) => {
          'writerNames': {'use': writers, 'source': 'user'},
        };

    test('graded sheets only from the judgements folder of the run', () {
      final folder = Directory.systemTemp.createTempSync('decision_run');
      addTearDown(() => folder.deleteSync(recursive: true));
      final run = '${folder.path}/final_run';
      writeJson(runMarkerPath(run), {'freezeSha256': 'sha-1'});
      String? problem(List<String> sheets) => decisionInputProblem(
            frozen(writers: false),
            writerNames: false,
            runFolder: run,
            freezeSha: 'sha-1',
            sheets: sheets,
          );
      expect(problem(['$run/judgements/teaching.csv']), isNull);
      expect(problem(const []), isNull);
      expect(problem(['${folder.path}/earlier_run/judgements/teaching.csv']),
          contains('earlier_run'));
      // Next to the folder, or reached through it and out again.
      expect(problem(['$run/teaching.csv']), isNotNull);
      expect(problem(['$run/judgements/../../other/teaching.csv']), isNotNull);
      expect(
        problem([
          '$run/judgements/teaching.csv',
          '${folder.path}/second.csv',
        ]),
        contains('second.csv'),
      );
    });

    test('the writers\' names exactly when the freeze says so', () {
      final folder = Directory.systemTemp.createTempSync('decision_writers');
      addTearDown(() => folder.deleteSync(recursive: true));
      final run = '${folder.path}/run';
      writeJson(runMarkerPath(run), {'freezeSha256': 'sha-1'});
      String? problem({required bool frozenUse, required bool passed}) =>
          decisionInputProblem(
            frozen(writers: frozenUse),
            writerNames: passed,
            runFolder: run,
            freezeSha: 'sha-1',
            sheets: const [],
          );
      expect(problem(frozenUse: false, passed: true), contains('refused'));
      expect(problem(frozenUse: true, passed: false),
          contains('pass --writer-names'));
      expect(problem(frozenUse: true, passed: true), isNull);
      expect(problem(frozenUse: false, passed: false), isNull);
    });

    test('only on a run folder the measurement started under this freeze',
        () {
      final folder = Directory.systemTemp.createTempSync('decision_marker');
      addTearDown(() => folder.deleteSync(recursive: true));
      String? problem(String run) => decisionInputProblem(
            frozen(writers: false),
            writerNames: false,
            runFolder: run,
            freezeSha: 'sha-1',
            sheets: const [],
          );
      final empty = '${folder.path}/empty';
      Directory(empty).createSync();
      expect(problem(empty), contains('has no run.json'));
      final other = '${folder.path}/other';
      writeJson(runMarkerPath(other), {'freezeSha256': 'sha-2'});
      expect(problem(other), contains('another freeze'));
      final started = '${folder.path}/started';
      writeJson(runMarkerPath(started), {'freezeSha256': 'sha-1'});
      expect(problem(started), isNull);
      expect(problem('$started/'), isNull);
    });

    test('a run folder that another run started is never written', () {
      final folder = Directory.systemTemp.createTempSync('run_marker');
      addTearDown(() => folder.deleteSync(recursive: true));
      // New, or holding only the guard output of this run: fine.
      expect(runFolderProblem('${folder.path}/new', 'sha-1'), isNull);
      final started = '${folder.path}/started';
      Directory('$started/guards').createSync(recursive: true);
      expect(runFolderProblem(started, 'sha-1'), isNull);
      // Stored answers and no marker: the folder of another run.
      final earlier = '${folder.path}/earlier';
      Directory('$earlier/raw/market').createSync(recursive: true);
      expect(runFolderProblem(earlier, 'sha-1'), contains('another run'));
      // A marker of this freeze lets the same command continue the run;
      // a marker of another freeze does not.
      writeJson(runMarkerPath(earlier), {'freezeSha256': 'sha-1'});
      expect(runFolderProblem(earlier, 'sha-1'), isNull);
      expect(runFolderProblem(earlier, 'sha-2'), contains('another freeze'));
    });

    test('nothing is ever written into the earlier run\'s folder', () {
      // Paths only: the folder itself is not opened.
      expect(earlierRunWriteProblem('build/gap_eval/final_r2'), isNotNull);
      expect(earlierRunWriteProblem('build/gap_eval/final_r2/'), isNotNull);
      expect(earlierRunWriteProblem('build/gap_eval/final_r2/new/review'),
          contains('only ever read'));
      expect(runFolderProblem('build/gap_eval/final_r2/new', 'sha-1'),
          contains('only ever read'));
      expect(earlierRunWriteProblem('build/gap_eval/final_r3'), isNull);
      expect(earlierRunWriteProblem('build/gap_eval/final_r2_copy'), isNull);
    });
  });

  group('the check of the shipped code', () {
    test('APP reads the constants of the app', () {
      final app = Approach.parse('APP');
      expect(app.id, Approach.appId);
      expect(
          identical(app.opportunities, LinkSettings.appOpportunities), isTrue);
      expect(identical(app.certifications, LinkSettings.appCertifications),
          isTrue);
      expect(app.source, Approach.appSource);
    });

    // This test changes at switch-on (plan section 6, "Tests that must
    // change"): it then expects the winner's settings and source, and
    // isControl false.
    test('while the app sends no link request, APP is the matching of today',
        () {
      final app = Approach.parse('APP');
      final today = Approach.parse('A0');
      expect(LinkSettings.requestedByApp, isFalse);
      expect(app.source, LinkSource.none);
      expect(app.opportunities.enabled, isFalse);
      expect(app.certifications.enabled, isFalse);
      for (final type in const ['opportunity', 'certification']) {
        expect(settingKey(app.source, app.settingsFor(type)),
            settingKey(today.source, today.settingsFor(type)));
      }
      // It is compared with, never chosen, and never frozen.
      expect(isControl(app), isTrue);
    });
  });

  group('the timing amendment (rule 7.2 d)', () {
    test('the median of 5 runs decides, at full precision', () {
      final verdict = amendedTimingVerdict(
          const [1.3, 1.2, 1.1, 1.0, 1.9], const [1.02, 1.15, 0.98, 1.08, 1.12]);
      expect(verdict.warm, 1.2);
      expect(verdict.first, 1.08);
      expect(verdict.passes, isTrue);

      const warm = [1.0, 1.0, 1.0, 1.0, 1.0];
      // The limit itself is included.
      final atLimit =
          amendedTimingVerdict(warm, const [1.10, 1.10, 1.10, 1.2, 0.9]);
      expect(atLimit.first, 1.10);
      expect(atLimit.passes, isTrue);
      // Just over the limit fails, although it prints as 1.1000.
      final over =
          amendedTimingVerdict(warm, const [1.0, 1.0, 1.1000001, 1.2, 1.3]);
      expect(over.first, 1.1000001);
      expect(over.first.toStringAsFixed(4), '1.1000');
      expect(over.passes, isFalse);

      const first = [1.0, 1.0, 1.0, 1.0, 1.0];
      expect(
          amendedTimingVerdict(const [1.0, 2.0, 2.0, 2.5, 1.5], first).passes,
          isTrue);
      expect(
          amendedTimingVerdict(const [1.0, 2.0000001, 2.0, 2.5, 2.5], first)
              .passes,
          isFalse);

      // The order of the runs does not matter, and the lists are not
      // changed.
      const shuffled = [1.08, 1.12, 1.02, 0.98, 1.15];
      final again =
          amendedTimingVerdict(const [1.9, 1.0, 1.2, 1.3, 1.1], shuffled);
      expect(again, verdict);
      expect(shuffled, const [1.08, 1.12, 1.02, 0.98, 1.15]);
    });

    test('one slow run does not decide, three do', () {
      const warm = [1.0, 1.0, 1.0, 1.0, 1.0];
      expect(
          amendedTimingVerdict(warm, const [1.25, 1.0, 1.0, 1.0, 1.0]).passes,
          isTrue);
      expect(
          amendedTimingVerdict(warm, const [1.25, 1.2, 1.15, 1.0, 1.0]).passes,
          isFalse);
    });

    test('only 5 runs of each kind', () {
      const five = [1.0, 1.0, 1.0, 1.0, 1.0];
      const four = [1.0, 1.0, 1.0, 1.0];
      const six = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0];
      expect(() => amendedTimingVerdict(four, four), throwsArgumentError);
      expect(() => amendedTimingVerdict(six, six), throwsArgumentError);
      expect(() => amendedTimingVerdict(five, four), throwsArgumentError);
      expect(() => amendedTimingVerdict(six, five), throwsArgumentError);
      expect(amendedTimingRuns, 5);
    });
  });

  group('the amendment of the freeze', () {
    test('the amendment lies next to its freeze', () {
      expect(amendmentFileOf('x/freeze_r2.json'),
          'x/freeze_r2_amendment_timing.json');
      expect(amendmentFileOf(defaultFreezeFile),
          'tools/gap_eval/freeze_r2_amendment_timing.json');
    });

    test(
        'an amendment of this freeze lets the amended tools match, and '
        'nothing else', () {
      final freeze = _RealFreeze();
      addTearDown(freeze.delete);
      expect(freezeDifferences(freeze.frozen), ['gapEvalTools']);
      final amendment = freeze.amendment();
      expect(
          amendmentProblems(amendment,
              frozen: freeze.frozen,
              freezeSha: freeze.sha,
              freezeFile: freeze.file),
          isEmpty);
      expect(freeze.differences(amendment), isEmpty);
      expect((amendment['toolHashes'] as Map)['gapEvalTools'],
          {'frozen': 'old-tools', 'amended': freeze.toolsNow});
      expect(amendment['candidate'], 'B/10/10/bt');
      expect(amendment['timingFiles'], {
        developmentPersonasFile: '${freeze.guards}/timing_dev.json',
        heldOutPersonasFile: '${freeze.guards}/timing_heldout.json',
      });
      expect(amendedGuardsFolderOf(amendment), freeze.guards);

      // Once it is written next to the freeze, every freeze check reads it.
      expect(readAmendment(freeze.file), isNull);
      expect(amendmentLine(freeze.file), isNull);
      writeJson(amendmentFileOf(freeze.file), amendment);
      expect(readAmendment(freeze.file), amendment);
      expect(
          amendmentLine(freeze.file),
          'Amendment 1 of rule 7.2 (d) matches '
          '(${amendmentFileOf(freeze.file)}, sha256 '
          '${amendmentShaOf(freeze.file)}).');
    });

    test('what the amendment does not excuse', () {
      final freeze = _RealFreeze();
      addTearDown(freeze.delete);
      Map<String, dynamic> changed(void Function(Map<String, dynamic>) change) {
        final copy =
            jsonDecode(jsonEncode(freeze.amendment())) as Map<String, dynamic>;
        change(copy);
        return copy;
      }

      List<String> problems(void Function(Map<String, dynamic>) change,
              {String? freezeSha, String? freezeFile}) =>
          amendmentProblems(changed(change),
              frozen: freeze.frozen,
              freezeSha: freezeSha ?? freeze.sha,
              freezeFile: freezeFile ?? freeze.file);

      // Another change is still listed, next to nothing else.
      final otherServices =
          jsonDecode(jsonEncode(freeze.frozen)) as Map<String, dynamic>;
      (otherServices['hashes'] as Map)['services'] = 'changed';
      expect(
          freezeDifferences(otherServices,
              amendment: freeze.amendment(),
              freezeSha: freeze.sha,
              freezeFile: freeze.file),
          ['services']);
      // The amended tools must be the tools of now.
      expect(freeze.differences(freeze.amendment(amendedTools: 'b' * 64)),
          ['gapEvalTools']);
      // What is wrong with the amendment stops the freeze check too.
      expect(freeze.differences(changed((a) => a['runs'] = 3)),
          ['amendment: runs is not 5']);

      expect(problems((a) {}), isEmpty);
      expect(problems((a) {}, freezeSha: 'another').single,
          contains('freezeSha256'));
      expect(problems((a) {}, freezeFile: 'other/freeze.json').single,
          contains('freezeFile'));
      expect(problems((a) => a['amendment'] = 2), ['amendment is not 1']);
      expect(problems((a) => a['rule'] = '7.2 (b)'), ['rule is not 7.2 (d)']);
      expect(problems((a) => a['text'] = '${a['text']} Or twice.').single,
          contains('text'));
      expect(problems((a) => a['runs'] = 3), ['runs is not 5']);
      expect(problems((a) => a['statistic'] = 'mean'),
          ['statistic is not median']);
      expect(problems((a) => a['warmLimit'] = 2.5).single,
          contains('warmLimit'));
      expect(problems((a) => a['firstLimit'] = 1.2).single,
          contains('firstLimit'));
      expect(problems((a) => a['comparedAt'] = '3 decimals').single,
          contains('comparedAt'));
      expect(problems((a) => a['source'] = '  '), ['source (missing)']);
      expect(problems((a) => a['candidate'] = 'B/10/10/bt-opp').single,
          contains('fallback'));
      expect(problems((a) => a['candidate'] = 'A/10/05').single,
          contains('not a frozen candidate'));
      expect(
          problems((a) => ((a['toolHashes'] as Map)['gapEvalTools']
              as Map)['frozen'] = 'other-tools').single,
          contains('toolHashes.gapEvalTools.frozen'));
      expect(
          problems((a) => ((a['toolHashes'] as Map)['gapEvalTools']
              as Map)['amended'] = 'not a hash').single,
          contains('toolHashes.gapEvalTools.amended'));
      expect(
          problems((a) => (a['timingFiles'] as Map).remove(heldOutPersonasFile))
              .single,
          contains('timingFiles'));
      expect(
          problems((a) => (a['timingFiles'] as Map)[developmentPersonasFile] =
              '${freeze.root}/elsewhere/timing_dev.json').single,
          contains('timingFiles of $developmentPersonasFile'));
      expect(
          problems((a) => (a['guardFiles'] as Map).remove(heldOutPersonasFile)),
          contains(contains('guardFiles')));

      // A recorded guard file that changed after the amendment was written.
      final before = freeze.amendment();
      writeJson('${freeze.guards}/dev.json',
          freeze.guard()..['withLinks'] = [0.9, 0.933, 1.0, 1.25]);
      expect(
          amendmentProblems(before,
              frozen: freeze.frozen,
              freezeSha: freeze.sha,
              freezeFile: freeze.file).single,
          contains('changed since the amendment was written'));
      File('${freeze.guards}/dev.json').deleteSync();
      expect(
          amendmentProblems(before,
              frozen: freeze.frozen,
              freezeSha: freeze.sha,
              freezeFile: freeze.file).single,
          contains('is missing'));
    });

    test('written once, and only over the amended tools', () {
      final freeze = _RealFreeze();
      addTearDown(freeze.delete);
      final amendmentFile = amendmentFileOf(freeze.file);
      String? problem({
        Map<String, dynamic>? frozen,
        Map<String, Map<String, dynamic>>? guards,
        String source = 'the user agreed in chat',
      }) =>
          amendmentWriteProblem(
            amendmentFile: amendmentFile,
            frozen: frozen ?? freeze.frozen,
            freezeSha: freeze.sha,
            guards: guards ?? freeze.guardFiles,
            source: source,
          );

      expect(problem(), isNull);
      // A freeze that matches as it is needs no excuse, and gets none for
      // anything else.
      final otherServices =
          jsonDecode(jsonEncode(freeze.frozen)) as Map<String, dynamic>;
      (otherServices['hashes'] as Map)['services'] = 'changed';
      expect(problem(frozen: otherServices), contains('services'));

      final dev = '${freeze.guards}/dev.json';
      final heldOut = '${freeze.guards}/heldout.json';
      expect(problem(guards: {dev: freeze.guard()}),
          contains('exactly one guard file for $heldOutPersonasFile'));
      expect(
          problem(guards: {
            ...freeze.guardFiles,
            '${freeze.guards}/again.json': freeze.guard(),
          }),
          contains('exactly one guard file for $developmentPersonasFile'));
      expect(
          problem(guards: {
            dev: freeze.guard(approach: 'B/10/10/bt-opp'),
            heldOut: freeze.guard(heldOut: true),
          }),
          contains('its approach is B/10/10/bt-opp'));
      expect(
          problem(guards: {
            dev: freeze.guard(approach: 'A/10/05'),
            heldOut: freeze.guard(heldOut: true),
          }),
          contains('its approach is A/10/05'));
      expect(
          problem(guards: {
            dev: freeze.guard(freezeSha: 'another'),
            heldOut: freeze.guard(heldOut: true),
          }),
          contains('another freeze'));
      expect(
          problem(guards: {
            dev: freeze.guard(),
            heldOut: freeze.guard(heldOut: true)..remove('today'),
          }),
          contains('today is not a list of four numbers'));
      expect(
          problem(guards: {
            dev: freeze.guard(),
            heldOut: freeze.guard(
                heldOut: true, withLinks: const [0.80, 0.933, 1.0, 1.25]),
          }),
          contains('persona guard fail'));
      expect(
          problem(guards: {
            dev: freeze.guard()..['sameWithoutLinks'] = false,
            heldOut: freeze.guard(heldOut: true),
          }),
          contains('without links as today NO'));
      expect(problem(source: ' \n'), contains('source file is empty'));
      expect(problem(source: 'agreed \u2713'), contains('printable ASCII'));

      // Written once.
      writeJson(amendmentFile, freeze.amendment());
      expect(problem(), contains('already exists'));
    });
  });

  group('the timing files', () {
    const passWarm = [1.3, 1.2, 1.1, 1.0, 1.9];
    const passFirst = [1.02, 1.15, 0.98, 1.08, 1.12];
    const failFirst = [1.25, 1.2, 1.15, 1.0, 1.0];

    test('five runs, one after another, each in its own process and folder',
        () async {
      final fixture = _TimingFixture();
      addTearDown(fixture.delete);
      final result = await fixture.measure(developmentPersonasFile,
          warm: passWarm, first: passFirst);
      expect(result.refusal, isNull);
      expect(fixture.calls, [
        for (var run = 1; run <= 5; run++)
          [
            'run',
            'tools/recommender_eval/evaluate_recommender.dart',
            '--personas',
            developmentPersonasFile,
            '--links',
            'links/dev.json',
            '--approach',
            'B/10/10/bt',
            '--guard-precision',
            '3',
            '--guard-json',
            '${fixture.guards}/timing_runs/dev_$run/guard.json',
            '--freeze-file',
            'freeze.json',
          ],
      ]);
      expect(fixture.log, [
        for (var run = 1; run <= 5; run++) 'run $run of 5 finished, exit 0',
      ]);

      final path = '${fixture.guards}/timing_dev.json';
      expect(result.timingPath, path);
      final file = fixture.read(path);
      expect(file, jsonDecode(jsonEncode(result.file)));
      expect(file['kind'], 'timing, rule 7.2 (d), amendment 1');
      expect(file['label'], 'dev');
      expect(file['warmRatios'], passWarm);
      expect(file['firstRatios'], passFirst);
      expect(file['warmMedian'], 1.2);
      expect(file['firstMedian'], 1.08);
      expect(file['warmLimit'], 2.0);
      expect(file['firstLimit'], 1.1);
      expect(file['comparedAt'], 'full precision');
      expect(file['status'], 'pass');
      expect(file['freezeSha256'], _TimingFixture.sha);
      expect(file['amendmentSha256'], _TimingFixture.amendmentSha);
      expect(file['guardFile'], {
        'path': '${fixture.guards}/dev.json',
        'sha256': timingShaOf('${fixture.guards}/dev.json'),
      });
      expect(file['measured'], {
        'personas': {'path': developmentPersonasFile, 'sha256': 'p-dev'},
        'links': {'path': 'links/dev.json', 'sha256': 'l-dev'},
      });
      expect(file['approach'], 'B/10/10/bt');
      expect(file['personaSameAsGuard'], isTrue);
      expect(file['stopReason'], isNull);
      final runs = file['runs'] as List;
      expect(runs, hasLength(5));
      for (var i = 0; i < 5; i++) {
        final run = runs[i] as Map;
        final runFile = '${fixture.guards}/timing_runs/dev_${i + 1}/guard.json';
        expect(run['run'], i + 1);
        expect(run['file'], runFile);
        expect(run['sha256'], timingShaOf(runFile));
        expect(run['exitCode'], 0);
        expect(run['warmRatio'], passWarm[i]);
        expect(run['firstRatio'], passFirst[i]);
      }
      // It is not a guard file: it has no persona file at its top level.
      expect(file.containsKey('personas'), isFalse);
      expect(fixture.problemsOf(developmentPersonasFile), isEmpty);

      // Three slow first calls fail it; the file says so and is usable.
      final slow = _TimingFixture();
      addTearDown(slow.delete);
      final failed = await slow.measure(developmentPersonasFile,
          warm: passWarm, first: failFirst);
      expect(failed.file!['status'], 'fail');
      expect(failed.file!['firstMedian'], 1.15);
      expect(failed.file!['stopReason'], isNull);
      expect(slow.problemsOf(developmentPersonasFile), isEmpty);
    });

    test('measured once', () async {
      final fixture = _TimingFixture();
      addTearDown(fixture.delete);
      await fixture.measure(developmentPersonasFile);
      expect(fixture.calls, hasLength(5));
      final again = await fixture.measure(developmentPersonasFile);
      expect(again.refusal, contains('already exists'));
      expect(again.refusal, contains('measured once'));
      expect(again.file, isNull);
      expect(fixture.calls, hasLength(5));

      // One run folder alone means it was started before.
      final started = _TimingFixture();
      addTearDown(started.delete);
      Directory('${started.guards}/timing_runs/dev_1')
          .createSync(recursive: true);
      expect((await started.measure(developmentPersonasFile)).refusal,
          contains('was started before'));
      expect(started.calls, isEmpty);

      // Anything unexpected in the guards folder.
      final extra = _TimingFixture();
      addTearDown(extra.delete);
      writeJson('${extra.guards}/extra.json', {'note': 'not expected'});
      expect((await extra.measure(developmentPersonasFile)).refusal,
          contains('extra.json is not expected there'));
      expect(extra.calls, isEmpty);

      // The held-out file only after a usable development result.
      final order = _TimingFixture();
      addTearDown(order.delete);
      expect((await order.measure(heldOutPersonasFile)).refusal,
          contains('measured first'));
      expect(order.calls, isEmpty);
      await order.measure(developmentPersonasFile, failAt: 1);
      expect(order.calls, hasLength(1));
      expect((await order.measure(heldOutPersonasFile)).refusal,
          contains('holds no usable result'));
      expect(order.calls, hasLength(1));

      // A development result that fails is a result: held-out is measured.
      final both = _TimingFixture();
      addTearDown(both.delete);
      await both.measure(developmentPersonasFile, first: failFirst);
      final heldOut = await both.measure(heldOutPersonasFile);
      expect(heldOut.refusal, isNull);
      expect(heldOut.file!['label'], 'heldout');
      expect(both.calls, hasLength(10));
      expect(both.calls.last[both.calls.last.indexOf('--links') + 1],
          'links/heldout.json');

      // A persona file that is not frozen.
      expect((await both.measure('test/fixtures/other.json')).refusal,
          contains('not a frozen persona file'));

      // A dry run applies the checks and creates nothing.
      final dry = _TimingFixture();
      addTearDown(dry.delete);
      final planned = await dry.measure(developmentPersonasFile, dryRun: true);
      expect(planned.refusal, isNull);
      expect(planned.file, isNull);
      expect(planned.commands, hasLength(5));
      expect(planned.links, 'links/dev.json');
      expect(planned.timingPath, '${dry.guards}/timing_dev.json');
      expect(dry.calls, isEmpty);
      expect(Directory('${dry.guards}/timing_runs').existsSync(), isFalse);
      expect(File('${dry.guards}/timing_dev.json').existsSync(), isFalse);
      expect((await dry.measure(heldOutPersonasFile, dryRun: true)).refusal,
          contains('measured first'));
    });

    test('a run that fails ends the measurement', () async {
      final fixture = _TimingFixture();
      addTearDown(fixture.delete);
      final result = await fixture.measure(developmentPersonasFile, failAt: 3);
      expect(fixture.calls, hasLength(3));
      final file = fixture.read('${fixture.guards}/timing_dev.json');
      expect(file, jsonDecode(jsonEncode(result.file)));
      expect(file['status'], 'incomplete');
      expect(file['stopReason'], 'run 3: it ended with exit code 1');
      expect(file['personaSameAsGuard'], isTrue);
      expect(file['warmMedian'], isNull);
      expect(file['firstMedian'], isNull);
      final runs = file['runs'] as List;
      expect(runs, hasLength(3));
      expect((runs[2] as Map)['exitCode'], 1);
      expect((runs[2] as Map).containsKey('warmRatio'), isFalse);
      expect((runs[2] as Map).containsKey('firstRatio'), isFalse);
      expect(file['warmRatios'], hasLength(2));
      expect(fixture.problemsOf(developmentPersonasFile),
          contains(contains('its status is incomplete')));

      // A run that leaves no guard file, or no ratio, ends it the same way.
      final silent = _TimingFixture();
      addTearDown(silent.delete);
      final none = await silent.measure(developmentPersonasFile, writeNoFileAt: 1);
      expect(silent.calls, hasLength(1));
      expect(none.file!['status'], 'incomplete');
      expect(none.file!['stopReason'], contains('missing or is not JSON'));

      final noRatio = _TimingFixture();
      addTearDown(noRatio.delete);
      final without = await noRatio.measure(developmentPersonasFile,
          change: (run, file) => run == 4 ? (file..['firstRatio'] = 'slow') : file);
      expect(noRatio.calls, hasLength(4));
      expect(without.file!['status'], 'incomplete');
      expect(without.file!['stopReason'],
          'run 4: firstRatio is not a number');

      final otherApproach = _TimingFixture();
      addTearDown(otherApproach.delete);
      final other = await otherApproach.measure(developmentPersonasFile,
          change: (run, file) => file..['approach'] = 'B/10/10/bt-opp');
      expect(otherApproach.calls, hasLength(1));
      expect(other.file!['stopReason'], contains('its approach is'));

      final otherFreeze = _TimingFixture();
      addTearDown(otherFreeze.delete);
      final another = await otherFreeze.measure(developmentPersonasFile,
          change: (run, file) => file..['freezeSha256'] = 'another');
      expect(otherFreeze.calls, hasLength(1));
      expect(another.file!['stopReason'], contains('another freeze'));
    });

    test('a run that cannot start, or whose folder is in use, ends it too',
        () async {
      // The runner throws on run 2: the error is recorded, not raised.
      final fixture = _TimingFixture();
      addTearDown(fixture.delete);
      final result = await fixture.measure(developmentPersonasFile, throwAt: 2);
      expect(result.refusal, isNull);
      expect(fixture.calls, hasLength(2));
      expect(fixture.log, [
        'run 1 of 5 finished, exit 0',
        'run 2 of 5 did not finish',
      ]);
      final file = fixture.read('${fixture.guards}/timing_dev.json');
      expect(file, jsonDecode(jsonEncode(result.file)));
      expect(file['status'], 'incomplete');
      expect(file['stopReason'], startsWith('run 2: it could not be run: '));
      expect(file['stopReason'], contains('the program could not be found'));
      expect(file['stopReason'], isNot(contains('\n')));
      expect(file['personaSameAsGuard'], isTrue);
      final runs = file['runs'] as List;
      expect(runs, hasLength(2));
      expect((runs[1] as Map)['exitCode'], -1);
      expect((runs[1] as Map).containsKey('firstRatio'), isFalse);
      expect(fixture.problemsOf(developmentPersonasFile),
          contains(contains('its status is incomplete')));
      // It was measured: it is never started again.
      expect((await fixture.measure(developmentPersonasFile)).refusal,
          contains('measured once'));
      expect(fixture.calls, hasLength(2));

      // Another measurement made the folder of run 3 while run 2 ran: run 3
      // never starts and nothing is written into that folder.
      final clash = _TimingFixture();
      addTearDown(clash.delete);
      final third = '${clash.guards}/timing_runs/dev_3';
      final stopped = await clash.measure(developmentPersonasFile,
          alsoDo: (run) {
        if (run == 2) Directory(third).createSync(recursive: true);
      });
      expect(clash.calls, hasLength(2));
      expect(clash.log.last, 'run 3 of 5 did not finish');
      expect(stopped.file!['status'], 'incomplete');
      expect(stopped.file!['stopReason'], startsWith('run 3: its folder '));
      expect(stopped.file!['stopReason'], contains('was already there'));
      final listed = stopped.file!['runs'] as List;
      expect(listed, hasLength(3));
      expect((listed[2] as Map)['exitCode'], -1);
      expect((listed[2] as Map)['sha256'], isNull);
      expect(Directory(third).listSync(), isEmpty);
      expect(clash.problemsOf(developmentPersonasFile), isNotEmpty);
    });

    test('persona numbers that differ from the guard file stop it at once',
        () async {
      final fixture = _TimingFixture();
      addTearDown(fixture.delete);
      final result = await fixture.measure(developmentPersonasFile,
          change: (run, file) => run == 2
              ? (file..['withLinks'] = [0.8368, 0.933, 1.0, 1.25])
              : file);
      expect(fixture.calls, hasLength(2));
      final file = result.file!;
      expect(file['status'], 'incomplete');
      expect(file['personaSameAsGuard'], isFalse);
      expect(file['stopReason'], contains('run 2'));
      expect(file['stopReason'], contains('withLinks'));
      expect(fixture.problemsOf(developmentPersonasFile), isNotEmpty);
      // The guard file itself is never replaced.
      expect(fixture.read('${fixture.guards}/dev.json')['withLinks'],
          [0.8369, 0.933, 1.0, 1.25]);

      final extraKey = _TimingFixture();
      addTearDown(extraKey.delete);
      final extra = await extraKey.measure(developmentPersonasFile,
          change: (run, file) => file..['note'] = 'added');
      expect(extraKey.calls, hasLength(1));
      expect(extra.file!['status'], 'incomplete');
      expect(extra.file!['personaSameAsGuard'], isFalse);
      expect(extra.file!['stopReason'], contains('note'));
      expect(extraKey.problemsOf(developmentPersonasFile), isNotEmpty);

      // A field the timing does not own may not be missing either, and the
      // comparison reaches into lists and nested fields.
      final guard = extraKey.guard();
      expect(timingRunDifference({...guard}, guard), isNull);
      expect(
          timingRunDifference(
              {...guard, 'warmRatio': 9.0, 'firstRatio': 9.0, 'timingPass': false},
              guard),
          isNull);
      expect(timingRunDifference({...guard}..remove('linkRuns'), guard),
          contains('linkRuns'));
      expect(
          timingRunDifference({
            ...guard,
            'links': {'path': 'links/dev.json', 'sha256': 'other'},
          }, guard),
          contains('links'));
      expect(timingRunDifference({...guard, 'unlabelledItems': ['x']}, guard),
          contains('unlabelledItems'));
    });

    test('the decision takes a timing file only as written', () async {
      final fixture = _TimingFixture();
      addTearDown(fixture.delete);
      await fixture.measure(developmentPersonasFile);
      final path = '${fixture.guards}/timing_dev.json';
      List<String> problems(void Function(Map<String, dynamic>) change,
          {String? at}) {
        final copy = fixture.read(path);
        change(copy);
        return timingFileProblems(copy,
            path: at ?? path,
            frozen: fixture.frozen,
            freezeSha: _TimingFixture.sha,
            amendment: fixture.amendment,
            amendmentSha: _TimingFixture.amendmentSha);
      }

      expect(problems((t) {}), isEmpty);
      expect(problems((t) => t['freezeSha256'] = 'another'),
          ['it was written under another freeze']);
      expect(problems((t) => t['amendmentSha256'] = 'another'),
          ['it was written under another amendment']);
      expect(problems((t) => t['kind'] = 'guard').single, contains('kind'));
      expect(problems((t) => t['label'] = 'heldout').single,
          contains('label'));
      expect(problems((t) => (t['runs'] as List).removeLast()),
          contains('it lists 4 runs, not 5'));
      expect(
          problems((t) => ((t['runs'] as List)[0] as Map)['firstRatio'] = 0.9)
              .single,
          contains('the firstRatio of run 1'));
      expect(problems((t) => (t['warmRatios'] as List)[4] = 1.0),
          contains(contains('the warmRatio of run 5')));
      expect(
          problems((t) => ((t['runs'] as List)[1] as Map)['sha256'] = 'other')
              .single,
          contains('changed since the measurement'));
      expect(
          problems((t) => ((t['runs'] as List)[1] as Map)['exitCode'] = 1)
              .single,
          contains('run 2 ended with exit code 1'));
      expect(
          problems((t) => ((t['runs'] as List)[1] as Map)['file'] =
              '${fixture.guards}/timing_runs/dev_1/guard.json').single,
          contains('the file of run 2'));
      expect(problems((t) => t['status'] = 'fail'),
          ['its status is not what its medians give']);
      expect(problems((t) => t['firstMedian'] = 1.0),
          ['its medians are not the medians of its ratios']);
      expect(problems((t) => t['firstLimit'] = 1.2).single,
          contains('limits'));
      expect(problems((t) => t['comparedAt'] = '3 decimals').single,
          contains('comparedAt'));
      expect(problems((t) => t['personaSameAsGuard'] = false),
          ['personaSameAsGuard is not true']);
      expect(problems((t) => t['stopReason'] = 'stopped'),
          ['it has a stopReason']);
      expect(problems((t) => t['approach'] = 'B/10/10/bt-opp').single,
          contains('its approach'));
      expect(problems((t) => t['opportunities'] = 'other').single,
          contains('opportunities'));
      expect(
          problems((t) {}, at: '${fixture.guards}/timing_other.json').single,
          contains('its path is not the one the amendment names'));
      expect(
          problems((t) => ((t['measured'] as Map)['links'] as Map)['path'] =
              'links/other.json').single,
          contains('is not the frozen link file'));
      expect(
          problems((t) => ((t['measured'] as Map)['links'] as Map)['sha256'] =
              'other').single,
          contains('is not the frozen content'));
      expect(
          problems((t) => (t['guardFile'] as Map)['sha256'] = 'other').single,
          contains('its guardFile is not the guard file the amendment'));
      expect(
          problems((t) => ((t['measured'] as Map)['personas'] as Map)['path'] =
              'test/fixtures/other.json'),
          ['test/fixtures/other.json is not a frozen persona file']);

      // A sixth run folder: it was run again.
      final sixth = Directory('${fixture.guards}/timing_runs/dev_6')
        ..createSync();
      expect(problems((t) {}).single, contains('not exactly dev_1'));
      sixth.deleteSync();
      expect(problems((t) {}), isEmpty);

      // A run file that changed after the measurement.
      final runFile = '${fixture.guards}/timing_runs/dev_2/guard.json';
      writeJson(runFile, fixture.read(runFile)..['firstRatio'] = 0.5);
      expect(problems((t) {}),
          contains(contains('changed since the measurement')));
    });

    test(
        'a timing file is not a guard file, and the folder holds only what '
        'is expected', () async {
      final fixture = _TimingFixture();
      addTearDown(fixture.delete);
      await fixture.measure(developmentPersonasFile, errorsAt: 2);
      await fixture.measure(heldOutPersonasFile);
      final guards = fixture.guards;
      for (final name in const [
        'dev.txt', 'heldout.txt', 'timing_dev.txt', 'timing_heldout.txt',
      ]) {
        File('$guards/$name').writeAsStringSync('printed output');
      }
      expect(File('$guards/timing_runs/dev_2/guard.err.txt').existsSync(),
          isTrue);
      expect(
          Directory('$guards/timing_runs').listSync().whereType<Directory>(),
          hasLength(10));

      expect(guardPersonaFilesIn(guards), {
        '$guards/dev.json': developmentPersonasFile,
        '$guards/heldout.json': heldOutPersonasFile,
        '$guards/timing_dev.json': null,
        '$guards/timing_heldout.json': null,
      });
      expect(personaFilesGuardedTwice(guards), isEmpty);
      expect(
          guardInputProblem([
            '$guards/dev.json',
            '$guards/heldout.json',
            '$guards/timing_dev.json',
            '$guards/timing_heldout.json',
          ], runFolder: fixture.run),
          isNull);
      expect(amendedGuardsFolderProblems(guards, fixture.amendment), isEmpty);
      expect(fixture.problemsOf(developmentPersonasFile), isEmpty);
      expect(fixture.problemsOf(heldOutPersonasFile), isEmpty);

      List<String> unexpected() =>
          amendedGuardsFolderProblems(guards, fixture.amendment);
      writeJson('$guards/extra.json', {'note': 'not expected'});
      expect(unexpected(), ['$guards/extra.json is not expected there']);
      File('$guards/extra.json').deleteSync();

      final zero = Directory('$guards/timing_runs/dev_0')..createSync();
      expect(unexpected(),
          ['$guards/timing_runs/dev_0 is not expected there']);
      zero.deleteSync();
      final other = Directory('$guards/timing_runs/other_1')..createSync();
      expect(unexpected(),
          ['$guards/timing_runs/other_1 is not expected there']);
      other.deleteSync();

      final notes = File('$guards/timing_runs/dev_1/notes.txt')
        ..writeAsStringSync('a note');
      expect(unexpected(),
          ['$guards/timing_runs/dev_1/notes.txt is not expected there']);
      notes.deleteSync();
      final deeper = Directory('$guards/timing_runs/dev_1/more')..createSync();
      expect(unexpected(),
          ['$guards/timing_runs/dev_1/more is not expected there']);
      deeper.deleteSync();
      final loose = File('$guards/timing_runs/guard.json')
        ..writeAsStringSync('{}');
      expect(unexpected(),
          ['$guards/timing_runs/guard.json is not expected there']);
      loose.deleteSync();
      expect(unexpected(), isEmpty);
    });

    test('the fallback takes the timing files of its full candidate',
        () async {
      final fixture = _TimingFixture();
      addTearDown(fixture.delete);
      await fixture.measure(developmentPersonasFile);
      await fixture.measure(heldOutPersonasFile);
      final dev = '${fixture.guards}/timing_dev.json';
      final heldOut = '${fixture.guards}/timing_heldout.json';
      ({
        Map<String, Map<String, Map<String, dynamic>>> files,
        List<String> problems
      }) found(Map<String, Map<String, dynamic>> timing) => amendedTimingFor(
            [Approach.parse('B/10/10/bt'), Approach.parse('B/10/10/bt-opp')],
            timing,
            frozen: fixture.frozen,
            freezeSha: _TimingFixture.sha,
            amendment: fixture.amendment,
            amendmentSha: _TimingFixture.amendmentSha,
          );

      final both = found({dev: fixture.read(dev), heldOut: fixture.read(heldOut)});
      expect(both.problems, isEmpty);
      expect(both.files['B/10/10/bt']!.keys,
          [developmentPersonasFile, heldOutPersonasFile]);
      expect(both.files['B/10/10/bt-opp'], both.files['B/10/10/bt']);
      expect(both.files['B/10/10/bt']![heldOutPersonasFile]!['label'],
          'heldout');

      // One file alone serves neither candidate.
      final one = found({dev: fixture.read(dev)});
      expect(one.problems, [
        'B/10/10/bt needs exactly one timing file for $heldOutPersonasFile; '
            '0 were passed',
        'B/10/10/bt-opp needs exactly one timing file for '
            '$heldOutPersonasFile; 0 were passed',
      ]);
      // An unusable file is named with its path.
      final changed = found({
        dev: fixture.read(dev)..['status'] = 'fail',
        heldOut: fixture.read(heldOut),
      });
      expect(changed.problems,
          ['$dev: its status is not what its medians give']);
    });

    test('the verdict of step 3c', () async {
      Future<({String verdict, List<String> lines})> check({
        List<double> devFirst = passFirst,
        List<double>? heldOutFirst = passFirst,
        int? heldOutFailAt,
      }) async {
        final fixture = _TimingFixture();
        addTearDown(fixture.delete);
        await fixture.measure(developmentPersonasFile, first: devFirst);
        if (heldOutFirst != null) {
          await fixture.measure(heldOutPersonasFile,
              first: heldOutFirst, failAt: heldOutFailAt);
        }
        return amendedTimingCheck(
          frozen: fixture.frozen,
          freezeSha: _TimingFixture.sha,
          amendment: fixture.amendment,
          amendmentSha: _TimingFixture.amendmentSha,
        );
      }

      final passes = await check();
      expect(passes.verdict, 'PASS');
      expect(passes.lines.join('\n'), contains('median, first call: 1.0800'));
      expect(passes.lines.where((line) => line.contains('this file: pass')),
          hasLength(2));

      expect((await check(devFirst: failFirst, heldOutFailAt: 2)).verdict,
          'FAIL');
      expect((await check(heldOutFailAt: 2)).verdict, 'NOT USABLE');
      final missing = await check(heldOutFirst: null);
      expect(missing.verdict, 'NOT USABLE');
      expect(missing.lines.join('\n'), contains('the timing file is missing'));
      final fails = await check(heldOutFirst: failFirst);
      expect(fails.verdict, 'FAIL');
      expect(fails.lines.join('\n'), contains('this file: FAIL'));
      expect((await check(devFirst: failFirst)).verdict, 'FAIL');

      // Both pass, but the folder holds something unexpected.
      final fixture = _TimingFixture();
      addTearDown(fixture.delete);
      await fixture.measure(developmentPersonasFile);
      await fixture.measure(heldOutPersonasFile);
      Directory('${fixture.guards}/timing_runs/dev_6').createSync();
      final again = amendedTimingCheck(
        frozen: fixture.frozen,
        freezeSha: _TimingFixture.sha,
        amendment: fixture.amendment,
        amendmentSha: _TimingFixture.amendmentSha,
      );
      expect(again.verdict, 'NOT USABLE');
      expect(again.lines.join('\n'), contains('dev_6 is not expected there'));
    });
  });

  group('the guards with the amended timing', () {
    final fixture = _TimingFixture.inMemory();
    const passing = {
      'warmRatios': [1.3, 1.2, 1.1, 1.0, 1.9],
      'firstRatios': [1.02, 1.15, 0.98, 1.08, 1.12],
    };
    const failing = {
      'warmRatios': [1.3, 1.2, 1.1, 1.0, 1.9],
      'firstRatios': [1.25, 1.2, 1.15, 1.0, 1.0],
    };
    GuardVerdict verdict(
      List<Map<String, dynamic>> files, {
      Map<String, Map<String, dynamic>>? amendedTiming,
    }) =>
        guardVerdictOf(files,
            decimals: 3, tolerance: 0, amendedTiming: amendedTiming);

    test('persona from the guard files, timing from the timing files', () {
      // The guard files as they were run: the single first-call ratio of
      // the development file is over the limit.
      final files = [fixture.guard(), fixture.guard(heldOut: true)];
      final frozenRule = verdict(files);
      expect(frozenRule.personaStatus, 'pass');
      expect(frozenRule.sameWithoutLinks, isTrue);
      expect(frozenRule.timing, isFalse);
      expect(frozenRule.passes, isFalse);
      expect(frozenRule.lines.first,
          endsWith('timing ratios 1.1033 and 1.1006 FAIL'));

      final amended = verdict(files, amendedTiming: {
        developmentPersonasFile: passing,
        heldOutPersonasFile: passing,
      });
      expect(amended.personaStatus, 'pass');
      expect(amended.timing, isTrue);
      expect(amended.passes, isTrue);
      expect(
          amended.lines.first,
          endsWith('timing (rule 7.2 d, amendment 1) medians 1.2000 and '
              '1.0800 of 5 runs pass; the single run of the guard file, '
              '1.1033 and 1.1006, is reported only'));
      expect(amended.lines.last, contains('reported only'));

      final heldOutFails = verdict(files, amendedTiming: {
        developmentPersonasFile: passing,
        heldOutPersonasFile: failing,
      });
      expect(heldOutFails.timing, isFalse);
      expect(heldOutFails.passes, isFalse);
      expect(heldOutFails.lines.first, contains('of 5 runs pass'));
      expect(heldOutFails.lines.last,
          contains('medians 1.2000 and 1.1500 of 5 runs FAIL'));

      // A persona file without a timing file never passes.
      final oneMissing = verdict(files,
          amendedTiming: {developmentPersonasFile: passing});
      expect(oneMissing.timing, isFalse);
      expect(oneMissing.lines.last, endsWith('FAIL: no timing file'));
      expect(verdict(files, amendedTiming: const {}).timing, isFalse);
      // Nor does a timing file without its 5 ratios.
      final short = verdict(files, amendedTiming: {
        developmentPersonasFile: passing,
        heldOutPersonasFile: const {
          'warmRatios': [1.0, 1.0],
          'firstRatios': [1.0, 1.0],
        },
      });
      expect(short.timing, isFalse);
      // A single run under the limit does not excuse failing medians.
      final fast = [
        fixture.guard(firstRatio: 1.0),
        fixture.guard(heldOut: true, firstRatio: 1.0),
      ];
      expect(verdict(fast).timing, isTrue);
      expect(
          verdict(fast, amendedTiming: {
            developmentPersonasFile: failing,
            heldOutPersonasFile: passing,
          }).timing,
          isFalse);
      // The persona part is not touched by the timing files.
      final worse = verdict(
        [
          fixture.guard(),
          fixture.guard(
              heldOut: true, withLinks: const [0.80, 0.933, 1.0, 1.25]),
        ],
        amendedTiming: {
          developmentPersonasFile: passing,
          heldOutPersonasFile: passing,
        },
      );
      expect(worse.personaStatus, 'fail');
      expect(worse.timing, isTrue);
      expect(worse.passes, isFalse);
    });

    test('pending still waits for labels', () {
      final waiting = verdict(
        [
          fixture.guard(),
          fixture.guard(
            heldOut: true,
            withLinks: const [0.80, 0.933, 1.0, 1.25],
            withBest: const [0.84, 0.933, 1.0, 1.25],
            unlabelled: 2,
          ),
        ],
        amendedTiming: {
          developmentPersonasFile: passing,
          heldOutPersonasFile: passing,
        },
      );
      expect(waiting.personaStatus, 'pending');
      expect(waiting.timing, isTrue);
      expect(waiting.passes, isFalse);
      expect(waiting.onlyPending, isTrue);
      expect(
          pendingCandidates({'B/10/10/bt': true}, {'B/10/10/bt': waiting}),
          ['B/10/10/bt']);
    });

    test('which inputs the decision accepts', () {
      String? input(bool amended, bool guards, bool timing) =>
          timingInputProblem(
            amended: amended,
            hasGuards: guards,
            hasTiming: timing,
            amendmentFile: 'tools/gap_eval/freeze_r2_amendment_timing.json',
          );
      expect(
          input(true, true, false),
          'Rule 7.2 (d) is amended '
          '(tools/gap_eval/freeze_r2_amendment_timing.json): pass --timing '
          'with the timing files it names.');
      expect(input(false, true, true), contains('this freeze has none'));
      expect(input(true, false, true), contains('--timing goes with --guards'));
      expect(input(false, false, true), isNotNull);
      expect(input(true, true, true), isNull);
      expect(input(false, true, false), isNull);
      // Without the guards nothing of rule 7.2 is read (pooling, or a
      // score that names no winner).
      expect(input(true, false, false), isNull);
      expect(input(false, false, false), isNull);

      final onDisk = _TimingFixture();
      addTearDown(onDisk.delete);
      final guards = onDisk.guards;
      final recorded = ['$guards/dev.json', '$guards/heldout.json'];
      expect(amendedGuardProblems(recorded, onDisk.amendment), isEmpty);
      expect(amendedGuardProblems(recorded.reversed.toList(), onDisk.amendment),
          isEmpty);
      // A run file of the timing measurement never stands in for one.
      final nested = '$guards/timing_runs/dev_1/guard.json';
      writeJson(nested, onDisk.guard());
      expect(
          amendedGuardProblems([nested, '$guards/heldout.json'],
              onDisk.amendment),
          [
            '$nested is not a guard file the amendment recorded',
            '$guards/dev.json, which the amendment recorded, was not passed',
          ]);
      writeJson('$guards/dev2.json', onDisk.guard());
      expect(
          amendedGuardProblems(['$guards/dev2.json', '$guards/heldout.json'],
              onDisk.amendment),
          contains(contains('dev2.json is not a guard file')));
      expect(
          amendedGuardProblems(['$guards/dev.json'], onDisk.amendment).single,
          contains('heldout.json, which the amendment recorded, was not'));
      expect(
          amendedGuardProblems([...recorded, '$guards/dev.json'],
              onDisk.amendment).single,
          contains('passed twice'));
      // The recorded file itself, changed.
      writeJson('$guards/dev.json', onDisk.guard(firstRatio: 1.0));
      expect(amendedGuardProblems(recorded, onDisk.amendment).single,
          contains('dev.json is missing or changed'));
    });
  });
}

/// A guard file as the guard tool writes it, with every field of the real
/// files, for the tests of the timing amendment.
Map<String, dynamic> _guardFile({
  required String personas,
  required String personasSha,
  required String links,
  required String linksSha,
  required String freezeSha,
  String freezeFile = 'freeze.json',
  String approach = 'B/10/10/bt',
  List<double> withLinks = const [0.8369, 0.933, 1.0, 1.25],
  List<double>? withBest,
  int unlabelled = 0,
  double firstRatio = 1.1006,
}) {
  const today = [0.8374, 0.933, 1.0, 1.25];
  final ran = Approach.parse(approach);
  return {
    'freezeFile': freezeFile,
    'freezeSha256': freezeSha,
    'approach': ran.id,
    'source': ran.source.name,
    'opportunities': settingKey(ran.source, ran.opportunities),
    'certifications': settingKey(ran.source, ran.certifications),
    'personas': {'path': personas, 'sha256': personasSha},
    'links': {'path': links, 'sha256': linksSha},
    'precision': 3,
    'tolerance': 0,
    'metrics': ['nDCG@10', 'GapCov@10', 'P@5', 'TopGapRank'],
    'today': today,
    'withLinks': withLinks,
    'todayWithBestLabels': today,
    'withBestLabels': withBest ?? withLinks,
    'linkRuns': 3,
    'passesFullPrecision': false,
    'passesThreeDecimals': true,
    'unlabelled': unlabelled,
    'unlabelledItems': <String>[],
    'passesWithBestLabels': true,
    'guardStatus': 'pass',
    'sameWithoutLinks': true,
    'certificationListsSame': true,
    'warmRatio': 1.1033,
    'firstRatio': firstRatio,
    'timingPass': timingPasses(1.1033, firstRatio),
  };
}

/// A freeze with invented hashes, its two guard files in the guards folder
/// of a run in a temporary folder, and the amendment that records them.
/// The runs of the timing measurement are played by a fake runner: no
/// process is started.
class _TimingFixture {
  _TimingFixture() : this._(true);
  _TimingFixture.inMemory() : this._(false);

  _TimingFixture._(bool onDisk)
      : root = onDisk
            ? slashes(Directory.systemTemp.createTempSync('timing_fixture').path)
            : 'nowhere' {
    if (!onDisk) return;
    final files = {
      '$guards/dev.json': guard(),
      '$guards/heldout.json': guard(heldOut: true),
    };
    files.forEach(writeJson);
    amendment = jsonDecode(jsonEncode(amendmentOf(
      frozen: frozen,
      freezeFile: 'freeze.json',
      freezeSha: sha,
      guards: files,
      source: 'the user agreed in chat',
      amendedTools: 'a' * 64,
    ))) as Map<String, dynamic>;
  }

  static const sha = 'the-sha-of-the-freeze-file';
  static const amendmentSha = 'the-sha-of-the-amendment-file';

  final String root;
  String get run => '$root/run';
  String get guards => guardsFolderOf(run);
  late final Map<String, dynamic> amendment;

  final Map<String, dynamic> frozen = {
    'candidates': ['B/10/10/bt', 'B/10/10/bt-opp'],
    'personaGuard': {'precision': 3, 'tolerance': 0, 'source': 'user'},
    'personaLinkFor': {
      developmentPersonasFile: 'links/dev.json',
      heldOutPersonasFile: 'links/heldout.json',
    },
    'hashes': {
      'gapEvalTools': 'old-tools',
      'personas': 'p-dev',
      'personasHeldOut': 'p-heldout',
      'personaLinks:links/dev.json': 'l-dev',
      'personaLinks:links/heldout.json': 'l-heldout',
    },
  };

  /// The arguments of every run the fake runner was asked for, and the
  /// lines the measurement logged.
  final List<List<String>> calls = [];
  final List<String> log = [];

  Map<String, dynamic> guard({
    bool heldOut = false,
    List<double> withLinks = const [0.8369, 0.933, 1.0, 1.25],
    List<double>? withBest,
    int unlabelled = 0,
    double firstRatio = 1.1006,
  }) =>
      _guardFile(
        personas: heldOut ? heldOutPersonasFile : developmentPersonasFile,
        personasSha: heldOut ? 'p-heldout' : 'p-dev',
        links: heldOut ? 'links/heldout.json' : 'links/dev.json',
        linksSha: heldOut ? 'l-heldout' : 'l-dev',
        freezeSha: sha,
        withLinks: withLinks,
        withBest: withBest,
        unlabelled: unlabelled,
        firstRatio: firstRatio,
      );

  Map<String, dynamic> read(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  /// The timing measurement of [personas] with a fake runner. Run k writes
  /// the recorded guard file with the k-th of [warm] and [first] as its
  /// ratios, changed by [change]; it exits 1 without a file at [failAt],
  /// exits 0 without a file at [writeNoFileAt], leaves printed errors at
  /// [errorsAt], and throws as a program that cannot be started at
  /// [throwAt]. [alsoDo] is called during each run with its number.
  Future<TimingMeasurement> measure(
    String personas, {
    List<double> warm = const [1.3, 1.2, 1.1, 1.0, 1.9],
    List<double> first = const [1.02, 1.15, 0.98, 1.08, 1.12],
    int? failAt,
    int? writeNoFileAt,
    int? errorsAt,
    int? throwAt,
    void Function(int run)? alsoDo,
    Map<String, dynamic> Function(int run, Map<String, dynamic> file)? change,
    bool dryRun = false,
  }) {
    var number = 0;
    var running = false;
    return measureTiming(
      personas: personas,
      frozen: frozen,
      freezeFile: 'freeze.json',
      freezeSha: sha,
      amendment: amendment,
      amendmentFile: 'freeze_amendment_timing.json',
      amendmentSha: amendmentSha,
      dryRun: dryRun,
      log: log.add,
      run: (args, folder) async {
        // One after another: the previous run has returned.
        expect(running, isFalse);
        running = true;
        number++;
        calls.add(args);
        // Its folder and its guard.txt are there before it starts.
        expect(folder, endsWith('_$number'));
        expect(Directory(folder).existsSync(), isTrue);
        expect(File('$folder/guard.txt').existsSync(), isTrue);
        expect(File('$folder/guard.json').existsSync(), isFalse);
        await Future<void>.delayed(Duration.zero);
        running = false;
        alsoDo?.call(number);
        if (number == throwAt) {
          throw const ProcessException(
              'dart', [], 'the program could not be found', 2);
        }
        if (number == errorsAt) {
          File('$folder/guard.err.txt').writeAsStringSync('a warning');
        }
        if (number == failAt) return 1;
        if (number == writeNoFileAt) return 0;
        final file = {
          ...guard(heldOut: personas == heldOutPersonasFile),
          'warmRatio': warm[number - 1],
          'firstRatio': first[number - 1],
          'timingPass': timingPasses(warm[number - 1], first[number - 1]),
        };
        writeJson(args[args.indexOf('--guard-json') + 1],
            change == null ? file : change(number, file));
        return 0;
      },
    );
  }

  /// What the decision finds wrong with the timing file of [personas].
  List<String> problemsOf(String personas) {
    final path = '${(amendment['timingFiles'] as Map)[personas]}';
    return timingFileProblems(read(path),
        path: path,
        frozen: frozen,
        freezeSha: sha,
        amendment: amendment,
        amendmentSha: amendmentSha);
  }

  void delete() => Directory(root).deleteSync(recursive: true);
}

/// A freeze written to a temporary folder with the hashes of the files as
/// they are now, except that it says the tools of tools/gap_eval had
/// another hash when it was written: the state after the amendment's code
/// change. Its two guard files lie in the guards folder of a run.
class _RealFreeze {
  _RealFreeze()
      : root = slashes(Directory.systemTemp.createTempSync('amendment').path) {
    for (final path in links) {
      File(path).writeAsStringSync('{"links": []}');
    }
    final decided = freezeSettings(
      precision: '3',
      precisionSource: 'the user chose it in chat',
      tolerance: '0',
      graceSeconds: '3',
      graceSource: 'the user chose it in chat',
      writerNames: 'off',
      writerSource: 'the user answered no',
      personaLinks: links,
    ).settings!;
    final hashes = hashesNow(links);
    toolsNow = '${hashes['gapEvalTools']}';
    writeJson(file, {
      'candidates': ['B/10/10/bt', 'B/10/10/bt-opp'],
      'requests': ['typed'],
      'decisionGoals': decisionGoals,
      'promptExampleGoals': promptExampleGoals,
      'marketRuns': frozenMarketRuns,
      'writerLinkRuns': frozenWriterLinkRuns,
      'seeds': seeds,
      ...decided,
      'hashes': {...hashes, 'gapEvalTools': 'old-tools'},
    });
    frozen = Map<String, dynamic>.from(readJson(file) as Map);
    sha = freezeShaOf(file);
    guardFiles.forEach(writeJson);
  }

  final String root;
  String get file => '$root/freeze.json';
  String get guards => '$root/run/guards';
  List<String> get links =>
      ['$root/dev_links.json', '$root/heldout_links.json'];
  late final Map<String, dynamic> frozen;
  late final String sha;
  late final String toolsNow;

  Map<String, dynamic> guard({
    bool heldOut = false,
    String approach = 'B/10/10/bt',
    String? freezeSha,
    List<double> withLinks = const [0.8369, 0.933, 1.0, 1.25],
  }) {
    final hashes = frozen['hashes'] as Map;
    final linksPath = links[heldOut ? 1 : 0];
    return _guardFile(
      personas: heldOut ? heldOutPersonasFile : developmentPersonasFile,
      personasSha: '${hashes[heldOut ? 'personasHeldOut' : 'personas']}',
      links: linksPath,
      linksSha: '${hashes['personaLinks:$linksPath']}',
      freezeSha: freezeSha ?? sha,
      freezeFile: file,
      approach: approach,
      withLinks: withLinks,
    );
  }

  /// The two guard files as they were run, by path.
  Map<String, Map<String, dynamic>> get guardFiles => {
        '$guards/dev.json': guard(),
        '$guards/heldout.json': guard(heldOut: true),
      };

  /// The amendment of this freeze, over the guard files on disk.
  Map<String, dynamic> amendment({String? amendedTools}) =>
      jsonDecode(jsonEncode(amendmentOf(
        frozen: frozen,
        freezeFile: file,
        freezeSha: sha,
        guards: guardFiles,
        source: 'the user agreed in chat',
        amendedTools: amendedTools ?? toolsNow,
      ))) as Map<String, dynamic>;

  List<String> differences(Map<String, dynamic> amendment) =>
      freezeDifferences(frozen,
          amendment: amendment, freezeSha: sha, freezeFile: file);

  void delete() => Directory(root).deleteSync(recursive: true);
}
