import 'package:flutter_test/flutter_test.dart';
import 'package:masra/constants/profile_options.dart';

void main() {
  final now = DateTime(2027, 7, 15);

  String? status(String? saved, {Object? year, Object? month}) =>
      ProfileOptions.effectiveGraduationStatus(
        saved,
        year: year,
        month: month,
        now: now,
      );

  test('a student becomes a graduate once the graduation month is over', () {
    expect(status('Student', year: 2027, month: 6), 'Graduate');
    expect(status('Student', year: 2026, month: 12), 'Graduate');
  });

  test('a student stays a student until the graduation month ends', () {
    expect(status('Student', year: 2027, month: 7), 'Student');
    expect(status('Student', year: 2027, month: 12), 'Student');
    expect(status('Student', year: 2028, month: 1), 'Student');
  });

  test('with no month saved, the year decides', () {
    expect(status('Student', year: 2026), 'Graduate');
    expect(status('Student', year: 2027), 'Student');
  });

  test('other values are left alone', () {
    expect(status('Graduate', year: 2030, month: 1), 'Graduate');
    expect(status('Fresh Graduate', year: 2020), 'Graduate');
    expect(status('Student'), 'Student');
    expect(status(null, year: 2020), isNull);
    expect(status('Something else', year: 2020), isNull);
  });

  test('graduation years include the current year', () {
    expect(
      ProfileOptions.graduationYears.first,
      DateTime.now().year.toString(),
    );
  });
}
