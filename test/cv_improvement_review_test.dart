import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:masra/services/claude_service.dart' show AnalysisAi;

/// The ATS review (CV Improvement Assistant): its text, how its inputs go
/// in, how its answer is parsed, and how it is sent. No request leaves the
/// machine: every request goes to a MockClient.
void main() {
  String placeholderText() => AnalysisAi.cvImprovementPrompt(
        cvText: '{{CV_TEXT}}',
        careerName: '{{CAREER_NAME}}',
        today: '{{TODAY}}',
      );

  String jsonBlockOf(String text) {
    const marker = 'Return EXACTLY this JSON structure:';
    final at = text.indexOf(marker);
    expect(at, greaterThanOrEqualTo(0));
    return text.substring(text.indexOf('{', at));
  }

  String todayNow() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  http.Response answer(Object body, {int status = 200}) => http.Response(
        jsonEncode({
          'stop_reason': 'end_turn',
          'content': [
            {'type': 'text', 'text': body is String ? body : jsonEncode(body)},
          ],
        }),
        status,
      );

  const emptyReview = {
    'cvStructure': [],
    'sectionOrganization': [],
    'keywordUsage': [],
    'readability': [],
    'contentFormatting': [],
  };

  group('the review text', () {
    test('lists the five areas once each, in the screen order', () {
      final text = placeholderText();
      var last = -1;
      for (var i = 0; i < AnalysisAi.cvImprovementAreaKeys.length; i++) {
        final key = AnalysisAi.cvImprovementAreaKeys[i];
        final pattern = RegExp('^${i + 1}\\. $key\$', multiLine: true);
        expect(pattern.allMatches(text).length, 1, reason: key);
        final at = pattern.firstMatch(text)!.start;
        expect(at, greaterThan(last), reason: key);
        last = at;
      }
      expect(AnalysisAi.cvImprovementAreaKeys, [
        'cvStructure',
        'sectionOrganization',
        'keywordUsage',
        'readability',
        'contentFormatting',
      ]);
    });

    test('keeps the JSON block of the old text, byte for byte', () {
      final old = File('tools/ats_eval/old_improve_cv_prompt.txt')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      final block = jsonBlockOf(placeholderText());
      expect(block, jsonBlockOf(old));
      final decoded = jsonDecode(block) as Map<String, dynamic>;
      expect(decoded.keys.toList(), AnalysisAi.cvImprovementAreaKeys);
    });

    test('puts the inputs in exactly as given', () {
      const cv = 'Built a \$5 budget tool with "quoted" words\n'
          '{{TODAY}} stays as written\r\nLast line';
      final text = AnalysisAi.cvImprovementPrompt(
        cvText: cv,
        careerName: 'Data Analyst',
        today: '2026-11-22',
      );
      expect(text, contains('CV TEXT\n----------------\n$cv\n'
          '----------------\n'));
      expect(text, contains('TARGET CAREER GOAL:\nData Analyst\n'));
      expect(text, contains("TODAY'S DATE:\n2026-11-22\n"));
      expect('{{TODAY}}'.allMatches(text).length, 1);
      expect(text.contains('\r\nLast line'), isTrue);
    });

    test('has no carriage return of its own', () {
      expect(placeholderText().contains('\r'), isFalse);
    });
  });

  group('cvImprovementFrom', () {
    test('keeps only full items, trimmed, in the five areas in order', () {
      final result = AnalysisAi().cvImprovementFrom({
        'readability': [
          {'issue': '  A long entry.  ', 'suggestion': ' Split it. ', 'x': 1},
          {'issue': 'Only an issue', 'suggestion': ''},
          {'issue': '', 'suggestion': 'Only a suggestion'},
          {'suggestion': 'No issue key'},
          'not a map',
        ],
        'sectionOrganization': 'not a list',
        'keywordUsage': null,
        'somethingElse': [
          {'issue': 'ignored', 'suggestion': 'ignored'},
        ],
      });
      expect(result.keys.toList(), AnalysisAi.cvImprovementAreaKeys);
      expect(result['readability'], [
        {'issue': 'A long entry.', 'suggestion': 'Split it.'},
      ]);
      for (final key in [
        'cvStructure',
        'sectionOrganization',
        'keywordUsage',
        'contentFormatting',
      ]) {
        expect(result[key], isEmpty, reason: key);
      }
    });
  });

  group('improveCv', () {
    test('sends one request the way the review is sent and parses a fenced '
        'answer', () async {
      final bodies = <Map<String, dynamic>>[];
      final ai = AnalysisAi()
        ..apiKey = 'test-key'
        ..client = MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return answer('```json\n${jsonEncode({
                ...emptyReview,
                'cvStructure': [
                  {'issue': 'No phone number.', 'suggestion': 'Add one.'},
                ],
              })}\n```');
        });
      final before = todayNow();
      final result = await ai.improveCv(
          cvText: 'Sample CV text', careerName: 'Web Developer');
      final after = todayNow();

      expect(bodies, hasLength(1));
      final body = bodies.single;
      expect(body['max_tokens'], 10000);
      expect(body.containsKey('thinking'), isFalse);
      final sent = (body['messages'] as List).single['content'];
      expect(sent, anyOf(
        AnalysisAi.cvImprovementPrompt(
            cvText: 'Sample CV text', careerName: 'Web Developer',
            today: before),
        AnalysisAi.cvImprovementPrompt(
            cvText: 'Sample CV text', careerName: 'Web Developer',
            today: after),
      ));
      expect(result['cvStructure'], [
        {'issue': 'No phone number.', 'suggestion': 'Add one.'},
      ]);
      expect(result.keys.toList(), AnalysisAi.cvImprovementAreaKeys);
    });

    test('tries once more after a failure', () async {
      var calls = 0;
      final ai = AnalysisAi()
        ..apiKey = 'test-key'
        ..client = MockClient((request) async {
          calls++;
          if (calls == 1) return http.Response('server error', 500);
          return answer(emptyReview);
        });
      final result =
          await ai.improveCv(cvText: 'CV', careerName: 'Software Engineer');
      expect(calls, 2);
      expect(result.keys.toList(), AnalysisAi.cvImprovementAreaKeys);
    });

    test('gives up after two failures', () async {
      var calls = 0;
      final ai = AnalysisAi()
        ..apiKey = 'test-key'
        ..client = MockClient((request) async {
          calls++;
          return http.Response('server error', 500);
        });
      await expectLater(
        ai.improveCv(cvText: 'CV', careerName: 'Software Engineer'),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), 'text', contains('CV review failed'))),
      );
      expect(calls, 2);
    });
  });

  group('requestJson', () {
    Future<Map<String, dynamic>> sentBody({bool? enableThinking}) async {
      Map<String, dynamic>? body;
      final ai = AnalysisAi()
        ..apiKey = 'test-key'
        ..client = MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return answer({'ok': true});
        });
      if (enableThinking == null) {
        await ai.requestJson(prompt: 'P', maxTokens: 1234);
      } else {
        await ai.requestJson(
            prompt: 'P', maxTokens: 1234, enableThinking: enableThinking);
      }
      return body!;
    }

    test('keeps thinking off unless asked', () async {
      final body = await sentBody();
      expect(body['thinking'], {'type': 'disabled'});
      expect(body['max_tokens'], 1234);
    });

    test('sends no thinking field when thinking is on', () async {
      final body = await sentBody(enableThinking: true);
      expect(body.containsKey('thinking'), isFalse);
      expect(body['max_tokens'], 1234);
    });
  });
}
