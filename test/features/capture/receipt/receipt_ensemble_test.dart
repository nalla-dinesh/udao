// phase-04
// Ensemble semantics: rules first; below 0.7 the model leg is
// consulted. Today the model is absent (Err('model-absent')) and the
// rules draft survives; a landed model (Phase 06) wins instead. OCR
// failure is the only hard error.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/features/capture/ports/receipt_ocr.dart';
import 'package:udao/features/capture/receipt/receipt_parsed.dart';
import 'package:udao/features/capture/receipt/receipt_parser.dart';

class _FakeOcr implements ReceiptOcr {
  _FakeOcr(this.text);
  final String text;

  @override
  Future<Result<String>> recognizeText(String imagePath) async =>
      Ok(text);
}

class _DeadOcr implements ReceiptOcr {
  @override
  Future<Result<String>> recognizeText(String imagePath) async =>
      const Err<String>(ModelFailure('ocr_failed'));
}

class _RecordingModel implements ReceiptModelParser {
  _RecordingModel(this.draft);
  final ParsedReceipt? draft;
  int calls = 0;

  @override
  Future<Result<ParsedReceipt>> parseImage(String imagePath) async {
    calls++;
    return draft == null
        ? const Err<ParsedReceipt>(ModelFailure('model-absent'))
        : Ok(draft!);
  }
}

void main() {
  test('clean receipt: rules clear the bar, model never called', () async {
    final _RecordingModel model = _RecordingModel(null);
    final EnsembleReceiptParser parser = EnsembleReceiptParser(
      ocr: _FakeOcr('SWIGGY LIMITED\nDate: 12/06/2026\nTOTAL ₹349.00\n'),
      model: model,
    );
    final Result<ParsedReceipt> r = await parser.parse('/img.jpg');
    expect(r.valueOrNull!.total!.paise, 34900);
    expect(model.calls, 0);
  });

  test('weak receipt + absent model: rules draft survives, leg ran',
      () async {
    final _RecordingModel model = _RecordingModel(null);
    final EnsembleReceiptParser parser = EnsembleReceiptParser(
      ocr: _FakeOcr('garbled ocr\nn0 real am0unt here\n'),
      model: model,
    );
    final Result<ParsedReceipt> r = await parser.parse('/img.jpg');
    expect(r, isA<Ok<ParsedReceipt>>());
    expect(r.valueOrNull!.total, isNull);
    expect(model.calls, 1, reason: 'escalation must fire below 0.7');
  });

  test('weak receipt + landed model: the model draft wins (Phase 06+)',
      () async {
    const ParsedReceipt modelDraft = ParsedReceipt(
      rawText: '',
      confidence: 0.9,
      merchant: 'Swiggy',
    );
    final _RecordingModel model = _RecordingModel(modelDraft);
    final EnsembleReceiptParser parser = EnsembleReceiptParser(
      ocr: _FakeOcr('garbled ocr\nn0 real am0unt here\n'),
      model: model,
    );
    final Result<ParsedReceipt> r = await parser.parse('/img.jpg');
    expect(identical(r.valueOrNull, modelDraft), isTrue);
  });

  test('OCR failure is the only hard error', () async {
    final EnsembleReceiptParser parser = EnsembleReceiptParser(
      ocr: _DeadOcr(),
      model: _RecordingModel(null),
    );
    final Result<ParsedReceipt> r = await parser.parse('/img.jpg');
    expect(r, isA<Err<ParsedReceipt>>());
    expect((r as Err<ParsedReceipt>).failure, isA<ModelFailure>());
  });
}
