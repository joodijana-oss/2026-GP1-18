import 'dart:io';

import 'package:masra/models/gap_link.dart';

import 'eval_support.dart';

/// One CV of a test set with the writer's labels.
class EvalCase {
  final String id;
  final String goalId;
  final String level;
  final String cvText;

  /// normalized skill name (or other name of it) -> shown, partly or
  /// not_shown, from the labels file and the role skills.
  final Map<String, String> statusByName;

  /// normalized name -> the label's own skill name.
  final Map<String, String> labelSkillByName;

  const EvalCase({
    required this.id,
    required this.goalId,
    required this.level,
    required this.cvText,
    required this.statusByName,
    required this.labelSkillByName,
  });

  bool get seenGoal => seenGoals.contains(goalId);
}

/// A reviewer's answer for one (case, name) pair of the names sheet.
class NameJudgement {
  final String status;
  final bool? bundled;
  const NameJudgement(this.status, this.bundled);
}

/// A test set folder: manifest.json, the CVs, their labels, roles.json
/// (optional) and the reviewers' answers under judgements/.
///
/// The format is the one of the test set spec. The tools only read these
/// files; the people who build the feature never open a held-out folder
/// themselves.
class EvalSet {
  final String folder;

  /// `heldout` or `dev`, from the manifest.
  final String name;
  final List<EvalCase> cases;

  /// (case id, normalized name) -> the reviewer's answer.
  final Map<String, NameJudgement> judgements;

  const EvalSet(this.folder, this.name, this.cases, this.judgements);

  static String judgementKey(String caseId, String name) =>
      '$caseId|${keyOf(name)}';

  String get namesSheet => '$folder/judgements/names.csv';
  String get namesSecondSheet => '$folder/judgements/names_second.csv';
  String get teachingSheet => '$folder/judgements/teaching.csv';
  String get teachingSecondSheet => '$folder/judgements/teaching_second.csv';

  factory EvalSet.load(String folder) {
    final root = folder.replaceAll('\\', '/').replaceFirst(RegExp(r'/+$'), '');
    final manifest = readJson('$root/manifest.json');
    if (manifest is! Map || manifest['cases'] is! List) {
      fail('$root/manifest.json has no "cases" list.');
    }
    final rolesFile = File('$root/roles.json');
    final roles = rolesFile.existsSync() ? readJson(rolesFile.path) : null;

    final cases = <EvalCase>[];
    for (final item in manifest['cases'] as List) {
      if (item is! Map) continue;
      final id = item['id'].toString();
      final goalId = item['careerGoalId'].toString();
      final labels = readJson('$root/${item['labels']}');
      if (labels is! Map) fail('$root/${item['labels']} is not an object.');

      final status = <String, String>{};
      final labelSkill = <String, String>{};
      void add(dynamic entries, String value) {
        for (final entry in entries is List ? entries : const []) {
          if (entry is! Map) continue;
          final skill = entry['skill']?.toString() ?? '';
          final also = entry['alsoCalled'];
          for (final name in [skill, ...(also is List ? also : const [])]) {
            final key = keyOf(name.toString());
            if (key.isEmpty) continue;
            status.putIfAbsent(key, () => value);
            labelSkill.putIfAbsent(key, () => skill);
          }
        }
      }

      // The skill's own names first, so another skill's "also called"
      // name never overrides them.
      for (final pass in [false, true]) {
        for (final entry in const [
          ['shown', 'shown'],
          ['partly', 'partly'],
          ['notShown', 'not_shown'],
        ]) {
          final entries = labels[entry[0]];
          if (!pass) {
            for (final e in entries is List ? entries : const []) {
              if (e is! Map) continue;
              final skill = e['skill']?.toString() ?? '';
              final key = keyOf(skill);
              if (key.isEmpty) continue;
              status.putIfAbsent(key, () => entry[1]);
              labelSkill.putIfAbsent(key, () => skill);
            }
          } else {
            add(entries, entry[1]);
          }
        }
      }
      // The other names of the role skills point to the same label.
      final roleSkills = roles is Map ? roles[goalId] : null;
      for (final role in roleSkills is List ? roleSkills : const []) {
        if (role is! Map) continue;
        final also = role['alsoCalled'];
        final names = [
          role['skill']?.toString() ?? '',
          for (final name in also is List ? also : const []) name.toString(),
        ].map(keyOf).where((key) => key.isNotEmpty).toList();
        final known = names.where(status.containsKey).toList();
        if (known.isEmpty) continue;
        for (final key in names) {
          status.putIfAbsent(key, () => status[known.first]!);
          labelSkill.putIfAbsent(key, () => labelSkill[known.first]!);
        }
      }

      cases.add(EvalCase(
        id: id,
        goalId: goalId,
        level: item['level']?.toString() ?? '',
        cvText: readText('$root/${item['cv']}'),
        statusByName: status,
        labelSkillByName: labelSkill,
      ));
    }
    if (cases.isEmpty) fail('$root/manifest.json lists no case.');

    final judgements = <String, NameJudgement>{};
    // The reviewers' sheet does not exist before the first review.
    for (final row in readCsv('$root/judgements/names.csv', optional: true)) {
      final status = (row['status'] ?? '').toLowerCase().replaceAll(' ', '_');
      if (!const {'shown', 'partly', 'not_shown'}.contains(status)) continue;
      final bundled = (row['bundled'] ?? '').toLowerCase();
      judgements[judgementKey(row['case_id'] ?? '', row['name'] ?? '')] =
          NameJudgement(
        status,
        bundled == 'yes' ? true : (bundled == 'no' ? false : null),
      );
    }
    return EvalSet(root, manifest['set']?.toString() ?? '', cases, judgements);
  }

  /// shown, partly, not_shown, or null when nobody has judged the name
  /// for this CV yet.
  String? statusOf(EvalCase c, String name) =>
      c.statusByName[keyOf(name)] ??
      judgements[judgementKey(c.id, name)]?.status;

  /// Whether a reviewer marked the name as bundled. A name that maps to a
  /// label is a single skill by the rules of the labels. Null when nobody
  /// has judged it yet.
  bool? bundledOf(EvalCase c, String name) {
    if (c.statusByName.containsKey(keyOf(name))) return false;
    return judgements[judgementKey(c.id, name)]?.bundled;
  }

  List<String> get goals => {for (final c in cases) c.goalId}.toList();
}

/// The primary skill names ("skill", never "alsoCalled") the writers of a
/// set defined, per career goal, in the order the files give them: first
/// the label file of every case of the manifest, then the role file
/// (stratum W of the final matching measurement).
Map<String, List<String>> writerNamesOf(String folder) {
  final result = <String, List<String>>{};
  void add(String goal, dynamic entries) {
    if (goal.isEmpty) return;
    for (final entry in entries is List ? entries : const []) {
      final skill = entry is Map ? entry['skill']?.toString().trim() ?? '' : '';
      if (skill.isEmpty) continue;
      final list = result[goal] ??= [];
      if (!list.any((name) => keyOf(name) == keyOf(skill))) list.add(skill);
    }
  }

  final manifestFile = File('$folder/manifest.json');
  final manifest = manifestFile.existsSync() ? readJson(manifestFile.path) : null;
  final cases = manifest is Map ? manifest['cases'] : null;
  for (final item in cases is List ? cases : const []) {
    if (item is! Map) continue;
    final labelsFile =
        File('$folder/${item['labels'] ?? '${item['id']}.labels.json'}');
    if (!labelsFile.existsSync()) continue;
    final labels = readJson(labelsFile.path);
    if (labels is! Map) continue;
    for (final part in const ['shown', 'partly', 'notShown']) {
      add(item['careerGoalId']?.toString() ?? '', labels[part]);
    }
  }
  final rolesFile = File('$folder/roles.json');
  if (rolesFile.existsSync()) {
    final roles = readJson(rolesFile.path);
    if (roles is Map) {
      roles.forEach((goal, entries) => add(goal.toString(), entries));
    }
  }
  return result;
}

/// One arm of the gap evaluation: a gap method (G0 names only, the app's
/// fallback; G1 CV evidence, what the app runs; G2 names then verified,
/// which left the app and runs from its text in tools/gap_eval/arms/) and
/// an extractor (E0 market names as they come, E1 single-skill names).
class Arm {
  final String id;
  final int gapMethod;
  final int extractor;
  const Arm(this.id, this.gapMethod, this.extractor);

  static final RegExp _pattern = RegExp(r'^G([012])E([01])$');

  factory Arm.parse(String text) {
    final match = _pattern.firstMatch(text.trim().toUpperCase());
    if (match == null) fail('Unknown arm "$text" (use G0E0, G0E1, G1E1, G2E1).');
    return Arm(text.trim().toUpperCase(), int.parse(match.group(1)!),
        int.parse(match.group(2)!));
  }

  String get extractorId => 'E$extractor';
}

/// What one gap request of the evaluation produced.
class GapRecord {
  final List<String> gaps;
  final String method;
  final bool usedFallback;
  final int unverifiedQuotes;
  final int checkedSkills;
  final String? error;

  const GapRecord({
    required this.gaps,
    required this.method,
    required this.usedFallback,
    required this.unverifiedQuotes,
    required this.checkedSkills,
    this.error,
  });
}

/// The files of one evaluation run (build/gap_eval/`name`).
class RunFolder {
  RunFolder(String path)
      : path = path.replaceAll('\\', '/').replaceFirst(RegExp(r'/+$'), '');

  final String path;

  String get configPath => '$path/config.json';
  String analyzePath(String caseId, int run) =>
      '$path/raw/analyze/${caseId}_r$run.json';
  String marketPath(String goal, String extractor, int run) =>
      '$path/raw/market/${goal}_${extractor}_r$run.json';
  String gapsPath(String caseId, String arm, int run) =>
      '$path/raw/gaps/${caseId}_${arm}_r$run.json';

  /// The folder of the stored answers of one link request: raw/links for
  /// the first request, raw/links_typed for the typed one.
  String linksFolder(LinkRequest request) =>
      request == LinkRequest.names ? '$path/raw/links' : '$path/raw/links_typed';

  /// The stored link answer of one list. [list] is the extractor of a
  /// market list ("E1"), or the id of a list of writer names ("W1").
  String linksPath(
    String goal,
    String list,
    int run, {
    LinkRequest request = LinkRequest.names,
  }) =>
      '${linksFolder(request)}/${goal}_${list}_r$run.json';

  /// The skill names the writers of the set defined, per career goal
  /// (stratum W of the final measurement), as final_matching.dart stored
  /// them. Empty when the run has none.
  Map<String, List<String>> get writerNames {
    final data = _read('$path/raw/writer_names.json');
    return {
      for (final entry in (data ?? const {}).entries)
        if (entry.value is List) entry.key: _strings(entry.value),
    };
  }

  Map<String, dynamic> get config {
    final decoded = readJson(configPath);
    if (decoded is! Map) fail('$configPath is not an object.');
    return Map<String, dynamic>.from(decoded);
  }

  static Map<String, dynamic>? _read(String path) {
    if (!File(path).existsSync()) return null;
    final decoded = readJson(path);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  static List<String> _strings(dynamic raw) =>
      [for (final v in raw is List ? raw : const []) v.toString()];

  Map<String, dynamic>? analysis(String caseId, int run) =>
      _read(analyzePath(caseId, run))?['cvAnalysis'] as Map<String, dynamic>?;

  /// The market skills of one request after cleaning, or null when the
  /// request has no stored answer.
  List<String>? market(String goal, String extractor, int run) {
    final data = _read(marketPath(goal, extractor, run));
    return data == null || data['error'] != null
        ? null
        : _strings(data['names']);
  }

  List<String>? rawMarket(String goal, String extractor, int run) {
    final data = _read(marketPath(goal, extractor, run));
    return data == null || data['error'] != null
        ? null
        : _strings(data['rawNames']);
  }

  /// The links of one link request, or null when it failed or never ran.
  List<GapLink>? links(
    String goal,
    String list,
    int run, {
    LinkRequest request = LinkRequest.names,
  }) {
    final data = _read(linksPath(goal, list, run, request: request));
    if (data == null || data['links'] is! List) return null;
    return GapLink.listFrom(data['links']);
  }

  /// Every stored link answer of [goal] for [request], by list id and run
  /// ("E1_r2", "W1_r3").
  Map<String, List<GapLink>> linkAnswers(String goal, LinkRequest request) {
    final folder = Directory(linksFolder(request));
    if (!folder.existsSync()) return const {};
    final result = <String, List<GapLink>>{};
    final pattern = RegExp('^${RegExp.escape(goal)}_([A-Z][0-9]+_r[0-9]+)'
        r'\.json$');
    final files = folder.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final name = file.path.replaceAll('\\', '/').split('/').last;
      final match = pattern.firstMatch(name);
      if (match == null) continue;
      final data = _read(file.path);
      if (data == null || data['links'] is! List) continue;
      result[match.group(1)!] = GapLink.listFrom(data['links']);
    }
    return result;
  }

  /// The career goals that have a stored market list of [extractor].
  List<String> marketGoals(String extractor) {
    final folder = Directory('$path/raw/market');
    if (!folder.existsSync()) return const [];
    final pattern = RegExp('^(.+)_${extractor}_r[0-9]+\\.json\$');
    final goals = <String>{};
    for (final file in folder.listSync().whereType<File>()) {
      final name = file.path.replaceAll('\\', '/').split('/').last;
      final match = pattern.firstMatch(name);
      if (match != null) goals.add(match.group(1)!);
    }
    return goals.toList()..sort();
  }

  /// The run numbers of the stored market lists of one goal.
  List<int> marketRuns(String goal, String extractor) {
    final runs = <int>[];
    for (var r = 1; r <= 99; r++) {
      if (File(marketPath(goal, extractor, r)).existsSync()) runs.add(r);
    }
    return runs;
  }

  GapRecord? gaps(String caseId, String arm, int run) {
    final data = _read(gapsPath(caseId, arm, run));
    if (data == null) return null;
    final statuses = data['statuses'];
    return GapRecord(
      gaps: _strings(data['gaps']),
      method: data['method']?.toString() ?? '',
      usedFallback: data['usedFallback'] == true,
      unverifiedQuotes: (data['unverifiedQuotes'] as num?)?.toInt() ?? 0,
      checkedSkills: statuses is List ? statuses.length : 0,
      error: data['error']?.toString(),
    );
  }
}
