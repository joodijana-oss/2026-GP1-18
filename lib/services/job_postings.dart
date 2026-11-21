import 'package:csv/csv.dart';

/// The job postings of the bundled dataset that belong to a career goal,
/// and the text built from them for the market-skills request.
///
/// This file has no Flutter import on purpose. The app reads the dataset
/// from its assets (JobMarketService) and the evaluation tools read the
/// same file from disk; both pass the text here, so they filter the
/// postings in exactly the same way.
class JobPostings {
  JobPostings._();

  /// How many postings one analysis sends to the market-skills request.
  static const int analysisLimit = 20;

  /// The first [limit] postings of [csvText] whose title matches the
  /// career goal (see [aliasMatches]), each as
  /// {title, description, city, source}.
  static List<Map<String, String>> relevant(
    String csvText,
    String careerGoalId, {
    int limit = 25,
  }) {
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

    // Normalized once here, not again for every row.
    final aliases =
        careerAliases(
      careerGoalId,
    ).map(normalize).toList();

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
          normalize(title);

      final matches =
          aliases.any(
        (alias) => aliasMatches(
          normalizedTitle,
          alias,
        ),
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

  /// The text of [jobs] as the market-skills request reads it.
  static String marketText(
    List<Map<String, String>> jobs,
  ) {
    final buffer = StringBuffer();

    for (int i = 0; i < jobs.length; i++) {
      final job = jobs[i];

      buffer.writeln('JOB ${i + 1}');
      buffer.writeln('Title: ${job['title'] ?? ''}');

      final city = job['city'] ?? '';

      if (city.trim().isNotEmpty) {
        buffer.writeln('City: $city');
      }

      buffer.writeln('Description:');
      buffer.writeln(job['description'] ?? '');
      buffer.writeln('------------------------------');
    }

    return buffer.toString();
  }

  // =========================================================
  // CAREER GOAL -> JOB TITLE ALIASES
  // =========================================================

  static List<String> careerAliases(
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
    'security engineer',
    'cybersecurity engineer',
    'cyber security engineer',
    'penetration testing',
    'penetration tester',
    'vapt',
    'iam',
    'identity and access management',
    'security operations engineer',
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

      // Newer goals

      case 'qa_test_engineer':
        return [
          'qa',
          'quality assurance',
          'tester',
          'test engineer',
          'test automation',
          'software testing',
          'performance testing',
          'sdet',
          'quality engineer',
        ];

      case 'data_engineer':
        return [
          'data engineer',
          'etl',
          'big data',
          'data platform',
          'data pipeline',
          'data warehouse',
          'databricks',
          'spark',
          'data integration',
          'informatica',
        ];

      case 'cybersecurity_grc_specialist':
        return [
          'grc',
          'governance',
          'compliance',
          'information security risk',
          'cybersecurity risk',
          'cyber security risk',
          'risk management',
        ];

      case 'telecom_engineer':
        return [
          'telecom',
          'telecommunication',
          'rf',
          '5g',
          'lte',
          'transmission',
        ];

      case 'infrastructure_data_center_engineer':
        return [
          'infrastructure',
          'data center',
          'datacenter',
          'server engineer',
          'vmware',
          'virtualization',
        ];

      case 'it_support_specialist':
        return [
          'it support',
          'help desk',
          'helpdesk',
          'service desk',
          'desktop support',
          'technical support',
          'it technician',
        ];

      case 'product_manager':
        return [
          'product manager',
          'product owner',
          'product management',
        ];

      case 'erp_consultant':
        return [
          'erp',
          'sap',
          'oracle',
          'dynamics 365',
          'd365',
        ];

      case 'solutions_architect':
        return [
          'solution architect',
          'solutions architect',
          'enterprise architect',
          'technical architect',
          'cloud architect',
          'architect',
        ];

      case 'pre_sales_engineer':
        return [
          'pre-sales',
          'presales',
          'pre sales',
          'sales engineer',
          'solution consultant',
          'solutions consultant',
        ];

      default:
        return [];
    }
  }

  // =========================================================
  // TITLE MATCHING
  // =========================================================

  /// Whether [normalizedAlias] names the job in [normalizedTitle], both
  /// already passed through [normalize]. The alias must appear as whole
  /// words, side by side and in order; its last word may also take a
  /// plural "s" ("developers" is the same job as "developer"), but no
  /// other ending, so "engineer" never matches inside "engineering" and
  /// "rf" never matches inside "surf". The same rule for every goal.
  static bool aliasMatches(
    String normalizedTitle,
    String normalizedAlias,
  ) {
    if (normalizedAlias.isEmpty) {
      return false;
    }

    final padded = ' $normalizedTitle ';

    return padded.contains(' $normalizedAlias ') ||
        padded.contains(' ${normalizedAlias}s ');
  }

  // =========================================================
  // NORMALIZE TEXT
  // =========================================================

  static String normalize(
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
