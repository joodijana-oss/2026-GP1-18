import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:masra/services/opportunity_service.dart';

/// Checks every record of the bundled opportunities JSON, whatever its size
/// (the same rules as tools/upload_opportunities/upload_opportunities.js).
void main() {
  test('bundled opportunities JSON parses into complete records', () {
    final text =
        File('lib/assets/data/Masra_Opportunities.json').readAsStringSync();
    final raw = (jsonDecode(text) as List).cast<Map<String, dynamic>>();
    final opportunities = OpportunityService.parseJson(text);

    final careerPathIds = (jsonDecode(
      File('lib/assets/data/careerPaths.json').readAsStringSync(),
    ) as List)
        .map((p) => (p as Map)['id'].toString())
        .toSet();

    expect(opportunities, isNotEmpty);
    // No record was skipped for a missing id or title.
    expect(opportunities.length, raw.length);
    expect(opportunities.map((o) => o.id).toSet().length, opportunities.length,
        reason: 'ids must be unique');

    final day = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    String format(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    for (var i = 0; i < opportunities.length; i++) {
      final o = opportunities[i];
      final record = raw[i];

      expect(o.id, isNotEmpty, reason: 'record $i');
      expect(o.id.contains('/'), isFalse, reason: o.id);
      expect(o.title, isNotEmpty, reason: o.id);
      expect(o.url, isNotEmpty, reason: o.id);
      expect(o.type, isNotEmpty, reason: o.id);
      expect(['tuwaiq', 'doroob', 'coursera'], contains(o.source),
          reason: o.id);
      for (final path in o.careerPathIds) {
        expect(careerPathIds, contains(path), reason: '${o.id}: $path');
      }

      final dates = {
        'startDate': o.startDate,
        'endDate': o.endDate,
        'registrationDeadline': o.registrationDeadline,
      };
      dates.forEach((key, parsed) {
        final value = (record[key] ?? '').toString().trim();
        if (value.isEmpty) {
          expect(parsed, isNull, reason: '${o.id}: $key');
        } else {
          expect(value, matches(day), reason: '${o.id}: $key');
          expect(parsed, isNotNull, reason: '${o.id}: $key');
          // A real calendar day ("2026-02-30" would roll over).
          expect(format(parsed!), value, reason: '${o.id}: $key');
        }
      });
    }
  });
}
