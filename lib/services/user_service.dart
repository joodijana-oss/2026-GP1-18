import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
 
class UserService {
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
    });
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
    });
  }
 
  // ---------------------------------------------------------
  // USER DATA
  // ---------------------------------------------------------
 
  Future<Map<String, dynamic>?> getUser() async {
    final snapshot = await _userDoc.get();
    return snapshot.data();
  }
 
  Future<void> updateUser(
    Map<String, dynamic> data,
  ) async {
    await _userDoc.update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
 
    await batch.commit();
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
    });
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
 
    return currentCvUploadedAt ==
        analyzedCvUploadedAt;
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
      'cvUploadedAt': cvUploadedAt,
      'reviewedAt': FieldValue.serverTimestamp(),
    });
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
 