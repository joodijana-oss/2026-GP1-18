import 'dart:math';

import 'package:masra/utils/skill_matcher.dart';

/// Two crude, high-recall searches over the items' own texts. The matching
/// evaluation adds their 5 best items to every pool, so "some item teaches
/// this skill" does not depend only on what the approaches found. They are
/// evaluation code: nothing here ships, and no approach uses them.
class TextProbes {
  TextProbes._();

  /// The words of [text]: lower-cased, without punctuation, grammar words
  /// and one-letter words, a final "s" dropped.
  static List<String> wordsOf(String text) {
    final result = <String>[];
    for (final word
        in SkillMatcher.normalize(SkillMatcher.searchForm(text)).split(' ')) {
      if (word.length < 2 || _stopWords.contains(word)) continue;
      result.add(word.length >= 4 && word.endsWith('s') && !word.endsWith('ss')
          ? word.substring(0, word.length - 1)
          : word);
    }
    return result;
  }

  /// Grammar words only. They carry no subject.
  static const Set<String> _stopWords = {
    'and', 'or', 'of', 'the', 'for', 'in', 'with', 'to', 'an', 'on', 'by',
    'as', 'at', 'is', 'are', 'be', 'it', 'its', 'this', 'that', 'from',
    'you', 'your', 'will', 'can', 'how', 'what', 'into', 'using', 'use',
  };

  /// The [limit] items of [texts] (id -> text) closest to [query] by the
  /// cosine of their TF-IDF word vectors; each item keeps its 40 heaviest
  /// words.
  static List<String> bySimilarity(
    String query,
    Map<String, String> texts, {
    int limit = 5,
  }) {
    final counts = <String, Map<String, int>>{};
    final documentFrequency = <String, int>{};
    texts.forEach((id, text) {
      final count = <String, int>{};
      for (final word in wordsOf(text)) {
        count[word] = (count[word] ?? 0) + 1;
      }
      counts[id] = count;
      for (final word in count.keys) {
        documentFrequency[word] = (documentFrequency[word] ?? 0) + 1;
      }
    });
    final total = texts.length;
    // A word no item uses gets the highest weight, so a name made mostly
    // of unknown words is close to nothing.
    double idf(String word) =>
        log(1 + total / (documentFrequency[word] ?? 1 / total));

    Map<String, double> unit(Map<String, double> weights) {
      var sum = 0.0;
      for (final weight in weights.values) {
        sum += weight * weight;
      }
      if (sum <= 0) return const {};
      final length = sqrt(sum);
      return {for (final e in weights.entries) e.key: e.value / length};
    }

    final queryCount = <String, int>{};
    for (final word in wordsOf(query)) {
      queryCount[word] = (queryCount[word] ?? 0) + 1;
    }
    final queryVector = unit({
      for (final e in queryCount.entries)
        e.key: (1 + log(e.value)) * idf(e.key),
    });
    if (queryVector.isEmpty) return const [];

    final scores = <String, double>{};
    counts.forEach((id, count) {
      final weights = {
        for (final e in count.entries) e.key: (1 + log(e.value)) * idf(e.key),
      };
      final ordered = weights.keys.toList()
        ..sort((a, b) {
          final byWeight = weights[b]!.compareTo(weights[a]!);
          return byWeight != 0 ? byWeight : a.compareTo(b);
        });
      final profile =
          unit({for (final word in ordered.take(40)) word: weights[word]!});
      var score = 0.0;
      queryVector.forEach((word, weight) {
        score += weight * (profile[word] ?? 0);
      });
      if (score > 0) scores[id] = score;
    });
    return _best(scores, limit);
  }

  /// The [limit] best items of [texts] by BM25 with any word of [query].
  static List<String> byAnyWord(
    String query,
    Map<String, String> texts, {
    int limit = 5,
  }) {
    final words = wordsOf(query).toSet();
    if (words.isEmpty || texts.isEmpty) return const [];
    final tokens = {for (final e in texts.entries) e.key: wordsOf(e.value)};
    var totalLength = 0;
    for (final list in tokens.values) {
      totalLength += list.length;
    }
    final average = max(1.0, totalLength / tokens.length);
    final scores = <String, double>{};
    for (final word in words) {
      final containing =
          tokens.values.where((list) => list.contains(word)).length;
      if (containing == 0) continue;
      final idf =
          log(1 + (tokens.length - containing + 0.5) / (containing + 0.5));
      tokens.forEach((id, list) {
        final tf = list.where((w) => w == word).length;
        if (tf == 0) return;
        scores[id] = (scores[id] ?? 0) +
            idf * tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * list.length / average));
      });
    }
    return _best(scores, limit);
  }

  static List<String> _best(Map<String, double> scores, int limit) {
    final ordered = scores.keys.toList()
      ..sort((a, b) {
        final byScore = scores[b]!.compareTo(scores[a]!);
        return byScore != 0 ? byScore : a.compareTo(b);
      });
    return ordered.take(limit).toList();
  }
}
