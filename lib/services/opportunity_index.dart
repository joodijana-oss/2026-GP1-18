import '../models/opportunity.dart';
import '../utils/skill_matcher.dart';
import 'link_support.dart';

/// The parts of an opportunity that are searched for a skill.
/// Requirements are left out on purpose: they are what the learner needs
/// before joining, not what the opportunity teaches.
enum OpportunityField { title, skills, objectives, description }

/// How many times one skill was found in each field of one opportunity,
/// after the evidence rules of [OpportunityIndex.hitsFor].
class FieldHits {
  final int title;

  /// Skill tags that stand for the skill.
  final int skills;
  final int objectives;
  final int description;

  /// Mentions of a one-word name in long objectives that did not pass the
  /// evidence rules ("Apply defense, monitoring and initial response
  /// controls"). They are not counted in [objectives]. The recommender
  /// counts them only for an opportunity listed for the user's career
  /// goal: inside the career path the word most likely has the meaning
  /// the user needs ("monitoring" in a cloud programme is cloud
  /// monitoring), outside it, it is often another subject.
  final int looseObjectives;

  const FieldHits({
    this.title = 0,
    this.skills = 0,
    this.objectives = 0,
    this.description = 0,
    this.looseObjectives = 0,
  });

  /// True when a counted field (not [looseObjectives]) has a mention.
  bool get hasEvidence =>
      title > 0 || skills > 0 || objectives > 0 || description > 0;

  int of(OpportunityField field) {
    switch (field) {
      case OpportunityField.title:
        return title;
      case OpportunityField.skills:
        return skills;
      case OpportunityField.objectives:
        return objectives;
      case OpportunityField.description:
        return description;
    }
  }

  bool get isEmpty => !hasEvidence && looseObjectives == 0;
}

/// A search index over the opportunities, built once and reused.
///
/// The recommender asks one question many times: "which opportunities
/// mention this skill, where, and how often?". Reading every title and
/// description again for every skill and every visit is slow, so the texts
/// are prepared once:
///
///  - Tokens. Each text is lower-cased, punctuation is removed and it is
///    split into words ([tokensOf]). "C#" and "C++" become "csharp" and
///    "cpp" first ([SkillMatcher.searchForm]), so they are not confused
///    with the letter "c". Each word is then stemmed ([stem]): a final "s"
///    is dropped, so "microservices" and "microservice" become the same
///    token.
///  - Inverted index. For every token, the set of opportunities that
///    contain it. To find a skill, only the opportunities that contain all
///    of its words are opened, not the whole catalogue. Search engines work
///    the same way.
///  - Phrase matching. A skill of several words ("power bi", "incident
///    response") must appear as the same words in the same order, next to
///    each other. Loose words do not count.
///  - Features. The estimated learning hours ([estimatedHours]) and the
///    level ([levelOf]) of each opportunity.
///
/// Nothing here depends on the ranking weights: the index only stores
/// facts about the texts (tokens, lengths, counts, hours, level, open or
/// closed). Scores are computed by the recommender from these facts.
///
/// When it is built. [of] keeps one index per list object.
/// OpportunityService hands out the same list until a forced refresh (pull
/// to refresh, or the retry button), which loads a new list because the
/// data may have changed. So the index is built once per list: when the
/// opportunities screen first opens, and once after each forced refresh.
///
/// Where it is built. The opportunities screen calls
/// `OpportunityRecommender.recommendInBackground`. For a list that has no
/// index yet, it builds the index and ranks on a background isolate, so the
/// frames on screen are not held up. Isolates do not share memory, so the
/// index built there is sent back with the result and kept here with
/// [adopt]. Every later call on the same list finds it ([cachedFor]) and
/// ranks right away on the main isolate, without building anything.
class OpportunityIndex {
  OpportunityIndex._(
    this._opportunities,
    this._title,
    this._objectives,
    this._description,
    this._objectivesLength,
    this._tokenDocs,
    this._tagDocs,
    this._hours,
    this._levels,
    this._averageLength,
  );

  /// A one-word name of a broad skill must appear at least this many times
  /// in a description, or in the objectives, before that field counts as
  /// evidence (see [hitsFor]).
  static const int minDescriptionMentions = 2;

  /// An objective of at most this many words is short: one stated outcome
  /// ("Use Docker", "Monitor cloud workloads"), so a one-word skill name in
  /// it counts with a single mention. Longer objectives are lists of
  /// several things, where one word is often a passing mention. Of the 558
  /// objectives in the catalogue, 29% have 8 words or fewer and half have
  /// 11 or fewer.
  static const int shortObjectiveWords = 8;

  /// Training hours per working day of a dated event. The one record that
  /// states its hours (Applied Digital Forensics Program) gives 40 training
  /// hours over 10 working days.
  static const double hoursPerTrainingDay = 4;

  /// Typical learning hours by type, used when an opportunity gives neither
  /// a duration nor a start and end date. Course, Training Program and
  /// Bootcamp are the medians of the catalogue records that do give them
  /// (measured with [estimatedHours]); the short session types have no
  /// data and use the usual length of such a session.
  static const Map<String, double> typicalHours = {
    'Course': 14,
    'Training Program': 40,
    'Bootcamp': 240,
    'Hackathon': 24,
    'Meetup': 2,
    'Webinar': 1.5,
  };

  /// Used for a type that is not in [typicalHours] (same as a Course).
  static const double defaultHours = 14;

  final List<Opportunity> _opportunities;

  /// Tokens of each text field, per opportunity. Objectives are kept one
  /// list per objective, so a phrase never runs across two objectives.
  final List<List<String>> _title;
  final List<List<List<String>>> _objectives;
  final List<List<String>> _description;
  final List<int> _objectivesLength;

  /// token -> opportunities that contain it in a text field.
  final Map<String, Set<int>> _tokenDocs;

  /// skill tag as written -> opportunities that carry it.
  final Map<String, List<int>> _tagDocs;

  final List<double> _hours;
  final List<int?> _levels;
  final Map<OpportunityField, double> _averageLength;

  final Map<String, Map<int, FieldHits>> _hitsCache = {};
  final Map<int, List<bool>> _openCache = {};

  /// Each distinct skill tag, prepared once for the tag test
  /// ([SkillMatcher.prepare]); filled on first use.
  final Map<String, PreparedSkill> _preparedTags = {};

  // ---------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------

  static final Expando<OpportunityIndex> _cache = Expando<OpportunityIndex>();

  /// The index of [list], built on the first call and reused afterwards.
  /// The same list object must be passed again to reuse it. If any item of
  /// the list was added, removed or replaced since the index was built, it
  /// is built again: reusing it would rank the old data.
  static OpportunityIndex of(List<Opportunity> list) {
    final cached = cachedFor(list);
    if (cached != null) return cached;
    final built = build(list);
    _cache[list] = built;
    return built;
  }

  /// The cached index of [list] when there is one and it still matches
  /// every item (see [of]), or null. Never builds one.
  static OpportunityIndex? cachedFor(List<Opportunity> list) {
    final cached = _cache[list];
    return cached != null && cached._sameItems(list) ? cached : null;
  }

  /// Keeps [index], built on another isolate, as the index of [list], so
  /// [of] and [cachedFor] find it. Returns false, and keeps nothing, when
  /// it does not fit [list].
  ///
  /// [builtFrom] is the list, on this isolate, whose copy was sent to the
  /// other isolate to build [index]. Objects sent between isolates are
  /// copied, so [index] holds copies of the opportunities, not the objects
  /// of this isolate. The kept index points to the objects of [builtFrom]
  /// instead (position by position, with the same ids). Its search data,
  /// including the hits already found for the user's skills, is reused as
  /// it is. Then the usual check of [of] applies: if [list] changed since
  /// [builtFrom] was taken, the index is not kept.
  static bool adopt(
    List<Opportunity> list,
    OpportunityIndex index, {
    required List<Opportunity> builtFrom,
  }) {
    final items = index._sameIdsAs(builtFrom);
    if (items == null) return false;
    final adopted = index._withItems(items);
    if (!adopted._sameItems(list)) return false;
    _cache[list] = adopted;
    return true;
  }

  /// True when [list] still holds exactly the opportunity objects this
  /// index was built from, in the same order (a few microseconds for the
  /// whole catalogue).
  bool _sameItems(List<Opportunity> list) {
    if (list.length != _opportunities.length) return false;
    for (var i = 0; i < list.length; i++) {
      if (!identical(list[i], _opportunities[i])) return false;
    }
    return true;
  }

  /// A fixed copy of [list] when it has the same ids as the opportunities
  /// of this index, in the same order, or null.
  List<Opportunity>? _sameIdsAs(List<Opportunity> list) {
    if (list.length != _opportunities.length) return null;
    for (var i = 0; i < list.length; i++) {
      if (list[i].id != _opportunities[i].id) return null;
    }
    return List<Opportunity>.of(list, growable: false);
  }

  /// The same index pointing to [items] (see [adopt]). The search data is
  /// shared, not copied; the remembered results are carried over.
  OpportunityIndex _withItems(List<Opportunity> items) {
    final copy = OpportunityIndex._(
      items,
      _title,
      _objectives,
      _description,
      _objectivesLength,
      _tokenDocs,
      _tagDocs,
      _hours,
      _levels,
      _averageLength,
    );
    copy._hitsCache.addAll(_hitsCache);
    copy._openCache.addAll(_openCache);
    copy._preparedTags.addAll(_preparedTags);
    copy._tagCoverCache.addAll(_tagCoverCache);
    copy._supportCache.addAll(_supportCache);
    return copy;
  }

  /// Builds a new index without caching it (for tests and timing).
  static OpportunityIndex build(List<Opportunity> list) {
    final opportunities = List<Opportunity>.of(list, growable: false);
    final title = <List<String>>[];
    final objectives = <List<List<String>>>[];
    final description = <List<String>>[];
    final objectivesLength = <int>[];
    final tokenDocs = <String, Set<int>>{};
    final tagDocs = <String, List<int>>{};
    final hours = <double>[];
    final levels = <int?>[];

    for (var i = 0; i < opportunities.length; i++) {
      final o = opportunities[i];

      final titleTokens = tokensOf(o.title);
      final objectiveTokens = <List<String>>[];
      var objectiveWords = 0;
      for (final objective in o.objectives) {
        final words = tokensOf(objective);
        if (words.isEmpty) continue;
        objectiveTokens.add(words);
        objectiveWords += words.length;
      }
      final descriptionTokens = tokensOf(o.description);

      final allTokens = [titleTokens, ...objectiveTokens, descriptionTokens];
      for (final tokens in allTokens) {
        for (final token in tokens) {
          (tokenDocs[token] ??= <int>{}).add(i);
        }
      }
      for (final tag in o.skills) {
        (tagDocs[tag] ??= <int>[]).add(i);
      }

      title.add(titleTokens);
      objectives.add(objectiveTokens);
      description.add(descriptionTokens);
      objectivesLength.add(objectiveWords);
      hours.add(estimatedHours(o));
      levels.add(levelOf(o));
    }

    /// The mean of the non-empty lengths (1 when every one is empty).
    double average(int Function(int index) lengthOf) {
      var sum = 0;
      var count = 0;
      for (var i = 0; i < opportunities.length; i++) {
        final length = lengthOf(i);
        if (length > 0) {
          sum += length;
          count++;
        }
      }
      return count == 0 ? 1 : sum / count;
    }

    return OpportunityIndex._(
      opportunities,
      title,
      objectives,
      description,
      objectivesLength,
      tokenDocs,
      tagDocs,
      hours,
      levels,
      {
        OpportunityField.title: average((i) => title[i].length),
        OpportunityField.skills: average((i) => opportunities[i].skills.length),
        OpportunityField.objectives: average((i) => objectivesLength[i]),
        OpportunityField.description: average((i) => description[i].length),
      },
    );
  }

  int get size => _opportunities.length;

  Opportunity opportunityAt(int index) => _opportunities[index];

  /// The length of one field: words for the text fields, tags for
  /// [OpportunityField.skills].
  int fieldLength(int index, OpportunityField field) {
    switch (field) {
      case OpportunityField.title:
        return _title[index].length;
      case OpportunityField.skills:
        return _opportunities[index].skills.length;
      case OpportunityField.objectives:
        return _objectivesLength[index];
      case OpportunityField.description:
        return _description[index].length;
    }
  }

  /// The average [fieldLength] over the opportunities where that field is
  /// not empty.
  double averageLength(OpportunityField field) => _averageLength[field] ?? 1;

  /// Estimated learning hours of one opportunity (see [estimatedHours]).
  double hoursAt(int index) => _hours[index];

  /// Level of one opportunity (see [levelOf]).
  int? levelAt(int index) => _levels[index];

  /// For each opportunity, whether the user can still join on [now]
  /// ([Opportunity.isOpen]). Remembered per calendar day.
  List<bool> openOn(DateTime now) {
    final day = now.year * 10000 + now.month * 100 + now.day;
    return _openCache[day] ??= [
      for (final o in _opportunities) o.isOpen(now),
    ];
  }

  // ---------------------------------------------------------
  // SEARCH
  // ---------------------------------------------------------

  /// Where and how often [skill] is found, per opportunity index. Only
  /// opportunities with at least one hit are in the result.
  ///
  /// What is searched:
  ///  - Skill tags: a tag counts when [SkillMatcher.tagCovers] says it
  ///    stands for the skill (the full synonym table).
  ///  - Title, objectives and description: the names of the skill are
  ///    searched as phrases. Without [expand] the names are the skill and
  ///    its spellings ([SkillMatcher.searchNamesOf]); with it, the query
  ///    expansion of the skill ([SkillMatcher.expansionsOf]). The
  ///    recommender leaves expansion off by default (`expandSynonyms` in
  ///    the ranking weights of opportunity_recommender.dart).
  ///
  /// One mention is counted once. When several names overlap ("docker" and
  /// "docker containers" in the text "Docker containers"), the longest name
  /// wins and its words are not counted again.
  ///
  /// Evidence rules (what counts as a real mention). A "strong" name has
  /// two words or more ("incident response"), or is the exact name of a
  /// specific product ("Tableau", "C#") that is longer than one letter.
  ///  - A mention in the title always counts: the title says what the
  ///    opportunity is about.
  ///  - A mention in an objective counts for a strong name. A one-word
  ///    name ("monitoring", "design") counts only when it appears at least
  ///    [minDescriptionMentions] times in the objectives, or in a short
  ///    objective ([shortObjectiveWords]), or the title or a tag names the
  ///    skill too. Objectives are often long lists, and one generic word in
  ///    them does not mean the skill is taught. Such a mention is kept
  ///    apart in [FieldHits.looseObjectives].
  ///  - A mention in the description counts for a strong name, or when the
  ///    same one-word name appears at least [minDescriptionMentions] times.
  ///    A single passing word in a long description ("... and basic
  ///    statistics ...") is not evidence that the skill is taught. The
  ///    short form of a product name ("node" for "Node.js") is such a word
  ///    too: networks have nodes.
  ///  - A one-letter name ("C", "R") counts in the objectives and the
  ///    description only when the title or a tag names the skill too:
  ///    "a) ... b) ... c) ..." is not a mention of C.
  ///
  /// With [textOnly] the skill tags are not looked at: only the title, the
  /// objectives and the description are searched. The recommender uses it
  /// for the stored wording of a meaning link, which is something to find
  /// in a text, not a skill name to compare with tags.
  ///
  /// The result is remembered, so asking again for the same skill is free.
  Map<int, FieldHits> hitsFor(
    String skill, {
    bool expand = false,
    bool textOnly = false,
  }) {
    final wanted = SkillMatcher.prepare(skill);
    final key = wanted.key;
    if (key.isEmpty) return const {};
    final cacheKey = textOnly ? 'text|$expand|$key' : '$expand|$key';
    final cached = _hitsCache[cacheKey];
    if (cached != null) return cached;

    final names = expand
        ? SkillMatcher.expansionsOf(skill)
        : SkillMatcher.searchNamesOf(skill);
    final phrases = _phrasesOf(names);
    // The exact name of a specific product, with and without spaces.
    final productNames = wanted.isSpecific
        ? {tokensOf(key).join(' '), tokensOf(key.replaceAll(' ', '')).join(' ')}
        : const <String>{};
    final strong = [
      for (final phrase in phrases)
        phrase.length >= 2 ||
            (phrase.first.length > 1 && productNames.contains(phrase.first)),
    ];
    final oneLetter = [
      for (final phrase in phrases)
        phrase.length == 1 && phrase.first.length == 1,
    ];
    final tagCounts = textOnly ? const <int, int>{} : _tagCounts(wanted);

    final candidates = <int>{...tagCounts.keys};
    for (final phrase in phrases) {
      candidates.addAll(_docsWithAll(phrase));
    }
    final ordered = candidates.toList()..sort();

    // Phrases by their first word, longest first, for the scan.
    final byFirstWord = <String, List<int>>{};
    for (var p = 0; p < phrases.length; p++) {
      (byFirstWord[phrases[p].first] ??= <int>[]).add(p);
    }

    final result = <int, FieldHits>{};
    for (final i in ordered) {
      final title = _sum(_countPhrases(_title[i], phrases, byFirstWord));
      final tags = tagCounts[i] ?? 0;
      // The title or a tag names the skill.
      final anchored = title > 0 || tags > 0;

      final inObjectives = List<int>.filled(phrases.length, 0);
      final inShortObjectives = List<int>.filled(phrases.length, 0);
      for (final objective in _objectives[i]) {
        final counts = _countPhrases(objective, phrases, byFirstWord);
        final short = objective.length <= shortObjectiveWords;
        for (var p = 0; p < phrases.length; p++) {
          inObjectives[p] += counts[p];
          if (short) inShortObjectives[p] += counts[p];
        }
      }
      final inDescription =
          _countPhrases(_description[i], phrases, byFirstWord);

      var objectives = 0;
      var looseObjectives = 0;
      var description = 0;
      for (var p = 0; p < phrases.length; p++) {
        if (oneLetter[p]) {
          if (anchored) {
            objectives += inObjectives[p];
            description += inDescription[p];
          }
          continue;
        }
        if (strong[p] ||
            anchored ||
            inObjectives[p] >= minDescriptionMentions ||
            inShortObjectives[p] > 0) {
          objectives += inObjectives[p];
        } else {
          looseObjectives += inObjectives[p];
        }
        if (strong[p] || inDescription[p] >= minDescriptionMentions) {
          description += inDescription[p];
        }
      }

      final hits = FieldHits(
        title: title,
        skills: tags,
        objectives: objectives,
        description: description,
        looseObjectives: looseObjectives,
      );
      if (!hits.isEmpty) result[i] = hits;
    }
    return _hitsCache[cacheKey] = result;
  }

  /// True when opportunity [index] names [skill] itself, not only a broader
  /// or related skill: the title, objectives or description mention one of
  /// its own names (after the evidence rules of [hitsFor], without query
  /// expansion), or one of its skill tags contains such a name ("Routing
  /// and Switching" names "Switching"; "Deep Learning" does not name
  /// "Computer Vision", although the tag test lets it stand for it).
  bool namesItself(int index, String skill) {
    final hits = hitsFor(skill)[index];
    if (hits == null) return false;
    if (hits.title + hits.objectives + hits.description > 0) return true;
    final names = _phrasesOf(SkillMatcher.searchNamesOf(skill));
    for (final tag in _opportunities[index].skills) {
      final tokens = tokensOf(tag);
      for (final name in names) {
        for (var start = 0; start + name.length <= tokens.length; start++) {
          if (_startsWith(tokens, start, name)) return true;
        }
      }
    }
    return false;
  }

  /// True when at least one skill tag of the catalogue stands for [skill]
  /// ([SkillMatcher.tagCovers]). When none does, the skill's own name is a
  /// hole in the catalogue: only a mention in a text can find it, and the
  /// recommender may use a meaning link for it.
  ///
  /// The answer is remembered per name, so a gap asked about again (the
  /// same analysis on the next call) costs nothing.
  bool anyTagCovers(String skill) => _tagCoverCache[skill] ??= () {
        final wanted = SkillMatcher.prepare(skill);
        if (wanted.key.isEmpty) return false;
        for (final tag in _tagDocs.keys) {
          final prepared = _preparedTags[tag] ??= SkillMatcher.prepare(tag);
          if (SkillMatcher.tagCoversPrepared(wanted, prepared)) return true;
        }
        return false;
      }();

  final Map<String, bool> _tagCoverCache = {};

  /// The distinct skill tags of the catalogue, as written.
  Iterable<String> get tags => _tagDocs.keys;

  // ---------------------------------------------------------
  // SUPPORT (the gate of the meaning links)
  // ---------------------------------------------------------

  /// The opportunities whose own text supports the skill gap [gap]: the
  /// test a meaning link must pass before the gap is named as the reason
  /// for an opportunity (see "Meaning links" in OpportunityRecommender).
  /// Own text is the title, the objectives and the description; with
  /// [tags] the skill tags count too.
  ///
  /// An opportunity supports the gap when its own text contains the gap's
  /// whole name as a phrase, a distinctive word of it, or one of [terms],
  /// the wording stored with the link ([LinkSupport.supported] has the
  /// rule, shared with the certifications). The share that makes a word
  /// distinctive is counted here, from this catalogue: a common word
  /// ("management", "network") exceeds [theta] by itself, so no word list
  /// is needed, and the same word can be distinctive in one catalogue and
  /// common in another.
  ///
  /// Words are the tokens of [tokensOf], so plurals and the spellings of
  /// "C#" behave as in the search. The result is remembered, keyed on the
  /// names as given, so a repeated call does not even tokenize them.
  Set<int> supportFor(
    String gap, {
    Iterable<String> terms = const [],
    required double theta,
    bool tags = false,
  }) {
    final termList = terms is List<String> ? terms : terms.toList();
    final cacheKey = '$theta|$tags|$gap|${termList.join('\u0001')}';
    return _supportCache[cacheKey] ??= LinkSupport.supported(
      gapTokens: tokensOf(gap),
      terms: [for (final term in termList) tokensOf(term)],
      theta: theta,
      size: size,
      itemsWithWord: (word) => _docsWithWord(word, tags: tags),
      itemsWithPhrase: (phrase) => _docsWithPhrase(phrase, tags: tags),
    );
  }

  /// The opportunities whose own text (with [tags], also a skill tag)
  /// contains the words of [phrase] next to each other, in order.
  Set<int> _docsWithPhrase(List<String> phrase, {required bool tags}) {
    final result = <int>{
      for (final i in _docsWithAll(phrase))
        if (_textHasPhrase(i, phrase)) i,
    };
    if (!tags) return result;
    _tagTokens.forEach((tag, tokens) {
      for (var start = 0; start + phrase.length <= tokens.length; start++) {
        if (_startsWith(tokens, start, phrase)) {
          result.addAll(_tagDocs[tag]!);
          break;
        }
      }
    });
    return result;
  }

  final Map<String, Set<int>> _supportCache = {};

  /// Each distinct skill tag as tokens; filled on first use.
  late final Map<String, List<String>> _tagTokens = {
    for (final tag in _tagDocs.keys) tag: tokensOf(tag),
  };

  /// token -> opportunities with a skill tag that contains it.
  late final Map<String, Set<int>> _tagTokenDocs = () {
    final docs = <String, Set<int>>{};
    _tagTokens.forEach((tag, tokens) {
      for (final token in tokens) {
        (docs[token] ??= <int>{}).addAll(_tagDocs[tag]!);
      }
    });
    return docs;
  }();

  /// The opportunities that contain [word] in a text field, or with [tags]
  /// also in a skill tag.
  Set<int> _docsWithWord(String word, {required bool tags}) {
    final inText = _tokenDocs[word] ?? const <int>{};
    if (!tags) return inText;
    final inTags = _tagTokenDocs[word];
    return inTags == null ? inText : {...inText, ...inTags};
  }

  /// True when the title, one objective or the description of opportunity
  /// [index] contains the words of [phrase] next to each other, in order.
  bool _textHasPhrase(int index, List<String> phrase) {
    bool inside(List<String> tokens) {
      for (var start = 0; start + phrase.length <= tokens.length; start++) {
        if (_startsWith(tokens, start, phrase)) return true;
      }
      return false;
    }

    return inside(_title[index]) ||
        _objectives[index].any(inside) ||
        inside(_description[index]);
  }

  /// opportunity index -> how many of its tags stand for [wanted]. Each
  /// distinct tag is prepared once per index, so this costs one cheap
  /// comparison per distinct tag (144 in the catalogue).
  Map<int, int> _tagCounts(PreparedSkill wanted) {
    final counts = <int, int>{};
    _tagDocs.forEach((tag, docs) {
      final prepared = _preparedTags[tag] ??= SkillMatcher.prepare(tag);
      if (!SkillMatcher.tagCoversPrepared(wanted, prepared)) return;
      for (final i in docs) {
        counts[i] = (counts[i] ?? 0) + 1;
      }
    });
    return counts;
  }

  /// The names as token lists, without duplicates, longest first.
  static List<List<String>> _phrasesOf(List<String> names) {
    final seen = <String>{};
    final phrases = <List<String>>[];
    for (final name in names) {
      final tokens = tokensOf(name);
      if (tokens.isEmpty || !seen.add(tokens.join(' '))) continue;
      phrases.add(tokens);
    }
    // Longest first; equal lengths keep their order (a stable sort).
    final order = List<int>.generate(phrases.length, (i) => i)
      ..sort((a, b) {
        final byLength = phrases[b].length.compareTo(phrases[a].length);
        return byLength != 0 ? byLength : a.compareTo(b);
      });
    return [for (final i in order) phrases[i]];
  }

  /// The opportunities whose text fields contain every word of [phrase]
  /// (from the inverted index). The words may still be apart or in
  /// different fields; [_countPhrases] checks that.
  Set<int> _docsWithAll(List<String> phrase) {
    Set<int>? docs;
    for (final word in phrase) {
      final withWord = _tokenDocs[word];
      if (withWord == null) return const {};
      docs = docs == null ? withWord : docs.intersection(withWord);
      if (docs.isEmpty) return const {};
    }
    return docs ?? const {};
  }

  /// How many times each of [phrases] appears in [tokens], reading left to
  /// right. At each position the longest phrase that fits is taken and its
  /// words are skipped, so no word is counted twice.
  static List<int> _countPhrases(
    List<String> tokens,
    List<List<String>> phrases,
    Map<String, List<int>> byFirstWord,
  ) {
    final counts = List<int>.filled(phrases.length, 0);
    var position = 0;
    while (position < tokens.length) {
      var matched = -1;
      for (final p in byFirstWord[tokens[position]] ?? const <int>[]) {
        if (_startsWith(tokens, position, phrases[p])) {
          matched = p;
          break; // phrases are ordered longest first
        }
      }
      if (matched < 0) {
        position++;
      } else {
        counts[matched]++;
        position += phrases[matched].length;
      }
    }
    return counts;
  }

  static bool _startsWith(List<String> tokens, int start, List<String> phrase) {
    if (start + phrase.length > tokens.length) return false;
    for (var k = 0; k < phrase.length; k++) {
      if (tokens[start + k] != phrase[k]) return false;
    }
    return true;
  }

  static int _sum(List<int> values) {
    var sum = 0;
    for (final value in values) {
      sum += value;
    }
    return sum;
  }

  // ---------------------------------------------------------
  // FEATURES: LENGTH AND LEVEL
  // ---------------------------------------------------------

  /// How many learning hours an opportunity takes, from the best source it
  /// has:
  ///  1. its duration text ([hoursFromDuration]), for example
  ///     "4 weeks of study, 3-5 hours/week" = 16 hours;
  ///  2. its start and end dates: [workingDays] between them times
  ///     [hoursPerTrainingDay];
  ///  3. the typical hours of its type ([typicalHours]).
  static double estimatedHours(Opportunity opportunity) {
    final stated = hoursFromDuration(opportunity.duration);
    if (stated != null && stated > 0) return stated;

    final start = opportunity.startDate;
    final end = opportunity.endDate;
    if (start != null && end != null && end.isAfter(start)) {
      return workingDays(start, end) * hoursPerTrainingDay;
    }
    return typicalHours[opportunity.type] ?? defaultHours;
  }

  /// Reads the total hours from a duration text, or null when it does not
  /// say. Numbers can be digits or the words one to ten.
  ///  - "4 weeks of study, 3-5 hours/week"  -> 4 x 4 = 16 (the middle of a
  ///    range is used)
  ///  - "At the rate of 5 hours a week, it takes 6 weeks" -> 30
  ///  - "3 days, 6 hours /day"              -> 18
  ///  - "11 hours"                          -> 11
  ///  - "3 weeks", "2-4 hours per week", "8 - 10 hours per module" -> null
  ///    (the number of weeks, hours or modules is missing)
  static double? hoursFromDuration(String duration) {
    if (duration.trim().isEmpty) return null;
    // Typographic dashes and "~" are written in many ways in the data.
    final text =
        duration.toLowerCase().replaceAll(_notDurationCharacter, '-');

    final weeks = _weeks.firstMatch(text);
    final perWeek = _hoursPerWeek.firstMatch(text);
    if (weeks != null && perWeek != null) {
      return _middle(weeks) * _middle(perWeek);
    }
    final days = _days.firstMatch(text);
    final perDay = _hoursPerDay.firstMatch(text);
    if (days != null && perDay != null) {
      return _middle(days) * _middle(perDay);
    }
    if (text.contains('module')) return null;
    final total = _totalHours.firstMatch(text);
    return total == null ? null : _middle(total);
  }

  /// Working days from [start] to [end], both included. The Saudi working
  /// week is Sunday to Thursday, so Fridays and Saturdays are skipped.
  static int workingDays(DateTime start, DateTime end) {
    // UTC so a daylight saving change does not lose a day.
    final first = DateTime.utc(start.year, start.month, start.day);
    final last = DateTime.utc(end.year, end.month, end.day);
    final total = last.difference(first).inDays + 1;
    if (total <= 0) return 0;

    // Every full week has five working days; only the rest is counted.
    var days = (total ~/ 7) * 5;
    for (var k = 0; k < total % 7; k++) {
      final weekday = (first.weekday - 1 + k) % 7 + 1;
      if (weekday != DateTime.friday && weekday != DateTime.saturday) days++;
    }
    return days;
  }

  /// The level an opportunity is written for: 0 beginner, 1 intermediate,
  /// 2 advanced, or null when it does not say (most records).
  ///
  /// The title is read first: "advanced", "expert" or "mastery" mean 2,
  /// "intermediate" means 1, and "introduction", "fundamentals", "basics",
  /// "beginners", "foundations", "essentials", "getting started",
  /// "principles" or "101" mean 0.
  /// Then the description and the requirements: "intermediate" means 1;
  /// "beginners", "introductory" or "no prior ... experience" mean 0.
  /// "Advanced" is only trusted in the title: descriptions use it for the
  /// result ("reach an advanced level in Excel"), not for the starting
  /// level.
  static int? levelOf(Opportunity opportunity) {
    final title = opportunity.title.toLowerCase();
    if (_advancedTitle.hasMatch(title)) return 2;
    if (_intermediate.hasMatch(title)) return 1;
    if (_beginnerTitle.hasMatch(title)) return 0;

    final text = [opportunity.description, ...opportunity.requirements]
        .join(' ')
        .toLowerCase();
    if (_intermediate.hasMatch(text)) return 1;
    if (_beginnerText.hasMatch(text)) return 0;
    return null;
  }

  // ---------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------

  /// The words of [text], each one stemmed: the same words as
  /// [SkillMatcher.normalize] after [SkillMatcher.searchForm] gives.
  /// "REST APIs" -> [rest, api], "C# & .NET" -> [csharp, and, net].
  ///
  /// It reads the text once, character by character: every run of letters
  /// and digits is a word and "&" is the word "and". This is several times
  /// faster than a regular expression, and it runs on every title,
  /// objective and description when the index is built.
  static List<String> tokensOf(String text) {
    final lower = SkillMatcher.searchForm(text).toLowerCase();
    final tokens = <String>[];
    var start = -1;
    for (var i = 0; i <= lower.length; i++) {
      final c = i < lower.length ? lower.codeUnitAt(i) : _space;
      final isWordCharacter =
          (c >= _lowerA && c <= _lowerZ) || (c >= _digit0 && c <= _digit9);
      if (isWordCharacter) {
        if (start < 0) start = i;
        continue;
      }
      if (start >= 0) {
        tokens.add(stem(lower.substring(start, i)));
        start = -1;
      }
      if (c == _ampersand) tokens.add('and');
    }
    return tokens;
  }

  static const int _space = 0x20;
  static const int _ampersand = 0x26;
  static const int _digit0 = 0x30;
  static const int _digit9 = 0x39;
  static const int _lowerA = 0x61;
  static const int _lowerZ = 0x7A;

  /// Plural stemming: drops a final "s" so singular and plural match
  /// ("microservices" -> "microservice"). Short words ("aws", "sas") and
  /// words ending in "ss" ("class", "business") are kept as they are.
  static String stem(String word) {
    if (word.length >= 4 && word.endsWith('s') && !word.endsWith('ss')) {
      return word.substring(0, word.length - 1);
    }
    return word;
  }

  static const String _number =
      r'(\d+(?:\.\d+)?|\b(?:one|two|three|four|five|six|seven|eight|nine|ten))';
  static const String _range = '$_number\\s*(?:(?:-|to)\\s*$_number\\s*)?';
  static const String _hoursWord = r'(?:hours?|hrs?)\b';

  static final RegExp _notDurationCharacter = RegExp(r'[^a-z0-9.,:;/\s-]');
  static final RegExp _weeks = RegExp('${_range}weeks?\\b');
  static final RegExp _days = RegExp('${_range}days?\\b');
  static final RegExp _hoursPerWeek =
      RegExp('$_range$_hoursWord\\s*(?:/|per|a)\\s*week');
  static final RegExp _hoursPerDay =
      RegExp('$_range$_hoursWord\\s*(?:/|per|a)\\s*day');
  static final RegExp _totalHours = RegExp(
      '$_range$_hoursWord(?!\\s*(?:/|per|a)\\s*(?:week|day|module))');

  static const Map<String, double> _numberWords = {
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
    'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
  };

  static double _numberOf(String text) =>
      double.tryParse(text) ?? _numberWords[text] ?? 0;

  /// The number matched by [_range], or the middle of the range.
  static double _middle(RegExpMatch match) {
    final from = _numberOf(match.group(1)!);
    final to = match.group(2);
    return to == null ? from : (from + _numberOf(to)) / 2;
  }

  static final RegExp _advancedTitle = RegExp(r'\b(advanced|expert|mastery)\b');
  static final RegExp _intermediate = RegExp(r'\bintermediate\b');
  static final RegExp _beginnerTitle = RegExp(
      r'\b(introduction|introductory|intro|fundamentals?|basics?|beginners?|'
      r'foundations?|essentials|getting started|principles|101)\b');
  static final RegExp _beginnerText = RegExp(
      r'\b(beginners?|introductory|'
      r'no (prior|previous|specialized)\b.{0,40}\b'
      r'(experience|knowledge|background))\b');
}
