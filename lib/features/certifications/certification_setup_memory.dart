import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/content_based_recommender.dart';

/// The choices a user last ran the Certification Recommender with, and the
/// analysis and career goal they were for.
class SavedCertificationRun {
  /// Close my skill gaps or Strengthen my skills.
  final CertificationGoal goal;

  /// 5, 10, or null for All.
  final int? limit;

  /// Which analysis the choices were run for. Null when it was not known.
  final String? analysisKey;

  /// The career goal the choices were run for. Null when it was not known.
  final String? careerGoalId;

  const SavedCertificationRun({
    required this.goal,
    required this.limit,
    this.analysisKey,
    this.careerGoalId,
  });
}

/// Remembers the Certification Recommender choices on this device,
/// separately for each signed-in user.
///
/// The setup page shows the first time, after a new analysis, or when the
/// career goal changed. Otherwise the results open straight away with the
/// choices saved here. Nothing is saved in Firestore.
class CertificationSetupMemory {
  const CertificationSetupMemory();

  /// Top 5, Top 10, All (null).
  static const List<int?> limits = [5, 10, null];
  static const int defaultLimit = 5;

  // Keys end with the user id so two accounts on one phone never share them.
  static String goalKey(String uid) => 'cert_recommender_goal_$uid';

  /// 0 means All.
  static String limitKey(String uid) => 'cert_recommender_limit_$uid';
  static String analysisKeyFor(String uid) => 'cert_recommender_analysis_$uid';
  static String careerGoalKey(String uid) =>
      'cert_recommender_career_goal_$uid';

  // ---------------------------------------------------------
  // WHICH ANALYSIS AND CAREER GOAL
  // ---------------------------------------------------------

  /// Which analysis this is: the time it was saved ("seconds.nanoseconds").
  /// Every new analysis gets a new time. Null when the time is not readable
  /// yet (for example, still waiting for the server while offline).
  static String? analysisKeyOf(Map<String, dynamic> analysis) {
    final time = analysis['analyzedAt'];
    return time is Timestamp ? '${time.seconds}.${time.nanoseconds}' : null;
  }

  /// The career goal id of the analysis, trimmed; null when empty.
  static String? careerGoalIdOf(Map<String, dynamic> analysis) {
    final id = analysis['careerGoalId']?.toString().trim() ?? '';
    return id.isEmpty ? null : id;
  }

  /// True when the setup page should show instead of the results.
  ///
  /// When anything is unknown the setup shows, so the user is never sent to
  /// results made with choices for an older analysis.
  static bool shouldShowSetup({
    required SavedCertificationRun? saved,
    required String? analysisKey,
    required String? careerGoalId,
  }) {
    // First time this user opens it on this device (old installs too).
    if (saved == null) return true;
    // The last run did not record which analysis or career goal it was for.
    if (saved.analysisKey == null || saved.careerGoalId == null) return true;
    // Cannot tell which analysis this is.
    if (analysisKey == null || careerGoalId == null) return true;
    // A new analysis, or the career goal changed.
    return saved.analysisKey != analysisKey ||
        saved.careerGoalId != careerGoalId;
  }

  // ---------------------------------------------------------
  // LABELS
  // ---------------------------------------------------------

  /// Labels shared with the setup page so the "Your choices" row always
  /// matches the option titles.
  static String goalTitle(CertificationGoal goal) {
    switch (goal) {
      case CertificationGoal.closeGaps:
        return 'Close my skill gaps';
      case CertificationGoal.strengthenSkills:
        return 'Strengthen my skills';
    }
  }

  static String limitLabel(int? limit) => limit == null ? 'All' : 'Top $limit';

  /// For example "Close my skill gaps · Top 5".
  ///
  /// The space before the dot and the space in "Top 5" are non-breaking
  /// spaces, so on a narrow phone a line never starts with the dot and the
  /// number never sits alone on the next line.
  static String choicesSummary(CertificationGoal goal, int? limit) {
    final limitText = limitLabel(limit).replaceAll(' ', ' ');
    return '${goalTitle(goal)} · $limitText';
  }

  // ---------------------------------------------------------
  // LOAD AND SAVE
  // ---------------------------------------------------------

  /// Null when nothing was saved for this user on this device.
  Future<SavedCertificationRun?> load(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final goalName = prefs.getString(goalKey(uid));
      if (goalName == null) return null;

      final goal = CertificationGoal.values.firstWhere(
        (g) => g.name == goalName,
        orElse: () => CertificationGoal.closeGaps,
      );

      // 0 means All; a missing or unknown value falls back to Top 5.
      final stored = prefs.getInt(limitKey(uid));
      int? limit;
      if (stored == null) {
        limit = defaultLimit;
      } else if (stored == 0) {
        limit = null;
      } else {
        limit = limits.contains(stored) ? stored : defaultLimit;
      }

      return SavedCertificationRun(
        goal: goal,
        limit: limit,
        analysisKey: _cleanString(prefs.getString(analysisKeyFor(uid))),
        careerGoalId: _cleanString(prefs.getString(careerGoalKey(uid))),
      );
    } catch (_) {
      // Nothing readable: behave as the first time.
      return null;
    }
  }

  /// Saves the choices and the analysis and career goal they were run for.
  ///
  /// The analysis key is removed first and written last, so a save that
  /// stops halfway can only make the setup show next time, never open the
  /// results with old choices.
  Future<void> saveRun(
    String uid, {
    required CertificationGoal goal,
    required int? limit,
    required String? analysisKey,
    required String? careerGoalId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(analysisKeyFor(uid));
      await prefs.setString(goalKey(uid), goal.name);
      await prefs.setInt(limitKey(uid), limit ?? 0);
      if (careerGoalId == null) {
        await prefs.remove(careerGoalKey(uid));
      } else {
        await prefs.setString(careerGoalKey(uid), careerGoalId);
      }
      if (analysisKey != null) {
        await prefs.setString(analysisKeyFor(uid), analysisKey);
      }
    } catch (_) {
      // Only a convenience: the choices still work for this visit.
    }
  }

  static String? _cleanString(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
