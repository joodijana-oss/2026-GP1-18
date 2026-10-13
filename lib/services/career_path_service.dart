import 'dart:convert';

import 'package:flutter/services.dart';

class CareerPathService {
  Future<Map<String, dynamic>?> getCareerPath(
    String careerGoalId,
  ) async {
    final jsonString = await rootBundle.loadString(
      'lib/assets/data/careerPaths.json',
    );

    final List<dynamic> paths = jsonDecode(jsonString);

    for (final item in paths) {
      if (item is Map &&
          item['id']?.toString() == careerGoalId) {
        return Map<String, dynamic>.from(item);
      }
    }

    return null;
  }

  Future<String> getCareerName(
    String careerGoalId,
  ) async {
    final path = await getCareerPath(
      careerGoalId,
    );

    return path?['name']?.toString() ??
        careerGoalId;
  }

  List<String> getJobFamilies(
    String careerGoalId,
  ) {
    switch (careerGoalId) {
      case 'software_engineer':
        return [
          'Software',
        ];

      case 'web_developer':
        return [
          'Software',
        ];

      case 'mobile_developer':
        return [
          'Software',
        ];

      case 'data_analyst':
        return [
          'Data and AI',
        ];

      case 'data_scientist':
        return [
          'Data and AI',
        ];

      case 'ai_ml_engineer':
        return [
          'Data and AI',
        ];

      case 'cybersecurity_analyst':
        return [
          'Data Protection and Cybersecurity',
        ];

      case 'cloud_devops_engineer':
        return [
          'Infrastructure',
          'Software',
        ];

      case 'network_engineer':
        return [
          'Infrastructure',
          'Telecom engineering',
        ];

      case 'systems_administrator':
        return [
          'Infrastructure',
        ];

      case 'database_administrator':
        return [
          'Infrastructure',
          'Data and AI',
        ];

      case 'ui_ux_designer':
        return [
          'Design and Animation',
        ];

      case 'business_analyst':
        return [
          'Business processes',
        ];

      case 'it_project_manager':
        return [
          'Project management',
        ];

      case 'it_consultant':
        return [
          'Business processes',
          'Infrastructure',
          'Software',
        ];

      default:
        return [];
    }
  }

  Future<List<String>> getTargetSkills(
    String careerGoalId,
  ) async {
    final csvText = await rootBundle.loadString(
      'lib/assets/data/Masra_Taxonomy.csv',
    );

    final jobFamilies = getJobFamilies(
      careerGoalId,
    );

    if (jobFamilies.isEmpty) {
      return [];
    }

    final lines = const LineSplitter().convert(
      csvText,
    );

    if (lines.length <= 1) {
      return [];
    }

    final header = _parseCsvLine(
      lines.first,
    );

    final skillIndex = header.indexOf(
      'technical_skill',
    );

    final familyIndex = header.indexOf(
      'job_family',
    );

    final prioritizedIndex = header.indexOf(
      'prioritized',
    );

    if (skillIndex == -1 ||
        familyIndex == -1) {
      throw Exception(
        'Required columns were not found in Masra_Taxonomy.csv',
      );
    }

    final prioritizedSkills = <String>{};
    final otherSkills = <String>{};

    for (int i = 1; i < lines.length; i++) {
      final row = _parseCsvLine(
        lines[i],
      );

      if (row.length <= skillIndex ||
          row.length <= familyIndex) {
        continue;
      }

      final skill = row[skillIndex].trim();

      final familyText =
          row[familyIndex].trim();

      if (skill.isEmpty ||
          familyText.isEmpty) {
        continue;
      }

      final normalizedFamilyText =
          familyText.toLowerCase();

      final matchesFamily =
          jobFamilies.any(
        (targetFamily) =>
            normalizedFamilyText.contains(
          targetFamily.toLowerCase(),
        ),
      );

      if (!matchesFamily) {
        continue;
      }

      String prioritized = '';

      if (prioritizedIndex != -1 &&
          row.length > prioritizedIndex) {
        prioritized =
            row[prioritizedIndex]
                .trim()
                .toLowerCase();
      }

      if (prioritized == 'yes' ||
          prioritized == 'true' ||
          prioritized == '1') {
        prioritizedSkills.add(skill);
      } else {
        otherSkills.add(skill);
      }
    }

    final result = <String>[
      ...prioritizedSkills,
    ];

    for (final skill in otherSkills) {
      if (result.length >= 20) {
        break;
      }

      if (!result.contains(skill)) {
        result.add(skill);
      }
    }

    return result;
  }

  List<String> calculateSkillGaps({
    required List<String> currentSkills,
    required List<String> targetSkills,
  }) {
    final normalizedCurrent = currentSkills
        .map(_normalizeSkill)
        .where(
          (skill) => skill.isNotEmpty,
        )
        .toSet();

    final gaps = <String>[];

    for (final target in targetSkills) {
      final normalizedTarget =
          _normalizeSkill(target);

      final found =
          normalizedCurrent.any(
        (current) =>
            current ==
                normalizedTarget ||
            current.contains(
              normalizedTarget,
            ) ||
            normalizedTarget.contains(
              current,
            ),
      );

      if (!found) {
        gaps.add(target);
      }
    }

    return gaps;
  }

  String _normalizeSkill(
    String value,
  ) {
    return value
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll('/', ' ')
        .replaceAll('-', ' ')
        .replaceAll(
          RegExp(r'[^a-z0-9 ]'),
          '',
        )
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        )
        .trim();
  }

  List<String> _parseCsvLine(
    String line,
  ) {
    final result = <String>[];
    final buffer = StringBuffer();

    bool insideQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        if (insideQuotes &&
            i + 1 < line.length &&
            line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          insideQuotes = !insideQuotes;
        }
      } else if (char == ',' &&
          !insideQuotes) {
        result.add(
          buffer.toString(),
        );

        buffer.clear();
      } else {
        buffer.write(char);
      }
    }

    result.add(
      buffer.toString(),
    );

    return result;
  }
}