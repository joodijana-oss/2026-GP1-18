import 'dart:async';
import 'dart:convert';

import 'analysis_requests.dart';
import 'job_postings.dart';
import 'market_skill_names.dart';
import 'skill_gap_check.dart';

/// How the skill gaps of an analysis are found.
enum GapMethod {
  /// Compare the names of the current skills with the names of the market
  /// skills. The CV text is not read. This is the original analysis, and
  /// the fallback of [cvEvidence].
  namesOnly,

  /// Check every market skill against the CV text
  /// (lib/services/skill_gap_check.dart). When that request fails, the
  /// analysis falls back to [namesOnly].
  cvEvidence,
}

/// Which steps one analysis runs.
///
/// The app runs [app]. The evaluation tool (tools/gap_eval/evaluate_gaps.dart)
/// builds the other combinations to measure them against each other: the
/// original analysis (names only, market names as they come) and the
/// single-skill names with the comparison by names.
class AnalysisSettings {
  final GapMethod gapMethod;

  /// Ask the market-skills request for one skill per entry and clean what
  /// still arrives bundled (lib/services/market_skill_names.dart).
  final bool singleSkillNames;

  /// Whether a skill the CV only partly shows is a gap. It is not: the CV
  /// shows something to build on. This was settled on the development CVs
  /// only.
  final bool partlyIsGap;

  /// One attempt, no retry: the user is waiting on the loading screen.
  final Duration gapCheckLimit;

  /// The time limit of the comparison by names when it runs because the
  /// evidence check failed. The two together then take about as long as
  /// the comparison by names alone may take on its own (two minutes).
  final Duration fallbackLimit;

  const AnalysisSettings({
    this.gapMethod = GapMethod.namesOnly,
    this.singleSkillNames = false,
    this.partlyIsGap = false,
    this.gapCheckLimit = const Duration(seconds: 60),
    this.fallbackLimit = const Duration(seconds: 45),
  });

  /// What the app runs, chosen by the held-out evaluation of the skill
  /// gaps: single-skill market names, and the gap step reads the CV text
  /// and checks every market skill against a quote from it. It was the
  /// only approach that passed every decision rule (gaps for something the
  /// CV clearly shows fell from 18% to none, with recall inside its
  /// limit).
  static const AnalysisSettings app = AnalysisSettings(
    gapMethod: GapMethod.cvEvidence,
    singleSkillNames: true,
  );

  /// True when nothing new is switched on: the analysis then makes the
  /// same requests and saves the same fields as it always did.
  bool get isOriginal =>
      gapMethod == GapMethod.namesOnly && !singleSkillNames;
}

/// The skill names the app knows, read from its own data at run time.
class CatalogueNames {
  /// Whether a name is one skill the app knows
  /// ([MarketSkillNames.knownFrom]).
  final bool Function(String name) isKnown;

  const CatalogueNames._(this.isKnown);

  /// [opportunityTags] are the skill tags of the opportunities. The
  /// synonym table is always known. The app passes no
  /// [certificationSkills]: the certification skill names are the group
  /// names of the synonym table, so they are known anyway. The evaluation
  /// tool passes them all the same, as a check.
  factory CatalogueNames({
    Iterable<String> opportunityTags = const [],
    Iterable<String> certificationSkills = const [],
  }) {
    return CatalogueNames._(
      MarketSkillNames.knownFrom([...opportunityTags, ...certificationSkills]),
    );
  }

  /// The skill tags in the text of the bundled opportunities file (a JSON
  /// list of records with a `skills` list), each once. Anything unreadable
  /// is skipped, so a broken file gives no tags and the synonym table
  /// names alone. It has no Flutter import and touches no state, so the
  /// screen runs it away from the main isolate.
  static List<String> opportunityTagsFromJson(String jsonText) {
    final text =
        jsonText.startsWith('﻿') ? jsonText.substring(1) : jsonText;
    final tags = <String>{};
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        for (final record in decoded) {
          final skills = record is Map ? record['skills'] : null;
          if (skills is! List) continue;
          for (final skill in skills) {
            if (skill is String && skill.trim().isNotEmpty) tags.add(skill);
          }
        }
      }
    } on FormatException {
      // Fall through with the tags read so far (none).
    }
    return tags.toList();
  }
}

/// The skill gaps of one analysis and how they were found.
class GapOutcome {
  /// The gaps, in the order of the market skills.
  final List<String> gaps;

  /// `cv-evidence` or `names-only`: the path that produced [gaps] (stored
  /// as `gapMethod`).
  final String method;

  /// True when the wanted method failed and a fallback produced [gaps].
  final bool usedFallback;

  /// The evidence status of each checked skill (stored as
  /// `targetSkillStatus`), or null when the CV was not checked.
  final List<Map<String, String>>? statuses;

  /// Answers dropped because their quote is not in the CV.
  final int unverifiedQuotes;

  /// Why the wanted method failed, for the evaluation report.
  final String? failure;

  const GapOutcome({
    required this.gaps,
    required this.method,
    this.usedFallback = false,
    this.statuses,
    this.unverifiedQuotes = 0,
    this.failure,
  });

  static const String cvEvidence = 'cv-evidence';
  static const String namesOnly = 'names-only';
}

/// Thrown by [CareerAnalysisPipeline.run] when the caller asked it to stop
/// (the user left the screen). Nothing is saved.
class AnalysisCancelled implements Exception {
  const AnalysisCancelled();

  @override
  String toString() => 'The analysis was stopped.';
}

/// The AI steps of one career analysis, with their fallbacks.
///
///  1. Read the CV: strengths, current skills, certifications, projects.
///  2. Read the job postings of the career goal: the market skills, most
///     requested first ([marketSkills]).
///  3. Find the skill gaps ([skillGaps]).
///
/// Nothing new may cost the user their analysis. The evidence check has
/// one attempt and a time limit, and falls back to the comparison by
/// names. Only the steps that always existed can end in an error.
///
/// This file has no Flutter import. The career analysis screen runs it,
/// and so does the evaluation tool, which is how it measures the code that
/// ships and not a copy of it.
class CareerAnalysisPipeline {
  CareerAnalysisPipeline(
    this.ai, {
    this.settings = AnalysisSettings.app,
    CatalogueNames? names,
  }) : names = names ?? CatalogueNames();

  final AnalysisRequests ai;
  final AnalysisSettings settings;
  final CatalogueNames names;

  /// The fields this pipeline adds to an analysis. All are optional: every
  /// reader works without them, and an analysis saved before they existed
  /// works as it always did. [saveWithFallback] saves without them when
  /// the database refuses them.
  static const List<String> optionalFields = [
    'analysisVersion',
    'gapMethod',
    'targetSkillStatus',
  ];

  static const int analysisVersion = 2;

  /// Runs the whole analysis and returns the map that is saved.
  /// [onStep] is called with 1 when the CV has been read and with 2 when
  /// the market skills are known, for the progress display.
  ///
  /// [isCancelled] is asked after each of those two steps. When it says
  /// yes (the user left the screen), [AnalysisCancelled] is thrown and no
  /// further request is sent, as the screen did before the steps moved
  /// here. Once the gap step has started, the analysis finishes and is
  /// saved, as it always was.
  Future<Map<String, dynamic>> run({
    required String cvText,
    required String careerGoalId,
    required String careerName,
    required List<Map<String, String>> jobs,
    void Function(int step)? onStep,
    bool Function()? isCancelled,
  }) async {
    if (jobs.isEmpty) {
      throw Exception(
        'No relevant job postings were found for $careerName.',
      );
    }

    final cvAnalysis = await ai.analyzeCv(cvText: cvText);
    final currentSkills = List<String>.from(
      cvAnalysis['currentSkills'] ?? [],
    );
    if (isCancelled?.call() ?? false) throw const AnalysisCancelled();
    onStep?.call(1);

    final targetSkills = await marketSkills(
      careerName: careerName,
      jobMarketText: JobPostings.marketText(jobs),
    );
    if (targetSkills.isEmpty) {
      throw Exception(
        'No market skills could be identified.',
      );
    }
    if (isCancelled?.call() ?? false) throw const AnalysisCancelled();
    onStep?.call(2);

    final outcome = await skillGaps(
      cvText: cvText,
      cvAnalysis: cvAnalysis,
      targetSkills: targetSkills,
    );

    return <String, dynamic>{
      'strengths': List<String>.from(
        cvAnalysis['strengths'] ?? [],
      ),
      'currentSkills': currentSkills,
      'skillGaps': outcome.gaps,
      'targetSkills': targetSkills,

      // Keep structured AI output as-is.
      'education': cvAnalysis['education'] ?? [],
      'certifications': cvAnalysis['certifications'] ?? [],
      'projects': cvAnalysis['projects'] ?? [],
      'experience': cvAnalysis['experience'] ?? [],

      'careerGoalId': careerGoalId,
      'careerGoalName': careerName,
      'marketJobCount': jobs.length,
      'analysisSource': 'Masra Saudi job postings dataset',
      'marketBased': true,

      if (!settings.isOriginal) ...{
        'analysisVersion': analysisVersion,
        'gapMethod': outcome.method,
        if (outcome.statuses != null) 'targetSkillStatus': outcome.statuses,
      },
    };
  }

  // ---------------------------------------------------------
  // STEP 2: MARKET SKILLS
  // ---------------------------------------------------------

  /// The market skills of the career goal, most requested first.
  Future<List<String>> marketSkills({
    required String careerName,
    required String jobMarketText,
  }) async {
    final skills = await ai.extractMarketSkills(
      careerName: careerName,
      jobMarketText: jobMarketText,
      singleSkillNames: settings.singleSkillNames,
    );
    return cleanMarketSkills(skills);
  }

  /// [skills] as single-skill names when the setting asks for it,
  /// otherwise unchanged. If cleaning would leave nothing of a list that
  /// had names, the list is kept as it came: a market list with bundled
  /// names is still better than no analysis.
  List<String> cleanMarketSkills(List<String> skills) {
    if (!settings.singleSkillNames) return skills;
    final single = MarketSkillNames.single(skills, isKnown: names.isKnown);
    return single.isEmpty ? skills : single;
  }

  // ---------------------------------------------------------
  // STEP 3: SKILL GAPS
  // ---------------------------------------------------------

  /// The skill gaps, by the method of the settings, with its fallback.
  Future<GapOutcome> skillGaps({
    required String cvText,
    required Map<String, dynamic> cvAnalysis,
    required List<String> targetSkills,
  }) async {
    final currentSkills = List<String>.from(
      cvAnalysis['currentSkills'] ?? [],
    );
    Future<List<String>> byNames({Duration? timeLimit}) =>
        ai.identifySkillGaps(
          currentSkills: currentSkills,
          targetSkills: targetSkills,
          timeLimit: timeLimit,
        );

    switch (settings.gapMethod) {
      case GapMethod.namesOnly:
        return GapOutcome(gaps: await byNames(), method: GapOutcome.namesOnly);

      case GapMethod.cvEvidence:
        if (targetSkills.isEmpty) {
          return const GapOutcome(gaps: [], method: GapOutcome.cvEvidence);
        }
        try {
          final raw = await ai
              .checkSkillsAgainstCv(
                cvText: cvText,
                currentSkills: currentSkills,
                certifications: heldCertifications(cvAnalysis),
                targetSkills: targetSkills,
                timeLimit: settings.gapCheckLimit,
              )
              .timeout(settings.gapCheckLimit);
          final checked = SkillGapCheck.resolve(
            targetSkills: targetSkills,
            raw: raw,
            cvText: cvText,
            partlyIsGap: settings.partlyIsGap,
          );
          return GapOutcome(
            gaps: checked.gaps,
            method: GapOutcome.cvEvidence,
            statuses: checked.toStoredList(),
            unverifiedQuotes: checked.unverifiedQuotes,
          );
        } catch (error) {
          // One attempt only. The comparison by names runs at once, with a
          // shorter limit, so a stalled connection cannot make the gap
          // step much longer than it was before the evidence check.
          return GapOutcome(
            gaps: await byNames(timeLimit: settings.fallbackLimit),
            method: GapOutcome.namesOnly,
            usedFallback: true,
            failure: _reason(error),
          );
        }
    }
  }

  /// The certifications the CV lists, as "name (issuer)" texts.
  static List<String> heldCertifications(Map<String, dynamic> cvAnalysis) {
    final raw = cvAnalysis['certifications'];
    if (raw is! List) return const [];
    final result = <String>[];
    for (final item in raw) {
      final name =
          (item is Map ? item['name'] : item)?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      final issuer = item is Map ? item['issuer']?.toString().trim() ?? '' : '';
      result.add(issuer.isEmpty ? name : '$name ($issuer)');
    }
    return result;
  }

  // ---------------------------------------------------------
  // SAVING
  // ---------------------------------------------------------

  /// Saves [analysis] with [save]. The fields this pipeline adds are
  /// optional, so when the database refuses the write ([isRefusal] says
  /// which errors mean that; its rules may list the allowed fields), the
  /// analysis is saved once more without [optionalFields]: the user keeps
  /// the result, and every screen works as before. Any other error, or a
  /// refusal of an analysis that has none of those fields, is rethrown.
  static Future<void> saveWithFallback(
    Map<String, dynamic> analysis, {
    required Future<void> Function(Map<String, dynamic> analysis) save,
    required bool Function(Object error) isRefusal,
  }) async {
    try {
      await save(analysis);
    } catch (error) {
      if (!isRefusal(error) || !optionalFields.any(analysis.containsKey)) {
        rethrow;
      }
      await save(withoutOptionalFields(analysis));
    }
  }

  /// [analysis] without the fields this pipeline adds.
  static Map<String, dynamic> withoutOptionalFields(
    Map<String, dynamic> analysis,
  ) =>
      {
        for (final entry in analysis.entries)
          if (!optionalFields.contains(entry.key)) entry.key: entry.value,
      };

  static String _reason(Object error) =>
      error is TimeoutException ? 'time limit reached' : error.toString();
}
