import 'package:flutter_test/flutter_test.dart';
import 'package:masra/models/opportunity.dart';

/// Looks like a Firestore Timestamp: it only has `toDate()`.
class FakeTimestamp {
  final DateTime date;
  const FakeTimestamp(this.date);
  DateTime toDate() => date;
}

Opportunity fromMap(Map<String, dynamic> data, {String id = 'doc_id'}) =>
    Opportunity.fromMap(id, data);

void main() {
  group('fromMap', () {
    test('reads a full record', () {
      final o = fromMap({
        'id': 'ignored_when_doc_id_given',
        'source': 'tuwaiq',
        'provider': 'Tuwaiq Academy',
        'type': 'Bootcamp',
        'title': ' Data Analysis Bootcamp ',
        'description': 'Learn data analysis.',
        'objectives': ['Clean data', 'Build dashboards'],
        'requirements': ['Basic computer skills'],
        'field': 'Data Science',
        'location': 'Riyadh',
        'isFree': false,
        'price': '600 SAR',
        'startDate': '2026-12-06',
        'endDate': '2026-12-31',
        'registrationDeadline': '2026-12-01',
        'duration': '4 weeks',
        'url': 'https://example.com',
        'skills': ['Data Analysis', 'Python'],
        'careerPathIds': ['data_analyst'],
        'language': 'en',
      });

      expect(o.id, 'doc_id');
      expect(o.source, 'tuwaiq');
      expect(o.title, 'Data Analysis Bootcamp');
      expect(o.objectives, ['Clean data', 'Build dashboards']);
      expect(o.requirements, ['Basic computer skills']);
      expect(o.isFree, isFalse);
      expect(o.price, '600 SAR');
      expect(o.startDate, DateTime(2026, 12, 6));
      expect(o.endDate, DateTime(2026, 12, 31));
      expect(o.registrationDeadline, DateTime(2026, 12, 1));
      expect(o.skills, ['Data Analysis', 'Python']);
      expect(o.careerPathIds, ['data_analyst']);
      expect(o.hasDates, isTrue);
    });

    test('empty strings and missing fields become empty values', () {
      final o = fromMap({
        'title': 'Course',
        'startDate': '',
        'endDate': '  ',
        'registrationDeadline': 'not a date',
        'skills': ['Python', '', '  '],
        'isFree': null,
      });

      expect(o.source, '');
      expect(o.provider, '');
      expect(o.url, '');
      expect(o.objectives, isEmpty);
      expect(o.requirements, isEmpty);
      expect(o.careerPathIds, isEmpty);
      expect(o.skills, ['Python']);
      expect(o.isFree, isNull);
      expect(o.startDate, isNull);
      expect(o.endDate, isNull);
      expect(o.registrationDeadline, isNull);
      expect(o.hasDates, isFalse);
    });

    test('the id falls back to the id field', () {
      expect(fromMap({'id': 'from_data'}, id: '').id, 'from_data');
      expect(fromMap({}, id: '').id, '');
    });

    test('reads Timestamp-like objects and DateTime values as days', () {
      final o = fromMap({
        'startDate': FakeTimestamp(DateTime(2026, 12, 6, 15, 30)),
        'endDate': DateTime(2026, 12, 31, 9),
        'registrationDeadline': Object(),
      });
      expect(o.startDate, DateTime(2026, 12, 6));
      expect(o.endDate, DateTime(2026, 12, 31));
      expect(o.registrationDeadline, isNull);
    });

    test('isFree written as text is understood', () {
      expect(fromMap({'isFree': 'true'}).isFree, isTrue);
      expect(fromMap({'isFree': 'false'}).isFree, isFalse);
      expect(fromMap({'isFree': 'maybe'}).isFree, isNull);
    });
  });

  group('isOpen', () {
    final event = fromMap({
      'registrationDeadline': '2026-12-01',
      'startDate': '2026-12-06',
    });

    test('the deadline day itself is still open, the next day is not', () {
      expect(event.isOpen(DateTime(2026, 11, 30)), isTrue);
      expect(event.isOpen(DateTime(2026, 12, 1)), isTrue);
      expect(event.isOpen(DateTime(2026, 12, 1, 23, 59)), isTrue);
      expect(event.isOpen(DateTime(2026, 12, 2)), isFalse);
    });

    test('the deadline wins over the start date', () {
      // Still before the start, but registration has closed.
      expect(event.isOpen(DateTime(2026, 12, 4)), isFalse);
    });

    test('without a deadline it is open until the start day', () {
      final o = fromMap({'startDate': '2026-12-06', 'endDate': '2026-12-08'});
      expect(o.isOpen(DateTime(2026, 12, 5)), isTrue);
      expect(o.isOpen(DateTime(2026, 12, 6, 20)), isTrue);
      expect(o.isOpen(DateTime(2026, 12, 7)), isFalse);
    });

    test('with only an end date it is open until the end day', () {
      final o = fromMap({'endDate': '2026-12-08'});
      expect(o.isOpen(DateTime(2026, 12, 8)), isTrue);
      expect(o.isOpen(DateTime(2026, 12, 9)), isFalse);
    });

    test('a course with no dates is always open', () {
      final o = fromMap({'title': 'Self-paced'});
      expect(o.isOpen(DateTime(2020)), isTrue);
      expect(o.isOpen(DateTime(2040)), isTrue);
    });
  });

  group('daysLeft', () {
    test('counts whole days to the deadline', () {
      final o = fromMap({'registrationDeadline': '2026-12-01'});
      expect(o.daysLeft(DateTime(2026, 11, 28, 22)), 3);
      expect(o.daysLeft(DateTime(2026, 12, 1, 23)), 0);
      expect(o.daysLeft(DateTime(2026, 12, 3)), -2);
    });

    test('does not lose a day over a daylight saving change', () {
      final o = fromMap({'registrationDeadline': '2027-04-05'});
      expect(o.daysLeft(DateTime(2027, 3, 1)), 35);
    });

    test('is null without a deadline', () {
      expect(fromMap({'startDate': '2026-12-06'}).daysLeft(DateTime(2026)),
          isNull);
    });
  });

  group('labels', () {
    test('source labels', () {
      expect(fromMap({'source': 'tuwaiq'}).sourceLabel, 'Tuwaiq Academy');
      expect(fromMap({'source': 'doroob'}).sourceLabel, 'Doroob');
      expect(fromMap({'source': 'coursera'}).sourceLabel, 'Coursera');
      expect(fromMap({'source': 'other', 'provider': 'Udacity'}).sourceLabel,
          'Udacity');
    });

    test('provider labels', () {
      expect(
        fromMap({'source': 'coursera', 'provider': 'Google'}).providerLabel,
        'Google on Coursera',
      );
      expect(fromMap({'source': 'coursera'}).providerLabel, 'Coursera');
      expect(
        fromMap({'source': 'coursera', 'provider': 'Coursera'}).providerLabel,
        'Coursera',
      );
      expect(
        fromMap({'source': 'tuwaiq', 'provider': 'Tuwaiq Academy'})
            .providerLabel,
        'Tuwaiq Academy',
      );
      expect(fromMap({'source': 'doroob'}).providerLabel, 'Doroob');
    });
  });
}
