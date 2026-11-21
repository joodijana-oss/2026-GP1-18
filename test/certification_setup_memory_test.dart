import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masra/features/certifications/certification_setup_memory.dart';
import 'package:masra/services/content_based_recommender.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A saved run for the decision tests.
SavedCertificationRun run({
  String? analysisKey = '1700000000.0',
  String? careerGoalId = 'data_analyst',
}) {
  return SavedCertificationRun(
    goal: CertificationGoal.closeGaps,
    limit: 5,
    analysisKey: analysisKey,
    careerGoalId: careerGoalId,
  );
}

void main() {
  const memory = CertificationSetupMemory();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('when the setup shows', () {
    test('the first time (nothing saved)', () {
      expect(
        CertificationSetupMemory.shouldShowSetup(
          saved: null,
          analysisKey: '1700000000.0',
          careerGoalId: 'data_analyst',
        ),
        isTrue,
      );
    });

    test('not when the analysis and career goal are the same', () {
      expect(
        CertificationSetupMemory.shouldShowSetup(
          saved: run(),
          analysisKey: '1700000000.0',
          careerGoalId: 'data_analyst',
        ),
        isFalse,
      );
    });

    test('after a new CV analysis', () {
      expect(
        CertificationSetupMemory.shouldShowSetup(
          saved: run(),
          analysisKey: '1700000100.0',
          careerGoalId: 'data_analyst',
        ),
        isTrue,
      );
    });

    test('when the career goal changed', () {
      expect(
        CertificationSetupMemory.shouldShowSetup(
          saved: run(),
          analysisKey: '1700000000.0',
          careerGoalId: 'software_engineer',
        ),
        isTrue,
      );
    });

    test('when anything is unknown', () {
      // The current analysis time is not readable.
      expect(
        CertificationSetupMemory.shouldShowSetup(
          saved: run(),
          analysisKey: null,
          careerGoalId: 'data_analyst',
        ),
        isTrue,
      );
      // The current career goal is unknown.
      expect(
        CertificationSetupMemory.shouldShowSetup(
          saved: run(),
          analysisKey: '1700000000.0',
          careerGoalId: null,
        ),
        isTrue,
      );
      // The saved run did not record the analysis.
      expect(
        CertificationSetupMemory.shouldShowSetup(
          saved: run(analysisKey: null),
          analysisKey: '1700000000.0',
          careerGoalId: 'data_analyst',
        ),
        isTrue,
      );
      // The saved run did not record the career goal.
      expect(
        CertificationSetupMemory.shouldShowSetup(
          saved: run(careerGoalId: null),
          analysisKey: '1700000000.0',
          careerGoalId: 'data_analyst',
        ),
        isTrue,
      );
    });
  });

  group('which analysis and career goal', () {
    test('the analysis key is the time it was saved', () {
      expect(
        CertificationSetupMemory.analysisKeyOf({
          'analyzedAt': Timestamp(1700000000, 123),
        }),
        '1700000000.123',
      );
    });

    test('two different times give different keys', () {
      final a = CertificationSetupMemory.analysisKeyOf({
        'analyzedAt': Timestamp(1700000000, 5),
      });
      final b = CertificationSetupMemory.analysisKeyOf({
        'analyzedAt': Timestamp(1700000000, 6),
      });
      final c = CertificationSetupMemory.analysisKeyOf({
        'analyzedAt': Timestamp(1700000001, 5),
      });
      expect({a, b, c}.length, 3);
    });

    test('no key when the time is missing or not readable', () {
      expect(CertificationSetupMemory.analysisKeyOf({}), isNull);
      expect(
        CertificationSetupMemory.analysisKeyOf({'analyzedAt': null}),
        isNull,
      );
      expect(
        CertificationSetupMemory.analysisKeyOf({
          'analyzedAt': '2026-01-01T00:00:00Z',
        }),
        isNull,
      );
    });

    test('the career goal id is trimmed, and empty means unknown', () {
      expect(
        CertificationSetupMemory.careerGoalIdOf({
          'careerGoalId': '  data_analyst ',
        }),
        'data_analyst',
      );
      expect(CertificationSetupMemory.careerGoalIdOf({}), isNull);
      expect(
        CertificationSetupMemory.careerGoalIdOf({'careerGoalId': null}),
        isNull,
      );
      expect(
        CertificationSetupMemory.careerGoalIdOf({'careerGoalId': ''}),
        isNull,
      );
      expect(
        CertificationSetupMemory.careerGoalIdOf({'careerGoalId': '   '}),
        isNull,
      );
    });
  });

  group('saved on the device for each user', () {
    test('nothing is saved at first, and a saved run comes back', () async {
      expect(await memory.load('uidA'), isNull);

      await memory.saveRun(
        'uidA',
        goal: CertificationGoal.strengthenSkills,
        limit: 10,
        analysisKey: '1700000000.5',
        careerGoalId: 'data_analyst',
      );

      final saved = await memory.load('uidA');
      expect(saved, isNotNull);
      expect(saved!.goal, CertificationGoal.strengthenSkills);
      expect(saved.limit, 10);
      expect(saved.analysisKey, '1700000000.5');
      expect(saved.careerGoalId, 'data_analyst');

      // Another account on the same phone has nothing saved.
      expect(await memory.load('uidB'), isNull);
    });

    test('All is stored as 0 and comes back as All', () async {
      await memory.saveRun(
        'uidA',
        goal: CertificationGoal.closeGaps,
        limit: null,
        analysisKey: '1700000000.0',
        careerGoalId: 'data_analyst',
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(CertificationSetupMemory.limitKey('uidA')), 0);
      expect((await memory.load('uidA'))!.limit, isNull);
    });

    test(
      'an old install with only the device-wide keys is a first time',
      () async {
        SharedPreferences.setMockInitialValues({
          'cert_recommender_goal': 'strengthenSkills',
          'cert_recommender_limit': 10,
        });

        final saved = await memory.load('uidA');
        expect(saved, isNull);
        expect(
          CertificationSetupMemory.shouldShowSetup(
            saved: saved,
            analysisKey: '1700000000.0',
            careerGoalId: 'data_analyst',
          ),
          isTrue,
        );
      },
    );

    test('bad stored values fall back to the defaults', () async {
      SharedPreferences.setMockInitialValues({
        CertificationSetupMemory.goalKey('uidA'): 'xyz',
        CertificationSetupMemory.limitKey('uidA'): 7,
      });

      final saved = await memory.load('uidA');
      expect(saved!.goal, CertificationGoal.closeGaps);
      expect(saved.limit, 5);
      expect(saved.analysisKey, isNull);
      expect(saved.careerGoalId, isNull);
    });

    test('a missing limit falls back to Top 5', () async {
      SharedPreferences.setMockInitialValues({
        CertificationSetupMemory.goalKey('uidA'): 'closeGaps',
      });

      expect((await memory.load('uidA'))!.limit, 5);
    });

    test('saving without an analysis key removes the old one', () async {
      await memory.saveRun(
        'uidA',
        goal: CertificationGoal.closeGaps,
        limit: 5,
        analysisKey: '1700000000.0',
        careerGoalId: 'data_analyst',
      );
      await memory.saveRun(
        'uidA',
        goal: CertificationGoal.closeGaps,
        limit: 5,
        analysisKey: null,
        careerGoalId: 'data_analyst',
      );

      final saved = await memory.load('uidA');
      expect(saved!.analysisKey, isNull);
      expect(
        CertificationSetupMemory.shouldShowSetup(
          saved: saved,
          analysisKey: '1700000000.0',
          careerGoalId: 'data_analyst',
        ),
        isTrue,
      );
    });
  });

  // The space before the dot and the space in "Top 5" are non-breaking
  // ( ), so a narrow phone never starts a line with the dot or the number.
  test('the choices summary matches the option titles', () {
    expect(
      CertificationSetupMemory.choicesSummary(CertificationGoal.closeGaps, 5),
      'Close my skill gaps · Top 5',
    );
    expect(
      CertificationSetupMemory.choicesSummary(
        CertificationGoal.strengthenSkills,
        10,
      ),
      'Strengthen my skills · Top 10',
    );
    expect(
      CertificationSetupMemory.choicesSummary(
        CertificationGoal.closeGaps,
        null,
      ),
      'Close my skill gaps · All',
    );
    // The option titles on the setup page keep normal spaces.
    expect(CertificationSetupMemory.limitLabel(10), 'Top 10');
  });

  test('from saved analyses to the decision', () async {
    final a = {
      'analyzedAt': Timestamp(1700000000, 5),
      'careerGoalId': 'data_analyst',
      'careerGoalName': 'Data Analyst',
      'skillGaps': ['SQL'],
      'currentSkills': ['Python'],
    };
    // A new analysis one second later, same career goal.
    final b = {...a, 'analyzedAt': Timestamp(1700000001, 5)};
    // The same analysis time, another career goal.
    final c = {...a, 'careerGoalId': 'software_engineer'};
    // The time is not readable yet.
    final d = {...a}..remove('analyzedAt');

    await memory.saveRun(
      'uidA',
      goal: CertificationGoal.closeGaps,
      limit: 5,
      analysisKey: CertificationSetupMemory.analysisKeyOf(a),
      careerGoalId: CertificationSetupMemory.careerGoalIdOf(a),
    );
    final saved = await memory.load('uidA');

    bool showsSetupFor(Map<String, dynamic> analysis) =>
        CertificationSetupMemory.shouldShowSetup(
          saved: saved,
          analysisKey: CertificationSetupMemory.analysisKeyOf(analysis),
          careerGoalId: CertificationSetupMemory.careerGoalIdOf(analysis),
        );

    expect(showsSetupFor(a), isFalse);
    expect(showsSetupFor(b), isTrue);
    expect(showsSetupFor(c), isTrue);
    expect(showsSetupFor(d), isTrue);
  });
}
