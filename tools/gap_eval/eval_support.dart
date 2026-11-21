import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;
import 'package:masra/models/certification.dart';
import 'package:masra/models/gap_link.dart';
import 'package:masra/models/opportunity.dart';
import 'package:masra/services/career_analysis_pipeline.dart';
import 'package:masra/services/claude_service.dart' show AnalysisAi;
import 'package:masra/utils/skill_matcher.dart';

/// Shared helpers of the evaluation tools in this folder and of
/// tools/recommender_eval: reading the app's data files from disk, the AI
/// service with the key from `.env`, CSV sheets, hashes and statistics.
///
/// Nothing here imports Flutter or Firestore code, so the tools run with
/// plain `dart run` and can never write to the database.

const String opportunitiesPath = 'lib/assets/data/Masra_Opportunities.json';
const String certificationsPath = 'lib/assets/data/Masra_IT_Certifications.csv';
const String jobsPath =
    'lib/assets/data/Masra_Career_Analysis_Jobs_881_Title_Cleaned.csv';
const String careerPathsPath = 'lib/assets/data/careerPaths.json';

/// The date every evaluation ranks on (the same as
/// tools/recommender_eval/evaluate_recommender.dart), so the same files
/// always give the same lists.
final DateTime evalDate = DateTime(2026, 11, 19);

/// The career goals whose reported failures and development CVs the
/// developers saw. Their market names repeat between development and
/// held-out runs, so they are reported apart and never used to decide.
const Set<String> seenGoals = {'cybersecurity_analyst', 'data_analyst'};

Never fail(String message) {
  stderr.writeln(message);
  exit(1);
}

// ---------------------------------------------------------
// ARGUMENTS
// ---------------------------------------------------------

/// The command line of a tool. [known] lists every flag the tool reads; a
/// flag that is not in it stops the tool at once, so a typo such as
/// `--exclude-name` cannot silently drop a part of the run.
class Args {
  Args(this._args, {required Set<String> known}) {
    final unknown = [
      for (final arg in _args)
        if (arg.startsWith('--') && !known.contains(arg)) arg,
    ];
    if (unknown.isNotEmpty) {
      fail('Unknown option${unknown.length == 1 ? '' : 's'}: '
          '${unknown.join(', ')}.\nThis tool knows: '
          '${(known.toList()..sort()).join(', ')}.');
    }
  }
  final List<String> _args;

  bool has(String flag) => _args.contains(flag);

  String? value(String flag) {
    final index = _args.indexOf(flag);
    if (index < 0) return null;
    if (index + 1 >= _args.length) fail('$flag needs a value.');
    return _args[index + 1];
  }

  List<String> list(String flag) => [
        for (final part in (value(flag) ?? '').split(','))
          if (part.trim().isNotEmpty) part.trim(),
      ];

  int integer(String flag, int fallback) {
    final text = value(flag);
    if (text == null) return fallback;
    return int.tryParse(text) ?? fail('$flag needs a whole number.');
  }
}

// ---------------------------------------------------------
// THE APP'S DATA
// ---------------------------------------------------------

String readText(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('File not found: $path (run this from the project root).');
  }
  var text = file.readAsStringSync();
  if (text.startsWith('﻿')) text = text.substring(1);
  return text;
}

dynamic readJson(String path) {
  try {
    return jsonDecode(readText(path));
  } on FormatException catch (e) {
    fail('$path is not valid JSON: ${e.message}');
  }
}

void writeJson(String path, Object? value) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent(' ').convert(value));
}

List<Opportunity> loadOpportunities([String path = opportunitiesPath]) {
  final decoded = readJson(path);
  if (decoded is! List) fail('$path is not a JSON list.');
  return [
    for (final item in decoded)
      if (item is Map)
        Opportunity.fromMap('', Map<String, dynamic>.from(item)),
  ].where((o) => o.id.isNotEmpty && o.title.isNotEmpty).toList();
}

/// The certifications of the bundled CSV, read as the app reads them.
List<Certification> loadCertifications([String path = certificationsPath]) {
  final rows = Csv(autoDetect: false).decode(readText(path));
  if (rows.isEmpty) return [];
  final header = rows.first.map((v) => v.toString().trim()).toList();
  final result = <Certification>[];
  for (final row in rows.skip(1)) {
    if (row.length != header.length) continue;
    final map = <String, String>{
      for (var i = 0; i < header.length; i++)
        header[i]: row[i].toString().trim(),
    };
    if ((map['id'] ?? '').isNotEmpty) {
      result.add(Certification.fromCsvRow(map));
    }
  }
  return result;
}

/// career goal id -> name, from careerPaths.json.
Map<String, String> loadCareerNames() {
  final decoded = readJson(careerPathsPath);
  return {
    for (final item in decoded is List ? decoded : const [])
      if (item is Map && item['id'] != null)
        item['id'].toString(): item['name']?.toString() ?? item['id'].toString(),
  };
}

/// The catalogue names the pipeline works with, from the same data the
/// app bundles.
CatalogueNames loadCatalogueNames(
  List<Opportunity> opportunities,
  List<Certification> certifications,
) =>
    CatalogueNames(
      opportunityTags: {for (final o in opportunities) ...o.skills},
      certificationSkills: {for (final c in certifications) ...c.skills},
    );

// ---------------------------------------------------------
// THE AI SERVICE
// ---------------------------------------------------------

/// The app's AI service with the key of the local `.env` file.
///
/// The key is a compile-time constant in the app, which `dart run` cannot
/// set, so the file is read here: the single entry whose name ends in
/// `_API_KEY`. The key is handed to the service and nowhere else. It is
/// never printed, logged or written to a file, and neither are the names
/// in the file.
///
/// With a [meter], every request goes through it: it adds up the tokens
/// the answers report and stops everything at the first billing or credit
/// error.
AnalysisAi newAi({String envPath = '.env', UsageMeter? meter}) {
  final file = File(envPath);
  if (!file.existsSync()) {
    fail('No $envPath file. Copy .env.example to .env and add the API key.');
  }
  final keys = <String>[];
  for (final line in file.readAsLinesSync()) {
    final text = line.trim();
    if (text.isEmpty || text.startsWith('#')) continue;
    final at = text.indexOf('=');
    if (at <= 0) continue;
    if (!text.substring(0, at).trim().endsWith('_API_KEY')) continue;
    var value = text.substring(at + 1).trim();
    if (value.length >= 2 &&
        (value.startsWith('"') && value.endsWith('"') ||
            value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    if (value.isNotEmpty) keys.add(value);
  }
  if (keys.length != 1) {
    fail('Expected one API key entry in $envPath, found ${keys.length}.');
  }
  return AnalysisAi()
    ..apiKey = keys.single
    ..client = meter;
}

/// Thrown, and never retried, when the AI service refuses a request for a
/// billing or credit reason. Every later request of the same meter is
/// refused here, without being sent.
class CreditStop implements Exception {
  final String message;
  const CreditStop(this.message);

  @override
  String toString() => 'STOPPED, billing or credit error: $message';
}

/// An HTTP client for the evaluation tools that counts what the requests
/// cost. It reads the token counts each answer reports, so a tool can
/// print what it really spent, and it enforces the stop rule: after one
/// billing or credit error nothing more is sent.
class UsageMeter extends http.BaseClient {
  UsageMeter({this.inputPrice = 2, this.outputPrice = 10});

  /// USD per million tokens.
  final double inputPrice;
  final double outputPrice;

  final http.Client _inner = http.Client();
  int requests = 0;
  int inputTokens = 0;
  int outputTokens = 0;
  CreditStop? stopped;

  double get cost =>
      (inputTokens * inputPrice + outputTokens * outputPrice) / 1e6;

  String get summary => '$requests requests, $inputTokens input and '
      '$outputTokens output tokens, about ${cost.toStringAsFixed(3)} USD';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stop = stopped;
    if (stop != null) throw stop;
    final response = await _inner.send(request);
    final bytes = await response.stream.toBytes();
    requests++;
    final text = utf8.decode(bytes, allowMalformed: true);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        final usage = (jsonDecode(text) as Map)['usage'];
        if (usage is Map) {
          inputTokens += (usage['input_tokens'] as num?)?.toInt() ?? 0;
          outputTokens += (usage['output_tokens'] as num?)?.toInt() ?? 0;
        }
      } on Object {
        // An answer without readable counts is simply not counted.
      }
    } else {
      final lower = text.toLowerCase();
      if (response.statusCode == 402 ||
          lower.contains('credit') ||
          lower.contains('billing')) {
        throw stopped = CreditStop('HTTP ${response.statusCode}');
      }
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: response.request,
    );
  }

  @override
  void close() => _inner.close();
}

/// The text of a link request as the app sends it.
String linkPromptOf(
  LinkRequest request,
  List<String> skills,
  List<String> concepts,
) =>
    request == LinkRequest.typed
        ? AnalysisAi.typedSkillLinkPrompt(skills: skills, concepts: concepts)
        : AnalysisAi.skillLinkPrompt(skills: skills, concepts: concepts);

/// A rough token count of a text (about four characters per token), for
/// the estimate a tool prints before it sends anything.
int roughTokens(String text) => (text.length / 4).ceil();

/// The texts of the new requests, with placeholders where the inputs go
/// (file name -> text). The text of the arm that left the app
/// (gap_verification.txt in tools/gap_eval/arms/) is no longer in the
/// source: that file is its only copy, and --export-prompts never writes
/// it. The catalogue names of the link requests are a placeholder too:
/// they are read from the app's data at run time.
Map<String, String> promptTexts() => {
      'skill_links.txt': AnalysisAi.skillLinkPrompt(
        skills: const ['{{MARKET_SKILLS}}'],
        concepts: const ['{{CATALOGUE_SKILL_NAMES}}'],
      ),
      'skill_links_typed.txt': AnalysisAi.typedSkillLinkPrompt(
        skills: const ['{{MARKET_SKILLS}}'],
        concepts: const ['{{CATALOGUE_SKILL_NAMES}}'],
      ),
      'single_skill_rule.txt': AnalysisAi.singleSkillRule,
      'cv_evidence_check.txt': AnalysisAi.skillEvidencePrompt(
        cvText: '{{CV_TEXT}}',
        currentSkills: const ['{{CURRENT_SKILLS}}'],
        certifications: const ['{{CERTIFICATIONS_HELD}}'],
        targetSkills: const ['{{TARGET_SKILLS}}'],
      ),
    };

/// The text of an arm in tools/gap_eval/arms/ with its inputs filled in.
/// Each `["{{NAME}}"]` placeholder named in [lists] becomes that JSON list,
/// as the app wrote it, and {{CV_TEXT}} becomes [cvText]. The CV goes in
/// last, so nothing in it is ever taken for a placeholder.
String filledArm(
  String fileName, {
  required String cvText,
  Map<String, List<String>> lists = const {},
}) {
  var text = readText('tools/gap_eval/arms/$fileName')
      .replaceAll('\r\n', '\n');
  lists.forEach((name, values) {
    final placeholder = '["{{$name}}"]';
    if (!text.contains(placeholder)) fail('$fileName has no $placeholder.');
    text = text.replaceAll(placeholder, jsonEncode(values));
  });
  if (!text.contains('{{CV_TEXT}}')) fail('$fileName has no {{CV_TEXT}}.');
  return text.replaceAll('{{CV_TEXT}}', cvText);
}

/// Runs [tasks] with at most [concurrency] at the same time.
Future<void> runPool(
  List<Future<void> Function()> tasks, {
  int concurrency = 3,
  void Function(int done, int total)? onProgress,
}) async {
  var next = 0;
  var done = 0;
  Future<void> worker() async {
    while (next < tasks.length) {
      final task = tasks[next++];
      await task();
      onProgress?.call(++done, tasks.length);
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
}

// ---------------------------------------------------------
// CSV SHEETS
// ---------------------------------------------------------

String csvCell(String value) {
  final flat = value.replaceAll('\r', ' ').replaceAll('\n', ' ');
  return flat.contains(',') || flat.contains('"')
      ? '"${flat.replaceAll('"', '""')}"'
      : flat;
}

void writeCsv(String path, List<String> header, List<List<String>> rows) {
  final buffer = StringBuffer()..writeln(header.map(csvCell).join(','));
  for (final row in rows) {
    buffer.writeln(row.map(csvCell).join(','));
  }
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(buffer.toString());
}

/// The rows of a CSV sheet as column name -> value. A missing file stops
/// the tool with its path: a sheet named on the command line that is not
/// there (a typo, or a path the shell changed) must never be read as a
/// sheet without rows, which would drop its grades without a word. Only a
/// file the tool looks for by itself, which may well not exist yet, is
/// read with [optional], and then a missing file gives no rows.
List<Map<String, String>> readCsv(String path, {bool optional = false}) {
  final file = File(path);
  if (!file.existsSync()) {
    if (optional) return [];
    fail('File not found: $path. Check the path (in Git Bash, a list of '
        'Windows paths separated by commas can be changed by the shell; '
        'use forward slashes from the project root, or PowerShell).');
  }
  var text = file.readAsStringSync();
  if (text.startsWith('﻿')) text = text.substring(1);
  final rows = Csv(autoDetect: false).decode(text);
  if (rows.isEmpty) return [];
  final header = rows.first.map((v) => v.toString().trim()).toList();
  return [
    for (final row in rows.skip(1))
      if (row.any((cell) => cell.toString().trim().isNotEmpty))
        {
          for (var i = 0; i < header.length && i < row.length; i++)
            header[i]: row[i].toString().trim(),
        },
  ];
}

// ---------------------------------------------------------
// HASHES
// ---------------------------------------------------------

/// SHA-256 of [bytes] as hex. Written out here so the tools need no
/// package that the app does not already depend on.
String sha256Hex(List<int> bytes) {
  const k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  const mask = 0xffffffff;
  int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & mask;

  final length = bytes.length;
  final padded = BytesBuilder()
    ..add(bytes)
    ..addByte(0x80);
  while (padded.length % 64 != 56) {
    padded.addByte(0);
  }
  final bits = ByteData(8)..setUint64(0, length * 8);
  padded.add(bits.buffer.asUint8List());
  final data = ByteData.sublistView(padded.toBytes());

  final h = <int>[
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  final w = List<int>.filled(64, 0);
  for (var offset = 0; offset < data.lengthInBytes; offset += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = data.getUint32(offset + i * 4);
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & mask;
    }
    var a = h[0], b = h[1], c = h[2], d = h[3];
    var e = h[4], f = h[5], g = h[6], hh = h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ ((~e & mask) & g);
      final t1 = (hh + s1 + ch + k[i] + w[i]) & mask;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & mask;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & mask;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & mask;
    }
    h[0] = (h[0] + a) & mask;
    h[1] = (h[1] + b) & mask;
    h[2] = (h[2] + c) & mask;
    h[3] = (h[3] + d) & mask;
    h[4] = (h[4] + e) & mask;
    h[5] = (h[5] + f) & mask;
    h[6] = (h[6] + g) & mask;
    h[7] = (h[7] + hh) & mask;
  }
  return [for (final part in h) part.toRadixString(16).padLeft(8, '0')].join();
}

String sha256OfText(String text) =>
    sha256Hex(utf8.encode(text.replaceAll('\r\n', '\n')));

/// One hash for all files under [folder] with one of the [extensions],
/// by relative path, whatever the line endings. [skip] leaves out
/// sub-folders by name.
String sha256OfFolder(
  String folder, {
  List<String> extensions = const ['.dart'],
  Set<String> skip = const {},
}) {
  final directory = Directory(folder);
  if (!directory.existsSync()) return 'missing';
  final root = directory.absolute.path.replaceAll('\\', '/');
  final lines = <String>[];
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = entity.absolute.path.replaceAll('\\', '/');
    final relative = path.substring(root.length).replaceFirst(RegExp('^/'), '');
    if (relative.split('/').any(skip.contains)) continue;
    if (!extensions.any(relative.endsWith)) continue;
    String content;
    try {
      content = sha256OfText(entity.readAsStringSync());
    } on FileSystemException {
      content = sha256Hex(entity.readAsBytesSync());
    }
    lines.add('$relative $content');
  }
  lines.sort();
  return sha256Hex(utf8.encode(lines.join('\n')));
}

// ---------------------------------------------------------
// STATISTICS
// ---------------------------------------------------------

double meanOf(Iterable<double> values) {
  var sum = 0.0;
  var count = 0;
  for (final value in values) {
    sum += value;
    count++;
  }
  return count == 0 ? 0 : sum / count;
}

/// The 95% interval of a statistic by bootstrap: [resample] is called
/// [rounds] times with a random generator and returns the statistic of one
/// resample (or null to skip it).
({double low, double high}) bootstrapInterval(
  double? Function(Random random) resample, {
  int rounds = 10000,
  int seed = 20261119,
}) {
  final random = Random(seed);
  final values = <double>[];
  for (var i = 0; i < rounds; i++) {
    final value = resample(random);
    if (value != null) values.add(value);
  }
  if (values.isEmpty) return (low: double.nan, high: double.nan);
  values.sort();
  double at(double share) =>
      values[(share * (values.length - 1)).round().clamp(0, values.length - 1)];
  return (low: at(0.025), high: at(0.975));
}

/// Mean Jaccard similarity of every pair of [sets] (1 when there is only
/// one, or when all are empty).
double meanPairwiseJaccard(List<Set<String>> sets) {
  final values = <double>[];
  for (var i = 0; i < sets.length; i++) {
    for (var j = i + 1; j < sets.length; j++) {
      final union = sets[i].union(sets[j]).length;
      values.add(
          union == 0 ? 1.0 : sets[i].intersection(sets[j]).length / union);
    }
  }
  return values.isEmpty ? 1.0 : meanOf(values);
}

/// Cohen's kappa for two raters' labels of the same items. With
/// [weighted], labels are numbers and a disagreement counts by its
/// distance (linear weights).
double cohenKappa(List<int> a, List<int> b, {bool weighted = false}) {
  if (a.isEmpty || a.length != b.length) return double.nan;
  final labels = {...a, ...b}.toList()..sort();
  if (labels.length < 2) return 1;
  final n = a.length;
  final span = (labels.last - labels.first).toDouble();
  double weight(int x, int y) =>
      weighted ? 1 - (x - y).abs() / span : (x == y ? 1.0 : 0.0);
  var observed = 0.0;
  for (var i = 0; i < n; i++) {
    observed += weight(a[i], b[i]);
  }
  observed /= n;
  var expected = 0.0;
  for (final x in labels) {
    for (final y in labels) {
      final px = a.where((v) => v == x).length / n;
      final py = b.where((v) => v == y).length / n;
      expected += px * py * weight(x, y);
    }
  }
  return expected >= 1 ? 1 : (observed - expected) / (1 - expected);
}

String f3(double value) => value.isNaN ? '  n/a' : value.toStringAsFixed(3);

String signed3(double value) => value.isNaN
    ? '  n/a'
    : '${value >= 0 ? '+' : ''}${value.toStringAsFixed(3)}';

String keyOf(String name) => SkillMatcher.normalize(name);

/// A file-name-safe form of an id or a name.
String slug(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
