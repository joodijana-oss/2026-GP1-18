// App-wide settings.
class AppConfig {
  // The single admin account (created manually in Firebase Console).
  // Must be the same email written in firestore.rules -> isAdmin().
  static const String adminEmail = 'REPLACE_WITH_ADMIN_EMAIL';

  static bool isAdminEmail(String? email) {
    if (email == null) return false;
    return email.trim().toLowerCase() == adminEmail.toLowerCase();
  }
}
