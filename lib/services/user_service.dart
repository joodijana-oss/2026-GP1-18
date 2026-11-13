import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../constants/profile_options.dart';
 
class UserService {
  // Firestore writes never fail while offline: they wait for the server.
  // Without a limit the screen would show a spinner forever, so every
  // write gives up after this long and the caller shows its error message.
  static const Duration _writeTimeout = Duration(seconds: 15);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
 
  String get _uid {
    final user = _auth.currentUser;
 
    if (user == null) {
      throw Exception('No logged-in user');
    }
 
    return user.uid;
  }
 
  DocumentReference<Map<String, dynamic>> get _userDoc =>
      _db.collection('users').doc(_uid);
 
  DocumentReference<Map<String, dynamic>> get _cvDoc =>
      _userDoc.collection('private').doc('cv');
 
  // Profile photo, kept as a small image inside Firestore (the free plan
  // has no Cloud Storage). Owner-only, like the CV text.
  DocumentReference<Map<String, dynamic>> get _photoDoc =>
      _userDoc.collection('private').doc('photo');

  DocumentReference<Map<String, dynamic>> get _latestAnalysisDoc =>
      _userDoc.collection('analysis').doc('latest');
 
  DocumentReference<Map<String, dynamic>> get _latestCvReviewDoc =>
      _userDoc.collection('cvImprovement').doc('latest');
 
  // ---------------------------------------------------------
  // ACCOUNT
  // ---------------------------------------------------------
 
  Future<void> createUser({
    required String fullName,
    required String email,
  }) async {
    await _userDoc.set({
      'fullName': fullName,
      'email': email,
      'profileCompleted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(_writeTimeout);
  }
 
  // ---------------------------------------------------------
  // PROFILE SETUP
  // ---------------------------------------------------------
 
  Future<void> saveProfile({
    required String university,
    required String degree,
    required String major,
    required String graduationStatus,
    required int graduationYear,
    required String careerGoalId,
    required String experienceLevel,
  }) async {
    await _userDoc.update({
      'university': university,
      'degree': degree,
      'major': major,
      'graduationStatus': graduationStatus,
      'graduationYear': graduationYear,
      'careerGoalId': careerGoalId,
      'experienceLevel': experienceLevel,
      'profileCompleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(_writeTimeout);
  }
 
  // ---------------------------------------------------------
  // USER DATA
  // ---------------------------------------------------------
 
  Future<Map<String, dynamic>?> getUser() async {
    final snapshot = await _userDoc.get();
    final data = snapshot.data();
    if (data == null) return null;

    // A student whose graduation date has passed becomes a graduate
    // automatically (see ProfileOptions.effectiveGraduationStatus).
    final status = ProfileOptions.effectiveGraduationStatus(
      data['graduationStatus']?.toString(),
      year: data['graduationYear'],
      month: data['graduationMonth'],
    );

    if (status != null && status != data['graduationStatus']) {
      data['graduationStatus'] = status;
      try {
        await _userDoc.update({
          'graduationStatus': status,
          'updatedAt': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 4));
      } catch (_) {
        // Offline or not allowed: still show the right status this session.
      }
    }

    return data;
  }
 
  Future<void> updateUser(
    Map<String, dynamic> data,
  ) async {
    await _userDoc.update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(_writeTimeout);
  }
 
  // ---------------------------------------------------------
  // PROFILE PHOTO (optional)
  // ---------------------------------------------------------

  // Firestore documents are limited to 1 MB; the app shrinks photos to
  // far below this before saving.
  static const int maxPhotoBytes = 400 * 1024;

  Future<Uint8List?> getProfilePhoto() async {
    final snapshot = await _photoDoc.get();
    final value = snapshot.data()?['bytes'];
    return value is Blob ? value.bytes : null;
  }

  Future<void> saveProfilePhoto(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxPhotoBytes) {
      throw ArgumentError('Photo is empty or too large.');
    }
    await _photoDoc.set({
      'bytes': Blob(bytes),
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(_writeTimeout);
  }

  Future<void> deleteProfilePhoto() async {
    await _photoDoc.delete().timeout(_writeTimeout);
  }

  // ---------------------------------------------------------
  // CV
  // ---------------------------------------------------------
 
  Future<void> saveCv({
    required String fileName,
    required String text,
  }) async {
    final batch = _db.batch();
 
    batch.update(
      _userDoc,
      {
        'cv': {
          'fileName': fileName,
          'uploadedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
 
    batch.set(
      _cvDoc,
      {
        'text': text,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
 
    await batch.commit().timeout(_writeTimeout);
  }
 
  Future<String?> getCvText() async {
    final snapshot = await _cvDoc.get();
 
    return snapshot.data()?['text'] as String?;
  }
 
  // ---------------------------------------------------------
  // CAREER ANALYSIS
  // ---------------------------------------------------------
 
  Future<Map<String, dynamic>?> getLatestAnalysis() async {
    final snapshot = await _latestAnalysisDoc.get();
 
    return snapshot.data();
  }
 
  Future<void> saveLatestAnalysis(
    Map<String, dynamic> analysis,
  ) async {
    final userSnapshot = await _userDoc.get();
    final userData = userSnapshot.data();
 
    final cvData = userData?['cv'];
 
    Timestamp? cvUploadedAt;
 
    if (cvData is Map &&
        cvData['uploadedAt'] is Timestamp) {
      cvUploadedAt =
          cvData['uploadedAt'] as Timestamp;
    }
 
    await _latestAnalysisDoc.set({
      ...analysis,
 
      // نربط هذا التحليل بالـCV الحالي
      'cvUploadedAt': cvUploadedAt,
 
      // وقت تنفيذ التحليل
      'analyzedAt':
          FieldValue.serverTimestamp(),
 
      'updatedAt':
          FieldValue.serverTimestamp(),
    }).timeout(_writeTimeout);
  }
 
  // ---------------------------------------------------------
  // CHECK IF SAVED ANALYSIS BELONGS TO CURRENT CV
  // ---------------------------------------------------------
 
  Future<bool> hasValidLatestAnalysis() async {
    final userSnapshot =
        await _userDoc.get();
 
    final analysisSnapshot =
        await _latestAnalysisDoc.get();
 
    final userData = userSnapshot.data();
    final analysisData =
        analysisSnapshot.data();
 
    if (userData == null ||
        analysisData == null) {
      return false;
    }
 
    final cvData = userData['cv'];
 
    if (cvData is! Map) {
      return false;
    }
 
    final currentCvUploadedAt =
        cvData['uploadedAt'];
 
    final analyzedCvUploadedAt =
        analysisData['cvUploadedAt'];
 
    if (currentCvUploadedAt is! Timestamp ||
        analyzedCvUploadedAt
            is! Timestamp) {
      return false;
    }
 
    if (currentCvUploadedAt != analyzedCvUploadedAt) {
      return false;
    }

    // The analysis was made for one career goal. If the user changed the
    // goal in the profile, this saved analysis belongs to the old goal.
    return _sameCareerGoal(
      userData['careerGoalId'],
      analysisData['careerGoalId'],
    );
  }

  /// True when both career goal ids are filled and equal.
  bool _sameCareerGoal(dynamic current, dynamic saved) {
    final a = current?.toString().trim() ?? '';
    final b = saved?.toString().trim() ?? '';
    return a.isNotEmpty && a == b;
  }
 
  // ---------------------------------------------------------
  // GET ANALYSIS ONLY IF IT BELONGS TO CURRENT CV
  // ---------------------------------------------------------
 
  Future<Map<String, dynamic>?>
      getValidLatestAnalysis() async {
    final isValid =
        await hasValidLatestAnalysis();
 
    if (!isValid) {
      return null;
    }
 
    return getLatestAnalysis();
  }
 
  // ---------------------------------------------------------
  // PROFILE DATA FROM LATEST ANALYSIS
  // ---------------------------------------------------------
 
  Future<Map<String, dynamic>?>
      getProfileAnalysisData() async {
    final analysis =
        await getLatestAnalysis();
 
    if (analysis == null) {
      return null;
    }
 
    return {
      'currentSkills':
          analysis['currentSkills'] ?? [],
      'education':
          analysis['education'] ?? [],
      'certifications':
          analysis['certifications'] ?? [],
      'projects':
          analysis['projects'] ?? [],
      'experience':
          analysis['experience'] ?? [],
      'strengths':
          analysis['strengths'] ?? [],
      'skillGaps':
          analysis['skillGaps'] ?? [],
      'careerGoalId':
          analysis['careerGoalId'],
      'careerGoalName':
          analysis['careerGoalName'],
    };
  }
 
  // ---------------------------------------------------------
  // CV IMPROVEMENT (latest review, same idea as the analysis)
  // ---------------------------------------------------------
 
  // Saves the latest CV review and links it to the current CV
  Future<void> saveLatestCvReview(
    Map<String, List<Map<String, dynamic>>> areas,
  ) async {
    final userSnapshot = await _userDoc.get();
    final userData = userSnapshot.data();
 
    final cvData = userData?['cv'];
 
    Timestamp? cvUploadedAt;
 
    if (cvData is Map && cvData['uploadedAt'] is Timestamp) {
      cvUploadedAt = cvData['uploadedAt'] as Timestamp;
    }
 
    await _latestCvReviewDoc.set({
      'areas': areas,
      // The review uses the career goal name, so it belongs to this goal.
      'careerGoalId': userData?['careerGoalId'],
      'cvUploadedAt': cvUploadedAt,
      'reviewedAt': FieldValue.serverTimestamp(),
    }).timeout(_writeTimeout);
  }
 
  // Returns the saved review only if it belongs to the current CV.
  // If the user replaced the CV in the profile, it returns null.
  Future<Map<String, List<Map<String, dynamic>>>?>
      getValidLatestCvReview() async {
    final userSnapshot = await _userDoc.get();
    final reviewSnapshot = await _latestCvReviewDoc.get();
 
    final userData = userSnapshot.data();
    final reviewData = reviewSnapshot.data();
 
    if (userData == null || reviewData == null) {
      return null;
    }
 
    final cvData = userData['cv'];
 
    if (cvData is! Map) {
      return null;
    }
 
    final currentCvUploadedAt = cvData['uploadedAt'];
    final reviewedCvUploadedAt = reviewData['cvUploadedAt'];
 
    if (currentCvUploadedAt is! Timestamp ||
        reviewedCvUploadedAt is! Timestamp ||
        currentCvUploadedAt != reviewedCvUploadedAt) {
      return null;
    }

    // A review saved for another career goal (or saved before the goal was
    // stored with it) is not shown; the user reviews the CV again.
    if (!_sameCareerGoal(
      userData['careerGoalId'],
      reviewData['careerGoalId'],
    )) {
      return null;
    }
 
    final rawAreas = reviewData['areas'];
 
    if (rawAreas is! Map) {
      return null;
    }
 
    final areas = <String, List<Map<String, dynamic>>>{};
 
    rawAreas.forEach((key, value) {
      final items = <Map<String, dynamic>>[];
 
      if (value is List) {
        for (final item in value) {
          if (item is Map) {
            items.add(Map<String, dynamic>.from(item));
          }
        }
      }
 
      areas[key.toString()] = items;
    });
 
    return areas;
  }
}
 