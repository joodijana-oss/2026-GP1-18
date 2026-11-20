import 'package:flutter_test/flutter_test.dart';

import '../tools/recommender_eval/ranking_metrics.dart';

/// The evaluation metrics, checked against values worked out by hand.
void main() {
  group('precisionAt', () {
    test('counts labelled results in the first k', () {
      final grades = {'a': 2, 'c': 1, 'z': 1};
      expect(precisionAt(5, ['a', 'b', 'c', 'd', 'e', 'f'], grades), 0.4);
    });

    test('always divides by k, also for a short list', () {
      expect(precisionAt(5, ['a'], {'a': 2}), 0.2);
      expect(precisionAt(5, [], {'a': 2}), 0);
    });
  });

  group('ndcgAt', () {
    test('a worse order scores below 1', () {
      // DCG   = 1 / log2(2) + 3 / log2(3) = 1 + 1.8928 = 2.8928
      // ideal = 3 / log2(2) + 1 / log2(3) = 3 + 0.6309 = 3.6309
      expect(ndcgAt(10, ['c', 'a'], {'a': 2, 'c': 1}), closeTo(0.7967, 0.0001));
    });

    test('the best order scores 1', () {
      expect(ndcgAt(10, ['a', 'c', 'x'], {'a': 2, 'c': 1}), closeTo(1, 1e-12));
    });

    test('unlabelled results in front lower the score', () {
      // DCG = 3 / log2(3) = 1.8928, ideal = 3
      expect(ndcgAt(10, ['x', 'a'], {'a': 2}), closeTo(0.6309, 0.0001));
    });

    test('only the first k results count', () {
      expect(ndcgAt(1, ['x', 'a'], {'a': 2}), 0);
    });

    test('no relevant label gives null', () {
      expect(ndcgAt(10, ['a', 'b'], {}), isNull);
    });
  });

  group('gapCoverageAt', () {
    final teaches = {
      'a': {'power bi'},
      'b': {'ci cd', 'power bi'},
      'c': {'sql'},
    };
    const gaps = ['Power BI', 'CI/CD', 'SQL'];

    test('names are compared after normalizing', () {
      expect(
        gapCoverageAt(10, ['a', 'b'], teaches, gaps),
        closeTo(2 / 3, 1e-12),
      );
    });

    test('only the first k results count', () {
      expect(
        gapCoverageAt(1, ['a', 'b', 'c'], teaches, gaps),
        closeTo(1 / 3, 1e-12),
      );
      expect(gapCoverageAt(3, ['a', 'b', 'c'], teaches, gaps), 1);
    });

    test('no gaps gives 0', () {
      expect(gapCoverageAt(10, ['a'], teaches, []), 0);
    });
  });

  group('tiesAt', () {
    test('counts results that share a score with another one', () {
      expect(tiesAt(10, [3, 3, 2, 1, 1, 1]), 5);
      expect(tiesAt(10, [3, 2, 1]), 0);
    });

    test('only looks at the first k', () {
      expect(tiesAt(3, [3, 2, 1, 1, 1]), 0);
    });
  });

  group('firstHitRank', () {
    test('is the 1-based rank of the first match', () {
      expect(firstHitRank(['a', 'b', 'c'], {'c', 'b'}), 2);
    });

    test('is the list length + 1 when nothing matches', () {
      expect(firstHitRank(['a', 'b', 'c'], {'z'}), 4);
      expect(firstHitRank([], {'z'}), 1);
    });
  });

  group('median and mean', () {
    test('median takes the middle value', () {
      expect(median([5, 1, 3]), 3);
      expect(median([4, 1, 3, 2]), 2.5);
      expect(median([]), 0);
    });

    test('mean is the average', () {
      expect(mean([1, 2, 6]), 3);
      expect(mean([]), 0);
    });
  });
}
