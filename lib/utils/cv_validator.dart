// ============================================================
// CV VALIDATOR
// Checks a picked CV file before it's accepted.
// Order: format -> size (before reading) -> parse -> page count -> content.
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class CvValidationResult {
  // Ready-to-show message, or null when the CV is valid
  final String? error;

  final Uint8List? bytes;
  final String? text;
  final int? pageCount;
  final int? sizeInBytes;

  const CvValidationResult.valid({
    required Uint8List this.bytes,
    required String this.text,
    required int this.pageCount,
    required int this.sizeInBytes,
  }) : error = null;

  const CvValidationResult.invalid(String this.error)
      : bytes = null,
        text = null,
        pageCount = null,
        sizeInBytes = null;

  bool get isValid => error == null;
}

// Result of parsing the PDF (runs in a background isolate)
class _PdfContent {
  final int pageCount;
  final String text;
  const _PdfContent(this.pageCount, this.text);
}

class CvValidator {
  CvValidator._();

  static const int maxSizeInBytes = 5 * 1024 * 1024;
  static const int maxPages = 3;

  static const String formatMessage =
      'Unsupported file format. Please upload your CV as a PDF file.';
  static const String tooLargeMessage =
      'File is too large. Maximum size is 5 MB.';
  static const String tooManyPagesMessage = 'Your CV must be 3 pages or less.';
  static const String emptyMessage =
      'This file appears to be empty. Please upload a CV with content.';
  static const String unreadableMessage =
      "We couldn't read this file. Please upload a valid PDF.";

  // [sizeInBytes] = size reported by the picker (null if unknown).
  // [readBytes] is only called after the size check passes.
  static Future<CvValidationResult> validate({
    required String fileName,
    required int? sizeInBytes,
    required Future<Uint8List> Function() readBytes,
  }) async {
    // 1) PDF only
    if (!fileName.toLowerCase().endsWith('.pdf')) {
      _log('"$fileName" is not a PDF');
      return _reject(formatMessage);
    }

    // 2) Size, before opening the file
    if (sizeInBytes != null && sizeInBytes > maxSizeInBytes) {
      _log('"$fileName" picker reported size=$sizeInBytes bytes');
      return _reject(tooLargeMessage);
    }

    final Uint8List bytes;
    try {
      bytes = await readBytes();
    } catch (e) {
      _log('"$fileName" could not be read: $e');
      return _reject(unreadableMessage);
    }

    // Size again in case the picker didn't report it
    if (bytes.length > maxSizeInBytes) {
      _log('"$fileName" size=${bytes.length} bytes');
      return _reject(tooLargeMessage);
    }

    if (bytes.isEmpty) {
      _log('"$fileName" size=0 bytes');
      return _reject(emptyMessage);
    }

    // 3) Open / parse (off the UI thread so the loader keeps spinning)
    final _PdfContent? content = await compute(_readPdf, bytes);

    _log(
      '"$fileName" size=${bytes.length} bytes '
      '(picker reported ${sizeInBytes ?? 'unknown'}), '
      'pages=${content?.pageCount ?? 'unreadable'}, '
      'textLength=${content?.text.length ?? 0}',
    );

    if (content == null) {
      return _reject(unreadableMessage);
    }

    // 4) Page count
    if (content.pageCount > maxPages) {
      return _reject(tooManyPagesMessage);
    }

    // 5) No pages or no readable text
    // Note: scanned image-only PDFs have no text, so they land here too.
    if (content.pageCount < 1 || content.text.isEmpty) {
      return _reject(emptyMessage);
    }

    _log('accepted');

    return CvValidationResult.valid(
      bytes: bytes,
      text: content.text,
      pageCount: content.pageCount,
      sizeInBytes: bytes.length,
    );
  }

  static CvValidationResult _reject(String message) {
    _log('rejected: $message');
    return CvValidationResult.invalid(message);
  }

  // Debug builds only
  static void _log(String message) {
    if (kDebugMode) debugPrint('[CvValidator] $message');
  }

  // Returns null when the PDF can't be opened or parsed
  static _PdfContent? _readPdf(Uint8List bytes) {
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      final pageCount = document.pages.count;

      // Skip text extraction for files that will be rejected anyway
      if (pageCount < 1 || pageCount > maxPages) {
        return _PdfContent(pageCount, '');
      }

      final text = PdfTextExtractor(document).extractText().trim();
      return _PdfContent(pageCount, text);
    } catch (_) {
      return null;
    } finally {
      document?.dispose();
    }
  }

  // e.g. "820 KB", "1.4 MB"
  static String formatSize(int bytes) {
    if (bytes < 1024 * 1024) {
      final kb = (bytes / 1024).ceil();
      return '$kb KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
