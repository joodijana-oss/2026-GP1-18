import 'dart:io';
import 'dart:math';

import 'package:masra/models/certification.dart';
import 'package:masra/models/gap_link.dart';
import 'package:masra/models/opportunity.dart';
import 'package:masra/services/content_based_recommender.dart';
import 'package:masra/services/opportunity_index.dart';
import 'package:masra/services/opportunity_recommender.dart';
import 'package:masra/utils/skill_matcher.dart';

import 'approaches.dart';
import 'decision_rules.dart';
import 'eval_data.dart';
import 'eval_support.dart';
import 'freeze_r2.dart';
import 'link_requests.dart' show exclusionKeys;
import 'text_probes.dart';
import 'word_control.dart';

/// Evaluation of matching by meaning (task 4). Offline: it makes no AI
/// request. It reads the market skill names and the link answers stored in
/// run folders, runs the app's own recommenders on them once per approach,
/// and scores the result against the reviewers' grades.
///
/// The approaches and their ids are described in approaches.dart.
///
/// Test names: every market skill name of the runs, per career goal (and,
/// with --writer-names, the skill names the writers of a set defined). The
/// scores are computed on the hole names: names whose own words find no
/// skill of the catalogue. Only there can the approaches differ; for every
/// other name all of them give today's result (a unit test proves it).
///
/// Steps, from the project root:
///
///   --pool    writes `out`/teaching_review.csv: for every hole name, the
///             first 5 items each approach attributes to it, plus the 5
///             best items of two crude searches, without saying which
///             approach found what, and only the pairs that have no grade
///             yet. Rows are grouped by (name, catalogue) with the items
///             shuffled, and every row carries the full item text. The
///             reviewers grade each pair: 2 = teaches the skill as a main
///             topic, 1 = as a clear part, 0 = no.
///   --score   prints, per approach:
///               TeachHit@5      of the hole names that some item teaches,
///                               the share where one of the first 5 items
///                               attributed to the name teaches it;
///               AttribPrec@5    of the first 5 items attributed to hole
///                               names, the share that teach the name: how
///                               often the reason on a card is right;
///               FalseUncovered  of the hole names that some item teaches,
///                               the share the approach finds nothing for.
///   --select  (with --score) the development selection: which settings of
///             --grid are eligible, best first.
///   --decision (with --pool or --score) the final measurement: the freeze
///             is checked first, the decision names are the market names
///             of the frozen decision goals and, when the freeze says so,
///             the writers' names (--writer-names must then be passed, and
///             must not be otherwise), the first run folder must hold the
///             run.json final_matching.dart wrote under this freeze, every
///             graded sheet must lie in its judgements folder, nothing is
///             written into build/gap_eval/final_r2, and --score applies
///             the decision rules.
///   --whole-lists (with --score, development only) ranks every stored
///             market list as one analysis, as the app does, and counts
///             the gaps the links cover on their own that end up on no
///             opportunity card and not in the "nothing covers" notice.
///
/// The controls are always added, so their items are pooled and graded
/// too: today's matching (A0), in development round 1's ungated links
/// (M1), and the gated word control of every approach with links
/// ("L1g~id"). "L1g" alone in --approaches stands for those controls.
///
/// Options:
///   --runs `folders`        run folders (build/gap_eval/...), comma separated
///   --extractors `list`     market lists to read (default E1, what the app
///                           runs)
///   --goals `list`          only these career goals
///   --writer-names          also the writers' skill names of the run
///                           (raw/writer_names.json)
///   --names-from `file`     only the names of this graded sheet (round 1's
///                           sample is the names of its teaching sheet)
///   --exclude-names `file`  leave out the names listed there (the names
///                           seen in development); with --decision it is
///                           required and must be the frozen list
///   --grades `files`        graded sheets, comma separated; the first grade
///                           of a pair counts
///   --second `file`         a second rater's sheet, for the agreement
///   --approaches `list`     default A0,L1,M1 (with --decision: A0, L1 and
///                           the frozen candidates); with --decision only
///                           frozen candidates and controls are accepted
///   --grid `families`       add every setting of the family (A, B or A,B)
///   --decision-goals `list` with --decision: must be the frozen decision
///                           goals (they are read from the freeze anyway)
///   --freeze-file `file`    with --decision (default
///                           tools/gap_eval/freeze_r2.json)
///   --guards `files`        with --decision --score: the guard files that
///                           evaluate_recommender.dart --guard-json wrote
///                           under this freeze, one per frozen persona
///                           file. They must lie in the guards folder of
///                           the first run folder, which may hold one
///                           guard file per persona file at most. Without
///                           them no winner is named.
///   --timing `files`        with --decision --score --guards, when the
///                           freeze has the amendment of rule 7.2 (d)
///                           (freeze_r2_amendment_timing.json): the two
///                           timing files it names, which
///                           timing_amendment.dart --measure wrote. Rule
///                           7.2 (d) is then read from the medians of
///                           their 5 runs, the guard files must be the two
///                           the amendment recorded, and their single-run
///                           ratios are reported only.
///   --out `folder`        where --pool and --score write (default the
///                           first run folder)
///   --max-names `n`         at most this many hole names (default: all);
///                           more are sampled per stratum and career goal
///   --seed `n`              seed of that sample (default 20261121)
///   --dump `approach`       also print what the approach attributes to
///                           every hole name, with the grades
const int topK = 5;
const List<String> types = ['opportunity', 'certification'];

const List<String> teachingHeader = [
  'row_id', 'career_goal_id', 'gap', 'item_type', 'item_id', 'item_title',
  'item_text', 'grade', 'note',
];

void main(List<String> arguments) {
  final args = Args(arguments, known: const {
    '--approaches', '--decision', '--decision-goals', '--dump',
    '--exclude-names', '--extractors', '--freeze-file', '--goals',
    '--grades', '--grid', '--guards', '--max-names', '--names-from', '--out',
    '--pool',
    '--runs', '--score', '--second', '--seed', '--select', '--timing',
    '--whole-lists', '--writer-names',
  });
  final runs = args.list('--runs');
  if (runs.isEmpty) fail('Pass --runs <folder[,folder]>.');
  final decision = args.has('--decision');

  // The final measurement works only on what the freeze fixed: the
  // candidates, the decision goals and the exclusion list.
  Map<String, dynamic>? frozen;
  if (decision) {
    final freezeFile = args.value('--freeze-file') ?? defaultFreezeFile;
    frozen = checkFreeze(freezeFile);
    stdout.writeln('The freeze matches ($freezeFile).');
    final amended = amendmentLine(freezeFile);
    if (amended != null) stdout.writeln(amended);
    final excludePath = args.value('--exclude-names') ??
        fail('With --decision, pass --exclude-names with the frozen '
            'exclusion list ($exclusionFile).');
    if (sha256OfText(readText(excludePath)) !=
        '${(frozen['hashes'] as Map)['exclusionList']}') {
      fail('$excludePath is not the frozen exclusion list.');
    }
    if (args.has('--grid')) fail('--grid is for development only.');
    final asked = args.list('--decision-goals').toSet();
    final fixed = frozenList(frozen, 'decisionGoals').toSet();
    if (asked.isNotEmpty &&
        (asked.length != fixed.length || !asked.containsAll(fixed))) {
      fail('--decision-goals must be the frozen decision goals: '
          '${fixed.join(',')}.');
    }
    final problem = decisionInputProblem(
          frozen,
          writerNames: args.has('--writer-names'),
          runFolder: runs.first,
          freezeSha: freezeShaOf(freezeFile),
          sheets: [...args.list('--grades'), ...args.list('--second')],
        ) ??
        earlierRunWriteProblem(args.value('--out') ?? runs.first);
    if (problem != null) fail(problem);
  } else {
    for (final flag in const [
      '--decision-goals', '--freeze-file', '--guards', '--timing',
    ]) {
      if (args.has(flag)) fail('$flag belongs to --decision.');
    }
  }

  final frozenCandidates =
      frozen == null ? const <String>[] : frozenList(frozen, 'candidates');
  final ids = args.list('--approaches').isEmpty
      ? (decision ? ['A0', 'L1', ...frozenCandidates] : const ['A0', 'L1', 'M1'])
      : args.list('--approaches');
  final listed = <Approach>[
    // "L1g" alone: the gated word controls, which are added below anyway.
    for (final id in ids)
      if (id != 'L1g') Approach.parse(id),
    for (final family in args.list('--grid')) ...Approach.grid(family),
  ];
  if (decision) {
    if (listed.any((approach) => approach.id == Approach.appId)) {
      fail('${Approach.appId} is the check of the shipped code, not a '
          'frozen candidate: it is scored without --decision.');
    }
    final notFrozen = [
      for (final approach in listed)
        if (!isControl(approach) && !frozenCandidates.contains(approach.id))
          approach.id,
    ];
    if (notFrozen.isNotEmpty) {
      fail('Not frozen candidates: ${notFrozen.join(', ')}. The decision '
          'scores only the frozen candidates (${frozenCandidates.join(', ')}) '
          'and the controls.');
    }
    for (final id in frozenCandidates) {
      if (!listed.any((approach) => approach.id == id)) {
        stdout.writeln('Frozen candidate $id added to the approaches.');
        listed.add(Approach.parse(id));
      }
    }
  }
  final approaches = withControls(listed, development: !decision);

  // The guards (rules 7.2 a, b and d) of every frozen candidate, from the
  // files the guard tool wrote under this freeze.
  Map<String, GuardVerdict>? guards;
  // The amendment of rule 7.2 (d), when the freeze has one: checkFreeze has
  // checked it. With it, the guards are read together with the timing
  // files it names.
  final amendment = decision
      ? readAmendment(args.value('--freeze-file') ?? defaultFreezeFile)
      : null;
  if (decision) {
    final problem = timingInputProblem(
      amended: amendment != null,
      hasGuards: args.has('--guards'),
      hasTiming: args.has('--timing'),
      amendmentFile:
          amendmentFileOf(args.value('--freeze-file') ?? defaultFreezeFile),
    );
    if (problem != null) fail('$problem\nNothing was scored.');
  }
  if (decision && args.has('--guards')) {
    if (!args.has('--score')) fail('--guards belongs to --score.');
    final freezeFile = args.value('--freeze-file') ?? defaultFreezeFile;
    final where = guardInputProblem(
        [...args.list('--guards'), ...args.list('--timing')],
        runFolder: runs.first);
    if (where != null) fail('$where\nNothing was scored.');
    // Rule 7.2 (d) as amended: the timing files of every frozen candidate,
    // by persona file. Null without an amendment.
    Map<String, Map<String, Map<String, dynamic>>>? timingFiles;
    if (amendment != null) {
      final amendmentSha = amendmentShaOf(freezeFile);
      final timingRead = <String, Map<String, dynamic>>{};
      final unusable = <String>[
        ...amendedGuardsFolderProblems(guardsFolderOf(runs.first), amendment),
        ...amendedGuardProblems(args.list('--guards'), amendment),
      ];
      for (final path in args.list('--timing')) {
        final content = timingJsonOf(path);
        if (content == null) {
          unusable.add('$path is missing or is not a JSON object');
        } else {
          timingRead[path] = content;
        }
      }
      if (unusable.isEmpty) {
        final found = amendedTimingFor(
          [for (final id in frozenCandidates) Approach.parse(id)],
          timingRead,
          frozen: frozen!,
          freezeSha: freezeShaOf(freezeFile),
          amendment: amendment,
          amendmentSha: amendmentSha,
        );
        unusable.addAll(found.problems);
        timingFiles = found.files;
      }
      if (unusable.isNotEmpty) {
        fail('The guard files and the timing files of the amended rule 7.2 '
            '(d) cannot be used:\n  ${unusable.toSet().join('\n  ')}\n'
            'Nothing was scored.');
      }
    }
    final read = <String, Map<String, dynamic>>{
      for (final path in args.list('--guards'))
        path: Map<String, dynamic>.from(readJson(path) as Map),
    };
    final rule = frozenGuard(frozen!);
    final problems = <String>{};
    final files = <String, List<Map<String, dynamic>>>{};
    for (final id in frozenCandidates) {
      final found = guardFilesFor(Approach.parse(id), read,
          frozen: frozen, freezeSha: freezeShaOf(freezeFile));
      problems.addAll(found.problems);
      files[id] = found.files;
    }
    if (problems.isNotEmpty) {
      fail('The guard files cannot be used:\n  ${problems.join('\n  ')}\n'
          'Nothing was scored.');
    }
    guards = {
      for (final id in frozenCandidates)
        id: guardVerdictOf(files[id]!,
            decimals: rule.decimals,
            tolerance: rule.tolerance,
            amendedTiming: timingFiles?[id]),
    };
  }

  final evaluation = _Evaluation(
    runs: [for (final path in runs) RunFolder(path)],
    extractors: args.list('--extractors').isEmpty
        ? const ['E1']
        : args.list('--extractors'),
    goals: args.list('--goals').toSet(),
    writerNames: args.has('--writer-names'),
    excludePath: args.value('--exclude-names'),
    namesFromPath: args.value('--names-from'),
    gradePaths: args.list('--grades'),
    secondPath: args.value('--second'),
    approaches: approaches,
    out: args.value('--out') ?? runs.first,
    maxNames: args.integer('--max-names', 0),
    seed: args.integer('--seed', 20261121),
    decision: decision,
    decisionGoals: frozen == null
        ? null
        : frozenList(frozen, 'decisionGoals').toSet(),
    promptExampleGoals: frozen == null
        ? const {}
        : frozenList(frozen, 'promptExampleGoals').toSet(),
    guards: guards,
    guardReading: frozen == null
        ? ''
        : 'precision ${frozenPrecision(frozen)}, tolerance '
            '${(frozen['personaGuard'] as Map)['tolerance']}',
    timingReading: amendment == null
        ? ''
        : '7.2 (d) timing, amendment 1: medians of $amendedTimingRuns '
            'separate runs at most ${warmRatioLimit.toStringAsFixed(2)} and '
            '${firstRatioLimit.toStringAsFixed(2)}, at full precision',
  );
  if (args.has('--pool')) {
    evaluation.writePool();
  } else if (args.has('--score')) {
    if (decision && args.has('--whole-lists')) {
      fail('--whole-lists is a development check.');
    }
    evaluation.score(
      select: args.has('--select'),
      dump: args.value('--dump'),
      wholeLists: args.has('--whole-lists'),
    );
  } else {
    fail('Pass --pool or --score.');
  }
}

/// One skill name of one career goal.
class _Name {
  final String goal;
  final String name;

  /// M for a market name, W for a name the writers of the set defined.
  final String stratum;
  final bool opportunityHole;
  final bool certificationHole;

  /// The link of this name in each stored answer that mentions it, per
  /// link request.
  final Map<LinkRequest, List<GapLink>> links;

  _Name(this.goal, this.name, this.stratum, this.opportunityHole,
      this.certificationHole, this.links);

  bool holeIn(String type) =>
      type == 'opportunity' ? opportunityHole : certificationHole;
  String get id => '$goal|${keyOf(name)}';
  String get group => '$stratum|$goal';
}

/// What one way of running one catalogue gives for one name: the means
/// over its link runs.
class _Cell {
  double hit = 0;
  double uncovered = 0;
  double taught = 0;
  double counted = 0;
  int ungraded = 0;
}

class _Evaluation {
  _Evaluation({
    required this.runs,
    required this.extractors,
    required this.goals,
    required this.writerNames,
    required String? excludePath,
    required String? namesFromPath,
    required List<String> gradePaths,
    required this.secondPath,
    required this.approaches,
    required this.out,
    required this.maxNames,
    required this.seed,
    required this.decision,
    required this.decisionGoals,
    required this.promptExampleGoals,
    this.guards,
    this.guardReading = '',
    this.timingReading = '',
  })  : opportunities = loadOpportunities(),
        certifications = loadCertifications() {
    excluded = excludePath == null
        ? const {}
        : {
            for (final line in readText(excludePath).split('\n'))
              if (line.trim().isNotEmpty && !line.startsWith('#')) line.trim(),
          };
    onlyNames = namesFromPath == null
        ? null
        : {
            for (final row in readCsv(namesFromPath))
              '${row['career_goal_id']}|${keyOf(row['gap'] ?? '')}',
          };
    for (final path in gradePaths) {
      _readGrades(path).forEach((key, grade) {
        grades.putIfAbsent(key, () => grade);
      });
    }
    grades.forEach((key, grade) {
      if (grade < 1) return;
      final parts = key.split('|');
      teachableKeys.add('${parts[0]}|${parts[1]}|${parts[2]}');
    });
    names = _loadNames();
  }

  /// With --decision --guards: what the guard files say for every frozen
  /// candidate (rules 7.2 a, b and d). Null: the guards were not passed.
  final Map<String, GuardVerdict>? guards;

  /// How the frozen persona guard compares, for the report.
  final String guardReading;

  /// The label of rule 7.2 (d) when the freeze has its amendment (the
  /// medians of 5 separate runs); empty for the rule as frozen.
  final String timingReading;

  final List<RunFolder> runs;
  final List<String> extractors;
  final Set<String> goals;
  final bool writerNames;
  final String? secondPath;
  final List<Approach> approaches;
  final String out;
  final int maxNames;
  final int seed;
  final bool decision;

  /// With --decision: the frozen decision goals. Only their market names
  /// are market decision names (stratum M); the market lists of any other
  /// goal in the run folder (the CV pass that is only reported) are left
  /// out. Null in development: every market list counts.
  final Set<String>? decisionGoals;

  /// With --decision: the goals the prompt examples come from. Their names
  /// never count, in either stratum.
  final Set<String> promptExampleGoals;

  /// The goals whose market lists were left out by [decisionGoals].
  final Set<String> ignoredMarketGoals = {};
  final List<Opportunity> opportunities;
  final List<Certification> certifications;
  late final Set<String> excluded;
  late final Set<String>? onlyNames;
  late final List<_Name> names;
  int excludedCount = 0;

  /// (goal, name, type, item) -> grade.
  final Map<String, int> grades = {};

  /// (goal, name, type) with at least one graded item that teaches it.
  final Set<String> teachableKeys = {};

  // ---------------------------------------------------------
  // NAMES
  // ---------------------------------------------------------

  List<_Name> _loadNames() {
    final index = OpportunityIndex.of(opportunities);
    final certificationSkills = {
      for (final c in certifications) ...c.skills,
    };
    bool isExcluded(String name) =>
        excluded.isNotEmpty && exclusionKeys(name).any(excluded.contains);

    // goal -> normalized name -> (spelling, stratum), market names first.
    final found = <String, Map<String, (String, String)>>{};
    for (final run in runs) {
      for (final extractor in extractors) {
        for (final goal in run.marketGoals(extractor)) {
          if (goals.isNotEmpty && !goals.contains(goal)) continue;
          final only = decisionGoals;
          if (promptExampleGoals.contains(goal) ||
              (only != null && !only.contains(goal))) {
            ignoredMarketGoals.add(goal);
            continue;
          }
          for (final r in run.marketRuns(goal, extractor)) {
            for (final name
                in run.market(goal, extractor, r) ?? const <String>[]) {
              final key = keyOf(name);
              if (key.isEmpty) continue;
              (found[goal] ??= {}).putIfAbsent(key, () => (name, 'M'));
            }
          }
        }
      }
    }
    if (writerNames) {
      for (final run in runs) {
        run.writerNames.forEach((goal, list) {
          if (goals.isNotEmpty && !goals.contains(goal)) return;
          if (promptExampleGoals.contains(goal)) return;
          for (final name in list) {
            final key = keyOf(name);
            if (key.isEmpty) continue;
            (found[goal] ??= {}).putIfAbsent(key, () => (name, 'W'));
          }
        });
      }
    }

    // The stored link answers of each goal, per request.
    final answers = <String, Map<LinkRequest, List<Map<String, GapLink>>>>{};
    Map<LinkRequest, List<Map<String, GapLink>>> answersOf(
      String goal,
      String stratum,
    ) =>
        answers['$stratum|$goal'] ??= {
          for (final request in LinkRequest.values)
            request: [
              for (final run in runs)
                for (final entry in run.linkAnswers(goal, request).entries)
                  if (stratum == 'W'
                      ? entry.key.startsWith('W')
                      : extractors.any((e) => entry.key.startsWith('${e}_')))
                    {for (final link in entry.value) keyOf(link.gap): link},
            ],
        };

    final holes = <String, List<_Name>>{};
    for (final goal in found.keys.toList()..sort()) {
      for (final entry in found[goal]!.entries) {
        final (name, stratum) = entry.value;
        final opportunityHole = !index.anyTagCovers(name);
        final certificationHole = !certificationSkills
            .any((skill) => SkillMatcher.matches(name, skill));
        if (!opportunityHole && !certificationHole) continue;
        final only = onlyNames;
        if (only != null && !only.contains('$goal|${entry.key}')) continue;
        if (isExcluded(name)) {
          excludedCount++;
          continue;
        }
        final links = <LinkRequest, List<GapLink>>{};
        answersOf(goal, stratum).forEach((request, lists) {
          links[request] = [
            for (final byKey in lists)
              if (byKey[entry.key] != null)
                _renamed(byKey[entry.key]!, name),
          ];
        });
        (holes['$stratum|$goal'] ??= <_Name>[]).add(_Name(
            goal, name, stratum, opportunityHole, certificationHole, links));
      }
    }

    // More hole names than the limit: the same share of every stratum and
    // goal, drawn with the seed.
    final total = holes.values.fold<int>(0, (sum, list) => sum + list.length);
    final result = <_Name>[];
    final random = Random(seed);
    for (final group in holes.keys.toList()..sort()) {
      final list = holes[group]!;
      if (maxNames > 0 && total > maxNames) {
        list.shuffle(random);
        result.addAll(list.take((list.length * maxNames / total).round()));
      } else {
        result.addAll(list);
      }
    }
    return result;
  }

  static GapLink _renamed(GapLink link, String gap) => GapLink(
        gap: gap,
        kind: link.kind,
        concepts: link.concepts,
        same: link.same,
        phrases: link.phrases,
        terms: link.terms,
      );

  // ---------------------------------------------------------
  // ATTRIBUTION
  // ---------------------------------------------------------

  /// The link sets one catalogue setting is run with for a name: one per
  /// stored link answer for the approaches that use them, otherwise one.
  /// Null means "an analysis without links".
  List<List<GapLink>?> _linkSets(LinkSource source, bool enabled, _Name name) {
    if (!enabled) return const [null];
    switch (source) {
      case LinkSource.none:
        return const [null];
      case LinkSource.words:
        final link = WordControl.linkFor(name.name);
        return [
          [?link],
        ];
      case LinkSource.names:
      case LinkSource.typed:
        final stored = name.links[source == LinkSource.names
                ? LinkRequest.names
                : LinkRequest.typed] ??
            const <GapLink>[];
        return stored.isEmpty
            ? const [<GapLink>[]]
            : [for (final link in stored) [link]];
    }
  }

  final Map<String, List<List<String>>> _attributed = {};

  /// Per link set, the ids of the items the setting attributes to the
  /// name, best first, from the app's own recommenders.
  List<List<String>> attributed(Approach approach, _Name name, String type) {
    final settings = approach.settingsFor(type);
    final key = '$type|${settingKey(approach.source, settings)}|${name.id}';
    return _attributed[key] ??= [
      for (final links in _linkSets(approach.source, settings.enabled, name))
        _run(settings, name, type, links),
    ];
  }

  List<String> _run(
    LinkSettings settings,
    _Name name,
    String type,
    List<GapLink>? links,
  ) {
    final analysis = <String, dynamic>{
      'careerGoalId': name.goal,
      'skillGaps': [name.name],
      'currentSkills': const <String>[],
      'gapLinks': ?links?.map((l) => l.toMap()).toList(),
    };
    if (type == 'opportunity') {
      final result =
          OpportunityRecommender(weights: RankingWeights(links: settings))
              .recommend(
        analysis: analysis,
        opportunities: opportunities,
        now: evalDate,
      );
      return [
        for (final match in result.matched)
          if (match.gapSkills.contains(name.name)) match.opportunity.id,
      ];
    }
    final result = ContentBasedRecommender(links: settings)
        .recommendCertifications(
      analysis: analysis,
      certifications: certifications,
    );
    return [
      for (final match in result.matched)
        if (match.matchedSkills.contains(name.name)) match.certification.id,
    ];
  }

  // ---------------------------------------------------------
  // POOL
  // ---------------------------------------------------------

  late final Map<String, Opportunity> _opportunityById = {
    for (final o in opportunities) o.id: o,
  };
  late final Map<String, Certification> _certificationById = {
    for (final c in certifications) c.id: c,
  };

  String _title(String type, String id) => type == 'opportunity'
      ? _opportunityById[id]!.title
      : _certificationById[id]!.name;

  String _text(String type, String id) {
    if (type == 'opportunity') {
      final o = _opportunityById[id]!;
      return [
        if (o.objectives.isNotEmpty) 'Objectives: ${o.objectives.join('; ')}.',
        o.description,
        if (o.skills.isNotEmpty) 'Skills: ${o.skills.join(', ')}.',
      ].join(' ');
    }
    final c = _certificationById[id]!;
    return [
      c.description,
      if (c.skills.isNotEmpty) 'Skills: ${c.skills.join(', ')}.',
    ].join(' ');
  }

  final Map<String, Map<String, String>> _candidateCache = {};

  /// The items a name could be attributed to: opportunities open on the
  /// evaluation date, and the certifications of the career goal.
  Map<String, String> _candidates(_Name name, String type) =>
      _candidateCache[type == 'opportunity' ? type : '$type|${name.goal}'] ??=
          type == 'opportunity'
              ? {
                  for (final o in opportunities)
                    if (o.isOpen(evalDate))
                      o.id:
                          '${o.title}. ${o.objectives.join('. ')}. ${o.description}',
                }
              : {
                  for (final c in certifications)
                    if (c.careerPaths.contains(name.goal))
                      c.id: '${c.name}. ${c.description}',
                };

  /// The pooled item ids of a name in one catalogue.
  Set<String> pool(_Name name, String type) {
    final ids = <String>{};
    for (final approach in approaches) {
      for (final list in attributed(approach, name, type)) {
        ids.addAll(list.take(topK));
      }
    }
    final candidates = _candidates(name, type);
    ids
      ..addAll(TextProbes.bySimilarity(name.name, candidates, limit: topK))
      ..addAll(TextProbes.byAnyWord(name.name, candidates, limit: topK));
    return ids;
  }

  static String rowKey(String goal, String gap, String type, String itemId) =>
      '$goal|${keyOf(gap)}|$type|$itemId';

  /// (goal, name, type, item) -> grade, from a filled teaching sheet.
  static Map<String, int> _readGrades(String path) {
    final grades = <String, int>{};
    for (final row in readCsv(path)) {
      final grade = int.tryParse(row['grade'] ?? '');
      if (grade == null || grade < 0 || grade > 2) continue;
      grades.putIfAbsent(
        rowKey(row['career_goal_id'] ?? '', row['gap'] ?? '',
            row['item_type'] ?? '', row['item_id'] ?? ''),
        () => grade,
      );
    }
    return grades;
  }

  void writePool() {
    final random = Random(seed);
    final pending = <List<String>>[];
    final graded = <List<String>>[];
    var total = 0;
    // Rows of one (name, catalogue) stay together; the groups and the
    // items inside each group are shuffled.
    final groups = <List<List<String>>>[];
    for (final name in names) {
      for (final type in types) {
        if (!name.holeIn(type)) continue;
        final group = <List<String>>[];
        for (final id in pool(name, type)) {
          total++;
          final key = rowKey(name.goal, name.name, type, id);
          final row = [
            't_${sha256OfText(key).substring(0, 10)}',
            name.goal,
            name.name,
            type,
            id,
            _title(type, id),
            _text(type, id),
            '',
            '',
          ];
          (grades.containsKey(key) ? graded : group).add(row);
        }
        if (group.isNotEmpty) groups.add(group..shuffle(random));
      }
    }
    groups.shuffle(random);
    for (final group in groups) {
      pending.addAll(group);
    }
    writeCsv('$out/teaching_review.csv', teachingHeader, pending);

    // For the agreement: in the final measurement a fifth of all pairs; in
    // development a fifth of the pairs that already have a grade, which
    // the new reviewer grades again without seeing it.
    final secondSeed = Random(20261122);
    final source = decision ? [...graded, ...pending] : [...graded];
    source.shuffle(secondSeed);
    writeCsv('$out/teaching_second.csv', teachingHeader,
        source.take((source.length / 5).ceil()).toList());

    stdout.writeln('MATCHING EVALUATION, POOL');
    _describeNames(stdout.writeln);
    stdout.writeln('Approaches pooled: ${approaches.length}.');
    stdout.writeln('Pooled (name, item) pairs: $total, of which '
        '${pending.length} are not graded yet.');
    stdout.writeln('  To grade        : $out/teaching_review.csv');
    stdout.writeln('  For the agreement: $out/teaching_second.csv '
        '(${(source.length / 5).ceil()} pairs, without grades)');
  }

  void _describeNames(void Function(String) line) {
    line('Run folders: ${runs.map((r) => r.path).join(', ')}  '
        '(market lists ${extractors.join(', ')}'
        '${writerNames ? ', and the writers\' names' : ''})');
    final goalCount = {for (final name in names) name.goal}.length;
    line('Hole names: ${names.length} over $goalCount career goals '
        '(${names.where((n) => n.opportunityHole).length} holes for '
        'opportunities, ${names.where((n) => n.certificationHole).length} '
        'for certifications)'
        '${excluded.isEmpty ? '' : '; $excludedCount hole names left out as seen in development'}');
    if (ignoredMarketGoals.isNotEmpty) {
      line('  Market lists left out (not a decision goal, or a goal of the '
          'prompt examples): ${(ignoredMarketGoals.toList()..sort()).join(', ')}');
    }
    for (final stratum in const ['M', 'W']) {
      final list = names.where((n) => n.stratum == stratum).toList();
      if (list.isEmpty) continue;
      final byGoal = <String, int>{};
      for (final name in list) {
        byGoal[name.goal] = (byGoal[name.goal] ?? 0) + 1;
      }
      line('  ${stratum == 'M' ? 'market names' : 'writers\' names'}: '
          '${list.length} '
          '(${list.where((n) => n.opportunityHole).length} opp, '
          '${list.where((n) => n.certificationHole).length} cert)  '
          '${byGoal.entries.map((e) => '${e.key} ${e.value}').join(', ')}');
    }
    for (final request in LinkRequest.values) {
      final without = names
          .where((n) => (n.links[request] ?? const []).isEmpty)
          .length;
      line('  without a stored answer of the '
          '${request == LinkRequest.names ? 'first' : 'typed'} link '
          'request: $without');
    }
  }

  // ---------------------------------------------------------
  // SCORES
  // ---------------------------------------------------------

  final Map<String, _Cell> _cells = {};

  _Cell cell(Approach approach, _Name name, String type) {
    final settings = approach.settingsFor(type);
    final key = '$type|${settingKey(approach.source, settings)}|${name.id}';
    return _cells[key] ??= () {
      final result = _Cell();
      final sets = attributed(approach, name, type);
      for (final list in sets) {
        final first = list.take(topK).toList();
        if (first.isEmpty) result.uncovered++;
        var anyTeaches = false;
        for (final id in first) {
          final grade = grades[rowKey(name.goal, name.name, type, id)];
          if (grade == null) {
            result.ungraded++;
            continue;
          }
          result.counted++;
          if (grade >= 1) {
            result.taught++;
            anyTeaches = true;
          }
        }
        if (anyTeaches) result.hit++;
      }
      result
        ..hit /= sets.length
        ..uncovered /= sets.length
        ..taught /= sets.length
        ..counted /= sets.length;
      return result;
    }();
  }

  bool teachable(_Name name, String type) =>
      teachableKeys.contains('${name.id}|$type');

  double teachHit(Approach approach, String type, Iterable<_Name> among) =>
      meanOf([
        for (final name in among)
          if (name.holeIn(type) && teachable(name, type))
            cell(approach, name, type).hit,
      ]);

  double primary(Approach approach, Iterable<_Name> among) =>
      (teachHit(approach, 'opportunity', among) +
          teachHit(approach, 'certification', among)) /
      2;

  ({double value, double attributions}) attribPrec(
    Approach approach,
    String type,
    Iterable<_Name> among,
  ) {
    var good = 0.0, counted = 0.0;
    for (final name in among) {
      if (!name.holeIn(type)) continue;
      final c = cell(approach, name, type);
      good += c.taught;
      counted += c.counted;
    }
    return (
      value: counted == 0 ? double.nan : good / counted,
      attributions: counted,
    );
  }

  double falseUncovered(Approach approach, String type, Iterable<_Name> among) =>
      meanOf([
        for (final name in among)
          if (name.holeIn(type) && teachable(name, type))
            cell(approach, name, type).uncovered,
      ]);

  int ungraded(Approach approach, Iterable<_Name> among) {
    var count = 0;
    for (final name in among) {
      for (final type in types) {
        if (name.holeIn(type)) count += cell(approach, name, type).ungraded;
      }
    }
    return count;
  }

  /// The values of [statistic] over bootstrap resamples of the names,
  /// drawn within each group (stratum and career goal), sorted.
  List<double> _bootstrap(
    double Function(List<_Name> sample) statistic, {
    required int rounds,
    required int seed,
  }) {
    final byGroup = <String, List<_Name>>{};
    for (final name in names) {
      (byGroup[name.group] ??= <_Name>[]).add(name);
    }
    final random = Random(seed);
    final values = <double>[];
    for (var i = 0; i < rounds; i++) {
      final sample = <_Name>[];
      for (final list in byGroup.values) {
        for (var k = 0; k < list.length; k++) {
          sample.add(list[random.nextInt(list.length)]);
        }
      }
      final value = statistic(sample);
      if (!value.isNaN) values.add(value);
    }
    return values..sort();
  }

  static double _quantile(List<double> sorted, double share) => sorted.isEmpty
      ? double.nan
      : sorted[(share * (sorted.length - 1)).round()];

  /// The one-sided 90% lower bound of AttribPrec@5 in one catalogue
  /// (2,000 resamples, seed 20261123).
  final Map<String, double> _lowerBounds = {};
  double lowerBound(Approach approach, String type) =>
      _lowerBounds['$type|${settingKey(approach.source, approach.settingsFor(type))}'] ??=
          () {
        if (attribPrec(approach, type, names).attributions == 0) {
          return double.nan;
        }
        return _quantile(
          _bootstrap((sample) => attribPrec(approach, type, sample).value,
              rounds: 2000, seed: 20261123),
          0.10,
        );
      }();

  void score({required bool select, String? dump, bool wholeLists = false}) {
    final buffer = StringBuffer();
    void line([String text = '']) {
      stdout.writeln(text);
      buffer.writeln(text);
    }

    line('MATCHING EVALUATION, SCORES');
    _describeNames(line);
    line('Grades: ${grades.length} graded pairs.');

    Approach? find(String id) {
      for (final approach in approaches) {
        if (approach.id == id) return approach;
      }
      return null;
    }

    final today = find('A0') ?? Approach.parse('A0');

    void table(String title, List<_Name> among, List<Approach> rows) {
      if (among.isEmpty) return;
      line();
      line('$title  (${among.length} hole names)');
      line('  ${'Approach'.padRight(16)}${'TeachHit@5'.padLeft(11)}'
          '${'opp'.padLeft(7)}${'cert'.padLeft(7)}'
          '${'AttribPrec@5 opp'.padLeft(18)}${'(n)'.padLeft(7)}'
          '${'cert'.padLeft(7)}${'(n)'.padLeft(7)}'
          '${'FalseUncov opp'.padLeft(16)}${'cert'.padLeft(7)}'
          '${'ungraded'.padLeft(10)}');
      for (final approach in rows) {
        final opp = attribPrec(approach, 'opportunity', among);
        final cert = attribPrec(approach, 'certification', among);
        line('  ${approach.id.padRight(16)}'
            '${f3(primary(approach, among)).padLeft(11)}'
            '${f3(teachHit(approach, 'opportunity', among)).padLeft(7)}'
            '${f3(teachHit(approach, 'certification', among)).padLeft(7)}'
            '${f3(opp.value).padLeft(18)}'
            '${opp.attributions.toStringAsFixed(0).padLeft(7)}'
            '${f3(cert.value).padLeft(7)}'
            '${cert.attributions.toStringAsFixed(0).padLeft(7)}'
            '${f3(falseUncovered(approach, 'opportunity', among)).padLeft(16)}'
            '${f3(falseUncovered(approach, 'certification', among)).padLeft(7)}'
            '${'${ungraded(approach, among)}'.padLeft(10)}');
      }
      line('  Teachable hole names: '
          '${among.where((n) => n.holeIn('opportunity') && teachable(n, 'opportunity')).length} '
          'for opportunities, '
          '${among.where((n) => n.holeIn('certification') && teachable(n, 'certification')).length} '
          'for certifications. (n) = graded attributions in the first 5. '
          'A pair without a grade is in neither number.');
    }

    table('ALL NAMES', names, approaches);
    for (final stratum in const ['M', 'W']) {
      final among = names.where((n) => n.stratum == stratum).toList();
      if (among.length == names.length) continue;
      table(stratum == 'M' ? 'MARKET NAMES' : 'WRITERS\' NAMES', among,
          approaches);
    }
    final goalsWithNames = {for (final name in names) name.goal}.toList()
      ..sort();
    if (goalsWithNames.length > 1 && approaches.length <= 12) {
      for (final goal in goalsWithNames) {
        table('GOAL $goal', names.where((n) => n.goal == goal).toList(),
            approaches);
      }
    }

    if (select) _select(line, today, find('M1'));
    if (decision) _decide(line, today);
    if (wholeLists) _wholeLists(line);

    if (dump != null) {
      final approach = find(dump) ?? Approach.parse(dump);
      line();
      line('ATTRIBUTIONS OF ${approach.id} (first $topK per link run; '
          'grade in brackets, ? = not graded)');
      for (final name in names) {
        for (final type in types) {
          if (!name.holeIn(type)) continue;
          final sets = attributed(approach, name, type);
          line('  ${name.goal} | ${name.name} | $type'
              '${teachable(name, type) ? '' : ' | no pooled item teaches it'}');
          for (var s = 0; s < sets.length; s++) {
            final items = sets[s].take(topK).map((id) {
              final grade = grades[rowKey(name.goal, name.name, type, id)];
              return '${_title(type, id)} [${grade ?? '?'}]';
            }).join('; ');
            line('    run ${s + 1}: ${items.isEmpty ? '(nothing)' : items}');
          }
        }
      }
    }

    // ---- agreement of the two raters ----------------------------------
    final secondSheet = secondPath;
    if (secondSheet != null) {
      final first = <int>[];
      final other = <int>[];
      _readGrades(secondSheet).forEach((key, grade) {
        final mine = grades[key];
        if (mine == null) return;
        first.add(mine);
        other.add(grade);
      });
      line();
      if (first.isEmpty) {
        line('RATER AGREEMENT: no pair of $secondSheet has a first grade.');
      } else {
        final kappa = cohenKappa(
          [for (final g in first) g >= 1 ? 1 : 0],
          [for (final g in other) g >= 1 ? 1 : 0],
        );
        line('RATER AGREEMENT on ${first.length} pairs: Cohen\'s kappa '
            '${f3(kappa)} on "teaches it or not", '
            '${f3(cohenKappa(first, other, weighted: true))} weighted on the '
            'grades 0, 1, 2.'
            '${kappa < 0.6 ? '  BELOW 0.6: see the plan for what happens next.' : ''}');
      }
    }

    final file = File('$out/matching_scores_r2.txt')
      ..createSync(recursive: true);
    file.writeAsStringSync(buffer.toString());
    stdout.writeln();
    stdout.writeln('Scores written to ${file.path}');
  }

  // ---------------------------------------------------------
  // DEVELOPMENT SELECTION
  // ---------------------------------------------------------

  /// How many switches an approach has on and how large its thetas are:
  /// ties go to the smaller theta and to switches off.
  static double _weightOf(Approach a) {
    double of(LinkSettings s) => !s.enabled
        ? 0
        : s.theta +
            (s.termSupport ? 1 : 0) +
            (s.tagSupport ? 1 : 0) +
            (s.termEvidence ? 1 : 0) +
            (s.reasonOnly ? 1 : 0);
    return of(a.opportunities) + of(a.certifications);
  }


  /// Pairs without a grade, per approach id, over all the names.
  late final Map<String, int> _ungradedById = {
    for (final approach in approaches) approach.id: ungraded(approach, names),
  };

  void _select(void Function([String]) line, Approach today, Approach? round1) {
    line();
    line('DEVELOPMENT SELECTION (rules 1 to 3 of the plan; the persona guard '
        'and the timing guard are checked with '
        'tools/recommender_eval/evaluate_recommender.dart)');
    final todayHit = primary(today, names);
    final reference = round1 == null ? double.nan : primary(round1, names);
    final floor = round1 == null
        ? double.nan
        : todayHit + 0.5 * (reference - todayHit);
    line('  Today (A0) TeachHit@5 ${f3(todayHit)}; the first request\'s '
        'ungated links (M1) ${f3(reference)}; an eligible setting needs at '
        'least ${f3(floor)}. An "-opp" fallback is held to rules 1 '
        '(opportunities) and 3 only.');
    if (round1 == null) {
      line('  M1 is not among the approaches: add it, rule 2 cannot be '
          'checked without it.');
    }
    // The floor of rule 2 and rule 3 rest on A0 and M1: while either has
    // a pair without a grade, nothing can be eligible.
    final controlsOpen = notGradedYet(_ungradedById, ['A0', 'M1']);
    if (controlsOpen != null) {
      line('  The controls are not fully graded: $controlsOpen. Rules 2 and '
          '3 cannot be applied yet.');
    }

    final eligible = <Approach>[];
    final rows = <String>[];
    for (final approach in approaches) {
      if (isControl(approach)) continue;
      final fallback = fullCandidateOf(approach.id) != null;
      final fails = <String>[];
      for (final type in types) {
        if (!approach.settingsFor(type).enabled) continue;
        final label = type == 'opportunity' ? 'opp' : 'cert';
        final precision = attribPrec(approach, type, names);
        if (precision.attributions > 0 && !(precision.value >= 0.76)) {
          fails.add('AttribPrec $label ${f3(precision.value)} < 0.760');
        }
        final bound = lowerBound(approach, type);
        if (precision.attributions > 0 && !(bound >= 0.70)) {
          fails.add('90% lower bound $label ${f3(bound)} < 0.700');
        }
      }
      final hit = primary(approach, names);
      if (!fallback && !(hit >= floor)) {
        fails.add('TeachHit ${f3(hit)} < ${f3(floor)}');
      }
      for (final type in types) {
        if (teachHit(approach, type, names) < teachHit(today, type, names)) {
          fails.add('below A0 for ${type == 'opportunity' ? 'opp' : 'cert'}');
        }
      }
      final open = notGradedYet(
          _ungradedById, neededFor(approach, development: true));
      if (open != null) fails.add('not graded yet: $open');
      if (fails.isEmpty) eligible.add(approach);
      rows.add('  ${approach.id.padRight(16)}${f3(hit).padLeft(8)}'
          '${f3(attribPrec(approach, 'opportunity', names).value).padLeft(8)}'
          '${f3(lowerBound(approach, 'opportunity')).padLeft(8)}'
          '${f3(attribPrec(approach, 'certification', names).value).padLeft(8)}'
          '${f3(lowerBound(approach, 'certification')).padLeft(8)}'
          '  ${fails.isEmpty ? 'ELIGIBLE' : fails.join('; ')}');
    }
    line('  ${'Setting'.padRight(16)}${'TeachHit'.padLeft(8)}'
        '${'AP opp'.padLeft(8)}${'LB90'.padLeft(8)}'
        '${'AP cert'.padLeft(8)}${'LB90'.padLeft(8)}');
    rows.forEach(line);

    eligible.sort((a, b) {
      final byHit = primary(b, names).compareTo(primary(a, names));
      if (byHit.abs() > 0 &&
          (primary(b, names) - primary(a, names)).abs() > 1e-9) {
        return byHit;
      }
      return _weightOf(a).compareTo(_weightOf(b));
    });
    line();
    // The candidates are chosen among full settings; an "-opp" fallback is
    // only ever the fallback of candidate 1.
    final full = [
      for (final approach in eligible)
        if (fullCandidateOf(approach.id) == null) approach,
    ];
    if (full.isEmpty) {
      line('  No setting is eligible on these names.');
      return;
    }
    line('  Eligible, best first (ties go to the smaller theta and to '
        'switches off):');
    for (final approach in full) {
      line('    ${approach.id.padRight(16)}${f3(primary(approach, names))}');
    }
    final bestOf = <String, Approach>{};
    for (final approach in full) {
      bestOf.putIfAbsent(approach.id.split('/').first.substring(0, 1),
          () => approach);
    }
    final first = full.first;
    line('  Candidate 1: ${first.id}');
    for (final entry in bestOf.entries) {
      if (identical(entry.value, first)) continue;
      final gap = primary(first, names) - primary(entry.value, names);
      line('  Best of the other family: ${entry.value.id} '
          '(${f3(gap)} below; it is frozen too only when within 0.030)');
    }
    final fallbackId = '${first.id}-opp';
    final fallbackApproach = [
      for (final approach in approaches)
        if (approach.id == fallbackId) approach,
    ];
    line('  Fallback $fallbackId: '
        '${fallbackApproach.isEmpty ? 'not among the approaches (add it to check it)' : eligible.contains(fallbackApproach.first) ? 'meets rules 1 (opportunities) and 3; it is frozen too if it also passes the persona and timing guards' : 'does not meet rules 1 (opportunities) and 3'}');
  }

  // ---------------------------------------------------------
  // DECISION RULES OF THE FINAL MEASUREMENT
  // ---------------------------------------------------------

  /// The 95% bootstrap interval of a difference of TeachHit@5 (10,000
  /// resamples of names within stratum and goal, seed 20261121).
  ({double low, double high}) _differenceInterval(Approach a, Approach b) {
    final values = _bootstrap(
      (sample) => primary(a, sample) - primary(b, sample),
      rounds: 10000,
      seed: 20261121,
    );
    return (low: _quantile(values, 0.025), high: _quantile(values, 0.975));
  }

  void _decide(void Function([String]) line, Approach today) {
    line();
    line('DECISION RULES (tools/gap_eval/decision_rule_r2.txt), on '
        '${names.length} decision names');
    if (names.length < 40) {
      line('  SMALL SAMPLE: fewer than 40 decision names. The rules apply '
          'as written; read every interval.');
    }
    final candidates = [
      for (final approach in approaches)
        if (!isControl(approach)) approach,
    ];
    final needed = <String>{
      for (final candidate in candidates)
        ...neededFor(candidate, development: false),
    };
    final results = <CandidateResult>[];
    final passesOtherRules = <String, bool>{};
    for (final approach in candidates) {
      final difference = primary(approach, names) - primary(today, names);
      final interval = _differenceInterval(approach, today);
      final rules = <String, bool>{
        'TeachHit@5 beats A0 by at least 0.10, 95% interval above 0':
            difference >= 0.10 && interval.low > 0,
      };
      line('  ${approach.id}: TeachHit@5 against A0 ${signed3(difference)}  '
          '[${signed3(interval.low)}, ${signed3(interval.high)}]');
      for (final type in types) {
        final label = type == 'opportunity' ? 'opportunities' : 'certifications';
        rules['not below A0 for $label'] =
            !(teachHit(approach, type, names) < teachHit(today, type, names));
        final precision = attribPrec(approach, type, names);
        rules['AttribPrec@5 at least 0.70 for $label'] =
            precision.attributions == 0 || precision.value >= 0.70;
        final spread = _bootstrap(
          (sample) => attribPrec(approach, type, sample).value,
          rounds: 2000,
          seed: 20261123,
        );
        line('    AttribPrec@5 $label ${f3(precision.value)} on '
            '${precision.attributions.toStringAsFixed(1)} graded '
            'attributions, 90% interval [${f3(_quantile(spread, 0.05))}, '
            '${f3(_quantile(spread, 0.95))}]');
      }
      final control = approach.gatedControl;
      final againstControl = primary(approach, names) - primary(control, names);
      line('    against the word control with the same gate: '
          '${signed3(againstControl)} '
          '(control TeachHit@5 ${f3(primary(control, names))}, AttribPrec '
          '${f3(attribPrec(control, 'opportunity', names).value)} opp, '
          '${f3(attribPrec(control, 'certification', names).value)} cert)');
      final uncovered = (falseUncovered(approach, 'opportunity', names) +
              falseUncovered(approach, 'certification', names)) /
          2;
      line('    FalseUncovered ${f3(falseUncovered(approach, 'opportunity', names))} '
          'opp, ${f3(falseUncovered(approach, 'certification', names))} cert');
      passesOtherRules[approach.id] = rules.values.every((ok) => ok);
      final guard = guards?[approach.id];
      if (guard != null) {
        for (final guardLine in guard.lines) {
          line('    guards, $guardLine');
        }
        rules['7.2 (a) without links, the lists of today on both persona '
            'files'] = guard.sameWithoutLinks;
        rules['7.2 (b) persona guard ($guardReading): '
            '${guard.personaStatus}'] = guard.personaStatus == 'pass';
        rules[timingReading.isNotEmpty
            ? timingReading
            : '7.2 (d) timing ratios at most '
                '${warmRatioLimit.toStringAsFixed(2)} and '
                '${firstRatioLimit.toStringAsFixed(2)}, at full precision'] =
            guard.timing;
      }
      rules.forEach((rule, ok) => line('    ${ok ? 'pass' : 'FAIL'}  $rule'));
      results.add(CandidateResult(
        id: approach.id,
        passes: rules.values.every((ok) => ok),
        teachHit: primary(approach, names),
        falseUncovered: uncovered,
        requests: 1,
        movingParts: movingPartsOf(approach),
      ));
    }
    line();
    final open = notGradedYet(_ungradedById, needed);
    if (open != null) {
      line('DECISION: none yet. $open: run --pool, have them graded, then '
          'score again.');
      return;
    }
    final guardVerdicts = guards;
    if (guardVerdicts == null) {
      line('DECISION: pending the guards. Rules 7.2 (a), (b) and (d) are '
          'not checked: pass --guards with the guard files of '
          'tools/recommender_eval/evaluate_recommender.dart --guard-json. '
          'No winner is named without them.');
      return;
    }
    final pending = pendingCandidates(passesOtherRules, guardVerdicts);
    if (pending.isNotEmpty) {
      line('DECISION: pending (blind labelling needs the user). '
          '${pending.join(', ')} ${pending.length == 1 ? 'passes' : 'pass'} '
          'every other rule, but the persona guard fails as measured and '
          'would pass only with labels for the unlabelled new items (rule '
          '7.2 b). Nothing ships and no winner is named until the user '
          'decides on blind labelling.');
      return;
    }
    guardVerdicts.forEach((id, verdict) {
      if (verdict.personaStatus == 'pending') {
        line('  $id: the persona guard is pending (rule 7.2 b), but $id '
            'fails another rule, so labels could not make it pass.');
      }
    });
    final byId = {for (final approach in candidates) approach.id: approach};
    final picked = pickWinner(results, withinNoise: (a, b) {
      final interval = _differenceInterval(byId[a]!, byId[b]!);
      return interval.low <= 0 && interval.high >= 0;
    });
    for (final note in picked.notes) {
      line('  $note');
    }
    final winner = picked.winner;
    if (winner == null) {
      line(results.any((r) => r.passes)
          ? 'DECISION: no winner by these rules; the user decides.'
          : 'DECISION: no candidate passes these rules. A0 stays.');
      return;
    }
    final control = byId[winner]!.gatedControl;
    final aboveControl =
        primary(byId[winner]!, names) > primary(control, names);
    line('DECISION: $winner wins these rules (7.2 with the guard files, 7.3 '
        'and 7.4)'
        '${fullCandidateOf(winner) == null ? '' : '; it is an "-opp" fallback, so the certification half of the task is not done'}.');
    if (!aboveControl) {
      line('  NOT ABOVE THE WORD CONTROL (rule 7.6): the gain is not shown to '
          'come from meaning; the user decides before anything ships.');
    }
    if (fullCandidateOf(winner) == null) {
      final fallback = '$winner-opp';
      if (byId.containsKey(fallback)) {
        line('  $fallback is not considered (rule 7.4: a fallback wins only '
            'when its full candidate fails).');
      }
    }
  }

  // ---------------------------------------------------------
  // WHOLE ANALYSES (development check)
  // ---------------------------------------------------------

  /// The scores above rank one hole name at a time, so they never see how
  /// the gaps of one analysis act on each other (aspects, and which gaps a
  /// card names). Here every stored market list is ranked as one analysis,
  /// with the whole list as the gaps (the worst case: a CV that shows none
  /// of them), and each gap that the links cover on their own (named on a
  /// card when ranked alone with links, never without them) is checked: on
  /// the whole analysis it must still be named on some opportunity card or
  /// be listed as uncovered. Zero requests: the stored link answers only.
  void _wholeLists(void Function([String]) line) {
    line();
    line('WHOLE ANALYSES (development check, opportunities): every stored '
        '${extractors.join('/')} market list ranked as one analysis');
    line('  ${'Approach'.padRight(16)}${'lists'.padLeft(7)}'
        '${'covered by links alone'.padLeft(24)}${'on no card'.padLeft(12)}'
        '${'AttribPrec@5 opp'.padLeft(18)}');
    final plain = OpportunityRecommender(
        weights: const RankingWeights(links: LinkSettings.off));
    final plainNamed = <String, bool>{};
    bool namedAlone(OpportunityRecommender recommender, String goal,
        String gap, List<GapLink>? links) {
      final result = recommender.recommend(
        analysis: {
          'careerGoalId': goal,
          'skillGaps': [gap],
          'currentSkills': const <String>[],
          'gapLinks': ?links?.map((l) => l.toMap()).toList(),
        },
        opportunities: opportunities,
        now: evalDate,
      );
      return result.matched.any((m) => m.gapSkills.contains(gap));
    }

    for (final approach in approaches) {
      final settings = approach.opportunities;
      if (!settings.enabled || approach.source == LinkSource.none) continue;
      final recommender =
          OpportunityRecommender(weights: RankingWeights(links: settings));
      var lists = 0, covered = 0, vanished = 0;
      for (final run in runs) {
        for (final extractor in extractors) {
          for (final goal in run.marketGoals(extractor)) {
            if (goals.isNotEmpty && !goals.contains(goal)) continue;
            for (final r in run.marketRuns(goal, extractor)) {
              final gaps = run.market(goal, extractor, r);
              if (gaps == null || gaps.isEmpty) continue;
              final List<GapLink>? links;
              switch (approach.source) {
                case LinkSource.none:
                  continue;
                case LinkSource.words:
                  links = [
                    for (final gap in gaps) ?WordControl.linkFor(gap),
                  ];
                case LinkSource.names:
                case LinkSource.typed:
                  links = run.links(goal, extractor, r,
                      request: approach.source == LinkSource.names
                          ? LinkRequest.names
                          : LinkRequest.typed);
              }
              if (links == null) continue;
              lists++;
              final whole = recommender.recommend(
                analysis: {
                  'careerGoalId': goal,
                  'skillGaps': gaps,
                  'currentSkills': const <String>[],
                  'gapLinks': [for (final link in links) link.toMap()],
                },
                opportunities: opportunities,
                now: evalDate,
              );
              final onCards = {for (final m in whole.matched) ...m.gapSkills};
              final uncovered = whole.uncoveredGaps.toSet();
              for (final gap in gaps) {
                if (plainNamed['$goal|$gap'] ??=
                    namedAlone(plain, goal, gap, null)) {
                  continue;
                }
                if (!namedAlone(recommender, goal, gap, links)) continue;
                covered++;
                if (!onCards.contains(gap) && !uncovered.contains(gap)) {
                  vanished++;
                }
              }
            }
          }
        }
      }
      line('  ${approach.id.padRight(16)}${'$lists'.padLeft(7)}'
          '${'$covered'.padLeft(24)}${'$vanished'.padLeft(12)}'
          '${f3(attribPrec(approach, 'opportunity', names).value).padLeft(18)}');
    }
    line('  (covered by links alone: (list, gap) pairs named on a card when '
        'the gap is ranked alone with links and never without them; on no '
        'card: of those, the gaps that the whole analysis names on no card '
        'and does not list as uncovered either.)');
  }
}
