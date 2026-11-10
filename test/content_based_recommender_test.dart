import 'package:flutter_test/flutter_test.dart';
import 'package:masra/models/certification.dart';
import 'package:masra/services/content_based_recommender.dart';

Certification cert(
  String id, {
  String? name,
  String shortName = '',
  String level = 'Beginner',
  List<String> paths = const ['data_analyst'],
  List<String> skills = const [],
  bool verified = true,
}) {
  return Certification(
    id: id,
    name: name ?? id,
    shortName: shortName,
    issuer: 'Issuer',
    examCode: '',
    level: level,
    category: 'Category',
    description: 'Description',
    descriptionAr: '',
    careerPaths: paths,
    skills: skills,
    officialUrl: 'https://example.com',
    verified: verified,
    statusNote: '',
  );
}

Map<String, dynamic> analysis({
  String goal = 'data_analyst',
  List<String> gaps = const ['SQL', 'Power BI', 'Tableau'],
  List<Map<String, String>> held = const [],
}) {
  return {
    'careerGoalId': goal,
    'skillGaps': gaps,
    'certifications': held,
  };
}

List<String> ids(List<CertificationMatch> matches) =>
    matches.map((m) => m.certification.id).toList();

void main() {
  const recommender = ContentBasedRecommender();

  test('keeps only certifications for the career goal and ranks by gaps', () {
    final recs = recommender.recommendCertifications(
      analysis: analysis(),
      certifications: [
        cert('one_gap', skills: ['Databases and SQL']),
        cert('two_gaps', skills: ['Databases and SQL', 'Power BI']),
        cert('other_goal',
            paths: ['network_engineer'], skills: ['Databases and SQL']),
        cert('no_gap', skills: ['Python']),
      ],
    );

    expect(ids(recs.forGaps), ['two_gaps', 'one_gap']);
    expect(recs.forGaps.first.matchedGaps, ['SQL', 'Power BI']);
    expect(recs.forGaps.first.gapCount, 2);
    expect(ids(recs.forGoal), ['no_gap']);
    expect(recs.forGoal.first.matchedGaps, isEmpty);
    expect(recs.skillGaps, ['SQL', 'Power BI', 'Tableau']);
    expect(recs.isEmpty, isFalse);
  });

  test('hides certifications already listed in the CV', () {
    final recs = recommender.recommendCertifications(
      analysis: analysis(held: [
        {'name': 'Tableau Desktop Specialist', 'issuer': 'Tableau'},
      ]),
      certifications: [
        cert('held',
            name: 'Tableau Desktop Specialist', skills: ['Data Visualization']),
        cert('other', skills: ['Databases and SQL']),
      ],
    );

    expect(ids(recs.forGaps), ['other']);
    expect(ids(recs.forGoal), isEmpty);
    expect(recs.hiddenOwned, 1);
  });

  test('a short held name must match exactly', () {
    final recs = recommender.recommendCertifications(
      analysis: analysis(held: [
        {'name': 'CCNA'},
        {'name': 'Cisco'},
      ]),
      certifications: [
        cert('ccna', name: 'Cisco Certified Network Associate', shortName: 'CCNA'),
        cert('devnet', name: 'Cisco DevNet Associate', shortName: 'DevNet'),
      ],
    );

    // "CCNA" equals the short name, so it is hidden.
    // "Cisco" is too short to match a longer name by containment.
    expect(ids(recs.forGoal), ['devnet']);
    expect(recs.hiddenOwned, 1);
  });

  test('prefers the level closest to the experience level', () {
    final certs = [
      cert('beginner', level: 'Beginner', skills: ['Databases and SQL']),
      cert('advanced', level: 'Advanced', skills: ['Databases and SQL']),
    ];

    final advanced = recommender.recommendCertifications(
      analysis: analysis(),
      certifications: certs,
      experienceLevel: 'Advanced',
    );
    expect(ids(advanced.forGaps), ['advanced', 'beginner']);
    expect(advanced.forGaps.first.levelFits, isTrue);
    expect(advanced.forGaps.last.levelFits, isFalse);

    final none = recommender.recommendCertifications(
      analysis: analysis(),
      certifications: certs,
      experienceLevel: 'No Experience',
    );
    expect(ids(none.forGaps), ['beginner', 'advanced']);
    expect(none.forGaps.first.levelFits, isTrue);
  });

  test('more gaps covered beats a better level fit', () {
    final recs = recommender.recommendCertifications(
      analysis: analysis(),
      certifications: [
        cert('fits_level',
            level: 'Advanced', skills: ['Databases and SQL']),
        cert('more_gaps',
            level: 'Beginner', skills: ['Databases and SQL', 'Power BI']),
      ],
      experienceLevel: 'Advanced',
    );
    expect(ids(recs.forGaps), ['more_gaps', 'fits_level']);
  });

  test('verified certifications come first when everything else is equal', () {
    final recs = recommender.recommendCertifications(
      analysis: analysis(),
      certifications: [
        cert('a_unverified', verified: false, skills: ['Databases and SQL']),
        cert('b_verified', skills: ['Databases and SQL']),
      ],
    );
    expect(ids(recs.forGaps), ['b_verified', 'a_unverified']);
  });

  test('limits the "more for your goal" list', () {
    final recs = recommender.recommendCertifications(
      analysis: analysis(),
      certifications: [
        for (var i = 0; i < 10; i++) cert('x$i', skills: ['Python']),
      ],
      maxRelated: 3,
    );
    expect(recs.forGaps, isEmpty);
    expect(recs.forGoal.length, 3);
  });

  test('with no skill gaps every certification is a goal-only match', () {
    final recs = recommender.recommendCertifications(
      analysis: analysis(gaps: const []),
      certifications: [
        cert('a', skills: ['Databases and SQL']),
        cert('b', skills: ['Python']),
      ],
    );
    expect(recs.forGaps, isEmpty);
    expect(ids(recs.forGoal).toSet(), {'a', 'b'});
  });

  test('without a career goal nothing is recommended', () {
    final recs = recommender.recommendCertifications(
      analysis: {'skillGaps': ['SQL']},
      certifications: [cert('a', skills: ['Databases and SQL'])],
    );
    expect(recs.isEmpty, isTrue);
  });

  test('calculateSkillMatch counts the covered gaps', () {
    expect(
      recommender.calculateSkillMatch(
        ['SQL', 'Docker', 'Rust crab'],
        ['Databases and SQL', 'Containers'],
      ),
      2,
    );
  });

  test('preferredLevel maps the profile experience level', () {
    expect(ContentBasedRecommender.preferredLevel('No Experience'), 'Beginner');
    expect(ContentBasedRecommender.preferredLevel('Beginner'), 'Beginner');
    expect(
      ContentBasedRecommender.preferredLevel('Intermediate'),
      'Intermediate',
    );
    expect(ContentBasedRecommender.preferredLevel('Advanced'), 'Advanced');
    expect(ContentBasedRecommender.preferredLevel(null), isNull);
    expect(ContentBasedRecommender.preferredLevel('Expert'), isNull);
  });

  group('saved matches', () {
    final certs = [
      cert('a', skills: ['Databases and SQL', 'Power BI']),
      cert('b', skills: ['Databases and SQL']),
      cert('c', skills: ['Python']),
    ];
    final byId = {for (final c in certs) c.id: c};
    final skillGaps = ContentBasedRecommender.skillGapsOf(analysis());

    test('can be saved and restored', () {
      final recs = recommender.recommendCertifications(
        analysis: analysis(),
        certifications: certs,
      );
      final restored = CertificationRecommendations.fromSaved(
        recs.toMap(),
        byId: byId,
        careerGoalId: 'data_analyst',
        skillGaps: skillGaps,
      );

      expect(restored, isNotNull);
      expect(ids(restored!.forGaps), ids(recs.forGaps));
      expect(ids(restored.forGoal), ids(recs.forGoal));
      expect(restored.forGaps.first.matchedGaps,
          recs.forGaps.first.matchedGaps);
      expect(restored.hiddenOwned, recs.hiddenOwned);
      expect(restored.skillGaps, skillGaps);
    });

    test('skips certifications that left the catalog', () {
      final recs = recommender.recommendCertifications(
        analysis: analysis(),
        certifications: certs,
      );
      final restored = CertificationRecommendations.fromSaved(
        recs.toMap(),
        byId: {'a': certs.first},
        careerGoalId: 'data_analyst',
        skillGaps: skillGaps,
      );
      expect(ids(restored!.forGaps), ['a']);
      expect(restored.forGoal, isEmpty);
    });

    test('returns null when nothing saved is usable', () {
      final recs = recommender.recommendCertifications(
        analysis: analysis(),
        certifications: certs,
      );
      expect(
        CertificationRecommendations.fromSaved(
          recs.toMap(),
          byId: const {},
          careerGoalId: 'data_analyst',
          skillGaps: skillGaps,
        ),
        isNull,
      );
      expect(
        CertificationRecommendations.fromSaved(
          'not a map',
          byId: byId,
          careerGoalId: 'data_analyst',
          skillGaps: skillGaps,
        ),
        isNull,
      );
    });

    test('an empty saved result is still a result', () {
      final restored = CertificationRecommendations.fromSaved(
        {'forGaps': [], 'forGoal': [], 'hiddenOwned': 0},
        byId: byId,
        careerGoalId: 'data_analyst',
        skillGaps: skillGaps,
      );
      expect(restored, isNotNull);
      expect(restored!.isEmpty, isTrue);
    });
  });
}
