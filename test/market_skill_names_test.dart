import 'package:flutter_test/flutter_test.dart';
import 'package:masra/services/market_skill_names.dart';
import 'package:masra/utils/skill_matcher.dart';

void main() {
  // A small vocabulary written for this test, standing in for the names
  // the app reads from its data at run time.
  final isKnown = MarketSkillNames.knownFrom(const [
    'UI/UX Design',
    'Research and Development',
    'Client/Server Architecture',
    'Python',
    'R',
    'Wireframing',
    'Prototyping',
  ]);

  List<String> single(List<String> names) =>
      MarketSkillNames.single(names, isKnown: isKnown);

  group('parentheses', () {
    test('a list of examples is dropped and the head is kept', () {
      expect(single(['ETL Pipelines (Airflow/dbt)']), ['ETL Pipelines']);
      expect(single(['Data Modelling (star schema, snowflake schema)']),
          ['Data Modelling']);
      expect(single(['Statistics (e.g. regression, hypothesis tests)']),
          ['Statistics']);
    });

    test('a category head is replaced by the items it lists', () {
      expect(single(['Design Tools (Figma, Sketch)']), ['Figma', 'Sketch']);
      expect(single(['Vendor Certifications (CCNA / JNCIA or HCIA)']),
          ['CCNA', 'JNCIA', 'HCIA']);
      expect(single(['Programming Languages such as Python, R']),
          ['Python', 'R']);
    });

    test('a category head is never kept in place of its items', () {
      expect(
        single([
          'Design Tools (whatever the team has agreed to use for mock-ups)',
        ]),
        isEmpty,
      );
    });

    test('a single note in parentheses is dropped too', () {
      expect(single(['Search Engine Optimization (SEO)']),
          ['Search Engine Optimization']);
    });
  });

  group('categories without items', () {
    test('a category with no items is dropped, as it names several things',
        () {
      expect(single(['Design Tools', 'Wireframing', 'Survey Platforms']),
          ['Wireframing']);
      expect(single(['Mapping Tools']), isEmpty);
      // In a list, each part is judged on its own.
      expect(single(['Prototyping Tools, Wireframing']), ['Wireframing']);
    });

    test('a known name that ends like a category is kept', () {
      // A name of the synonym table.
      expect(single(['Programming Languages']), ['Programming Languages']);
      final known = MarketSkillNames.knownFrom(const ['Collaboration Tools']);
      expect(MarketSkillNames.single(['Collaboration Tools'], isKnown: known),
          ['Collaboration Tools']);
    });
  });

  group('lists', () {
    test('comma, semicolon, "or" and slash lists are split', () {
      expect(single(['Python or R']), ['Python', 'R']);
      expect(single(['Wireframing, Prototyping']),
          ['Wireframing', 'Prototyping']);
      expect(single(['Figma/Sketch']), ['Figma', 'Sketch']);
      expect(single(['Stakeholder Interviews; Journey Mapping']),
          ['Stakeholder Interviews', 'Journey Mapping']);
    });

    test('a list with a long part is a sentence and stays whole', () {
      const name =
          'Requirements Gathering, writing clear user stories for teams';
      expect(single([name]), [name]);
    });

    test('"and" is split only between two known names', () {
      expect(single(['Wireframing and Prototyping']),
          ['Wireframing', 'Prototyping']);
      expect(single(['Identity and Access Management']),
          ['Identity and Access Management']);
    });

    test('a slash is not split in a name joined by "and"', () {
      // Splitting at the slash would give "Spectrum Planning and RF" and
      // "Microwave", a broken name.
      expect(single(['Spectrum Planning and RF/Microwave']),
          ['Spectrum Planning and RF/Microwave']);
      // Both sides known: split at "and", and the slash name stays whole.
      expect(single(['Wireframing and UI/UX Design']),
          ['Wireframing', 'UI/UX Design']);
    });
  });

  group('known names stay whole', () {
    test('a known slash name or "and" name is one skill', () {
      expect(single(['UI/UX Design']), ['UI/UX Design']);
      expect(single(['Client/Server Architecture']),
          ['Client/Server Architecture']);
      expect(single(['Research and Development']),
          ['Research and Development']);
    });

    test('a slash name with a side of two characters or fewer stays whole',
        () {
      expect(single(['A/B Testing']), ['A/B Testing']);
      expect(single(['TCP/IP']), ['TCP/IP']);
    });

    test('names of the synonym table count as known without being listed',
        () {
      // "CI/CD" is a name of the synonym table, not of the list above.
      expect(single(['CI/CD']), ['CI/CD']);
    });
  });

  group('order, duplicates and the limit', () {
    test('the parts take the place of the entry they came from', () {
      expect(
        single(['Usability Testing', 'Python or R', 'Wireframing']),
        ['Usability Testing', 'Python', 'R', 'Wireframing'],
      );
    });

    test('duplicates are removed, whatever the case or punctuation', () {
      expect(single(['Python', 'python', 'Python or R']), ['Python', 'R']);
      expect(single(['A/B Testing', 'a-b testing']), ['A/B Testing']);
    });

    test('names that differ only in "+" or "#" are different skills', () {
      expect(single(['C#', 'C++', 'Java', 'C']), ['C#', 'C++', 'Java', 'C']);
      expect(single(['Data+', 'Data', 'data+']), ['Data+', 'Data']);
    });

    test('at most 12 names are kept', () {
      final many = [for (var i = 0; i < 20; i++) 'Skill number$i'];
      expect(single(many), hasLength(12));
      expect(single(many).first, 'Skill number0');
    });

    test('single names pass through unchanged', () {
      const names = ['Usability Testing', 'User Research', 'Figma'];
      expect(single(names), names);
    });
  });

  group('looksBundled', () {
    bool bundled(String name) =>
        MarketSkillNames.looksBundled(name, isKnown: isKnown);

    test('parentheses that hold a list, and lists', () {
      expect(bundled('Design Tools (Figma, Sketch)'), isTrue);
      expect(bundled('ETL Pipelines (Airflow/dbt)'), isTrue);
      expect(bundled('Python or R'), isTrue);
      expect(bundled('Wireframing, Prototyping'), isTrue);
      expect(bundled('Figma/Sketch'), isTrue);
    });

    test('a category that is not a known name is bundled', () {
      expect(bundled('Design Tools'), isTrue);
      expect(bundled('Survey Platforms'), isTrue);
      expect(bundled('Programming Languages'), isFalse);
      expect(
        MarketSkillNames.looksBundled('Collaboration Tools',
            isKnown: MarketSkillNames.knownFrom(const ['Collaboration Tools'])),
        isFalse,
      );
    });

    test('single names and known slash names are not bundled', () {
      expect(bundled('Usability Testing'), isFalse);
      expect(bundled('UI/UX Design'), isFalse);
      expect(bundled('A/B Testing'), isFalse);
      expect(bundled('Search Engine Optimization (SEO)'), isFalse);
    });
  });

  group('names as identities', () {
    test('identityKey keeps "+" and "#", normalize does not', () {
      expect(SkillMatcher.identityKey('C++'), 'c plus plus');
      expect(SkillMatcher.identityKey('C#'), 'c sharp');
      expect(SkillMatcher.identityKey('Data+'), 'data plus');
      expect(SkillMatcher.identityKey('CI/CD'), 'ci cd');
      expect(SkillMatcher.normalize('C++'), SkillMatcher.normalize('C#'));
    });

    test('the names the synonym table knows', () {
      expect(SkillMatcher.isKnownName('databases & sql'), isTrue);
      expect(SkillMatcher.isKnownName('MySQL'), isTrue);
      expect(SkillMatcher.isKnownName('Roadmap Planning'), isFalse);
    });
  });
}
