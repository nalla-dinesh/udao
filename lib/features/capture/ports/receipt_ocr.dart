// phase-04
// google_mlkit_text_recognition behind a seam. Receipt OCR is
// ON-DEVICE ONLY — ML Kit's bundled latin recognizer, no network
// call, no image ever leaves the phone. The recognizer instance is
// created per call and closed in finally: ML Kit holds native
// memory that Dart GC will not collect on its own.
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as ml;
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';

abstract class ReceiptOcr {
  /// Full OCR text of the receipt image at [imagePath], reading
  /// order. `Err(ModelFailure('ocr_failed'))` on any native failure.
  Future<Result<String>> recognizeText(String imagePath);
}

class MlKitReceiptOcr implements ReceiptOcr {
  @override
  Future<Result<String>> recognizeText(String imagePath) async {
    final ml.TextRecognizer recognizer = ml.TextRecognizer(
      script: ml.TextRecognitionScript.latin,
    );
    try {
      final ml.InputImage image = ml.InputImage.fromFilePath(imagePath);
      final ml.RecognizedText visionText = await recognizer.processImage(image);
      return Ok<String>(visionText.text);
    } on Object catch (e, s) {
      return Err<String>(
        ModelFailure('ocr_failed', cause: e, stackTrace: s),
      );
    } finally {
      await recognizer.close();
    }
  }
}
