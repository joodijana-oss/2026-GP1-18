import 'package:flutter/material.dart';

import '../utils/password_validator.dart';

// Live list of password rules: red ✕ while unmet, green ✓ once met.
// Used under every "new password" field (Sign Up, Reset Password).
class PasswordRulesChecklist extends StatelessWidget {
  const PasswordRulesChecklist({super.key, required this.password});

  final String password;

  static const Color errorColor = Color(0xFFD64545);
  static const Color successColor = Color(0xFF23966F);

  @override
  Widget build(BuildContext context) {
    final rules = <(String, bool)>[
      (
        'At least ${PasswordValidator.minLength} characters',
        PasswordValidator.hasMinLength(password),
      ),
      ('An uppercase letter', PasswordValidator.hasUppercase(password)),
      ('A lowercase letter', PasswordValidator.hasLowercase(password)),
      ('A number', PasswordValidator.hasDigit(password)),
      ('A special character', PasswordValidator.hasSpecial(password)),
    ];

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, met) in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Icon(
                    met ? Icons.check_rounded : Icons.close_rounded,
                    color: met ? successColor : errorColor,
                    size: 16,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      color: met ? successColor : errorColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
