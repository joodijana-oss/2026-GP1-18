import 'package:flutter/material.dart';
import '../screens/email_action_screen.dart';
import '../screens/reset_password_screen.dart';

// ============================================================
// PASSWORD RESET + EMAIL CHANGE LINKS (Android App Links)
// Firebase's default email link:
// https://masra-184b3.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=...
// (or mode=verifyAndChangeEmail / recoverEmail for an email change)
// Flutter passes it to the app as "/__/auth/action?mode=...&oobCode=..."
// ============================================================

const String _authActionPath = '/__/auth/action';

bool _isAuthActionLink(Uri uri) => uri.path.startsWith(_authActionPath);

// The oobCode if [location] is a reset-password link, otherwise null
// (other modes such as verifyEmail are ignored).
String? resetCodeFromLink(String? location) {
  if (location == null) return null;

  final uri = Uri.tryParse(location);
  if (uri == null || !_isAuthActionLink(uri)) return null;
  if (uri.queryParameters['mode'] != 'resetPassword') return null;

  final code = uri.queryParameters['oobCode'];
  if (code == null || code.isEmpty) return null;

  return code;
}

// Email change links:
// verifyAndChangeEmail = sent to the new email to confirm the change
// recoverEmail = sent to the old email to undo the change
const Set<String> emailActionModes = {'verifyAndChangeEmail', 'recoverEmail'};

class EmailActionLink {
  const EmailActionLink({required this.mode, required this.oobCode});

  final String mode;
  final String oobCode;
}

// The mode + oobCode if [location] is an email change link, otherwise null
EmailActionLink? emailActionFromLink(String? location) {
  if (location == null) return null;

  final uri = Uri.tryParse(location);
  if (uri == null || !_isAuthActionLink(uri)) return null;

  final mode = uri.queryParameters['mode'];
  if (!emailActionModes.contains(mode)) return null;

  final code = uri.queryParameters['oobCode'];
  if (code == null || code.isEmpty) return null;

  return EmailActionLink(mode: mode!, oobCode: code);
}

// Link opened while the app is already running.
// Registered in main() before runApp, so it runs before MaterialApp's
// own handler (which would push the link as an unknown named route).
class PasswordResetLinkObserver with WidgetsBindingObserver {
  PasswordResetLinkObserver(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final uri = routeInformation.uri;

    // Not our link: let Flutter handle it as usual
    if (!_isAuthActionLink(uri)) return false;

    final code = resetCodeFromLink(uri.toString());

    if (code != null) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => ResetPasswordScreen(oobCode: code),
        ),
      );
      return true;
    }

    final emailAction = emailActionFromLink(uri.toString());

    if (emailAction != null) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => EmailActionScreen(
            mode: emailAction.mode,
            oobCode: emailAction.oobCode,
          ),
        ),
      );
    }

    // Handled (other modes are ignored on purpose)
    return true;
  }
}
