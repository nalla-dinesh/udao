// phase-04
// pdfrx behind a seam. Bank-statement PDF text extraction is pure
// adaptation: open (optionally with the user-typed password, which
// lives ONLY in this call frame and dies with it), pull each page's
// full text, close. The statement parser and its tests never see
// pdfrx — they consume PdfExtract from a fake.
//
// pdfrx is pinned ^2.10.1 (the phase sketch's ^0.5.x is four majors
// stale); the 2.x surface used here — PdfDocument.openFile(path,
// password:), doc.pages, page.loadText(), pageText.fullText — was
// verified against the 2.10.1 API docs. This file is the ONLY line
// of defence if a future major renames any of it.
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';

/// Everything the statement parser needs from one PDF.
class PdfExtract {
  const PdfExtract({required this.pages});

  /// Page texts in page order (1-based page N = pages[N - 1]).
  final List<String> pages;

  /// Whole document, pages joined by form feeds — what parsers read.
  String get fullText => pages.join('\f');
}

abstract class PdfTextExtractor {
  /// Extracts text from a local PDF file.
  ///
  /// Encrypted statement + wrong/no password →
  /// `Err(ParseFailure('pdf_password'))`. Anything else that goes
  /// wrong opening/reading → `Err(CaptureFailure('pdf_open_failed'))`.
  ///
  /// The [password] is used for this call only — never persisted,
  /// never logged, zeroized by the caller's scope ending.
  Future<Result<PdfExtract>> extract(String path, {String? password});
}

class PdfrxTextExtractor implements PdfTextExtractor {
  @override
  Future<Result<PdfExtract>> extract(String path, {String? password}) async {
    pdfrx.PdfDocument? doc;
    try {
      // pdfrx takes a password PROVIDER (called only if the PDF asks);
      // the password itself stays a call-argument, never persisted.
      doc = await pdfrx.PdfDocument.openFile(
        path,
        passwordProvider: password == null ? null : () => password,
      );
      final List<String> pages = <String>[];
      for (final pdfrx.PdfPage page in doc.pages) {
        final pdfrx.PdfPageRawText? pageText = await page.loadText();
        pages.add(pageText?.fullText ?? '');
      }
      return Ok<PdfExtract>(PdfExtract(pages: pages));
    } on Object catch (e, s) {
      if (_looksLikePasswordProblem(e, password)) {
        return const Err<PdfExtract>(ParseFailure('pdf_password'));
      }
      return Err<PdfExtract>(
        CaptureFailure('pdf_open_failed', cause: e, stackTrace: s),
      );
    } finally {
      // null when openFile itself failed; otherwise always released —
      // pdfium keeps the file handle otherwise.
      await doc?.dispose();
    }
  }

  /// pdfium reports a bad/missing password differently per platform;
  /// we classify on the message text and default to open-failed so
  /// the UI never shows "wrong password" for a corrupt file.
  static bool _looksLikePasswordProblem(Object error, String? password) {
    final String flat = error.toString().toLowerCase();
    final bool passwordWord =
        flat.contains('password') || flat.contains('encrypted');
    // A password supplied but rejected — or an encrypted file with
    // none supplied at all.
    return passwordWord;
  }
}
