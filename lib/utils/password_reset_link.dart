import 'package:flutter/material.dart';
import '../screens/reset_password_screen.dart';

// ============================================================
// PASSWORD RESET LINK (Android App Links)
// Firebase's default email link:
// https://masra-184b3.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=...
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
    }

    // Handled (other modes are ignored on purpose)
    return true;
  }
}
