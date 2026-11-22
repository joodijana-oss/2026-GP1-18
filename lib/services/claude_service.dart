import 'dart:convert';
 
import 'package:http/http.dart' as http;

import '../models/gap_link.dart';
import 'analysis_requests.dart';
 
/// The neutral name the rest of the app and the evaluation tools use for
/// the AI analysis service.
typedef AnalysisAi = ClaudeService;
 
class ClaudeService implements AnalysisRequests {
  static const String _apiKey =
      String.fromEnvironment('ANTHROPIC_API_KEY');
 
  static const String _endpoint =
      'https://api.anthropic.com/v1/messages';
 
  static const String _model =
      'claude-sonnet-5';

  // A stalled connection would otherwise leave the loading screen forever.
  // The CV review thinks before answering, so the limit is generous.
  static const Duration _requestTimeout = Duration(seconds: 120);

  /// Set only by the evaluation tools and the tests: the key to send
  /// instead of the one compiled into the app, and the HTTP client to send
  /// requests with. The app leaves both unset.
  String? apiKey;
  http.Client? client;

  /// The key every request uses.
  String get _effectiveKey => apiKey ?? _apiKey;
 
  // =========================================================
  // 1) ANALYZE USER CV
  // =========================================================
 
  @override
  Future<Map<String, dynamic>> analyzeCv({
    required String cvText,
  }) async {
    if (_effectiveKey.isEmpty) {
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
        allowedKeys: [
          'degree',
          'major',
          'institution',
          'year',
        ],
      ),
      'certifications': _normalizeMapList(
        decoded['certifications'],
        allowedKeys: [
          'name',
          'issuer',
          'year',
        ],
      ),
      'projects': _normalizeMapList(
        decoded['projects'],
        allowedKeys: [
          'name',
          'description',
        ],
      ),
      'experience': _normalizeMapList(
        decoded['experience'],
        allowedKeys: [
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
 
  /// With [singleSkillNames] the request also asks for one skill, tool or
  /// certification per entry ([singleSkillRule]).
  @override
  Future<List<String>> extractMarketSkills({
    required String careerName,
    required String jobMarketText,
    bool singleSkillNames = false,
  }) async {
    if (_effectiveKey.isEmpty) {
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
 
${singleSkillNames ? singleSkillRule : ''}Return exactly:
 
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
 
  /// [timeLimit] replaces the usual limit of two minutes. The analysis
  /// passes a shorter one when this request is the fallback of the CV
  /// evidence check.
  @override
  Future<List<String>> identifySkillGaps({
    required List<String> currentSkills,
    required List<String> targetSkills,
    Duration? timeLimit,
  }) async {
    if (_effectiveKey.isEmpty) {
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
      timeLimit: timeLimit,
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
  // 3b) SINGLE-SKILL NAMES AND CV EVIDENCE CHECK
  // =========================================================

  /// Added to the market-skills request when it must return one skill per
  /// entry. Without it the list repeats what postings do: several
  /// certifications or vendors packed into one entry, which no course can
  /// be matched to. The examples are from career goals the evaluation does
  /// not use.
  static const String singleSkillRule = '''
12. Every entry must name exactly ONE skill, tool or certification,
    the way a learner would search for it:
    - no parentheses and no examples inside a name;
    - no lists joined by "/", ",", "or" or "and";
    - no "such as", "e.g." or "including";
    - never a category that stands for several different things.
      Return the things themselves, each as its own entry, when the
      postings name them, and leave the category out.

Examples:
- "Design Tools (Figma, Sketch)" -> "Figma" and "Sketch"
- "Python or R" -> "Python" and "R"
- "ETL Pipelines (Airflow/dbt)" -> "ETL Pipelines"
- "Vendor Certifications" -> the certifications the postings name

''';

  /// The rules of the CV evidence check ([skillEvidencePrompt]). The
  /// examples are from career goals the evaluation does not use.
  static const String cvEvidenceRules = '''
STATUS:
- "shown": the CV gives direct evidence of the skill: work or internship
  tasks, a project, coursework with practical work, a lab, a competition,
  a certification that covers it, or the CV lists it as a skill.
- "partly": only weak or indirect evidence: a passing mention, a course
  title with no practical work, or a related skill that is not the same.
- "missing": the CV does not show it.

RULES:

1. Read the whole CV: experience, projects, education, certifications,
   activities and skills. Judge what the person did, not which words the
   CV uses. Evidence written as an activity counts.

Example:
- "Interviewed 12 customers and turned their answers into a feature
  list" shows "User Research", although the CV never uses that name.

2. A skill that is a certification is "shown" only when the person holds
   that certification. A similar certification is not the same one.

3. A skill that is a specific product or tool is "shown" only when the CV
   names that product or tool, or the person holds a certification about
   it.

4. Do not over-generalize. A related skill is not the same skill.

Examples:
- "Built wireframes in a design tool" does not show "Usability Testing".
- "Spliced and tested fibre cables" does not show "RF Planning".
- "Wrote SQL reports" does not show "Data Pipeline Orchestration".

5. For "shown" and "partly", put in "quote" a short piece of the CV text
   that is the evidence: 3 to 15 words from one line of the CV, copied
   exactly, character by character. Never write a quote that is not in the
   CV. For "missing", use an empty string.

6. Return every listed skill exactly once, with its name exactly as it is
   written in the list, in the same order.

7. Return ONLY valid JSON. Do not include markdown or explanations.

Return exactly:

{
  "skills": [
    {
      "skill": "",
      "status": "shown",
      "quote": ""
    }
  ]
}
''';

  /// The request that checks every market skill against the CV text.
  static String skillEvidencePrompt({
    required String cvText,
    required List<String> currentSkills,
    required List<String> certifications,
    required List<String> targetSkills,
  }) {
    return '''
You are checking a CV against the skills that job postings ask for,
for Masra, a Saudi career-development application for university
students and fresh graduates in Computing and IT.

CV TEXT
----------------
$cvText
----------------

SKILLS ALREADY EXTRACTED FROM THIS CV:
${jsonEncode(currentSkills)}

CERTIFICATIONS THE PERSON HOLDS (FROM THIS CV):
${jsonEncode(certifications)}

TARGET SKILLS IDENTIFIED FROM REAL JOB POSTINGS:
${jsonEncode(targetSkills)}

TASK:

For every TARGET SKILL, decide from the CV text whether the person
already shows it.

$cvEvidenceRules''';
  }

  /// The request that links market skills to the names the catalogues use
  /// (round 1's text, kept word for word so its stored answers stay
  /// comparable). The examples are from career goals the evaluation does
  /// not use.
  static String skillLinkPrompt({
    required List<String> skills,
    required List<String> concepts,
  }) {
    return '''
You are linking skill names taken from job postings to the skill names
of a learning catalogue, for Masra, a Saudi career-development
application. The catalogue holds courses, training programs and
certifications for Computing and IT.

SKILLS FROM JOB POSTINGS:
${jsonEncode(skills)}

CATALOGUE SKILL NAMES:
${jsonEncode(concepts)}

TASK:

For every skill from the job postings return:

- "kind":
  "skill" for a competency or an area of knowledge,
  "tool" for a specific product, platform, framework or programming
  language,
  "certification" for a named certificate or exam,
  "soft" for a personal or communication skill.

- "concepts": 0, 1 or 2 CATALOGUE SKILL NAMES that name the same skill,
  or a broader skill that fully contains it, so that a course on that
  catalogue skill would normally teach the job-posting skill.

- "phrases": 0 to 3 short phrases of 2 to 5 words that a course
  description would use when it teaches this skill, in other words than
  the skill name itself.

RULES:

1. Judge by meaning, not by shared words.

Examples:
- "Roadmap Planning" means product planning. It can link to a catalogue
  name about product management even with no word in common.
- "Radio Network Planning" must not link to a catalogue name about
  project planning only because both contain "planning".

2. Copy catalogue names exactly as they are written in CATALOGUE SKILL
   NAMES. Never return a name that is not in that list.

3. Return an empty "concepts" array when no catalogue name fits. A name
   that is only related, or that is narrower than the skill, does not
   fit. An empty array is a correct answer.

4. For kind "tool" and "certification", "concepts" must be empty unless
   a catalogue name is that very tool or certification.

5. Do not put product or vendor names in "phrases" unless the skill
   itself is that product.

6. Return every skill exactly once, with its name exactly as it is
   written in SKILLS FROM JOB POSTINGS, in the same order.

7. Return ONLY valid JSON. Do not include markdown or explanations.

Return exactly:

{
  "links": [
    {
      "skill": "",
      "kind": "skill",
      "concepts": [],
      "phrases": []
    }
  ]
}
''';
  }

  /// The typed link request. It separates a catalogue name that names the
  /// very same skill from a broader one that only teaches it, and asks for
  /// the words a course text uses when it really teaches the skill, so the
  /// recommenders can check a broader link against each course's own text
  /// (lib/models/gap_link.dart). The examples are invented and come from
  /// career goals the evaluation does not use.
  static String typedSkillLinkPrompt({
    required List<String> skills,
    required List<String> concepts,
  }) {
    return '''
You are linking skill names taken from job postings to the skill names
of a learning catalogue, for Masra, a Saudi career-development
application. The catalogue holds courses, training programs and
certifications for Computing and IT.

SKILLS FROM JOB POSTINGS:
${jsonEncode(skills)}

CATALOGUE SKILL NAMES:
${jsonEncode(concepts)}

TASK:

For every skill from the job postings return:

- "kind":
  "skill" for a competency or an area of knowledge,
  "tool" for a specific product, platform, framework or programming
  language,
  "certification" for a named certificate or exam,
  "soft" for a personal or communication skill.

- "same": 0, 1 or 2 CATALOGUE SKILL NAMES that name this very skill:
  another name for it, its abbreviation, or a wording variant. A learner
  who took a course on that catalogue skill has learned exactly this
  skill.

- "covers": 0, 1 or 2 CATALOGUE SKILL NAMES of a broader skill whose
  typical course teaches this skill as one of its main topics.
  Never put here:
  a neighbouring skill,
  a skill this one is only used together with,
  a skill that is a part of this one (a narrower skill),
  a wide field in which this skill is only a small part.

- "terms": 0 to 4 short terms of 1 to 4 words that the text of a course
  contains when it really teaches this skill: its key words, its usual
  abbreviation and its other common names. No vendor or product names
  unless the skill is that product. No general words of the broad field
  (a course that only says such a word does not teach this skill).

RULES:

1. Judge by meaning, not by shared words.

Examples:
- "Roadmap Planning" is deciding what a product will deliver and when.
  It is a main topic of a course on product management, so a catalogue
  name about product management goes in "covers", even with no word in
  common. Its terms could be "product roadmap" and "roadmap".
- "Drive Testing" and a catalogue name "Drive Test Measurement" are two
  names of one skill, so that catalogue name goes in "same".
- "Radio Network Planning" must not link to a catalogue name about
  project planning only because both contain "planning".

2. Copy catalogue names exactly as they are written in CATALOGUE SKILL
   NAMES. Never return a name that is not in that list. A name goes in
   "same" or in "covers", never in both.

3. An empty list is a correct answer, and it is better than a loose
   link. Leave "same" and "covers" empty when no catalogue name fits by
   the definitions above.

4. For kind "tool" and "certification", "same" may hold a catalogue name
   only when it is that very tool or certification, and "covers" must be
   empty.

5. Return every skill exactly once, with its name exactly as it is
   written in SKILLS FROM JOB POSTINGS, in the same order.

6. Return ONLY valid JSON. Do not include markdown or explanations.

Return exactly:

{
  "links": [
    {
      "skill": "",
      "kind": "skill",
      "same": [],
      "covers": [],
      "terms": []
    }
  ]
}
''';
  }

  /// Sends [prompt] and returns the JSON object of the answer. The CV
  /// evidence check and the evaluation tools use it (the tools send the
  /// texts of tools/gap_eval/arms/ through it). [timeLimit] replaces the
  /// usual limit of two minutes. [enableThinking] sends the request the
  /// way the ATS review does (tools/ats_eval); every other request keeps
  /// thinking off.
  Future<Map<String, dynamic>> requestJson({
    required String prompt,
    required int maxTokens,
    Duration? timeLimit,
    bool enableThinking = false,
  }) async {
    if (_effectiveKey.isEmpty) {
      throw Exception(
        'AI request failed: the API key is missing.',
      );
    }

    return _sendPrompt(
      prompt: prompt,
      maxTokens: maxTokens,
      enableThinking: enableThinking,
      timeLimit: timeLimit,
    );
  }

  /// Checks every target skill against the CV text. Returns the raw
  /// `skills` list of the answer (`{skill, status, quote}` per skill);
  /// lib/services/skill_gap_check.dart verifies it and turns it into gaps.
  @override
  Future<dynamic> checkSkillsAgainstCv({
    required String cvText,
    required List<String> currentSkills,
    required List<String> certifications,
    required List<String> targetSkills,
    Duration? timeLimit,
  }) async {
    final decoded = await requestJson(
      prompt: skillEvidencePrompt(
        cvText: cvText,
        currentSkills: currentSkills,
        certifications: certifications,
        targetSkills: targetSkills,
      ),
      maxTokens: 2500,
      timeLimit: timeLimit,
    );

    return decoded['skills'];
  }

  /// Links [skills] to the catalogue names in [concepts] with the wanted
  /// [request]. Returns the raw `links` list of the answer; the analysis
  /// pipeline checks it against the catalogue names
  /// (CareerAnalysisPipeline.linksFrom).
  @override
  Future<dynamic> linkSkillsToConcepts({
    required List<String> skills,
    required List<String> concepts,
    LinkRequest request = LinkRequest.typed,
    Duration? timeLimit,
  }) async {
    final decoded = await requestJson(
      prompt: request == LinkRequest.typed
          ? typedSkillLinkPrompt(skills: skills, concepts: concepts)
          : skillLinkPrompt(skills: skills, concepts: concepts),
      maxTokens: 3000,
      timeLimit: timeLimit,
    );

    return decoded['links'];
  }

  // =========================================================
  // 4) CV IMPROVEMENT (ATS REVIEW)
  // =========================================================
 
  // The five ATS-related areas required by the backlog, in display order.
  static const List<String> cvImprovementAreaKeys = [
    'cvStructure',
    'sectionOrganization',
    'keywordUsage',
    'readability',
    'contentFormatting',
  ];
 
  /// The text of the ATS review: what to check in each of the five
  /// areas, with the target career goal, today's date and the CV text
  /// in place. tools/ats_eval and the tests read it here.
  static String cvImprovementPrompt({
    required String cvText,
    required String careerName,
    required String today,
  }) {
    return '''
You are the CV Improvement Assistant for Masra,
a Saudi career-development application for university students
and fresh graduates in Computing and IT.
 
Review the CV below for Applicant Tracking System (ATS)
compatibility and quality.
 
TARGET CAREER GOAL:
$careerName
 
TODAY'S DATE:
$today
Use today's date to decide whether dates in the CV are in the past
or in the future. A degree or job whose end date is before today's
date is completed, not ongoing.
 
CV TEXT
----------------
$cvText
----------------
 
IMPORTANT CONTEXT:
The CV text was extracted from a PDF file. Visual details such as
fonts, colors, and exact layout are not available. Only judge
what can be seen in the extracted text, such as the order of
sections, headings, bullet points, dates, spacing, and wording.
 
TASK:
Evaluate the CV in exactly these five areas:
 
1. cvStructure
   Whether the CV contains the expected sections for a Computing
   or IT student or graduate (contact information, education,
   skills, projects, experience, certifications when available)
   and whether they appear in a logical order.
 
2. sectionOrganization
   Whether each section has a clear heading, content is placed in
   the correct section, and items inside sections are consistently
   ordered (for example, most recent first).
 
3. keywordUsage
   Whether the CV uses clear, standard technical keywords and tool
   names that ATS systems and recruiters look for, especially those
   relevant to the target career goal.
 
4. readability
   Whether sentences and bullet points are clear, concise, and
   start with strong action verbs, and whether achievements are
   described with specific results where possible.
 
5. contentFormatting
   Whether dates, headings, bullet points, and contact details are
   written in a consistent and ATS-friendly way.
 
RULES:
 
1. Only report real issues that are supported by the CV text.
 
2. Never invent experience, skills, or achievements that the user
   does not have.
 
3. Each issue must have one specific, personalized suggestion that
   refers to the content of this CV.
 
4. If an area has no real issue, return an empty array for it.
 
5. Report at most 3 issues per area, starting with the most
   important one.
 
6. Keep each issue and each suggestion to one or two sentences.
 
7. Write in clear English.
 
8. Before reporting an issue, check that it is definitely true.
   If you are not certain, do not report it.
 
9. A later date is more recent. For example, Feb 2026 is more
   recent than Oct 2025. "Most recent first" means the item with
   the later date appears first.
 
10. Only report a timeline problem (for example, a degree described
    as completed while it is still ongoing) if it is clearly wrong
    after comparing the dates with today's date.
 
11. Write each issue as one clear final statement. Do not include
    your reasoning, corrections, or doubts in the issue or
    suggestion text.
 
12. Do not report the same problem in more than one area.
 
13. Return ONLY valid JSON.
 
14. Do not include markdown or explanations outside the JSON.
 
Return EXACTLY this JSON structure:
 
{
  "cvStructure": [
    {
      "issue": "",
      "suggestion": ""
    }
  ],
  "sectionOrganization": [],
  "keywordUsage": [],
  "readability": [],
  "contentFormatting": []
}
''';
  }

  Future<Map<String, List<Map<String, dynamic>>>> improveCv({
    required String cvText,
    required String careerName,
  }) async {
    if (_effectiveKey.isEmpty) {
      throw Exception(
        'ANTHROPIC_API_KEY is missing.',
      );
    }
 
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
 
    final prompt = cvImprovementPrompt(
      cvText: cvText,
      careerName: careerName,
      today: today,
    );
 
    // Try twice before showing an error to the user
    Map<String, dynamic>? decoded;
    Object? lastError;
 
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        // Thinking is on here for more accurate reviews, so
        // max_tokens leaves room for both thinking and the answer.
        decoded = await _sendPrompt(
          prompt: prompt,
          maxTokens: 10000,
          enableThinking: true,
        );
        break;
      } catch (e) {
        lastError = e;
 
        if (attempt < 2) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
 
    if (decoded == null) {
      throw Exception('CV review failed: $lastError');
    }

    return cvImprovementFrom(decoded);
  }

  /// The five areas of an ATS review answer, as the screen shows them.
  /// The evaluation tools parse their answers here too, so both go
  /// through the same parsing.
  Map<String, List<Map<String, dynamic>>> cvImprovementFrom(
    Map<String, dynamic> decoded,
  ) {
    final reviewData = decoded;
 
    final result = <String, List<Map<String, dynamic>>>{};
 
    for (final key in cvImprovementAreaKeys) {
      // Keep only items that have both an issue and a suggestion
      result[key] = _normalizeMapList(
        reviewData[key],
        allowedKeys: [
          'issue',
          'suggestion',
        ],
      ).where((item) {
        return item['issue'].toString().isNotEmpty &&
            item['suggestion'].toString().isNotEmpty;
      }).toList();
    }
 
    return result;
  }
 
  // =========================================================
  // SHARED CLAUDE API REQUEST
  // =========================================================
 
  Future<Map<String, dynamic>> _sendPrompt({
    required String prompt,
    required int maxTokens,
    bool enableThinking = false,
    Duration? timeLimit,
  }) async {
    // Each request has its own HTTP client unless one was set. Closing it
    // after the answer is what http.post does too; closing it when the
    // time limit is reached also stops the request, so its connection does
    // not stay open in the background.
    final own = client == null ? http.Client() : null;
    final request = (client ?? own!).post(
      Uri.parse(
        _endpoint,
      ),
      headers: {
        'Content-Type':
            'application/json',
        'x-api-key':
            _effectiveKey,
        'anthropic-version':
            '2023-06-01',
      },
      body: jsonEncode({
        'model':
            _model,
        'max_tokens':
            maxTokens,
        // Claude Sonnet 5 thinks by default and thinking tokens count
        // toward max_tokens, which can leave no room for the answer.
        // Thinking stays off unless a feature asks for it.
        if (!enableThinking)
          'thinking': {
            'type': 'disabled',
          },
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

    final http.Response response;
    try {
      response = await request.timeout(timeLimit ?? _requestTimeout);
    } finally {
      own?.close();
    }
 
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
 
    // The answer was cut off before it finished
    if (body['stop_reason'] == 'max_tokens') {
      throw Exception(
        'Claude response was cut off (max_tokens reached).',
      );
    }
 
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
 
    // Keep only the JSON object, in case Claude adds text
    // before or after it
    final jsonStart = cleanText.indexOf('{');
    final jsonEnd = cleanText.lastIndexOf('}');
 
    if (jsonStart != -1 && jsonEnd > jsonStart) {
      cleanText = cleanText.substring(jsonStart, jsonEnd + 1);
    }
 
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