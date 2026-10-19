// ============================================================
// SHARED FORM VALIDATORS
// Same rules and messages on every form (Sign Up, Log In,
// Forgot / Reset Password, Profile edit sheets).
// Each returns the error message, or null when the value is valid.
// ============================================================

export 'password_validator.dart';

class Validators {
  Validators._();

  static const String emailHint = 'name@example.com';

  static final RegExp _emailRegex = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );

  static String? required(String? value, String message) {
    if (value == null || value.trim().isEmpty) return message;
    return null;
  }

  static String? fullName(String? value) =>
      required(value, 'Full name is required.');

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email address is required.';
    }
    if (!_emailRegex.hasMatch(value.trim())) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  // Any password that only needs to be filled in (Log In, re-auth).
  // Not trimmed: a password of spaces is still a value.
  static String? enteredPassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required.';
    return null;
  }

  static String? confirmPassword(
    String? value,
    String password, {
    String requiredMessage = 'Please confirm your password.',
  }) {
    if (value == null || value.isEmpty) return requiredMessage;
    if (value != password) return "Passwords don't match.";
    return null;
  }
}
