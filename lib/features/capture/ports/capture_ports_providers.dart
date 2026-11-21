// phase-04
// Riverpod wiring for the Phase-04 plugin seams. Same law as
// capture_providers.dart: nothing above these providers ever imports
// a plugin package — tests override each seam with a fake.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory;

import '../../ai/ai_providers.dart' show llmRuntimeProvider;
import '../capture_providers.dart' show txnDaoProvider;
import '../import/statement_import_service.dart';
import '../receipt/gemma_vision_parser.dart';
import '../receipt/receipt_parser.dart';
import '../receipt/receipt_vault.dart';
import 'pdf_text_extractor.dart';
import 'permission_port.dart';
import 'receipt_camera.dart';
import 'receipt_ocr.dart';
import 'statement_source.dart';
import 'voice_input.dart';

/// permission_handler seam.
final Provider<PermissionPort> permissionPortProvider =
    Provider<PermissionPort>((Ref ref) => PlatformPermissionPort());

/// pdfrx seam (statement PDF text).
final Provider<PdfTextExtractor> pdfTextExtractorProvider =
    Provider<PdfTextExtractor>((Ref ref) => PdfrxTextExtractor());

/// file_picker seam (statement picking).
final Provider<StatementSource> statementSourceProvider =
    Provider<StatementSource>((Ref ref) => FilePickerStatementSource());

/// ML Kit seam (receipt OCR, offline).
final Provider<ReceiptOcr> receiptOcrProvider =
    Provider<ReceiptOcr>((Ref ref) => MlKitReceiptOcr());

/// speech_to_text seam (Bolo tab).
final Provider<VoiceInput> voiceInputProvider =
    Provider<VoiceInput>((Ref ref) => SpeechToTextInput());

/// image_picker seam (receipt camera/gallery). The picker's
/// maxWidth/imageQuality output IS the stored thumbnail — full-res
/// originals are never kept.
final Provider<ReceiptCamera> receiptCameraProvider =
    Provider<ReceiptCamera>((Ref ref) => const ImagePickerReceiptCamera());

/// Receipt OCR ensemble: ML Kit (offline) → rules → model leg
/// (absent until Phase 06).
final Provider<EnsembleReceiptParser> receiptParserProvider =
    Provider<EnsembleReceiptParser>(
      (Ref ref) =>
          EnsembleReceiptParser(
            ocr: ref.watch(receiptOcrProvider),
            model: GemmaVisionParser(
              runtime: ref.watch(llmRuntimeProvider),
            ),
          ),
    );

/// Encrypted receipt thumbnails (AES-GCM, key in secure storage).
final Provider<ReceiptVault> receiptVaultProvider =
    Provider<ReceiptVault>(
      (Ref ref) => EncryptedReceiptVault(
        baseDir: getApplicationDocumentsDirectory,
      ),
    );

/// Statement import orchestration (PDF + CSV review screen).
final Provider<StatementImportService> statementImportServiceProvider =
    Provider<StatementImportService>(
      (Ref ref) => StatementImportService(txnDao: ref.watch(txnDaoProvider)),
    );
