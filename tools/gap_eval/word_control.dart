import 'package:masra/models/gap_link.dart';
import 'package:masra/utils/skill_matcher.dart';

/// The word-only control of the matching evaluation (never shipped).
///
/// It answers one question honestly: does an approach that claims to match
/// by meaning beat a cheap word rule on names nobody looked at? The rule
/// uses only the synonym table that already exists:
///
///   For a gap, take the longest run of consecutive words of its name that
///   is a name the table knows (a group name or one of its synonyms). The
///   gap is linked to the group of that run. Ties go to the leftmost run.
///
/// "Kubernetes Cluster Operations" contains the table name "Kubernetes",
/// so it is linked to that group. The table itself only maps whole names,
/// which is why such a gap finds nothing today.
///
/// A specific product gets no link, as in every approach. The recommenders
/// then use the link like any stored link, and only where the gap is a
/// hole.
class WordControl {
  WordControl._();

  /// normalized group name -> the name as written in the table.
  static final Map<String, String> _groupNames = {
    for (final name in SkillMatcher.conceptNames)
      SkillMatcher.normalize(name): name,
  };

  /// The link of [gap], or null when no run of its words is a table name.
  static GapLink? linkFor(String gap) {
    if (SkillMatcher.isSpecific(gap)) return null;
    final words = SkillMatcher.normalize(gap)
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toList();
    for (var length = words.length; length >= 1; length--) {
      for (var start = 0; start + length <= words.length; start++) {
        final run = words.sublist(start, start + length).join(' ');
        if (!SkillMatcher.isKnownName(run)) continue;
        final group = _groupNames[SkillMatcher.canonical(run)];
        if (group != null) return GapLink(gap: gap, concepts: [group]);
      }
    }
    return null;
  }
}
