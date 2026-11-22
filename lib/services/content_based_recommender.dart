import '../models/certification.dart';
import '../models/gap_link.dart';
import '../utils/skill_matcher.dart';
import 'link_support.dart';
import 'opportunity_index.dart' show OpportunityIndex;

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
///     certification ([gapNamesCertification]). A skill gap whose whole
///     name is in the certification's own name or short name counts for it
///     too ([nameContainsGap]); a broad skill word keeps its own matching.
///  4. Rank: more skills first, then the level that suits the user, then
///     verified certifications, then name.
///
/// Matching by meaning. A skill gap is written as job postings write it,
/// and its name may match no certification skill at all, although
/// certifications on that subject exist under another name. For such a gap
/// (and only for such a gap) the meaning links stored with the analysis
/// are used (`gapLinks`, lib/models/gap_link.dart; [links] says how). A
/// linked name of the same skill counts like the gap's own name. A linked
/// name of a broader skill counts for a certification only when the
/// certification's own text (its name and description) supports the gap:
/// it contains the gap's whole name, or a word of it that is distinctive
/// in this list of certifications. A gap whose own name matches a
/// certification skill is matched exactly as before, and so is an analysis
/// without links. The card still shows the user's own gap name.
class ContentBasedRecommender {
  const ContentBasedRecommender({this.links = LinkSettings.appCertifications});

  /// How stored meaning links are used. Whatever the setting, an analysis
  /// saved without links (no `gapLinks`) gives exactly the old list.
  final LinkSettings links;

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

    // Links are for skill gaps only: a current skill is the user's own
    // wording of something they know, not a market name to translate.
    final gapLinks = goal == CertificationGoal.closeGaps
        ? _linksFor(targets, analysis, certifications)
        : const <String, _CertificationLink>{};
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

      // The linked names that count for this certification, per gap.
      final names = <String, List<String>>{};
      final wordings = <String, List<String>>{};
      gapLinks.forEach((gap, link) {
        final allowed = [
          ...link.same,
          if (link.supported == null || link.supported!.contains(position))
            ...link.covers,
        ];
        if (allowed.isNotEmpty) names[gap] = allowed;
        if (link.searched.isNotEmpty) wordings[gap] = link.searched;
      });
      final byWords = SkillMatcher.matchedSkills(
        targets,
        cert.skills,
        evidence: '${cert.name} ${cert.description} ${cert.skills.join(' ')}',
        links: names,
        phrases: wordings,
      );
      // Both lists keep the order of the targets, so a ranking where no
      // gap names a certification or is in its name is exactly what words
      // alone give.
      final List<String> skills;
      if (listNames == null) {
        skills = byWords;
      } else {
        final certNames = listNames.at(position);
        skills = [
          for (var g = 0; g < targets.length; g++)
            if (byWords.contains(targets[g]) ||
                gapNames[g].names(certNames) ||
                gapNames[g].inNameOf(certNames))
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

  /// The meaning links written in an analysis document (`gapLinks`). Empty
  /// for an analysis saved before links existed.
  static List<GapLink> gapLinksOf(Map<String, dynamic> analysis) =>
      GapLink.listFrom(analysis['gapLinks']);

  /// The link each skill gap uses, for the gaps that are a hole in the
  /// certification catalogue: no skill of any certification matches the
  /// gap's own name ([SkillMatcher.matches]). A specific product, a gap the
  /// analysis calls a tool or a certification, and a separate field of
  /// study ([SkillMatcher.fieldOf]) never get one, as for opportunities:
  /// the table keeps Computer Vision apart from Deep Learning on purpose,
  /// and a link must not undo that.
  Map<String, _CertificationLink> _linksFor(
    List<String> gaps,
    Map<String, dynamic> analysis,
    List<Certification> certifications,
  ) {
    const none = <String, _CertificationLink>{};
    if (!links.enabled || analysis['gapLinks'] is! List) return none;
    final stored = GapLink.byGap(gapLinksOf(analysis));
    if (stored.isEmpty) return none;

    List<String> longEnough(Iterable<String> wordings) => [
          for (final wording in wordings)
            if (OpportunityIndex.tokensOf(wording).length >= 2) wording,
        ];

    final listNames = _CertificationNames.of(certifications);
    final result = <String, _CertificationLink>{};
    for (final gap in gaps) {
      final link = stored[gap];
      if (link == null ||
          link.isProduct ||
          SkillMatcher.isSpecific(gap) ||
          SkillMatcher.fieldOf(gap) != null) {
        continue;
      }
      if (!listNames.isHole(gap)) continue;
      final covers = links.useCovers ? link.covers : const <String>[];
      final searched = <String>[
        if (links.phraseSearch) ...longEnough(link.phrases),
        if (links.termEvidence && link.concepts.isEmpty)
          ...longEnough(link.supportTerms),
      ];
      if (link.same.isEmpty && covers.isEmpty && searched.isEmpty) continue;
      result[gap] = _CertificationLink(
        same: link.same,
        covers: covers,
        searched: searched,
        supported: covers.isEmpty || !links.supportGate
            ? null
            : CertificationTexts.of(certifications).supportFor(
                gap,
                terms: links.termSupport
                    ? link.supportTerms
                    : const <String>[],
                theta: links.theta,
                tags: links.tagSupport,
              ),
      );
    }
    return result;
  }

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

  /// True when the certification's own name or short name contains the
  /// whole name of the skill gap [gap]: the gap's words next to each other,
  /// as whole words ("Java" is not in "JavaScript"), and not followed by
  /// "+" or "#" (a name with a sign is another name). A product the synonym
  /// table does not know is often named only in the certification's name,
  /// so its skills alone would never match the gap. Only the name counts,
  /// never the description, which lists many side technologies.
  ///
  /// A broad gap keeps its own matching through the certification's
  /// skills: a name the synonym table knows, or one word of a longer skill
  /// name of the table ("Data" of "Data Analysis"). A specific product the
  /// table knows is never broad. The names are compared with
  /// [SkillMatcher.identityKey], and a name of one or two letters never
  /// counts.
  ///
  /// The ranking runs the same rule with the gap and the certification
  /// names prepared once ([_GapName], [_CertificationNames]).
  static bool nameContainsGap(String gap, Certification cert) =>
      _GapName.of(gap).inNameOf(_CertNames.of(cert));

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

/// A skill gap as the two certification-name rules need it, worked out
/// once: the gap names the certification
/// ([ContentBasedRecommender.gapNamesCertification]), or the
/// certification's name contains the gap
/// ([ContentBasedRecommender.nameContainsGap]).
class _GapName {
  /// [SkillMatcher.identityKey] of the gap, or empty when the name is too
  /// short to name a certification (one or two letters).
  final String key;

  /// Whether the gap may name a family of certifications: it is written in
  /// capitals and is not a name the synonym table knows.
  final bool family;

  /// Whether the gap counts where a certification's name contains it: it
  /// is not a broad skill word, or it is a specific product.
  final bool inName;

  const _GapName(this.key, this.family, this.inName);

  factory _GapName.of(String gap) {
    final key = SkillMatcher.identityKey(gap);
    if (key.length < 3) return const _GapName('', false, false);
    final known = SkillMatcher.isKnownName(gap);
    // Broad: a name the synonym table knows, or one word of a longer skill
    // name of the table.
    final broad = known || (!key.contains(' ') && _broadWords.contains(key));
    return _GapName(
      key,
      gap.toUpperCase() == gap && !known,
      !broad || SkillMatcher.isSpecific(gap),
    );
  }

  /// The words of the longer skill names of the synonym table ("data" and
  /// "analysis" of "Data Analysis"), read from the table at run time.
  static final Set<String> _broadWords = {
    for (final name in SkillMatcher.conceptNames)
      if (SkillMatcher.identityKey(name).contains(' '))
        ...SkillMatcher.identityKey(name).split(' '),
  };

  /// How [SkillMatcher.identityKey] writes the signs "+" and "#".
  static final Set<String> _signs = {
    SkillMatcher.identityKey('+'),
    SkillMatcher.identityKey('#'),
  };

  /// True when this gap names the certification whose names are [cert].
  bool names(_CertNames cert) {
    if (key.isEmpty) return false;
    if (key == cert.short || key == cert.name) return true;
    return family && cert.short.isNotEmpty && cert.short.startsWith('$key ');
  }

  /// True when the name or the short name of the certification [cert]
  /// contains this gap's whole name.
  bool inNameOf(_CertNames cert) =>
      inName && (_hasWords(cert.name, key) || _hasWords(cert.short, key));

  /// True when [name] contains the words of [key] next to each other, as
  /// whole words, at a place where no sign follows them. Both are
  /// [SkillMatcher.identityKey]s.
  static bool _hasWords(String name, String key) {
    if (name.isEmpty) return false;
    final padded = ' $name ';
    final needle = ' $key ';
    for (var at = padded.indexOf(needle);
        at >= 0;
        at = padded.indexOf(needle, at + 1)) {
      final rest = padded.substring(at + needle.length);
      final space = rest.indexOf(' ');
      final next = space < 0 ? rest : rest.substring(0, space);
      if (!_signs.contains(next)) return true;
    }
    return false;
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
/// (kept in an Expando, like [CertificationTexts]): the names of each
/// certification for the certification-name rule, and which gaps are
/// holes in the catalogue for the meaning links.
class _CertificationNames {
  _CertificationNames._(this._items)
      : _names = List<_CertNames?>.filled(_items.length, null);

  final List<Certification> _items;

  /// The names of each certification, worked out the first time the
  /// ranking asks for them (only the certifications of the career goal).
  final List<_CertNames?> _names;

  /// Every skill of every certification, through [SkillMatcher.canonical].
  /// Built on first use: only the meaning links need it.
  late final List<String> _skills = {
    for (final cert in _items)
      for (final skill in cert.skills) SkillMatcher.canonical(skill),
  }.toList(growable: false);

  /// gap -> whether it is a hole, remembered per name.
  final Map<String, bool> _holes = {};

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

  /// True when no skill of any certification matches the gap's own name
  /// ([SkillMatcher.matches]).
  bool isHole(String gap) => _holes[gap] ??= () {
        final wanted = SkillMatcher.canonical(gap);
        return !_skills
            .any((skill) => SkillMatcher.matchesCanonical(wanted, skill));
      }();
}

/// The meaning link one skill gap uses in a certification ranking.
class _CertificationLink {
  /// Catalogue names of the same skill.
  final List<String> same;

  /// Catalogue names of a broader skill.
  final List<String> covers;

  /// Stored wording searched in the certification's text.
  final List<String> searched;

  /// The positions, in the list given to the recommender, of the
  /// certifications whose own text supports the gap: only for them do the
  /// [covers] names count. Null when every certification may use them.
  final Set<int>? supported;

  const _CertificationLink({
    required this.same,
    required this.covers,
    required this.searched,
    required this.supported,
  });
}

/// The words of each certification's own text (its name and description),
/// prepared once per list for the support test of the meaning links. It is
/// the certification counterpart of [OpportunityIndex.supportFor] and
/// follows the same rules, with the same tokens ([OpportunityIndex.tokensOf]).
class CertificationTexts {
  CertificationTexts._(this._items, this._texts, this._tags);

  final List<Certification> _items;

  /// Tokens of the name and of the description, per certification.
  final List<List<List<String>>> _texts;

  /// Tokens of each skill, per certification.
  final List<List<List<String>>> _tags;

  static final Expando<CertificationTexts> _cache =
      Expando<CertificationTexts>();

  /// The prepared texts of [list], built on the first call and reused while
  /// the list still holds the same certifications.
  static CertificationTexts of(List<Certification> list) {
    final cached = _cache[list];
    if (cached != null && cached._sameItems(list)) return cached;
    return _cache[list] = CertificationTexts._(
      List<Certification>.of(list, growable: false),
      [
        for (final cert in list)
          [
            OpportunityIndex.tokensOf(cert.name),
            OpportunityIndex.tokensOf(cert.description),
          ],
      ],
      [
        for (final cert in list)
          [for (final skill in cert.skills) OpportunityIndex.tokensOf(skill)],
      ],
    );
  }

  bool _sameItems(List<Certification> list) {
    if (list.length != _items.length) return false;
    for (var i = 0; i < list.length; i++) {
      if (!identical(list[i], _items[i])) return false;
    }
    return true;
  }

  /// token -> certifications that contain it, without and with the skills.
  late final Map<String, Set<int>> _wordDocs = _docsOf(false);
  late final Map<String, Set<int>> _wordDocsWithTags = _docsOf(true);

  Map<String, Set<int>> _docsOf(bool tags) {
    final docs = <String, Set<int>>{};
    for (var i = 0; i < _items.length; i++) {
      for (final tokens in [..._texts[i], if (tags) ..._tags[i]]) {
        for (final token in tokens) {
          (docs[token] ??= <int>{}).add(i);
        }
      }
    }
    return docs;
  }

  final Map<String, Set<int>> _supportCache = {};

  /// The positions of the certifications whose own text supports the skill
  /// gap [gap]: it contains the gap's whole name as a phrase, a distinctive
  /// word of it, or one of [terms] ([LinkSupport.supported] has the rule,
  /// shared with the opportunities). A word is distinctive when at most the
  /// share [theta] of the certifications of this list contain it. With
  /// [tags] the skills of a certification count as its text too. The
  /// result is remembered, keyed on the names as given.
  Set<int> supportFor(
    String gap, {
    Iterable<String> terms = const [],
    required double theta,
    bool tags = false,
  }) {
    final termList = terms is List<String> ? terms : terms.toList();
    final cacheKey = '$theta|$tags|$gap|${termList.join('\u0001')}';
    return _supportCache[cacheKey] ??= () {
      final words = tags ? _wordDocsWithTags : _wordDocs;
      Iterable<int> withPhrase(List<String> phrase) {
        Set<int>? candidates;
        for (final word in phrase) {
          final docs = words[word];
          if (docs == null) return const <int>[];
          candidates =
              candidates == null ? docs : candidates.intersection(docs);
        }
        return [
          for (final i in candidates ?? const <int>{})
            if ([..._texts[i], if (tags) ..._tags[i]]
                .any((tokens) => _hasPhrase(tokens, phrase)))
              i,
        ];
      }

      return LinkSupport.supported(
        gapTokens: OpportunityIndex.tokensOf(gap),
        terms: [for (final term in termList) OpportunityIndex.tokensOf(term)],
        theta: theta,
        size: _items.length,
        itemsWithWord: (word) => words[word],
        itemsWithPhrase: withPhrase,
      );
    }();
  }

  static bool _hasPhrase(List<String> tokens, List<String> phrase) {
    for (var start = 0; start + phrase.length <= tokens.length; start++) {
      var same = true;
      for (var k = 0; k < phrase.length && same; k++) {
        same = tokens[start + k] == phrase[k];
      }
      if (same) return true;
    }
    return false;
  }
}
