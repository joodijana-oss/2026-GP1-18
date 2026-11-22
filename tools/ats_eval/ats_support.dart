import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../gap_eval/eval_support.dart';

/// Helpers of the ATS review evaluation (evaluate_ats.dart): filling the
/// review texts, the anonymous labels, the quote check, the stop rule, the
/// request summary and the grading sheet. Nothing here touches a file.
/// AtsMeter is the HTTP client the run sends with; everything else is a
/// pure function, so the tests can check all of it.

const String careerPlaceholder = '{{CAREER_NAME}}';
const String todayPlaceholder = '{{TODAY}}';
const String cvPlaceholder = '{{CV_TEXT}}';

/// The review text the app sent before this change, word for word, and
/// the decision rule fixed before any measurement.
const String oldTextPath = 'tools/ats_eval/old_improve_cv_prompt.txt';
const String decisionRulePath = 'tools/ats_eval/decision_rule.txt';

/// sha256 of the LF text of each (decision_rule.txt pins the first two).
const String oldTextSha256 =
    '61df986f8be2f4ebaad6784eb0388c8eb7784769f99de7fe873d1443355509bb';
const String newTextSha256 =
    '512c0968af9bf7b8000b30fd448d2151f7c760e93d4453080894b76ffd3c131e';
const String decisionRuleSha256 =
    'abcf81b7807733ba08d573734081a76fad891f505646304a2597c4125f978894';

/// The versions a run can compare.
const List<String> knownVersions = ['old', 'new'];

/// The five areas of the review, in the order the screen shows them
/// (the same as AnalysisAi.cvImprovementAreaKeys).
const List<String> areaKeys = [
  'cvStructure',
  'sectionOrganization',
  'keywordUsage',
  'readability',
  'contentFormatting',
];

// ---------------------------------------------------------
// FILLING A REVIEW TEXT
// ---------------------------------------------------------

/// [template] with its three placeholders replaced. CRLF becomes LF in
/// the template first. Each placeholder must be there exactly once. They
/// are replaced in one pass, where they stand in the template, so nothing
/// in the inputs is ever read as a placeholder: a CV that contains
/// `{{TODAY}}` keeps it as written. The CV text itself is used exactly as
/// given.
String fillReviewText(
  String template, {
  required String careerName,
  required String today,
  required String cvText,
}) {
  final text = template.replaceAll('\r\n', '\n');
  final places = <({int at, String placeholder, String value})>[];
  for (final (placeholder, value) in [
    (careerPlaceholder, careerName),
    (todayPlaceholder, today),
    (cvPlaceholder, cvText),
  ]) {
    final count = placeholder.allMatches(text).length;
    if (count != 1) {
      throw FormatException(
          'The review text must hold $placeholder exactly once '
          '(found $count).');
    }
    places.add(
        (at: text.indexOf(placeholder), placeholder: placeholder, value: value));
  }
  places.sort((a, b) => a.at.compareTo(b.at));
  final out = StringBuffer();
  var from = 0;
  for (final place in places) {
    out
      ..write(text.substring(from, place.at))
      ..write(place.value);
    from = place.at + place.placeholder.length;
  }
  out.write(text.substring(from));
  return out.toString();
}

// ---------------------------------------------------------
// ANONYMOUS LABELS
// ---------------------------------------------------------

/// One output of the run: a CV, a version and a run number, and the
/// opaque label the grader sees instead.
class Slot {
  const Slot({
    required this.cv,
    required this.version,
    required this.run,
    required this.label,
  });

  factory Slot.fromJson(Map<dynamic, dynamic> json) => Slot(
        cv: json['cv'].toString(),
        version: json['version'].toString(),
        run: (json['run'] as num).toInt(),
        label: json['label'].toString(),
      );

  final String cv;
  final String version;
  final int run;
  final String label;

  /// The file name of the slot's sealed answer.
  String get rawName => '${cv}_${version}_r$run';

  Map<String, Object> toJson() =>
      {'label': label, 'cv': cv, 'version': version, 'run': run};
}

/// The labels of every output: for each CV in [cvIds], its
/// `versions.length * runs` outputs get the labels `<cv>_01`, `<cv>_02`,
/// ... in an order shuffled with [seed]. A grader cannot tell from a label
/// which version an output is, nor which two outputs come from the same
/// run. The same arguments always give the same labels.
List<Slot> assignLabels(
  List<String> cvIds,
  List<String> versions,
  int runs,
  int seed,
) {
  if (cvIds.toSet().length != cvIds.length) {
    throw ArgumentError('CV ids must be unique.');
  }
  if (versions.isEmpty || versions.toSet().length != versions.length) {
    throw ArgumentError('Versions must be unique and not empty.');
  }
  if (runs < 1) throw ArgumentError('Runs must be at least 1.');
  final random = Random(seed);
  final count = versions.length * runs;
  final width = max(2, '$count'.length);
  final slots = <Slot>[];
  for (final cv in cvIds) {
    final pairs = [
      for (final version in versions)
        for (var run = 1; run <= runs; run++) (version: version, run: run),
    ]..shuffle(random);
    for (var i = 0; i < pairs.length; i++) {
      slots.add(Slot(
        cv: cv,
        version: pairs[i].version,
        run: pairs[i].run,
        label: '${cv}_${'${i + 1}'.padLeft(width, '0')}',
      ));
    }
  }
  return slots;
}

// ---------------------------------------------------------
// QUOTES
// ---------------------------------------------------------

final RegExp _letter = RegExp(r'[\p{L}\p{N}]', unicode: true);
const String _l = r'[\p{L}\p{N}]';

/// Spans in double quotes, single quotes or curly quotes. An apostrophe
/// between two letters (don't, CV's) is part of a word, not a quote mark.
final RegExp _quotePattern = RegExp(
  r'"([^"\n]+)"'
  r'|“([^”\n]+)”'
  "|(?<!$_l)'((?:[^'\\n]|(?<=$_l)'(?=$_l))+?)'(?!$_l)"
  "|(?<!$_l)‘((?:[^’\\n]|(?<=$_l)’(?=$_l))+?)’(?!$_l)",
  unicode: true,
);

/// Every quoted span of [text], without its quote marks, in order.
List<String> quotedSpans(String text) {
  final spans = <String>[];
  for (final match in _quotePattern.allMatches(text)) {
    final span = (match.group(1) ??
            match.group(2) ??
            match.group(3) ??
            match.group(4) ??
            '')
        .trim();
    if (_letter.hasMatch(span)) spans.add(span);
  }
  return spans;
}

/// [text] in the form the quote check compares: curly quotes and
/// apostrophes made straight, dashes made "-", non-breaking spaces made
/// spaces, and letter case, whitespace and quote marks left out. [ends]
/// marks each character of the result that ends a sentence ('.', '!' or
/// '?' followed by whitespace or the end of the text).
({String text, List<bool> ends}) _comparable(String text) {
  final prepared = text
      .replaceAll(RegExp('[‘’‚‛′]'), "'")
      .replaceAll(RegExp('[“”„‟″]'), '"')
      .replaceAll(RegExp('[‐‑‒–—―−]'), '-')
      .replaceAll(RegExp('[     ]'), ' ')
      .replaceAll('…', '...')
      .toLowerCase();
  final out = StringBuffer();
  final ends = <bool>[];
  var last = '';
  bool isLetter(int i) =>
      i >= 0 && i < prepared.length && _letter.hasMatch(prepared[i]);
  for (var i = 0; i < prepared.length; i++) {
    final c = prepared[i];
    if (c.trim().isEmpty) {
      if (ends.isNotEmpty && '.!?'.contains(last)) ends[ends.length - 1] = true;
      continue;
    }
    if (c == '"') continue;
    if (c == "'" && !(isLetter(i - 1) && isLetter(i + 1))) continue;
    out.write(c);
    ends.add(false);
    last = c;
  }
  if (ends.isNotEmpty && '.!?'.contains(last)) ends[ends.length - 1] = true;
  return (text: out.toString(), ends: ends);
}

String? _cachedCv;
({String text, List<bool> ends})? _cachedComparable;

final RegExp _edgePunctuation = RegExp(r'^[.,;:!?]+|[.,;:!?]+$');

/// Whether [span] is text of [cvText], ignoring letter case, whitespace,
/// quote marks and "..." for left-out words. The parts around a "..."
/// must appear in order and inside one sentence: words joined from two
/// sentences are not a quote of the CV. Punctuation at the start or end
/// of a part is ignored.
bool quoteInCv(String span, String cvText) {
  if (_cachedCv != cvText) {
    _cachedCv = cvText;
    _cachedComparable = _comparable(cvText);
  }
  final cv = _cachedComparable!;
  final normalized = _comparable(
          span.replaceAll(RegExp(r'[\[(]\s*(\.\.\.|…)\s*[\])]'), '...'))
      .text;
  final parts = [
    for (final part in normalized.split('...'))
      if (part.replaceAll(_edgePunctuation, '').isNotEmpty)
        part.replaceAll(_edgePunctuation, ''),
  ];
  if (parts.isEmpty) return false;

  bool crossesSentence(int from, int to) {
    for (var i = from; i < to; i++) {
      if (cv.ends[i]) return true;
    }
    return false;
  }

  // Each part after the first must start after the one before it, with no
  // sentence end in between.
  bool placeFrom(int index, int from) {
    if (index == parts.length) return true;
    var at = cv.text.indexOf(parts[index], from);
    while (at >= 0) {
      if (index > 0 && crossesSentence(from, at)) return false;
      if (placeFrom(index + 1, at + parts[index].length)) return true;
      at = cv.text.indexOf(parts[index], at + 1);
    }
    return false;
  }

  return placeFrom(0, 0);
}

// ---------------------------------------------------------
// STOPS AND FAILURES
// ---------------------------------------------------------

/// Why a run stops at once: a credit or billing error, a rate error, or a
/// key or permission error. None of them can be helped by a retry.
enum StopKind { credit, rate, key }

/// The stop an answer calls for, or null when the run goes on. Only an
/// answer that is not a success can stop the run.
StopKind? stopReason(int status, String body) {
  if (status >= 200 && status < 300) return null;
  if (status == 402) return StopKind.credit;
  if (status == 429) return StopKind.rate;
  if (status == 401 || status == 403) return StopKind.key;
  final lower = body.toLowerCase();
  if (lower.contains('credit') || lower.contains('billing')) {
    return StopKind.credit;
  }
  if (lower.contains('rate_limit')) return StopKind.rate;
  return null;
}

/// Thrown, and never retried, when the run must stop. It carries only the
/// status code and the kind of stop, never a response body.
class AtsStop implements Exception {
  const AtsStop(this.kind, this.status);

  final StopKind kind;
  final int? status;

  String get message => kind == StopKind.key
      ? 'STOPPED: key or permission error (HTTP ${status ?? '?'}).'
      : 'STOPPED: credit/rate error (HTTP ${status ?? '?'}). '
          'Re-run the same command to resume.';

  @override
  String toString() => message;
}

/// The token counts of one output, added up by [AtsMeter] for every
/// request sent inside [withUsage].
class UsageCounter {
  int inputTokens = 0;
  int outputTokens = 0;
}

const Symbol _usageKey = #atsUsageCounter;

/// Runs [body] so that [AtsMeter] adds the tokens of its requests to
/// [counter].
Future<T> withUsage<T>(UsageCounter counter, Future<T> Function() body) =>
    runZoned(body, zoneValues: {_usageKey: counter});

/// The meter of the evaluation tools with the stops this run needs on top:
/// UsageMeter already stops at a credit or billing error; this one also
/// stops at a rate error (429 or rate_limit) and at a key or permission
/// error (401 or 403). After any stop every later request is refused
/// before it is sent.
class AtsMeter extends UsageMeter {
  AtsMeter({super.inputPrice, super.outputPrice});

  AtsStop? stop;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final earlier = stop;
    if (earlier != null) throw earlier;
    final http.StreamedResponse response;
    try {
      response = await super.send(request);
    } on CreditStop catch (e) {
      final status = RegExp(r'\d{3}').firstMatch(e.message)?.group(0);
      throw stop ??= AtsStop(
          StopKind.credit, status == null ? null : int.parse(status));
    }
    return inspect(response);
  }

  /// Reads [response] once, stops the run when it calls for a stop, adds
  /// its tokens to the counter of the current output, and returns it
  /// rebuilt the way UsageMeter rebuilds it.
  Future<http.StreamedResponse> inspect(http.StreamedResponse response) async {
    final bytes = await response.stream.toBytes();
    final text = utf8.decode(bytes, allowMalformed: true);
    final kind = stopReason(response.statusCode, text);
    if (kind != null) throw stop ??= AtsStop(kind, response.statusCode);
    final counter = Zone.current[_usageKey];
    if (counter is UsageCounter &&
        response.statusCode >= 200 &&
        response.statusCode < 300) {
      try {
        final usage = (jsonDecode(text) as Map)['usage'];
        if (usage is Map) {
          counter.inputTokens += (usage['input_tokens'] as num?)?.toInt() ?? 0;
          counter.outputTokens +=
              (usage['output_tokens'] as num?)?.toInt() ?? 0;
        }
      } on Object {
        // An answer without readable counts is simply not counted.
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
}

/// The status code and kind of a failed request: timeout, http, cut_off,
/// invalid_json, empty or other. The error text is read only to tell the
/// kind; it is never printed or saved, because it can hold the response
/// body or the answer.
({int? status, String kind}) describeFailure(Object error) {
  if (error is TimeoutException) return (status: null, kind: 'timeout');
  if (error is FormatException) return (status: null, kind: 'invalid_json');
  final text = error.toString();
  final httpError =
      RegExp(r'^Exception: \S+ API error (\d{3})').firstMatch(text);
  if (httpError != null) {
    return (status: int.parse(httpError.group(1)!), kind: 'http');
  }
  if (RegExp(r'^Exception: \S+ response was cut off').hasMatch(text)) {
    return (status: null, kind: 'cut_off');
  }
  if (RegExp(r'^Exception: (\S+ returned invalid JSON|Invalid AI response format)')
      .hasMatch(text)) {
    return (status: null, kind: 'invalid_json');
  }
  if (RegExp(r'^Exception: \S+ returned (an empty response|no text)')
      .hasMatch(text)) {
    return (status: null, kind: 'empty');
  }
  return (status: null, kind: 'other');
}

// ---------------------------------------------------------
// REQUESTS PER VERSION
// ---------------------------------------------------------

/// The requests of one version, from its sealed answers ([raws], the
/// sealed/raw files) and its failure records ([failures], the
/// sealed/failed files): how many slots were answered at the first try or
/// after a retry, every failed attempt by kind (a slot that succeeded on
/// its retry counts here too), the time each answered slot took (what a
/// user would wait, retries included), and the time and output tokens of
/// the answers that came at the first try (one request each). Reported
/// next to the decision; it does not decide.
Map<String, Object?> requestSummary(
  List<Map<dynamic, dynamic>> raws,
  List<Map<dynamic, dynamic>> failures,
) {
  final failedByKind = <String, int>{};
  void countFailed(Object? attempts) {
    for (final attempt in attempts is List ? attempts : const []) {
      if (attempt is! Map) continue;
      final kind = attempt['kind']?.toString() ?? 'other';
      final key = kind == 'http' && attempt['status'] != null
          ? 'http ${attempt['status']}'
          : kind;
      failedByKind[key] = (failedByKind[key] ?? 0) + 1;
    }
  }

  final slotSeconds = <double>[];
  final firstSeconds = <double>[];
  final firstOutput = <double>[];
  var firstTry = 0;
  var afterRetry = 0;
  var inputTokens = 0;
  var outputTokens = 0;
  for (final raw in raws) {
    countFailed(raw['failedAttempts']);
    inputTokens += (raw['inputTokens'] as num?)?.toInt() ?? 0;
    outputTokens += (raw['outputTokens'] as num?)?.toInt() ?? 0;
    final seconds = (raw['seconds'] as num?)?.toDouble();
    if (seconds != null) slotSeconds.add(seconds);
    if (((raw['attempts'] as num?)?.toInt() ?? 1) <= 1) {
      firstTry++;
      if (seconds != null) firstSeconds.add(seconds);
      final output = (raw['outputTokens'] as num?)?.toDouble();
      if (output != null) firstOutput.add(output);
    } else {
      afterRetry++;
    }
  }
  for (final failure in failures) {
    for (final run in failure['history'] is List
        ? failure['history'] as List
        : const []) {
      if (run is Map) countFailed(run['attempts']);
    }
  }
  return {
    'answered': raws.length,
    'firstTry': firstTry,
    'afterRetry': afterRetry,
    'failedAttempts': {
      for (final key in failedByKind.keys.toList()..sort())
        key: failedByKind[key],
    },
    'secondsPerSlot': spread(slotSeconds),
    'firstTrySeconds': spread(firstSeconds),
    'firstTryOutputTokens': spread(firstOutput),
    // The tokens of the answered slots, their failed attempts included
    // (the tokens of slots that never succeeded are only in the meter).
    'answeredInputTokens': inputTokens,
    'answeredOutputTokens': outputTokens,
  };
}

/// Mean, median and largest of [values] (null each when there are none).
Map<String, double?> spread(List<double> values) {
  if (values.isEmpty) return {'mean': null, 'median': null, 'max': null};
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return {
    'mean': sorted.reduce((a, b) => a + b) / sorted.length,
    'median': sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2,
    'max': sorted.last,
  };
}

// ---------------------------------------------------------
// THE GRADING SHEET
// ---------------------------------------------------------

const List<String> sheetHeader = [
  'label',
  'cv',
  'area',
  'n',
  'issue',
  'suggestion',
  'quotes_not_in_cv',
  'verdict',
  'credits',
  'point',
  'invented_facts',
  'misquotes',
  'notes',
];

/// The columns the tool fills; the grader fills the rest.
const int toolColumns = 7;

const List<String> quotesHeader = [
  'label',
  'cv',
  'area',
  'n',
  'field',
  'quote',
  'check',
];

/// The five areas of an output with no issues.
Map<String, List<Map<String, String>>> emptyAreas() =>
    {for (final key in areaKeys) key: <Map<String, String>>[]};

/// The five areas of a saved output, in screen order.
Map<String, List<Map<String, String>>> areasFrom(Object? saved) {
  final map = saved is Map ? saved : const {};
  return {
    for (final key in areaKeys)
      key: [
        for (final item in map[key] is List ? map[key] as List : const [])
          if (item is Map)
            {
              'issue': item['issue']?.toString() ?? '',
              'suggestion': item['suggestion']?.toString() ?? '',
            },
      ],
  };
}

/// The sheet rows and the quote rows of one output. An output with no
/// issues gets one sheet row with area `(none)` and verdict EMPTY.
({List<List<String>> sheet, List<List<String>> quotes}) sheetRowsFor(
  String label,
  String cv,
  Map<String, List<Map<String, String>>> areas,
  String cvText,
) {
  final sheet = <List<String>>[];
  final quotes = <List<String>>[];
  for (final area in areaKeys) {
    final items = areas[area] ?? const [];
    for (var i = 0; i < items.length; i++) {
      final n = '${i + 1}';
      final notInCv = <String>[];
      for (final field in const ['issue', 'suggestion']) {
        for (final span in quotedSpans(items[i][field] ?? '')) {
          final found = quoteInCv(span, cvText);
          if (!found) notInCv.add(span);
          quotes.add([
            label,
            cv,
            area,
            n,
            field,
            span,
            found ? 'in CV' : 'NOT in CV',
          ]);
        }
      }
      sheet.add([
        label,
        cv,
        area,
        n,
        items[i]['issue'] ?? '',
        items[i]['suggestion'] ?? '',
        notInCv.join(' | '),
        '',
        '',
        '',
        '',
        '',
        '',
      ]);
    }
  }
  if (sheet.isEmpty) {
    sheet.add([label, cv, '(none)', '', '', '', '', 'EMPTY', '', '', '', '', '']);
  }
  return (sheet: sheet, quotes: quotes);
}

/// A sheet cell as it reads back from the CSV file.
String cellAsRead(String value) =>
    value.replaceAll('\r', ' ').replaceAll('\n', ' ').trim();
