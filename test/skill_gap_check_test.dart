import 'package:flutter_test/flutter_test.dart';
import 'package:masra/services/skill_gap_check.dart';

const String cv = '''
Sara Example
Product intern, a Riyadh-based delivery company (Jun 2026 - Aug 2026)
- Interviewed 12 customers and turned their answers into a feature list
- Wrote user stories for the checkout re-design
Skills: Figma, SQL
''';

Map<String, String> answer(String skill, String status, [String quote = '']) =>
    {'skill': skill, 'status': status, 'quote': quote};

void main() {
  group('resolve', () {
    test('missing skills are the gaps, in the order of the target skills',
        () {
      final result = SkillGapCheck.resolve(
        targetSkills: const ['User Research', 'Roadmap Planning', 'SQL'],
        cvText: cv,
        raw: [
          answer('SQL', 'shown', 'Skills: Figma, SQL'),
          answer('Roadmap Planning', 'missing'),
          answer('User Research', 'shown', 'Interviewed 12 customers'),
        ],
      );
      expect(result.gaps, ['Roadmap Planning']);
      expect(result.unverifiedQuotes, 0);
      expect(result.toStoredList(), [
        {'skill': 'User Research', 'status': 'shown'},
        {'skill': 'Roadmap Planning', 'status': 'missing'},
        {'skill': 'SQL', 'status': 'shown'},
      ]);
    });

    test('a "shown" answer whose quote is not in the CV counts as missing',
        () {
      final result = SkillGapCheck.resolve(
        targetSkills: const ['A/B Testing', 'SQL'],
        cvText: cv,
        raw: [
          answer('A/B Testing', 'shown', 'Ran split tests on the home page'),
          answer('SQL', 'shown', ''),
        ],
      );
      expect(result.gaps, ['A/B Testing', 'SQL']);
      expect(result.unverifiedQuotes, 2);
    });

    test('a target skill the answer leaves out is a gap', () {
      final result = SkillGapCheck.resolve(
        targetSkills: const ['SQL', 'Roadmap Planning'],
        cvText: cv,
        raw: [answer('SQL', 'shown', 'Figma, SQL')],
      );
      expect(result.gaps, ['Roadmap Planning']);
    });

    test('a name that is not a target skill never becomes a gap', () {
      final result = SkillGapCheck.resolve(
        targetSkills: const ['SQL'],
        cvText: cv,
        raw: [
          answer('SQL', 'shown', 'Figma, SQL'),
          answer('Kanban', 'missing'),
        ],
      );
      expect(result.gaps, isEmpty);
      expect(result.statuses, hasLength(1));
    });

    test('names are compared without case and punctuation, and the target '
        'spelling is kept', () {
      final result = SkillGapCheck.resolve(
        targetSkills: const ['A/B Testing'],
        cvText: cv,
        raw: [answer('a b testing', 'missing')],
      );
      expect(result.gaps, ['A/B Testing']);
    });

    test('partly is no gap by default and a gap when the policy says so', () {
      final raw = [answer('User Stories', 'partly', 'Wrote user stories')];
      expect(
        SkillGapCheck.resolve(
                targetSkills: const ['User Stories'], cvText: cv, raw: raw)
            .gaps,
        isEmpty,
      );
      expect(
        SkillGapCheck.resolve(
          targetSkills: const ['User Stories'],
          cvText: cv,
          raw: raw,
          partlyIsGap: true,
        ).gaps,
        ['User Stories'],
      );
    });

    test('an unknown status counts as missing', () {
      final result = SkillGapCheck.resolve(
        targetSkills: const ['SQL'],
        cvText: cv,
        raw: [answer('SQL', 'probably', 'Figma, SQL')],
      );
      expect(result.gaps, ['SQL']);
    });

    test('garbage answers throw, so the caller can fall back', () {
      expect(
        () => SkillGapCheck.resolve(
            targetSkills: const ['SQL'], cvText: cv, raw: 'not a list'),
        throwsFormatException,
      );
      expect(
        () => SkillGapCheck.resolve(
            targetSkills: const ['SQL'], cvText: cv, raw: null),
        throwsFormatException,
      );
      expect(
        () => SkillGapCheck.resolve(
          targetSkills: const ['SQL'],
          cvText: cv,
          raw: [
            'text',
            {'name': 'SQL'},
            answer('Something else', 'shown', 'Figma, SQL'),
          ],
        ),
        throwsFormatException,
      );
    });

    test('no target skills means no gaps and no error', () {
      final result = SkillGapCheck.resolve(
          targetSkills: const [], cvText: cv, raw: const []);
      expect(result.gaps, isEmpty);
    });
  });

  group('which answer belongs to which skill', () {
    const languages = '''
Data science intern
- Built a churn model in C# and wrote the report
Skills: SQL, Data+ certified
''';

    test('C#, C++ and C never share an answer', () {
      final result = SkillGapCheck.resolve(
        targetSkills: const ['C#', 'C++', 'C'],
        cvText: languages,
        raw: [answer('C#', 'shown', 'Built a churn model in C#')],
      );
      expect(result.gaps, ['C++', 'C']);
      expect(result.toStoredList(), [
        {'skill': 'C#', 'status': 'shown'},
        {'skill': 'C++', 'status': 'missing'},
        {'skill': 'C', 'status': 'missing'},
      ]);
    });

    test('each skill gets its own answer when all three are answered', () {
      final result = SkillGapCheck.resolve(
        targetSkills: const ['C#', 'C++', 'C'],
        cvText: languages,
        raw: [
          answer('C', 'missing'),
          answer('C++', 'missing'),
          answer('C#', 'shown', 'Built a churn model in C#'),
        ],
      );
      expect(result.gaps, ['C++', 'C']);
    });

    test('a plus sign is part of the name: "Data+" is not "Data"', () {
      final result = SkillGapCheck.resolve(
        targetSkills: const ['Data', 'Data+'],
        cvText: languages,
        raw: [answer('Data+', 'shown', 'Data+ certified')],
      );
      expect(result.gaps, ['Data']);
    });

    test('the loose comparison is used only when it cannot mix skills up', () {
      // The answer dropped the "#". Only one target is "c" without its
      // signs, so the answer can only be about C#.
      expect(
        SkillGapCheck.resolve(
          targetSkills: const ['C#', 'SQL'],
          cvText: languages,
          raw: [
            answer('C', 'shown', 'Built a churn model in C#'),
            answer('SQL', 'missing'),
          ],
        ).gaps,
        ['SQL'],
      );
      // With C# and C++ both listed, a "C" answer belongs to neither.
      expect(
        SkillGapCheck.resolve(
          targetSkills: const ['C#', 'C++', 'SQL'],
          cvText: languages,
          raw: [
            answer('C', 'shown', 'Built a churn model in C#'),
            answer('SQL', 'missing'),
          ],
        ).gaps,
        ['C#', 'C++', 'SQL'],
      );
      // Punctuation alone ("C Sharp", "c#.") is not loose: the signs match.
      expect(
        SkillGapCheck.resolve(
          targetSkills: const ['C#'],
          cvText: languages,
          raw: [answer('C Sharp', 'shown', 'Built a churn model in C#')],
        ).gaps,
        isEmpty,
      );
    });

    test('one answer is never used for two skills', () {
      final answers = SkillGapCheck.answersFor(
        const ['Data+', 'Data'],
        [answer('data', 'missing')],
      );
      expect(answers.keys, ['Data']);
    });
  });

  group('quoteFound', () {
    test('an exact piece of the CV, whatever the case or punctuation', () {
      expect(SkillGapCheck.quoteFound(cv, 'interviewed 12 customers'), isTrue);
      expect(SkillGapCheck.quoteFound(cv, 'Skills - Figma / SQL'), isTrue);
    });

    test('a long quote may differ in one word out of five', () {
      expect(
        SkillGapCheck.quoteFound(
            cv, 'Interviewed 12 customers and turned their feedback'),
        isTrue,
      );
    });

    test('a short quote must be exact, and whole words only', () {
      expect(SkillGapCheck.quoteFound(cv, 'Figma Python'), isFalse);
      expect(SkillGapCheck.quoteFound(cv, 'custom'), isFalse);
    });

    test('an invented or empty quote is not found', () {
      expect(SkillGapCheck.quoteFound(cv, 'Led a team of five engineers'),
          isFalse);
      expect(SkillGapCheck.quoteFound(cv, ''), isFalse);
      expect(SkillGapCheck.quoteFound(cv, ' ... '), isFalse);
    });

    const pdf = '''
Network intern, a telecom operator
- Measured signal strength on 40
  rural sites and logged the results
- Drew coverage maps
Tools: spectrum analyzer
''';

    test('a quote broken by a PDF line break is found', () {
      expect(
        SkillGapCheck.quoteFound(
            pdf, 'Measured signal strength on 40 rural sites'),
        isTrue,
      );
      // One word differs, and the line break is still in the middle.
      expect(
        SkillGapCheck.quoteFound(
            pdf, 'Measured the signal strength on 40 rural sites'),
        isTrue,
      );
    });

    test('words picked from different lines never make a quote', () {
      // Every word is somewhere in the CV, but not together, in order.
      expect(
        SkillGapCheck.quoteFound(pdf, 'spectrum analyzer coverage maps'),
        isFalse,
      );
      expect(
        SkillGapCheck.quoteFound(
            pdf, 'Drew signal coverage maps with a spectrum analyzer'),
        isFalse,
      );
      expect(
        SkillGapCheck.quoteFound(pdf, 'rural sites logged signal strength'),
        isFalse,
      );
    });
  });
}
