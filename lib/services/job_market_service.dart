import 'package:csv/csv.dart';
import 'package:flutter/services.dart';

class JobMarketService {
  static const String _jobsPath =
    'lib/assets/data/Masra_Career_Analysis_Jobs_881_Title_Cleaned.csv';
  // =========================================================
  // GET RELEVANT JOBS
  // =========================================================

  Future<List<Map<String, String>>> getRelevantJobs(
    String careerGoalId, {
    int limit = 25,
  }) async {
    final csvText = await rootBundle.loadString(
      _jobsPath,
    );

    final rows = csv.decode(csvText);

    if (rows.isEmpty) {
      return [];
    }

    final header = rows.first
        .map(
          (value) => value.toString().trim(),
        )
        .toList();

    final titleIndex =
        header.indexOf('cleaned_title');

    final descriptionIndex =
        header.indexOf('cleaned_description');

    final cityIndex =
        header.indexOf('normalized_city');

    final sourceIndex =
        header.indexOf('normalized_source');

    if (titleIndex == -1 ||
        descriptionIndex == -1) {
      throw Exception(
        'Required job columns were not found.',
      );
    }

    final aliases =
        _careerAliases(
      careerGoalId,
    );

    if (aliases.isEmpty) {
      throw Exception(
        'No job-title mapping found for career goal: $careerGoalId',
      );
    }

    final relevantJobs =
        <Map<String, String>>[];

    for (int i = 1;
        i < rows.length;
        i++) {
      final row = rows[i];

      if (row.length <= titleIndex ||
          row.length <= descriptionIndex) {
        continue;
      }

      final title =
          row[titleIndex]
              .toString()
              .trim();

      final description =
          row[descriptionIndex]
              .toString()
              .trim();

      if (title.isEmpty ||
          description.isEmpty) {
        continue;
      }

      final normalizedTitle =
          _normalize(title);

      final matches =
          aliases.any(
        (alias) {
          final normalizedAlias =
              _normalize(alias);

          return normalizedTitle.contains(
            normalizedAlias,
          );
        },
      );

      if (!matches) {
        continue;
      }

      String city = '';

      if (cityIndex != -1 &&
          row.length > cityIndex) {
        city =
            row[cityIndex]
                .toString()
                .trim();
      }

      String source = '';

      if (sourceIndex != -1 &&
          row.length > sourceIndex) {
        source =
            row[sourceIndex]
                .toString()
                .trim();
      }

      relevantJobs.add({
        'title': title,
        'description': description,
        'city': city,
        'source': source,
      });

      if (relevantJobs.length >=
          limit) {
        break;
      }
    }

    return relevantJobs;
  }

  // =========================================================
  // BUILD TEXT FOR CLAUDE
  // =========================================================

  Future<String> getRelevantJobMarketText(
    String careerGoalId, {
    int limit = 20,
  }) async {
    final jobs =
        await getRelevantJobs(
      careerGoalId,
      limit: limit,
    );

    if (jobs.isEmpty) {
      return '';
    }

    final buffer =
        StringBuffer();

    for (int i = 0;
        i < jobs.length;
        i++) {
      final job = jobs[i];

      buffer.writeln(
        'JOB ${i + 1}',
      );

      buffer.writeln(
        'Title: ${job['title'] ?? ''}',
      );

      final city =
          job['city'] ?? '';

      if (city.isNotEmpty) {
        buffer.writeln(
          'City: $city',
        );
      }

      buffer.writeln(
        'Description:',
      );

      buffer.writeln(
        job['description'] ?? '',
      );

      buffer.writeln(
        '------------------------------',
      );
    }

    return buffer.toString();
  }

  // =========================================================
  // GET RELEVANT JOB COUNT
  // =========================================================

  Future<int> getRelevantJobCount(
    String careerGoalId,
  ) async {
    final jobs =
        await getRelevantJobs(
      careerGoalId,
      limit: 881,
    );

    return jobs.length;
  }

  // =========================================================
  // CAREER GOAL → JOB TITLE ALIASES
  // =========================================================

  List<String> _careerAliases(
    String careerGoalId,
  ) {
    switch (careerGoalId) {
      case 'software_engineer':
        return [
          'software engineer',
          'software developer',
          'application developer',
          'application engineer',
          'backend engineer',
          'backend developer',
          'full stack engineer',
          'full stack developer',
        ];

      case 'web_developer':
        return [
          'web developer',
          'frontend developer',
          'front end developer',
          'frontend engineer',
          'front end engineer',
          'backend developer',
          'full stack developer',
          'fullstack developer',
          'web engineer',
        ];

      case 'mobile_developer':
        return [
          'mobile developer',
          'mobile engineer',
          'android developer',
          'android engineer',
          'ios developer',
          'ios engineer',
          'flutter developer',
          'flutter engineer',
        ];

      case 'data_analyst':
        return [
          'data analyst',
          'analytics analyst',
          'data analytics',
          'business intelligence analyst',
          'bi analyst',
          'reporting analyst',
        ];

      case 'data_scientist':
        return [
          'data scientist',
          'data science',
          'applied scientist',
        ];

      case 'ai_ml_engineer':
        return [
          'ai engineer',
          'artificial intelligence engineer',
          'machine learning engineer',
          'ml engineer',
          'ai developer',
          'machine learning developer',
          'generative ai',
          'genai engineer',
        ];

      case 'cybersecurity_analyst':
        return [
          'cybersecurity analyst',
          'cyber security analyst',
          'security analyst',
          'soc analyst',
          'information security analyst',
          'cyber analyst',
          'security operations analyst',
        ];

      case 'cloud_devops_engineer':
        return [
          'devops engineer',
          'cloud engineer',
          'cloud devops',
          'site reliability engineer',
          'sre engineer',
          'platform engineer',
          'cloud infrastructure engineer',
        ];

      case 'network_engineer':
        return [
          'network engineer',
          'networking engineer',
          'network administrator',
          'network specialist',
          'network operations',
          'noc engineer',
        ];

      case 'systems_administrator':
        return [
          'systems administrator',
          'system administrator',
          'systems engineer',
          'system engineer',
          'infrastructure administrator',
        ];

      case 'database_administrator':
        return [
          'database administrator',
          'database engineer',
          'database specialist',
          'dba',
        ];

      case 'ui_ux_designer':
        return [
          'ui ux designer',
          'ui/ux designer',
          'ux designer',
          'ui designer',
          'product designer',
          'user experience designer',
          'user interface designer',
        ];

      case 'business_analyst':
        return [
          'business analyst',
          'business systems analyst',
          'business system analyst',
          'requirements analyst',
          'functional analyst',
        ];

      case 'it_project_manager':
        return [
          'it project manager',
          'technical project manager',
          'technology project manager',
          'technical program manager',
          'it program manager',
          'project manager',
        ];

      case 'it_consultant':
        return [
          'it consultant',
          'technology consultant',
          'technical consultant',
          'digital transformation consultant',
          'information technology consultant',
        ];

      default:
        return [];
    }
  }

  // =========================================================
  // NORMALIZE TEXT
  // =========================================================

  String _normalize(
    String value,
  ) {
    return value
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll('/', ' ')
        .replaceAll('-', ' ')
        .replaceAll(
          RegExp(r'[^a-z0-9 ]'),
          ' ',
        )
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        )
        .trim();
  }
}