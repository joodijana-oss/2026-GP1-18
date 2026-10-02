import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

// Thrown when a CV file cannot be used. [message] is ready to show the user.
class CvReadException implements Exception {
  final String message;
  const CvReadException(this.message);

  @override
  String toString() => message;
}

class CvService {
  static const String unsupportedFormatMessage =
      'Unsupported file format. Please upload your CV as a PDF file.';
  static const String unreadableMessage =
      'The uploaded PDF could not be read. Please upload a valid PDF file.';

  // Checks the file and returns the CV text.
  // Throws CvReadException with the backlog message when the file is not usable.
  static String extractText({
    required String fileName,
    required Uint8List bytes,
  }) {
    if (!fileName.toLowerCase().endsWith('.pdf')) {
      throw const CvReadException(unsupportedFormatMessage);
    }

    if (bytes.isEmpty) {
      throw const CvReadException(unreadableMessage);
    }

    try {
      final document = PdfDocument(inputBytes: bytes);
      final text = PdfTextExtractor(document).extractText();
      document.dispose();

      final cleanText = text.trim();

      // Empty text = scanned image PDF, nothing to analyze
      if (cleanText.isEmpty) {
        throw const CvReadException(unreadableMessage);
      }

      return cleanText;
    } on CvReadException {
      rethrow;
    } catch (_) {
      throw const CvReadException(unreadableMessage);
    }
  }
}
