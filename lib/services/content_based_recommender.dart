import '../models/certification.dart';
import '../utils/skill_matcher.dart';

/// What the user wants the certifications to do for them.
enum CertificationGoal {
  /// Certifications that teach the skills the analysis found missing.
  closeGaps,

  /// Certifications that build on skills the user already has.
  strengthenSkills,
}

/// One recommended certification and why it was recommended.
class CertificationMatch {
  final Certification certification;

  /// The user's skills (as written in the analysis) that this certification
  /// works on: skill gaps it covers, or current skills it builds on,
  /// depending on the [CertificationGoal]. Empty for "also for your goal".
  final List<String> matchedSkills;

  /// True when the certification level is the one that suits the user for
  /// this goal (see [ContentBasedRecommender.preferredLevel]).
  final bool levelFits;

  const CertificationMatch({
    required this.certification,
    required this.matchedSkills,
    required this.levelFits,
  });

  int get matchCount => matchedSkills.length;
}

/// The result of [ContentBasedRecommender.recommendCertifications].
class CertificationRecommendations {
  final CertificationGoal goal;
  final String careerGoalId;

  /// The skills the ranking used: the skill gaps, or the current skills.
  final List<String> targetSkills;

  /// Certifications for the career goal that match at least one target
  /// skill, best first.
  final List<CertificationMatch> matched;

  /// All other certifications for the career goal, best first.
  final List<CertificationMatch> others;

  /// How many certifications were hidden because the CV already lists them.
  final int hiddenOwned;

  const CertificationRecommendations({
    required this.goal,
    required this.careerGoalId,
    required this.targetSkills,
    required this.matched,
    required this.others,
    required this.hiddenOwned,
  });

  /// Every certification for the career goal, best first.
  List<CertificationMatch> get ranked => [...matched, ...others];

  /// The best [limit] certifications, or all of them when [limit] is null.
  List<CertificationMatch> top(int? limit) =>
      limit == null ? ranked : ranked.take(limit).toList();

  int get total => matched.length + others.length;
  bool get isEmpty => total == 0;
}

/// Content-based recommender for certifications.
///
/// It needs no training data and no other users: it compares the content of
/// the user's analysis (career goal, skill gaps or current skills,
/// certifications already held) and profile (experience level) with the
/// content of each certification (career paths, skills, description, level).
///
/// Steps:
///  1. Keep certifications whose `careerPaths` contain the career goal.
///  2. Hide certifications the user already holds.
///  3. Count the target skills each certification works on.
///  4. Rank: more skills first, then the level that suits the user, then
///     verified certifications, then name.
class ContentBasedRecommender {
  const ContentBasedRecommender();

  CertificationRecommendations recommendCertifications({
    required Map<String, dynamic> analysis,
    required List<Certification> certifications,
    String? experienceLevel,
    CertificationGoal goal = CertificationGoal.closeGaps,
  }) {
    final goalId = analysis['careerGoalId']?.toString().trim() ?? '';
    final targets = goal == CertificationGoal.closeGaps
        ? skillGapsOf(analysis)
        : currentSkillsOf(analysis);
    final held = _heldCertifications(analysis['certifications']);

    final wantedLevel = preferredLevel(experienceLevel, goal: goal);
    final wantedRank = wantedLevel == null ? null : _levelRank(wantedLevel);

    final matched = <CertificationMatch>[];
    final others = <CertificationMatch>[];
    var hidden = 0;

    for (final cert in certifications) {
      if (goalId.isEmpty || !cert.careerPaths.contains(goalId)) continue;
      if (_isHeld(cert, held)) {
        hidden++;
        continue;
      }

      final skills = SkillMatcher.matchedSkills(
        targets,
        cert.skills,
        evidence: '${cert.name} ${cert.description} ${cert.skills.join(' ')}',
      );
      final match = CertificationMatch(
        certification: cert,
        matchedSkills: skills,
        levelFits: wantedRank != null && cert.levelRank == wantedRank,
      );
      (skills.isEmpty ? others : matched).add(match);
    }

    int levelDistance(CertificationMatch m) {
      final rank = m.certification.levelRank;
      return wantedRank == null ? rank : (rank - wantedRank).abs();
    }

    int byQuality(CertificationMatch a, CertificationMatch b) {
      final byLevel = levelDistance(a).compareTo(levelDistance(b));
      if (byLevel != 0) return byLevel;
      final byVerified = (b.certification.verified ? 1 : 0)
          .compareTo(a.certification.verified ? 1 : 0);
      if (byVerified != 0) return byVerified;
      return a.certification.name
          .toLowerCase()
          .compareTo(b.certification.name.toLowerCase());
    }

    matched.sort((a, b) {
      final bySkills = b.matchCount.compareTo(a.matchCount);
      if (bySkills != 0) return bySkills;
      return byQuality(a, b);
    });
    others.sort(byQuality);

    return CertificationRecommendations(
      goal: goal,
      careerGoalId: goalId,
      targetSkills: targets,
      matched: matched,
      others: others,
      hiddenOwned: hidden,
    );
  }

  /// The skill gaps written in an analysis document.
  static List<String> skillGapsOf(Map<String, dynamic> analysis) =>
      _stringList(analysis['skillGaps']);

  /// The current skills written in an analysis document.
  static List<String> currentSkillsOf(Map<String, dynamic> analysis) =>
      _stringList(analysis['currentSkills']);

  /// The certification level that suits an experience level from the
  /// profile ("No Experience", "Beginner", "Intermediate", "Advanced").
  /// To strengthen skills the user already has, the next level up suits
  /// better than the same level.
  static String? preferredLevel(
    String? experienceLevel, {
    CertificationGoal goal = CertificationGoal.closeGaps,
  }) {
    const levels = ['Beginner', 'Intermediate', 'Advanced'];
    final int index;
    switch (experienceLevel) {
      case 'No Experience':
      case 'Beginner':
        index = 0;
      case 'Intermediate':
        index = 1;
      case 'Advanced':
        index = 2;
      default:
        return null;
    }
    final step = goal == CertificationGoal.strengthenSkills ? 1 : 0;
    return levels[(index + step).clamp(0, levels.length - 1)];
  }

  // ---------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------
  static int _levelRank(String level) {
    switch (level) {
      case 'Beginner':
        return 0;
      case 'Intermediate':
        return 1;
      case 'Advanced':
        return 2;
      default:
        return 3;
    }
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return [];
    final result = <String>[];
    for (final value in raw) {
      final text = value.toString().trim();
      if (text.isNotEmpty && !result.contains(text)) result.add(text);
    }
    return result;
  }

  /// Normalized names of the certifications found in the CV
  /// (`analysis['certifications']` is a list of {name, issuer, year}).
  static List<String> _heldCertifications(dynamic raw) {
    if (raw is! List) return [];
    final names = <String>[];
    for (final item in raw) {
      final name = item is Map ? item['name'] : item;
      final text = SkillMatcher.normalize(name?.toString() ?? '');
      if (text.isNotEmpty) names.add(text);
    }
    return names;
  }

  /// Words that do not tell certifications apart.
  static const Set<String> _genericWords = {
    'certificate', 'certification', 'certified', 'professional', 'exam',
    'credential', 'course', 'program', 'programme', 'the', 'and', 'of', 'in',
  };

  /// The words that identify a certification name: no generic words and
  /// no codes or years ("sy0 701", "2024").
  static Set<String> _coreWords(String normalized) => normalized
      .split(' ')
      .where((w) =>
          w.isNotEmpty &&
          !_genericWords.contains(w) &&
          !RegExp(r'\d').hasMatch(w))
      .toSet();

  /// True when the CV already lists this certification:
  ///  - the same name or short name ("CompTIA Security+", "CCNA"), or
  ///  - its exam code ("SY0-701"), or
  ///  - the same identifying words ("Google Data Analytics Certificate" and
  ///    "Google Data Analytics Professional Certificate").
  /// A name is never matched just because it is part of a longer one, so
  /// "Security+" does not hide "Cloud Security" certifications and
  /// "Microsoft Certified" does not hide every Microsoft certification.
  static bool _isHeld(Certification cert, List<String> held) {
    if (held.isEmpty) return false;
    final names = <String>{
      SkillMatcher.normalize(cert.name),
      SkillMatcher.normalize(cert.shortName),
    }..remove('');
    final examCode = SkillMatcher.normalize(cert.examCode);
    final certCores = [
      for (final n in names) _coreWords(n),
    ].where((c) => c.length >= 2).toList();

    for (final h in held) {
      if (names.contains(h)) return true;
      if (examCode.isNotEmpty && ' $h '.contains(' $examCode ')) return true;
      final core = _coreWords(h);
      if (core.length >= 2 &&
          certCores.any((c) => c.length == core.length && c.containsAll(core))) {
        return true;
      }
    }
    return false;
  }
}
