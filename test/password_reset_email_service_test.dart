import 'package:flutter_test/flutter_test.dart';
import 'package:masra/services/password_reset_email_service.dart';

void main() {
  test('only {"ok": true} with status 200 counts as handled', () {
    const accepted = PasswordResetEmailService.isAccepted;

    expect(accepted(200, '{"ok":true}'), isTrue);

    // The app must fall back to Firebase's own email in all of these cases.
    expect(accepted(200, '{"ok":false,"error":"not-configured"}'), isFalse);
    expect(accepted(200, '{"ok":false,"error":"daily-limit"}'), isFalse);
    expect(accepted(200, '<html>Sign in</html>'), isFalse);
    expect(accepted(200, ''), isFalse);
    expect(accepted(302, '{"ok":true}'), isFalse);
    expect(accepted(500, '{"ok":true}'), isFalse);
  });

  test('without a service URL nothing is sent', () async {
    // Tests run without --dart-define, so WELCOME_EMAIL_URL is empty.
    expect(await PasswordResetEmailService().send('a@b.com'), isFalse);
  });
}
