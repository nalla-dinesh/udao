// phase-04
// Statement import orchestration: file → parse → preview (dedup
// classified, NOTHING written) → user confirms → ONE atomic batch.
//
// Dedup legs, in order: in-set (same statement twice), refNo exact,
// fingerprint exact, fuzzy window (same amount ± merchant on the
// same calendar day — statements are date-granular, so the window is
// ±12h around the row's noon-IST timestamp).
//
// The PDF password crosses this service as a CALL ARGUMENT only: it
// is forwarded to the extractor and never stored on the service, the
// preview, or any model. The screen zeroes its controller when the
// flow ends (success, cancel, or failure).
import 'dart:io';

import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/date_utils.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/parsers/dedup_engine.dart';
import 'package:udao/data/parsers/merchant_cleaner.dart';
import 'package:udao/features/capture/pipeline/categorizer.dart';
import 'package:udao/features/capture/ports/pdf_text_extractor.dart';

import 'csv_statement_parser.dart';
import 'statement_parser.dart';
import 'statement_row.dart';

enum ImportFormat { pdf, csv }

enum DupReason { inSet, refNo, fingerprint, fuzzy }

/// One preview line: the built txn plus its dedup verdict.
class ImportPreviewRow {
  const ImportPreviewRow({required this.txn, this.dupReason});

  final Txn txn;
  final DupReason? dupReason;

  bool get isDuplicate => dupReason != null;
}

/// Nothing-written parse result for the review screen.
class ImportPreview {
  const ImportPreview({
    required this.format,
    required this.fileName,
    required this.bankId,
    required this.rows,
    required this.skipped,
  });

  final ImportFormat format;
  final String fileName;
  final String bankId;
  final List<ImportPreviewRow> rows;
  final List<SkippedLine> skipped;

  int get newCount =>
      rows.where((ImportPreviewRow r) => !r.isDuplicate).length;
  int get duplicateCount =>
      rows.where((ImportPreviewRow r) => r.isDuplicate).length;

  (DateTime?, DateTime)? get dateRange {
    if (rows.isEmpty) {
      return null;
    }
    final List<DateTime> dates =
        rows.map((ImportPreviewRow r) => r.txn.occurredAt).toList()..sort();
    return (dates.first, dates.last);
  }
}

/// Post-confirm outcome.
class ImportSummary {
  const ImportSummary({required this.inserted, required this.duplicates});

  final int inserted;
  final int duplicates;
}

class StatementImportService {
  StatementImportService({
    required TxnDao txnDao,
    DateTime Function()? now,
  })  : _txnDao = txnDao,
        _now = now ?? IstDates.nowIst;

  final TxnDao _txnDao;
  final DateTime Function() _now;

  /// Statement-import confidence: a bank-generated row is the most
  /// trustworthy source UDAO has (vs. 0.6–0.95 for captures).
  static const double _rowConfidence = 0.98;

  /// PDF leg. `pdf_password` errors propagate so the screen can
  /// re-prompt; every other failure is terminal for this file.
  Future<Result<ImportPreview>> previewPdf(
    String path,
    String fileName, {
    required PdfTextExtractor extractor,
    String? password,
  }) async {
    final Result<PdfExtract> extract =
        await extractor.extract(path, password: password);
    if (extract is Err<PdfExtract>) {
      return Err(extract.failure);
    }
    final Result<StatementParse> parse =
        StatementParser.parseText(extract.valueOrNull!.fullText);
    if (parse is Err<StatementParse>) {
      return Err(parse.failure);
    }
    return _toPreview(
      format: ImportFormat.pdf,
      fileName: fileName,
      parse: parse.valueOrNull!,
    );
  }

  /// CSV leg (UDAO export format).
  Future<Result<ImportPreview>> previewCsv(
    String path,
    String fileName,
  ) async {
    final String csv;
    try {
      csv = await File(path).readAsString();
    } on Object catch (e, s) {
      return Err(
        CaptureFailure('csv_read_failed', cause: e, stackTrace: s),
      );
    }
    final Result<StatementParse> parse = CsvStatementParser.parse(csv);
    if (parse is Err<StatementParse>) {
      return Err(parse.failure);
    }
    return _toPreview(
      format: ImportFormat.csv,
      fileName: fileName,
      parse: parse.valueOrNull!,
    );
  }

  /// Writes the preview's non-duplicate rows in ONE transaction. The
  /// preview object is the single source of truth — nothing is
  /// re-parsed here, so what the user confirmed is what lands.
  Future<Result<ImportSummary>> confirm(ImportPreview preview) async {
    final List<Txn> fresh = preview.rows
        .where((ImportPreviewRow r) => !r.isDuplicate)
        .map((ImportPreviewRow r) => r.txn)
        .toList(growable: false);
    if (fresh.isEmpty) {
      return Ok(
        ImportSummary(
          inserted: 0,
          duplicates: preview.duplicateCount,
        ),
      );
    }
    final Result<int> written = await _txnDao.insertAllAtomic(fresh);
    if (written is Err<int>) {
      return Err(written.failure);
    }
    return Ok(
      ImportSummary(
        inserted: written.valueOrNull ?? 0,
        duplicates: preview.duplicateCount +
            (fresh.length - (written.valueOrNull ?? 0)),
      ),
    );
  }

  // ---- preview build -----------------------------------------------

  Future<Result<ImportPreview>> _toPreview({
    required ImportFormat format,
    required String fileName,
    required StatementParse parse,
  }) async {
    final DateTime capturedAt = _now();
    // CSV (UDAO export) has no `csv` source in the enum by design —
    // re-importing an export lands as duplicates anyway, and a fresh
    // install's restore is a user-initiated act → `manual`.
    final TxnSource source =
        format == ImportFormat.pdf ? TxnSource.pdf : TxnSource.manual;

    final Set<String> seenKeys = <String>{};
    final List<ImportPreviewRow> out = <ImportPreviewRow>[];

    for (final StatementRow row in parse.rows) {
      final String merchantClean = _merchantFromNarration(row.narration);
      final String dedupKey = DedupEngine.fingerprint(
        refNo: row.refNo,
        amountPaise: row.amountPaise,
        counterparty: merchantClean,
        at: row.date,
      );

      DupReason? dup;
      if (!seenKeys.add(dedupKey)) {
        dup = DupReason.inSet;
      } else if (row.refNo != null) {
        final Result<bool> refHit = await _txnDao.refNoExists(row.refNo!);
        if (refHit.valueOrNull == true) {
          dup = DupReason.refNo;
        }
      }
      dup ??= await _fingerprintDup(dedupKey);
      dup ??= await _fuzzyDup(row, merchantClean);

      final Txn txn = Txn(
        id: TxnId.newId(),
        amount: Money(row.amountPaise),
        direction: row.direction,
        source: source,
        rawText: row.narration,
        merchantRaw: row.narration,
        merchantClean: merchantClean,
        bankOrApp: parse.bankId,
        categoryId: Categorizer.assign(merchantClean),
        refNo: row.refNo,
        occurredAt: row.date,
        capturedAt: capturedAt,
        confidence: _rowConfidence,
        dedupKey: dedupKey,
      );
      out.add(ImportPreviewRow(txn: txn, dupReason: dup));
    }

    return Ok(
      ImportPreview(
        format: format,
        fileName: fileName,
        bankId: parse.bankId,
        rows: out,
        skipped: parse.skipped,
      ),
    );
  }

  /// Bank narrations are slash/dash segmented (`UPI/<ref>/SWIGGY/YESB0PTX`,
  /// `NEFT CR-HDFC0000123-ACME CORP-SALARY`). The counterparty is the
  /// first wordy segment after the noise (channel, DR/CR, refs,
  /// IFSC/PSP codes, card numbers) — `MerchantCleaner.clean` alone has
  /// no notion of segments.
  static String _merchantFromNarration(String narration) {
    // Channel/connector words drop WORD-wise, so two-word segments
    // like `NEFT CR` vanish entirely and `ACME CORP` survives.
    final RegExp channelWord = RegExp(
      r'^(?:upi|neft|imps|mmi|p2a|p2m|dr|cr|to|by|chq|ref|no|pos|atm|wd|w)$',
      caseSensitive: false,
    );
    final RegExp ifscLike = RegExp(r'^[A-Z]{4}0[A-Z0-9]{3,}$');
    final RegExp digitsLike = RegExp(r'^[\dX*#.]+$');
    final RegExp keywordWord = RegExp(
      r'^(?:salary|refund|interest|cashback|debit|credit|purchase|'
      r'payment|transfer|received|paid)$',
      caseSensitive: false,
    );
    for (final String seg in narration.split(RegExp(r'[/-]'))) {
      final String kept = seg
          .trim()
          .split(RegExp(r'\s+'))
          .where(
            (String word) =>
                word.isNotEmpty &&
                !channelWord.hasMatch(word) &&
                !keywordWord.hasMatch(word) &&
                !digitsLike.hasMatch(word) &&
                !ifscLike.hasMatch(word),
          )
          .join(' ')
          .trim();
      if (kept.isEmpty) {
        continue;
      }
      final int letters = kept.replaceAll(RegExp(r'[^A-Za-z]'), '').length;
      if (letters < 3) {
        continue;
      }
      return MerchantCleaner.clean(kept);
    }
    return MerchantCleaner.clean(narration);
  }

  Future<DupReason?> _fingerprintDup(String dedupKey) async {
    final Result<Txn?> hit = await _txnDao.findByDedupKey(dedupKey);
    return hit.valueOrNull != null ? DupReason.fingerprint : null;
  }

  Future<DupReason?> _fuzzyDup(StatementRow row, String merchantClean) async {
    final Result<List<Txn>> near = await _txnDao.findNear(
      around: row.date,
      amountPaise: row.amountPaise,
      merchantClean: merchantClean == 'Unknown' ? null : merchantClean,
      window: const Duration(hours: 12),
    );
    return (near.valueOrNull ?? const <Txn>[]).isNotEmpty
        ? DupReason.fuzzy
        : null;
  }
}
