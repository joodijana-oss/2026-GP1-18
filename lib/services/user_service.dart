import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // الـ UID حق اليوزر المسجل دخول حالياً
  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No logged-in user');
    return user.uid;
  }

  // وثيقة اليوزر: users/{uid}
  DocumentReference<Map<String, dynamic>> get _userDoc =>
      _db.collection('users').doc(_uid);

  // 1) تُستدعى مباشرة بعد Sign Up
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

  // 2) تُستدعى من شاشة Profile Setup
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

  // 3) قراءة بيانات اليوزر (لصفحة البروفايل وغيرها)
  Future<Map<String, dynamic>?> getUser() async {
    final snapshot = await _userDoc.get();
    return snapshot.data();
  }

  // 4) تحديث حقول معينة (لصفحة Edit Profile)
  Future<void> updateUser(Map<String, dynamic> data) async {
    await _userDoc.update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}