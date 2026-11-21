import '../utils/skill_matcher.dart';

/// Turns the market skill names of an analysis into single-skill names.
///
/// The AI analysis reads job postings and lists the skills they ask for. A
/// posting often packs several things into one line, and the list used to
/// repeat that: one entry holding four certifications, or a skill followed
/// by three vendors in parentheses. Such an entry can never be matched to a
/// course, and when it becomes a skill gap the user cannot work on it as
/// one thing. The request now asks for one skill per entry, and this class
/// cleans whatever still arrives bundled. It only uses the shape of a name
/// (parentheses, separators, word counts) and the names the app already
/// knows at run time. It holds no list of skill names of its own.
///
/// Rules, in this order:
///  1. Parentheses. "Head (A, B, C)" and "Head such as A, B" are handled by
///     the head:
///      - a head that is a plural category of distinct things
///        ([categoryWords]: "... Certifications", "... Tools") is replaced by
///        the items it lists, each kept when it has at most
///        [maxItemWords] words. A category alone is still a bundle, so it is
///        never kept in place of its items;
///      - any other head is kept and the parentheses are dropped.
///     A category with no items ("Cloud Platforms") is dropped for the
///     same reason, unless it is a name the app knows.
///  2. Lists. "A, B", "A; B", "A or B" and "A/B" are split when every part
///     has at most [maxPartWords] words. "A and B" is split only when both
///     sides are names the app knows, because "and" is also part of many
///     single skill names. A slash is not split in a name that also holds
///     "and" ("Spectrum Planning and RF/Microwave"): splitting there would
///     cut one side of the "and" in two.
///  3. Known names stay whole. A name the app knows as one skill (a synonym
///     table name, an opportunity skill tag or a certification skill, asked
///     through `isKnown`) is never split. A slash name also stays whole
///     when one side has two characters or fewer ("CI/CD").
///  4. Duplicates are removed (compared with [SkillMatcher.identityKey], so
///     "C#" and "C++" are two skills), the order is kept and the list is
///     cut to [limit].
///
/// The order matters to the rest of the app: the market skills are listed
/// from the most to the least requested, and the parts of a split entry
/// take the place of that entry.
class MarketSkillNames {
  MarketSkillNames._();

  /// The most market skills an analysis keeps.
  static const int limit = 12;

  /// A list item longer than this is a description, not a skill name.
  static const int maxItemWords = 4;

  /// A list is split only when every part is at most this long.
  static const int maxPartWords = 3;

  /// Plural words for a set of distinct things. A head that ends in one of
  /// them names a category, not one skill.
  static const Set<String> categoryWords = {
    'certifications', 'certificates', 'credentials', 'tools', 'platforms',
    'vendors', 'languages', 'frameworks', 'technologies',
  };

  /// The single-skill names of [names] (see the class comment).
  /// [isKnown] says whether a name is one skill the app knows; build it
  /// with [knownFrom].
  static List<String> single(
    List<String> names, {
    required bool Function(String name) isKnown,
    int limit = MarketSkillNames.limit,
  }) {
    final result = <String>[];
    final seen = <String>{};
    for (final name in names) {
      for (final part in _split(name.trim(), isKnown)) {
        final key = SkillMatcher.identityKey(part);
        if (key.isEmpty || !seen.add(key)) continue;
        result.add(part);
        if (result.length >= limit) return result;
      }
    }
    return result;
  }

  /// A test for "the app knows this name as one skill": a name of the
  /// synonym table, or one of [catalogueNames] (the opportunity skill tags
  /// and certification skills, read from the data at run time).
  static bool Function(String name) knownFrom(Iterable<String> catalogueNames) {
    final keys = {
      for (final name in catalogueNames) SkillMatcher.normalize(name),
    }..remove('');
    return (name) =>
        SkillMatcher.isKnownName(name) ||
        keys.contains(SkillMatcher.normalize(name));
  }

  /// True when [name] still looks like several things in one entry:
  /// parentheses that hold a list, a comma or "or" list, a slash between
  /// two parts of three characters or more that is not one known name, or
  /// a category ("Security Certifications") that is not a known name.
  /// The evaluation tool reports it next to the reviewers' own judgement.
  static bool looksBundled(
    String name, {
    required bool Function(String name) isKnown,
  }) {
    final text = name.trim();
    if (text.isNotEmpty && !isKnown(text) && _isCategory(text)) return true;
    final inside = _parentheses.firstMatch(text)?.group(2) ?? '';
    if (inside.contains(',') ||
        inside.contains('/') ||
        _or.hasMatch(' $inside ')) {
      return true;
    }
    if (text.contains(', ') || _or.hasMatch(text)) return true;
    if (text.contains('/') && !isKnown(text)) {
      final parts = text.split('/').map((p) => p.trim()).toList();
      if (parts.length >= 2 && parts.every((p) => p.length >= 3)) return true;
    }
    return false;
  }

  // ---------------------------------------------------------
  // INTERNALS
  // ---------------------------------------------------------

  static final RegExp _parentheses = RegExp(r'^([^()]*)\(([^()]*)\)(.*)$');
  static final RegExp _examplesTail = RegExp(
    r'^(.*?)[\s,:]+(?:such as|including|e\.g\.|eg\.?|for example|like)[\s:,]+(.+)$',
    caseSensitive: false,
  );
  static final RegExp _examplesLead = RegExp(
    r'^(?:such as|including|e\.g\.|eg\.?|i\.e\.|for example|like)[\s:,]+',
    caseSensitive: false,
  );
  static final RegExp _etc = RegExp(
    r'[\s,]*(?:\betc\.?|\band more|\band others|\.\.\.)\s*$',
    caseSensitive: false,
  );
  static final RegExp _listSeparator =
      RegExp(r'\s*[,;]\s*|\s+or\s+', caseSensitive: false);
  static final RegExp _or = RegExp(r'\s+or\s+', caseSensitive: false);
  static final RegExp _and = RegExp(r'\s+(?:and|&)\s+', caseSensitive: false);
  static final RegExp _leadingAnd =
      RegExp(r'^(?:and|or|&)\s+', caseSensitive: false);

  static int _words(String text) =>
      text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  static bool _isCategory(String head) {
    final words = SkillMatcher.normalize(head).split(' ');
    return words.isNotEmpty && categoryWords.contains(words.last);
  }

  /// The parts of a list text ("A, B or C", "A/B"), trimmed, without the
  /// words that only introduce or end a list.
  static List<String> _items(String text) {
    final cleaned =
        text.replaceFirst(_examplesLead, '').replaceFirst(_etc, '').trim();
    return [
      for (final part in cleaned.split(RegExp(r'\s*[,;/]\s*|\s+or\s+|\s+(?:and|&)\s+')))
        if (part.replaceFirst(_leadingAnd, '').trim().isNotEmpty)
          part.replaceFirst(_leadingAnd, '').trim(),
    ];
  }

  static List<String> _split(String name, bool Function(String) isKnown) {
    if (name.isEmpty) return const [];
    if (isKnown(name)) return [name];

    // Rule 1: "Head (items)" and "Head such as items".
    String? head;
    String? inside;
    final bracket = _parentheses.firstMatch(name);
    if (bracket != null) {
      head = '${bracket.group(1)!.trim()} ${bracket.group(3)!.trim()}'.trim();
      inside = bracket.group(2)!.trim();
    } else {
      final examples = _examplesTail.firstMatch(name);
      if (examples != null) {
        head = examples.group(1)!.trim();
        inside = examples.group(2)!.trim();
      }
    }
    if (head != null && inside != null) {
      if (head.isEmpty) return _split(inside, isKnown);
      if (_isCategory(head)) {
        return [
          for (final item in _items(inside))
            if (_words(item) <= maxItemWords) item,
        ];
      }
      return _split(head, isKnown);
    }

    // Rule 2: comma, semicolon and "or" lists.
    final listed = [
      for (final part in name.replaceFirst(_etc, '').split(_listSeparator))
        if (part.replaceFirst(_leadingAnd, '').trim().isNotEmpty)
          part.replaceFirst(_leadingAnd, '').trim(),
    ];
    if (listed.length >= 2 && listed.every((p) => _words(p) <= maxPartWords)) {
      return [for (final part in listed) ..._split(part, isKnown)];
    }

    // Rule 1: a category with no items stands for several things. The
    // parts of a list are judged one by one above.
    if (_isCategory(name)) return const [];

    // Rules 2 and 3: slash names, when no "and" joins the name.
    if (name.contains('/') && !_and.hasMatch(name)) {
      final sides = name.split('/').map((p) => p.trim()).toList();
      final shortSide = sides.any((p) => p.length <= 2);
      if (!shortSide &&
          sides.every((p) => p.isNotEmpty && _words(p) <= maxPartWords)) {
        return [for (final side in sides) ..._split(side, isKnown)];
      }
      return [name];
    }

    // Rule 2: "A and B" only when both sides are known names.
    final sides = name.split(_and).map((p) => p.trim()).toList();
    if (sides.length == 2 && sides.every((p) => p.isNotEmpty && isKnown(p))) {
      return sides;
    }
    return [name];
  }
}
