import 'package:flutter_test/flutter_test.dart';
import 'package:masra/models/certification.dart';
import 'package:masra/services/content_based_recommender.dart';

Certification cert(
  String id, {
  String? name,
  String shortName = '',
  String examCode = '',
  String level = 'Beginner',
  List<String> paths = const ['data_analyst'],
  List<String> skills = const [],
  String description = 'Description',
  bool verified = true,
}) {
  return Certification(
    id: id,
    name: name ?? id,
    shortName: shortName,
    issuer: 'Issuer',
    examCode: examCode,
    level: level,
    category: 'Category',
    description: description,
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
  List<String> current = const ['Python', 'Excel'],
  List<String> held = const [],
}) {
  return {
    'careerGoalId': goal,
    'skillGaps': gaps,
    'currentSkills': current,
    'certifications': [for (final name in held) {'name': name}],
  };
}

List<String> ids(List<CertificationMatch> matches) =>
    matches.map((m) => m.certification.id).toList();

void main() {
  const recommender = ContentBasedRecommender();

  group('close my skill gaps', () {
    test('keeps only the career goal and ranks by gaps covered', () {
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
      expect(ids(recs.matched), ['two_gaps', 'one_gap']);
      expect(ids(recs.others), ['no_gap']);
      expect(recs.matched.first.matchedSkills, ['SQL', 'Power BI']);
      expect(recs.goal, CertificationGoal.closeGaps);
    });

    test('"All" returns every certification for the goal, with no cap', () {
      final certs = [
        for (var i = 0; i < 40; i++) cert('c$i', skills: ['Python']),
      ];
      final recs = recommender.recommendCertifications(
        analysis: analysis(),
        certifications: certs,
      );
      expect(recs.total, 40);
      expect(recs.top(null).length, 40);
      expect(recs.top(5).length, 5);
      expect(recs.top(10).length, 10);
    });

    test('top N puts gap matches first, then the rest for the goal', () {
      final recs = recommender.recommendCertifications(
        analysis: analysis(),
        certifications: [
          cert('goal_a', skills: ['Python']),
          cert('gap', skills: ['Power BI']),
          cert('goal_b', skills: ['Linux']),
        ],
      );
      expect(ids(recs.top(2)), ['gap', 'goal_a']);
    });
  });

  group('strengthen my skills', () {
    test('ranks by the current skills the certification builds on', () {
      final recs = recommender.recommendCertifications(
        analysis: analysis(current: ['Python', 'Excel', 'SQL']),
        goal: CertificationGoal.strengthenSkills,
        certifications: [
          cert('python_only', skills: ['Python']),
          cert('python_sql', skills: ['Python', 'Databases and SQL']),
          cert('gap_only', skills: ['Power BI']),
        ],
      );
      expect(ids(recs.matched), ['python_sql', 'python_only']);
      expect(recs.matched.first.matchedSkills, ['Python', 'SQL']);
      expect(recs.targetSkills, ['Python', 'Excel', 'SQL']);
      expect(ids(recs.others), ['gap_only']);
    });

    test('prefers the next level up', () {
      expect(
        ContentBasedRecommender.preferredLevel('Beginner',
            goal: CertificationGoal.strengthenSkills),
        'Intermediate',
      );
      expect(
        ContentBasedRecommender.preferredLevel('Advanced',
            goal: CertificationGoal.strengthenSkills),
        'Advanced',
      );
      expect(ContentBasedRecommender.preferredLevel('No Experience'),
          'Beginner');
      expect(ContentBasedRecommender.preferredLevel(null), isNull);

      final recs = recommender.recommendCertifications(
        analysis: analysis(current: ['Python']),
        goal: CertificationGoal.strengthenSkills,
        experienceLevel: 'Beginner',
        certifications: [
          cert('beginner', skills: ['Python']),
          cert('intermediate', level: 'Intermediate', skills: ['Python']),
        ],
      );
      expect(ids(recs.matched), ['intermediate', 'beginner']);
      expect(recs.matched.first.levelFits, isTrue);
    });
  });

  group('specific technologies need the certification to mention them', () {
    test('a JavaScript certification does not cover Node.js or Angular', () {
      final recs = recommender.recommendCertifications(
        analysis: analysis(
          goal: 'web_developer',
          gaps: ['JavaScript', 'Node.js', 'Angular', 'React.js'],
        ),
        certifications: [
          cert('sap_fiori',
              paths: ['web_developer'],
              skills: ['JavaScript', 'Frontend Frameworks'],
              description: 'SAP Fiori and SAPUI5 front-end apps.'),
          cert('full_stack',
              paths: ['web_developer'],
              skills: ['JavaScript', 'Frontend Frameworks'],
              description: 'Covers HTML, CSS, JavaScript, React, Node.js.'),
        ],
      );
      final byId = {for (final m in recs.ranked) m.certification.id: m};
      expect(byId['sap_fiori']!.matchedSkills, ['JavaScript']);
      expect(byId['full_stack']!.matchedSkills,
          ['JavaScript', 'Node.js', 'React.js']);
    });
  });

  group('certifications already in the CV', () {
    final catalog = [
      cert('secplus',
          name: 'CompTIA Security+',
          shortName: 'Security+',
          examCode: 'SY0-701',
          paths: ['cybersecurity_analyst'],
          skills: ['Information Security']),
      cert('secx',
          name: 'CompTIA SecurityX',
          shortName: 'SecurityX',
          paths: ['cybersecurity_analyst'],
          skills: ['Information Security']),
      cert('cloudsec',
          name: 'Certificate of Cloud Security Knowledge',
          shortName: 'CCSK',
          paths: ['cybersecurity_analyst'],
          skills: ['Cloud Security']),
      cert('az900',
          name: 'Microsoft Certified: Azure Fundamentals',
          shortName: 'AZ-900',
          paths: ['cybersecurity_analyst'],
          skills: ['Azure']),
      cert('gda',
          name: 'Google Data Analytics Professional Certificate',
          paths: ['cybersecurity_analyst'],
          skills: ['Data Analysis']),
    ];

    Set<String> hiddenFor(List<String> held) {
      final recs = recommender.recommendCertifications(
        analysis: analysis(goal: 'cybersecurity_analyst', held: held),
        certifications: catalog,
      );
      final shown = ids(recs.ranked).toSet();
      return catalog.map((c) => c.id).where((id) => !shown.contains(id)).toSet();
    }

    test('the same name, short name or exam code is hidden', () {
      expect(hiddenFor(['Security+']), {'secplus'});
      expect(hiddenFor(['CompTIA Security+ (SY0-701)']), {'secplus'});
      expect(hiddenFor(['SY0-701']), {'secplus'});
      expect(hiddenFor(['AZ-900']), {'az900'});
    });

    test('the same identifying words are hidden', () {
      expect(hiddenFor(['Google Data Analytics Certificate']), {'gda'});
    });

    test('a name that is only part of another name hides nothing extra', () {
      expect(hiddenFor(['Microsoft Certified']), isEmpty);
      expect(hiddenFor(['Network Security']), isEmpty);
      expect(hiddenFor(['Introduction to Cybersecurity']), isEmpty);
      expect(hiddenFor(['CompTIA Security+']), {'secplus'});
    });

    test('the hidden count is reported', () {
      final recs = recommender.recommendCertifications(
        analysis: analysis(goal: 'cybersecurity_analyst', held: ['Security+']),
        certifications: catalog,
      );
      expect(recs.hiddenOwned, 1);
    });
  });

  test('no career goal means no recommendations', () {
    final recs = recommender.recommendCertifications(
      analysis: analysis(goal: ''),
      certifications: [cert('a', skills: ['Python'])],
    );
    expect(recs.isEmpty, isTrue);
  });
}
