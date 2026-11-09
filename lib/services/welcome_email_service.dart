import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Asks the Masra welcome-email service (Google Apps Script, see
/// tools/welcome_email/Code.gs) to email the user who just signed up.
///
/// The service URL comes from WELCOME_EMAIL_URL in the .env file. If it is
/// not set, or the request fails, sign-up continues normally.
class WelcomeEmailService {
  static const String _url = String.fromEnvironment('WELCOME_EMAIL_URL');

  Future<void> send({required String fullName}) async {
    if (_url.isEmpty) return;

    try {
      // The script uses this token to confirm who the new user is, so it
      // only ever emails the address of the account that was just created.
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) return;

      final response = await http
          .post(
            Uri.parse(_url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'idToken': idToken, 'name': fullName}),
          )
          .timeout(const Duration(seconds: 15));

      // Apps Script runs the request and then answers with a redirect (302)
      // to the result page, so both 200 and 302 mean it was received.
      if (response.statusCode != 200 && response.statusCode != 302) {
        debugPrint('Welcome email: unexpected status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Welcome email failed: $e');
    }
  }
}
