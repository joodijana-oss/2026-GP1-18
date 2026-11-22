import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masra/utils/cv_validator.dart';

/// Writes the text the app extracts from each PDF, for the ATS review
/// evaluation (evaluate_ats.dart). Run by hand only; the normal test run
/// reads test/ and never runs this file:
///
/// ```text
/// flutter test tools/ats_eval/extract_cv_text_test.dart
///     --dart-define=ATS_PDF_DIR=<folder with PDFs>
///     --dart-define=ATS_TEXT_DIR=<folder for the texts>
/// ```
///
/// For every PDF it calls the app's own CvValidator.validate and writes
/// `result.text`, the exact text the app stores and sends, to
/// `<name>.txt`. The PDF package needs Flutter, which is why this one part
/// runs under `flutter test`.
const String pdfDir = String.fromEnvironment('ATS_PDF_DIR');
const String textDir = String.fromEnvironment('ATS_TEXT_DIR');

void main() {
  test(
    'writes the text the app extracts from every PDF',
    () async {
      final pdfs = Directory(pdfDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.pdf'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      expect(pdfs, isNotEmpty, reason: 'No PDF in $pdfDir.');
      Directory(textDir).createSync(recursive: true);
      for (final pdf in pdfs) {
        final name = pdf.uri.pathSegments.last;
        final result = await CvValidator.validate(
          fileName: name,
          sizeInBytes: null,
          readBytes: () async => Uint8List.fromList(await pdf.readAsBytes()),
        );
        expect(result.isValid, isTrue,
            reason: '$name was refused: ${result.error}');
        final out = File(
            '$textDir/${name.substring(0, name.length - '.pdf'.length)}.txt');
        out.writeAsStringSync(result.text!);
        debugPrint('${out.path}: ${result.text!.length} chars, '
            '${result.pageCount} page(s)');
      }
    },
    skip: pdfDir.isEmpty || textDir.isEmpty
        ? 'Run by hand with --dart-define=ATS_PDF_DIR=... and '
            '--dart-define=ATS_TEXT_DIR=...'
        : false,
  );
}
