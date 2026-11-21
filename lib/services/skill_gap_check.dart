import '../utils/skill_matcher.dart';

/// What the CV shows for one market skill.
enum SkillEvidence {
  /// The CV gives direct evidence of the skill.
  shown,

  /// Only weak or indirect evidence.
  partly,

  /// The CV does not show it: a skill gap.
  missing,
}

/// The result of checking the market skills against the CV text.
class SkillGapCheckResult {
  /// One entry per target skill, in the order of the target skills.
  final List<MapEntry<String, SkillEvidence>> statuses;

  /// The skill gaps, in the order of the target skills.
  final List<String> gaps;

  /// How many "shown" or "partly" answers were turned into "missing"
  /// because their quote is not in the CV.
  final int unverifiedQuotes;

  const SkillGapCheckResult({
    required this.statuses,
    required this.gaps,
    required this.unverifiedQuotes,
  });

  /// `targetSkillStatus` as stored with the analysis: the status of every
  /// target skill, without the CV quotes (they are only used here, in
  /// memory, to verify the answer).
  List<Map<String, String>> toStoredList() => [
        for (final entry in statuses)
          {'skill': entry.key, 'status': entry.value.name},
      ];
}

/// Turns the AI answer of the CV evidence check into skill gaps.
///
/// The gap step used to compare two lists of names (the skills extracted
/// from the CV and the skills job postings ask for) and never saw the CV
/// itself. Whatever the CV showed only as an activity ("triaged alerts
/// during an internship") became a gap. The evidence check reads the CV
/// text and answers, for every target skill, shown, partly or missing, with
/// a short quote from the CV for the first two.
///
/// This class does not trust that answer blindly:
///  - a "shown" or "partly" answer must come with a quote that really is in
///    the CV ([quoteFound]); otherwise the skill counts as missing, so an
///    invented quote can never hide a gap;
///  - a target skill the answer does not mention counts as missing;
///  - an answer belongs to a target skill by its exact name; a looser
///    comparison is used only where it cannot mix two skills up, so "C#"
///    and "C++" never share an answer ([answersFor]);
///  - names that are not target skills are ignored, so no gap is invented;
///  - an answer that mentions none of the target skills is not usable and
///    throws, so the caller falls back to the comparison by names.
class SkillGapCheck {
  SkillGapCheck._();

  /// A quote of this many words or more may differ a little from the CV
  /// (line breaks, bullets and hyphens of text copied out of a PDF).
  static const int minWordsForLooseQuote = 3;

  /// The share of a quote's words that must be in the CV, in their order
  /// and close together, when the quote is not found as it is.
  static const double looseQuoteShare = 0.8;

  /// How many more CV words than the quote has may lie between the first
  /// and the last word of a loose quote.
  static const int looseQuoteSlack = 3;

  /// [raw] is the `skills` list of the AI answer: `{skill, status, quote}`
  /// per target skill. With [partlyIsGap] a "partly" skill is a gap too; by
  /// default it is not, because the CV does show something to build on.
  static SkillGapCheckResult resolve({
    required List<String> targetSkills,
    required dynamic raw,
    required String cvText,
    bool partlyIsGap = false,
  }) {
    if (raw is! List) {
      throw const FormatException('The evidence check returned no list.');
    }
    final answers = answersFor(targetSkills, raw);

    final cv = _CvText(cvText);
    final statuses = <MapEntry<String, SkillEvidence>>[];
    final gaps = <String>[];
    var answered = 0;
    var unverified = 0;
    for (final skill in targetSkills) {
      final answer = answers[skill];
      var status = SkillEvidence.missing;
      if (answer != null) {
        answered++;
        status = _statusOf(answer['status']);
        if (status != SkillEvidence.missing &&
            !cv.contains(answer['quote']?.toString() ?? '')) {
          status = SkillEvidence.missing;
          unverified++;
        }
      }
      statuses.add(MapEntry(skill, status));
      final isGap = status == SkillEvidence.missing ||
          (partlyIsGap && status == SkillEvidence.partly);
      if (isGap && !gaps.contains(skill)) gaps.add(skill);
    }
    if (targetSkills.isNotEmpty && answered == 0) {
      throw const FormatException(
        'The evidence check answered none of the target skills.',
      );
    }
    return SkillGapCheckResult(
      statuses: statuses,
      gaps: gaps,
      unverifiedQuotes: unverified,
    );
  }

  /// The answer item of each target skill (target name -> item), from the
  /// `skills` list [raw]. The names are compared in three steps, and each
  /// answer item is used for one target at most:
  ///  1. the same name, ignoring case and extra spaces;
  ///  2. the same [SkillMatcher.identityKey] ("CI/CD" and "CI-CD"), which
  ///     keeps '+' and '#';
  ///  3. the same [SkillMatcher.normalize]d name, which drops '+', '#' and
  ///     '.', only when no other target and no other answer has that name.
  /// So with the targets "C#" and "C++" and an answer for "C#" only, "C++"
  /// gets no answer and stays a gap.
  static Map<String, Map> answersFor(List<String> targetSkills, List raw) {
    final items = [
      for (final item in raw)
        if (item is Map && (item['skill']?.toString().trim() ?? '').isNotEmpty)
          item,
    ];
    final result = <String, Map>{};
    final used = <Map>{};

    void pass(String Function(String name) keyOf, {bool uniqueOnly = false}) {
      final targetCount = <String, int>{};
      for (final skill in targetSkills) {
        final key = keyOf(skill);
        targetCount[key] = (targetCount[key] ?? 0) + 1;
      }
      final byKey = <String, List<Map>>{};
      for (final item in items) {
        (byKey[keyOf(item['skill'].toString())] ??= []).add(item);
      }
      for (final skill in targetSkills) {
        if (result.containsKey(skill)) continue;
        final key = keyOf(skill);
        if (key.isEmpty) continue;
        final found = byKey[key] ?? const <Map>[];
        if (uniqueOnly && (targetCount[key]! > 1 || found.length > 1)) {
          continue;
        }
        for (final item in found) {
          if (used.add(item)) {
            result[skill] = item;
            break;
          }
        }
      }
    }

    pass((name) => name.trim().toLowerCase().replaceAll(_spaces, ' '));
    pass(SkillMatcher.identityKey);
    pass(SkillMatcher.normalize, uniqueOnly: true);
    return result;
  }

  static final RegExp _spaces = RegExp(r'\s+');

  /// True when [quote] is in [cvText]: as it is after lower-casing and
  /// removing punctuation, or, for a quote of [minWordsForLooseQuote] words
  /// or more, when at least [looseQuoteShare] of its words appear in the
  /// CV in the same order and close together: inside a stretch of the CV
  /// at most [looseQuoteSlack] words longer than the quote. A line break of
  /// a PDF copy does not matter (the CV is read as one run of words), but
  /// words picked from different parts of the CV never make a quote. An
  /// empty quote is never found.
  static bool quoteFound(String cvText, String quote) =>
      _CvText(cvText).contains(quote);

  static SkillEvidence _statusOf(dynamic value) {
    switch (value?.toString().trim().toLowerCase()) {
      case 'shown':
        return SkillEvidence.shown;
      case 'partly':
        return SkillEvidence.partly;
      default:
        return SkillEvidence.missing;
    }
  }
}

/// A CV text prepared once for many quote checks.
class _CvText {
  _CvText(String text) : this._(SkillMatcher.normalize(text));

  _CvText._(String normalized)
      : _padded = ' $normalized ',
        _words = normalized.isEmpty ? const [] : normalized.split(' ');

  final String _padded;
  final List<String> _words;

  bool contains(String quote) {
    final key = SkillMatcher.normalize(quote);
    if (key.isEmpty) return false;
    if (_padded.contains(' $key ')) return true;
    final words = key.split(' ');
    if (words.length < SkillGapCheck.minWordsForLooseQuote) return false;
    // The fewest words that make the share (counted, so that rounding in
    // a multiplication can never ask for one word too many).
    var needed = 0;
    while (needed / words.length < SkillGapCheck.looseQuoteShare) {
      needed++;
    }
    final window = words.length + SkillGapCheck.looseQuoteSlack;
    final quoteWords = words.toSet();
    for (var start = 0; start < _words.length; start++) {
      if (!quoteWords.contains(_words[start])) continue;
      final end = start + window < _words.length
          ? start + window
          : _words.length;
      if (_inOrder(words, start, end) >= needed) return true;
    }
    return false;
  }

  /// How many of [quote]'s words appear in the CV words from [start] up to
  /// [end], in the quote's order (their longest common subsequence).
  int _inOrder(List<String> quote, int start, int end) {
    var previous = List<int>.filled(end - start + 1, 0);
    for (final word in quote) {
      final row = List<int>.filled(end - start + 1, 0);
      for (var j = 1; j <= end - start; j++) {
        row[j] = word == _words[start + j - 1]
            ? previous[j - 1] + 1
            : (row[j - 1] > previous[j] ? row[j - 1] : previous[j]);
      }
      previous = row;
    }
    return previous.last;
  }
}
