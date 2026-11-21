/// The AI requests one career analysis makes.
///
/// The analysis pipeline (career_analysis_pipeline.dart) only knows this
/// interface. The app hands it the real AI service; the unit tests hand it
/// a fake that answers from memory, so every fallback path can be tested
/// without the network.
abstract interface class AnalysisRequests {
  /// Strengths, current skills, education, certifications, projects and
  /// experience found in the CV.
  Future<Map<String, dynamic>> analyzeCv({
    required String cvText,
  });

  /// The skills the job postings ask for, most requested first. With
  /// [singleSkillNames] the request asks for one skill per entry.
  Future<List<String>> extractMarketSkills({
    required String careerName,
    required String jobMarketText,
    bool singleSkillNames,
  });

  /// The target skills the current skills do not cover, judged from the
  /// two lists of names alone. [timeLimit] replaces the usual limit; the
  /// pipeline passes a shorter one when this request is the fallback of
  /// the evidence check, so the two together take about as long as this
  /// request alone used to.
  Future<List<String>> identifySkillGaps({
    required List<String> currentSkills,
    required List<String> targetSkills,
    Duration? timeLimit,
  });

  /// For every target skill, whether the CV text shows it: the raw
  /// `{skill, status, quote}` list of the answer.
  Future<dynamic> checkSkillsAgainstCv({
    required String cvText,
    required List<String> currentSkills,
    required List<String> certifications,
    required List<String> targetSkills,
    Duration? timeLimit,
  });
}
