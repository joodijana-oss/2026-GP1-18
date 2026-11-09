import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Asks the Masra email service (Google Apps Script, see
/// tools/welcome_email/Code.gs) to send the Masra-designed password reset
/// email. Firebase still creates the reset link; only the email is ours.
///
/// The service URL is WELCOME_EMAIL_URL in the .env file (the same script
/// sends the welcome email).
class PasswordResetEmailService {
  static const String _url = String.fromEnvironment('WELCOME_EMAIL_URL');
  static const Duration _timeout = Duration(seconds: 20);

  /// True when the service took the request. False means the caller should
  /// use Firebase's own reset email instead (service not set up, offline...).
  Future<bool> send(String email) async {
    if (_url.isEmpty) return false;

    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(_url))
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({'action': 'resetPassword', 'email': email});

      var response = await http.Response.fromStream(
        await client.send(request).timeout(_timeout),
      );

      // Apps Script runs the request, then redirects to the page that holds
      // the JSON answer.
      if (response.statusCode == 302 || response.statusCode == 303) {
        final location = response.headers['location'];
        if (location == null) return false;
        response = await client.get(Uri.parse(location)).timeout(_timeout);
      }

      return isAccepted(response.statusCode, response.body);
    } catch (e) {
      debugPrint('Masra reset email failed: $e');
      return false;
    } finally {
      client.close();
    }
  }

  /// Whether the script's answer means "handled" ({"ok": true}).
  @visibleForTesting
  static bool isAccepted(int statusCode, String body) {
    if (statusCode != 200) return false;
    try {
      final data = jsonDecode(body);
      return data is Map && data['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}
