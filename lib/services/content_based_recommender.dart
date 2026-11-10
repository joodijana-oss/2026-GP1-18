import '../models/certification.dart';
import '../utils/skill_matcher.dart';

/// One recommended certification and why it was recommended.
class CertificationMatch {
  final Certification certification;

  /// The user's skill gaps (as written in the analysis) that this
  /// certification covers. Empty for "more for your goal" items.
  final List<String> matchedGaps;

  /// True when the certification level equals the level that fits the
  /// user's experience level (Beginner for "No Experience" / "Beginner").
  final bool levelFits;

  const CertificationMatch({
    required this.certification,
    required this.matchedGaps,
    required this.levelFits,
  });

  int get gapCount => matchedGaps.length;

  /// What is saved in Firestore (the certification itself is read again
  /// from the catalog, so only its id is stored).
  Map<String, dynamic> toMap() => {
        'id': certification.id,
        'gaps': matchedGaps,
        'levelFits': levelFits,
      };

  /// Rebuilds a match from [toMap]; null when the certification is no
  /// longer in the catalog.
  static CertificationMatch? fromSaved(
    dynamic raw,
    Map<String, Certification> byId,
  ) {
    if (raw is! Map) return null;
    final cert = byId[raw['id']?.toString()];
    if (cert == null) return null;
    final gaps = raw['gaps'];
    return CertificationMatch(
      certification: cert,
      matchedGaps:
          gaps is List ? gaps.map((g) => g.toString()).toList() : <String>[],
      levelFits: raw['levelFits'] == true,
    );
  }
}

/// The result of [ContentBasedRecommender.recommendCertifications].
class CertificationRecommendations {
  final String careerGoalId;

  /// All skill gaps of the analysis (used to show "2 of 5 gaps covered").
  final List<String> skillGaps;

  /// Certifications for the career goal that cover at least one gap,
  /// best first.
  final List<CertificationMatch> forGaps;

  /// Other certifications for the career goal (no gap covered), best first.
  final List<CertificationMatch> forGoal;

  /// How many certifications were hidden because the user already holds
  /// them (listed in the CV).
  final int hiddenOwned;

  const CertificationRecommendations({
    required this.careerGoalId,
    required this.skillGaps,
    required this.forGaps,
    required this.forGoal,
    required this.hiddenOwned,
  });

  bool get isEmpty => forGaps.isEmpty && forGoal.isEmpty;

  /// What is saved inside the analysis document (`certificationMatches`).
  Map<String, dynamic> toMap() => {
        'forGaps': forGaps.map((m) => m.toMap()).toList(),
        'forGoal': forGoal.map((m) => m.toMap()).toList(),
        'hiddenOwned': hiddenOwned,
      };

  /// Rebuilds the recommendations from [toMap] using the current catalog.
  /// Returns null when the saved data cannot be used (malformed, or every
  /// saved certification has left the catalog) so the caller recomputes.
  static CertificationRecommendations? fromSaved(
    dynamic raw, {
    required Map<String, Certification> byId,
    required String careerGoalId,
    required List<String> skillGaps,
  }) {
    if (raw is! Map) return null;

    var savedCount = 0;
    List<CertificationMatch> read(dynamic list) {
      final result = <CertificationMatch>[];
      if (list is! List) return result;
      for (final item in list) {
        savedCount++;
        final match = CertificationMatch.fromSaved(item, byId);
        if (match != null) result.add(match);
      }
      return result;
    }

    final forGaps = read(raw['forGaps']);
    final forGoal = read(raw['forGoal']);
    if (savedCount > 0 && forGaps.isEmpty && forGoal.isEmpty) return null;

    final hidden = raw['hiddenOwned'];
    return CertificationRecommendations(
      careerGoalId: careerGoalId,
      skillGaps: skillGaps,
      forGaps: forGaps,
      forGoal: forGoal,
      hiddenOwned: hidden is int ? hidden : 0,
    );
  }
}

/// Content-based recommender for certifications.
///
/// It needs no training data and no other users: it compares the content of
/// the user's analysis (career goal, skill gaps, certifications already
/// held) and profile (experience level) with the content of each
/// certification (career paths, skills, level).
///
/// Steps:
///  1. Keep certifications whose `careerPaths` contain the career goal.
///  2. Hide certifications the user already holds.
///  3. Count the skill gaps each certification covers.
///  4. Rank: more gaps covered first, then the level closest to the user's
///     experience, then verified certifications, then name.
class ContentBasedRecommender {
  const ContentBasedRecommender();

  CertificationRecommendations recommendCertifications({
    required Map<String, dynamic> analysis,
    required List<Certification> certifications,
    String? experienceLevel,
    int maxRelated = 6,
  }) {
    final goalId = analysis['careerGoalId']?.toString().trim() ?? '';
    final gaps = _stringList(analysis['skillGaps']);
    final heldNames = _heldCertificationNames(analysis['certifications']);

    final wantedLevel = preferredLevel(experienceLevel);
    final wantedRank = wantedLevel == null ? null : _levelRank(wantedLevel);

    final forGaps = <CertificationMatch>[];
    final forGoal = <CertificationMatch>[];
    var hidden = 0;

    for (final cert in certifications) {
      if (goalId.isEmpty || !cert.careerPaths.contains(goalId)) continue;
      if (_isHeld(cert, heldNames)) {
        hidden++;
        continue;
      }

      final matched = SkillMatcher.matchedSkills(gaps, cert.skills);
      final match = CertificationMatch(
        certification: cert,
        matchedGaps: matched,
        levelFits: wantedRank != null && cert.levelRank == wantedRank,
      );
      if (matched.isEmpty) {
        forGoal.add(match);
      } else {
        forGaps.add(match);
      }
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

    forGaps.sort((a, b) {
      final byGaps = b.gapCount.compareTo(a.gapCount);
      if (byGaps != 0) return byGaps;
      return byQuality(a, b);
    });
    forGoal.sort(byQuality);

    return CertificationRecommendations(
      careerGoalId: goalId,
      skillGaps: gaps,
      forGaps: forGaps,
      forGoal: forGoal.take(maxRelated).toList(),
      hiddenOwned: hidden,
    );
  }

  /// The skill gaps written in an analysis document.
  static List<String> skillGapsOf(Map<String, dynamic> analysis) =>
      _stringList(analysis['skillGaps']);

  /// How many of [skillGaps] are covered by [itemSkills].
  int calculateSkillMatch(List<String> skillGaps, List<String> itemSkills) {
    return SkillMatcher.matchedSkills(skillGaps, itemSkills).length;
  }

  /// The certification level that fits an experience level from the profile
  /// ("No Experience", "Beginner", "Intermediate", "Advanced").
  static String? preferredLevel(String? experienceLevel) {
    switch (experienceLevel) {
      case 'No Experience':
      case 'Beginner':
        return 'Beginner';
      case 'Intermediate':
        return 'Intermediate';
      case 'Advanced':
        return 'Advanced';
      default:
        return null;
    }
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
  static List<String> _heldCertificationNames(dynamic raw) {
    if (raw is! List) return [];
    final names = <String>[];
    for (final item in raw) {
      final name = item is Map ? item['name'] : item;
      final text = SkillMatcher.normalize(name?.toString() ?? '');
      if (text.isNotEmpty) names.add(text);
    }
    return names;
  }

  /// True when the user's CV already lists this certification. A short
  /// name (like "ccna") must match exactly; longer names may be contained
  /// in each other ("CompTIA Security+" and "CompTIA Security+ (SY0-701)").
  static bool _isHeld(Certification cert, List<String> heldNames) {
    if (heldNames.isEmpty) return false;
    final names = <String>{
      SkillMatcher.normalize(cert.name),
      SkillMatcher.normalize(cert.shortName),
    }..remove('');

    for (final held in heldNames) {
      for (final name in names) {
        if (name == held) return true;
        final shorter = name.length <= held.length ? name : held;
        final longer = name.length <= held.length ? held : name;
        if (shorter.length >= 8 && longer.contains(shorter)) return true;
      }
    }
    return false;
  }
}
