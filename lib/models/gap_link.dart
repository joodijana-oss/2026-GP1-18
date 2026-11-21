/// How the recommenders use meaning links for a skill gap.
///
/// A skill gap is written as job postings write it ("Roadmap Planning"),
/// while the catalogues use their own names ("Product Management"). When
/// the gap's own name finds no skill of a catalogue, the gap is a hole, and
/// a link tells the recommender which catalogue names the gap belongs to.
/// Links only fill holes: a gap that already finds a catalogue skill by its
/// own name is matched exactly as before, and so is an analysis that has no
/// links stored.
///
/// The rule the settings below implement: find by meaning, claim only with
/// evidence. A link may bring an item in, but before the card names the gap
/// as its reason, the item's own text (title, objectives and description of
/// an opportunity; name and description of a certification) must show the
/// gap. That is the support gate.
class LinkSettings {
  /// False: no links at all, words and the synonym table only.
  final bool enabled;

  /// The support gate. A catalogue name the gap is linked to as a broader
  /// skill ([GapLink.covers]) counts for an item only when the item's own
  /// text supports the gap: it contains the gap's whole name as a phrase,
  /// or at least one distinctive word of it. With the gate off every
  /// linked name counts for every item that carries it.
  final bool supportGate;

  /// A word is distinctive when at most this share of the catalogue's
  /// items contain it in their own text. The share is counted from the
  /// list the recommender receives, at run time: there is no word list.
  /// Common words ("management", "security") exceed it by themselves.
  final double theta;

  /// The terms and phrases stored with a link ([GapLink.supportTerms])
  /// count as support too: a term of two words or more as a phrase, a
  /// one-word term only when it is distinctive.
  final bool termSupport;

  /// The item's skill tags count as its own text for the support test.
  final bool tagSupport;

  /// Opportunities only. An item the gate does not support keeps the
  /// link's evidence for the ranking, but the gap is left out of its
  /// reason line. Off: an unsupported item gets no evidence at all, so the
  /// reason on a card always matches why the item ranks.
  final bool reasonOnly;

  /// False: the broader-skill links ([GapLink.covers]) are ignored and
  /// only same-skill links ([GapLink.same]) count.
  final bool useCovers;

  /// For a hole with no linked name at all, a stored term of two words or
  /// more found as a phrase in an item's own text is evidence.
  final bool termEvidence;

  /// The stored phrases of two words or more are searched in the texts as
  /// evidence of their own, whatever the gate says (round 1's second
  /// approach; kept for the evaluation).
  final bool phraseSearch;

  const LinkSettings({
    this.enabled = true,
    this.supportGate = true,
    this.theta = 0.05,
    this.termSupport = false,
    this.tagSupport = false,
    this.reasonOnly = false,
    this.useCovers = true,
    this.termEvidence = false,
    this.phraseSearch = false,
  });

  /// No links: today's matching.
  static const LinkSettings off = LinkSettings(enabled: false);

  /// Every stored link counts, with no support test (round 1's approach).
  static const LinkSettings ungated = LinkSettings(supportGate: false);

  // ---------------------------------------------------------
  // WHAT THE APP RUNS
  // ---------------------------------------------------------
  //
  // The three switches of matching by meaning are here, in one place. They
  // stay off until the final measurement has picked an approach: the app
  // then sends no link request, stores no links, and the recommenders give
  // exactly today's lists.

  /// Whether a new analysis asks the AI model for links and stores them as
  /// `gapLinks` (one more AI request per analysis).
  static const bool requestedByApp = false;

  /// Which link request the app sends when [requestedByApp] is true.
  static const LinkRequest appRequest = LinkRequest.typed;

  /// How the opportunity recommender uses stored links.
  static const LinkSettings appOpportunities = off;

  /// How the certification recommender uses stored links.
  static const LinkSettings appCertifications = off;
}

/// The two link requests (lib/services/career_analysis_pipeline.dart).
enum LinkRequest {
  /// Catalogue names and search phrases per skill (round 1's request).
  names,

  /// Typed links: catalogue names that name the same skill, catalogue
  /// names of a broader skill that teaches it as a main topic, and short
  /// terms a course text uses when it teaches the skill.
  typed,
}

/// One skill gap of an analysis with the catalogue names it belongs to.
/// Stored in the analysis document as `gapLinks`, a list of
/// `{gap, kind, concepts, phrases}` maps, with `same` and `terms` added
/// when the typed request filled them (a list, not a map: a gap name can
/// contain a dot, which Firestore does not allow in a map key).
class GapLink {
  /// The gap name exactly as in `skillGaps`.
  final String gap;

  /// What the name is: `skill`, `tool`, `certification` or `soft`.
  final String kind;

  /// Every catalogue skill name the gap is linked to (synonym table groups
  /// and opportunity skill tags): the [same] names first, then the
  /// [covers] names.
  final List<String> concepts;

  /// The names in [concepts] that name this very skill (another name, an
  /// abbreviation, a wording variant). They count like a skill tag of the
  /// gap and need no support. Empty for a link of the first request, which
  /// did not tell the two kinds apart.
  final List<String> same;

  /// Short phrases a course description would use for this skill (the
  /// first request).
  final List<String> phrases;

  /// Short terms a course text contains when it really teaches this skill
  /// (the typed request).
  final List<String> terms;

  const GapLink({
    required this.gap,
    this.kind = skillKind,
    this.concepts = const [],
    this.same = const [],
    this.phrases = const [],
    this.terms = const [],
  });

  static const String skillKind = 'skill';
  static const String toolKind = 'tool';
  static const String certificationKind = 'certification';
  static const String softKind = 'soft';

  static const List<String> kinds = [
    skillKind,
    toolKind,
    certificationKind,
    softKind,
  ];

  /// A tool or a certification is only taught by a course that names it, so
  /// its links are never used: a course on the broad skill does not teach
  /// the product.
  bool get isProduct => kind == toolKind || kind == certificationKind;

  /// The names in [concepts] of a broader skill: every name that is not in
  /// [same]. They count for an item only where the item supports the gap
  /// ([LinkSettings.supportGate]).
  List<String> get covers => [
        for (final name in concepts)
          if (!same.contains(name)) name,
      ];

  /// The wording that can support the gap in an item's text: the terms of
  /// the typed request and the phrases of the first one.
  List<String> get supportTerms => [...terms, ...phrases];

  Map<String, dynamic> toMap() => {
        'gap': gap,
        'kind': kind,
        'concepts': concepts,
        'phrases': phrases,
        if (same.isNotEmpty) 'same': same,
        if (terms.isNotEmpty) 'terms': terms,
      };

  /// Reads `gapLinks` from an analysis document. Tolerant on purpose: an
  /// analysis saved before links existed has no such field, and Firestore
  /// returns lists and maps with dynamic types. Anything that is not a
  /// usable link is skipped, so the result is an empty list at worst.
  static List<GapLink> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    final result = <GapLink>[];
    for (final item in raw) {
      if (item is GapLink) {
        result.add(item);
        continue;
      }
      if (item is! Map) continue;
      final gap = item['gap']?.toString().trim() ?? '';
      if (gap.isEmpty) continue;
      final kind = item['kind']?.toString().trim().toLowerCase() ?? '';
      final concepts = _strings(item['concepts']);
      result.add(GapLink(
        gap: gap,
        kind: kinds.contains(kind) ? kind : skillKind,
        concepts: concepts,
        same: [
          for (final name in _strings(item['same']))
            if (concepts.contains(name)) name,
        ],
        phrases: _strings(item['phrases']),
        terms: _strings(item['terms']),
      ));
    }
    return result;
  }

  /// The link of each gap name, for the gaps that have one.
  static Map<String, GapLink> byGap(Iterable<GapLink> links) => {
        for (final link in links) link.gap: link,
      };

  static List<String> _strings(dynamic raw) {
    if (raw is! List) return const [];
    final result = <String>[];
    for (final value in raw) {
      if (value is! String) continue;
      final text = value.trim();
      if (text.isNotEmpty && !result.contains(text)) result.add(text);
    }
    return result;
  }
}
