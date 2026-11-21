// phase-02
// A recurring charge detected from repeat txns (no bank mandate API —
// UDAO infers cadence from observed history).
import 'package:udao/core/utils/money.dart';

enum SubscriptionStatus { active, suspected, dead }

extension SubscriptionStatusName on SubscriptionStatus {
  static SubscriptionStatus? fromName(String? name) {
    for (final SubscriptionStatus v in SubscriptionStatus.values) {
      if (v.name == name) {
        return v;
      }
    }
    return null;
  }
}

class Subscription {
  const Subscription({
    required this.id,
    required this.merchantClean,
    required this.amount,
    required this.cadenceDays,
    required this.lastSeen,
    required this.status,
    this.mandateRef,
  });

  final String id;
  final String merchantClean;
  final Money amount;

  /// Observed gap between charges, in days.
  final int cadenceDays;

  /// IST timestamp of the most recent matching txn.
  final DateTime lastSeen;
  final SubscriptionStatus status;
  final String? mandateRef;

  Subscription copyWith({
    String? id,
    String? merchantClean,
    Money? amount,
    int? cadenceDays,
    DateTime? lastSeen,
    SubscriptionStatus? status,
    String? mandateRef,
  }) {
    return Subscription(
      id: id ?? this.id,
      merchantClean: merchantClean ?? this.merchantClean,
      amount: amount ?? this.amount,
      cadenceDays: cadenceDays ?? this.cadenceDays,
      lastSeen: lastSeen ?? this.lastSeen,
      status: status ?? this.status,
      mandateRef: mandateRef ?? this.mandateRef,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Subscription && other.id == id;

  @override
  int get hashCode => id.hashCode;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'merchantClean': merchantClean,
        'amount': amount.toJson(),
        'cadenceDays': cadenceDays,
        'lastSeenMs': lastSeen.millisecondsSinceEpoch,
        'status': status.name,
        'mandateRef': mandateRef,
      };

  factory Subscription.fromJson(Map<String, Object?> json) {
    return Subscription(
      id: json['id']! as String,
      merchantClean: json['merchantClean']! as String,
      amount: Money.fromJson(json['amount']! as Map<String, Object?>),
      cadenceDays: json['cadenceDays']! as int,
      lastSeen:
          DateTime.fromMillisecondsSinceEpoch(json['lastSeenMs']! as int),
      status: SubscriptionStatusName.fromName(json['status']! as String)!,
      mandateRef: json['mandateRef'] as String?,
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'merchant_clean': merchantClean,
        'amount_paise': amount.paise,
        'cadence_days': cadenceDays,
        'last_seen': lastSeen.millisecondsSinceEpoch,
        'status': status.name,
        'mandate_ref': mandateRef,
      };

  factory Subscription.fromRow(Map<String, Object?> row) {
    return Subscription(
      id: row['id']! as String,
      merchantClean: row['merchant_clean']! as String,
      amount: Money(row['amount_paise']! as int),
      cadenceDays: row['cadence_days']! as int,
      lastSeen:
          DateTime.fromMillisecondsSinceEpoch(row['last_seen']! as int),
      status: SubscriptionStatusName.fromName(row['status']! as String)!,
      mandateRef: row['mandate_ref'] as String?,
    );
  }
}
