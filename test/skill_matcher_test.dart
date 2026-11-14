import 'package:flutter_test/flutter_test.dart';
import 'package:masra/utils/skill_matcher.dart';

void main() {
  group('normalize', () {
    test('lower-cases and removes punctuation', () {
      expect(SkillMatcher.normalize('CI/CD'), 'ci cd');
      expect(SkillMatcher.normalize('T-SQL'), 't sql');
      expect(SkillMatcher.normalize('  Power   BI '), 'power bi');
      expect(
        SkillMatcher.normalize('Mobile Core (EPC / 5G)'),
        'mobile core epc 5g',
      );
      expect(SkillMatcher.normalize('Policies & Procedures'),
          'policies and procedures');
    });
  });

  group('matches: synonyms of certification skills', () {
    test('job-posting names match the certification skill names', () {
      expect(SkillMatcher.matches('SQL', 'Databases and SQL'), isTrue);
      expect(SkillMatcher.matches('MySQL', 'Databases and SQL'), isTrue);
      expect(SkillMatcher.matches('Microsoft Power BI', 'Power BI'), isTrue);
      expect(SkillMatcher.matches('Docker', 'Containers'), isTrue);
      expect(SkillMatcher.matches('k8s', 'Kubernetes'), isTrue);
      expect(SkillMatcher.matches('Amazon Web Services', 'AWS'), isTrue);
      expect(
        SkillMatcher.matches('Terraform', 'Infrastructure as Code'),
        isTrue,
      );
      expect(SkillMatcher.matches('SIEM', 'Security Operations'), isTrue);
    });

    test('is symmetric', () {
      expect(SkillMatcher.matches('Databases and SQL', 'SQL'), isTrue);
      expect(SkillMatcher.matches('Containers', 'Docker'), isTrue);
    });

    test('is not case or punctuation sensitive', () {
      expect(SkillMatcher.matches('power-bi', 'POWER BI'), isTrue);
      expect(SkillMatcher.matches('ci/cd', 'CI/CD'), isTrue);
    });
  });

  group('matches: words contained in each other', () {
    test('a longer name that contains a two-word skill matches', () {
      expect(
        SkillMatcher.matches('Network Security Fundamentals', 'Network Security'),
        isTrue,
      );
    });

    test('single vague words do not match by containment', () {
      expect(SkillMatcher.matches('Cloud', 'Cloud Security'), isFalse);
      expect(SkillMatcher.matches('Security', 'Cloud Security'), isFalse);
    });
  });

  group('matches: different skills', () {
    test('unrelated skills do not match', () {
      expect(SkillMatcher.matches('Python', 'Java'), isFalse);
      expect(SkillMatcher.matches('Tableau', 'Power BI'), isFalse);
      expect(SkillMatcher.matches('Docker', 'Kubernetes'), isFalse);
    });

    test('empty names never match', () {
      expect(SkillMatcher.matches('', 'Python'), isFalse);
      expect(SkillMatcher.matches('Python', ' '), isFalse);
      expect(SkillMatcher.matches('', ''), isFalse);
    });
  });

  group('matchedSkills', () {
    test('keeps the original spelling, order, and each gap once', () {
      final result = SkillMatcher.matchedSkills(
        ['SQL', 'Docker', 'SQL', 'Rust crab'],
        ['Databases and SQL', 'Containers'],
      );
      expect(result, ['SQL', 'Docker']);
    });

    test('a specific technology needs the certification to mention it', () {
      // "JavaScript" on the certification is not enough for a Node.js gap
      expect(
        SkillMatcher.matchedSkills(['Node.js', 'TypeScript'], ['JavaScript']),
        isEmpty,
      );
      expect(
        SkillMatcher.matchedSkills(
          ['Node.js', 'TypeScript', 'Tableau'],
          ['JavaScript'],
          evidence: 'Build APIs with Node.js and Express.',
        ),
        ['Node.js'],
      );
      expect(
        SkillMatcher.matchedSkills(['NodeJS'], [], evidence: 'Node.js apps'),
        ['NodeJS'],
      );
    });

    test('a multi-word gap written in the certification text counts', () {
      expect(
        SkillMatcher.matchedSkills(['Data Governance'], ['Data Analysis'],
            evidence: 'Covers data governance and data quality.'),
        ['Data Governance'],
      );
    });

    test('vague words do not create matches', () {
      expect(SkillMatcher.matchedSkills(['Automation'], ['Scripting']),
          isEmpty);
      expect(SkillMatcher.matchedSkills(['Problem Solving'], ['Troubleshooting']),
          isEmpty);
      expect(
        SkillMatcher.matchedSkills(
            ['Security Information and Event Management'],
            ['Information Security']),
        isEmpty,
      );
      expect(
        SkillMatcher.matchedSkills(
            ['Security Information and Event Management'],
            ['Security Operations']),
        ['Security Information and Event Management'],
      );
    });

    test('returns an empty list when nothing matches', () {
      expect(
        SkillMatcher.matchedSkills(['Photoshop'], ['Python', 'Linux']),
        isEmpty,
      );
    });
  });
}
