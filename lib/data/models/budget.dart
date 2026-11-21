// phase-02
// A spending cap. Applies to a category (or the whole wallet when
// `categoryId` is null).
import 'package:udao/core/utils/money.dart';

enum BudgetPeriod { weekly, monthly }

extension BudgetPeriodName on BudgetPeriod {
  static BudgetPeriod? fromName(String? name) {
    for (final BudgetPeriod v in BudgetPeriod.values) {
      if (v.name == name) {
        return v;
      }
    }
    return null;
  }
}

class Budget {
  const Budget({
    required this.id,
    required this.limit,
    required this.period,
    required this.rollover,
    required this.active,
    this.categoryId,
  });

  final String id;
  final String? categoryId;
  final Money limit;
  final BudgetPeriod period;

  /// Unspent amount carries into the next period.
  final bool rollover;
  final bool active;

  Budget copyWith({
    String? id,
    String? categoryId,
    Money? limit,
    BudgetPeriod? period,
    bool? rollover,
    bool? active,
  }) {
    return Budget(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      limit: limit ?? this.limit,
      period: period ?? this.period,
      rollover: rollover ?? this.rollover,
      active: active ?? this.active,
    );
  }

  @override
  bool operator ==(Object other) => other is Budget && other.id == id;

  @override
  int get hashCode => id.hashCode;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'categoryId': categoryId,
        'limit': limit.toJson(),
        'period': period.name,
        'rollover': rollover,
        'active': active,
      };

  factory Budget.fromJson(Map<String, Object?> json) {
    return Budget(
      id: json['id']! as String,
      categoryId: json['categoryId'] as String?,
      limit: Money.fromJson(json['limit']! as Map<String, Object?>),
      period: BudgetPeriodName.fromName(json['period']! as String)!,
      rollover: json['rollover']! as bool,
      active: json['active']! as bool,
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'category_id': categoryId,
        'limit_paise': limit.paise,
        'period': period.name,
        'rollover': rollover ? 1 : 0,
        'active': active ? 1 : 0,
      };

  factory Budget.fromRow(Map<String, Object?> row) {
    return Budget(
      id: row['id']! as String,
      categoryId: row['category_id'] as String?,
      limit: Money(row['limit_paise']! as int),
      period: BudgetPeriodName.fromName(row['period']! as String)!,
      rollover: (row['rollover']! as int) == 1,
      active: (row['active']! as int) == 1,
    );
  }
}
