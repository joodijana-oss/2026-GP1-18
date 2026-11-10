import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Saves the certification matches inside the user's latest analysis
/// document: users/{uid}/analysis/latest -> field `certificationMatches`.
///
/// Why there:
///  - The analysis document is replaced as a whole (`set`) every time a new
///    AI Career Analysis is saved, so the matches disappear automatically
///    when the user analyzes again (new CV or new career goal).
///  - When the CV is replaced the analysis stops being valid
///    (`getValidLatestAnalysis` returns null), so the matches are not shown.
///  - The existing Firestore rule for `analysis/latest` already lets the
///    owner write it, so no new rule is needed.
class CertificationMatchesStore {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CertificationMatchesStore({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// Saves [matches] (from `CertificationRecommendations.toMap`).
  Future<void> save(Map<String, dynamic> matches) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('analysis')
        .doc('latest')
        .update({
      'certificationMatches': {
        ...matches,
        'generatedAt': FieldValue.serverTimestamp(),
      },
    });
  }
}
