import 'dart:io';

import 'package:masra/models/gap_link.dart';
import 'package:masra/services/analysis_requests.dart';
import 'package:masra/services/career_analysis_pipeline.dart';
import 'package:masra/utils/skill_matcher.dart';

import 'eval_support.dart';

/// Shared by the tools that send link requests (link_lists.dart,
/// final_matching.dart and tools/recommender_eval/link_persona_gaps.dart).
/// The request and the reading of its answer are the app's own
/// (linkSkillsToConcepts and CareerAnalysisPipeline.linksFrom).

/// The career goals whose market names decide the final measurement. No
/// tool asks for their market skills, or for links of their names, before
/// that measurement.
const List<String> decisionGoals = [
  'data_scientist',
  'business_analyst',
  'it_consultant',
  'data_engineer',
];

/// The career goals the prompt examples come from. Their names never count
/// in a decision.
const List<String> promptExampleGoals = ['product_manager', 'telecom_engineer'];

LinkRequest linkRequestOf(String text) => switch (text) {
      'names' => LinkRequest.names,
      'typed' => LinkRequest.typed,
      _ => fail('Unknown link request "$text" (use names or typed).'),
    };

/// The exclusion list stores names as short hashes, so no skill name is
/// ever written into a file of the repository by it.
String nameHash(String key) => sha256OfText(key).substring(0, 16);

/// The two keys a name is excluded by: its normalized form and its synonym
/// table form, both hashed.
List<String> exclusionKeys(String name) => {
      nameHash(SkillMatcher.normalize(name)),
      nameHash(SkillMatcher.canonical(name)),
    }.toList();

/// Sends link requests and counts what they cost.
class LinkRequester {
  LinkRequester({UsageMeter? meter, CatalogueNames? names})
      : meter = meter ?? UsageMeter(),
        names = names ??
            loadCatalogueNames(loadOpportunities(), loadCertifications()) {
    _ai = newAi(meter: this.meter);
  }

  final UsageMeter meter;
  final CatalogueNames names;
  late final AnalysisRequests _ai;
  int failed = 0;

  /// The time limit of the app's own link request.
  static const Duration limit = Duration(seconds: 45);

  /// What one request for [skills] is expected to cost, in tokens: the
  /// prompt as it will be sent, and an answer of about 60 tokens per skill
  /// for the typed request and 50 for the first one, both multiplied by
  /// what the answers really reported ([inputFactor], [outputFactor]).
  ({int input, int output}) estimate(List<String> skills, LinkRequest request) {
    return (
      input: (roughTokens(linkPromptOf(request, skills, names.concepts)) *
              inputFactor)
          .ceil(),
      output: ((30 + skills.length * (request == LinkRequest.typed ? 60 : 50)) *
              outputFactor)
          .ceil(),
    );
  }

  /// The rough count of four characters per token is too low for these
  /// prompts: the long list of short catalogue names takes more tokens.
  /// The development link requests (47 market lists and 47 persona
  /// requests) reported 1.53 times the rough input count and 1.15 to 1.21
  /// times the output estimate, so the estimate printed before a batch
  /// uses these factors and is not too low.
  static const double inputFactor = 1.55;
  static const double outputFactor = 1.25;

  /// The links of [skills], or null when the request failed. A request
  /// that is refused because too many were sent (HTTP 429) waits and is
  /// sent again, up to 3 times; another failure is tried once more. A
  /// billing or credit error is never retried: it is rethrown as
  /// [CreditStop], and the caller stops.
  Future<List<GapLink>?> request(
    List<String> skills,
    LinkRequest request,
  ) async {
    if (skills.isEmpty) return const [];
    var busy = 0;
    var retried = false;
    while (true) {
      try {
        final raw = await _ai
            .linkSkillsToConcepts(
              skills: skills,
              concepts: names.concepts,
              request: request,
              timeLimit: limit,
            )
            .timeout(limit);
        return CareerAnalysisPipeline.linksFrom(
          raw,
          skills: skills,
          concepts: names.concepts,
        );
      } on CreditStop {
        rethrow;
      } catch (error) {
        if (meter.stopped != null) throw meter.stopped!;
        final text = error.toString();
        if (text.contains(' 429') && busy < 3) {
          busy++;
          await Future<void>.delayed(Duration(seconds: 15 * busy));
          continue;
        }
        if (!retried) {
          retried = true;
          continue;
        }
        failed++;
        return null;
      }
    }
  }
}

/// Prints the estimate of a batch and returns its cost in USD.
double printEstimate(
  String title,
  Iterable<({int input, int output})> requests, {
  double inputPrice = 2,
  double outputPrice = 10,
}) {
  var count = 0, input = 0, output = 0;
  for (final r in requests) {
    count++;
    input += r.input;
    output += r.output;
  }
  final cost = (input * inputPrice + output * outputPrice) / 1e6;
  stdout.writeln('$title: $count requests, about $input input and $output '
      'output tokens, about ${cost.toStringAsFixed(2)} USD '
      '(2 USD per million input tokens, 10 per million output).');
  return cost;
}
