import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:masra/models/certification.dart';
import 'package:masra/services/certification_service.dart';
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

  group('a skill gap that names a certification', () {
    final telecom = [
      cert('ccnp_sp',
          name: 'Cisco Certified Network Professional Service Provider',
          shortName: 'CCNP Service Provider',
          paths: ['telecom_engineer'],
          skills: ['Networking Fundamentals']),
      cert('ccnp_ent',
          name: 'Cisco Certified Network Professional Enterprise',
          shortName: 'CCNP Enterprise',
          paths: ['telecom_engineer'],
          skills: ['Networking Fundamentals']),
      cert('fiber',
          name: 'Certified Fiber Optics Technician',
          shortName: 'CFOT',
          paths: ['telecom_engineer'],
          skills: ['Fiber Optics']),
    ];

    test('counts for that certification, by short name or family', () {
      final recs = recommender.recommendCertifications(
        analysis: analysis(goal: 'telecom_engineer', gaps: ['CFOT', 'CCNP']),
        certifications: telecom,
      );
      final matched = {
        for (final m in recs.matched) m.certification.id: m.matchedSkills,
      };
      expect(matched['fiber'], ['CFOT']);
      expect(matched['ccnp_sp'], ['CCNP']);
      expect(matched['ccnp_ent'], ['CCNP']);
    });

    test('changes nothing when no gap names a certification', () {
      final gaps = ['Fiber Optics', 'Routing'];
      final recs = recommender.recommendCertifications(
        analysis: analysis(goal: 'telecom_engineer', gaps: gaps),
        certifications: telecom,
      );
      expect(ids(recs.matched), ['fiber']);
      expect(recs.matched.single.matchedSkills, ['Fiber Optics']);
    });

    test('the rule itself', () {
      final dataPlus = cert('data_plus', shortName: 'Data+');
      final linuxPlus = cert('linux_plus', shortName: 'Linux+');
      bool names(String gap, Certification c) =>
          ContentBasedRecommender.gapNamesCertification(gap, c);

      expect(names('Data+', dataPlus), isTrue);
      expect(names('data +', dataPlus), isTrue);
      // "+" is part of the name: the skill "Data" is not the certification.
      expect(names('Data', dataPlus), isFalse);
      // A family is written in capitals; a skill name is not a family.
      expect(names('Linux', linuxPlus), isFalse);
      expect(names('CCNP', telecom.first), isTrue);
      expect(names('Ccnp', telecom.first), isFalse);
      // A name the synonym table knows keeps its own matching ("SQL" is a
      // skill, not a family of certifications).
      expect(names('SQL', cert('sql_ai', shortName: 'SQL AI Developer')),
          isFalse);
      expect(names('SQL AI Developer',
              cert('sql_ai', shortName: 'SQL AI Developer')),
          isTrue);
      // The full name counts too; one or two letters never do.
      expect(names('Certified Fiber Optics Technician', telecom.last), isTrue);
      expect(names('CC', cert('cc', shortName: 'CC')), isFalse);
    });

    test('is for skill gaps only, not for strengthening current skills', () {
      final recs = recommender.recommendCertifications(
        analysis: analysis(goal: 'telecom_engineer', current: ['CFOT']),
        certifications: telecom,
        goal: CertificationGoal.strengthenSkills,
      );
      expect(recs.matched, isEmpty);
    });
  });

  group('names with signs', () {
    // Made-up certifications, not from the bundled CSV.
    final catalog = [
      cert('web_api',
          paths: ['software_engineer'],
          skills: ['Programming Fundamentals', 'APIs'],
          description: 'Shows you can build web APIs with C# and Python.'),
      cert('engine',
          paths: ['software_engineer'],
          skills: ['Programming Fundamentals'],
          description: 'For developers who write game engines in C++17.'),
      cert('firmware',
          paths: ['software_engineer'],
          skills: ['Programming Fundamentals'],
          description: 'Firmware for small devices, written in C.'),
      cert('both',
          paths: ['software_engineer'],
          skills: ['Programming Fundamentals'],
          description: 'Moving old C code to modern C++.'),
    ];

    test('each C-family gap counts only where its own name is written', () {
      final recs = recommender.recommendCertifications(
        analysis: analysis(
            goal: 'software_engineer', gaps: ['C++', 'C#', 'C', 'APIs']),
        certifications: catalog,
      );
      final byId = {
        for (final m in recs.ranked) m.certification.id: m.matchedSkills,
      };
      expect(byId['web_api'], ['C#', 'APIs']);
      expect(byId['engine'], ['C++']);
      expect(byId['firmware'], ['C']);
      expect(byId['both'], ['C++', 'C']);
    });

    test('current skills follow the same rule', () {
      final recs = recommender.recommendCertifications(
        analysis: analysis(goal: 'software_engineer', current: ['C#']),
        goal: CertificationGoal.strengthenSkills,
        certifications: catalog,
      );
      expect(ids(recs.matched), ['web_api']);
      expect(recs.matched.single.matchedSkills, ['C#']);
    });

    test('on the bundled certifications a C-family gap needs its own name',
        () {
      // The bundled certifications go through the ranking itself, so the
      // check follows whatever text the recommender reads. Expected: a gap
      // counts exactly when the certification's own name, description or
      // skills write that name.
      final certs = CertificationService.parseCsv(
        File('lib/assets/data/Masra_IT_Certifications.csv')
            .readAsStringSync(),
      );
      final written = {
        'C++': RegExp(r'(?<![a-z0-9#+])c\+\+(?![a-z#+])',
            caseSensitive: false),
        'C#': RegExp(r'(?<![a-z0-9#+])c#(?![a-z#+])', caseSensitive: false),
        'C': RegExp(r'(?<![a-z0-9#+])c(?![a-z0-9#+])', caseSensitive: false),
      };
      final gaps = written.keys.toList();
      final covered = <String, List<String>>{};
      for (final path in {for (final c in certs) ...c.careerPaths}) {
        final recs = recommender.recommendCertifications(
          analysis: analysis(goal: path, gaps: gaps),
          certifications: certs,
        );
        for (final m in [...recs.matched, ...recs.others]) {
          covered[m.certification.id] = m.matchedSkills;
        }
      }
      expect(covered.length, certs.length);
      var checked = 0;
      for (final c in certs) {
        final text = '${c.name} ${c.description} ${c.skills.join(' ')}';
        written.forEach((gap, pattern) {
          expect(covered[c.id]!.contains(gap), pattern.hasMatch(text),
              reason: '${c.id} / $gap');
          checked++;
        });
      }
      expect(checked, greaterThan(800));
    });
  });

  group('a gap in the certification name', () {
    // Made-up certifications and products, not from the bundled CSV.
    // Pulumi is the one real name: a specific product the synonym table
    // already knows.
    final catalog = [
      cert('quill_dev',
          name: 'Quillstore Associate Developer',
          shortName: 'Quillstore Developer',
          paths: ['web_developer'],
          skills: ['Databases and SQL', 'Backend Development', 'APIs'],
          description: 'Build services on a document store with REST APIs.'),
      cert('backend_pc',
          name: 'Northwind Back-End Developer Certificate',
          paths: ['web_developer'],
          skills: ['Backend Development', 'Databases and SQL'],
          description:
              'Server-side apps with Python and SQL, with a short look at '
              'Quillstore.'),
      cert('kestrel_apps',
          name: 'Fennix Web Apps Professional Certificate',
          shortName: 'Kestrel Apps',
          paths: ['web_developer'],
          skills: ['JavaScript']),
      cert('torvic_plus',
          name: 'Torvic+ Web Defender Associate',
          shortName: 'TWDA',
          paths: ['web_developer'],
          skills: ['Web Security']),
      cert('torvic_sharp',
          name: 'Torvic# Service Builder',
          paths: ['web_developer'],
          skills: ['APIs']),
      cert('cpp_robotics',
          name: 'C++ Robotics Developer Associate',
          paths: ['web_developer'],
          skills: ['Programming Fundamentals'],
          description: 'Robot control in modern C++.'),
      cert('orvana_cloud',
          name: 'Orvana Cloud Ledger Consultant',
          paths: ['web_developer'],
          skills: ['Big Data']),
      cert('hexwall_pentest',
          name: 'Hexwall Penetration Testing Professional',
          paths: ['web_developer'],
          skills: ['Penetration Testing']),
      cert('fennix_cloud',
          name: 'Fennix Cloud Basics',
          paths: ['web_developer'],
          skills: ['Cloud Computing']),
      cert('skyforge',
          name: 'Skyforge Infrastructure Engineer Associate',
          shortName: 'Pulumi Stack Engineer',
          paths: ['web_developer'],
          skills: ['Infrastructure as Code'],
          description: 'Infrastructure as code on several clouds.'),
      cert('qx',
          name: 'Qx Platform Associate',
          paths: ['web_developer'],
          skills: ['Git']),
      cert('quill_model',
          name: 'Quillstore Data Modeling Specialist',
          paths: ['data_engineer'],
          skills: ['Database Design']),
      cert('orvana_data',
          name: 'Orvana Data Ledger Associate',
          paths: ['web_developer'],
          skills: ['Big Data']),
      cert('velmora',
          name: 'Velmora+ Tools with Velmora',
          paths: ['web_developer'],
          skills: ['APIs']),
    ];
    final byId = {for (final c in catalog) c.id: c};

    CertificationRecommendations close(List<String> gaps) =>
        recommender.recommendCertifications(
          analysis: analysis(goal: 'web_developer', gaps: gaps),
          certifications: catalog,
        );

    Map<String, List<String>> covered(List<String> gaps) => {
          for (final m in close(gaps).matched)
            m.certification.id: m.matchedSkills,
        };

    bool inName(String gap, String id) =>
        ContentBasedRecommender.nameContainsGap(gap, byId[id]!);

    test('a product the table does not know counts through the name', () {
      final recs = close(['SQL', 'Quillstore']);
      expect(ids(recs.matched), ['quill_dev', 'backend_pc']);
      expect(recs.matched.first.matchedSkills, ['SQL', 'Quillstore']);
      // The other certification names the product only in its description.
      expect(recs.matched.last.matchedSkills, ['SQL']);
      // Another career goal stays out, whatever its name says.
      expect(ids(recs.ranked), isNot(contains('quill_model')));
    });

    test('capitals do not matter, and the short name counts too', () {
      expect(covered(['quillstore']), {
        'quill_dev': ['quillstore'],
      });
      expect(covered(['QUILLSTORE']), {
        'quill_dev': ['QUILLSTORE'],
      });
      expect(covered(['Kestrel']), {
        'kestrel_apps': ['Kestrel'],
      });
      expect(inName('quillstore', 'quill_dev'), isTrue);
      expect(inName('Kestrel', 'kestrel_apps'), isTrue);
    });

    test('only whole words count, and only the name', () {
      expect(covered(['Quill']), isEmpty);
      expect(inName('Quill', 'quill_dev'), isFalse);
      expect(inName('Quillstore', 'backend_pc'), isFalse);
    });

    test('a name with a sign is another name', () {
      expect(covered(['Torvic', 'Torvic+', 'Torvic#']), {
        'torvic_plus': ['Torvic+'],
        'torvic_sharp': ['Torvic#'],
      });
      expect(inName('Torvic+', 'torvic_plus'), isTrue);
      expect(inName('Torvic#', 'torvic_sharp'), isTrue);
      expect(inName('Torvic', 'torvic_plus'), isFalse);
      expect(inName('Torvic', 'torvic_sharp'), isFalse);
      expect(inName('Torvic+', 'torvic_sharp'), isFalse);

      expect(covered(['C#', 'C++', 'C']), {
        'cpp_robotics': ['C++'],
      });
    });

    test('a later place in the name counts when the first has a sign', () {
      expect(covered(['Velmora', 'Velmora+']), {
        'velmora': ['Velmora', 'Velmora+'],
      });
      expect(inName('Velmora', 'velmora'), isTrue);
    });

    test('a gap of several words needs them side by side and in order', () {
      // Name: "Fennix Web Apps Professional Certificate", short name
      // "Kestrel Apps".
      expect(covered(['Fennix Web', 'Apps Web', 'Fennix Apps']), {
        'kestrel_apps': ['Fennix Web'],
      });
      expect(inName('Web Apps', 'kestrel_apps'), isTrue);
      expect(inName('Fennix Web Apps', 'kestrel_apps'), isTrue);
      // The last words of the name.
      expect(inName('Apps Professional Certificate', 'kestrel_apps'), isTrue);
      // Wrong order, or another word between them.
      expect(inName('Apps Web', 'kestrel_apps'), isFalse);
      expect(inName('Apps Kestrel', 'kestrel_apps'), isFalse);
      expect(inName('Fennix Apps', 'kestrel_apps'), isFalse);
      // A hyphen reads as a space; one joined word is another word.
      expect(inName('Kestrel-Apps', 'kestrel_apps'), isTrue);
      expect(inName('KestrelApps', 'kestrel_apps'), isFalse);
    });

    test('a specific product the table knows counts in the short name', () {
      expect(covered(['Pulumi']), {
        'skyforge': ['Pulumi'],
      });
      expect(inName('Pulumi', 'skyforge'), isTrue);
    });

    test('a broad skill name keeps its own matching', () {
      // A name the synonym table knows still counts through the skills.
      expect(covered(['Cloud']), {
        'fennix_cloud': ['Cloud'],
      });
      final both = covered(['Cloud', 'Testing']);
      expect(both.containsKey('orvana_cloud'), isFalse);
      expect(both.containsKey('hexwall_pentest'), isFalse);
      expect(inName('Cloud', 'orvana_cloud'), isFalse);
      expect(inName('Testing', 'hexwall_pentest'), isFalse);
      // One word of a longer skill name of the table ("Data Analysis").
      expect(covered(['Data']), isEmpty);
      expect(inName('Data', 'orvana_data'), isFalse);
    });

    test('one or two letters never count', () {
      expect(covered(['Qx']), isEmpty);
      expect(inName('Qx', 'qx'), isFalse);
    });

    test('is for skill gaps only, not for strengthening current skills', () {
      final recs = recommender.recommendCertifications(
        analysis: analysis(goal: 'web_developer', current: ['Quillstore']),
        certifications: catalog,
        goal: CertificationGoal.strengthenSkills,
      );
      expect(recs.matched, isEmpty);
    });
  });
}
