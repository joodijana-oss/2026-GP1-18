import 'package:flutter_test/flutter_test.dart';
import 'package:masra/utils/validators.dart';

void main() {
  group('email', () {
    test('accepts normal addresses', () {
      for (final email in [
        'name@domain.com',
        'sara.alharbi@ksu.edu.sa',
        'first_last+tag@mail.example.org',
        ' padded@example.com ',
      ]) {
        expect(Validators.email(email), isNull, reason: email);
      }
    });

    test('rejects malformed addresses', () {
      for (final email in [
        'abc',
        'sara@mail',
        'a@b..com',
        '.a@b.com',
        'a.@b.com',
        'a..b@c.com',
        'a@.b.com',
        'a@b.c',
      ]) {
        expect(Validators.email(email), 'Enter a valid email address.',
            reason: email);
      }
    });

    test('empty email has its own message', () {
      expect(Validators.email('  '), 'Email address is required.');
    });
  });

  group('password special characters', () {
    test('every symbol in the Firebase policy counts', () {
      for (final symbol in r'''^$*.[]{}()?"!@#%&/\,><':;|_~`=+-'''.split('')) {
        expect(PasswordValidator.hasSpecial('Abcdefg1$symbol'), isTrue,
            reason: symbol);
      }
    });

    test('letters, digits and spaces are not special', () {
      expect(PasswordValidator.hasSpecial('Abcdefg12'), isFalse);
      expect(PasswordValidator.hasSpecial('Abc defg12'), isFalse);
    });

    test('a strong password passes, a weak one lists what is missing', () {
      expect(PasswordValidator.validate('Abcdefg1~'), isNull);
      final message = PasswordValidator.validate('abcdefgh')!;
      expect(message, contains('an uppercase letter'));
      expect(message, contains('a number'));
      expect(message, contains('a special character'));
    });
  });
}
