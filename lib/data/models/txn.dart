// phase-02
// A single money movement — the atom every UDAO feature reads from.
//
// Money is [Money] (paise ints, never doubles). Timestamps follow the
// IST convention (see `IstDates`) and are persisted as epoch-ms ints.
import 'dart:math';

import 'package:udao/core/utils/money.dart';

class Txn {
  const Txn({
    required this.id,
    required this.amount,
    required this.direction,
    required this.source,
    required this.rawText,
    required this.merchantRaw,
    required this.merchantClean,
    required this.bankOrApp,
    required this.occurredAt,
    required this.capturedAt,
    required this.confidence,
    required this.dedupKey,
    this.categoryId,
    this.refNo,
    this.vpa,
    this.note,
  });

  /// Sortable uuid-v7-style id (ms timestamp prefix, see [TxnId]).
  final String id;
  final Money amount;
  final TxnDirection direction;
  final TxnSource source;

  /// Verbatim capture text — user-editable in review flows.
  final String rawText;

  /// Counterparty exactly as extracted, before cleaning.
  final String merchantRaw;

  /// Normalised display name (see `MerchantCleaner`).
  final String merchantClean;

  /// Originating bank or UPI app tag (`hdfc`, `gpay`, …).
  final String bankOrApp;
  final String? categoryId;
  final String? refNo;
  final String? vpa;

  /// When the money moved (bank timestamp when known, else received).
  final DateTime occurredAt;
  final DateTime capturedAt;

  /// Parser confidence 0.0–1.0 (see `CONFIDENCE.md`).
  final double confidence;

  /// Dedup fingerprint (see `DedupEngine`).
  final String dedupKey;
  final String? note;

  Txn copyWith({
    String? id,
    Money? amount,
    TxnDirection? direction,
    TxnSource? source,
    String? rawText,
    String? merchantRaw,
    String? merchantClean,
    String? bankOrApp,
    String? categoryId,
    String? refNo,
    String? vpa,
    DateTime? occurredAt,
    DateTime? capturedAt,
    double? confidence,
    String? dedupKey,
    String? note,
  }) {
    return Txn(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      direction: direction ?? this.direction,
      source: source ?? this.source,
      rawText: rawText ?? this.rawText,
      merchantRaw: merchantRaw ?? this.merchantRaw,
      merchantClean: merchantClean ?? this.merchantClean,
      bankOrApp: bankOrApp ?? this.bankOrApp,
      categoryId: categoryId ?? this.categoryId,
      refNo: refNo ?? this.refNo,
      vpa: vpa ?? this.vpa,
      occurredAt: occurredAt ?? this.occurredAt,
      capturedAt: capturedAt ?? this.capturedAt,
      confidence: confidence ?? this.confidence,
      dedupKey: dedupKey ?? this.dedupKey,
      note: note ?? this.note,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Txn && other.id == id && other.dedupKey == dedupKey;

  @override
  int get hashCode => Object.hash(id, dedupKey);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'amount': amount.toJson(),
        'direction': direction.name,
        'source': source.name,
        'rawText': rawText,
        'merchantRaw': merchantRaw,
        'merchantClean': merchantClean,
        'bankOrApp': bankOrApp,
        'categoryId': categoryId,
        'refNo': refNo,
        'vpa': vpa,
        'occurredAtMs': occurredAt.millisecondsSinceEpoch,
        'capturedAtMs': capturedAt.millisecondsSinceEpoch,
        'confidence': confidence,
        'dedupKey': dedupKey,
        'note': note,
      };

  factory Txn.fromJson(Map<String, Object?> json) {
    return Txn(
      id: json['id']! as String,
      amount: Money.fromJson(json['amount']! as Map<String, Object?>),
      direction: TxnDirectionName.fromName(json['direction']! as String)!,
      source: TxnSourceName.fromName(json['source']! as String)!,
      rawText: json['rawText']! as String,
      merchantRaw: json['merchantRaw']! as String,
      merchantClean: json['merchantClean']! as String,
      bankOrApp: json['bankOrApp']! as String,
      categoryId: json['categoryId'] as String?,
      refNo: json['refNo'] as String?,
      vpa: json['vpa'] as String?,
      occurredAt:
          DateTime.fromMillisecondsSinceEpoch(json['occurredAtMs']! as int),
      capturedAt:
          DateTime.fromMillisecondsSinceEpoch(json['capturedAtMs']! as int),
      confidence: (json['confidence']! as num).toDouble(),
      dedupKey: json['dedupKey']! as String,
      note: json['note'] as String?,
    );
  }

  /// DB row (`txn` table). Money and timestamps as raw ints.
  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'amount': amount.paise,
        'direction': direction.name,
        'source': source.name,
        'raw_text': rawText,
        'merchant_raw': merchantRaw,
        'merchant_clean': merchantClean,
        'bank_or_app': bankOrApp,
        'category_id': categoryId,
        'ref_no': refNo,
        'vpa': vpa,
        'occurred_at': occurredAt.millisecondsSinceEpoch,
        'captured_at': capturedAt.millisecondsSinceEpoch,
        'confidence': confidence,
        'dedup_key': dedupKey,
        'note': note,
      };

  factory Txn.fromRow(Map<String, Object?> row) {
    return Txn(
      id: row['id']! as String,
      amount: Money(row['amount']! as int),
      direction: TxnDirectionName.fromName(row['direction']! as String)!,
      source: TxnSourceName.fromName(row['source']! as String)!,
      rawText: row['raw_text']! as String,
      merchantRaw: row['merchant_raw']! as String,
      merchantClean: row['merchant_clean']! as String,
      bankOrApp: row['bank_or_app']! as String,
      categoryId: row['category_id'] as String?,
      refNo: row['ref_no'] as String?,
      vpa: row['vpa'] as String?,
      occurredAt:
          DateTime.fromMillisecondsSinceEpoch(row['occurred_at']! as int),
      capturedAt:
          DateTime.fromMillisecondsSinceEpoch(row['captured_at']! as int),
      confidence: (row['confidence']! as num).toDouble(),
      dedupKey: row['dedup_key']! as String,
      note: row['note'] as String?,
    );
  }
}

/// Money left the wallet (a spend).
enum TxnDirection { debit, credit }

extension TxnDirectionName on TxnDirection {
  static TxnDirection? fromName(String? name) {
    for (final TxnDirection v in TxnDirection.values) {
      if (v.name == name) {
        return v;
      }
    }
    return null;
  }
}

/// How the movement was captured.
enum TxnSource { notification, sms, pdf, receipt, voice, manual }

extension TxnSourceName on TxnSource {
  static TxnSource? fromName(String? name) {
    for (final TxnSource v in TxnSource.values) {
      if (v.name == name) {
        return v;
      }
    }
    return null;
  }
}

/// Sortable, collision-safe txn id: 12-hex ms timestamp prefix + 14
/// random hex chars (uuid-v7 style, hand-rolled — no dependency on
/// package internals).
abstract final class TxnId {
  static final Random _random = Random.secure();

  /// New id for "now" ([atMillis] overridable for tests).
  static String newId({int? atMillis}) {
    final int ms =
        atMillis ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    final int rand = _random.nextInt(1 << 31) ^ (_random.nextInt(1 << 31) << 8);
    return '${ms.toRadixString(16).padLeft(12, '0')}'
        '${(rand & 0x3FFFFFFFFF).toRadixString(16).padLeft(10, '0')}'
        '${_random.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0')}';
  }
}
