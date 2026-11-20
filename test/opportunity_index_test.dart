import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:masra/models/opportunity.dart';
import 'package:masra/services/opportunity_index.dart';
import 'package:masra/utils/skill_matcher.dart';

Opportunity opp(
  String id, {
  String type = 'Course',
  String? title,
  String description = '',
  List<String> objectives = const [],
  List<String> requirements = const [],
  List<String> skills = const [],
  String duration = '',
  DateTime? start,
  DateTime? end,
}) {
  return Opportunity(
    id: id,
    source: 'coursera',
    provider: '',
    type: type,
    title: title ?? id,
    description: description,
    objectives: objectives,
    requirements: requirements,
    field: 'Field',
    location: 'Online',
    isFree: true,
    price: '',
    duration: duration,
    url: 'https://example.com',
    skills: skills,
    careerPathIds: const [],
    startDate: start,
    endDate: end,
    registrationDeadline: null,
  );
}

/// The hits of [skill] in a one-opportunity index, or null when not found.
/// Query expansion is off, as in the app.
FieldHits? hits(Opportunity opportunity, String skill, {bool expand = false}) {
  return OpportunityIndex.build([opportunity])
      .hitsFor(skill, expand: expand)[0];
}

void main() {
  group('tokens', () {
    test('words are normalized and plurals are stemmed', () {
      expect(OpportunityIndex.tokensOf('Microservices'), ['microservice']);
      expect(OpportunityIndex.tokensOf('REST APIs'), ['rest', 'api']);
      expect(OpportunityIndex.tokensOf('CI/CD Pipelines'),
          ['ci', 'cd', 'pipeline']);
      expect(OpportunityIndex.tokensOf('  '), isEmpty);
    });

    test('C-family names and & become words', () {
      expect(OpportunityIndex.tokensOf('C# & .NET'), ['csharp', 'and', 'net']);
      expect(OpportunityIndex.tokensOf('C++ basics'), ['cpp', 'basic']);
      expect(OpportunityIndex.tokensOf('R&D'), ['r', 'and', 'd']);
    });

    test('the scanner gives the same words as normalize on the catalogue', () {
      List<String> viaNormalize(String text) {
        final normalized =
            SkillMatcher.normalize(SkillMatcher.searchForm(text));
        if (normalized.isEmpty) return const [];
        return [
          for (final word in normalized.split(' ')) OpportunityIndex.stem(word),
        ];
      }

      var texts = 0;
      for (final record in jsonDecode(
        File('lib/assets/data/Masra_Opportunities.json').readAsStringSync(),
      ) as List) {
        final o =
            Opportunity.fromMap('', Map<String, dynamic>.from(record as Map));
        for (final text in [
          o.title,
          o.description,
          ...o.objectives,
          ...o.skills,
        ]) {
          expect(OpportunityIndex.tokensOf(text), viaNormalize(text),
              reason: text);
          texts++;
        }
      }
      expect(texts, greaterThan(2000));
    });

    test('short words and words ending in ss keep their s', () {
      expect(OpportunityIndex.stem('class'), 'class');
      expect(OpportunityIndex.stem('aws'), 'aws');
      expect(OpportunityIndex.stem('business'), 'business');
      expect(OpportunityIndex.stem('dashboards'), 'dashboard');
    });
  });

  group('search', () {
    test('singular and plural find each other', () {
      final o = opp('a', title: 'Building Microservices');
      expect(hits(o, 'Microservice')?.title, 1);
      expect(hits(o, 'Microservices')?.title, 1);
    });

    test('a phrase must be whole and in order', () {
      expect(hits(opp('a', title: 'Power BI Dashboards'), 'Power BI')?.title,
          1);
      expect(hits(opp('a', title: 'BI with power'), 'Power BI'), isNull);
      expect(hits(opp('a', title: 'Power of BI'), 'Power BI'), isNull);
    });

    test('a phrase does not run across two objectives', () {
      final split = opp('a', objectives: ['Learn power', 'BI dashboards']);
      expect(hits(split, 'Power BI'), isNull);

      final whole = opp('a', objectives: ['Learn Power BI', 'Dashboards']);
      expect(hits(whole, 'Power BI')?.objectives, 1);
    });

    test('requirements are never searched', () {
      final o = opp('a', requirements: ['Experience with Power BI']);
      expect(hits(o, 'Power BI'), isNull);
    });

    test('skill tags use the synonym table', () {
      final o = opp('a', skills: ['Databases and SQL', 'Python']);
      expect(hits(o, 'SQL')?.skills, 1);
      expect(hits(o, 'Python')?.skills, 1);
      expect(hits(o, 'Tableau'), isNull);
    });

    test('query expansion (off by default) finds another name of the skill',
        () {
      final o = opp('a', title: 'Relational Databases in Practice');
      expect(hits(o, 'SQL', expand: true)?.title, 1);
      expect(hits(o, 'SQL'), isNull);
      expect(OpportunityIndex.build([o]).hitsFor('SQL'), isEmpty);
    });

    test('NLP and Natural Language Processing find each other', () {
      final o = opp('a', title: 'Natural Language Processing in Practice');
      expect(hits(o, 'NLP')?.title, 1);
      expect(
        hits(opp('a', title: 'NLP for beginners'),
                'Natural Language Processing')
            ?.title,
        1,
      );
    });

    test('only opportunities with a hit are returned', () {
      final index = OpportunityIndex.build([
        opp('a', title: 'Cooking'),
        opp('b', title: 'Kubernetes in Action'),
        opp('c', skills: ['Kubernetes']),
      ]);
      expect(index.hitsFor('Kubernetes').keys, [1, 2]);
      expect(index.hitsFor(''), isEmpty);
    });
  });

  group('evidence rules', () {
    test('a one-word broad skill needs two mentions in a description', () {
      final once = opp('a', description: 'Covers some statistics.');
      expect(hits(once, 'Statistics'), isNull);

      final twice = opp('a',
          description: 'Statistics for analysts. Practise statistics daily.');
      expect(hits(twice, 'Statistics')?.description, 2);
    });

    test('one mention in the title or in a short objective is enough', () {
      expect(hits(opp('a', title: 'Statistics'), 'Statistics')?.title, 1);
      expect(
        hits(opp('a', objectives: ['Use statistics']), 'Statistics')
            ?.objectives,
        1,
      );
    });

    test('a one-word name in a long objective is only a loose mention', () {
      // 11 words, one generic mention: not evidence on its own.
      final long = opp('a', objectives: [
        'Analyze network traffic and apply defense, monitoring and initial '
            'response controls.',
      ]);
      final loose = hits(long, 'Monitoring')!;
      expect(loose.objectives, 0);
      expect(loose.looseObjectives, 1);
      expect(loose.hasEvidence, isFalse);

      // Two mentions in the objectives count.
      final twice = opp('a', objectives: [
        'Set up monitoring and logging for every service in the cloud.',
        'Build monitoring dashboards and alerts for the whole production team.',
      ]);
      expect(hits(twice, 'Monitoring')?.objectives, 2);

      // A title or a tag that names the skill makes one mention count.
      final titled = opp('a', title: 'Monitoring in Practice', objectives: [
        'Analyze network traffic and apply defense, monitoring and initial '
            'response controls.',
      ]);
      expect(hits(titled, 'Monitoring')?.objectives, 1);

      // A name of two words or a product counts with one mention.
      final named = opp('a', objectives: [
        'Plan the response to a breach and practise incident response with '
            'the whole team.',
        'Deploy the application and run every service with Docker on the '
            'production servers.',
      ]);
      expect(hits(named, 'Incident Response')?.objectives, 1);
      expect(hits(named, 'Kubernetes'), isNull);
    });

    test('a multi-word name counts with one mention in a description', () {
      final o = opp('a', description: 'Practise incident response.');
      expect(hits(o, 'Incident Response')?.description, 1);
    });

    test('a specific product counts with one mention in a description', () {
      final o = opp('a', description: 'Dashboards are built in Tableau.');
      expect(hits(o, 'Tableau')?.description, 1);
    });

    test('the short form of a product name is an ordinary word', () {
      // "node" is also a network node: one mention is not Node.js.
      final network = opp('a', description: 'Explains what a node does.');
      expect(hits(network, 'Node.js'), isNull);

      final named = opp('a', description: 'Build a server with Node.js.');
      expect(hits(named, 'Node.js')?.description, 1);
      final joined = opp('a', description: 'Build a server with NodeJS.');
      expect(hits(joined, 'Node.js')?.description, 1);

      // In a title, or twice in a description, the short form counts.
      expect(hits(opp('a', title: 'Node and Express'), 'Node.js')?.title, 1);
      final twice =
          opp('a', description: 'Install Node. Then run a Node script.');
      expect(hits(twice, 'Node.js')?.description, 2);
    });
  });

  group('overlapping names are counted once', () {
    test('"Docker containers" is one mention of Docker', () {
      // With query expansion, "docker containers" is also a name of Docker.
      final o = opp('a', description: 'Docker containers');
      expect(hits(o, 'Docker', expand: true)?.description, 1);
    });

    test('"React JS" is one mention of React', () {
      final o = opp('a', title: 'React JS for beginners');
      expect(hits(o, 'React')?.title, 1);
      expect(hits(o, 'React.js')?.title, 1);
    });

    test('two separate names are two mentions', () {
      final o = opp('a', title: 'Databases and SQL, then SQL queries');
      expect(hits(o, 'SQL')?.title, 2);
    });
  });

  group('C#, C++ and one-letter names', () {
    test('a C# gap does not match C or the c) of a list', () {
      expect(hits(opp('a', title: 'C for Everyone, Part 1'), 'C#'), isNull);
      expect(
        hits(
            opp('a',
                description: 'You will: a) read text b) train models '
                    'c) use T5 and BERT. Then c) again.'),
            'C#'),
        isNull,
      );
      expect(
        hits(opp('a', description: 'Build web APIs with C#.'), 'C#')
            ?.description,
        1,
      );
      expect(hits(opp('a', title: 'C# Fundamentals'), 'C#')?.title, 1);
    });

    test('a C++ gap does not match a C# course', () {
      final csharp = opp('a', title: 'C# Fundamentals', skills: ['C#']);
      expect(hits(csharp, 'C++'), isNull);
      expect(hits(opp('a', title: 'Modern C++17'), 'C++')?.title, 1);
    });

    test('a one-letter name needs the title or a tag', () {
      final list = opp('a',
          title: 'Machine learning',
          description: 'a) data b) models c) results, and c) again.');
      expect(hits(list, 'C'), isNull);

      final course = opp('a',
          title: 'C for Everyone',
          description: 'Write C programs. Compile C code.');
      final found = hits(course, 'C')!;
      expect(found.title, 1);
      expect(found.description, 2);
    });
  });

  group('namesItself', () {
    test('a tag that only stands for the skill does not name it', () {
      final index = OpportunityIndex.build([
        opp('text',
            title: 'Text models', skills: ['Natural Language Processing']),
        opp('net', title: 'Protecting networks', skills: ['Network Security']),
      ]);
      expect(index.namesItself(0, 'NLP'), isTrue);
      // The tag stands for Deep Learning (same synonym group) but does not
      // say it.
      expect(index.hitsFor('Deep Learning').containsKey(0), isTrue);
      expect(index.namesItself(0, 'Deep Learning'), isFalse);
      expect(index.namesItself(1, 'Network Security'), isTrue);
      // The tag stands for Firewall (same synonym group) but does not say it.
      expect(index.hitsFor('Firewall').containsKey(1), isTrue);
      expect(index.namesItself(1, 'Firewall'), isFalse);
    });
  });

  group('lengths', () {
    test('field lengths count words, and tags for skills', () {
      final index = OpportunityIndex.build([
        opp('a',
            title: 'Intro to SQL',
            description: 'One two three four',
            objectives: ['Learn SQL', 'Write queries'],
            skills: ['SQL', 'Databases']),
        opp('b', title: 'Kubernetes'),
      ]);
      expect(index.size, 2);
      expect(index.opportunityAt(1).id, 'b');
      expect(index.fieldLength(0, OpportunityField.title), 3);
      expect(index.fieldLength(0, OpportunityField.description), 4);
      expect(index.fieldLength(0, OpportunityField.objectives), 4);
      expect(index.fieldLength(0, OpportunityField.skills), 2);
      // Averages skip empty fields.
      expect(index.averageLength(OpportunityField.title), 2);
      expect(index.averageLength(OpportunityField.description), 4);
      expect(index.averageLength(OpportunityField.skills), 2);
    });

    test('an empty index has average length 1', () {
      final index = OpportunityIndex.build([]);
      expect(index.averageLength(OpportunityField.title), 1);
    });
  });

  group('estimated hours', () {
    test('hoursFromDuration reads weeks times hours per week', () {
      expect(
          OpportunityIndex.hoursFromDuration(
              '4 weeks of study, 3-5 hours/week.'),
          16);
      expect(
          OpportunityIndex.hoursFromDuration(
              'Five weeks of study, five hours a week.'),
          25);
      expect(
          OpportunityIndex.hoursFromDuration(
              'At the rate of 5 hours a week, it typically takes 6 weeks '
              'to complete this course.'),
          30);
      expect(
          OpportunityIndex.hoursFromDuration('4 weeks of study, 2–4 '
              'hours/week'),
          12);
      expect(OpportunityIndex.hoursFromDuration('~4 weeks/3 hrs per week'),
          12);
    });

    test('hoursFromDuration reads total hours and days', () {
      expect(OpportunityIndex.hoursFromDuration('11 hours'), 11);
      expect(
          OpportunityIndex.hoursFromDuration(
              '5 weeks of study, approximately 20 hours total'),
          20);
      expect(OpportunityIndex.hoursFromDuration('3 days, 6 hours /day'), 18);
    });

    test('hoursFromDuration gives null when the total is unknown', () {
      expect(OpportunityIndex.hoursFromDuration(''), isNull);
      expect(OpportunityIndex.hoursFromDuration('8 - 10 hours per module'),
          isNull);
      expect(OpportunityIndex.hoursFromDuration('2-4 hours per week'), isNull);
      expect(OpportunityIndex.hoursFromDuration('3 weeks'), isNull);
    });

    test('workingDays skips Fridays and Saturdays', () {
      // Sunday 22 November to Thursday 3 December 2026.
      expect(
        OpportunityIndex.workingDays(
            DateTime(2026, 11, 22), DateTime(2026, 12, 3)),
        10,
      );
      // Friday and Saturday only.
      expect(
        OpportunityIndex.workingDays(
            DateTime(2026, 11, 20), DateTime(2026, 11, 21)),
        0,
      );
      // Four full weeks.
      expect(
        OpportunityIndex.workingDays(
            DateTime(2026, 11, 1), DateTime(2026, 11, 28)),
        20,
      );
      expect(
        OpportunityIndex.workingDays(
            DateTime(2026, 11, 22), DateTime(2026, 11, 21)),
        0,
      );
    });

    test('estimatedHours uses the duration, then the dates, then the type',
        () {
      expect(
        OpportunityIndex.estimatedHours(opp('a',
            type: 'Bootcamp',
            duration: '11 hours',
            start: DateTime(2026, 11, 22),
            end: DateTime(2026, 12, 3))),
        11,
      );
      expect(
        OpportunityIndex.estimatedHours(opp('a',
            type: 'Training Program',
            start: DateTime(2026, 11, 22),
            end: DateTime(2026, 12, 3))),
        40,
      );
      // A one-day event has no span to measure.
      expect(
        OpportunityIndex.estimatedHours(opp('a',
            type: 'Webinar',
            start: DateTime(2026, 11, 22),
            end: DateTime(2026, 11, 22))),
        1.5,
      );
      expect(OpportunityIndex.estimatedHours(opp('a', type: 'Bootcamp')), 240);
      expect(OpportunityIndex.estimatedHours(opp('a', type: 'Course')), 14);
      expect(OpportunityIndex.estimatedHours(opp('a', type: 'Workshop')), 14);
    });
  });

  group('level', () {
    test('the title is read first', () {
      expect(OpportunityIndex.levelOf(opp('a', title: 'Advanced Kubernetes')),
          2);
      expect(OpportunityIndex.levelOf(opp('a', title: 'Intermediate Python')),
          1);
      expect(OpportunityIndex.levelOf(opp('a', title: 'Introduction to SQL')),
          0);
      expect(OpportunityIndex.levelOf(opp('a', title: 'Linux Fundamentals')),
          0);
    });

    test('then the description and the requirements', () {
      expect(
        OpportunityIndex.levelOf(opp('a',
            title: 'Java',
            description: 'This is an intermediate Java course.')),
        1,
      );
      expect(
        OpportunityIndex.levelOf(opp('a',
            title: 'Python',
            requirements: ['No prior programming experience required.'])),
        0,
      );
      expect(
        OpportunityIndex.levelOf(
            opp('a', title: 'Python', description: 'Ideal for beginners.')),
        0,
      );
    });

    test('"advanced" in a description does not make it advanced', () {
      expect(
        OpportunityIndex.levelOf(opp('a',
            title: 'Excel for Data Analysis',
            description: 'You will reach an advanced level in Excel.')),
        isNull,
      );
      expect(OpportunityIndex.levelOf(opp('a', title: 'Kubernetes')), isNull);
    });
  });

  group('open flags and caching', () {
    test('openOn follows Opportunity.isOpen', () {
      final index = OpportunityIndex.build([
        opp('started', start: DateTime(2026, 11, 1)),
        opp('later', start: DateTime(2026, 12, 1)),
        opp('self_paced'),
      ]);
      expect(index.openOn(DateTime(2026, 11, 19)), [false, true, true]);
      expect(index.openOn(DateTime(2026, 12, 2)), [false, false, true]);
    });

    test('of() builds once per list object', () {
      final list = [opp('a', title: 'Kubernetes')];
      final first = OpportunityIndex.of(list);
      expect(identical(OpportunityIndex.of(list), first), isTrue);

      final copy = List<Opportunity>.of(list);
      expect(identical(OpportunityIndex.of(copy), first), isFalse);
    });

    test('of() indexes again when the list changed its length', () {
      final list = [opp('a', title: 'Kubernetes')];
      final first = OpportunityIndex.of(list);
      list.add(opp('b', title: 'Kubernetes Basics'));
      final second = OpportunityIndex.of(list);
      expect(identical(second, first), isFalse);
      expect(second.hitsFor('Kubernetes').keys, [0, 1]);
    });

    test('of() indexes again when an item was replaced in place', () {
      final list = [opp('a', title: 'Kubernetes'), opp('b', title: 'Linux')];
      final first = OpportunityIndex.of(list);
      expect(first.hitsFor('Quantum Basketweaving'), isEmpty);

      list[0] = opp('c', title: 'Quantum Basketweaving Course');
      final second = OpportunityIndex.of(list);
      expect(identical(second, first), isFalse);
      expect(second.hitsFor('Quantum Basketweaving').keys, [0]);
      // Unchanged again: the new index is reused.
      expect(identical(OpportunityIndex.of(list), second), isTrue);
    });

    test('cachedFor never builds and follows the same check as of()', () {
      final list = [opp('a', title: 'Kubernetes')];
      expect(OpportunityIndex.cachedFor(list), isNull);
      final index = OpportunityIndex.of(list);
      expect(identical(OpportunityIndex.cachedFor(list), index), isTrue);
      list[0] = opp('b', title: 'Linux');
      expect(OpportunityIndex.cachedFor(list), isNull);
    });

    test('adopt keeps an index built from copies, with this list\'s objects',
        () {
      final list = List<Opportunity>.unmodifiable(
          [opp('a', title: 'Kubernetes'), opp('b', title: 'Linux')]);
      // Copies with the same ids, as an index built on another isolate holds.
      final built = OpportunityIndex.build(
          [opp('a', title: 'Kubernetes'), opp('b', title: 'Linux')]);
      final hits = built.hitsFor('Kubernetes');

      expect(OpportunityIndex.adopt(list, built, builtFrom: list), isTrue);
      final kept = OpportunityIndex.cachedFor(list)!;
      expect(identical(OpportunityIndex.of(list), kept), isTrue);
      expect(identical(kept.opportunityAt(0), list[0]), isTrue);
      expect(identical(kept.opportunityAt(1), list[1]), isTrue);
      // The hits already found are reused, not searched again.
      expect(identical(kept.hitsFor('Kubernetes'), hits), isTrue);
    });

    test('adopt keeps nothing when the index does not fit the list', () {
      final list = [opp('a', title: 'Kubernetes'), opp('b', title: 'Linux')];
      final otherIds = OpportunityIndex.build(
          [opp('a', title: 'Kubernetes'), opp('x', title: 'Linux')]);
      expect(OpportunityIndex.adopt(list, otherIds, builtFrom: list), isFalse);
      expect(OpportunityIndex.cachedFor(list), isNull);

      // The list changed after the copy was sent.
      final snapshot = List<Opportunity>.unmodifiable(list);
      final built = OpportunityIndex.build(
          [opp('a', title: 'Kubernetes'), opp('b', title: 'Linux')]);
      list[1] = opp('b', title: 'Linux Administration');
      expect(OpportunityIndex.adopt(list, built, builtFrom: snapshot), isFalse);
      expect(OpportunityIndex.cachedFor(list), isNull);
    });

    test('hitsFor remembers its result', () {
      final index = OpportunityIndex.build([opp('a', title: 'Kubernetes')]);
      expect(
        identical(index.hitsFor('Kubernetes'), index.hitsFor('kubernetes')),
        isTrue,
      );
    });
  });
}
