// ============================================================
// PASSWORD VALIDATOR
// Shared by Sign Up and Reset Password so the rules stay identical.
// ============================================================

class PasswordValidator {
  PasswordValidator._();

  static final RegExp _uppercase = RegExp(r'[A-Z]');
  static final RegExp _lowercase = RegExp(r'[a-z]');
  static final RegExp _digit = RegExp(r'[0-9]');
  static final RegExp _special = RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=]');

  // [requiredMessage] is shown when the field is empty
  // (Sign Up: "Password is required.", Reset: "New password is required.")
  static String? validate(
    String? value, {
    String requiredMessage = 'Password is required.',
  }) {
    if (value == null || value.isEmpty) {
      return requiredMessage;
    }

    // Length message first, then every other unmet rule under it
    final lines = <String>[];

    if (value.length < 8) {
      lines.add('Password must contain at least 8 characters.');
    }

    // نجمع كل الشروط الناقصة ونعرضها مع بعض، كل شرط في سطر
    final missing = <String>[];

    if (!_uppercase.hasMatch(value)) {
      missing.add('an uppercase letter');
    }

    if (!_lowercase.hasMatch(value)) {
      missing.add('a lowercase letter');
    }

    if (!_digit.hasMatch(value)) {
      missing.add('a number');
    }

    if (!_special.hasMatch(value)) {
      missing.add('a special character');
    }

    if (missing.isNotEmpty) {
      lines.add(
        'Password must contain:\n${missing.map((rule) => '• $rule').join('\n')}',
      );
    }

    return lines.isEmpty ? null : lines.join('\n');
  }
}
