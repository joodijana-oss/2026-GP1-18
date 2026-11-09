import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:masra/services/certification_service.dart';

void main() {
  test('bundled certifications CSV parses into complete records', () {
    final text = File(
      'lib/assets/data/Masra_IT_Certifications.csv',
    ).readAsStringSync();

    final certs = CertificationService.parseCsv(text);

    expect(certs.length, 300);
    expect(certs.map((c) => c.id).toSet().length, certs.length);

    for (final c in certs) {
      expect(c.name, isNotEmpty, reason: c.id);
      expect(c.issuer, isNotEmpty, reason: c.id);
      expect(c.description, isNotEmpty, reason: c.id);
      expect(c.descriptionAr, isNotEmpty, reason: c.id);
      expect(c.careerPaths, isNotEmpty, reason: c.id);
      expect(c.officialUrl, startsWith('https://'), reason: c.id);
      expect(
        ['Beginner', 'Intermediate', 'Advanced'],
        contains(c.level),
        reason: c.id,
      );
    }

    final ccna = certs.firstWhere((c) => c.id == 'cisco_ccna');
    expect(ccna.careerPaths, contains('network_engineer'));
    expect(ccna.verified, isTrue);
  });
}
