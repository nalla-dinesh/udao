// phase-04
// The receipt-parsing interface + ensemble strategy. The interface
// takes an image PATH (not an XFile): a plain string keeps the seam
// plugin-free, so the ensemble unit-tests without any image package
// on the classpath. Callers already hold the picked file's path.
//
// Ensemble (spec): rules parser first; if its confidence is below
// 0.70, escalate to the model leg. The model leg is Phase 06's
// on-device Gemma-vision parser — until then it is wired as an
// explicit `Err(ModelFailure('model-absent'))`, so the ensemble's
// failure mode is a human-confirm form with whatever the rules found
// (receipts are ALWAYS human-confirmed anyway).
//
// ML Kit OCR itself lives behind the ReceiptOcr seam (ports/), fully
// offline — no image or text ever leaves the device.
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';

import '../ports/receipt_ocr.dart';
import 'receipt_parsed.dart';
import 'receipt_rules_parser.dart';

/// Phase-06 drop-in: on-device vision model over the same OCR/image.
abstract class ReceiptModelParser {
  Future<Result<ParsedReceipt>> parseImage(String imagePath);
}

/// The wire-today model leg: Phase 06 is not built yet.
class AbsentReceiptModel implements ReceiptModelParser {
  @override
  Future<Result<ParsedReceipt>> parseImage(String imagePath) async {
    return const Err<ParsedReceipt>(ModelFailure('model-absent'));
  }
}

/// Ensemble receipt parser: OCR → rules → (escalate) → draft.
class EnsembleReceiptParser {
  EnsembleReceiptParser({
    required ReceiptOcr ocr,
    ReceiptModelParser? model,
    this.modelEscalationMin = 0.70,
  })  : _ocr = ocr,
        _model = model ?? AbsentReceiptModel();

  final ReceiptOcr _ocr;
  final ReceiptModelParser _model;
  final double modelEscalationMin;

  /// Full pipeline for one receipt image. Result carries the draft
  /// for the human-confirm form; `Err` only for hard failures
  /// (OCR dead, unreadable file).
  Future<Result<ParsedReceipt>> parse(String imagePath) async {
    final Result<String> ocr = await _ocr.recognizeText(imagePath);
    if (ocr is Err<String>) {
      return Err(ocr.failure);
    }
    final ParsedReceipt rules =
        ReceiptRulesParser.parse(ocr.valueOrNull ?? '');
    if (rules.confidence < modelEscalationMin) {
      // Model leg: absent until Phase 06 (Err('model-absent')). When
      // a model lands and wins, ITS draft is returned; until then
      // the rules draft is the best we have and the user confirms
      // either way.
      final Result<ParsedReceipt> modelDraft =
          await _model.parseImage(imagePath);
      if (modelDraft is Ok<ParsedReceipt>) {
        return modelDraft;
      }
    }
    return Ok(rules);
  }
}
