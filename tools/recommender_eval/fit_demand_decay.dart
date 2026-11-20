import 'dart:io';
import 'dart:math';

import 'package:csv/csv.dart';

/// Measures how fast market demand falls from the most requested skill of
/// a career to the next ones, using the bundled job postings. The result is
/// the `demandDecay` setting of the opportunity recommender
/// (RankingWeights in lib/services/opportunity_recommender.dart).
///
/// Run it from the project root:
///
///   dart run tools/recommender_eval/fit_demand_decay.dart
///
/// Method:
///  1. Group the postings into career families by their cleaned title.
///  2. For each family, count the postings that mention each skill of its
///     list at least once.
///  3. Sort the skills from most to least mentioned and keep the first 12
///     (the AI analysis also returns at most 12 market skills).
///  4. Divide every count by the count of the top skill. Rank 0 is then
///     1.0, and each later rank is "how often it is requested compared
///     with the most requested skill".
///  5. Only families with at least 30 postings are used.
///  6. Try four curves that turn a rank into a weight and measure how far
///     each is from the real shares (mean absolute error, lower is better):
///       decay^rank        (the decay is fitted by least squares)
///       1 / log2(rank + 2)
///       1 / (rank + 1)
///       1 - rank / 12     (a straight line)
///
/// The title patterns and the skill lists below were written by the team.
/// They are a sample of the skills each family asks for, not a complete
/// list, so re-run this script when the postings file or the lists change.
const String postingsPath =
    'lib/assets/data/Masra_Career_Analysis_Jobs_881_Title_Cleaned.csv';

const int maxRanks = 12;
const int minPostings = 30;

/// One career family: which titles belong to it and which skills to count.
/// Both are regular expressions, matched without regard to case.
class Family {
  final String name;
  final String titlePattern;

  /// skill name -> pattern searched in the posting description.
  final Map<String, String> skills;

  const Family(this.name, this.titlePattern, this.skills);
}

const List<Family> families = [
  Family('Data analysis', r'data analy', {
    'SQL': r'\bsql\b',
    'Power BI': r'power ?bi',
    'Tableau': r'tableau',
    'Excel': r'excel',
    'Python': r'python',
    'Statistics': r'statistic',
    'Data Visualization': r'visuali[sz]ation',
    'ETL': r'\betl\b',
    'Data Modeling': r'data model',
    'Storytelling': r'storytell',
    'R': r'\br\b',
  }),
  Family('Cybersecurity', r'security|cyber', {
    'SIEM': r'\bsiem\b',
    'Incident Response': r'incident response',
    'Threat Hunting': r'threat hunt',
    'Network Security': r'network security',
    'Splunk': r'splunk',
    'Vulnerability Management': r'vulnerab',
    'Risk': r'risk',
    'ISO 27001': r'27001',
    'NIST': r'nist',
    'SOC': r'\bsoc\b',
    'Firewall': r'firewall',
    'Penetration Testing': r'penetration',
    'Cloud Security': r'cloud security',
    'Linux': r'linux',
  }),
  Family('Software', r'software|developer|engineer', {
    'Git': r'\bgit\b',
    'Microservices': r'microservice',
    'REST API': r'rest',
    'Agile': r'agile',
    'Docker': r'docker',
    'SQL': r'\bsql\b',
    'Java': r'\bjava\b',
    'Python': r'python',
    'Testing': r'testing',
    'CI/CD': r'ci/cd',
    'Cloud': r'aws|azure',
    'Design Patterns': r'design pattern',
    'Data Structures': r'data structures',
    'JavaScript': r'javascript',
  }),
  Family('Cloud and DevOps', r'devops|cloud', {
    'Kubernetes': r'kubernetes',
    'Docker': r'docker',
    'Terraform': r'terraform',
    'CI/CD': r'ci/cd',
    'AWS': r'\baws\b',
    'Azure': r'azure',
    'Linux': r'linux',
    'Ansible': r'ansible',
    'Monitoring': r'monitoring',
    'Jenkins': r'jenkins',
    'Python': r'python',
    'Git': r'\bgit\b',
    'Networking': r'network',
  }),
  Family('UI/UX design', r'ux|ui|design', {
    'Figma': r'figma',
    'User Research': r'user research',
    'Prototyping': r'prototyp',
    'Wireframing': r'wireframe',
    'Design Systems': r'design system',
    'Usability Testing': r'usability',
    'Adobe XD': r'adobe xd',
    'Accessibility': r'accessib',
    'Interaction Design': r'interaction',
    'HTML/CSS': r'css',
  }),
  Family('Networking', r'network', {
    'Cisco': r'cisco',
    'Routing': r'routing',
    'Switching': r'switch',
    'Firewall': r'firewall',
    'TCP/IP': r'tcp',
    'VPN': r'vpn',
    'Network Security': r'network security',
    'Wireless': r'wireless|wi-?fi',
    'SD-WAN': r'sd-?wan',
    'CCNA': r'ccna',
    'Troubleshooting': r'troubleshoot',
    'Load Balancing': r'load balanc',
    'Monitoring': r'monitoring',
    'Linux': r'linux',
    'Automation': r'automation',
    'Fortinet': r'fortinet',
  }),
  Family('AI and machine learning', r'ai|machine|ml|data scien', {
    'Python': r'python',
    'Machine Learning': r'machine learning',
    'Deep Learning': r'deep learning',
    'TensorFlow': r'tensorflow',
    'PyTorch': r'pytorch',
    'NLP': r'\bnlp\b|natural language',
    'Computer Vision': r'computer vision',
    'MLOps': r'mlops',
    'LLM': r'\bllm|large language',
    'SQL': r'\bsql\b',
    'Statistics': r'statistic',
    'Cloud': r'aws|azure',
    'Generative AI': r'generative',
  }),
  Family('Database administration', r'database|dba', {
    'Oracle': r'oracle',
    'SQL Server': r'sql server',
    'PostgreSQL': r'postgres',
    'MySQL': r'mysql',
    'Backup and Recovery': r'backup',
    'Performance Tuning': r'tuning|performance',
    'High Availability': r'high availability|replication',
    'Linux': r'linux',
    'PL/SQL': r'pl/?sql',
    'NoSQL': r'nosql|mongodb',
    'Database Security': r'security',
    'Cloud': r'aws|azure',
    'Data Warehousing': r'warehouse',
  }),
];

void main() {
  final postings = _loadPostings();
  stdout.writeln('DEMAND DECAY FIT');
  stdout.writeln('Postings: ${postings.length} ($postingsPath)');
  stdout.writeln('');

  // (rank, share of the top skill) for every family that is large enough.
  final points = <_Point>[];
  var familiesUsed = 0;
  for (final family in families) {
    final title = RegExp(family.titlePattern, caseSensitive: false);
    final selected = postings.where((p) => title.hasMatch(p.title)).toList();
    final counts = _countSkills(family, selected);
    final used = selected.length >= minPostings && counts.first.value > 0;

    stdout.writeln('${family.name}: ${selected.length} postings'
        '${used ? '' : '  (not used: fewer than $minPostings postings)'}');
    final top = counts.first.value;
    for (var rank = 0; rank < counts.length && rank < maxRanks; rank++) {
      final share = top == 0 ? 0.0 : counts[rank].value / top;
      stdout.writeln('  ${rank.toString().padLeft(2)}  '
          '${counts[rank].key.padRight(26)}'
          '${counts[rank].value.toString().padLeft(4)}'
          '   share ${share.toStringAsFixed(2)}');
      if (used) points.add(_Point(rank, share));
    }
    if (used) familiesUsed++;
  }

  if (points.isEmpty) {
    stderr.writeln('No family has $minPostings postings or more.');
    exit(1);
  }

  // Least squares over a grid: the decay with the smallest squared error.
  var bestDecay = 0.7;
  var bestError = double.infinity;
  for (var step = 700; step <= 999; step++) {
    final decay = step / 1000;
    var error = 0.0;
    for (final point in points) {
      final difference = point.share - pow(decay, point.rank);
      error += difference * difference;
    }
    if (error < bestError) {
      bestError = error;
      bestDecay = decay;
    }
  }

  double meanAbsoluteError(double Function(int rank) curve) {
    var sum = 0.0;
    for (final point in points) {
      sum += (point.share - curve(point.rank)).abs();
    }
    return sum / points.length;
  }

  stdout.writeln('');
  stdout.writeln('RESULT (${points.length} points from $familiesUsed '
      'families with at least $minPostings postings, ranks 0 to '
      '${maxRanks - 1})');
  stdout.writeln('  Fitted decay: ${bestDecay.toStringAsFixed(3)}');
  stdout.writeln('  Mean absolute error of each curve (lower is better):');
  String error(double Function(int rank) curve) =>
      meanAbsoluteError(curve).toStringAsFixed(3);

  stdout.writeln('    decay^rank, decay ${bestDecay.toStringAsFixed(3)}   '
      '${error((k) => pow(bestDecay, k).toDouble())}');
  stdout.writeln('    decay^rank, decay 0.870   '
      '${error((k) => pow(0.87, k).toDouble())}');
  stdout.writeln('    1 / log2(rank + 2)        '
      '${error((k) => 1 / (log(k + 2) / ln2))}');
  stdout.writeln('    1 / (rank + 1)            '
      '${error((k) => 1 / (k + 1))}');
  stdout.writeln('    1 - rank / $maxRanks             '
      '${error((k) => 1 - k / maxRanks)}');
}

// ---------------------------------------------------------
// HELPERS
// ---------------------------------------------------------

class _Posting {
  final String title;
  final String text;

  const _Posting(this.title, this.text);
}

class _Point {
  final int rank;
  final double share;

  const _Point(this.rank, this.share);
}

/// The skills of [family] with the number of [postings] that mention each,
/// most mentioned first (equal counts keep the order of the list).
List<MapEntry<String, int>> _countSkills(
  Family family,
  List<_Posting> postings,
) {
  final names = family.skills.keys.toList();
  final counts = <MapEntry<String, int>>[];
  for (final name in names) {
    final pattern = RegExp(family.skills[name]!);
    counts.add(
      MapEntry(name, postings.where((p) => pattern.hasMatch(p.text)).length),
    );
  }
  counts.sort((a, b) {
    final byCount = b.value.compareTo(a.value);
    return byCount != 0
        ? byCount
        : names.indexOf(a.key).compareTo(names.indexOf(b.key));
  });
  return counts;
}

/// Reads the cleaned title and the lower-cased description of every
/// posting (the cleaned description, or the raw one when it is empty).
List<_Posting> _loadPostings() {
  final file = File(postingsPath);
  if (!file.existsSync()) {
    stderr.writeln(
        'File not found: $postingsPath (run this from the project root).');
    exit(1);
  }
  var text = file.readAsStringSync();
  if (text.startsWith('﻿')) text = text.substring(1);

  final rows = csv.decode(text);
  if (rows.isEmpty) return const [];
  final header = rows.first.map((value) => value.toString().trim()).toList();
  final titleIndex = header.indexOf('cleaned_title');
  final cleanedIndex = header.indexOf('cleaned_description');
  final rawIndex = header.indexOf('description_raw');
  if (titleIndex < 0 || cleanedIndex < 0 || rawIndex < 0) {
    stderr.writeln('Required columns were not found in $postingsPath.');
    exit(1);
  }

  String cell(List<dynamic> row, int index) =>
      index < row.length ? row[index].toString() : '';

  final postings = <_Posting>[];
  for (final row in rows.skip(1)) {
    final cleaned = cell(row, cleanedIndex);
    final description =
        cleaned.trim().isNotEmpty ? cleaned : cell(row, rawIndex);
    postings.add(_Posting(cell(row, titleIndex), description.toLowerCase()));
  }
  return postings;
}
