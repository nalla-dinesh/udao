// phase-04
// What receipt parsing produces — OCR text in, one editable draft
// out. Receipts are ALWAYS human-confirmed before the ledger write
// (spec), so these fields are prefill candidates, not facts.
import 'package:udao/core/utils/money.dart';

class ParsedReceipt {
  const ParsedReceipt({
    required this.rawText,
    required this.confidence,
    this.merchant,
    this.total,
    this.date,
    this.items = const <ReceiptLineItem>[],
  });

  /// Verbatim OCR text (never persisted outside the vault flow).
  final String rawText;

  /// Rules-parser self-assessed confidence 0.0–1.0 (see
  /// ReceiptRulesParser for the scoring rubric).
  final double confidence;

  final String? merchant;

  /// Grand total in paise, when found.
  final Money? total;

  /// Receipt date, when found (date-only, IST noon — same convention
  /// as statements).
  final DateTime? date;

  /// First plausible line items (order preserved, top-3).
  final List<ReceiptLineItem> items;
}

class ReceiptLineItem {
  const ReceiptLineItem(this.label, this.amount);

  final String label;
  final Money? amount;
}
