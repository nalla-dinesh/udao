// phase-02
// A low-confidence capture parked for user review (confidence band
// 0.6–0.9, see `CONFIDENCE.md`). Phase 07 renders the UI; the repo
// contract lands here.
import 'package:udao/core/utils/money.dart';

import 'txn.dart';

class PendingReviewEntry {
  const PendingReviewEntry({
    required this.id,
    required this.source,
    required this.receivedAt,
    required this.rawText,
    required this.confidence,
    this.amount,
    this.direction,
    this.merchantRaw,
    this.merchantClean,
    this.bankOrApp,
    this.refNo,
    this.vpa,
    this.parserId,
    this.dedupKey,
    this.resolved = false,
    this.resolution,
    this.resolvedAt,
  });

  final String id;
  final String source;
  final DateTime receivedAt;
  final String rawText;
  final double confidence;
  final Money? amount;
  final TxnDirection? direction;
  final String? merchantRaw;
  final String? merchantClean;
  final String? bankOrApp;
  final String? refNo;
  final String? vpa;
  final String? parserId;
  final String? dedupKey;

  /// Review outcome: `approved` | `dismissed`; null = still pending.
  final bool resolved;
  final String? resolution;
  final DateTime? resolvedAt;

  @override
  bool operator ==(Object other) =>
      other is PendingReviewEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'source': source,
        'received_at': receivedAt.millisecondsSinceEpoch,
        'raw_text': rawText,
        'amount': amount?.paise,
        'direction': direction?.name,
        'merchant_raw': merchantRaw,
        'merchant_clean': merchantClean,
        'bank_or_app': bankOrApp,
        'ref_no': refNo,
        'vpa': vpa,
        'confidence': confidence,
        'parser_id': parserId,
        'dedup_key': dedupKey,
        'resolved': resolved ? 1 : 0,
        'resolution': resolution,
        'resolved_at': resolvedAt?.millisecondsSinceEpoch,
      };

  factory PendingReviewEntry.fromRow(Map<String, Object?> row) {
    return PendingReviewEntry(
      id: row['id']! as String,
      source: row['source']! as String,
      receivedAt:
          DateTime.fromMillisecondsSinceEpoch(row['received_at']! as int),
      rawText: row['raw_text']! as String,
      amount: row['amount'] == null ? null : Money(row['amount']! as int),
      direction:
          TxnDirectionName.fromName(row['direction'] as String?),
      merchantRaw: row['merchant_raw'] as String?,
      merchantClean: row['merchant_clean'] as String?,
      bankOrApp: row['bank_or_app'] as String?,
      refNo: row['ref_no'] as String?,
      vpa: row['vpa'] as String?,
      confidence: (row['confidence']! as num).toDouble(),
      parserId: row['parser_id'] as String?,
      dedupKey: row['dedup_key'] as String?,
      resolved: (row['resolved']! as int) == 1,
      resolution: row['resolution'] as String?,
      resolvedAt: row['resolved_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              row['resolved_at']! as int,
            ),
    );
  }
}
