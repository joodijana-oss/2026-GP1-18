import 'dart:isolate';
import 'dart:math';

import '../models/opportunity.dart';
import '../utils/skill_matcher.dart';
import 'content_based_recommender.dart';
import 'opportunity_index.dart';

/// One recommended opportunity and why it was recommended.
class OpportunityMatch {
  final Opportunity opportunity;

  /// The user's skill gaps (as written in the analysis) that this
  /// opportunity teaches, in the order of the analysis. When several gaps
  /// are one skill in the synonym table (an aspect, see
  /// [OpportunityRecommender]), only those the opportunity names itself are
  /// listed, so a course on Computer Vision is not said to teach NLP.
  final List<String> gapSkills;

  /// The user's current skills (as written in the analysis) that this
  /// opportunity builds on. Never repeats a skill from [gapSkills].
  final List<String> currentSkills;

  /// True when the opportunity is listed for the user's career goal.
  final bool goalRelated;

  /// Higher is better. For an opportunity that teaches a skill gap it is
  /// the gain it had when the re-ranking placed it (between 0 and 1, never
  /// rising down the list). 0 for an opportunity that is only listed for
  /// the career goal (see [OpportunityRecommender]).
  final double score;

  /// For each skill in [gapSkills], how well this opportunity covers it,
  /// from 0 to 1. 1 means: the strongest match for that skill among the
  /// open opportunities, at full depth, at a suitable level and listed for
  /// the career goal.
  final Map<String, double> gapCoverage;

  const OpportunityMatch({
    required this.opportunity,
    required this.gapSkills,
    required this.currentSkills,
    required this.goalRelated,
    required this.score,
    this.gapCoverage = const {},
  });

  /// [gapSkills] from the best covered to the least covered (by
  /// [gapCoverage]); equal coverage keeps the order of the analysis. The
  /// cards show only the first few names, so the main topics of the
  /// opportunity come first and a passing mention falls into "+N more".
  List<String> get gapSkillsByCoverage {
    final order = List<int>.generate(gapSkills.length, (i) => i)
      ..sort((a, b) {
        final byCoverage = (gapCoverage[gapSkills[b]] ?? 0)
            .compareTo(gapCoverage[gapSkills[a]] ?? 0);
        return byCoverage != 0 ? byCoverage : a.compareTo(b);
      });
    return [for (final i in order) gapSkills[i]];
  }
}

/// The result of [OpportunityRecommender.recommend].
class OpportunityRecommendations {
  final String careerGoalId;

  /// The skill gaps the ranking used.
  final List<String> skillGaps;

  /// Open opportunities that cover a skill gap or fit the career goal,
  /// best first.
  final List<OpportunityMatch> matched;

  /// How many opportunities were skipped because registration has closed
  /// or the event has already started.
  final int closedHidden;

  /// What [filter] needs to re-rank a part of [matched], and the gaps for
  /// [uncoveredGaps]. Null when the object was built with the public
  /// constructor.
  final _Ranking? _ranking;

  const OpportunityRecommendations({
    required this.careerGoalId,
    required this.skillGaps,
    required this.matched,
    required this.closedHidden,
  }) : _ranking = null;

  const OpportunityRecommendations._ranked(
    this._ranking, {
    required this.careerGoalId,
    required this.skillGaps,
    required this.matched,
    required this.closedHidden,
  });

  bool get isEmpty => matched.isEmpty;

  /// The skill gaps that no open opportunity covers at all, in the order of
  /// the analysis: the catalogue has nothing on them (Splunk, NoSQL). The
  /// screen says so instead of dropping them silently. A gap that is
  /// covered, but only through a tag of its synonym group and never by
  /// name, is not listed here.
  List<String> get uncoveredGaps {
    final ranking = _ranking;
    if (ranking != null) return ranking.uncoveredGaps;
    final covered = {for (final m in matched) ...m.gapSkills};
    return [for (final gap in skillGaps) if (!covered.contains(gap)) gap];
  }

  static const List<String> _typeOrder = [
    'Training Program',
    'Bootcamp',
    'Hackathon',
    'Meetup',
    'Webinar',
    'Course',
  ];

  static const List<String> _sourceOrder = [
    'Tuwaiq Academy',
    'Doroob',
    'Coursera',
  ];

  /// The types found in [matched], known types first in a fixed order.
  List<String> get types =>
      _ordered(matched.map((m) => m.opportunity.type), _typeOrder);

  /// The platforms ([Opportunity.sourceLabel]) found in [matched], known
  /// platforms first in a fixed order.
  List<String> get sources =>
      _ordered(matched.map((m) => m.opportunity.sourceLabel), _sourceOrder);

  /// The matches of one type and/or one platform (compared with
  /// [Opportunity.sourceLabel]). Null means no filter.
  ///
  /// The order of [matched] comes from the coverage re-ranking (step 6 of
  /// [OpportunityRecommender]): an opportunity is placed lower when earlier
  /// results already teach its gaps. A filter can hide those earlier
  /// results, so the shown part is re-ranked on its own: its first results
  /// again cover as many gaps as they can, and near-copies do not end up
  /// next to each other. Each kept match then has the score it got in that
  /// re-ranking. Opportunities that only fit the career goal keep their
  /// order at the end.
  List<OpportunityMatch> filter({String? type, String? source}) {
    bool keep(Opportunity o) =>
        (type == null || o.type == type) &&
        (source == null || o.sourceLabel == source);

    final ranking = _ranking;
    if (ranking == null || (type == null && source == null)) {
      return matched.where((m) => keep(m.opportunity)).toList();
    }
    final teaching = [
      for (final candidate in ranking.teaching)
        if (keep(candidate.opportunity)) candidate,
    ];
    final picks = OpportunityRecommender._greedyOrder(
        teaching, ranking.share, ranking.diversity);
    return [
      for (final pick in picks) pick.candidate.toMatch(pick.gain),
      for (final m in matched.skip(ranking.teaching.length))
        if (keep(m.opportunity)) m,
    ];
  }

  /// Distinct non-empty [values]: those in [order] first, in that order,
  /// then the rest by name.
  static List<String> _ordered(Iterable<String> values, List<String> order) {
    final present = values.where((v) => v.isNotEmpty).toSet();
    final rest = present.where((v) => !order.contains(v)).toList()..sort();
    return [...order.where(present.contains), ...rest];
  }
}

/// Every number the ranking uses, in one place, with where it comes from.
/// The defaults are what the app uses. Other values are only passed by
/// tests and by the evaluation script
/// (tools/recommender_eval/evaluate_recommender.dart), which switches one
/// technique off at a time to measure what it adds.
class RankingWeights {
  /// BM25 saturation: how fast extra mentions of a skill stop adding to the
  /// score. 1.2 is the standard value (Robertson and Zaragoza 2009; also
  /// the default of the Lucene search library).
  final double k1;

  /// BM25 length normalization, from 0 (ignore the length of a text) to 1
  /// (divide fully by it). 0.75 is the standard value (same sources).
  final double b;

  /// Field weights: how much one mention counts in each field.
  /// Titles (about 5 words) and skill tags (2 to 3 per opportunity) are
  /// short statements of what the opportunity is about, so a mention there
  /// counts 3 times a mention in the description. Objectives are explicit
  /// learning outcomes and count 1.5 times. Descriptions (about 64 words)
  /// carry general text, sometimes shared by many records.
  final double titleWeight;
  final double skillsWeight;
  final double objectivesWeight;
  final double descriptionWeight;

  /// Market demand: the skill gap at rank k (0 = most requested in job
  /// postings) weighs demandDecay^k.
  ///
  /// 0.87 is measured, not chosen: tools/recommender_eval/
  /// fit_demand_decay.dart counts how many of the 881 bundled job postings
  /// mention each skill of a career family, and compares the k-th most
  /// mentioned skill with the top one. Over 70 points from the 6 families
  /// with at least 30 postings the best fit is 0.872. Its mean absolute
  /// error is 0.073 (0.074 for 0.87), against 0.117 for 1 / log2(k + 2),
  /// 0.263 for 1 / (k + 1) and 0.096 for a straight line. The skill lists
  /// in that script were written by the team.
  ///
  /// Set it to 1 to weigh all gaps equally.
  final double demandDecay;

  /// Coverage-aware re-ranking, from 0 to 1: the share of each pick that
  /// goes to "teaches gaps the earlier results did not cover". The rest
  /// goes to overall relevance. 0 switches the re-ranking off.
  ///
  /// 0.7 was fixed in the design before the labels were made. On the 8
  /// labelled personas (a development set, seen during the design) the
  /// first 10 results teach 85.3% of the gaps without re-ranking, 90.2%
  /// with 0.5, 93.3% with 0.7 and with 0.8, and 91.5% with 1
  /// (evaluate_recommender.dart --ablation). 0.8 has a slightly higher
  /// nDCG@10 (0.847 against 0.837), but that is within the noise of 8
  /// personas, and picking it after seeing the labels would fit the
  /// ranking to them, so 0.7 stays. With 1 the relevance is ignored, and
  /// it is what decides between opportunities that cover the same gaps.
  final double diversity;

  /// An opportunity that is not listed for the user's career goal keeps
  /// this share of its score. Its match is more often a side mention (a
  /// security diploma that mentions "monitoring"), so it needs about 25%
  /// stronger evidence to rank level with one inside the career path.
  final double offGoalFactor;

  /// Lost per level when an opportunity is above the user's level
  /// ([OpportunityRecommender.levelFit]). Small on purpose: a much
  /// stronger match on the topic can still win.
  final double levelStep;

  /// Lost per level when the user is Advanced and the opportunity is below
  /// that ([OpportunityRecommender.levelFit]). The idea: a course "for
  /// everyone" gives an experienced professional less. It is off (0): a
  /// skill gap is new to the user whatever their experience, and the
  /// labels agree. With 0.1, nDCG@10 on the labelled personas does not
  /// change on average, and "Introduction to Terraform" (very relevant for
  /// the advanced cloud persona) drops from 8th to 10th place. It is kept
  /// so the evaluation script can show this.
  final double easierStep;

  /// Depth of the shortest session, between 0 and 1
  /// ([OpportunityRecommender.depthOf]). A short session still teaches
  /// something: depth can at most halve a score.
  final double depthFloor;

  /// Learning hours from which an opportunity counts as full depth. Of the
  /// 195 courses in the catalogue that state their duration, a quarter
  /// take 10 hours or less, half 14 or less, three quarters 19 or less
  /// and nine in ten 25 or less. With 18, a course of typical full length
  /// counts fully and only shorter sessions count less.
  final double fullDepthHours;

  /// Query expansion: also search the free text for the other names of a
  /// skill in its synonym group ([SkillMatcher.expansionsOf]).
  ///
  /// Off by default. It was built and measured, and it is left off for two
  /// reasons. On the labelled personas it adds nothing (nDCG@10 0.835 with
  /// it, 0.837 without; evaluate_recommender.dart --ablation). And it makes
  /// the reasons on the cards wrong: a course found only through another
  /// name of the group is shown as teaching the user's own gap ("Penetration
  /// Testing" for a course on vulnerability management, "Docker" for a text
  /// that says "containers", "REST APIs" for "Amazon Web Services"). Skill
  /// tags still use the whole synonym table ([SkillMatcher.tagCovers]), so
  /// a course tagged "Databases and SQL" is still found for a SQL gap.
  final bool expandSynonyms;

  /// IDF: a skill that few opportunities teach counts more than a skill
  /// taught everywhere (see [OpportunityRecommender]). On the labelled
  /// personas it changes little (nDCG@10 0.837 with and without it). It
  /// matters when one gap is found in many records ("Python") and another
  /// in few ("Kafka"); a unit test shows that case.
  final bool useIdf;

  const RankingWeights({
    this.k1 = 1.2,
    this.b = 0.75,
    this.titleWeight = 3,
    this.skillsWeight = 3,
    this.objectivesWeight = 1.5,
    this.descriptionWeight = 1,
    this.demandDecay = 0.87,
    this.diversity = 0.7,
    this.offGoalFactor = 0.8,
    this.levelStep = 0.15,
    this.easierStep = 0,
    this.depthFloor = 0.5,
    this.fullDepthHours = 18,
    this.expandSynonyms = false,
    this.useIdf = true,
  });
}

/// Content-based recommender for learning opportunities (Tuwaiq Academy
/// events, Doroob and Coursera courses). It runs on the phone, offline, and
/// needs no trained model: it compares the user's analysis (career goal,
/// skill gaps, current skills) and experience level with the content of
/// each opportunity, using standard search-engine techniques.
///
/// Steps:
///  1. Filter. Skip opportunities the user can no longer join
///     ([Opportunity.isOpen]) and count them.
///
///  2. Find. For every skill gap, search the title, skill tags, objectives
///     and description of every opportunity ([OpportunityIndex.hitsFor]).
///     Requirements are not searched: they are what the learner needs
///     before joining, not what the opportunity teaches.
///     Skill tags go through the synonym table, so the tag "Databases and
///     SQL" covers a SQL gap. The free text is searched for the gap's own
///     name and spellings only. Query expansion (also searching the text
///     for the other names in the synonym group) was tried and measured,
///     and is off ([RankingWeights.expandSynonyms] says why).
///
///  3. Score each (gap, opportunity) pair with BM25F.
///     BM25 is the ranking function of most search engines. In plain words:
///       - more mentions of the skill help, but each extra mention helps
///         less than the one before (the tenth mention adds almost
///         nothing);
///       - a mention in a long text counts less than in a short one, since
///         a long text mentions many things in passing;
///       - the "F" means fields: a mention in the title or in a skill tag
///         counts more than one in the description
///         ([RankingWeights.titleWeight] and the other field weights).
///     IDF (inverse document frequency): a skill that only a few
///     opportunities teach counts more than a skill found everywhere. A
///     match on a rare skill says more about an opportunity than a match on
///     a skill that half the catalogue mentions.
///
///       tf    = sum over fields of
///               weight * mentions / (1 - b + b * length / average length)
///       idf   = ln(1 + (N - n + 0.5) / (n + 0.5))
///               (N opportunities, n of them teach the skill)
///       bm25  = idf * tf * (k1 + 1) / (tf + k1)
///
///  4. Weigh the gaps by market demand. The AI analysis lists the skill
///     gaps from the most to the least requested in job postings, so the
///     first gap weighs 1 and each next one a little less
///     ([demandWeight], [RankingWeights.demandDecay]).
///     Gaps that are the same skill under two names in the synonym table
///     ("Switching" and "Routing") are merged into one aspect, so the same
///     opportunities are not rewarded twice. A specific product (React,
///     Tableau) and a separate field of study (NLP, Computer Vision; see
///     [SkillMatcher.fieldOf]) are always their own aspect.
///     The reason line follows the evidence, not the aspect: of the gaps of
///     one aspect, an opportunity lists only those it names itself
///     ([OpportunityIndex.namesItself]), or else the most demanded one.
///
///  5. Adjust for the opportunity itself (the prior, between 0 and 1):
///       - depth: a one-hour webinar covers a skill less than a full
///         course ([depthOf], from the estimated learning hours);
///       - level: an opportunity above the user's level loses a little
///         ([levelFit]); one below it loses nothing, because a skill gap is
///         new to the user whatever their experience;
///       - career goal: an opportunity outside the user's career path
///         keeps [RankingWeights.offGoalFactor] of its score. Inside the
///         career path, a one-word gap name in a long objective counts too
///         ([FieldHits.looseObjectives]): there it most likely means what
///         the user needs.
///
///       relevance = prior * sum over the gaps it teaches of
///                   demand weight * bm25
///       coverage of a gap = prior * bm25 / best bm25 for that gap
///
///  6. Re-rank for coverage (xQuAD, Santos et al. 2010). A plain sort by
///     relevance puts near-copies first: three courses that all teach the
///     same two gaps. The list should read like a learning path, so it is
///     built one pick at a time. Each pick is mostly about the gaps still
///     left uncovered and partly about overall relevance:
///
///       gain = (1 - diversity) * relevance / best relevance
///            + diversity * (sum over gaps of demand share
///                           * coverage of the gap
///                           * how uncovered the gap still is)
///                        / best first-pick coverage
///
///     After a pick, the gaps it teaches count as (partly) covered, so
///     the next pick favours other gaps. Both parts are put on the same
///     0-to-1 scale (each divided by its best value), so
///     [RankingWeights.diversity] = 0.7 really means 70% coverage and 30%
///     relevance.
///
///  7. Tiers. Opportunities that teach at least one skill gap always come
///     first (in the order of step 6). Opportunities that teach none but
///     are listed for the career goal follow, with score 0: dated events
///     first, then deeper and better-levelled ones. Building on current
///     skills alone is not enough to be listed.
///
///  8. Ties. Equal gains are ordered by: dated events first, the nearest
///     deadline (or start date), more current skills, title, id. The same
///     input always gives the same list.
///
///  9. Filters. When the user picks a type or a platform, the shown part
///     is re-ranked on its own with step 6
///     ([OpportunityRecommendations.filter]).
///
/// Limits: matching is by words, not by meaning ("React Native" counts for
/// a "React" gap, and a course titled "Risk Identification, Monitoring, and
/// Analysis" counts for a "Monitoring" gap of a cloud engineer).
/// Understanding meaning needs a language model (embeddings), which is
/// future work.
class OpportunityRecommender {
  const OpportunityRecommender({this.weights = const RankingWeights()});

  final RankingWeights weights;

  /// [experienceLevel] is the level from the user's profile ("No
  /// Experience", "Beginner", "Intermediate", "Advanced"). Null or any
  /// other value means the level is not used.
  ///
  /// Pass the same [opportunities] list object on every call: the search
  /// index is built once per list and reused ([OpportunityIndex.of]).
  OpportunityRecommendations recommend({
    required Map<String, dynamic> analysis,
    required List<Opportunity> opportunities,
    DateTime? now,
    String? experienceLevel,
  }) {
    final today = now ?? DateTime.now();
    final goalId = analysis['careerGoalId']?.toString().trim() ?? '';
    final gaps = ContentBasedRecommender.skillGapsOf(analysis);
    final current = ContentBasedRecommender.currentSkillsOf(analysis);

    // Step 1: open or closed.
    final index = OpportunityIndex.of(opportunities);
    final open = index.openOn(today);
    final closed = open.where((isOpen) => !isOpen).length;

    // Steps 2 to 4: evidence per gap, and how much each gap weighs.
    final bm25 = [for (final gap in gaps) _bm25ForGap(index, gap, goalId)];
    final bestBm25 = [for (final scores in bm25) _bestOpen(scores, open)];
    final gapWeights = _gapWeights(gaps, analysis);
    final aspects = _Aspects.of(gaps, gapWeights);
    final currentHits = [
      for (final skill in current) _evidenceFor(index, skill, goalId),
    ];
    final userLevel = userLevelOf(experienceLevel);

    final teaching = <_Candidate>[]; // tier 1
    final goalOnly = <_Candidate>[]; // tier 2

    for (var i = 0; i < index.size; i++) {
      if (!open[i]) continue;
      final opportunity = index.opportunityAt(i);
      final goalRelated =
          goalId.isNotEmpty && opportunity.careerPathIds.contains(goalId);

      final covered = <int>[
        for (var g = 0; g < gaps.length; g++)
          if (bm25[g].containsKey(i)) g,
      ];
      if (covered.isEmpty && !goalRelated) continue;

      final shown = _shownGaps(index, i, covered, gaps, gapWeights, aspects);
      final gapSkills = [for (final g in shown) gaps[g]];
      final gapKeys = gapSkills.map(SkillMatcher.canonical).toSet();
      final currentSkills = <String>[
        for (var c = 0; c < current.length; c++)
          if (currentHits[c].containsKey(i) &&
              !gapKeys.contains(SkillMatcher.canonical(current[c])))
            current[c],
      ];

      // Step 5: the prior.
      final quality = depthOf(index.hoursAt(i), weights: weights) *
          levelFit(index.levelAt(i), userLevel,
              step: weights.levelStep, easierStep: weights.easierStep);
      final prior = quality * (goalRelated ? 1.0 : weights.offGoalFactor);

      final candidate = _Candidate(
        opportunity: opportunity,
        gapSkills: gapSkills,
        currentSkills: currentSkills,
        goalRelated: goalRelated,
        quality: quality,
        aspectCoverage: List<double>.filled(aspects.count, 0),
      );
      if (covered.isEmpty) {
        goalOnly.add(candidate);
        continue;
      }

      // The ranking uses every covered gap: within an aspect only the best
      // one counts, so a gap left out of the reason line adds nothing.
      final aspectBm25 = List<double>.filled(aspects.count, 0);
      for (final g in covered) {
        final score = bm25[g][i]!;
        final coverage = min(1.0, prior * score / bestBm25[g]);
        if (shown.contains(g)) candidate.gapCoverage[gaps[g]] = coverage;

        final a = aspects.ofGap[g];
        aspectBm25[a] = max(aspectBm25[a], score);
        candidate.aspectCoverage[a] =
            max(candidate.aspectCoverage[a], coverage);
      }
      var relevance = 0.0;
      for (var a = 0; a < aspects.count; a++) {
        relevance += aspects.weight[a] * aspectBm25[a];
      }
      candidate.relevance = prior * relevance;
      teaching.add(candidate);
    }

    // Steps 6 to 8.
    final diversity = weights.diversity.clamp(0.0, 1.0).toDouble();
    final picks = _greedyOrder(teaching, aspects.share, diversity);
    goalOnly.sort(_byGoalOnlyOrder);

    return OpportunityRecommendations._ranked(
      _Ranking(
        teaching: [for (final pick in picks) pick.candidate],
        share: aspects.share,
        diversity: diversity,
        uncoveredGaps: [
          for (var g = 0; g < gaps.length; g++)
            if (bestBm25[g] <= 0) gaps[g],
        ],
      ),
      careerGoalId: goalId,
      skillGaps: gaps,
      matched: [
        for (final pick in picks) pick.candidate.toMatch(pick.gain),
        for (final candidate in goalOnly) candidate.toMatch(0),
      ],
      closedHidden: closed,
    );
  }

  /// The same list as [recommend]. The search index is built at most once
  /// per list, and never on the main isolate.
  ///
  ///  - First call for a list (no index yet): the index is built and the
  ///    ranking runs on a background isolate, so the screen keeps drawing
  ///    frames (the loading spinner, the pull-to-refresh animation)
  ///    meanwhile. Isolates do not share memory, so the index built there,
  ///    with the hits it found for the user's skills, comes back with the
  ///    result and is kept for this list ([OpportunityIndex.adopt]).
  ///  - Every later call on the same list (reopening the screen, coming
  ///    back from the career analysis): the index is already here
  ///    ([OpportunityIndex.cachedFor]), so the ranking runs right away on
  ///    this isolate. On a desktop that takes about a millisecond or less
  ///    for a user seen before and a few milliseconds for new skills, less
  ///    than the background call itself (see the TIMING block of
  ///    tools/recommender_eval/evaluate_recommender.dart).
  ///
  /// Only plain values are sent to the other isolate: the career goal, the
  /// skill gaps, the current skills and the market skills as strings, plus
  /// the opportunities. The analysis read from Firestore may hold values
  /// that cannot be sent. If the platform cannot run isolates, the ranking
  /// runs here instead.
  Future<OpportunityRecommendations> recommendInBackground({
    required Map<String, dynamic> analysis,
    required List<Opportunity> opportunities,
    DateTime? now,
    String? experienceLevel,
  }) async {
    final plain = <String, dynamic>{
      'careerGoalId': analysis['careerGoalId']?.toString() ?? '',
      'skillGaps': ContentBasedRecommender.skillGapsOf(analysis),
      'currentSkills': ContentBasedRecommender.currentSkillsOf(analysis),
      'targetSkills': [
        for (final skill in analysis['targetSkills'] is List
            ? analysis['targetSkills'] as List
            : const [])
          if (skill is String) skill,
      ],
    };
    final today = now ?? DateTime.now();
    OpportunityRecommendations here() => recommend(
          analysis: plain,
          opportunities: opportunities,
          now: today,
          experienceLevel: experienceLevel,
        );

    if (OpportunityIndex.cachedFor(opportunities) != null) return here();

    // The items as they are now. The other isolate builds from a copy of
    // this list, so the index it sends back matches it position by position.
    final items = List<Opportunity>.unmodifiable(opportunities);
    try {
      final (result, index) = await _runInBackground(
          weights, plain, items, today, experienceLevel);
      OpportunityIndex.adopt(opportunities, index, builtFrom: items);
      return result;
    } on UnsupportedError {
      return here();
    }
  }

  /// Static, so the task sent to the isolate cannot capture anything but
  /// its arguments. Returns the ranking and the index it was built with.
  static Future<(OpportunityRecommendations, OpportunityIndex)>
      _runInBackground(
    RankingWeights weights,
    Map<String, dynamic> analysis,
    List<Opportunity> opportunities,
    DateTime now,
    String? experienceLevel,
  ) {
    return Isolate.run(() {
      final result = OpportunityRecommender(weights: weights).recommend(
        analysis: analysis,
        opportunities: opportunities,
        now: now,
        experienceLevel: experienceLevel,
      );
      // The index recommend() just built (cached for this list).
      return (result, OpportunityIndex.of(opportunities));
    });
  }

  /// The covered gaps (positions in [gaps]) that the reason line shows for
  /// opportunity [i]. A gap that is the only one of its aspect is always
  /// shown. Of an aspect that holds several of the user's gaps, only those
  /// the opportunity names itself are shown ([OpportunityIndex.namesItself]):
  /// the tag "Network Security" stands for Firewall, VPN and Network
  /// Security alike, but a course should only be said to teach VPN when it
  /// says so. When it names none of them, the most demanded one is shown.
  static List<int> _shownGaps(
    OpportunityIndex index,
    int i,
    List<int> covered,
    List<String> gaps,
    List<double> gapWeights,
    _Aspects aspects,
  ) {
    final byAspect = <int, List<int>>{};
    for (final g in covered) {
      (byAspect[aspects.ofGap[g]] ??= <int>[]).add(g);
    }
    final shown = <int>{};
    byAspect.forEach((a, inAspect) {
      if (aspects.gapCount[a] < 2) {
        shown.addAll(inAspect);
        return;
      }
      final named = [
        for (final g in inAspect)
          if (index.namesItself(i, gaps[g])) g,
      ];
      if (named.isNotEmpty) {
        shown.addAll(named);
        return;
      }
      var best = inAspect.first;
      for (final g in inAspect) {
        if (gapWeights[g] > gapWeights[best]) best = g;
      }
      shown.add(best);
    });
    return [for (final g in covered) if (shown.contains(g)) g];
  }

  // ---------------------------------------------------------
  // SCORING
  // ---------------------------------------------------------

  /// How much the skill gap at [rank] weighs (0 = most requested in the
  /// job market): 1, 0.87, 0.76, 0.66 ... See [RankingWeights.demandDecay].
  static double demandWeight(int rank, {double decay = 0.87}) =>
      pow(decay, rank).toDouble();

  /// Depth of an opportunity from its estimated learning [hours], between
  /// [RankingWeights.depthFloor] and 1. It grows quickly for the first
  /// hours and then flattens (a logarithm): the step from 1 to 5 hours
  /// matters more than the step from 30 to 34. From
  /// [RankingWeights.fullDepthHours] on it is 1.
  static double depthOf(
    double hours, {
    RankingWeights weights = const RankingWeights(),
  }) {
    final full = log(1 + weights.fullDepthHours);
    final share = full <= 0 ? 1.0 : min(1.0, log(1 + max(0.0, hours)) / full);
    return weights.depthFloor + (1 - weights.depthFloor) * share;
  }

  /// The user's level as a number: 0 beginner (also "No Experience"),
  /// 1 intermediate, 2 advanced. Null when the profile has no known level.
  /// Uses the same mapping as the certifications recommender
  /// ([ContentBasedRecommender.preferredLevel]).
  static int? userLevelOf(String? experienceLevel) {
    switch (ContentBasedRecommender.preferredLevel(experienceLevel)) {
      case 'Beginner':
        return 0;
      case 'Intermediate':
        return 1;
      case 'Advanced':
        return 2;
      default:
        return null;
    }
  }

  /// How well the level of an opportunity suits the user, between 0 and 1.
  /// Levels are 0, 1, 2 as in [OpportunityIndex.levelOf].
  ///  - Each level above the user's costs [step]: an advanced course is 0.7
  ///    for a beginner and 0.85 for an intermediate user.
  ///  - For an advanced user, each level below costs [easierStep] (0 by
  ///    default, see [RankingWeights.easierStep]).
  ///  - Otherwise it is 1: at or below the user's level, and when either
  ///    level is unknown.
  static double levelFit(
    int? opportunityLevel,
    int? userLevel, {
    double step = 0.15,
    double easierStep = 0,
  }) {
    if (opportunityLevel == null || userLevel == null) return 1;
    final above = max(0, opportunityLevel - userLevel);
    final below =
        userLevel >= advancedLevel ? max(0, userLevel - opportunityLevel) : 0;
    return max(0.0, 1 - step * above - easierStep * below);
  }

  /// The number [userLevelOf] gives for "Advanced".
  static const int advancedLevel = 2;

  /// The demand weight of each gap. The rank of a gap is its position in
  /// the market skills of the analysis (`targetSkills`, most requested
  /// first). When that list is missing or does not contain every gap, the
  /// position in the gap list is used for all of them, so ranks from two
  /// lists are never mixed.
  List<double> _gapWeights(List<String> gaps, Map<String, dynamic> analysis) {
    final market = _marketSkills(analysis['targetSkills']);
    final marketRanks = [
      for (final gap in gaps) market.indexOf(SkillMatcher.searchKey(gap)),
    ];
    final useMarket = marketRanks.every((rank) => rank >= 0);
    return [
      for (var g = 0; g < gaps.length; g++)
        demandWeight(useMarket ? marketRanks[g] : g,
            decay: weights.demandDecay),
    ];
  }

  /// The market skills of the analysis as [SkillMatcher.searchKey]s, without
  /// duplicates.
  static List<String> _marketSkills(dynamic raw) {
    if (raw is! List) return const [];
    final result = <String>[];
    for (final value in raw) {
      if (value is! String) continue;
      final key = SkillMatcher.searchKey(value);
      if (key.isNotEmpty && !result.contains(key)) result.add(key);
    }
    return result;
  }

  /// opportunity index -> BM25 score of [skill], for every opportunity in
  /// the catalogue that teaches it (see step 3 of the class comment).
  /// [goalId] is the user's career goal ([_evidenceFor] needs it).
  Map<int, double> _bm25ForGap(
    OpportunityIndex index,
    String skill,
    String goalId,
  ) {
    final evidence = _evidenceFor(index, skill, goalId);
    // n counts closed opportunities too, and only the evidence that does
    // not depend on the user: how rare a skill is in the catalogue does not
    // change from day to day or from user to user.
    final n = index
        .hitsFor(skill, expand: weights.expandSynonyms)
        .values
        .where((hits) => hits.hasEvidence)
        .length;
    final idf = weights.useIdf
        ? log(1 + (index.size - n + 0.5) / (n + 0.5))
        : 1.0;
    return evidence.map((i, tf) =>
        MapEntry(i, idf * tf * (weights.k1 + 1) / (tf + weights.k1)));
  }

  /// opportunity index -> weighted mentions of [skill] (the "tf" of the
  /// class comment). Only opportunities with evidence are in the result.
  /// Loose mentions in long objectives ([FieldHits.looseObjectives]) count
  /// as objective mentions only for an opportunity listed for the career
  /// goal [goalId].
  Map<int, double> _evidenceFor(
    OpportunityIndex index,
    String skill,
    String goalId,
  ) {
    final result = <int, double>{};
    index.hitsFor(skill, expand: weights.expandSynonyms).forEach((i, hits) {
      final inGoal = goalId.isNotEmpty &&
          index.opportunityAt(i).careerPathIds.contains(goalId);
      var tf = 0.0;
      for (final field in OpportunityField.values) {
        var mentions = hits.of(field);
        if (field == OpportunityField.objectives && inGoal) {
          mentions += hits.looseObjectives;
        }
        if (mentions == 0) continue;
        final relativeLength =
            index.fieldLength(i, field) / index.averageLength(field);
        tf += _fieldWeight(field) *
            mentions /
            (1 - weights.b + weights.b * relativeLength);
      }
      if (tf > 0) result[i] = tf;
    });
    return result;
  }

  double _fieldWeight(OpportunityField field) {
    switch (field) {
      case OpportunityField.title:
        return weights.titleWeight;
      case OpportunityField.skills:
        return weights.skillsWeight;
      case OpportunityField.objectives:
        return weights.objectivesWeight;
      case OpportunityField.description:
        return weights.descriptionWeight;
    }
  }

  /// The best score among the opportunities that are still open.
  static double _bestOpen(Map<int, double> scores, List<bool> open) {
    var best = 0.0;
    scores.forEach((i, score) {
      if (open[i] && score > best) best = score;
    });
    return best;
  }

  // ---------------------------------------------------------
  // RE-RANKING
  // ---------------------------------------------------------

  /// Orders the opportunities that teach a gap (step 6 of the class
  /// comment) and gives each one its score.
  ///
  /// It is a greedy method: it always takes the opportunity with the
  /// highest gain, then lowers how "uncovered" its gaps are. For this kind
  /// of coverage goal, picking greedily is known to stay close to the best
  /// possible list (Nemhauser et al. 1978).
  ///
  /// [diversity] is [RankingWeights.diversity]. The candidates are not
  /// changed, so [OpportunityRecommendations.filter] can re-rank a part of
  /// them later.
  static List<({_Candidate candidate, double gain})> _greedyOrder(
    List<_Candidate> candidates,
    List<double> share,
    double diversity,
  ) {
    if (candidates.isEmpty) return const [];

    // The best value of each part, to put both on a 0-to-1 scale.
    var bestRelevance = 0.0;
    var bestCoverage = 0.0;
    for (final candidate in candidates) {
      bestRelevance = max(bestRelevance, candidate.relevance);
      var coverage = 0.0;
      for (var a = 0; a < share.length; a++) {
        coverage += share[a] * candidate.aspectCoverage[a];
      }
      bestCoverage = max(bestCoverage, coverage);
    }

    final uncovered = List<double>.filled(share.length, 1);
    final remaining = [...candidates];
    final ordered = <({_Candidate candidate, double gain})>[];

    while (remaining.isNotEmpty) {
      var bestAt = 0;
      var bestGain = double.negativeInfinity;
      for (var k = 0; k < remaining.length; k++) {
        final candidate = remaining[k];
        var coverage = 0.0;
        for (var a = 0; a < share.length; a++) {
          coverage += share[a] * candidate.aspectCoverage[a] * uncovered[a];
        }
        final gain = (1 - diversity) *
                (bestRelevance > 0 ? candidate.relevance / bestRelevance : 0) +
            diversity * (bestCoverage > 0 ? coverage / bestCoverage : 0);

        final better = gain > bestGain + _tie;
        final tied = !better && (gain - bestGain).abs() <= _tie;
        if (better || (tied && _byTieBreak(candidate, remaining[bestAt]) < 0)) {
          bestAt = k;
          bestGain = gain;
        }
      }

      final picked = remaining.removeAt(bestAt);
      for (var a = 0; a < share.length; a++) {
        uncovered[a] *= 1 - picked.aspectCoverage[a];
      }
      ordered.add((candidate: picked, gain: bestGain));
    }
    return ordered;
  }

  // ---------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------

  /// Two gains closer than this are a tie (floating-point rounding).
  static const double _tie = 1e-12;

  /// Order of two opportunities with the same gain: dated events first,
  /// then the nearest date, more current skills, title, id.
  static int _byTieBreak(_Candidate a, _Candidate b) {
    final oa = a.opportunity;
    final ob = b.opportunity;
    final byDated = (ob.hasDates ? 1 : 0).compareTo(oa.hasDates ? 1 : 0);
    if (byDated != 0) return byDated;
    return _byDateSkillsTitle(a, b);
  }

  /// Order of the opportunities that teach no gap: dated events first (so
  /// live events are not buried under always-available courses), then the
  /// deeper and better-levelled ones, then as for ties.
  static int _byGoalOnlyOrder(_Candidate a, _Candidate b) {
    final oa = a.opportunity;
    final ob = b.opportunity;
    final byDated = (ob.hasDates ? 1 : 0).compareTo(oa.hasDates ? 1 : 0);
    if (byDated != 0) return byDated;
    final byQuality = b.quality.compareTo(a.quality);
    if (byQuality != 0) return byQuality;
    return _byDateSkillsTitle(a, b);
  }

  static int _byDateSkillsTitle(_Candidate a, _Candidate b) {
    final oa = a.opportunity;
    final ob = b.opportunity;
    final da = _keyDate(oa);
    final db = _keyDate(ob);
    if (da != null && db != null) {
      final byDate = da.compareTo(db);
      if (byDate != 0) return byDate;
    } else if (da != null || db != null) {
      return da != null ? -1 : 1; // a known date first
    }

    final bySkills = b.currentSkills.length.compareTo(a.currentSkills.length);
    if (bySkills != 0) return bySkills;

    final byTitle = oa.title.toLowerCase().compareTo(ob.title.toLowerCase());
    if (byTitle != 0) return byTitle;
    return oa.id.compareTo(ob.id);
  }

  /// The date that matters most to the user: the deadline, else the start.
  static DateTime? _keyDate(Opportunity o) =>
      o.registrationDeadline ?? o.startDate ?? o.endDate;
}

/// The skill gaps grouped into aspects: gaps that are the same skill in
/// the synonym table share one aspect. A specific product (React, Tableau)
/// and a separate field of study (NLP, Computer Vision) are always their
/// own aspect.
class _Aspects {
  /// gap position -> aspect position.
  final List<int> ofGap;

  /// Demand weight of each aspect: the largest weight among its gaps.
  final List<double> weight;

  /// [weight] divided by the sum of all weights (the shares add up to 1).
  final List<double> share;

  /// How many of the user's gaps each aspect holds.
  final List<int> gapCount;

  const _Aspects(this.ofGap, this.weight, this.share, this.gapCount);

  int get count => weight.length;

  factory _Aspects.of(List<String> gaps, List<double> gapWeights) {
    final keys = <String>[];
    final ofGap = <int>[];
    final weight = <double>[];
    final gapCount = <int>[];
    for (var g = 0; g < gaps.length; g++) {
      final key = keyOf(gaps[g]);
      var a = keys.indexOf(key);
      if (a < 0) {
        a = keys.length;
        keys.add(key);
        weight.add(0);
        gapCount.add(0);
      }
      ofGap.add(a);
      weight[a] = max(weight[a], gapWeights[g]);
      gapCount[a]++;
    }
    final total = weight.fold<double>(0, (sum, w) => sum + w);
    return _Aspects(
      ofGap,
      weight,
      [for (final w in weight) total > 0 ? w / total : 0.0],
      gapCount,
    );
  }

  /// The aspect a gap belongs to: a product by its own name ("csharp" and
  /// "cpp" stay apart, see [SkillMatcher.searchKey]), a field of study by
  /// its field, any other skill by its synonym group.
  static String keyOf(String gap) {
    if (SkillMatcher.isSpecific(gap)) return SkillMatcher.searchKey(gap);
    return SkillMatcher.fieldOf(gap) ?? SkillMatcher.canonical(gap);
  }
}

/// What [OpportunityRecommendations.filter] needs to re-rank a part of the
/// list (the opportunities that teach a gap, in their ranked order, and the
/// numbers of step 6), and the gaps that nothing covers.
class _Ranking {
  final List<_Candidate> teaching;
  final List<double> share;
  final double diversity;
  final List<String> uncoveredGaps;

  const _Ranking({
    required this.teaching,
    required this.share,
    required this.diversity,
    required this.uncoveredGaps,
  });
}

/// One open opportunity while it is being ranked.
class _Candidate {
  final Opportunity opportunity;
  final List<String> gapSkills;
  final List<String> currentSkills;
  final bool goalRelated;

  /// Depth times level fit (the prior without the career goal part).
  final double quality;

  /// Coverage of each aspect, from 0 to 1.
  final List<double> aspectCoverage;
  final Map<String, double> gapCoverage = {};
  double relevance = 0;

  _Candidate({
    required this.opportunity,
    required this.gapSkills,
    required this.currentSkills,
    required this.goalRelated,
    required this.quality,
    required this.aspectCoverage,
  });

  OpportunityMatch toMatch(double score) => OpportunityMatch(
        opportunity: opportunity,
        gapSkills: gapSkills,
        currentSkills: currentSkills,
        goalRelated: goalRelated,
        score: score,
        gapCoverage: gapCoverage,
      );
}
