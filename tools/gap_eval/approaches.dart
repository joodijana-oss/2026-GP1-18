import 'package:masra/models/gap_link.dart';

import 'eval_support.dart';

/// Where an approach takes its links from.
enum LinkSource {
  /// No links (today's matching).
  none,

  /// The word-only control (word_control.dart).
  words,

  /// The stored answers of the first link request (catalogue names and
  /// phrases).
  names,

  /// The stored answers of the typed link request.
  typed,
}

/// One approach of the matching evaluation: where the links come from and
/// how each recommender uses them. Nothing here is shipped; the app's own
/// switches are the constants in lib/models/gap_link.dart.
///
/// Ids (pass them with --approaches, thetas as hundredths: 03, 05, 10):
///   A0                 today: words and the synonym table, no links.
///   L1                 the word control, every link counts.
///   L1g/`o`/`c`[/t]    the word control with the support gate.
///   M1                 the first request's links, every link counts.
///   M2                 M1 and its phrases searched in the texts.
///   A/`o`/`c`[/p][/t][/r]
///                      the first request's links with the support gate:
///                      theta `o` for opportunities and `c` for
///                      certifications; p = the stored phrases count as
///                      support, t = skill tags count as own text, r =
///                      (opportunities) an unsupported course keeps its
///                      rank but the gap is not named on it.
///   B/`o`/`c`[/t][/bt] the typed request's links: same-skill names count
///                      like a tag, broader names need support, the terms
///                      count as support. bt = a term of two words or more
///                      is evidence for a gap with no linked name.
///   Bs[/bt]            B with the broader names ignored.
///   APP                what the app runs: the constants of
///                      lib/models/gap_link.dart, read as they are now. It
///                      is there to check the shipped code against the
///                      measured approach, and is never a candidate.
/// Any id may end in "-opp": certifications then use no links at all.
class Approach {
  final String id;
  final LinkSource source;
  final LinkSettings opportunities;
  final LinkSettings certifications;

  const Approach(this.id, this.source, this.opportunities, this.certifications);

  LinkSettings settingsFor(String type) =>
      type == 'opportunity' ? opportunities : certifications;

  static const List<String> thetas = ['03', '05', '10'];

  /// The id of what the app runs.
  static const String appId = 'APP';

  /// Where the links of the app come from: nowhere while the app sends no
  /// link request, otherwise the stored answers of the request it sends.
  static LinkSource get appSource {
    const requested = LinkSettings.requestedByApp;
    if (!requested) return LinkSource.none;
    return LinkSettings.appRequest == LinkRequest.typed
        ? LinkSource.typed
        : LinkSource.names;
  }

  factory Approach.parse(String text) {
    final id = text.trim();
    final opportunitiesOnly = id.endsWith('-opp');
    final parts =
        (opportunitiesOnly ? id.substring(0, id.length - 4) : id).split('/');
    Never bad() => fail('Unknown approach "$text". See the ids in '
        'tools/gap_eval/approaches.dart.');
    double theta(int position) {
      if (parts.length <= position || !thetas.contains(parts[position])) bad();
      return int.parse(parts[position]) / 100;
    }

    final flags = parts.length > 3 ? parts.sublist(3).toSet() : <String>{};
    void allow(Set<String> allowed) {
      if (!allowed.containsAll(flags)) bad();
    }

    LinkSource source;
    LinkSettings opportunities;
    LinkSettings certifications;
    switch (parts.first) {
      case 'A0':
        if (parts.length > 1) bad();
        source = LinkSource.none;
        opportunities = certifications = LinkSettings.off;
      case appId:
        if (parts.length > 1 || opportunitiesOnly) bad();
        source = appSource;
        opportunities = LinkSettings.appOpportunities;
        certifications = LinkSettings.appCertifications;
      case 'L1':
      case 'M1':
        if (parts.length > 1) bad();
        source = parts.first == 'L1' ? LinkSource.words : LinkSource.names;
        opportunities = certifications = LinkSettings.ungated;
      case 'M2':
        if (parts.length > 1) bad();
        source = LinkSource.names;
        opportunities = certifications =
            const LinkSettings(supportGate: false, phraseSearch: true);
      case 'L1g':
        allow(const {'t'});
        source = LinkSource.words;
        opportunities =
            LinkSettings(theta: theta(1), tagSupport: flags.contains('t'));
        certifications =
            LinkSettings(theta: theta(2), tagSupport: flags.contains('t'));
      case 'A':
        allow(const {'p', 't', 'r'});
        source = LinkSource.names;
        opportunities = LinkSettings(
          theta: theta(1),
          termSupport: flags.contains('p'),
          tagSupport: flags.contains('t'),
          reasonOnly: flags.contains('r'),
        );
        certifications = LinkSettings(
          theta: theta(2),
          termSupport: flags.contains('p'),
          tagSupport: flags.contains('t'),
        );
      case 'B':
        allow(const {'t', 'bt'});
        source = LinkSource.typed;
        opportunities = LinkSettings(
          theta: theta(1),
          termSupport: true,
          tagSupport: flags.contains('t'),
          termEvidence: flags.contains('bt'),
        );
        certifications = LinkSettings(
          theta: theta(2),
          termSupport: true,
          tagSupport: flags.contains('t'),
          termEvidence: flags.contains('bt'),
        );
      case 'Bs':
        final bt = parts.length == 2 && parts[1] == 'bt';
        if (parts.length > 2 || (parts.length == 2 && !bt)) bad();
        source = LinkSource.typed;
        opportunities = certifications =
            LinkSettings(useCovers: false, termEvidence: bt);
      default:
        bad();
    }
    return Approach(
      id,
      source,
      opportunities,
      opportunitiesOnly ? LinkSettings.off : certifications,
    );
  }

  /// Every setting of one family ("A" or "B"), for the development
  /// selection. r is left out: it is judged on the persona guard only.
  static List<Approach> grid(String family) {
    final ids = <String>[];
    switch (family) {
      case 'A':
        for (final o in thetas) {
          for (final c in thetas) {
            for (final flags in const ['', '/p', '/t', '/p/t']) {
              ids.add('A/$o/$c$flags');
            }
          }
        }
      case 'B':
        for (final o in thetas) {
          for (final c in thetas) {
            for (final flags in const ['', '/t', '/bt', '/t/bt']) {
              ids.add('B/$o/$c$flags');
            }
          }
        }
        ids.addAll(const ['Bs', 'Bs/bt']);
      default:
        fail('Unknown family "$family" (use A or B).');
    }
    return [for (final id in ids) Approach.parse(id)];
  }

  /// The word control with the same gate as this approach (same theta and
  /// tag switch, no terms: terms need the AI model). It differs from the
  /// approach only in where the links come from. Its id is the control's
  /// own id ("L1g/10/05", "L1g/10/05-opp", "L1"), so two approaches with
  /// the same gate share one control.
  Approach get gatedControl {
    LinkSettings like(LinkSettings s) => !s.enabled
        ? LinkSettings.off
        : (s.supportGate && s.useCovers
            ? LinkSettings(theta: s.theta, tagSupport: s.tagSupport)
            : LinkSettings.ungated);
    final opp = like(opportunities);
    final cert = like(certifications);
    String hundredths(double theta) =>
        (theta * 100).round().toString().padLeft(2, '0');
    bool gated(LinkSettings s) => s.enabled && s.supportGate;

    String? controlId;
    if (gated(opp) && gated(cert) && opp.tagSupport == cert.tagSupport) {
      controlId = 'L1g/${hundredths(opp.theta)}/${hundredths(cert.theta)}'
          '${opp.tagSupport ? '/t' : ''}';
    } else if (gated(opp) && !cert.enabled) {
      // The certification theta does not matter when they use no links.
      controlId = 'L1g/${hundredths(opp.theta)}/05'
          '${opp.tagSupport ? '/t' : ''}-opp';
    } else if (opp.enabled && !opp.supportGate) {
      if (cert.enabled && !cert.supportGate) controlId = 'L1';
      if (!cert.enabled) controlId = 'L1-opp';
    }
    // Only ids that parse (thetas of the grid); the settings must then be
    // exactly the control's, or the long form is used.
    final parts = controlId?.replaceAll('-opp', '').split('/');
    if (controlId != null &&
        (parts!.first == 'L1' ||
            (thetas.contains(parts[1]) && thetas.contains(parts[2])))) {
      final control = Approach.parse(controlId);
      if (settingKey(LinkSource.words, control.opportunities) ==
              settingKey(LinkSource.words, opp) &&
          settingKey(LinkSource.words, control.certifications) ==
              settingKey(LinkSource.words, cert)) {
        return control;
      }
    }
    return Approach('L1g~$id', LinkSource.words, opp, cert);
  }
}

/// A short text that identifies how one catalogue is run, so two approaches
/// that treat a catalogue the same way share their results.
String settingKey(LinkSource source, LinkSettings s) => !s.enabled ||
        source == LinkSource.none
    ? 'off'
    : '${source.name}|${s.supportGate}|${s.theta}|${s.termSupport}|'
        '${s.tagSupport}|${s.reasonOnly}|${s.useCovers}|${s.termEvidence}|'
        '${s.phraseSearch}';
