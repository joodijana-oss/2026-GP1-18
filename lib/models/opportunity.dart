/// One learning opportunity (training program, bootcamp, course ...), as
/// stored in the Firestore `opportunities` collection (and in the bundled
/// JSON fallback).
///
/// Tuwaiq Academy events have dates. Doroob and Coursera courses are
/// self-paced and have no dates.
class Opportunity {
  final String id;

  /// Where the record comes from: `tuwaiq`, `doroob` or `coursera`.
  final String source;

  /// Who teaches it (for Coursera, the university or company).
  final String provider;

  /// Training Program, Bootcamp, Meetup, Webinar, Course or Hackathon.
  final String type;
  final String title;
  final String description;

  /// What the learner will be able to do at the end.
  final List<String> objectives;

  /// What the learner needs before joining (not what it teaches).
  final List<String> requirements;
  final String field;
  final String location;

  /// Null when the source does not say.
  final bool? isFree;

  /// For example "600 SAR". Empty when free or unknown.
  final String price;
  final String duration;
  final String url;
  final List<String> skills;

  /// Career path ids from careerPaths.json (e.g. `data_analyst`).
  final List<String> careerPathIds;

  /// Dates are kept as days only (no time). Null when not given.
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? registrationDeadline;

  const Opportunity({
    required this.id,
    required this.source,
    required this.provider,
    required this.type,
    required this.title,
    required this.description,
    required this.objectives,
    required this.requirements,
    required this.field,
    required this.location,
    required this.isFree,
    required this.price,
    required this.duration,
    required this.url,
    required this.skills,
    required this.careerPathIds,
    required this.startDate,
    required this.endDate,
    required this.registrationDeadline,
  });

  // ---------------------------------------------------------
  // FROM FIRESTORE OR JSON
  // ---------------------------------------------------------

  /// Builds an opportunity from a Firestore document or a JSON record.
  /// Missing fields become empty; when [id] is empty, `data['id']` is used.
  factory Opportunity.fromMap(String id, Map<String, dynamic> data) {
    String text(String key) => data[key]?.toString().trim() ?? '';

    List<String> list(String key) {
      final value = data[key];
      if (value is! List) return [];
      return value
          .map((e) => e?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }

    final docId = id.trim();
    return Opportunity(
      id: docId.isNotEmpty ? docId : text('id'),
      source: text('source'),
      provider: text('provider'),
      type: text('type'),
      title: text('title'),
      description: text('description'),
      objectives: list('objectives'),
      requirements: list('requirements'),
      field: text('field'),
      location: text('location'),
      isFree: _flag(data['isFree']),
      price: text('price'),
      duration: text('duration'),
      url: text('url'),
      skills: list('skills'),
      careerPathIds: list('careerPathIds'),
      startDate: _date(data['startDate']),
      endDate: _date(data['endDate']),
      registrationDeadline: _date(data['registrationDeadline']),
    );
  }

  // ---------------------------------------------------------
  // LABELS
  // ---------------------------------------------------------

  /// The platform name to show: Tuwaiq Academy, Doroob or Coursera.
  String get sourceLabel {
    switch (source.toLowerCase()) {
      case 'tuwaiq':
        return 'Tuwaiq Academy';
      case 'doroob':
        return 'Doroob';
      case 'coursera':
        return 'Coursera';
      default:
        return provider.isNotEmpty ? provider : source;
    }
  }

  /// Who offers it: "Google on Coursera" for Coursera courses, otherwise
  /// the provider (or the platform name when there is no provider).
  String get providerLabel {
    if (source.toLowerCase() == 'coursera') {
      if (provider.isEmpty || provider.toLowerCase() == 'coursera') {
        return 'Coursera';
      }
      return '$provider on Coursera';
    }
    return provider.isNotEmpty ? provider : sourceLabel;
  }

  // ---------------------------------------------------------
  // DATES
  // ---------------------------------------------------------

  /// True for events with a date (Tuwaiq), false for self-paced courses.
  bool get hasDates =>
      startDate != null || endDate != null || registrationDeadline != null;

  /// True when the user can still join on [now]. Only the day counts:
  ///  - with a registration deadline: open until the end of that day;
  ///  - else with a start date: open until the day it starts;
  ///  - else with only an end date: open until the day it ends;
  ///  - no dates (self-paced course): always open.
  bool isOpen(DateTime now) {
    final today = _day(now);
    final deadline = registrationDeadline;
    if (deadline != null) return !today.isAfter(deadline);
    final start = startDate;
    if (start != null) return !start.isBefore(today);
    final end = endDate;
    if (end != null) return !end.isBefore(today);
    return true;
  }

  /// Whole days from [now] to the registration deadline: 0 on the deadline
  /// day, negative after it. Null when there is no deadline.
  int? daysLeft(DateTime now) {
    final deadline = registrationDeadline;
    if (deadline == null) return null;
    // UTC so a daylight saving change does not lose a day.
    final from = DateTime.utc(now.year, now.month, now.day);
    final to = DateTime.utc(deadline.year, deadline.month, deadline.day);
    return to.difference(from).inDays;
  }

  // ---------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Reads a date written as 'YYYY-MM-DD', a DateTime, or a Firestore
  /// Timestamp (anything with `toDate()`). Empty or unknown values give null.
  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return _day(value);
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return null;
      final parsed = DateTime.tryParse(text);
      return parsed == null ? null : _day(parsed);
    }
    try {
      // Firestore Timestamp, without importing cloud_firestore here.
      final date = (value as dynamic).toDate();
      if (date is DateTime) return _day(date);
    } catch (_) {
      // Not a date.
    }
    return null;
  }

  /// true / false, also when written as text. Anything else gives null.
  static bool? _flag(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase();
    if (text == 'true' || text == 'yes') return true;
    if (text == 'false' || text == 'no') return false;
    return null;
  }
}
