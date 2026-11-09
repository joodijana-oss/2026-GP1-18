/// One professional IT certification, as stored in the Firestore
/// `certifications` collection (and in the bundled CSV fallback).
class Certification {
  final String id;
  final String name;
  final String shortName;
  final String issuer;
  final String examCode;

  /// Beginner, Intermediate or Advanced.
  final String level;
  final String category;
  final String description;
  final String descriptionAr;

  /// Career path ids from careerPaths.json (e.g. `network_engineer`).
  final List<String> careerPaths;
  final List<String> skills;
  final String officialUrl;

  /// True when the details were checked on the official certification page.
  final bool verified;
  final String statusNote;

  const Certification({
    required this.id,
    required this.name,
    required this.shortName,
    required this.issuer,
    required this.examCode,
    required this.level,
    required this.category,
    required this.description,
    required this.descriptionAr,
    required this.careerPaths,
    required this.skills,
    required this.officialUrl,
    required this.verified,
    required this.statusNote,
  });

  // ---------------------------------------------------------
  // FROM FIRESTORE
  // ---------------------------------------------------------

  factory Certification.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    List<String> list(dynamic value) =>
        value is List ? value.map((e) => e.toString()).toList() : [];

    return Certification(
      id: id,
      name: data['name']?.toString() ?? '',
      shortName: data['shortName']?.toString() ?? '',
      issuer: data['issuer']?.toString() ?? '',
      examCode: data['examCode']?.toString() ?? '',
      level: data['level']?.toString() ?? '',
      category: data['category']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      descriptionAr: data['descriptionAr']?.toString() ?? '',
      careerPaths: list(data['careerPaths']),
      skills: list(data['skills']),
      officialUrl: data['officialUrl']?.toString() ?? '',
      verified: data['verified'] == true,
      statusNote: data['statusNote']?.toString() ?? '',
    );
  }

  // ---------------------------------------------------------
  // FROM CSV (offline fallback; column names as in the CSV header)
  // ---------------------------------------------------------

  factory Certification.fromCsvRow(Map<String, String> row) {
    List<String> list(String? value) => (value ?? '')
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return Certification(
      id: row['id'] ?? '',
      name: row['name'] ?? '',
      shortName: row['short_name'] ?? '',
      issuer: row['issuer'] ?? '',
      examCode: row['exam_code'] ?? '',
      level: row['level'] ?? '',
      category: row['category'] ?? '',
      description: row['description'] ?? '',
      descriptionAr: row['description_ar'] ?? '',
      careerPaths: list(row['career_paths']),
      skills: list(row['skills']),
      officialUrl: row['official_url'] ?? '',
      verified: (row['verified'] ?? '').toLowerCase() == 'yes',
      statusNote: row['status_note'] ?? '',
    );
  }

  /// Arabic description when asked for and available, otherwise English.
  String descriptionFor(String languageCode) =>
      languageCode == 'ar' && descriptionAr.isNotEmpty
          ? descriptionAr
          : description;

  /// 0 = Beginner, 1 = Intermediate, 2 = Advanced (unknown levels last).
  int get levelRank {
    switch (level) {
      case 'Beginner':
        return 0;
      case 'Intermediate':
        return 1;
      case 'Advanced':
        return 2;
      default:
        return 3;
    }
  }
}
