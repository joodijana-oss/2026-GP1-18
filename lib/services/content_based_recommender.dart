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
///  3. Count the target skills each certification works on. A skill gap
///     that names a certification itself ("CFOT", "CCNP") counts for that
///     certification ([gapNamesCertification]).
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

    // What the certification-name rule needs of each gap, worked out once
    // per call instead of once per certification.
    final gapNames = goal == CertificationGoal.closeGaps
        ? [for (final gap in targets) _GapName.of(gap)]
        : const <_GapName>[];
    final listNames = goal == CertificationGoal.closeGaps
        ? _CertificationNames.of(certifications)
        : null;

    final matched = <CertificationMatch>[];
    final others = <CertificationMatch>[];
    var hidden = 0;

    for (var position = 0; position < certifications.length; position++) {
      final cert = certifications[position];
      if (goalId.isEmpty || !cert.careerPaths.contains(goalId)) continue;
      if (_isHeld(cert, held)) {
        hidden++;
        continue;
      }

      final byWords = SkillMatcher.matchedSkills(
        targets,
        cert.skills,
        evidence: '${cert.name} ${cert.description} ${cert.skills.join(' ')}',
      );
      // Both lists keep the order of the targets, so a ranking where no
      // gap names a certification is exactly what words alone give.
      final List<String> skills;
      if (listNames == null) {
        skills = byWords;
      } else {
        final certNames = listNames.at(position);
        skills = [
          for (var g = 0; g < targets.length; g++)
            if (byWords.contains(targets[g]) ||
                gapNames[g].names(certNames))
              targets[g],
        ];
      }
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

  /// True when the skill gap [gap] names the certification [cert] itself.
  /// Job postings ask for certifications by name, and the synonym table
  /// holds skills, not certifications, so without this a "CFOT" gap would
  /// never count for the CFOT certification. A gap names a certification
  /// when it is its short name or its full name. It also names a family of
  /// certifications when it is written in capitals, is the first words of
  /// the short name ("CCNP" for "CCNP Enterprise" and "CCNP Data
  /// Center"), and is not a name the synonym table knows: a known name is a
  /// skill or a platform with its own matching, so "AWS" is not read as
  /// every AWS certification, nor "Linux" as "Linux+". The names are
  /// compared with [SkillMatcher.identityKey], so "Data+" is not "Data",
  /// and a name of one or two letters never counts.
  ///
  /// The ranking runs the same rule with the gap and the certification
  /// names prepared once ([_GapName], [_CertificationNames]).
  static bool gapNamesCertification(String gap, Certification cert) =>
      _GapName.of(gap).names(_CertNames.of(cert));

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

/// A skill gap as the certification-name rule needs it
/// ([ContentBasedRecommender.gapNamesCertification]), worked out once.
class _GapName {
  /// [SkillMatcher.identityKey] of the gap, or empty when the name is too
  /// short to name a certification (one or two letters).
  final String key;

  /// Whether the gap may name a family of certifications: it is written in
  /// capitals and is not a name the synonym table knows.
  final bool family;

  const _GapName(this.key, this.family);

  factory _GapName.of(String gap) {
    final key = SkillMatcher.identityKey(gap);
    if (key.length < 3) return const _GapName('', false);
    return _GapName(
      key,
      gap.toUpperCase() == gap && !SkillMatcher.isKnownName(gap),
    );
  }

  /// True when this gap names the certification whose names are [cert].
  bool names(_CertNames cert) {
    if (key.isEmpty) return false;
    if (key == cert.short || key == cert.name) return true;
    return family && cert.short.isNotEmpty && cert.short.startsWith('$key ');
  }
}

/// The short name and the full name of one certification, as
/// [SkillMatcher.identityKey]s.
class _CertNames {
  final String short;
  final String name;

  const _CertNames(this.short, this.name);

  factory _CertNames.of(Certification cert) => _CertNames(
        SkillMatcher.identityKey(cert.shortName),
        SkillMatcher.identityKey(cert.name),
      );
}

/// What the ranking needs of a whole certification list, worked out once
/// per list and reused while the list still holds the same certifications
/// (kept in an Expando): the names of each certification for the
/// certification-name rule.
class _CertificationNames {
  _CertificationNames._(this._items)
      : _names = List<_CertNames?>.filled(_items.length, null);

  final List<Certification> _items;

  /// The names of each certification, worked out the first time the
  /// ranking asks for them (only the certifications of the career goal).
  final List<_CertNames?> _names;

  static final Expando<_CertificationNames> _cache =
      Expando<_CertificationNames>();

  static _CertificationNames of(List<Certification> list) {
    final cached = _cache[list];
    if (cached != null && cached._sameItems(list)) return cached;
    return _cache[list] =
        _CertificationNames._(List<Certification>.of(list, growable: false));
  }

  bool _sameItems(List<Certification> list) {
    if (list.length != _items.length) return false;
    for (var i = 0; i < list.length; i++) {
      if (!identical(list[i], _items[i])) return false;
    }
    return true;
  }

  /// The names of the certification at [position] in the list.
  _CertNames at(int position) =>
      _names[position] ??= _CertNames.of(_items[position]);
}
