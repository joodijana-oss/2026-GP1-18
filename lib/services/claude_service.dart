import 'dart:convert';

import 'package:http/http.dart' as http;

class ClaudeService {
  static const String _apiKey =
      String.fromEnvironment('ANTHROPIC_API_KEY');

  static const String _endpoint =
      'https://api.anthropic.com/v1/messages';

  static const String _model =
      'claude-sonnet-5';

  // =========================================================
  // 1) ANALYZE USER CV
  // =========================================================

  Future<Map<String, dynamic>> analyzeCv({
    required String cvText,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception(
        'ANTHROPIC_API_KEY is missing.',
      );
    }

    final prompt = '''
You are the CV analysis engine for Masra,
a Saudi career-development application for university students
and fresh graduates in Computing and IT.

Analyze the CV below.

CV TEXT
----------------
$cvText
----------------

TASK:
Extract factual information from the CV.

GENERAL RULES:

1. Never invent information.

2. Only extract information supported by the CV.

3. Strengths must be supported by evidence found in the CV.

4. currentSkills must contain concise normalized skill names.

5. currentSkills must include skills that are clearly demonstrated
   anywhere in the CV, not only skills explicitly listed in a
   "Skills" section.

6. A skill may be included when there is direct evidence from
   projects, coursework, certifications, or experience.

Examples:
- If the CV states that the user performed statistical analysis,
  include "Statistics".
- If the CV states that the user created visualizations using
  Matplotlib, include "Matplotlib".
- If the CV states that the user wrote SQL queries,
  include "SQL".
- If the CV states that the user cleaned and analyzed data,
  include "Data Analysis" when clearly supported.
- If the CV states that the user used Pandas,
  include "Pandas".

7. Do not infer broad skills from weak evidence.

Examples:
- Python alone does not prove Machine Learning.
- SQL alone does not prove full Database Management.
- Excel alone does not prove Power BI.
- Git alone does not prove DevOps.

8. If a section is missing, return an empty array.

9. Do NOT determine skill gaps.

10. Avoid duplicate information.

11. Return ONLY valid JSON.

12. Do not include markdown or explanations outside the JSON.

STRUCTURE RULES:

A) strengths
Return as an array of strings.

B) currentSkills
Return as an array of short normalized skill names.

C) education
Return each education item as an object with:
- degree
- major
- institution
- year

Use an empty string for any field that is not stated.

D) certifications
Return each certification as an object with:
- name
- issuer
- year

Use an empty string for missing fields.

E) projects
Return each project as an object with:
- name
- description

The description should briefly summarize what was done,
using only information from the CV.

F) experience
Return each experience item as an object with:
- title
- organization
- duration
- description

Use an empty string for fields that are not stated.

Return EXACTLY this JSON structure:

{
  "strengths": [],
  "currentSkills": [],
  "education": [
    {
      "degree": "",
      "major": "",
      "institution": "",
      "year": ""
    }
  ],
  "certifications": [
    {
      "name": "",
      "issuer": "",
      "year": ""
    }
  ],
  "projects": [
    {
      "name": "",
      "description": ""
    }
  ],
  "experience": [
    {
      "title": "",
      "organization": "",
      "duration": "",
      "description": ""
    }
  ]
}
''';

    final decoded = await _sendPrompt(
      prompt: prompt,
      maxTokens: 3000,
    );

    return {
      'strengths': _normalizeStringList(
        decoded['strengths'],
      ),
      'currentSkills': _normalizeStringList(
        decoded['currentSkills'],
      ),
      'education': _normalizeMapList(
        decoded['education'],
        allowedKeys: const [
          'degree',
          'major',
          'institution',
          'year',
        ],
      ),
      'certifications': _normalizeMapList(
        decoded['certifications'],
        allowedKeys: const [
          'name',
          'issuer',
          'year',
        ],
      ),
      'projects': _normalizeMapList(
        decoded['projects'],
        allowedKeys: const [
          'name',
          'description',
        ],
      ),
      'experience': _normalizeMapList(
        decoded['experience'],
        allowedKeys: const [
          'title',
          'organization',
          'duration',
          'description',
        ],
      ),
    };
  }

  // =========================================================
  // 2) EXTRACT MARKET SKILLS FROM REAL JOB POSTINGS
  // =========================================================

  Future<List<String>> extractMarketSkills({
    required String careerName,
    required String jobMarketText,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception(
        'ANTHROPIC_API_KEY is missing.',
      );
    }

    if (jobMarketText.trim().isEmpty) {
      throw Exception(
        'No relevant job postings were found.',
      );
    }

    final prompt = '''
You are analyzing real job-posting data for Masra,
a Saudi career-development application.

TARGET CAREER:
$careerName

REAL JOB POSTINGS:
----------------
$jobMarketText
----------------

TASK:

Identify the technical and professional skills that are genuinely
required or repeatedly requested in these job postings for the
target career.

RULES:

1. Base the result ONLY on the supplied job postings.

2. Do not invent skills that are not supported by the postings.

3. Ignore unrelated responsibilities, company descriptions,
   benefits, locations, and generic recruitment text.

4. Normalize equivalent skill names.

Examples:
- "Structured Query Language" and "SQL" -> "SQL"
- "Microsoft Power BI" and "PowerBI" -> "Power BI"
- "Python programming" -> "Python"

5. Prefer skills that appear repeatedly across multiple postings.

6. Include tools, programming languages, technical concepts,
   platforms, and important career-specific professional skills.

7. Do not include vague phrases such as:
   "hard worker", "good employee", or "positive attitude".

8. Return a maximum of 12 skills.

9. Order the skills from most relevant / most frequently supported
   to less frequent.

10. Return ONLY valid JSON.

11. Do not include markdown.

Return exactly:

{
  "targetSkills": []
}
''';

    final decoded = await _sendPrompt(
      prompt: prompt,
      maxTokens: 1200,
    );

    return _normalizeStringList(
      decoded['targetSkills'],
    );
  }

  // =========================================================
  // 3) SEMANTIC SKILL GAP COMPARISON
  // =========================================================

  Future<List<String>> identifySkillGaps({
    required List<String> currentSkills,
    required List<String> targetSkills,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception(
        'ANTHROPIC_API_KEY is missing.',
      );
    }

    if (targetSkills.isEmpty) {
      return [];
    }

    final currentSkillsJson =
        jsonEncode(currentSkills);

    final targetSkillsJson =
        jsonEncode(targetSkills);

    final prompt = '''
You are determining skill gaps for Masra,
a Saudi career-development application.

CURRENT SKILLS EXTRACTED FROM THE USER'S CV:
$currentSkillsJson

TARGET SKILLS IDENTIFIED FROM REAL JOB POSTINGS:
$targetSkillsJson

TASK:

Compare the user's current skills with the target skills
semantically, not only by exact wording.

Determine which TARGET SKILLS are not sufficiently supported
by the user's CURRENT SKILLS.

IMPORTANT RULES:

1. Skill gaps MUST come only from TARGET SKILLS.

2. Never invent or add a new skill.

3. If a target skill already appears explicitly in CURRENT SKILLS,
   it MUST NOT be returned as a skill gap.

4. Do not require exact wording when two skills clearly represent
   the same competency.

5. Consider direct practical evidence and common equivalences.

Examples:
- "Matplotlib" can provide evidence of "Data Visualization".
- "PowerBI" is equivalent to "Power BI".
- "Structured Query Language" is equivalent to "SQL".
- "Pandas" can support data manipulation and data analysis.

6. Do NOT over-generalize.

Examples:
- SQL alone does NOT prove full "Database Management".
- Excel alone does NOT prove "Power BI".
- Python alone does NOT prove "Machine Learning".
- Matplotlib does NOT prove Tableau or Power BI.

7. If a target skill is clearly already demonstrated by the current
   skills, do NOT return it as a gap.

8. If the evidence is insufficient, keep it as a gap.

9. Preserve the normalized name used in TARGET SKILLS.

10. Keep the original target-skill order.

11. Return ONLY valid JSON.

12. Do not include markdown or explanations.

Return exactly:

{
  "skillGaps": []
}
''';

    final decoded = await _sendPrompt(
      prompt: prompt,
      maxTokens: 1200,
    );

    final gaps = _normalizeStringList(
      decoded['skillGaps'],
    );

    final targetLookup =
        <String, String>{};

    for (final skill in targetSkills) {
      targetLookup[
        _normalizeForComparison(
          skill,
        )
      ] = skill;
    }

    final safeGaps =
        <String>[];

    for (final gap in gaps) {
      final normalizedGap =
          _normalizeForComparison(
        gap,
      );

      final originalTarget =
          targetLookup[
        normalizedGap
      ];

      if (originalTarget != null &&
          !safeGaps.contains(
            originalTarget,
          )) {
        safeGaps.add(
          originalTarget,
        );
      }
    }

    return safeGaps;
  }

  // =========================================================
  // SHARED CLAUDE API REQUEST
  // =========================================================

  Future<Map<String, dynamic>> _sendPrompt({
    required String prompt,
    required int maxTokens,
  }) async {
    final response = await http.post(
      Uri.parse(
        _endpoint,
      ),
      headers: {
        'Content-Type':
            'application/json',
        'x-api-key':
            _apiKey,
        'anthropic-version':
            '2023-06-01',
      },
      body: jsonEncode({
        'model':
            _model,
        'max_tokens':
            maxTokens,
        'messages': [
          {
            'role':
                'user',
            'content':
                prompt,
          },
        ],
      }),
    );

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw Exception(
        'Claude API error '
        '${response.statusCode}: '
        '${response.body}',
      );
    }

    final body =
        jsonDecode(
      response.body,
    ) as Map<String, dynamic>;

    final content =
        body['content'];

    if (content is! List ||
        content.isEmpty) {
      throw Exception(
        'Claude returned an empty response.',
      );
    }

    String? text;

    for (final item in content) {
      if (item is Map &&
          item['type'] == 'text') {
        text =
            item['text']
                ?.toString();

        break;
      }
    }

    if (text == null ||
        text.trim().isEmpty) {
      throw Exception(
        'Claude returned no text.',
      );
    }

    String cleanText =
        text.trim();

    cleanText = cleanText
        .replaceFirst(
          RegExp(
            r'^```json\s*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(
          RegExp(
            r'^```\s*',
          ),
          '',
        )
        .replaceFirst(
          RegExp(
            r'```\s*$',
          ),
          '',
        )
        .trim();

    dynamic decoded;

    try {
      decoded =
          jsonDecode(
        cleanText,
      );
    } catch (_) {
      throw Exception(
        'Claude returned invalid JSON: $cleanText',
      );
    }

    if (decoded
        is! Map<String, dynamic>) {
      if (decoded is Map) {
        return Map<String, dynamic>.from(
          decoded,
        );
      }

      throw Exception(
        'Invalid AI response format.',
      );
    }

    return decoded;
  }

  // =========================================================
  // NORMALIZE STRING LIST
  // =========================================================

  List<String> _normalizeStringList(
    dynamic value,
  ) {
    if (value is! List) {
      return [];
    }

    final result =
        <String>[];

    final seen =
        <String>{};

    for (final item in value) {
      final text =
          item.toString().trim();

      if (text.isEmpty) {
        continue;
      }

      final key =
          text.toLowerCase();

      if (seen.add(
        key,
      )) {
        result.add(
          text,
        );
      }
    }

    return result;
  }

  // =========================================================
  // NORMALIZE MAP LIST
  // =========================================================

  List<Map<String, dynamic>> _normalizeMapList(
    dynamic value, {
    required List<String> allowedKeys,
  }) {
    if (value is! List) {
      return [];
    }

    final result =
        <Map<String, dynamic>>[];

    for (final item in value) {
      if (item is! Map) {
        continue;
      }

      final map =
          <String, dynamic>{};

      for (final key in allowedKeys) {
        final rawValue =
            item[key];

        final text =
            rawValue
                ?.toString()
                .trim() ??
            '';

        map[key] =
            text;
      }

      final hasUsefulValue =
          map.values.any(
        (value) =>
            value
                .toString()
                .trim()
                .isNotEmpty,
      );

      if (hasUsefulValue) {
        result.add(
          map,
        );
      }
    }

    return result;
  }

  // =========================================================
  // NORMALIZE FOR COMPARISON
  // =========================================================

  String _normalizeForComparison(
    String value,
  ) {
    return value
        .toLowerCase()
        .replaceAll(
          '&',
          'and',
        )
        .replaceAll(
          '/',
          ' ',
        )
        .replaceAll(
          '-',
          ' ',
        )
        .replaceAll(
          RegExp(
            r'[^a-z0-9 ]',
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\s+',
          ),
          ' ',
        )
        .trim();
  }
}