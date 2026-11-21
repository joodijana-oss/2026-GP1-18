/// The support test of the meaning links, written once for both catalogues
/// (OpportunityIndex.supportFor and CertificationTexts.supportFor). A link
/// may bring an item in, but the item's own text must show the gap before
/// the card names the gap as its reason. Each catalogue keeps its own words
/// and texts; the rule of what counts as support is here, so the reason
/// lines follow the same rule on both screens.
class LinkSupport {
  const LinkSupport._();

  /// The items that support a gap, among [size] items.
  ///
  /// An item supports the gap when its own text contains
  ///  - the gap's whole name as a phrase ([gapTokens], a name of two words
  ///    or more), or
  ///  - a distinctive word of the name, or
  ///  - one of [terms], the wording stored with the link: a term of two
  ///    words or more as a phrase, a one-word term only when it is
  ///    distinctive.
  /// A word is distinctive when it is a support word ([isSupportWord]) and
  /// at most the share [theta] of the items contain it. The share is
  /// counted from the items given, at run time: a common word exceeds it by
  /// itself, so no word list is needed.
  ///
  /// [itemsWithWord] gives the items whose own text contains a word (null
  /// or empty when none does), [itemsWithPhrase] the items whose own text
  /// contains the words of a phrase next to each other, in order. Both
  /// take tokens of the same tokenizer as [gapTokens] and [terms].
  static Set<int> supported({
    required List<String> gapTokens,
    required List<List<String>> terms,
    required double theta,
    required int size,
    required Set<int>? Function(String word) itemsWithWord,
    required Iterable<int> Function(List<String> phrase) itemsWithPhrase,
  }) {
    final result = <int>{};
    void addWord(String word) {
      if (!isSupportWord(word)) return;
      final items = itemsWithWord(word);
      if (items == null || items.isEmpty || items.length > theta * size) {
        return;
      }
      result.addAll(items);
    }

    if (gapTokens.length >= 2) result.addAll(itemsWithPhrase(gapTokens));
    gapTokens.forEach(addWord);
    for (final term in terms) {
      if (term.length >= 2) {
        result.addAll(itemsWithPhrase(term));
      } else if (term.length == 1) {
        addWord(term.single);
      }
    }
    return result;
  }

  /// A word that can support a gap on its own: two characters or more and
  /// at least one letter. A number in a gap name ("10" in "Top 10") is
  /// rare in a catalogue, but it says nothing about the subject ("10
  /// weeks").
  static bool isSupportWord(String word) {
    if (word.length < 2) return false;
    for (var i = 0; i < word.length; i++) {
      final c = word.codeUnitAt(i);
      if ((c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A)) return true;
    }
    return false;
  }
}
