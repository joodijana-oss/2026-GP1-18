import 'dart:convert';
import 'dart:io';

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

  group('query expansion and tags', () {
    test('a broad skill expands to the multi-word names of its group', () {
      final names = SkillMatcher.expansionsOf('SQL');
      expect(
        names,
        containsAll([
          'sql',
          'databases and sql',
          'relational databases',
          'sql queries',
        ]),
      );
      // Products and one-word synonyms are left out.
      expect(names, isNot(contains('mysql')));
      expect(names, isNot(contains('postgresql')));
      expect(names, isNot(contains('database')));
      expect(names.every((name) => name.length > 2), isTrue);

      final ml = SkillMatcher.expansionsOf('Machine Learning');
      expect(ml, contains('artificial intelligence'));
      expect(ml, isNot(contains('ai')));
      expect(ml, isNot(contains('ml')));
    });

    test('a specific product is never expanded', () {
      expect(SkillMatcher.expansionsOf('React'), ['react']);
      expect(
        SkillMatcher.expansionsOf('Node.js'),
        containsAll(['node js', 'nodejs', 'node']),
      );
      expect(SkillMatcher.expansionsOf('Node.js'), hasLength(3));
    });

    test('a skill outside the synonym table is only itself', () {
      expect(SkillMatcher.expansionsOf('Microservices'), ['microservices']);
      expect(SkillMatcher.expansionsOf(' '), isEmpty);
    });

    test('spellingsOf gives the ways a name is written', () {
      expect(SkillMatcher.spellingsOf('react js'),
          {'react js', 'reactjs', 'react'});
      expect(SkillMatcher.spellingsOf('power bi'), {'power bi', 'powerbi'});
      expect(SkillMatcher.spellingsOf('sql'), {'sql'});
    });

    test('isSpecific tells products from broad skills', () {
      expect(SkillMatcher.isSpecific('Tableau'), isTrue);
      expect(SkillMatcher.isSpecific('React.js'), isTrue);
      expect(SkillMatcher.isSpecific('SQL'), isFalse);
      expect(SkillMatcher.isSpecific('Docker'), isFalse);
    });

    test('tagCovers uses synonyms, but a product must be the tag itself',
        () {
      expect(SkillMatcher.tagCovers('SQL', 'Databases and SQL'), isTrue);
      expect(SkillMatcher.tagCovers('Docker', 'Containers'), isTrue);
      expect(SkillMatcher.tagCovers('React', 'React'), isTrue);
      expect(SkillMatcher.tagCovers('React', 'Frontend Frameworks'), isFalse);
      expect(SkillMatcher.tagCovers('SQL', 'Python'), isFalse);
      expect(SkillMatcher.tagCovers('', 'Python'), isFalse);
    });
  });

  group('C#, C++ and C', () {
    test('searchForm keeps the C-family names apart', () {
      expect(SkillMatcher.searchKey('C#'), 'csharp');
      expect(SkillMatcher.searchKey('c++'), 'cpp');
      expect(SkillMatcher.searchKey('F#'), 'fsharp');
      expect(SkillMatcher.searchKey('C'), 'c');
      expect(SkillMatcher.searchKey('C#/.NET developer'),
          'csharp net developer');
      expect(SkillMatcher.searchKey('C++17'), 'cpp 17');
      // Not a whole name: left as normalize gives it.
      expect(SkillMatcher.searchKey('abc#'), 'abc');
      expect(SkillMatcher.searchKey('a) one b) two c) three'),
          'a one b two c three');
    });

    test('normalize is unchanged, so certifications behave as before', () {
      expect(SkillMatcher.normalize('C#'), 'c');
      expect(SkillMatcher.normalize('C++'), 'c');
      expect(SkillMatcher.matches('C#', 'C++'), isTrue);
    });

    test('a tag of one C-family language does not cover another', () {
      expect(SkillMatcher.tagCovers('C#', 'C#'), isTrue);
      expect(SkillMatcher.tagCovers('C#', 'C'), isFalse);
      expect(SkillMatcher.tagCovers('C++', 'C#'), isFalse);
      expect(SkillMatcher.tagCovers('C', 'C++'), isFalse);
      expect(SkillMatcher.isSpecific('C#'), isTrue);
      expect(SkillMatcher.isSpecific('C++'), isTrue);
    });
  });

  group('fields of study', () {
    test('NLP and Computer Vision are fields, NLP is a spelling', () {
      expect(SkillMatcher.fieldOf('NLP'), 'natural language processing');
      expect(SkillMatcher.fieldOf('Natural Language Processing'),
          'natural language processing');
      expect(SkillMatcher.fieldOf('Computer Vision'), 'computer vision');
      expect(SkillMatcher.fieldOf('Deep Learning'), isNull);
      expect(SkillMatcher.searchNamesOf('NLP'),
          containsAll(['nlp', 'natural language processing']));
      expect(SkillMatcher.searchNamesOf('Computer Vision'),
          {'computer vision', 'computervision'});
    });

    test('a field is only covered by a tag of the same field', () {
      expect(SkillMatcher.tagCovers('NLP', 'Natural Language Processing'),
          isTrue);
      expect(SkillMatcher.tagCovers('Computer Vision', 'Deep Learning'),
          isFalse);
      expect(SkillMatcher.tagCovers('NLP', 'Deep Learning'), isFalse);
      const nlpTag = 'Natural Language Processing';
      expect(SkillMatcher.tagCovers('Computer Vision', nlpTag), isFalse);
      // The broader skill is still covered by a tag of the field.
      expect(SkillMatcher.tagCovers('Deep Learning', nlpTag), isTrue);
    });

    test('certifications still treat them as Deep Learning', () {
      expect(SkillMatcher.canonical('NLP'), 'deep learning');
      expect(SkillMatcher.matches('Computer Vision', 'Deep Learning'), isTrue);
    });

    test('a field is not widened to its synonym group', () {
      final names = SkillMatcher.expansionsOf('Computer Vision');
      expect(names.toSet(), {'computer vision', 'computervision'});
      expect(SkillMatcher.expansionsOf('NLP'),
          isNot(contains('neural networks')));
    });
  });

  test('prepared tags keep the old tag rule for ordinary names', () {
    // Every skill tag of the bundled catalogue against many gap names. For
    // names that are not C-family languages or fields of study, the tag
    // test must answer as it did before tags were prepared once.
    final tags = <String>{
      for (final record in jsonDecode(
        File('lib/assets/data/Masra_Opportunities.json').readAsStringSync(),
      ) as List)
        for (final tag in (record as Map)['skills'] as List) tag as String,
    };
    const gaps = [
      'SQL', 'Power BI', 'Python', 'Data Visualization', 'Tableau', 'Excel',
      'ETL', 'Incident Response', 'SIEM', 'Vulnerability Management',
      'Network Security', 'Threat Hunting', 'Splunk', 'Penetration Testing',
      'REST API', 'Software Testing', 'CI/CD', 'Git', 'Agile', 'Docker',
      'Microservices', 'Design Patterns', 'Kubernetes', 'Terraform', 'Azure',
      'Ansible', 'Monitoring', 'Figma', 'Prototyping', 'User Research',
      'Accessibility', 'Firewall', 'Routing', 'VPN', 'Wireless', 'LLM',
      'Generative AI', 'PyTorch', 'MLOps', 'Deep Learning', 'Oracle',
      'SQL Server', 'PostgreSQL', 'High Availability', 'React', 'Node.js',
      'AWS', 'System Design', 'Cloud',
    ];
    bool oldRule(String wanted, String tag) {
      final key = SkillMatcher.normalize(wanted);
      if (key.isEmpty) return false;
      if (SkillMatcher.isSpecific(wanted)) {
        return SkillMatcher.normalize(tag) == key;
      }
      return SkillMatcher.matches(wanted, tag);
    }

    var compared = 0;
    for (final gap in gaps) {
      final prepared = SkillMatcher.prepare(gap);
      for (final tag in tags) {
        if (SkillMatcher.fieldOf(tag) != null) continue;
        expect(
          SkillMatcher.tagCoversPrepared(prepared, SkillMatcher.prepare(tag)),
          oldRule(gap, tag),
          reason: '$gap / $tag',
        );
        compared++;
      }
    }
    expect(compared, greaterThan(5000));
  });
}
